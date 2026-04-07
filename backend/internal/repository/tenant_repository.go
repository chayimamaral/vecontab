package repository

import (
	"context"
	"fmt"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5/pgxpool"
)

type TenantRepository struct {
	pool *pgxpool.Pool
}

func NewTenantRepository(pool *pgxpool.Pool) *TenantRepository {
	return &TenantRepository{pool: pool}
}

func (r *TenantRepository) Create(ctx context.Context, nome, contato string) (domain.TenantEntity, error) {
	const existsQuery = `SELECT count(*) FROM public.tenant WHERE nome = $1`
	var count int64
	if err := r.pool.QueryRow(ctx, existsQuery, nome).Scan(&count); err != nil {
		return domain.TenantEntity{}, fmt.Errorf("check tenant exists: %w", err)
	}

	if count > 0 {
		return domain.TenantEntity{}, fmt.Errorf("Empresa ja cadastrada")
	}

	const query = `
		INSERT INTO public.tenant (nome, contato, active, plano)
		VALUES ($1, $2, $3, $4)
		RETURNING id, nome, contato, active, plano`

	var tenant domain.TenantEntity
	if err := r.pool.QueryRow(ctx, query, nome, contato, true, "DEMO").Scan(
		&tenant.ID,
		&tenant.Nome,
		&tenant.Contato,
		&tenant.Active,
		&tenant.Plano,
	); err != nil {
		return domain.TenantEntity{}, fmt.Errorf("create tenant: %w", err)
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
