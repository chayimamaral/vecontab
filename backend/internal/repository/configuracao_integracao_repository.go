package repository

import (
	"context"
	"fmt"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5/pgxpool"
)

type ConfiguracaoIntegracaoRepository struct {
	pool *pgxpool.Pool
}

func NewConfiguracaoIntegracaoRepository(pool *pgxpool.Pool) *ConfiguracaoIntegracaoRepository {
	return &ConfiguracaoIntegracaoRepository{pool: pool}
}

func (r *ConfiguracaoIntegracaoRepository) UpsertChavesSuper(ctx context.Context, item domain.ChavesSuper) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO public.chavessuper (tenant_id, consumer_key, consumer_secret, atualizado_em)
		VALUES ($1, $2, $3, NOW())
		ON CONFLICT (tenant_id) DO UPDATE
		SET consumer_key = EXCLUDED.consumer_key,
		    consumer_secret = EXCLUDED.consumer_secret,
		    atualizado_em = NOW()
	`, item.TenantID, strings.TrimSpace(item.ConsumerKey), strings.TrimSpace(item.ConsumerSecret))
	if err != nil {
		return fmt.Errorf("upsert chavessuper: %w", err)
	}
	return nil
}

func (r *ConfiguracaoIntegracaoRepository) GetChavesSuper(ctx context.Context, tenantID string) (domain.ChavesSuper, error) {
	var out domain.ChavesSuper
	err := r.pool.QueryRow(ctx, `
		SELECT tenant_id::text, COALESCE(consumer_key, ''), COALESCE(consumer_secret, '')
		FROM public.chavessuper
		WHERE tenant_id::text = $1
	`, tenantID).Scan(&out.TenantID, &out.ConsumerKey, &out.ConsumerSecret)
	if err != nil {
		return domain.ChavesSuper{TenantID: tenantID}, nil
	}
	return out, nil
}

func (r *ConfiguracaoIntegracaoRepository) UpsertTenantConfiguracoes(ctx context.Context, item domain.TenantConfiguracoes) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO public.tenant_configuracoes (
			tenant_id,
			gerar_das_por_procuracao,
			gerar_darf_dctfweb_por_procuracao,
			tipo_certificado,
			local_arquivo_certificado,
			senha_certificado,
			nome_certificado,
			emitido_para,
			emitido_por,
			validade_de,
			validade_ate,
			atualizado_em
		)
		VALUES ($1,$2,$3,NULLIF(TRIM($4),''),NULLIF(TRIM($5),''),NULLIF(TRIM($6),''),NULLIF(TRIM($7),''),NULLIF(TRIM($8),''),NULLIF(TRIM($9),''),NULLIF(TRIM($10), '')::date,NULLIF(TRIM($11), '')::date,NOW())
		ON CONFLICT (tenant_id) DO UPDATE SET
			gerar_das_por_procuracao = EXCLUDED.gerar_das_por_procuracao,
			gerar_darf_dctfweb_por_procuracao = EXCLUDED.gerar_darf_dctfweb_por_procuracao,
			tipo_certificado = EXCLUDED.tipo_certificado,
			local_arquivo_certificado = EXCLUDED.local_arquivo_certificado,
			senha_certificado = EXCLUDED.senha_certificado,
			nome_certificado = EXCLUDED.nome_certificado,
			emitido_para = EXCLUDED.emitido_para,
			emitido_por = EXCLUDED.emitido_por,
			validade_de = EXCLUDED.validade_de,
			validade_ate = EXCLUDED.validade_ate,
			atualizado_em = NOW()
	`, item.TenantID, item.GerarDASPorProcuracao, item.GerarDARFDCTFWebPorProcuracao, item.TipoCertificado, item.LocalArquivoCertificado, item.SenhaCertificado, item.NomeCertificado, item.EmitidoPara, item.EmitidoPor, item.ValidadeDe, item.ValidadeAte)
	if err != nil {
		return fmt.Errorf("upsert tenant_configuracoes: %w", err)
	}
	return nil
}

func (r *ConfiguracaoIntegracaoRepository) GetTenantConfiguracoes(ctx context.Context, tenantID string) (domain.TenantConfiguracoes, error) {
	var out domain.TenantConfiguracoes
	err := r.pool.QueryRow(ctx, `
		SELECT
			tenant_id::text,
			COALESCE(gerar_das_por_procuracao, false),
			COALESCE(gerar_darf_dctfweb_por_procuracao, false),
			COALESCE(tipo_certificado, ''),
			COALESCE(local_arquivo_certificado, ''),
			COALESCE(senha_certificado, ''),
			COALESCE(nome_certificado, ''),
			COALESCE(emitido_para, ''),
			COALESCE(emitido_por, ''),
			COALESCE(validade_de::text, ''),
			COALESCE(validade_ate::text, '')
		FROM public.tenant_configuracoes
		WHERE tenant_id::text = $1
	`, tenantID).Scan(
		&out.TenantID,
		&out.GerarDASPorProcuracao,
		&out.GerarDARFDCTFWebPorProcuracao,
		&out.TipoCertificado,
		&out.LocalArquivoCertificado,
		&out.SenhaCertificado,
		&out.NomeCertificado,
		&out.EmitidoPara,
		&out.EmitidoPor,
		&out.ValidadeDe,
		&out.ValidadeAte,
	)
	if err != nil {
		return domain.TenantConfiguracoes{TenantID: tenantID}, nil
	}
	return out, nil
}
