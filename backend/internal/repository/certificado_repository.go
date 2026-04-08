package repository

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type CertificadoRepository struct {
	pool *pgxpool.Pool
}

func NewCertificadoRepository(pool *pgxpool.Pool) *CertificadoRepository {
	return &CertificadoRepository{pool: pool}
}

// GetAtivoPorTenant retorna o certificado ativo do tenant (escritorio).
func (r *CertificadoRepository) GetAtivoPorTenant(ctx context.Context, tenantID string) (*domain.Certificado, error) {
	tid := strings.TrimSpace(tenantID)
	if tid == "" {
		return nil, fmt.Errorf("tenant obrigatorio")
	}

	const q = `
		SELECT id::text, tenant_id, pfx_cifrado, senha_cifrada,
			COALESCE(cnpj, ''), COALESCE(titular_nome, ''), COALESCE(emitido_por, ''), validade_de, validade_ate, ativo, criado_em, atualizado_em
		FROM public.certificado_tenant
		WHERE tenant_id = $1 AND ativo = true`

	row := r.pool.QueryRow(ctx, q, tid)

	var c domain.Certificado
	var criado, atualizado time.Time
	if err := row.Scan(
		&c.ID, &c.Tenant, &c.PFXCifrado, &c.SenhaCifrada,
		&c.CNPJ, &c.TitularNome, &c.EmitidoPor, &c.ValidadeDe, &c.ValidadeAte, &c.Ativo, &criado, &atualizado,
	); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, fmt.Errorf("certificado nao encontrado para este tenant")
		}
		return nil, fmt.Errorf("ler certificado: %w", err)
	}
	c.CriadoEm = criado
	c.AtualizadoEm = atualizado
	return &c, nil
}

// UpsertAtivo grava ou substitui o certificado por tenant.
func (r *CertificadoRepository) UpsertAtivo(ctx context.Context, c *domain.Certificado) error {
	if c == nil || strings.TrimSpace(c.Tenant) == "" {
		return fmt.Errorf("certificado invalido")
	}
	if len(c.PFXCifrado) == 0 || len(c.SenhaCifrada) == 0 {
		return fmt.Errorf("blobs cifrados obrigatorios")
	}

	const q = `
		INSERT INTO public.certificado_tenant (
			tenant_id, pfx_cifrado, senha_cifrada, cnpj, titular_nome, emitido_por, validade_de, validade_ate, ativo, atualizado_em
		)
		VALUES ($1, $2, $3, NULLIF(TRIM($4), ''), NULLIF(TRIM($5), ''), NULLIF(TRIM($6), ''), $7, $8, true, NOW())
		ON CONFLICT (tenant_id) DO UPDATE SET
			pfx_cifrado = EXCLUDED.pfx_cifrado,
			senha_cifrada = EXCLUDED.senha_cifrada,
			cnpj = EXCLUDED.cnpj,
			titular_nome = EXCLUDED.titular_nome,
			emitido_por = EXCLUDED.emitido_por,
			validade_de = EXCLUDED.validade_de,
			validade_ate = EXCLUDED.validade_ate,
			ativo = true,
			atualizado_em = NOW()`

	_, err := r.pool.Exec(ctx, q,
		strings.TrimSpace(c.Tenant),
		c.PFXCifrado,
		c.SenhaCifrada,
		c.CNPJ,
		c.TitularNome,
		c.EmitidoPor,
		c.ValidadeDe,
		c.ValidadeAte,
	)
	if err != nil {
		return fmt.Errorf("gravar certificado: %w", err)
	}
	return nil
}

// GetResumoAtivoPorTenant retorna metadados do certificado ativo sem decifrar blobs.
func (r *CertificadoRepository) GetResumoAtivoPorTenant(ctx context.Context, tenantID string) (*domain.Certificado, error) {
	tid := strings.TrimSpace(tenantID)
	if tid == "" {
		return nil, fmt.Errorf("tenant obrigatorio")
	}

	const q = `
		SELECT id::text, tenant_id, COALESCE(cnpj, ''), COALESCE(titular_nome, ''), COALESCE(emitido_por, ''), validade_de, validade_ate, ativo, criado_em, atualizado_em
		FROM public.certificado_tenant
		WHERE tenant_id = $1 AND ativo = true`

	row := r.pool.QueryRow(ctx, q, tid)

	var c domain.Certificado
	var criado, atualizado time.Time
	if err := row.Scan(
		&c.ID, &c.Tenant, &c.CNPJ, &c.TitularNome, &c.EmitidoPor, &c.ValidadeDe, &c.ValidadeAte, &c.Ativo, &criado, &atualizado,
	); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, fmt.Errorf("certificado nao encontrado para este tenant")
		}
		return nil, fmt.Errorf("ler resumo certificado: %w", err)
	}
	c.CriadoEm = criado
	c.AtualizadoEm = atualizado
	return &c, nil
}

