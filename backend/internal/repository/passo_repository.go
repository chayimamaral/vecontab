package repository

import (
	"context"
	"fmt"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PassoListParams struct {
	First       int
	Rows        int
	SortField   string
	SortOrder   int
	Descricao   string
	MunicipioID string
}

type PassoCidadeParams struct {
	MunicipioID string
	RotinaID    string
}

type PassoRepository struct {
	pool *pgxpool.Pool
}

func NewPassoRepository(pool *pgxpool.Pool) *PassoRepository {
	return &PassoRepository{pool: pool}
}

func (r *PassoRepository) List(ctx context.Context, params PassoListParams) ([]domain.PassoListItem, int64, error) {
	whereParts := []string{"p.ativo = true"}
	args := []any{}
	argIndex := 1

	if strings.TrimSpace(params.Descricao) != "" {
		whereParts = append(whereParts, fmt.Sprintf("p.descricao ILIKE $%d", argIndex))
		args = append(args, "%"+strings.TrimSpace(params.Descricao)+"%")
		argIndex++
	}

	if strings.TrimSpace(params.MunicipioID) != "" {
		whereParts = append(whereParts, fmt.Sprintf("p.municipio_id = $%d", argIndex))
		args = append(args, strings.TrimSpace(params.MunicipioID))
		argIndex++
	}

	orderBy := "p.descricao ASC"
	allowed := map[string]string{
		"descricao":     "p.descricao",
		"tempoestimado": "p.tempoestimado",
		"tipopasso":     "p.tipopasso",
	}
	if field, ok := allowed[params.SortField]; ok {
		direction := "DESC"
		if params.SortOrder == -1 {
			direction = "ASC"
		}
		orderBy = field + " " + direction
	}

	query := fmt.Sprintf(`
		SELECT
			p.id,
			p.descricao,
			p.tempoestimado,
			p.tipopasso,
			p.municipio_id,
			COALESCE(l.link, ''),
			m.id,
			m.nome,
			e.sigla
		FROM public.passos p
		LEFT JOIN public.linkpassos l ON l.passo_id = p.id
		JOIN public.municipio m ON m.id = p.municipio_id
		JOIN public.estado e ON e.id = m.ufid
		WHERE %s
		ORDER BY %s
		LIMIT $%d OFFSET $%d`, strings.Join(whereParts, " AND "), orderBy, argIndex, argIndex+1)
	args = append(args, params.Rows, params.First)

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list passos: %w", err)
	}
	defer rows.Close()

	passos := make([]domain.PassoListItem, 0)
	for rows.Next() {
		var id, descricao, tipoPasso, municipioID, link, mid, mnome, sigla string
		var tempo int
		if err := rows.Scan(&id, &descricao, &tempo, &tipoPasso, &municipioID, &link, &mid, &mnome, &sigla); err != nil {
			return nil, 0, fmt.Errorf("scan passo: %w", err)
		}

		passos = append(passos, domain.PassoListItem{
			ID:          id,
			Descricao:   descricao,
			Tempo:       tempo,
			TipoPasso:   tipoPasso,
			Link:        link,
			MunicipioID: municipioID,
			Municipio:   domain.PassoMunicipioRef{ID: mid, Nome: mnome + " / " + sigla},
		})
	}

	countQuery := fmt.Sprintf("SELECT count(*) FROM public.passos p WHERE %s", strings.Join(whereParts, " AND "))
	var total int64
	if err := r.pool.QueryRow(ctx, countQuery, args[:len(args)-2]...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count passos: %w", err)
	}

	return passos, total, nil
}

func (r *PassoRepository) Create(ctx context.Context, descricao string, tempo int, tipoPasso, municipioID, link string) ([]domain.PassoMutationItem, int64, error) {
	const query = `
		INSERT INTO public.passos (descricao, tempoestimado, tipopasso, municipio_id)
		VALUES ($1, $2, $3, $4)
		RETURNING id, descricao, tempoestimado, tipopasso, municipio_id, ativo`

	rows, err := r.pool.Query(ctx, query, descricao, tempo, tipoPasso, municipioID)
	if err != nil {
		return nil, 0, fmt.Errorf("create passo: %w", err)
	}
	defer rows.Close()

	passos := make([]domain.PassoMutationItem, 0)
	var createdID string
	for rows.Next() {
		var id, d, t, m string
		var te int
		var active bool
		if err := rows.Scan(&id, &d, &te, &t, &m, &active); err != nil {
			return nil, 0, fmt.Errorf("scan created passo: %w", err)
		}
		createdID = id
		passos = append(passos, domain.PassoMutationItem{ID: id, Descricao: d, Tempo: te, TipoPasso: t, MunicipioID: m, Active: active})
	}

	if strings.TrimSpace(link) != "" && createdID != "" {
		_, _ = r.pool.Exec(ctx, `INSERT INTO public.linkpassos (link, passo_id) VALUES ($1, $2)`, link, createdID)
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.passos WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count passos: %w", err)
	}

	return passos, total, nil
}

func (r *PassoRepository) Update(ctx context.Context, id, descricao string, tempo int, tipoPasso, municipioID, link string) ([]domain.PassoMutationItem, int64, error) {
	const query = `
		UPDATE public.passos
		SET descricao = $1, tempoestimado = $2, tipopasso = $3, municipio_id = $4
		WHERE id = $5
		RETURNING id, descricao, tempoestimado, tipopasso, municipio_id, ativo`

	rows, err := r.pool.Query(ctx, query, descricao, tempo, tipoPasso, municipioID, id)
	if err != nil {
		return nil, 0, fmt.Errorf("update passo: %w", err)
	}
	defer rows.Close()

	passos := make([]domain.PassoMutationItem, 0)
	for rows.Next() {
		var pid, d, t, m string
		var te int
		var active bool
		if err := rows.Scan(&pid, &d, &te, &t, &m, &active); err != nil {
			return nil, 0, fmt.Errorf("scan updated passo: %w", err)
		}
		passos = append(passos, domain.PassoMutationItem{ID: pid, Descricao: d, Tempo: te, TipoPasso: t, MunicipioID: m, Active: active})
	}

	if strings.TrimSpace(link) != "" {
		_, _ = r.pool.Exec(ctx, `
			INSERT INTO public.linkpassos (passo_id, link)
			VALUES ($1, $2)
			ON CONFLICT (passo_id)
			DO UPDATE SET link = $2`, id, link)
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.passos WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count passos: %w", err)
	}

	return passos, total, nil
}

func (r *PassoRepository) Delete(ctx context.Context, id string) ([]domain.PassoMutationItem, int64, error) {
	const query = `
		UPDATE public.passos
		SET ativo = false
		WHERE id = $1
		RETURNING id, descricao, tempoestimado, tipopasso, municipio_id, ativo`

	rows, err := r.pool.Query(ctx, query, id)
	if err != nil {
		return nil, 0, fmt.Errorf("delete passo: %w", err)
	}
	defer rows.Close()

	passos := make([]domain.PassoMutationItem, 0)
	for rows.Next() {
		var pid, d, t, m string
		var te int
		var active bool
		if err := rows.Scan(&pid, &d, &te, &t, &m, &active); err != nil {
			return nil, 0, fmt.Errorf("scan deleted passo: %w", err)
		}
		passos = append(passos, domain.PassoMutationItem{ID: pid, Descricao: d, Tempo: te, TipoPasso: t, MunicipioID: m, Active: active})
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.passos WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count passos: %w", err)
	}

	return passos, total, nil
}

func (r *PassoRepository) GetByID(ctx context.Context, id string) ([]domain.PassoDetailItem, int64, error) {
	const query = `
		SELECT p.id, p.descricao, p.tempoestimado, p.tipopasso, p.municipio_id, COALESCE(l.link, '')
		FROM public.passos p
		LEFT JOIN public.linkpassos l ON l.passo_id = p.id
		WHERE p.id = $1`

	rows, err := r.pool.Query(ctx, query, id)
	if err != nil {
		return nil, 0, fmt.Errorf("get passo by id: %w", err)
	}
	defer rows.Close()

	passos := make([]domain.PassoDetailItem, 0)
	for rows.Next() {
		var pid, d, t, m, link string
		var te int
		if err := rows.Scan(&pid, &d, &te, &t, &m, &link); err != nil {
			return nil, 0, fmt.Errorf("scan passo by id: %w", err)
		}
		passos = append(passos, domain.PassoDetailItem{ID: pid, Descricao: d, Tempo: te, TipoPasso: t, MunicipioID: m, Link: link})
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.passos WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count passos: %w", err)
	}

	return passos, total, nil
}

func (r *PassoRepository) ListByCidade(ctx context.Context, params PassoCidadeParams) ([]domain.PassoCidadeItem, int64, error) {
	if strings.TrimSpace(params.MunicipioID) == "" || strings.TrimSpace(params.RotinaID) == "" {
		return []domain.PassoCidadeItem{}, 0, nil
	}

	const query = `
		SELECT DISTINCT ON (p.id)
			p.id,
			p.descricao,
			p.tempoestimado,
			p.tipopasso,
			COALESCE(ri.rotina_id::text, ''),
			ri.ordem,
			COALESCE(l.link, '')
		FROM public.passos p
		LEFT JOIN public.linkpassos l ON l.passo_id = p.id
		LEFT JOIN public.rotinaitens ri ON ri.passo_id = p.id
		WHERE p.ativo = true
			AND p.municipio_id = $1
			AND NOT EXISTS (
				SELECT 1
				FROM public.rotinaitens ri2
				WHERE ri2.passo_id = p.id
					AND ri2.rotina_id = $2
			)
		ORDER BY p.id, p.descricao ASC`

	rows, err := r.pool.Query(ctx, query, params.MunicipioID, params.RotinaID)
	if err != nil {
		return nil, 0, fmt.Errorf("list passos por cidade: %w", err)
	}
	defer rows.Close()

	passos := make([]domain.PassoCidadeItem, 0)
	for rows.Next() {
		var id, descricao, tipoPasso, rotinaID, link string
		var tempo int
		var ordem any
		if err := rows.Scan(&id, &descricao, &tempo, &tipoPasso, &rotinaID, &ordem, &link); err != nil {
			return nil, 0, fmt.Errorf("scan passos por cidade: %w", err)
		}
		passos = append(passos, domain.PassoCidadeItem{ID: id, Descricao: descricao, Tempo: tempo, TipoPasso: tipoPasso, RotinaID: rotinaID, Ordem: ordem, Link: link})
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.passos WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count passos: %w", err)
	}

	return passos, total, nil
}
