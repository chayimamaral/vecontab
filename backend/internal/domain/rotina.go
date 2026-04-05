package domain

type RotinaMunicipioRef struct {
	ID   string `json:"id"`
	Nome string `json:"nome"`
}

type RotinaTipoEmpresaRef struct {
	ID        string `json:"id"`
	Descricao string `json:"descricao"`
}

type RotinaListItem struct {
	ID            string               `json:"id"`
	Descricao     string               `json:"descricao"`
	MunicipioID   string               `json:"municipio_id"`
	Municipio     RotinaMunicipioRef   `json:"municipio"`
	TipoEmpresaID string               `json:"tipo_empresa_id"`
	TipoEmpresa   RotinaTipoEmpresaRef `json:"tipo_empresa"`
}

type RotinaPassoItem struct {
	ID            string `json:"id"`
	Descricao     string `json:"descricao"`
	TempoEstimado int    `json:"tempoestimado"`
	Link          string `json:"link"`
}

type RotinaWithItensItem struct {
	ID            string               `json:"id"`
	Descricao     string               `json:"descricao"`
	MunicipioID   string               `json:"municipio_id"`
	Municipio     RotinaMunicipioRef   `json:"municipio"`
	TipoEmpresaID string               `json:"tipo_empresa_id"`
	TipoEmpresa   RotinaTipoEmpresaRef `json:"tipo_empresa"`
	RotinaItens   []RotinaPassoItem    `json:"rotinaitens"`
}

type RotinaLiteItem struct {
	ID            string               `json:"id"`
	Descricao     string               `json:"descricao"`
	TipoEmpresaID string               `json:"tipo_empresa_id"`
	TipoEmpresa   RotinaTipoEmpresaRef `json:"tipo_empresa"`
	Municipio     RotinaMunicipioRef   `json:"municipio"`
}

type RotinaMutationItem struct {
	ID            string `json:"id"`
	Descricao     string `json:"descricao"`
	MunicipioID   string `json:"municipio_id"`
	TipoEmpresaID string `json:"tipo_empresa_id"`
	Ativo         bool   `json:"ativo"`
}

type RotinaSelectedPassoItem struct {
	ID            string `json:"id"`
	Descricao     string `json:"descricao"`
	TempoEstimado int    `json:"tempoestimado"`
	Tipopasso     string `json:"tipopasso"`
	RotinaID      string `json:"rotina_id"`
	Ordem         any    `json:"ordem"`
	Link          string `json:"link"`
}
