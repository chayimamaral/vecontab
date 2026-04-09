package domain

type EmpresaDadosItem struct {
	EmpresaID        string     `json:"empresa_id"`
	CNPJ             *string    `json:"cnpj,omitempty"`
	CapitalSocial    *float64   `json:"capital_social,omitempty"`
	Endereco         *string    `json:"endereco,omitempty"`
	Numero           *string    `json:"numero,omitempty"`
	CEP              *string    `json:"cep,omitempty"`
	EmailContato     *string    `json:"email_contato,omitempty"`
	Telefone         *string    `json:"telefone,omitempty"`
	Telefone2        *string    `json:"telefone2,omitempty"`
	DataAbertura     *string    `json:"data_abertura,omitempty"`
	DataEncerramento *string    `json:"data_encerramento,omitempty"`
	Observacao       *string    `json:"observacao,omitempty"`
	Municipio        EmpresaRef `json:"municipio"`
}
