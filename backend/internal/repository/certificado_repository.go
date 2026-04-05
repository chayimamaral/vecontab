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

// GetAtivoPorEmpresa retorna o certificado ativo do cliente no tenant.
func (r *CertificadoRepository) GetAtivoPorEmpresa(ctx context.Context, tenantID, empresaID string) (*domain.Certificado, error) {
	tid := strings.TrimSpace(tenantID)
	eid := strings.TrimSpace(empresaID)
	if tid == "" || eid == "" {
		return nil, fmt.Errorf("tenant e empresa obrigatorios")
	}

	const q = `
		SELECT id::text, tenant_id, empresa_id, pfx_cifrado, senha_cifrada,
			COALESCE(cnpj, ''), COALESCE(titular_nome, ''), validade_ate, ativo, criado_em, atualizado_em
		FROM public.certificado_cliente
		WHERE tenant_id = $1 AND empresa_id = $2 AND ativo = true`

	row := r.pool.QueryRow(ctx, q, tid, eid)

	var c domain.Certificado
	var criado, atualizado time.Time
	if err := row.Scan(
		&c.ID, &c.Tenant, &c.EmpresaID, &c.PFXCifrado, &c.SenhaCifrada,
		&c.CNPJ, &c.TitularNome, &c.ValidadeAte, &c.Ativo, &criado, &atualizado,
	); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, fmt.Errorf("certificado nao encontrado para este cliente")
		}
		return nil, fmt.Errorf("ler certificado: %w", err)
	}
	c.CriadoEm = criado
	c.AtualizadoEm = atualizado
	return &c, nil
}

// UpsertAtivo grava ou substitui o certificado do par (tenant, empresa).
func (r *CertificadoRepository) UpsertAtivo(ctx context.Context, c *domain.Certificado) error {
	if c == nil || strings.TrimSpace(c.Tenant) == "" || strings.TrimSpace(c.EmpresaID) == "" {
		return fmt.Errorf("certificado invalido")
	}
	if len(c.PFXCifrado) == 0 || len(c.SenhaCifrada) == 0 {
		return fmt.Errorf("blobs cifrados obrigatorios")
	}

	const q = `
		INSERT INTO public.certificado_cliente (
			tenant_id, empresa_id, pfx_cifrado, senha_cifrada, cnpj, titular_nome, validade_ate, ativo, atualizado_em
		)
		VALUES ($1, $2, $3, $4, NULLIF(TRIM($5), ''), NULLIF(TRIM($6), ''), $7, true, NOW())
		ON CONFLICT (tenant_id, empresa_id) DO UPDATE SET
			pfx_cifrado = EXCLUDED.pfx_cifrado,
			senha_cifrada = EXCLUDED.senha_cifrada,
			cnpj = EXCLUDED.cnpj,
			titular_nome = EXCLUDED.titular_nome,
			validade_ate = EXCLUDED.validade_ate,
			ativo = true,
			atualizado_em = NOW()`

	_, err := r.pool.Exec(ctx, q,
		strings.TrimSpace(c.Tenant),
		strings.TrimSpace(c.EmpresaID),
		c.PFXCifrado,
		c.SenhaCifrada,
		c.CNPJ,
		c.TitularNome,
		c.ValidadeAte,
	)
	if err != nil {
		return fmt.Errorf("gravar certificado: %w", err)
	}
	return nil
}
