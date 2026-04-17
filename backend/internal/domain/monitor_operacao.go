package domain

import "time"

const (
	MonitorOperacaoOrigemManual                 = "MANUAL"
	MonitorOperacaoOrigemAutomatico             = "AUTOMATICO"
	MonitorOperacaoStatusSucesso                = "SUCESSO"
	MonitorOperacaoStatusErro                   = "ERRO"
	MonitorOperacaoTipoGeracaoCompromissos      = "GERACAO_COMPROMISSOS"
	MonitorOperacaoTipoGeracaoAgenda            = "GERACAO_AGENDA"
	MonitorOperacaoTipoWorkerCompromissosMensal = "WORKER_COMPROMISSOS_MENSAL"

	// MonitorOperacaoTenantPlataformaID agrupa operações automáticas de escopo global (ex.: worker mensal).
	// ADMIN filtra por tenant do JWT e não enxerga estes registros; SUPER lista todos os tenants, inclusive este.
	MonitorOperacaoTenantPlataformaID = "00000000-0000-4000-8000-000000000001"
)

type MonitorOperacaoItem struct {
	ID         string         `json:"id"`
	TenantID   string         `json:"tenant_id"`
	TenantNome *string        `json:"tenant_nome,omitempty"`
	ClienteNome *string       `json:"cliente_nome,omitempty"`
	UserID     *string        `json:"user_id,omitempty"`
	Origem     string         `json:"origem"`
	Tipo       string         `json:"tipo"`
	Status     string         `json:"status"`
	Mensagem   *string        `json:"mensagem,omitempty"`
	Detalhe    map[string]any `json:"detalhe,omitempty"`
	CriadoEm   time.Time      `json:"criado_em"`
	Compromissos []MonitorOperacaoCompromissoItem `json:"compromissos,omitempty"`
}

type MonitorOperacaoCompromissoItem struct {
	CompromissoID string   `json:"compromisso_id"`
	EmpresaID     string   `json:"empresa_id"`
	ClienteNome   *string  `json:"cliente_nome,omitempty"`
	Descricao     string   `json:"descricao"`
	Competencia   string   `json:"competencia"`
	Vencimento    string   `json:"vencimento"`
	Status        string   `json:"status"`
	Valor         *float64 `json:"valor,omitempty"`
}
