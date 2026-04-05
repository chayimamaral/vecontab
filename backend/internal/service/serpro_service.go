package service

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/chayimamaral/vecontab/backend/internal/config"
)

// SerproService esboço para Integra Contador / Sicalc–DARF (issue #55).
// Referências: quick start e autenticação em
// https://apicenter.estaleiro.serpro.gov.br/documentacao/api-integra-contador/pt/quick_start/
// Ajuste grant_type, escopos e URLs conforme o contrato vigente na loja SERPRO.
type SerproService struct {
	cfg     config.Config
	certSvc *CertificadoService

	mu          sync.Mutex
	cachedToken string
	cachedExp   time.Time
}

func NewSerproService(cfg config.Config, certSvc *CertificadoService) *SerproService {
	return &SerproService{cfg: cfg, certSvc: certSvc}
}

type oauthTokenResponse struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
	ExpiresIn   int    `json:"expires_in"`
}

// ObterBearerToken obtém access_token com credenciais de desenvolvedor (OAuth2).
// Implementação base: grant_type=client_credentials; valide na documentação oficial se houver escopos adicionais.
func (s *SerproService) ObterBearerToken(ctx context.Context) (string, error) {
	if strings.TrimSpace(s.cfg.SerproOAuthTokenURL) == "" {
		return "", fmt.Errorf("SERPRO_OAUTH_TOKEN_URL nao configurada")
	}
	if strings.TrimSpace(s.cfg.SerproClientID) == "" || strings.TrimSpace(s.cfg.SerproClientSecret) == "" {
		return "", fmt.Errorf("SERPRO_CLIENT_ID / SERPRO_CLIENT_SECRET obrigatorios")
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if s.cachedToken != "" && time.Now().Before(s.cachedExp.Add(-2*time.Minute)) {
		return s.cachedToken, nil
	}

	form := url.Values{}
	form.Set("grant_type", "client_credentials")
	form.Set("client_id", strings.TrimSpace(s.cfg.SerproClientID))
	form.Set("client_secret", strings.TrimSpace(s.cfg.SerproClientSecret))

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimSpace(s.cfg.SerproOAuthTokenURL), strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("token oauth: %w", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("token oauth status %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	var tr oauthTokenResponse
	if err := json.Unmarshal(body, &tr); err != nil {
		return "", fmt.Errorf("token oauth json: %w", err)
	}
	if strings.TrimSpace(tr.AccessToken) == "" {
		return "", fmt.Errorf("access_token vazio na resposta")
	}
	exp := time.Now().Add(time.Duration(tr.ExpiresIn) * time.Second)
	if tr.ExpiresIn <= 0 {
		exp = time.Now().Add(50 * time.Minute)
	}
	s.cachedToken = tr.AccessToken
	s.cachedExp = exp
	return tr.AccessToken, nil
}

// bearerTransport injeta Authorization em cada requisição.
type bearerTransport struct {
	token string
	inner http.RoundTripper
}

func (b *bearerTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	r := req.Clone(req.Context())
	r.Header.Set("Authorization", "Bearer "+b.token)
	return b.inner.RoundTrip(r)
}

// ClienteHTTPParaDemostracao monta *http.Client com:
//   - Bearer do desenvolvedor (OAuth2);
//   - mTLS com certificado A1 do cliente (empresa) decifrado em memória.
//
// cleanup() deve ser chamado ao fim do fluxo para zerar buffers e fechar idle connections.
// O path/método exatos da API de demonstração DARF dependem da versão publicada no API Center SERPRO.
func (s *SerproService) ClienteHTTPParaDemostracao(ctx context.Context, tenantID, empresaID string) (*http.Client, func(), error) {
	if s.certSvc == nil || !s.certSvc.Configurado() {
		return nil, nil, fmt.Errorf("certificado cliente: servico nao configurado")
	}
	if strings.TrimSpace(s.cfg.SerproAPIBaseURL) == "" {
		return nil, nil, fmt.Errorf("SERPRO_API_BASE_URL nao configurada")
	}

	tok, err := s.ObterBearerToken(ctx)
	if err != nil {
		return nil, nil, err
	}

	tcert, certCleanup, err := s.certSvc.TLSClientCertificate(ctx, tenantID, empresaID)
	if err != nil {
		return nil, nil, fmt.Errorf("tls cliente: %w", err)
	}

	tr := &http.Transport{
		TLSClientConfig: &tls.Config{
			MinVersion:   tls.VersionTLS12,
			Certificates: []tls.Certificate{tcert},
		},
	}
	chain := &bearerTransport{token: tok, inner: tr}
	cli := &http.Client{
		Transport: chain,
		Timeout:   90 * time.Second,
	}

	cleanup := func() {
		certCleanup()
		tr.CloseIdleConnections()
	}
	return cli, cleanup, nil
}

// PrepararRequisicaoGET esboço: GET autenticado contra SERPRO_API_BASE_URL + pathRelativo.
func (s *SerproService) PrepararRequisicaoGET(ctx context.Context, tenantID, empresaID, pathRelativo string) (*http.Request, *http.Client, func(), error) {
	cli, cleanup, err := s.ClienteHTTPParaDemostracao(ctx, tenantID, empresaID)
	if err != nil {
		return nil, nil, nil, err
	}
	base := strings.TrimSuffix(strings.TrimSpace(s.cfg.SerproAPIBaseURL), "/")
	path := strings.TrimPrefix(pathRelativo, "/")
	u := base + "/" + path
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		cleanup()
		return nil, nil, nil, err
	}
	return req, cli, cleanup, nil
}
