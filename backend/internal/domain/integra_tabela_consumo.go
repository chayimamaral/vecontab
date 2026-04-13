package domain

type IntegraTabelaConsumoFaixa struct {
	ID            string  `json:"id"`
	Tipo          string  `json:"tipo"`
	Faixa         int     `json:"faixa"`
	QuantidadeDe  int     `json:"quantidade_de"`
	QuantidadeAte *int    `json:"quantidade_ate,omitempty"`
	Preco         float64 `json:"preco"`
	Ativo         bool    `json:"ativo"`
}

type IntegraContadorGasto struct {
	ID               string  `json:"id"`
	TenantID         string  `json:"tenant_id"`
	EmpresaDocumento string  `json:"empresa_documento"`
	Tipo             string  `json:"tipo"`
	IDSistema        string  `json:"id_sistema"`
	IDServico        string  `json:"id_servico"`
	Quantidade       int     `json:"quantidade"`
	ConsumoMes       int     `json:"consumo_mes"`
	FaixaAplicada    int     `json:"faixa_aplicada"`
	PrecoUnitario    float64 `json:"preco_unitario"`
	ValorTotal       float64 `json:"valor_total"`
	ProcessadoEm     string  `json:"processado_em"`
}
