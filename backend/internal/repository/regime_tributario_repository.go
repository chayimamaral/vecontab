package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type RegimeTributarioListParams struct {
	First     int
	Rows      int
	SortField string
	SortOrder int
	Nome      string
}

type RegimeTributarioRepository struct {
	pool *pgxpool.Pool
}

func NewRegimeTributarioRepository(pool *pgxpool.Pool) *RegimeTributarioRepository {
	return &RegimeTributarioRepository{pool: pool}
}

func (r *RegimeTributarioRepository) List(ctx context.Context, params RegimeTributarioListParams) ([]domain.RegimeTributario, int64, error) {
	whereParts := []string{"r.ativo = true"}
	args := []any{}
	argIndex := 1

	if strings.TrimSpace(params.Nome) != "" {
		whereParts = append(whereParts, fmt.Sprintf("r.nome ILIKE $%d", argIndex))
		args = append(args, "%"+strings.TrimSpace(params.Nome)+"%")
		argIndex++
	}

	dir := "ASC"
	if params.SortOrder == -1 {
		dir = "DESC"
	}
	orderBy := "r.nome ASC"
	switch params.SortField {
	case "codigo_crt":
		orderBy = fmt.Sprintf("r.codigo_crt %s", dir)
	case "tipo_apuracao":
		orderBy = fmt.Sprintf("r.tipo_apuracao::text %s", dir)
	case "nome":
		orderBy = fmt.Sprintf("r.nome %s", dir)
	}

	whereClause := strings.Join(whereParts, " AND ")
	listQuery := fmt.Sprintf(`
		SELECT r.id, r.nome, r.codigo_crt, r.tipo_apuracao::text, r.ativo, r.configuracao_json
		FROM public.regime_tributario r
		WHERE %s
		ORDER BY %s
		LIMIT $%d OFFSET $%d`, whereClause, orderBy, argIndex, argIndex+1)
	args = append(args, params.Rows, params.First)

	rows, err := r.pool.Query(ctx, listQuery, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list regime_tributario: %w", err)
	}
	defer rows.Close()

	out := make([]domain.RegimeTributario, 0)
	for rows.Next() {
		var rec domain.RegimeTributario
		var cfg []byte
		if err := rows.Scan(&rec.ID, &rec.Nome, &rec.CodigoCRT, &rec.TipoApuracao, &rec.Ativo, &cfg); err != nil {
			return nil, 0, fmt.Errorf("scan regime_tributario: %w", err)
		}
		if len(cfg) > 0 {
			rec.ConfiguracaoJSON = json.RawMessage(cfg)
		} else {
			rec.ConfiguracaoJSON = json.RawMessage(`{}`)
		}
		out = append(out, rec)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("list regime_tributario rows: %w", err)
	}

	countQuery := fmt.Sprintf(`SELECT count(*) FROM public.regime_tributario r WHERE %s`, whereClause)
	var total int64
	if err := r.pool.QueryRow(ctx, countQuery, args[:len(args)-2]...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count regime_tributario: %w", err)
	}

	return out, total, nil
}

func (r *RegimeTributarioRepository) Create(ctx context.Context, nome string, codigoCRT int, tipoApuracao string, ativo bool, configuracaoJSON []byte) ([]domain.RegimeTributario, int64, error) {
	const query = `
		INSERT INTO public.regime_tributario (nome, codigo_crt, tipo_apuracao, ativo, configuracao_json)
		VALUES ($1, $2, $3::public.tipo_apuracao_regime, $4, $5::jsonb)
		RETURNING id, nome, codigo_crt, tipo_apuracao::text, ativo, configuracao_json`

	rows, err := r.pool.Query(ctx, query, nome, codigoCRT, tipoApuracao, ativo, configuracaoJSON)
	if err != nil {
		return nil, 0, fmt.Errorf("create regime_tributario: %w", err)
	}
	defer rows.Close()

	return scanRegimeRowsAndCount(rows)
}

func (r *RegimeTributarioRepository) Update(ctx context.Context, id, nome string, codigoCRT int, tipoApuracao string, ativo bool, configuracaoJSON []byte) ([]domain.RegimeTributario, int64, error) {
	const query = `
		UPDATE public.regime_tributario
		SET nome = $1, codigo_crt = $2, tipo_apuracao = $3::public.tipo_apuracao_regime, ativo = $4, configuracao_json = $5::jsonb
		WHERE id = $6
		RETURNING id, nome, codigo_crt, tipo_apuracao::text, ativo, configuracao_json`

	rows, err := r.pool.Query(ctx, query, nome, codigoCRT, tipoApuracao, ativo, configuracaoJSON, id)
	if err != nil {
		return nil, 0, fmt.Errorf("update regime_tributario: %w", err)
	}
	defer rows.Close()

	return scanRegimeRowsAndCount(rows)
}

func (r *RegimeTributarioRepository) Delete(ctx context.Context, id string) ([]domain.RegimeTributario, int64, error) {
	const query = `
		UPDATE public.regime_tributario
		SET ativo = false
		WHERE id = $1
		RETURNING id, nome, codigo_crt, tipo_apuracao::text, ativo, configuracao_json`

	rows, err := r.pool.Query(ctx, query, id)
	if err != nil {
		return nil, 0, fmt.Errorf("delete regime_tributario: %w", err)
	}
	defer rows.Close()

	return scanRegimeRowsAndCount(rows)
}

func scanRegimeRowsAndCount(rows pgx.Rows) ([]domain.RegimeTributario, int64, error) {
	out := make([]domain.RegimeTributario, 0)
	for rows.Next() {
		var rec domain.RegimeTributario
		var cfg []byte
		if err := rows.Scan(&rec.ID, &rec.Nome, &rec.CodigoCRT, &rec.TipoApuracao, &rec.Ativo, &cfg); err != nil {
			return nil, 0, fmt.Errorf("scan regime_tributario: %w", err)
		}
		if len(cfg) > 0 {
			rec.ConfiguracaoJSON = json.RawMessage(cfg)
		} else {
			rec.ConfiguracaoJSON = json.RawMessage(`{}`)
		}
		out = append(out, rec)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return out, int64(len(out)), nil
}
