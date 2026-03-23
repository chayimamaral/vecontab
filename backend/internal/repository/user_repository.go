package repository

import (
	"context"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Tenant struct {
	ID      string `json:"id"`
	Active  bool   `json:"active"`
	Nome    string `json:"nome"`
	Contato string `json:"contato,omitempty"`
	Plano   string `json:"plano,omitempty"`
}

type User struct {
	ID       string `json:"id"`
	Nome     string `json:"nome"`
	Email    string `json:"email"`
	TenantID string `json:"tenantid"`
	Password string `json:"-"`
	Role     string `json:"role"`
	Active   bool   `json:"active,omitempty"`
	Tenant   Tenant `json:"tenant"`
}

type UserDetailTenant struct {
	ID     string `json:"id"`
	Active bool   `json:"active"`
	Nome   string `json:"nome"`
}

type UserDetailResult struct {
	ID       string           `json:"id"`
	Nome     string           `json:"nome"`
	Email    string           `json:"email"`
	Active   bool             `json:"active"`
	TenantID string           `json:"tenantId"`
	Role     string           `json:"role"`
	Tenant   UserDetailTenant `json:"tenant"`
}

type UserDetailEntry struct {
	Resultado UserDetailResult `json:"resultado"`
}

type UserDetailResponse struct {
	Usuarios []UserDetailEntry `json:"usuarios"`
}

type UserRoleData struct {
	ID       string `json:"id"`
	Email    string `json:"email"`
	TenantID string `json:"tenantid"`
	Role     string `json:"role"`
}

type UserRoleResponse struct {
	Logado UserRoleData `json:"logado"`
}

type UserTenantIDResponse struct {
	TenantID string `json:"tenantid"`
}

type UserListItem struct {
	ID       string `json:"id"`
	Nome     string `json:"nome"`
	Email    string `json:"email"`
	Role     string `json:"role"`
	TenantID string `json:"tenantid"`
	Active   bool   `json:"active"`
}

type UserRepository struct {
	pool *pgxpool.Pool
}

func NewUserRepository(pool *pgxpool.Pool) *UserRepository {
	return &UserRepository{pool: pool}
}

func (r *UserRepository) FindByEmail(ctx context.Context, email string) (*User, error) {
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
			COALESCE(t.plano::text, '')
		FROM public.usuario u
		JOIN public.tenant t ON t.id = u.tenantid
		WHERE LOWER(TRIM(u.email)) = LOWER(TRIM($1))
		LIMIT 1`

	var user User
	if err := r.pool.QueryRow(ctx, query, email).Scan(
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
	); err != nil {
		return nil, fmt.Errorf("find user by email: %w", err)
	}

	return &user, nil
}

func (r *UserRepository) Detail(ctx context.Context, userID string) (UserDetailResponse, error) {
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
			t.nome
		FROM public.usuario u
		JOIN public.tenant t ON t.id = u.tenantid
		WHERE u.id = $1::text`

	var user User
	if err := r.pool.QueryRow(ctx, query, userID).Scan(
		&user.ID,
		&user.Nome,
		&user.Email,
		&user.Active,
		&user.TenantID,
		&user.Role,
		&user.Tenant.ID,
		&user.Tenant.Active,
		&user.Tenant.Nome,
	); err != nil {
		return UserDetailResponse{}, fmt.Errorf("detail user: %w", err)
	}

	return UserDetailResponse{
		Usuarios: []UserDetailEntry{
			{
				Resultado: UserDetailResult{
					ID:       user.ID,
					Nome:     user.Nome,
					Email:    user.Email,
					Active:   user.Active,
					TenantID: user.TenantID,
					Role:     user.Role,
					Tenant: UserDetailTenant{
						ID:     user.Tenant.ID,
						Active: user.Tenant.Active,
						Nome:   user.Tenant.Nome,
					},
				},
			},
		},
	}, nil
}

func (r *UserRepository) UserRole(ctx context.Context, userID string) (UserRoleResponse, error) {
	const query = `
		SELECT u.id, u.email, u.tenantid, u.role
		FROM public.usuario u
		WHERE u.id = $1::text`

	var id, email, tenantID, role string
	if err := r.pool.QueryRow(ctx, query, userID).Scan(&id, &email, &tenantID, &role); err != nil {
		return UserRoleResponse{}, fmt.Errorf("user role: %w", err)
	}

	return UserRoleResponse{Logado: UserRoleData{ID: id, Email: email, TenantID: tenantID, Role: role}}, nil
}

func (r *UserRepository) TenantID(ctx context.Context, userID string) (UserTenantIDResponse, error) {
	const query = `
		SELECT u.tenantid
		FROM public.usuario u
		WHERE u.id = $1::text`

	var tenantID string
	if err := r.pool.QueryRow(ctx, query, userID).Scan(&tenantID); err != nil {
		return UserTenantIDResponse{}, fmt.Errorf("tenant id: %w", err)
	}

	return UserTenantIDResponse{TenantID: tenantID}, nil
}

func (r *UserRepository) ListByTenant(ctx context.Context, tenantID string, first, rows int, sortField string, sortOrder int, nomeFilter string) ([]UserListItem, int64, error) {
	whereParts := []string{"active = true", "tenantid = $1"}
	args := []any{tenantID}
	argIndex := 2

	if strings.TrimSpace(nomeFilter) != "" {
		whereParts = append(whereParts, fmt.Sprintf("nome ILIKE $%d", argIndex))
		args = append(args, "%"+strings.TrimSpace(nomeFilter)+"%")
		argIndex++
	}

	orderBy := "nome ASC"
	allowedSort := map[string]string{
		"nome":  "nome",
		"email": "email",
		"id":    "id",
	}
	if field, ok := allowedSort[sortField]; ok {
		direction := "DESC"
		if sortOrder == -1 {
			direction = "ASC"
		}
		orderBy = field + " " + direction
	}

	listQuery := fmt.Sprintf(
		"SELECT id, nome, email, role, tenantid, active FROM public.usuario WHERE %s ORDER BY %s LIMIT $%d OFFSET $%d",
		strings.Join(whereParts, " AND "),
		orderBy,
		argIndex,
		argIndex+1,
	)
	args = append(args, rows, first)

	rowsData, err := r.pool.Query(ctx, listQuery, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list usuarios: %w", err)
	}
	defer rowsData.Close()

	usuarios := make([]UserListItem, 0)
	for rowsData.Next() {
		var id, nome, email, role, tenant string
		var active bool
		if err := rowsData.Scan(&id, &nome, &email, &role, &tenant, &active); err != nil {
			return nil, 0, fmt.Errorf("scan usuario: %w", err)
		}

		usuarios = append(usuarios, UserListItem{ID: id, Nome: nome, Email: email, Role: role, TenantID: tenant, Active: active})
	}

	countQuery := fmt.Sprintf("SELECT count(*) FROM public.usuario WHERE %s", strings.Join(whereParts, " AND "))
	var total int64
	if err := r.pool.QueryRow(ctx, countQuery, args[:len(args)-2]...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count usuarios: %w", err)
	}

	return usuarios, total, nil
}

func (r *UserRepository) Create(ctx context.Context, nome, email, password, role, tenantID string) ([]UserListItem, error) {
	const query = `
		INSERT INTO public.usuario (nome, email, password, role, tenantid, active)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, nome, email, role, tenantid, active`

	rows, err := r.pool.Query(ctx, query, nome, email, password, role, tenantID, true)
	if err != nil {
		return nil, fmt.Errorf("create usuario: %w", err)
	}
	defer rows.Close()

	usuarios := make([]UserListItem, 0)
	for rows.Next() {
		var id, nomeDB, emailDB, roleDB, tenantIDDB string
		var active bool
		if err := rows.Scan(&id, &nomeDB, &emailDB, &roleDB, &tenantIDDB, &active); err != nil {
			return nil, fmt.Errorf("scan created usuario: %w", err)
		}

		usuarios = append(usuarios, UserListItem{ID: id, Nome: nomeDB, Email: emailDB, Role: roleDB, TenantID: tenantIDDB, Active: active})
	}

	return usuarios, nil
}

func (r *UserRepository) Update(ctx context.Context, id, nome, email, role, tenantID string) ([]UserListItem, error) {
	const query = `
		UPDATE public.usuario
		SET nome = $1,
			email = $2,
			role = $3,
			tenantid = $4
		WHERE id = $5
		RETURNING id, nome, email, role, tenantid, active`

	rows, err := r.pool.Query(ctx, query, nome, email, role, tenantID, id)
	if err != nil {
		return nil, fmt.Errorf("update usuario: %w", err)
	}
	defer rows.Close()

	usuarios := make([]UserListItem, 0)
	for rows.Next() {
		var idDB, nomeDB, emailDB, roleDB, tenantIDDB string
		var active bool
		if err := rows.Scan(&idDB, &nomeDB, &emailDB, &roleDB, &tenantIDDB, &active); err != nil {
			return nil, fmt.Errorf("scan updated usuario: %w", err)
		}

		usuarios = append(usuarios, UserListItem{ID: idDB, Nome: nomeDB, Email: emailDB, Role: roleDB, TenantID: tenantIDDB, Active: active})
	}

	return usuarios, nil
}

func (r *UserRepository) Delete(ctx context.Context, id string) ([]UserListItem, error) {
	const query = `
		UPDATE public.usuario
		SET active = false
		WHERE id = $1
		RETURNING id, nome, email, role, tenantid, active`

	rows, err := r.pool.Query(ctx, query, id)
	if err != nil {
		return nil, fmt.Errorf("delete usuario: %w", err)
	}
	defer rows.Close()

	usuarios := make([]UserListItem, 0)
	for rows.Next() {
		var idDB, nomeDB, emailDB, roleDB, tenantIDDB string
		var active bool
		if err := rows.Scan(&idDB, &nomeDB, &emailDB, &roleDB, &tenantIDDB, &active); err != nil {
			return nil, fmt.Errorf("scan deleted usuario: %w", err)
		}

		usuarios = append(usuarios, UserListItem{ID: idDB, Nome: nomeDB, Email: emailDB, Role: roleDB, TenantID: tenantIDDB, Active: active})
	}

	return usuarios, nil
}

func (r *UserRepository) UpdatePassword(ctx context.Context, userID, passwordHash string) error {
	const query = `
		UPDATE public.usuario
		SET password = $1
		WHERE id = $2`

	if _, err := r.pool.Exec(ctx, query, passwordHash, userID); err != nil {
		return fmt.Errorf("update usuario password: %w", err)
	}

	return nil
}
