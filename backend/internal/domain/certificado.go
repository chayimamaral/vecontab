package domain

import "time"

// Certificado representa certificado digital A1 (PFX) de um cliente da contabilidade,
// persistido de forma cifrada. Multi-empresa: um registro por par (tenant_id, empresa_id)
// quando ativo — ver regra de negócio no serviço/repositório.
//
// PFX e senha nunca trafegam em JSON de API em claro; use DTOs separados para upload.
type Certificado struct {
	ID     string `json:"id"`
	Tenant string `json:"tenant_id"`
	// EmpresaID referencia public.empresa.id (cliente PJ/PF atendido pelo escritório).
	EmpresaID string `json:"empresa_id"`

	// PFXCifrado e SenhaCifrada são produzidos por certseal.Seal (nonce||ciphertext).
	PFXCifrado   []byte `json:"-"`
	SenhaCifrada []byte `json:"-"`

	CNPJ        string    `json:"cnpj,omitempty"`
	TitularNome string    `json:"titular_nome,omitempty"`
	EmitidoPor  string    `json:"emitido_por,omitempty"`
	ValidadeDe  time.Time `json:"validade_de,omitempty"`
	ValidadeAte time.Time `json:"validade_ate"`
	Ativo       bool      `json:"ativo"`
	CriadoEm    time.Time `json:"criado_em,omitempty"`
	AtualizadoEm time.Time `json:"atualizado_em,omitempty"`
}

// CertificadoMaterial existe apenas em memória entre decifrar e usar em tls.X509KeyPair / SERPRO.
// Chame Zero() após o uso para reduzir janela de vazamento em dumps de memória.
type CertificadoMaterial struct {
	PFX         []byte
	Senha       string
	CNPJ        string
	Nome        string
	ValidadeAte time.Time
}

// Zero apaga buffers sensíveis (melhor esforço em Go).
func (m *CertificadoMaterial) Zero() {
	if m == nil {
		return
	}
	for i := range m.PFX {
		m.PFX[i] = 0
	}
	m.PFX = nil
	m.Senha = ""
}
