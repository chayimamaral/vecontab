package repository

import (
	"context"
	"fmt"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type TenantRepository struct {
	pool *pgxpool.Pool
}

func NewTenantRepository(pool *pgxpool.Pool) *TenantRepository {
	return &TenantRepository{pool: pool}
}

func (r *TenantRepository) Create(ctx context.Context, nome, contato, plano string) (domain.TenantEntity, error) {
	const existsQuery = `SELECT count(*) FROM public.tenant WHERE nome = $1`
	var count int64
	if err := r.pool.QueryRow(ctx, existsQuery, nome).Scan(&count); err != nil {
		return domain.TenantEntity{}, fmt.Errorf("check tenant exists: %w", err)
	}

	if count > 0 {
		return domain.TenantEntity{}, fmt.Errorf("Empresa ja cadastrada")
	}

	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return domain.TenantEntity{}, fmt.Errorf("begin tx create tenant: %w", err)
	}
	defer tx.Rollback(ctx)

	const query = `
		INSERT INTO public.tenant (nome, contato, active, plano)
		VALUES ($1, $2, $3, $4::public.planos)
		RETURNING id, nome, contato, active, COALESCE(plano::text, '')`

	var tenant domain.TenantEntity
	if err := tx.QueryRow(ctx, query, nome, contato, true, plano).Scan(
		&tenant.ID,
		&tenant.Nome,
		&tenant.Contato,
		&tenant.Active,
		&tenant.Plano,
	); err != nil {
		return domain.TenantEntity{}, fmt.Errorf("create tenant: %w", err)
	}

	const dadosQuery = `INSERT INTO public.tenant_dados (tenantid) VALUES ($1)`
	if _, err := tx.Exec(ctx, dadosQuery, tenant.ID); err != nil {
		return domain.TenantEntity{}, fmt.Errorf("create tenant_dados: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return domain.TenantEntity{}, fmt.Errorf("commit create tenant: %w", err)
	}

	return tenant, nil
}

func (r *TenantRepository) Detail(ctx context.Context, id string) (domain.TenantEntity, error) {
	const query = `
		SELECT id,
		       COALESCE(nome, ''),
		       COALESCE(contato, ''),
		       COALESCE(active, false),
		       COALESCE(plano::text, '')
		FROM public.tenant
		WHERE id::text = $1`

	var tenant domain.TenantEntity
	if err := r.pool.QueryRow(ctx, query, id).Scan(
		&tenant.ID,
		&tenant.Nome,
		&tenant.Contato,
		&tenant.Active,
		&tenant.Plano,
	); err != nil {
		return domain.TenantEntity{}, fmt.Errorf("detail tenant: %w", err)
	}

	return tenant, nil
}

func (r *TenantRepository) Update(ctx context.Context, id, nome, contato, plano string, active bool) (domain.TenantEntity, error) {
	const query = `
		UPDATE public.tenant
		SET nome = $1,
		    active = $2,
		    contato = $3,
		    plano = CASE WHEN BTRIM($4) = '' THEN plano ELSE $4::public.planos END
		WHERE id::text = $5
		RETURNING id, COALESCE(nome, ''), COALESCE(contato, ''), COALESCE(active, false), COALESCE(plano::text, '')`

	var tenant domain.TenantEntity
	if err := r.pool.QueryRow(ctx, query, nome, active, contato, plano, id).Scan(
		&tenant.ID,
		&tenant.Nome,
		&tenant.Contato,
		&tenant.Active,
		&tenant.Plano,
	); err != nil {
		return domain.TenantEntity{}, fmt.Errorf("update tenant: %w", err)
	}

	return tenant, nil
}

func (r *TenantRepository) List(ctx context.Context, role, tenantID string) ([]domain.TenantEntity, error) {
	query := `
		SELECT id,
		       COALESCE(nome, ''),
		       COALESCE(contato, ''),
		       COALESCE(active, false),
		       COALESCE(plano::text, '')
		FROM public.tenant
		WHERE id::text = $1`
	args := []any{tenantID}

	if role == "SUPER" {
		query = `
			SELECT id,
			       COALESCE(nome, ''),
			       COALESCE(contato, ''),
			       COALESCE(active, false),
			       COALESCE(plano::text, '')
			FROM public.tenant
			WHERE NULLIF(BTRIM(COALESCE(nome, '')), '') IS NOT NULL`
		args = []any{}
	}

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list tenants: %w", err)
	}
	defer rows.Close()

	tenants := make([]domain.TenantEntity, 0)
	for rows.Next() {
		var tenant domain.TenantEntity
		if err := rows.Scan(
			&tenant.ID,
			&tenant.Nome,
			&tenant.Contato,
			&tenant.Active,
			&tenant.Plano,
		); err != nil {
			return nil, fmt.Errorf("scan tenant: %w", err)
		}

		tenants = append(tenants, tenant)
	}

	return tenants, nil
}

func (r *TenantRepository) ListWithDadosForSuper(ctx context.Context) ([]domain.TenantListRow, error) {
	const query = `
		SELECT t.id,
		       COALESCE(t.nome, ''),
		       COALESCE(t.contato, ''),
		       COALESCE(t.active, false),
		       COALESCE(t.plano::text, ''),
		       COALESCE(td.cnpj::text, ''),
		       COALESCE(td.razaosocial::text, ''),
		       COALESCE(td.fantasia::text, '')
		FROM public.tenant t
		LEFT JOIN public.tenant_dados td ON td.tenantid = t.id
		WHERE NULLIF(BTRIM(COALESCE(t.nome, '')), '') IS NOT NULL
		ORDER BY COALESCE(t.nome, '')`

	rows, err := r.pool.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("list tenants with dados: %w", err)
	}
	defer rows.Close()

	out := make([]domain.TenantListRow, 0)
	for rows.Next() {
		var row domain.TenantListRow
		if err := rows.Scan(
			&row.ID,
			&row.Nome,
			&row.Contato,
			&row.Active,
			&row.Plano,
			&row.CNPJ,
			&row.RazaoSocial,
			&row.Fantasia,
		); err != nil {
			return nil, fmt.Errorf("scan tenant list row: %w", err)
		}
		out = append(out, row)
	}

	return out, nil
}
