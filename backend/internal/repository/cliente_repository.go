package repository

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ClienteRepository acesso unificado a clientes PF/PJ persistidos em public.empresa
// (mesmos UUIDs usados por empresa_agenda e empresa_compromissos).
// Validação PJ (rotina/CNAEs) e PF (documento) fica na camada de serviço.
type ClienteRepository struct {
	pool *pgxpool.Pool
}

func NewClienteRepository(pool *pgxpool.Pool) *ClienteRepository {
	return &ClienteRepository{pool: pool}
}

// GetByID carrega um cliente ativo do tenant. Documento usa e.documento ou fallback em empresa_dados.cnpj (PJ legado).
func (r *ClienteRepository) GetByID(ctx context.Context, tenantID, id string) (domain.Cliente, error) {
	const q = `
		SELECT
			e.id,
			e.tenant_id,
			COALESCE(NULLIF(BTRIM(e.tipo_pessoa::text), ''), 'PJ')::text,
			e.nome,
			COALESCE(NULLIF(BTRIM(e.documento), ''), NULLIF(BTRIM(ed.cnpj::text), '')),
			COALESCE(e.municipio_id, ed.municipio_id)::text,
			e.rotina_id::text,
			e.cnaes,
			COALESCE(e.bairro, ''),
			e.iniciado,
			e.ativo
		FROM public.empresa e
		LEFT JOIN public.empresa_dados ed ON ed.empresa_id = e.id
		WHERE e.id = $1 AND e.tenant_id = $2 AND e.ativo = true`

	var c domain.Cliente
	var doc, munID, rotID sql.NullString
	if err := r.pool.QueryRow(ctx, q, id, tenantID).Scan(
		&c.ID,
		&c.TenantID,
		&c.TipoPessoa,
		&c.Nome,
		&doc,
		&munID,
		&rotID,
		&c.Cnaes,
		&c.Bairro,
		&c.Iniciado,
		&c.Ativo,
	); err != nil {
		if err == pgx.ErrNoRows {
			return domain.Cliente{}, fmt.Errorf("cliente nao encontrado")
		}
		return domain.Cliente{}, fmt.Errorf("get cliente: %w", err)
	}
	if doc.Valid {
		c.Documento = doc.String
	}
	if munID.Valid {
		s := munID.String
		c.MunicipioID = &s
	}
	if rotID.Valid {
		s := rotID.String
		c.RotinaID = &s
	}
	return c, nil
}

// ListByTenant lista clientes ativos do escritório (paginação pode ser acrescentada depois).
func (r *ClienteRepository) ListByTenant(ctx context.Context, tenantID string, limit, offset int) ([]domain.Cliente, error) {
	if limit <= 0 {
		limit = 100
	}
	if offset < 0 {
		offset = 0
	}
	const q = `
		SELECT
			e.id,
			e.tenant_id,
			COALESCE(NULLIF(BTRIM(e.tipo_pessoa::text), ''), 'PJ')::text,
			e.nome,
			COALESCE(NULLIF(BTRIM(e.documento), ''), NULLIF(BTRIM(ed.cnpj::text), '')),
			COALESCE(e.municipio_id, ed.municipio_id)::text,
			e.rotina_id::text,
			e.cnaes,
			COALESCE(e.bairro, ''),
			e.iniciado,
			e.ativo
		FROM public.empresa e
		LEFT JOIN public.empresa_dados ed ON ed.empresa_id = e.id
		WHERE e.tenant_id = $1 AND e.ativo = true
		ORDER BY e.nome ASC
		LIMIT $2 OFFSET $3`

	rows, err := r.pool.Query(ctx, q, tenantID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("list clientes: %w", err)
	}
	defer rows.Close()

	out := make([]domain.Cliente, 0)
	for rows.Next() {
		var c domain.Cliente
		var doc, munID, rotID sql.NullString
		if err := rows.Scan(
			&c.ID,
			&c.TenantID,
			&c.TipoPessoa,
			&c.Nome,
			&doc,
			&munID,
			&rotID,
			&c.Cnaes,
			&c.Bairro,
			&c.Iniciado,
			&c.Ativo,
		); err != nil {
			return nil, fmt.Errorf("scan cliente: %w", err)
		}
		if doc.Valid {
			c.Documento = doc.String
		}
		if munID.Valid {
			s := munID.String
			c.MunicipioID = &s
		}
		if rotID.Valid {
			s := rotID.String
			c.RotinaID = &s
		}
		out = append(out, c)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return out, nil
}
