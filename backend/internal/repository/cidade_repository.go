package repository

import (
	"context"
	"fmt"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5/pgxpool"
)

type CidadeListParams struct {
	First     int
	Rows      int
	SortField string
	SortOrder int
	Nome      string
}

type CidadeRepository struct {
	pool *pgxpool.Pool
}

func NewCidadeRepository(pool *pgxpool.Pool) *CidadeRepository {
	return &CidadeRepository{pool: pool}
}

func (r *CidadeRepository) List(ctx context.Context, params CidadeListParams) ([]domain.CidadeListItem, int64, error) {
	whereParts := []string{"c.ativo = true", "e.ativo = true"}
	args := []any{}
	argIndex := 1

	if strings.TrimSpace(params.Nome) != "" {
		whereParts = append(whereParts, fmt.Sprintf("c.nome ILIKE $%d", argIndex))
		args = append(args, "%"+strings.TrimSpace(params.Nome)+"%")
		argIndex++
	}

	orderBy := "c.nome ASC"
	switch params.SortField {
	case "estado":
		if params.SortOrder == -1 {
			orderBy = "e.nome DESC"
		} else {
			orderBy = "e.nome ASC"
		}
	case "nome":
		if params.SortOrder == -1 {
			orderBy = "c.nome DESC"
		} else {
			orderBy = "c.nome ASC"
		}
	case "codigo":
		if params.SortOrder == -1 {
			orderBy = "c.codigo DESC"
		} else {
			orderBy = "c.codigo ASC"
		}
	}

	listQuery := fmt.Sprintf(`
		SELECT
			c.id,
			c.nome,
			c.codigo,
			c.ufid,
			e.id,
			e.nome
		FROM public.municipio c
		JOIN public.estado e ON c.ufid = e.id
		WHERE %s
		ORDER BY %s
		LIMIT $%d OFFSET $%d`, strings.Join(whereParts, " AND "), orderBy, argIndex, argIndex+1)
	args = append(args, params.Rows, params.First)

	rows, err := r.pool.Query(ctx, listQuery, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list cidades: %w", err)
	}
	defer rows.Close()

	municipios := make([]domain.CidadeListItem, 0)
	for rows.Next() {
		var c domain.Cidade
		if err := rows.Scan(&c.ID, &c.Nome, &c.Codigo, &c.UfID, &c.Uf.ID, &c.Uf.Nome); err != nil {
			return nil, 0, fmt.Errorf("scan cidade: %w", err)
		}

		municipios = append(municipios, domain.CidadeListItem{
			ID:     c.ID,
			Nome:   c.Nome,
			Codigo: c.Codigo,
			UfID:   c.UfID,
			Uf: domain.UfLite{
				ID:   c.Uf.ID,
				Nome: c.Uf.Nome,
			},
		})
	}

	countQuery := fmt.Sprintf("SELECT count(*) FROM public.municipio c JOIN public.estado e ON c.ufid = e.id WHERE %s", strings.Join(whereParts, " AND "))
	var total int64
	if err := r.pool.QueryRow(ctx, countQuery, args[:len(args)-2]...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count cidades: %w", err)
	}

	return municipios, total, nil
}

func (r *CidadeRepository) Create(ctx context.Context, nome, codigo, ufID string) ([]domain.Cidade, int64, error) {
	const existsQuery = `SELECT count(*) FROM public.municipio WHERE nome = $1`
	var count int64
	if err := r.pool.QueryRow(ctx, existsQuery, nome).Scan(&count); err != nil {
		return nil, 0, fmt.Errorf("check cidade exists: %w", err)
	}

	if count > 0 {
		return nil, 0, fmt.Errorf("Municipio ja cadastrado")
	}

	const query = `
		INSERT INTO public.municipio (nome, codigo, ufid)
		VALUES ($1, $2, $3)
		RETURNING id, nome, codigo, ufid, ativo`

	rows, err := r.pool.Query(ctx, query, nome, codigo, ufID)
	if err != nil {
		return nil, 0, fmt.Errorf("create cidade: %w", err)
	}
	defer rows.Close()

	cidades := make([]domain.Cidade, 0)
	for rows.Next() {
		var c domain.Cidade
		if err := rows.Scan(&c.ID, &c.Nome, &c.Codigo, &c.UfID, &c.Ativo); err != nil {
			return nil, 0, fmt.Errorf("scan created cidade: %w", err)
		}
		cidades = append(cidades, c)
	}

	return cidades, int64(len(cidades)), nil
}

func (r *CidadeRepository) Update(ctx context.Context, id, nome, codigo, ufID string) ([]domain.Cidade, int64, error) {
	const query = `
		UPDATE public.municipio
		SET nome = $1, codigo = $2, ufid = $3
		WHERE id = $4
		RETURNING id, nome, codigo, ufid, ativo`

	rows, err := r.pool.Query(ctx, query, nome, codigo, ufID, id)
	if err != nil {
		return nil, 0, fmt.Errorf("update cidade: %w", err)
	}
	defer rows.Close()

	cidades := make([]domain.Cidade, 0)
	for rows.Next() {
		var c domain.Cidade
		if err := rows.Scan(&c.ID, &c.Nome, &c.Codigo, &c.UfID, &c.Ativo); err != nil {
			return nil, 0, fmt.Errorf("scan updated cidade: %w", err)
		}
		cidades = append(cidades, c)
	}

	return cidades, int64(len(cidades)), nil
}

func (r *CidadeRepository) Delete(ctx context.Context, id string) ([]domain.Cidade, int64, error) {
	const query = `
		UPDATE public.municipio
		SET ativo = false
		WHERE id = $1
		RETURNING id, nome, codigo, ufid, ativo`

	rows, err := r.pool.Query(ctx, query, id)
	if err != nil {
		return nil, 0, fmt.Errorf("delete cidade: %w", err)
	}
	defer rows.Close()

	cidades := make([]domain.Cidade, 0)
	for rows.Next() {
		var c domain.Cidade
		if err := rows.Scan(&c.ID, &c.Nome, &c.Codigo, &c.UfID, &c.Ativo); err != nil {
			return nil, 0, fmt.Errorf("scan deleted cidade: %w", err)
		}
		cidades = append(cidades, c)
	}

	return cidades, int64(len(cidades)), nil
}

func (r *CidadeRepository) ListLite(ctx context.Context) ([]domain.CidadeLiteItem, error) {
	const query = `
		SELECT c.id, c.nome, e.sigla
		FROM public.municipio c
		LEFT JOIN public.estado e ON e.id = c.ufid
		WHERE c.ativo = true
		ORDER BY c.nome ASC`

	rows, err := r.pool.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("list cidadeslite: %w", err)
	}
	defer rows.Close()

	municipios := make([]domain.CidadeLiteItem, 0)
	for rows.Next() {
		var id, nome, sigla string
		if err := rows.Scan(&id, &nome, &sigla); err != nil {
			return nil, fmt.Errorf("scan cidadeslite: %w", err)
		}

		municipios = append(municipios, domain.CidadeLiteItem{ID: id, Nome: fmt.Sprintf("%s / %s", nome, sigla)})
	}

	return municipios, nil
}
