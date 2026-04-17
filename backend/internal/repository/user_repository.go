package repository

import (
	"context"
	"fmt"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5/pgxpool"
)

type UserRepository struct {
	pool *pgxpool.Pool
}

func NewUserRepository(pool *pgxpool.Pool) *UserRepository {
	return &UserRepository{pool: pool}
}

func (r *UserRepository) FindByEmail(ctx context.Context, email string) (*domain.User, error) {
	const query = `
		SELECT
			u.id,
			u.nome,
			u.email,
			u.tenantid,
			u.password,
			u.role,
			t.id,
			t.active,
			t.nome,
			COALESCE(t.contato, ''),
			COALESCE(t.plano::text, ''),
			COALESCE(tsc.schema_name, '')
		FROM public.usuario u
		JOIN public.tenant t ON t.id = u.tenantid
		LEFT JOIN public.tenant_schema_catalog tsc ON tsc.tenant_id = t.id
		WHERE LOWER(TRIM(u.email)) = LOWER(TRIM($1))
		LIMIT 1`

	var user domain.User
	if err := dbQueryRow(ctx, r.pool, query, email).Scan(
		&user.ID,
		&user.Nome,
		&user.Email,
		&user.TenantID,
		&user.Password,
		&user.Role,
		&user.Tenant.ID,
		&user.Tenant.Active,
		&user.Tenant.Nome,
		&user.Tenant.Contato,
		&user.Tenant.Plano,
		&user.Tenant.SchemaName,
	); err != nil {
		return nil, fmt.Errorf("find user by email: %w", err)
	}

	return &user, nil
}

func (r *UserRepository) Detail(ctx context.Context, userID string) (domain.UserDetailResponse, error) {
	const query = `
		SELECT
			u.id,
			u.nome,
			u.email,
			u.active,
			u.tenantid,
			u.role,
			t.id,
			t.active,
			t.nome,
			COALESCE(tsc.schema_name, '')
		FROM public.usuario u
		JOIN public.tenant t ON t.id = u.tenantid
		LEFT JOIN public.tenant_schema_catalog tsc ON tsc.tenant_id = t.id
		WHERE u.id = $1::uuid`

	var user domain.User
	if err := dbQueryRow(ctx, r.pool, query, userID).Scan(
		&user.ID,
		&user.Nome,
		&user.Email,
		&user.Active,
		&user.TenantID,
		&user.Role,
		&user.Tenant.ID,
		&user.Tenant.Active,
		&user.Tenant.Nome,
		&user.Tenant.SchemaName,
	); err != nil {
		return domain.UserDetailResponse{}, fmt.Errorf("detail user: %w", err)
	}

	return domain.UserDetailResponse{
		Usuarios: []domain.UserDetailEntry{
			{
				Resultado: domain.UserDetailResult{
					ID:       user.ID,
					Nome:     user.Nome,
					Email:    user.Email,
					Active:   user.Active,
					TenantID: user.TenantID,
					Role:     user.Role,
					Tenant: domain.UserDetailTenant{
						ID:         user.Tenant.ID,
						Active:     user.Tenant.Active,
						Nome:       user.Tenant.Nome,
						SchemaName: user.Tenant.SchemaName,
					},
				},
			},
		},
	}, nil
}

func (r *UserRepository) UserRole(ctx context.Context, userID string) (domain.UserRoleResponse, error) {
	const query = `
		SELECT u.id, u.email, u.tenantid, u.role
		FROM public.usuario u
		WHERE u.id = $1::uuid`

	var id, email, tenantID, role string
	if err := dbQueryRow(ctx, r.pool, query, userID).Scan(&id, &email, &tenantID, &role); err != nil {
		return domain.UserRoleResponse{}, fmt.Errorf("user role: %w", err)
	}

	return domain.UserRoleResponse{Logado: domain.UserRoleData{ID: id, Email: email, TenantID: tenantID, Role: role}}, nil
}

func (r *UserRepository) TenantID(ctx context.Context, userID string) (domain.UserTenantIDResponse, error) {
	const query = `
		SELECT u.tenantid
		FROM public.usuario u
		WHERE u.id = $1::uuid`

	var tenantID string
	if err := dbQueryRow(ctx, r.pool, query, userID).Scan(&tenantID); err != nil {
		return domain.UserTenantIDResponse{}, fmt.Errorf("tenant id: %w", err)
	}

	return domain.UserTenantIDResponse{TenantID: tenantID}, nil
}

func (r *UserRepository) ListByTenant(ctx context.Context, role, tenantID string, filterTenantID string, first, rows int, sortField string, sortOrder int, nomeFilter string) ([]domain.UserListItem, int64, error) {
	whereParts := []string{"u.active = true"}
	args := make([]any, 0)
	argIndex := 1

	requesterRole := strings.ToUpper(strings.TrimSpace(role))
	switch requesterRole {
	case "SUPER":
		if strings.TrimSpace(filterTenantID) != "" {
			whereParts = append(whereParts, "u.role IN ('ADMIN', 'USER')")
			whereParts = append(whereParts, fmt.Sprintf("u.tenantid = $%d::uuid", argIndex))
			args = append(args, strings.TrimSpace(filterTenantID))
			argIndex++
		} else {
			// SUPER sem filtro: todos os ADMIN (todos os tenants)
			whereParts = append(whereParts, "u.role = 'ADMIN'")
		}
	default:
		// ADMIN visualiza ADMIN e USER apenas do seu tenant
		whereParts = append(whereParts, "u.role IN ('ADMIN', 'USER')")
		whereParts = append(whereParts, fmt.Sprintf("u.tenantid = $%d", argIndex))
		args = append(args, tenantID)
		argIndex++
	}

	if strings.TrimSpace(nomeFilter) != "" {
		whereParts = append(whereParts, fmt.Sprintf("u.nome ILIKE $%d", argIndex))
		args = append(args, "%"+strings.TrimSpace(nomeFilter)+"%")
		argIndex++
	}

	orderBy := "u.nome ASC"
	allowedSort := map[string]string{
		"nome":  "u.nome",
		"email": "u.email",
		"id":    "u.id",
		"role":  "u.role",
	}
	if field, ok := allowedSort[sortField]; ok {
		direction := "DESC"
		if sortOrder == -1 {
			direction = "ASC"
		}
		orderBy = field + " " + direction
	}

	listQuery := fmt.Sprintf(
		"SELECT u.id, u.nome, u.email, u.role, u.tenantid, COALESCE(NULLIF(BTRIM(t.nome), ''), '(sem nome)'), u.active FROM public.usuario u LEFT JOIN public.tenant t ON t.id = u.tenantid WHERE %s ORDER BY %s LIMIT $%d OFFSET $%d",
		strings.Join(whereParts, " AND "),
		orderBy,
		argIndex,
		argIndex+1,
	)
	args = append(args, rows, first)

	rowsData, err := dbQuery(ctx, r.pool, listQuery, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list usuarios: %w", err)
	}
	defer rowsData.Close()

	usuarios := make([]domain.UserListItem, 0)
	for rowsData.Next() {
		var id, nome, email, role, tenant, tenantNome string
		var active bool
		if err := rowsData.Scan(&id, &nome, &email, &role, &tenant, &tenantNome, &active); err != nil {
			return nil, 0, fmt.Errorf("scan usuario: %w", err)
		}

		usuarios = append(usuarios, domain.UserListItem{ID: id, Nome: nome, Email: email, Role: role, TenantID: tenant, TenantNome: tenantNome, Active: active})
	}

	countQuery := fmt.Sprintf("SELECT count(*) FROM public.usuario u WHERE %s", strings.Join(whereParts, " AND "))
	var total int64
	if err := dbQueryRow(ctx, r.pool, countQuery, args[:len(args)-2]...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count usuarios: %w", err)
	}

	return usuarios, total, nil
}

func (r *UserRepository) Create(ctx context.Context, nome, email, password, role, tenantID string) ([]domain.UserListItem, error) {
	const sqlQuery = `
		INSERT INTO public.usuario (nome, email, password, role, tenantid, active)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, nome, email, role, tenantid, active`

	rows, err := dbQuery(ctx, r.pool, sqlQuery, nome, email, password, role, tenantID, true)
	if err != nil {
		return nil, fmt.Errorf("create usuario: %w", err)
	}
	defer rows.Close()

	usuarios := make([]domain.UserListItem, 0)
	for rows.Next() {
		var id, nomeDB, emailDB, roleDB, tenantIDDB string
		var active bool
		if err := rows.Scan(&id, &nomeDB, &emailDB, &roleDB, &tenantIDDB, &active); err != nil {
			return nil, fmt.Errorf("scan created usuario: %w", err)
		}

		usuarios = append(usuarios, domain.UserListItem{ID: id, Nome: nomeDB, Email: emailDB, Role: roleDB, TenantID: tenantIDDB, Active: active})
	}

	return usuarios, nil
}

func (r *UserRepository) Update(ctx context.Context, id, nome, email, role, tenantID, requesterRole, requesterTenantID string) ([]domain.UserListItem, error) {
	sqlQuery := `
		UPDATE public.usuario
		SET nome = $1,
			email = $2,
			role = $3,
			tenantid = $4
		WHERE id = $5
		RETURNING id, nome, email, role, tenantid, active`
	args := []any{nome, email, role, tenantID, id}

	if requesterRole != "SUPER" {
		sqlQuery = `
			UPDATE public.usuario
			SET nome = $1,
				email = $2,
				role = $3,
				tenantid = $4
			WHERE id = $5 AND tenantid = $6
			RETURNING id, nome, email, role, tenantid, active`
		args = append(args, requesterTenantID)
	}

	rows, err := dbQuery(ctx, r.pool, sqlQuery, args...)
	if err != nil {
		return nil, fmt.Errorf("update usuario: %w", err)
	}
	defer rows.Close()

	usuarios := make([]domain.UserListItem, 0)
	for rows.Next() {
		var idDB, nomeDB, emailDB, roleDB, tenantIDDB string
		var active bool
		if err := rows.Scan(&idDB, &nomeDB, &emailDB, &roleDB, &tenantIDDB, &active); err != nil {
			return nil, fmt.Errorf("scan updated usuario: %w", err)
		}

		usuarios = append(usuarios, domain.UserListItem{ID: idDB, Nome: nomeDB, Email: emailDB, Role: roleDB, TenantID: tenantIDDB, Active: active})
	}

	if len(usuarios) == 0 {
		return nil, fmt.Errorf("usuario nao encontrado ou sem permissao")
	}

	return usuarios, nil
}

func (r *UserRepository) Delete(ctx context.Context, id, requesterRole, requesterTenantID string) ([]domain.UserListItem, error) {
	sqlQuery := `
		UPDATE public.usuario
		SET active = false
		WHERE id = $1
		RETURNING id, nome, email, role, tenantid, active`
	args := []any{id}

	if requesterRole != "SUPER" {
		sqlQuery = `
			UPDATE public.usuario
			SET active = false
			WHERE id = $1 AND tenantid = $2
			RETURNING id, nome, email, role, tenantid, active`
		args = append(args, requesterTenantID)
	}

	rows, err := dbQuery(ctx, r.pool, sqlQuery, args...)
	if err != nil {
		return nil, fmt.Errorf("delete usuario: %w", err)
	}
	defer rows.Close()

	usuarios := make([]domain.UserListItem, 0)
	for rows.Next() {
		var idDB, nomeDB, emailDB, roleDB, tenantIDDB string
		var active bool
		if err := rows.Scan(&idDB, &nomeDB, &emailDB, &roleDB, &tenantIDDB, &active); err != nil {
			return nil, fmt.Errorf("scan deleted usuario: %w", err)
		}

		usuarios = append(usuarios, domain.UserListItem{ID: idDB, Nome: nomeDB, Email: emailDB, Role: roleDB, TenantID: tenantIDDB, Active: active})
	}

	if len(usuarios) == 0 {
		return nil, fmt.Errorf("usuario nao encontrado ou sem permissao")
	}

	return usuarios, nil
}

func (r *UserRepository) UpdatePassword(ctx context.Context, userID, passwordHash string) error {
	const query = `
		UPDATE public.usuario
		SET password = $1
		WHERE id = $2`

	if _, err := dbExec(ctx, r.pool, query, passwordHash, userID); err != nil {
		return fmt.Errorf("update usuario password: %w", err)
	}

	return nil
}
