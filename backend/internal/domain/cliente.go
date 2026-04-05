package domain

// TipoPessoa discrimina Pessoa Física (IRPF/Carnê-Leão) e Pessoa Jurídica.
type TipoPessoa string

const (
	TipoPessoaPF TipoPessoa = "PF"
	TipoPessoaPJ TipoPessoa = "PJ"
)

// Cliente unifica o cadastro de PF e PJ no domínio.
// Persistência atual: linha em public.empresa (mesmo UUID) + opcional public.empresa_dados.
// RotinaID e Cnaes são obrigatórios na regra de negócio para PJ; para PF permanecem nulos.
type Cliente struct {
	ID          string     `json:"id"`
	TenantID    string     `json:"tenant_id"`
	TipoPessoa  TipoPessoa `json:"tipoPessoa"`
	Nome        string     `json:"nome"`
	Documento   string     `json:"documento"` // CPF ou CNPJ (formato definido na camada de aplicação)
	MunicipioID *string    `json:"municipioId,omitempty"`
	RotinaID    *string    `json:"rotinaId,omitempty"`
	Cnaes       any        `json:"cnaes,omitempty"`
	Bairro      string     `json:"bairro,omitempty"`
	Iniciado    bool       `json:"iniciado"`
	Ativo       bool       `json:"ativo"`
}

// ClienteSocio vincula um cliente PF a um cliente PJ (sócio também atendido como PF).
type ClienteSocio struct {
	ID           string `json:"id"`
	TenantID     string `json:"tenant_id"`
	ClientePJID  string `json:"clientePjId"`
	ClientePFID  string `json:"clientePfId"`
	Ativo        bool   `json:"ativo"`
}
