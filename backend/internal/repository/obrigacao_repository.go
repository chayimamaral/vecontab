package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ObrigacaoRef referência geográfica ou tipo de empresa.
type ObrigacaoRef struct {
	ID   string `json:"id"`
	Nome string `json:"nome"`
}

// ObrigacaoListItem projeção do cadastro de obrigações legais (ex-compromissos financeiros).
type ObrigacaoListItem struct {
	ID                string        `json:"id"`
	TipoEmpresaID     string        `json:"tipo_empresa_id"`
	TipoEmpresa       *ObrigacaoRef `json:"tipoempresa,omitempty"`
	Descricao         string        `json:"descricao"`
	Periodicidade     string        `json:"periodicidade"`
	Abrangencia       string        `json:"abrangencia"`
	DiaBase           int           `json:"dia_base"`
	MesBase           string        `json:"mes_base,omitempty"`
	TipoClassificacao string        `json:"tipo_classificacao,omitempty"`
	Valor             *float64      `json:"valor,omitempty"`
	Observacao        string        `json:"observacao,omitempty"`
	Estado            *ObrigacaoRef `json:"estado,omitempty"`
	Municipio         *ObrigacaoRef `json:"municipio,omitempty"`
	Bairro            string        `json:"bairro,omitempty"`
}

// ObrigacaoMutationItem retorno de Create/Update/Delete.
type ObrigacaoMutationItem struct {
	ID                string   `json:"id"`
	TipoEmpresaID     string   `json:"tipo_empresa_id"`
	TipoClassificacao string   `json:"tipo_classificacao"`
	Descricao         string   `json:"descricao"`
	Periodicidade     string   `json:"periodicidade"`
	Abrangencia       string   `json:"abrangencia"`
	Valor             *float64 `json:"valor,omitempty"`
	Observacao        string   `json:"observacao,omitempty"`
	Ativo             bool     `json:"ativo"`
}

// ObrigacaoListParams filtros da listagem lazy.
type ObrigacaoListParams struct {
	First             int
	Rows              int
	SortField         string
	SortOrder         int
	Descricao         string
	Abrangencia       string
	TipoEmpresa       string
	TipoClassificacao string
	Periodicidade     string
	Localizacao       string
}

// ObrigacaoUpsertInput entrada de criação/atualização.
type ObrigacaoUpsertInput struct {
	ID                string
	TipoEmpresaID     string
	TipoClassificacao string
	Descricao         string
	Periodicidade     string
	Abrangencia       string
	DiaBase           int
	MesBase           string
	Valor             *float64
	Observacao        string
	EstadoID          string
	MunicipioID       string
	Bairro            string
}

type ObrigacaoRepository struct {
	pool *pgxpool.Pool
}

func NewObrigacaoRepository(pool *pgxpool.Pool) *ObrigacaoRepository {
	return &ObrigacaoRepository{pool: pool}
}

// normalizeTipoClassificacao persiste TRIBUTARIA | INFORMATIVA; aceita legado TRIBUTO / FINANCEIRO no input.
func normalizeTipoClassificacao(s string) string {
	u := strings.ToUpper(strings.TrimSpace(s))
	switch u {
	case "", "TRIBUTARIA", "TRIBUTO", "FINANCEIRO":
		return "TRIBUTARIA"
	case "INFORMATIVA", "NAO_FINANCEIRO", "NÃO_FINANCEIRO":
		return "INFORMATIVA"
	default:
		return u
	}
}

func mesBaseArg(s string) any {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return strings.TrimSpace(s)
}

func (r *ObrigacaoRepository) List(ctx context.Context, params ObrigacaoListParams) ([]ObrigacaoListItem, int64, error) {
	whereParts := []string{"c.ativo = true"}
	args := []any{}
	argIndex := 1

	if strings.TrimSpace(params.Descricao) != "" {
		whereParts = append(whereParts, fmt.Sprintf("c.descricao ILIKE $%d", argIndex))
		args = append(args, "%"+strings.TrimSpace(params.Descricao)+"%")
		argIndex++
	}

	if strings.TrimSpace(params.Abrangencia) != "" && params.Abrangencia != "TODOS" {
		whereParts = append(whereParts, fmt.Sprintf("c.abrangencia = $%d", argIndex))
		args = append(args, strings.TrimSpace(params.Abrangencia))
		argIndex++
	}

	if strings.TrimSpace(params.TipoEmpresa) != "" {
		whereParts = append(whereParts, fmt.Sprintf("c.tipo_empresa_id = $%d", argIndex))
		args = append(args, strings.TrimSpace(params.TipoEmpresa))
		argIndex++
	}

	tc := strings.ToUpper(strings.TrimSpace(params.TipoClassificacao))
	if tc != "" && tc != "TODOS" {
		switch tc {
		case "TRIBUTARIA":
			whereParts = append(whereParts, `UPPER(TRIM(COALESCE(c.tipo_classificacao,''))) IN ('TRIBUTARIA','TRIBUTO')`)
		case "INFORMATIVA":
			whereParts = append(whereParts, `UPPER(TRIM(COALESCE(c.tipo_classificacao,''))) = 'INFORMATIVA'`)
		default:
			whereParts = append(whereParts, fmt.Sprintf("UPPER(TRIM(COALESCE(c.tipo_classificacao,''))) = $%d", argIndex))
			args = append(args, tc)
			argIndex++
		}
	}

	periodicidade := strings.ToUpper(strings.TrimSpace(params.Periodicidade))
	if periodicidade != "" && periodicidade != "TODOS" {
		whereParts = append(whereParts, fmt.Sprintf("UPPER(c.periodicidade) = $%d", argIndex))
		args = append(args, periodicidade)
		argIndex++
	}

	if strings.TrimSpace(params.Localizacao) != "" {
		whereParts = append(whereParts, fmt.Sprintf("(e.nome ILIKE $%d OR mm.nome ILIKE $%d OR mb.nome ILIKE $%d OR cb.bairro ILIKE $%d)", argIndex, argIndex, argIndex, argIndex))
		args = append(args, "%"+strings.TrimSpace(params.Localizacao)+"%")
		argIndex++
	}

	where := strings.Join(whereParts, " AND ")

	allowedSortFields := map[string]string{
		"descricao":          "c.descricao",
		"tipoempresa.nome":   "te.descricao",
		"tipo_classificacao": "c.tipo_classificacao",
		"periodicidade":      "c.periodicidade",
		"abrangencia":        "c.abrangencia",
		"valor":              "c.valor",
	}

	orderBy := "c.descricao ASC"
	if field, ok := allowedSortFields[params.SortField]; ok {
		direction := "ASC"
		if params.SortOrder == -1 {
			direction = "DESC"
		}
		orderBy = fmt.Sprintf("%s %s", field, direction)
	}

	query := fmt.Sprintf(`
		SELECT
			c.id, c.tipo_empresa_id, te.descricao, c.descricao, c.periodicidade, c.abrangencia,
			COALESCE(c.dia_base::int, 20),
			COALESCE(c.mes_base, ''),
			COALESCE(c.tipo_classificacao, ''),
			c.valor, c.observacao,
			e.id,  e.nome,
			COALESCE(mm.id::text,  mb.id::text),
			COALESCE(mm.nome, mb.nome),
			cb.bairro
		FROM public.tipoempresa_obrigacao c
		JOIN public.tipoempresa            te ON te.id = c.tipo_empresa_id
		LEFT JOIN public.tipoempresa_obriga_estado ce ON ce.obrigacao_id = c.id
		LEFT JOIN public.estado                e  ON e.id  = ce.estado_id
		LEFT JOIN public.tipoempresa_obriga_municipio cm ON cm.obrigacao_id = c.id
		LEFT JOIN public.municipio             mm ON mm.id = cm.municipio_id
		LEFT JOIN public.tipoempresa_obriga_bairro cb ON cb.tipoempresa_obrigacao_id = c.id
		LEFT JOIN public.municipio             mb ON mb.id = cb.municipio_id
		WHERE %s
		ORDER BY %s
		LIMIT $%d OFFSET $%d`, where, orderBy, argIndex, argIndex+1)

	args = append(args, params.Rows, params.First)

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list obrigacoes: %w", err)
	}
	defer rows.Close()

	items := make([]ObrigacaoListItem, 0)
	for rows.Next() {
		var id, tipoEmpresaID, tipoEmpresaNome, descricao, periodicidade, abrangencia string
		var diaBase int
		var mesBase, tipoClass sql.NullString
		var valor sql.NullFloat64
		var observacao, estadoID, estadoNome, municipioID, municipioNome, bairro sql.NullString

		if err := rows.Scan(
			&id, &tipoEmpresaID, &tipoEmpresaNome, &descricao, &periodicidade, &abrangencia,
			&diaBase, &mesBase, &tipoClass,
			&valor, &observacao,
			&estadoID, &estadoNome,
			&municipioID, &municipioNome,
			&bairro,
		); err != nil {
			return nil, 0, fmt.Errorf("scan obrigacao: %w", err)
		}

		item := ObrigacaoListItem{
			ID:            id,
			TipoEmpresaID: tipoEmpresaID,
			TipoEmpresa:   &ObrigacaoRef{ID: tipoEmpresaID, Nome: tipoEmpresaNome},
			Descricao:     descricao,
			Periodicidade: periodicidade,
			Abrangencia:   abrangencia,
			DiaBase:       diaBase,
		}
		if mesBase.Valid && strings.TrimSpace(mesBase.String) != "" {
			item.MesBase = mesBase.String
		}
		if tipoClass.Valid {
			item.TipoClassificacao = tipoClass.String
		}
		if valor.Valid {
			item.Valor = &valor.Float64
		}
		if observacao.Valid {
			item.Observacao = observacao.String
		}
		if estadoID.Valid {
			item.Estado = &ObrigacaoRef{ID: estadoID.String, Nome: estadoNome.String}
		}
		if municipioID.Valid {
			item.Municipio = &ObrigacaoRef{ID: municipioID.String, Nome: municipioNome.String}
		}
		if bairro.Valid {
			item.Bairro = bairro.String
		}

		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("rows error: %w", err)
	}

	countQuery := fmt.Sprintf(`
		SELECT count(DISTINCT c.id)
		FROM public.tipoempresa_obrigacao c
		JOIN public.tipoempresa            te ON te.id = c.tipo_empresa_id
		LEFT JOIN public.tipoempresa_obriga_estado ce ON ce.obrigacao_id = c.id
		LEFT JOIN public.estado                e  ON e.id  = ce.estado_id
		LEFT JOIN public.tipoempresa_obriga_municipio cm ON cm.obrigacao_id = c.id
		LEFT JOIN public.municipio             mm ON mm.id = cm.municipio_id
		LEFT JOIN public.tipoempresa_obriga_bairro cb ON cb.tipoempresa_obrigacao_id = c.id
		LEFT JOIN public.municipio             mb ON mb.id = cb.municipio_id
		WHERE %s`, where)
	var total int64
	if err := r.pool.QueryRow(ctx, countQuery, args[:len(args)-2]...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count obrigacoes: %w", err)
	}

	return items, total, nil
}

func (r *ObrigacaoRepository) Create(ctx context.Context, input ObrigacaoUpsertInput) ([]ObrigacaoMutationItem, int64, error) {
	const existsQuery = `
		SELECT count(*) FROM public.tipoempresa_obrigacao
		WHERE tipo_empresa_id = $1 AND descricao = $2 AND abrangencia = $3 AND ativo = true`
	var count int64
	if err := r.pool.QueryRow(ctx, existsQuery, input.TipoEmpresaID, input.Descricao, input.Abrangencia).Scan(&count); err != nil {
		return nil, 0, fmt.Errorf("check obrigacao exists: %w", err)
	}
	if count > 0 {
		return nil, 0, fmt.Errorf("obrigação já cadastrada para este tipo de empresa com esta descrição e abrangência")
	}

	dia := input.DiaBase
	if dia <= 0 {
		dia = 20
	}
	tipoCl := normalizeTipoClassificacao(input.TipoClassificacao)

	const query = `
		INSERT INTO public.tipoempresa_obrigacao (
			tipo_empresa_id, descricao, periodicidade, abrangencia, valor, observacao,
			dia_base, mes_base, tipo_classificacao
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING id, tipo_empresa_id, tipo_classificacao, descricao, periodicidade, abrangencia, valor, observacao, ativo`

	rows, err := r.pool.Query(ctx, query,
		input.TipoEmpresaID, input.Descricao, input.Periodicidade, input.Abrangencia,
		obrigacaoNullFloat(input.Valor), obrigacaoNullStr(input.Observacao),
		dia, mesBaseArg(input.MesBase), tipoCl,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("create obrigacao: %w", err)
	}
	defer rows.Close()

	result := make([]ObrigacaoMutationItem, 0)
	var createdID string
	for rows.Next() {
		item, id, err := scanObrigacaoMutation(rows)
		if err != nil {
			return nil, 0, err
		}
		createdID = id
		result = append(result, item)
	}

	r.upsertRelations(ctx, createdID, input)
	return result, int64(len(result)), nil
}

func (r *ObrigacaoRepository) Update(ctx context.Context, input ObrigacaoUpsertInput) ([]ObrigacaoMutationItem, int64, error) {
	dia := input.DiaBase
	if dia <= 0 {
		dia = 20
	}
	tipoCl := normalizeTipoClassificacao(input.TipoClassificacao)

	const query = `
		UPDATE public.tipoempresa_obrigacao
		SET tipo_empresa_id = $1, descricao = $2, periodicidade = $3, abrangencia = $4,
		    valor = $5, observacao = $6, dia_base = $7, mes_base = $8, tipo_classificacao = $9, atualizado_em = NOW()
		WHERE id = $10
		RETURNING id, tipo_empresa_id, tipo_classificacao, descricao, periodicidade, abrangencia, valor, observacao, ativo`

	rows, err := r.pool.Query(ctx, query,
		input.TipoEmpresaID, input.Descricao, input.Periodicidade, input.Abrangencia,
		obrigacaoNullFloat(input.Valor), obrigacaoNullStr(input.Observacao),
		dia, mesBaseArg(input.MesBase), tipoCl,
		input.ID,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("update obrigacao: %w", err)
	}
	defer rows.Close()

	result := make([]ObrigacaoMutationItem, 0)
	for rows.Next() {
		item, _, err := scanObrigacaoMutation(rows)
		if err != nil {
			return nil, 0, err
		}
		result = append(result, item)
	}

	r.clearRelations(ctx, input.ID)
	r.upsertRelations(ctx, input.ID, input)
	return result, int64(len(result)), nil
}

func (r *ObrigacaoRepository) Delete(ctx context.Context, id string) ([]ObrigacaoMutationItem, int64, error) {
	const query = `
		UPDATE public.tipoempresa_obrigacao
		SET ativo = false, atualizado_em = NOW()
		WHERE id = $1
		RETURNING id, tipo_empresa_id, tipo_classificacao, descricao, periodicidade, abrangencia, valor, observacao, ativo`

	rows, err := r.pool.Query(ctx, query, id)
	if err != nil {
		return nil, 0, fmt.Errorf("delete obrigacao: %w", err)
	}
	defer rows.Close()

	result := make([]ObrigacaoMutationItem, 0)
	for rows.Next() {
		item, _, err := scanObrigacaoMutation(rows)
		if err != nil {
			return nil, 0, err
		}
		result = append(result, item)
	}
	st := rows.Err()
	if st != nil {
		return nil, 0, fmt.Errorf("rows error: %w", st)
	}
	return result, int64(len(result)), nil
}

type obrigacaoMutationScanner interface {
	Scan(dest ...any) error
}

func scanObrigacaoMutation(row obrigacaoMutationScanner) (ObrigacaoMutationItem, string, error) {
	var id, tipoEmpresaID, tipoClass, descricao, periodicidade, abrangencia string
	var valor sql.NullFloat64
	var observacao sql.NullString
	var ativo bool

	if err := row.Scan(&id, &tipoEmpresaID, &tipoClass, &descricao, &periodicidade, &abrangencia, &valor, &observacao, &ativo); err != nil {
		return ObrigacaoMutationItem{}, "", fmt.Errorf("scan mutation obrigacao: %w", err)
	}

	item := ObrigacaoMutationItem{
		ID:                id,
		TipoEmpresaID:     tipoEmpresaID,
		TipoClassificacao: tipoClass,
		Descricao:         descricao,
		Periodicidade:     periodicidade,
		Abrangencia:       abrangencia,
		Ativo:             ativo,
	}
	if valor.Valid {
		item.Valor = &valor.Float64
	}
	if observacao.Valid {
		item.Observacao = observacao.String
	}
	return item, id, nil
}

func (r *ObrigacaoRepository) upsertRelations(ctx context.Context, id string, input ObrigacaoUpsertInput) {
	switch input.Abrangencia {
	case "ESTADUAL":
		if strings.TrimSpace(input.EstadoID) != "" {
			_, _ = r.pool.Exec(ctx,
				`INSERT INTO public.tipoempresa_obriga_estado (obrigacao_id, estado_id)
				 VALUES ($1, $2)
				 ON CONFLICT (obrigacao_id) DO UPDATE SET estado_id = EXCLUDED.estado_id`,
				id, input.EstadoID)
		}
	case "MUNICIPAL":
		if strings.TrimSpace(input.MunicipioID) != "" {
			_, _ = r.pool.Exec(ctx,
				`INSERT INTO public.tipoempresa_obriga_municipio (obrigacao_id, municipio_id)
				 VALUES ($1, $2)
				 ON CONFLICT (obrigacao_id) DO UPDATE SET municipio_id = EXCLUDED.municipio_id`,
				id, input.MunicipioID)
		}
	case "BAIRRO":
		if strings.TrimSpace(input.MunicipioID) != "" && strings.TrimSpace(input.Bairro) != "" {
			_, _ = r.pool.Exec(ctx,
				`INSERT INTO public.tipoempresa_obriga_bairro (tipoempresa_obrigacao_id, municipio_id, bairro)
				 VALUES ($1, $2, $3)
				 ON CONFLICT (tipoempresa_obrigacao_id) DO UPDATE SET municipio_id = EXCLUDED.municipio_id, bairro = EXCLUDED.bairro`,
				id, input.MunicipioID, input.Bairro)
		}
	}
}

func (r *ObrigacaoRepository) clearRelations(ctx context.Context, id string) {
	_, _ = r.pool.Exec(ctx, `DELETE FROM public.tipoempresa_obriga_estado WHERE obrigacao_id = $1`, id)
	_, _ = r.pool.Exec(ctx, `DELETE FROM public.tipoempresa_obriga_municipio WHERE obrigacao_id = $1`, id)
	_, _ = r.pool.Exec(ctx, `DELETE FROM public.tipoempresa_obriga_bairro WHERE tipoempresa_obrigacao_id = $1`, id)
}

func obrigacaoNullFloat(v *float64) any {
	if v == nil {
		return nil
	}
	return *v
}

func obrigacaoNullStr(s string) any {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return s
}
