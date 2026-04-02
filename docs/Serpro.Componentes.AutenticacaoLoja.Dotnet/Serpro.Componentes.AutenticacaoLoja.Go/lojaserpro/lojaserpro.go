// Package lojaserpro espelha o componente C# Serpro.Componentes.AutenticacaoLoja.LojaSerpro:
// autenticação na Loja Serpro com consumer key/secret, certificado e-CNPJ (PFX) e mTLS.
package lojaserpro

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"golang.org/x/crypto/pkcs12"
)

// EndpointPlaceholder é o mesmo placeholder do fonte C#; substitua pela URL base informada na documentação do produto.
const EndpointPlaceholder = "endereco_endpoint_de_autenticacao"

// TokensLojaSerpro corresponde ao record TokensLojaSerpro do C# (nomes JSON em snake_case).
type TokensLojaSerpro struct {
	ExpiresIn   int    `json:"expires_in"`
	Scope       string `json:"scope"`
	TokenType   string `json:"token_type"`
	AccessToken string `json:"access_token"`
	JwtToken    string `json:"jwt_token"`
}

// ClientHTTP opcional para testes; se nil, usa cliente padrão com TLS configurado.
type ClientHTTP interface {
	Do(req *http.Request) (*http.Response, error)
}

// GerarTokensTemporarios obtém tokens como GerarTokensTemporariosAsync no C#.
// baseURL deve ser a URL base do endpoint de autenticação (ex.: https://.../); o caminho "authenticate" é acrescentado.
// certificadoPath é o caminho do arquivo .pfx no disco (análogo ao parâmetro certificado string no C#).
//
// Atenção: como no exemplo C#, a validação do certificado do servidor é ignorada (InsecureSkipVerify).
// Em produção, avalie remover isso e usar CAs confiáveis.
func GerarTokensTemporarios(ctx context.Context, baseURL, consumerKey, consumerSecret, certificadoPath, senhaCertificado string) (*TokensLojaSerpro, error) {
	return GerarTokensTemporariosWithClient(ctx, nil, baseURL, consumerKey, consumerSecret, certificadoPath, senhaCertificado)
}

// GerarTokensTemporariosWithClient permite injetar um http.Client (útil em testes com httptest).
// Nesse caso, certificadoPath e senhaCertificado são ignorados — o cliente deve já transportar mTLS se necessário.
func GerarTokensTemporariosWithClient(ctx context.Context, client ClientHTTP, baseURL, consumerKey, consumerSecret, certificadoPath, senhaCertificado string) (*TokensLojaSerpro, error) {
	baseURL = strings.TrimSpace(baseURL)
	if baseURL == "" || baseURL == EndpointPlaceholder {
		return nil, fmt.Errorf("baseURL inválida: defina a URL do endpoint conforme documentação do produto (não use o placeholder)")
	}

	aut := base64.StdEncoding.EncodeToString([]byte(consumerKey + ":" + consumerSecret))

	// Espelha o C#: POST relativo a "authenticate", Basic auth, Role-Type, corpo grant_type=client_credentials.
	// O C# envia Content-Type application/json com corpo em formato form — mantemos o mesmo para compatibilidade com o exemplo oficial.
	const body = "grant_type=client_credentials"
	url := strings.TrimRight(baseURL, "/") + "/authenticate"

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader([]byte(body)))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Basic "+aut)
	req.Header.Set("Role-Type", "TERCEIROS")
	req.Header.Set("Content-Type", "application/json")

	var hc ClientHTTP = client
	if hc == nil {
		pfxData, err := os.ReadFile(certificadoPath)
		if err != nil {
			return nil, fmt.Errorf("ler certificado PFX: %w", err)
		}
		priv, cert, err := pkcs12.Decode(pfxData, senhaCertificado)
		if err != nil {
			return nil, fmt.Errorf("decodificar PFX: %w", err)
		}
		tlsCert := tls.Certificate{
			Certificate: [][]byte{cert.Raw},
			PrivateKey:  priv,
			Leaf:        cert,
		}
		tr := &http.Transport{
			TLSClientConfig: &tls.Config{
				Certificates:       []tls.Certificate{tlsCert},
				MinVersion:         tls.VersionTLS12,
				InsecureSkipVerify: true, // igual ao exemplo C# (callback retorna true)
			},
		}
		hc = &http.Client{Transport: tr, Timeout: 60 * time.Second}
	}

	resp, err := hc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("requisição authenticate: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("authenticate: status %s: %s", resp.Status, strings.TrimSpace(string(respBody)))
	}

	var out TokensLojaSerpro
	if err := json.Unmarshal(respBody, &out); err != nil {
		return nil, fmt.Errorf("decodificar JSON: %w", err)
	}
	return &out, nil
}
