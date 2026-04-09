package domain

type TipoEmpresa struct {
	ID        string  `json:"id"`
	Descricao string  `json:"descricao"`
	Anual     float64 `json:"anual"`
	Ativo     bool    `json:"ativo,omitempty"`
}

type TipoEmpresaLiteItem struct {
	ID        string `json:"id"`
	Descricao string `json:"descricao"`
}
