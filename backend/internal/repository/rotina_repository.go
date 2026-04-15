package repository

import (
	"context"
	"fmt"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type RotinaListParams struct {
	First     int
	Rows      int
	SortField string
	SortOrder int
	Descricao string
	MunicipioID string
	TipoEmpresaID string
}

type RotinaInput struct {
	ID             string
	Descricao      string
	MunicipioID    string
	TipoEmpresaID  string
	Link           string
}

type RotinaPassoSelection struct {
	ID       string
	RotinaID string
	Ordem    int
}

type RotinaRepository struct {
	pool *pgxpool.Pool
}

func NewRotinaRepository(pool *pgxpool.Pool) *RotinaRepository {
	return &RotinaRepository{pool: pool}
}

func rotinaNullableTipoEmpresaID(s string) any {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return strings.TrimSpace(s)
}

func (r *RotinaRepository) List(ctx context.Context, params RotinaListParams) ([]domain.RotinaListItem, int64, error) {
	whereParts := []string{"r.ativo = true"}
	args := []any{}
	argIndex := 1

	if strings.TrimSpace(params.Descricao) != "" {
		whereParts = append(whereParts, fmt.Sprintf("r.descricao ILIKE $%d", argIndex))
		args = append(args, "%"+strings.TrimSpace(params.Descricao)+"%")
		argIndex++
	}
	if strings.TrimSpace(params.MunicipioID) != "" {
		whereParts = append(whereParts, fmt.Sprintf("r.municipio_id = $%d", argIndex))
		args = append(args, strings.TrimSpace(params.MunicipioID))
		argIndex++
	}
	if strings.TrimSpace(params.TipoEmpresaID) != "" {
		whereParts = append(whereParts, fmt.Sprintf("r.tipo_empresa_id = $%d", argIndex))
		args = append(args, strings.TrimSpace(params.TipoEmpresaID))
		argIndex++
	}

	// PrimeReact: sortOrder 1 = ascendente, -1 = descendente. Desempate estável para paginação.
	orderBy := "r.descricao ASC, r.id ASC"
	switch params.SortField {
	case "municipio":
		if params.SortOrder == -1 {
			orderBy = "m.nome DESC NULLS LAST, r.id ASC"
		} else {
			orderBy = "m.nome ASC NULLS LAST, r.id ASC"
		}
	case "descricao":
		if params.SortOrder == -1 {
			orderBy = "r.descricao DESC, r.id ASC"
		} else {
			orderBy = "r.descricao ASC, r.id ASC"
		}
	}

	query := fmt.Sprintf(`
SELECT r.id, r.descricao, r.municipio_id, COALESCE(m.id::text, ''), COALESCE(m.nome, ''), COALESCE(e.sigla, ''),
	COALESCE(r.tipo_empresa_id::text, ''), COALESCE(te.id::text, ''), COALESCE(te.descricao, '')
FROM public.rotinas r
LEFT JOIN public.municipio m ON m.id = r.municipio_id
LEFT JOIN public.estado e ON e.id = m.ufid
LEFT JOIN public.tipoempresa te ON te.id = r.tipo_empresa_id
WHERE %s
ORDER BY %s
LIMIT $%d OFFSET $%d`, strings.Join(whereParts, " AND "), orderBy, argIndex, argIndex+1)
	args = append(args, params.Rows, params.First)

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list rotinas: %w", err)
	}
	defer rows.Close()

	rotinas := make([]domain.RotinaListItem, 0)
	for rows.Next() {
		var id, descricao, municipioID, mid, mnome, sigla, tipoEmpresaID, teid, tedesc string
		if err := rows.Scan(&id, &descricao, &municipioID, &mid, &mnome, &sigla, &tipoEmpresaID, &teid, &tedesc); err != nil {
			return nil, 0, fmt.Errorf("scan rotina: %w", err)
		}

		rotinas = append(rotinas, domain.RotinaListItem{
			ID:            id,
			Descricao:     descricao,
			MunicipioID:   municipioID,
			TipoEmpresaID: tipoEmpresaID,
			Municipio: domain.RotinaMunicipioRef{
				ID:   mid,
				Nome: rotinaMunicipioExibicao(mnome, sigla),
			},
			TipoEmpresa: domain.RotinaTipoEmpresaRef{
				ID:        teid,
				Descricao: tedesc,
			},
		})
	}

	countQuery := fmt.Sprintf("SELECT count(*) FROM public.rotinas r WHERE %s", strings.Join(whereParts, " AND "))
	var total int64
	if err := r.pool.QueryRow(ctx, countQuery, args[:len(args)-2]...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count rotinas: %w", err)
	}

	return rotinas, total, nil
}

func (r *RotinaRepository) ListWithItens(ctx context.Context, params RotinaListParams) ([]domain.RotinaWithItensItem, int64, error) {
	whereParts := []string{"r.ativo = true"}
	args := []any{}
	argIndex := 1

	if strings.TrimSpace(params.Descricao) != "" {
		whereParts = append(whereParts, fmt.Sprintf("r.descricao ILIKE $%d", argIndex))
		args = append(args, "%"+strings.TrimSpace(params.Descricao)+"%")
		argIndex++
	}

	// PrimeReact: sortOrder 1 = ascendente, -1 = descendente
	orderBy := "r.descricao ASC"
	outerOrderBy := "rp.descricao ASC, ri.ordem ASC NULLS LAST"
	switch params.SortField {
	case "municipio":
		if params.SortOrder == -1 {
			orderBy = "m.nome DESC NULLS LAST"
			outerOrderBy = "rp.m_nome DESC, ri.ordem ASC NULLS LAST"
		} else {
			orderBy = "m.nome ASC NULLS LAST"
			outerOrderBy = "rp.m_nome ASC, ri.ordem ASC NULLS LAST"
		}
	case "descricao":
		if params.SortOrder == -1 {
			orderBy = "r.descricao DESC"
			outerOrderBy = "rp.descricao DESC, ri.ordem ASC NULLS LAST"
		} else {
			orderBy = "r.descricao ASC"
			outerOrderBy = "rp.descricao ASC, ri.ordem ASC NULLS LAST"
		}
	}

	// Paginar por rotina: JOIN com passos multiplica linhas; LIMIT/OFFSET devem aplicar só às rotinas.
	query := fmt.Sprintf(`
WITH rotinas_page AS (
	SELECT r.id, r.descricao, r.municipio_id, COALESCE(m.id::text, '') AS m_id, COALESCE(m.nome, '') AS m_nome, COALESCE(e.sigla, '') AS e_sigla,
		COALESCE(r.tipo_empresa_id::text, '') AS tipo_empresa_id, COALESCE(te.id::text, '') AS te_id, COALESCE(te.descricao, '') AS te_desc
	FROM public.rotinas r
	LEFT JOIN public.municipio m ON m.id = r.municipio_id
	LEFT JOIN public.estado e ON e.id = m.ufid
	LEFT JOIN public.tipoempresa te ON te.id = r.tipo_empresa_id
	WHERE %s
	ORDER BY %s
	LIMIT $%d OFFSET $%d
)
SELECT
	rp.id,
	rp.descricao,
	rp.municipio_id,
	rp.m_id,
	rp.m_nome,
	rp.e_sigla,
	rp.tipo_empresa_id,
	rp.te_id,
	rp.te_desc,
	p.id,
	p.descricao,
	p.tempoestimado,
	COALESCE(l.link, '')
FROM rotinas_page rp
LEFT JOIN public.rotinaitens ri ON ri.rotina_id = rp.id
LEFT JOIN public.passos p ON p.id = ri.passo_id
LEFT JOIN public.linkpassos l ON l.passo_id = p.id
ORDER BY %s`, strings.Join(whereParts, " AND "), orderBy, argIndex, argIndex+1, outerOrderBy)
	args = append(args, params.Rows, params.First)

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list rotinas with itens: %w", err)
	}
	defer rows.Close()

	byID := map[string]*domain.RotinaWithItensItem{}
	ordered := make([]string, 0)

	for rows.Next() {
		var id, descricao, municipioID, mid, mnome, sigla, tipoEmpresaID, teid, tedesc string
		var pid, pdesc, link *string
		var tempo *int
		if err := rows.Scan(&id, &descricao, &municipioID, &mid, &mnome, &sigla, &tipoEmpresaID, &teid, &tedesc, &pid, &pdesc, &tempo, &link); err != nil {
			return nil, 0, fmt.Errorf("scan rotina with itens: %w", err)
		}

		entry, ok := byID[id]
		if !ok {
			entry = &domain.RotinaWithItensItem{
				ID:            id,
				Descricao:     descricao,
				MunicipioID:   municipioID,
				TipoEmpresaID: tipoEmpresaID,
				Municipio: domain.RotinaMunicipioRef{
					ID:   mid,
					Nome: rotinaMunicipioExibicao(mnome, sigla),
				},
				TipoEmpresa: domain.RotinaTipoEmpresaRef{
					ID:        teid,
					Descricao: tedesc,
				},
				RotinaItens: make([]domain.RotinaPassoItem, 0),
			}
			byID[id] = entry
			ordered = append(ordered, id)
		}

		if pid != nil {
			entry.RotinaItens = append(entry.RotinaItens, domain.RotinaPassoItem{
				ID:            *pid,
				Descricao:     valueOrEmpty(pdesc),
				TempoEstimado: valueOrZero(tempo),
				Link:          valueOrEmpty(link),
			})
		}
	}

	rotinas := make([]domain.RotinaWithItensItem, 0, len(ordered))
	for _, id := range ordered {
		rotinas = append(rotinas, *byID[id])
	}

	countQuery := fmt.Sprintf("SELECT count(*) FROM public.rotinas r WHERE %s", strings.Join(whereParts, " AND "))
	var total int64
	if err := r.pool.QueryRow(ctx, countQuery, args[:len(args)-2]...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count rotinas: %w", err)
	}

	return rotinas, total, nil
}

func (r *RotinaRepository) ListLite(ctx context.Context, municipioID string) ([]domain.RotinaLiteItem, int64, error) {
	if strings.TrimSpace(municipioID) == "" {
		return r.listRotinasLiteAll(ctx)
	}
	rows, err := r.pool.Query(ctx, `
SELECT r.id, r.descricao, COALESCE(r.tipo_empresa_id::text, ''), COALESCE(te.id::text, ''), COALESCE(te.descricao, ''),
	COALESCE(m.id::text, ''), COALESCE(m.nome, '')
FROM public.rotinas r
LEFT JOIN public.tipoempresa te ON te.id = r.tipo_empresa_id
INNER JOIN public.municipio m ON m.id = r.municipio_id
WHERE r.ativo = true AND r.municipio_id = $1
ORDER BY r.descricao ASC`, municipioID)
	if err != nil {
		return nil, 0, fmt.Errorf("list rotinas lite: %w", err)
	}
	defer rows.Close()

	rotinas := make([]domain.RotinaLiteItem, 0)
	for rows.Next() {
		var id, descricao, tipoEmpresaID, teid, tedesc, mid, mnome string
		if err := rows.Scan(&id, &descricao, &tipoEmpresaID, &teid, &tedesc, &mid, &mnome); err != nil {
			return nil, 0, fmt.Errorf("scan rotina lite: %w", err)
		}
		rotinas = append(rotinas, domain.RotinaLiteItem{
			ID:            id,
			Descricao:     descricao,
			TipoEmpresaID: tipoEmpresaID,
			TipoEmpresa: domain.RotinaTipoEmpresaRef{
				ID:        teid,
				Descricao: tedesc,
			},
			Municipio: domain.RotinaMunicipioRef{
				ID:   mid,
				Nome: mnome,
			},
		})
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.rotinas WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count rotinas: %w", err)
	}

	return rotinas, total, nil
}

func (r *RotinaRepository) listRotinasLiteAll(ctx context.Context) ([]domain.RotinaLiteItem, int64, error) {
	rows, err := r.pool.Query(ctx, `
SELECT r.id, r.descricao, COALESCE(r.tipo_empresa_id::text, ''), COALESCE(te.id::text, ''), COALESCE(te.descricao, ''),
	COALESCE(m.id::text, ''), COALESCE(m.nome, '')
FROM public.rotinas r
LEFT JOIN public.tipoempresa te ON te.id = r.tipo_empresa_id
INNER JOIN public.municipio m ON m.id = r.municipio_id
WHERE r.ativo = true
ORDER BY m.nome ASC, r.descricao ASC`)
	if err != nil {
		return nil, 0, fmt.Errorf("list rotinas lite todas: %w", err)
	}
	defer rows.Close()

	rotinas := make([]domain.RotinaLiteItem, 0)
	for rows.Next() {
		var id, descricao, tipoEmpresaID, teid, tedesc, mid, mnome string
		if err := rows.Scan(&id, &descricao, &tipoEmpresaID, &teid, &tedesc, &mid, &mnome); err != nil {
			return nil, 0, fmt.Errorf("scan rotina lite: %w", err)
		}
		rotinas = append(rotinas, domain.RotinaLiteItem{
			ID:            id,
			Descricao:     descricao,
			TipoEmpresaID: tipoEmpresaID,
			TipoEmpresa: domain.RotinaTipoEmpresaRef{
				ID:        teid,
				Descricao: tedesc,
			},
			Municipio: domain.RotinaMunicipioRef{
				ID:   mid,
				Nome: mnome,
			},
		})
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.rotinas WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count rotinas: %w", err)
	}

	return rotinas, total, nil
}

func (r *RotinaRepository) Create(ctx context.Context, input RotinaInput) ([]domain.RotinaMutationItem, int64, error) {
	rows, err := r.pool.Query(ctx, `
INSERT INTO public.rotinas (descricao, municipio_id, tipo_empresa_id)
VALUES ($1, $2, $3)
RETURNING id, descricao, municipio_id, COALESCE(tipo_empresa_id, ''), ativo`, input.Descricao, input.MunicipioID, rotinaNullableTipoEmpresaID(input.TipoEmpresaID))
	if err != nil {
		return nil, 0, fmt.Errorf("create rotina: %w", err)
	}
	defer rows.Close()

	rotinas := make([]domain.RotinaMutationItem, 0)
	var createdID string
	for rows.Next() {
		var id, descricao, municipioID, tipoEmpresaID string
		var ativo bool
		if err := rows.Scan(&id, &descricao, &municipioID, &tipoEmpresaID, &ativo); err != nil {
			return nil, 0, fmt.Errorf("scan created rotina: %w", err)
		}
		createdID = id
		rotinas = append(rotinas, domain.RotinaMutationItem{ID: id, Descricao: descricao, MunicipioID: municipioID, TipoEmpresaID: tipoEmpresaID, Ativo: ativo})
	}

	if strings.TrimSpace(input.Link) != "" && createdID != "" {
		_, _ = r.pool.Exec(ctx, `
INSERT INTO public.linkrotinas (link, rotinas_id)
VALUES ($1, $2)
ON CONFLICT (rotinas_id)
DO UPDATE SET link = $1`, input.Link, createdID)
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.rotinas WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count rotinas: %w", err)
	}

	return rotinas, total, nil
}

func (r *RotinaRepository) Update(ctx context.Context, input RotinaInput) ([]domain.RotinaMutationItem, int64, error) {
	rows, err := r.pool.Query(ctx, `
UPDATE public.rotinas
SET descricao = $1, municipio_id = $2, tipo_empresa_id = $3
WHERE id = $4
RETURNING id, descricao, municipio_id, COALESCE(tipo_empresa_id, ''), ativo`, input.Descricao, input.MunicipioID, rotinaNullableTipoEmpresaID(input.TipoEmpresaID), input.ID)
	if err != nil {
		return nil, 0, fmt.Errorf("update rotina: %w", err)
	}
	defer rows.Close()

	rotinas := make([]domain.RotinaMutationItem, 0)
	for rows.Next() {
		var id, descricao, municipioID, tipoEmpresaID string
		var ativo bool
		if err := rows.Scan(&id, &descricao, &municipioID, &tipoEmpresaID, &ativo); err != nil {
			return nil, 0, fmt.Errorf("scan updated rotina: %w", err)
		}
		rotinas = append(rotinas, domain.RotinaMutationItem{ID: id, Descricao: descricao, MunicipioID: municipioID, TipoEmpresaID: tipoEmpresaID, Ativo: ativo})
	}

	if strings.TrimSpace(input.Link) != "" {
		_, _ = r.pool.Exec(ctx, `
INSERT INTO public.linkrotinas (rotinas_id, link)
VALUES ($1, $2)
ON CONFLICT (rotinas_id)
DO UPDATE SET link = $2`, input.ID, input.Link)
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.rotinas WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count rotinas: %w", err)
	}

	return rotinas, total, nil
}

func (r *RotinaRepository) Delete(ctx context.Context, id string) ([]domain.RotinaMutationItem, int64, error) {
	rows, err := r.pool.Query(ctx, `
UPDATE public.rotinas
SET ativo = false
WHERE id = $1
RETURNING id, descricao, municipio_id, COALESCE(tipo_empresa_id, ''), ativo`, id)
	if err != nil {
		return nil, 0, fmt.Errorf("delete rotina: %w", err)
	}
	defer rows.Close()

	rotinas := make([]domain.RotinaMutationItem, 0)
	for rows.Next() {
		var rid, descricao, municipioID, tipoEmpresaID string
		var ativo bool
		if err := rows.Scan(&rid, &descricao, &municipioID, &tipoEmpresaID, &ativo); err != nil {
			return nil, 0, fmt.Errorf("scan deleted rotina: %w", err)
		}
		rotinas = append(rotinas, domain.RotinaMutationItem{ID: rid, Descricao: descricao, MunicipioID: municipioID, TipoEmpresaID: tipoEmpresaID, Ativo: ativo})
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.rotinas WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count rotinas: %w", err)
	}

	return rotinas, total, nil
}

func (r *RotinaRepository) RotinaItens(ctx context.Context, rotinaID string) ([]map[string]any, int64, error) {
	rows, err := r.pool.Query(ctx, `SELECT * FROM public.rotinaitenlink WHERE rotinas_id = $1`, rotinaID)
	if err != nil {
		return nil, 0, fmt.Errorf("list rotinaitens: %w", err)
	}
	defer rows.Close()

	rotinasitens := make([]map[string]any, 0)
	for rows.Next() {
		values, err := rows.Values()
		if err != nil {
			return nil, 0, fmt.Errorf("values rotinaitens: %w", err)
		}
		fieldDescs := rows.FieldDescriptions()
		row := make(map[string]any, len(values))
		for i, value := range values {
			row[string(fieldDescs[i].Name)] = value
		}
		rotinasitens = append(rotinasitens, row)
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.rotinas WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count rotinas: %w", err)
	}

	return rotinasitens, total, nil
}

func (r *RotinaRepository) RotinaItemCreate(ctx context.Context, rotinaID, descricao string, tempoestimado int, link string) ([]map[string]any, int64, error) {
	rows, err := r.pool.Query(ctx, `
INSERT INTO public.rotinaitenlink (rotinas_id, descricao, tempoestimado)
VALUES ($1, $2, $3)
RETURNING *`, rotinaID, descricao, tempoestimado)
	if err != nil {
		return nil, 0, fmt.Errorf("create rotinaitem: %w", err)
	}
	defer rows.Close()

	itens := make([]map[string]any, 0)
	var createdID any
	for rows.Next() {
		values, err := rows.Values()
		if err != nil {
			return nil, 0, fmt.Errorf("values created rotinaitem: %w", err)
		}
		fieldDescs := rows.FieldDescriptions()
		row := make(map[string]any, len(values))
		for i, value := range values {
			name := string(fieldDescs[i].Name)
			row[name] = value
			if name == "id" {
				createdID = value
			}
		}
		itens = append(itens, row)
	}

	if strings.TrimSpace(link) != "" && createdID != nil {
		_, _ = r.pool.Exec(ctx, `
INSERT INTO public.rotinaitenlink (link, rotinasitens_id)
VALUES ($1, $2)
ON CONFLICT (rotinasitens_id)
DO UPDATE SET link = $1`, link, createdID)
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.rotinas WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count rotinas: %w", err)
	}

	return itens, total, nil
}

func (r *RotinaRepository) RotinaItemUpdate(ctx context.Context, id, descricao string, tempoestimado int, link string) ([]map[string]any, int64, error) {
	rows, err := r.pool.Query(ctx, `
UPDATE public.rotinaitenlink
SET descricao = $1, tempoestimado = $2
WHERE id = $3
RETURNING *`, descricao, tempoestimado, id)
	if err != nil {
		return nil, 0, fmt.Errorf("update rotinaitem: %w", err)
	}
	defer rows.Close()

	itens := make([]map[string]any, 0)
	for rows.Next() {
		values, err := rows.Values()
		if err != nil {
			return nil, 0, fmt.Errorf("values updated rotinaitem: %w", err)
		}
		fieldDescs := rows.FieldDescriptions()
		row := make(map[string]any, len(values))
		for i, value := range values {
			row[string(fieldDescs[i].Name)] = value
		}
		itens = append(itens, row)
	}

	if strings.TrimSpace(link) != "" {
		_, _ = r.pool.Exec(ctx, `
INSERT INTO public.rotinaitenlink (rotinasitens_id, link)
VALUES ($1, $2)
ON CONFLICT (rotinasitens_id)
DO UPDATE SET link = $2`, id, link)
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.rotinas WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count rotinas: %w", err)
	}

	return itens, total, nil
}

func (r *RotinaRepository) RotinaItemDelete(ctx context.Context, id string) ([]map[string]any, int64, error) {
	rows, err := r.pool.Query(ctx, `
UPDATE public.rotinaitenlink
SET ativo = false
WHERE id = $1
RETURNING *`, id)
	if err != nil {
		return nil, 0, fmt.Errorf("delete rotinaitem: %w", err)
	}
	defer rows.Close()

	itens := make([]map[string]any, 0)
	for rows.Next() {
		values, err := rows.Values()
		if err != nil {
			return nil, 0, fmt.Errorf("values deleted rotinaitem: %w", err)
		}
		fieldDescs := rows.FieldDescriptions()
		row := make(map[string]any, len(values))
		for i, value := range values {
			row[string(fieldDescs[i].Name)] = value
		}
		itens = append(itens, row)
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.rotinas WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count rotinas: %w", err)
	}

	return itens, total, nil
}

func (r *RotinaRepository) ListSelectedItens(ctx context.Context, rotinaID string) ([]domain.RotinaSelectedPassoItem, int64, error) {
	rows, err := r.pool.Query(ctx, `
SELECT p.id, p.descricao, p.tempoestimado, p.tipopasso, ri.rotina_id, ri.ordem, COALESCE(l.link, '')
FROM public.rotinas r
LEFT JOIN public.rotinaitens ri ON ri.rotina_id = r.id
LEFT JOIN public.passos p ON p.id = ri.passo_id
LEFT JOIN public.linkpassos l ON l.passo_id = p.id
WHERE ri.rotina_id = $1
ORDER BY ri.ordem ASC`, rotinaID)
	if err != nil {
		return nil, 0, fmt.Errorf("list selected itens: %w", err)
	}
	defer rows.Close()

	passos := make([]domain.RotinaSelectedPassoItem, 0)
	for rows.Next() {
		var id, descricao, tipopasso, rid, link string
		var tempo int
		var ordem any
		if err := rows.Scan(&id, &descricao, &tempo, &tipopasso, &rid, &ordem, &link); err != nil {
			return nil, 0, fmt.Errorf("scan selected itens: %w", err)
		}
		passos = append(passos, domain.RotinaSelectedPassoItem{
			ID:            id,
			Descricao:     descricao,
			TempoEstimado: tempo,
			Tipopasso:     tipopasso,
			RotinaID:      rid,
			Ordem:         ordem,
			Link:          link,
		})
	}

	var total int64
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM public.rotinas WHERE ativo = true`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count rotinas: %w", err)
	}

	return passos, total, nil
}

func (r *RotinaRepository) SaveSelectedItens(ctx context.Context, selections []RotinaPassoSelection) error {
	if len(selections) == 0 {
		return nil
	}

	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return fmt.Errorf("begin tx save selected itens: %w", err)
	}
	defer tx.Rollback(ctx)

	for _, item := range selections {
		var exists bool
		if err := tx.QueryRow(ctx,
			`SELECT EXISTS(SELECT 1 FROM public.rotinaitens WHERE rotina_id = $1 AND passo_id = $2)`,
			item.RotinaID,
			item.ID,
		).Scan(&exists); err != nil {
			return fmt.Errorf("check selected item exists: %w", err)
		}

		if !exists {
			if _, err := tx.Exec(ctx,
				`INSERT INTO public.rotinaitens (rotina_id, passo_id, ordem) VALUES ($1, $2, $3)`,
				item.RotinaID,
				item.ID,
				item.Ordem,
			); err != nil {
				return fmt.Errorf("insert selected item: %w", err)
			}
		} else {
			if _, err := tx.Exec(ctx,
				`UPDATE public.rotinaitens SET ordem = $1 WHERE rotina_id = $2 AND passo_id = $3`,
				item.Ordem,
				item.RotinaID,
				item.ID,
			); err != nil {
				return fmt.Errorf("update selected item: %w", err)
			}
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit save selected itens: %w", err)
	}

	return nil
}

func (r *RotinaRepository) RemoveSelectedItens(ctx context.Context, selections []RotinaPassoSelection) error {
	for _, item := range selections {
		if _, err := r.pool.Exec(ctx,
			`DELETE FROM public.rotinaitens WHERE rotina_id = $1 AND passo_id = $2`,
			item.RotinaID,
			item.ID,
		); err != nil {
			return fmt.Errorf("remove selected item: %w", err)
		}
	}

	return nil
}

func rotinaMunicipioExibicao(nomeMunicipio, siglaUF string) string {
	n := strings.TrimSpace(nomeMunicipio)
	s := strings.TrimSpace(siglaUF)
	if n == "" {
		return "Sem município"
	}
	if s == "" {
		return n
	}
	return n + " / " + s
}

func valueOrEmpty(v *string) string {
	if v == nil {
		return ""
	}
	return *v
}

func valueOrZero(v *int) int {
	if v == nil {
		return 0
	}
	return *v
}
