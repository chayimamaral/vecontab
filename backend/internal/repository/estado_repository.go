package repository

import (
	"context"
	"fmt"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5/pgxpool"
)

type EstadoListParams struct {
	First     int
	Rows      int
	SortField string
	SortOrder int
	Nome      string
}

type EstadoRepository struct {
	pool *pgxpool.Pool
}

func NewEstadoRepository(pool *pgxpool.Pool) *EstadoRepository {
	return &EstadoRepository{pool: pool}
}

func (r *EstadoRepository) List(ctx context.Context, params EstadoListParams) ([]domain.Estado, int64, error) {
	whereParts := []string{"ativo = true"}
	args := []any{}
	argIndex := 1

	if strings.TrimSpace(params.Nome) != "" {
		whereParts = append(whereParts, fmt.Sprintf("nome ILIKE $%d", argIndex))
		args = append(args, "%"+strings.TrimSpace(params.Nome)+"%")
		argIndex++
	}

	allowedSortFields := map[string]string{
		"id":    "id",
		"nome":  "nome",
		"sigla": "sigla",
	}

	orderBy := "nome ASC"
 	if field, ok := allowedSortFields[params.SortField]; ok {
 		direction := "ASC"
 		if params.SortOrder == -1 {
 			direction = "DESC"
 		}
 		orderBy = field + " " + direction
 	}

	listQuery := fmt.Sprintf(
		"SELECT id, nome, sigla, ativo FROM public.estado WHERE %s ORDER BY %s LIMIT $%d OFFSET $%d",
		strings.Join(whereParts, " AND "),
		orderBy,
		argIndex,
		argIndex+1,
	)
	args = append(args, params.Rows, params.First)

	rows, err := r.pool.Query(ctx, listQuery, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list estados: %w", err)
	}
	defer rows.Close()

	var estados []domain.Estado
	for rows.Next() {
		var estado domain.Estado
		if err := rows.Scan(&estado.ID, &estado.Nome, &estado.Sigla, &estado.Ativo); err != nil {
			return nil, 0, fmt.Errorf("scan estado: %w", err)
		}
		estados = append(estados, estado)
	}

	countQuery := fmt.Sprintf("SELECT count(*) FROM public.estado WHERE %s", strings.Join(whereParts, " AND "))
	var totalRecords int64
	if err := r.pool.QueryRow(ctx, countQuery, args[:len(args)-2]...).Scan(&totalRecords); err != nil {
		return nil, 0, fmt.Errorf("count estados: %w", err)
	}

	return estados, totalRecords, nil
}

func (r *EstadoRepository) Create(ctx context.Context, nome, sigla string) ([]domain.Estado, int64, error) {
	const insertQuery = `INSERT INTO public.estado (nome, sigla) VALUES ($1, $2) RETURNING id, nome, sigla, ativo`

	rows, err := r.pool.Query(ctx, insertQuery, nome, sigla)
	if err != nil {
		return nil, 0, fmt.Errorf("create estado: %w", err)
	}
	defer rows.Close()

	var estados []domain.Estado
	for rows.Next() {
		var estado domain.Estado
		if err := rows.Scan(&estado.ID, &estado.Nome, &estado.Sigla, &estado.Ativo); err != nil {
			return nil, 0, fmt.Errorf("scan created estado: %w", err)
		}
		estados = append(estados, estado)
	}

	totalRecords, err := r.countActive(ctx)
	if err != nil {
		return nil, 0, err
	}

	return estados, totalRecords, nil
}

func (r *EstadoRepository) Update(ctx context.Context, id, nome, sigla string) ([]domain.Estado, int64, error) {
	const query = `UPDATE public.estado SET nome = $1, sigla = $2 WHERE id = $3 RETURNING id, nome, sigla, ativo`

	rows, err := r.pool.Query(ctx, query, nome, sigla, id)
	if err != nil {
		return nil, 0, fmt.Errorf("update estado: %w", err)
	}
	defer rows.Close()

	var estados []domain.Estado
	for rows.Next() {
		var estado domain.Estado
		if err := rows.Scan(&estado.ID, &estado.Nome, &estado.Sigla, &estado.Ativo); err != nil {
			return nil, 0, fmt.Errorf("scan updated estado: %w", err)
		}
		estados = append(estados, estado)
	}

	totalRecords, err := r.countActive(ctx)
	if err != nil {
		return nil, 0, err
	}

	return estados, totalRecords, nil
}

func (r *EstadoRepository) Delete(ctx context.Context, id string) ([]domain.Estado, int64, error) {
	const query = `UPDATE public.estado SET ativo = false WHERE id = $1 RETURNING id, nome, sigla, ativo`

	rows, err := r.pool.Query(ctx, query, id)
	if err != nil {
		return nil, 0, fmt.Errorf("delete estado: %w", err)
	}
	defer rows.Close()

	var estados []domain.Estado
	for rows.Next() {
		var estado domain.Estado
		if err := rows.Scan(&estado.ID, &estado.Nome, &estado.Sigla, &estado.Ativo); err != nil {
			return nil, 0, fmt.Errorf("scan deleted estado: %w", err)
		}
		estados = append(estados, estado)
	}

	totalRecords, err := r.countActive(ctx)
	if err != nil {
		return nil, 0, err
	}

	return estados, totalRecords, nil
}

func (r *EstadoRepository) ListLite(ctx context.Context) ([]domain.Estado, error) {
	const query = `SELECT id, nome FROM public.estado WHERE ativo = true ORDER BY nome ASC`

	rows, err := r.pool.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("list lite estados: %w", err)
	}
	defer rows.Close()

	var estados []domain.Estado
	for rows.Next() {
		var estado domain.Estado
		if err := rows.Scan(&estado.ID, &estado.Nome); err != nil {
			return nil, fmt.Errorf("scan lite estado: %w", err)
		}
		estados = append(estados, estado)
	}

	return estados, nil
}

func (r *EstadoRepository) countActive(ctx context.Context) (int64, error) {
	const query = `SELECT count(*) FROM public.estado WHERE ativo = true`

	var total int64
	if err := r.pool.QueryRow(ctx, query).Scan(&total); err != nil {
		return 0, fmt.Errorf("count active estados: %w", err)
	}

	return total, nil
}
