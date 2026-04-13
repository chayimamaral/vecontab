package domain

import "encoding/json"

// RegimeTributario cadastro de CRT (SPED) e metadados em JSON.
type RegimeTributario struct {
	ID                 string          `json:"id"`
	Nome               string          `json:"nome"`
	CodigoCRT          int             `json:"codigo_crt"`
	TipoApuracao       string          `json:"tipo_apuracao"`
	Ativo              bool            `json:"ativo"`
	ConfiguracaoJSON   json.RawMessage `json:"configuracao_json"`
}
