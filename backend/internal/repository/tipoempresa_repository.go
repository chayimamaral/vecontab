package repository

import (
	"context"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

type TipoEmpresa struct {
	ID        string  `json:"id"`
	Descricao string  `json:"descricao"`
	Capital   float64 `json:"capital"`
	Anual     float64 `json:"anual"`
	Ativo     bool    `json:"ativo,omitempty"`
}

type TipoEmpresaLiteItem struct {
	ID        string `json:"id"`
	Descricao string `json:"descricao"`
}

type TipoEmpresaListParams struct {
	First     int
	Rows      int
	SortField string
	SortOrder int
	Descricao string
}

type TipoEmpresaRepository struct {
	pool *pgxpool.Pool
}

func NewTipoEmpresaRepository(pool *pgxpool.Pool) *TipoEmpresaRepository {
	return &TipoEmpresaRepository{pool: pool}
}

func (r *TipoEmpresaRepository) List(ctx context.Context, params TipoEmpresaListParams) ([]TipoEmpresa, int64, error) {
	orderBy := "descricao ASC"
	allowed := map[string]string{
		"descricao": "descricao",
		"capital":   "capital",
		"anual":     "anual",
		"id":        "id",
	}
	if field, ok := allowed[params.SortField]; ok {
		direction := "DESC"
		if params.SortOrder == -1 {
			direction = "ASC"
		}
		orderBy = field + " " + direction
	}

	whereParts := []string{"ativo = true"}
	args := []any{}
	argIndex := 1

	if descricao := strings.TrimSpace(params.Descricao); descricao != "" {
		whereParts = append(whereParts, fmt.Sprintf("descricao ILIKE $%d", argIndex))
		args = append(args, "%"+descricao+"%")
		argIndex++
	}

	whereClause := strings.Join(whereParts, " AND ")
	args = append(args, params.Rows, params.First)

	query := fmt.Sprintf(
		"SELECT id, descricao, COALESCE(capital, 0), COALESCE(anual, 0), ativo FROM public.tipoempresa WHERE %s ORDER BY %s LIMIT $%d OFFSET $%d",
		whereClause,
		orderBy,
		argIndex,
		argIndex+1,
	)

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list tipoempresa: %w", err)
	}
	defer rows.Close()

	tipos := make([]TipoEmpresa, 0)
	for rows.Next() {
		var t TipoEmpresa
		if err := rows.Scan(&t.ID, &t.Descricao, &t.Capital, &t.Anual, &t.Ativo); err != nil {
			return nil, 0, fmt.Errorf("scan tipoempresa: %w", err)
		}
		tipos = append(tipos, t)
	}

	var total int64
	countQuery := fmt.Sprintf("SELECT count(*) FROM public.tipoempresa WHERE %s", whereClause)
	countArgs := args[:len(args)-2]
	if err := r.pool.QueryRow(ctx, countQuery, countArgs...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count tipoempresa: %w", err)
	}

	return tipos, total, nil
}

func (r *TipoEmpresaRepository) Create(ctx context.Context, descricao string, capital, anual float64) ([]TipoEmpresa, int64, error) {
	const query = `
		INSERT INTO public.tipoempresa (descricao, capital, anual)
		VALUES ($1, $2, $3)
		RETURNING id, descricao, capital, anual, ativo`

	rows, err := r.pool.Query(ctx, query, descricao, capital, anual)
	if err != nil {
		return nil, 0, fmt.Errorf("create tipoempresa: %w", err)
	}
	defer rows.Close()

	tipos := make([]TipoEmpresa, 0)
	for rows.Next() {
		var t TipoEmpresa
		if err := rows.Scan(&t.ID, &t.Descricao, &t.Capital, &t.Anual, &t.Ativo); err != nil {
			return nil, 0, fmt.Errorf("scan created tipoempresa: %w", err)
		}
		tipos = append(tipos, t)
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.tipoempresa WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count tipoempresa: %w", err)
	}

	return tipos, total, nil
}

func (r *TipoEmpresaRepository) Update(ctx context.Context, id, descricao string, capital, anual float64) ([]TipoEmpresa, int64, error) {
	const query = `
		UPDATE public.tipoempresa
		SET descricao = $1, capital = $2, anual = $3
		WHERE id = $4
		RETURNING id, descricao, capital, anual, ativo`

	rows, err := r.pool.Query(ctx, query, descricao, capital, anual, id)
	if err != nil {
		return nil, 0, fmt.Errorf("update tipoempresa: %w", err)
	}
	defer rows.Close()

	tipos := make([]TipoEmpresa, 0)
	for rows.Next() {
		var t TipoEmpresa
		if err := rows.Scan(&t.ID, &t.Descricao, &t.Capital, &t.Anual, &t.Ativo); err != nil {
			return nil, 0, fmt.Errorf("scan updated tipoempresa: %w", err)
		}
		tipos = append(tipos, t)
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.tipoempresa WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count tipoempresa: %w", err)
	}

	return tipos, total, nil
}

func (r *TipoEmpresaRepository) Delete(ctx context.Context, id string) ([]TipoEmpresa, int64, error) {
	const query = `
		UPDATE public.tipoempresa
		SET ativo = false
		WHERE id = $1
		RETURNING id, descricao, capital, anual, ativo`

	rows, err := r.pool.Query(ctx, query, id)
	if err != nil {
		return nil, 0, fmt.Errorf("delete tipoempresa: %w", err)
	}
	defer rows.Close()

	tipos := make([]TipoEmpresa, 0)
	for rows.Next() {
		var t TipoEmpresa
		if err := rows.Scan(&t.ID, &t.Descricao, &t.Capital, &t.Anual, &t.Ativo); err != nil {
			return nil, 0, fmt.Errorf("scan deleted tipoempresa: %w", err)
		}
		tipos = append(tipos, t)
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.tipoempresa WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count tipoempresa: %w", err)
	}

	return tipos, total, nil
}

func (r *TipoEmpresaRepository) Lite(ctx context.Context) ([]TipoEmpresaLiteItem, error) {
	const query = `SELECT id, descricao FROM public.tipoempresa WHERE ativo = true ORDER BY descricao ASC`

	rows, err := r.pool.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("lite tipoempresa: %w", err)
	}
	defer rows.Close()

	tipos := make([]TipoEmpresaLiteItem, 0)
	for rows.Next() {
		var id, descricao string
		if err := rows.Scan(&id, &descricao); err != nil {
			return nil, fmt.Errorf("scan lite tipoempresa: %w", err)
		}

		tipos = append(tipos, TipoEmpresaLiteItem{ID: id, Descricao: descricao})
	}

	return tipos, nil
}
