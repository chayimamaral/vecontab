package service

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/chayimamaral/vecontab/backend/internal/repository"
)

type IntegraContadorAmbiente string

const (
	IntegraAmbienteTrial    IntegraContadorAmbiente = "trial"
	IntegraAmbienteProducao IntegraContadorAmbiente = "producao"
)

type IntegraIdentificacao struct {
	Numero string `json:"numero"`
	Tipo   int    `json:"tipo"`
}

type IntegraPedidoDados struct {
	IDSistema     string `json:"idSistema"`
	IDServico     string `json:"idServico"`
	VersaoSistema string `json:"versaoSistema"`
	Dados         string `json:"dados"`
}

type IntegraDadosEntrada struct {
	Contratante  IntegraIdentificacao `json:"contratante"`
	AutorPedido  IntegraIdentificacao `json:"autorPedidoDados"`
	Contribuinte IntegraIdentificacao `json:"contribuinte"`
	PedidoDados  IntegraPedidoDados   `json:"pedidoDados"`
}

type IntegraCallInput struct {
	TenantID                  string
	Ambiente                  IntegraContadorAmbiente
	Operacao                  string
	Payload                   IntegraDadosEntrada
	AccessToken               string
	JWTToken                  string
	AutenticarProcuradorToken string
}

type IntegraCallOutput struct {
	StatusCode int               `json:"status_code"`
	Headers    map[string]string `json:"headers"`
	RawBody    string            `json:"raw_body"`
}

type IntegraAuthOutput struct {
	AccessToken string `json:"access_token"`
	JWTToken    string `json:"jwt_token"`
	TokenType   string `json:"token_type"`
	ExpiresIn   int    `json:"expires_in"`
}

type IntegraContadorService struct {
	certSvc    *CertificadoService
	configRepo *repository.ConfiguracaoIntegracaoRepository
	procRepo   *repository.IntegraContadorServicoProcuracaoRepository
	httpClient *http.Client
}

func NewIntegraContadorService(
	certSvc *CertificadoService,
	configRepo *repository.ConfiguracaoIntegracaoRepository,
	procRepo *repository.IntegraContadorServicoProcuracaoRepository,
) *IntegraContadorService {
	return &IntegraContadorService{
		certSvc:    certSvc,
		configRepo: configRepo,
		procRepo:   procRepo,
		httpClient: &http.Client{Timeout: 120 * time.Second},
	}
}

func (s *IntegraContadorService) Authenticate(ctx context.Context, tenantID string) (IntegraAuthOutput, error) {
	if strings.TrimSpace(tenantID) == "" {
		return IntegraAuthOutput{}, fmt.Errorf("tenant obrigatorio")
	}
	if s.configRepo == nil {
		return IntegraAuthOutput{}, fmt.Errorf("repositorio de configuracao nao disponivel")
	}
	if s.certSvc == nil || !s.certSvc.Configurado() {
		return IntegraAuthOutput{}, fmt.Errorf("certificado digital nao configurado")
	}

	chaves, err := s.configRepo.GetChavesIntegraTenantPlataforma(ctx)
	if err != nil {
		return IntegraAuthOutput{}, fmt.Errorf("falha ao obter chaves Integra Contador: %w", err)
	}
	consumerKey := strings.TrimSpace(chaves.ConsumerKey)
	consumerSecret := strings.TrimSpace(chaves.ConsumerSecret)
	if consumerKey == "" || consumerSecret == "" {
		return IntegraAuthOutput{}, fmt.Errorf("consumer key/secret nao cadastrados para o tenant da VEC Sistemas (SUPER > Integra Contador - Serpro)")
	}

	tlsCert, cleanup, err := s.certSvc.TLSClientCertificate(ctx, tenantID, "")
	if err != nil {
		return IntegraAuthOutput{}, fmt.Errorf("falha ao carregar certificado A1: %w", err)
	}
	defer cleanup()

	tr := &http.Transport{
		TLSClientConfig: &tls.Config{
			MinVersion:   tls.VersionTLS12,
			Certificates: []tls.Certificate{tlsCert},
		},
	}
	defer tr.CloseIdleConnections()
	client := &http.Client{
		Transport: tr,
		Timeout:   120 * time.Second,
	}

	authURL := "https://autenticacao.sapi.serpro.gov.br/authenticate"
	form := "grant_type=client_credentials"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, authURL, strings.NewReader(form))
	if err != nil {
		return IntegraAuthOutput{}, err
	}
	basic := base64.StdEncoding.EncodeToString([]byte(consumerKey + ":" + consumerSecret))
	req.Header.Set("Authorization", "Basic "+basic)
	req.Header.Set("Role-Type", "TERCEIROS")
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return IntegraAuthOutput{}, fmt.Errorf("falha na autenticacao SAPI: %w", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return IntegraAuthOutput{}, fmt.Errorf("autenticacao SAPI status %d: %s", resp.StatusCode, strings.TrimSpace(string(raw)))
	}

	var out IntegraAuthOutput
	if err := json.Unmarshal(raw, &out); err != nil {
		return IntegraAuthOutput{}, fmt.Errorf("resposta de autenticacao invalida: %w", err)
	}
	if strings.TrimSpace(out.AccessToken) == "" {
		return IntegraAuthOutput{}, fmt.Errorf("access_token vazio na resposta de autenticacao")
	}
	return out, nil
}

func (s *IntegraContadorService) Call(ctx context.Context, in IntegraCallInput) (IntegraCallOutput, error) {
	if strings.TrimSpace(in.TenantID) == "" {
		return IntegraCallOutput{}, fmt.Errorf("tenant obrigatorio")
	}
	op := strings.ToLower(strings.TrimSpace(in.Operacao))
	if op != "apoiar" && op != "consultar" && op != "declarar" && op != "emitir" && op != "monitorar" {
		return IntegraCallOutput{}, fmt.Errorf("operacao invalida: use Apoiar, Consultar, Declarar, Emitir ou Monitorar")
	}
	if strings.TrimSpace(in.Payload.Contratante.Numero) == "" || strings.TrimSpace(in.Payload.AutorPedido.Numero) == "" || strings.TrimSpace(in.Payload.Contribuinte.Numero) == "" {
		return IntegraCallOutput{}, fmt.Errorf("contratante, autorPedidoDados e contribuinte sao obrigatorios")
	}
	if strings.TrimSpace(in.Payload.PedidoDados.IDSistema) == "" || strings.TrimSpace(in.Payload.PedidoDados.IDServico) == "" || strings.TrimSpace(in.Payload.PedidoDados.VersaoSistema) == "" || strings.TrimSpace(in.Payload.PedidoDados.Dados) == "" {
		return IntegraCallOutput{}, fmt.Errorf("pedidoDados.idSistema, idServico, versaoSistema e dados sao obrigatorios")
	}
	if s.procRepo != nil {
		rows, err := s.procRepo.List(ctx, in.Payload.PedidoDados.IDSistema, in.Payload.PedidoDados.IDServico)
		if err != nil {
			return IntegraCallOutput{}, fmt.Errorf("falha ao validar regras de procuracao: %w", err)
		}
		if len(rows) > 0 {
			codProc := strings.TrimSpace(rows[0].CodProcuracao)
			exigeProc := exigeProcuracao(codProc)
			autor := strings.TrimSpace(in.Payload.AutorPedido.Numero)
			contri := strings.TrimSpace(in.Payload.Contribuinte.Numero)
			if exigeProc && autor != "" && contri != "" && autor != contri && strings.TrimSpace(in.AutenticarProcuradorToken) == "" {
				return IntegraCallOutput{}, fmt.Errorf("servico exige procuracao: informe autenticar_procurador_token quando autorPedidoDados for diferente de contribuinte")
			}
		}
	}

	access := strings.TrimSpace(in.AccessToken)
	jwtTok := strings.TrimSpace(in.JWTToken)
	if access == "" {
		authOut, err := s.Authenticate(ctx, in.TenantID)
		if err != nil {
			return IntegraCallOutput{}, err
		}
		access = strings.TrimSpace(authOut.AccessToken)
		if jwtTok == "" {
			jwtTok = strings.TrimSpace(authOut.JWTToken)
		}
	}

	base := "https://gateway.apiserpro.serpro.gov.br/integra-contador/v1"
	if strings.EqualFold(string(in.Ambiente), string(IntegraAmbienteTrial)) {
		base = "https://gateway.apiserpro.serpro.gov.br/integra-contador-trial/v1"
	}
	url := base + "/" + strings.ToUpper(op[:1]) + op[1:]

	bodyBytes, err := json.Marshal(in.Payload)
	if err != nil {
		return IntegraCallOutput{}, fmt.Errorf("falha ao serializar payload: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(bodyBytes))
	if err != nil {
		return IntegraCallOutput{}, err
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+access)
	if jwtTok != "" {
		req.Header.Set("jwt_token", jwtTok)
	}
	if strings.TrimSpace(in.AutenticarProcuradorToken) != "" {
		req.Header.Set("autenticar_procurador_token", strings.TrimSpace(in.AutenticarProcuradorToken))
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return IntegraCallOutput{}, fmt.Errorf("falha ao consumir Integra Contador: %w", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 8<<20))

	headers := map[string]string{}
	for k, values := range resp.Header {
		if len(values) > 0 {
			headers[k] = values[0]
		}
	}
	return IntegraCallOutput{
		StatusCode: resp.StatusCode,
		Headers:    headers,
		RawBody:    string(raw),
	}, nil
}

func exigeProcuracao(codProcuracao string) bool {
	raw := strings.ToLower(strings.TrimSpace(codProcuracao))
	if raw == "" || raw == "n/a" || raw == "na" || raw == "não se aplica" || raw == "aguardando definição" {
		return false
	}
	if strings.HasPrefix(raw, "sim") {
		return true
	}
	for _, ch := range raw {
		if ch < '0' || ch > '9' {
			return false
		}
	}
	return true
}
