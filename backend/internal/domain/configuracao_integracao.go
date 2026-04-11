package domain

// ChavesSuper credencial OAuth Serpro (Integra Contador), no tenant da VEC Sistemas (usuários SUPER).
// Manutenção apenas SUPER; todos os SUPER compartilham o mesmo tenant_id.
type ChavesSuper struct {
	TenantID       string `json:"tenant_id,omitempty"`
	ConsumerKey    string `json:"consumer_key"`
	ConsumerSecret string `json:"consumer_secret"`
}

type TenantConfiguracoes struct {
	TenantID                      string `json:"tenant_id"`
	GerarDASPorProcuracao         bool   `json:"gerar_das_por_procuracao"`
	GerarDARFDCTFWebPorProcuracao bool   `json:"gerar_darf_dctfweb_por_procuracao"`
	TipoCertificado               string `json:"tipo_certificado"`
	LocalArquivoCertificado       string `json:"local_arquivo_certificado"`
	SenhaCertificado              string `json:"senha_certificado"`
	NomeCertificado               string `json:"nome_certificado"`
	EmitidoPara                   string `json:"emitido_para"`
	EmitidoPor                    string `json:"emitido_por"`
	ValidadeDe                    string `json:"validade_de"`
	ValidadeAte                   string `json:"validade_ate"`
}
