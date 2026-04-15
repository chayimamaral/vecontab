package domain

// ObrigacaoRef referência geográfica ou tipo de empresa.
type ObrigacaoRef struct {
	ID   string `json:"id"`
	Nome string `json:"nome"`
}

// ObrigacaoListItem projeção do cadastro de obrigações legais (ex-compromissos financeiros).
type ObrigacaoListItem struct {
	ID                 string                    `json:"id"`
	TipoEmpresaID      string                    `json:"tipo_empresa_id"`
	TipoEmpresa        *ObrigacaoRef             `json:"tipoempresa,omitempty"`
	Descricao          string                    `json:"descricao"`
	Periodicidade      string                    `json:"periodicidade"`
	Abrangencia        string                    `json:"abrangencia"`
	DiaBase            int                       `json:"dia_base"`
	MesBase            string                    `json:"mes_base,omitempty"`
	TipoClassificacao  string                    `json:"tipo_classificacao,omitempty"`
	Valor              *float64                  `json:"valor,omitempty"`
	Observacao         string                    `json:"observacao,omitempty"`
	Estado             *ObrigacaoRef             `json:"estado,omitempty"`
	Municipio          *ObrigacaoRef             `json:"municipio,omitempty"`
	Bairro             string                    `json:"bairro,omitempty"`
	CatalogoServicoIDs []string                  `json:"catalogo_servico_ids,omitempty"`
	ServicosSerpro     []ObrigacaoServicoVinculo `json:"servicos_serpro,omitempty"`
}

type ObrigacaoServicoVinculo struct {
	CatalogoServicoID string `json:"catalogo_servico_id"`
	Operacao          string `json:"operacao"`
	Obrigatorio       bool   `json:"obrigatorio"`
	Ordem             int    `json:"ordem"`
	Codigo            string `json:"codigo,omitempty"`
	Descricao         string `json:"descricao,omitempty"`
	IDSistema         string `json:"id_sistema,omitempty"`
	IDServico         string `json:"id_servico,omitempty"`
}

// ObrigacaoMutationItem retorno de Create/Update/Delete.
type ObrigacaoMutationItem struct {
	ID                string   `json:"id"`
	TipoEmpresaID     string   `json:"tipo_empresa_id"`
	TipoClassificacao string   `json:"tipo_classificacao"`
	Descricao         string   `json:"descricao"`
	Periodicidade     string   `json:"periodicidade"`
	Abrangencia       string   `json:"abrangencia"`
	Valor             *float64 `json:"valor,omitempty"`
	Observacao        string   `json:"observacao,omitempty"`
	Ativo             bool     `json:"ativo"`
}
