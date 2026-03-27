package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// CompromissoRef is a lightweight FK reference for Estado or Municipio.
type CompromissoRef struct {
	ID   string `json:"id"`
	Nome string `json:"nome"`
}

// CompromissoListItem is the full read projection for the list/detail view.
type CompromissoListItem struct {
	ID            string          `json:"id"`
	TipoEmpresaID string          `json:"tipo_empresa_id"`
	TipoEmpresa   *CompromissoRef `json:"tipoempresa,omitempty"`
	Natureza      string          `json:"natureza"`
	Descricao     string          `json:"descricao"`
	Periodicidade string          `json:"periodicidade"`
	Abrangencia   string          `json:"abrangencia"`
	Valor         *float64        `json:"valor,omitempty"`
	Observacao    string          `json:"observacao,omitempty"`
	Estado        *CompromissoRef `json:"estado,omitempty"`
	Municipio     *CompromissoRef `json:"municipio,omitempty"`
	Bairro        string          `json:"bairro,omitempty"`
}

// CompromissoMutationItem is returned after Create/Update/Delete.
type CompromissoMutationItem struct {
	ID            string   `json:"id"`
	TipoEmpresaID string   `json:"tipo_empresa_id"`
	Natureza      string   `json:"natureza"`
	Descricao     string   `json:"descricao"`
	Periodicidade string   `json:"periodicidade"`
	Abrangencia   string   `json:"abrangencia"`
	Valor         *float64 `json:"valor,omitempty"`
	Observacao    string   `json:"observacao,omitempty"`
	Ativo         bool     `json:"ativo"`
}

// CompromissoListParams holds query parameters for List.
type CompromissoListParams struct {
	First       int
	Rows        int
	SortField   string
	SortOrder   int
	Descricao   string
	Abrangencia string // FEDERAL | ESTADUAL | MUNICIPAL | BAIRRO | "" (todos)
	TipoEmpresa string
	Natureza    string
	Periodicidade string
	Localizacao string
}

// CompromissoUpsertInput is used for Create and Update.
type CompromissoUpsertInput struct {
	ID            string
	TipoEmpresaID string
	Natureza      string
	Descricao     string
	Periodicidade string
	Abrangencia   string
	Valor         *float64
	Observacao    string
	EstadoID      string
	MunicipioID   string
	Bairro        string
}

// CompromissoRepository provides CRUD access to public.compromisso_financeiro.
type CompromissoRepository struct {
	pool *pgxpool.Pool
}

func NewCompromissoRepository(pool *pgxpool.Pool) *CompromissoRepository {
	return &CompromissoRepository{pool: pool}
}

func (r *CompromissoRepository) List(ctx context.Context, params CompromissoListParams) ([]CompromissoListItem, int64, error) {
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

	natureza := strings.ToUpper(strings.TrimSpace(params.Natureza))
	if natureza != "" && natureza != "TODOS" {
		if natureza == "NAO_FINANCEIRO" || natureza == "NÃO_FINANCEIRO" {
			whereParts = append(whereParts, `(c.natureza = 'NAO_FINANCEIRO' OR c.natureza = 'NÃO_FINANCEIRO')`)
		} else {
			whereParts = append(whereParts, fmt.Sprintf("UPPER(c.natureza) = $%d", argIndex))
			args = append(args, natureza)
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
		"descricao":      "c.descricao",
		"tipoempresa.nome": "te.descricao",
		"natureza":       "c.natureza",
		"periodicidade":  "c.periodicidade",
		"abrangencia":    "c.abrangencia",
		"valor":          "c.valor",
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
			c.id, c.tipo_empresa_id, te.descricao, c.natureza, c.descricao, c.periodicidade, c.abrangencia,
			c.valor, c.observacao,
			e.id,  e.nome,
			COALESCE(mm.id::text,  mb.id::text),
			COALESCE(mm.nome, mb.nome),
			cb.bairro
		FROM public.compromisso_financeiro c
		JOIN public.tipoempresa            te ON te.id = c.tipo_empresa_id
		LEFT JOIN public.compromisso_estado    ce ON ce.compromisso_id = c.id
		LEFT JOIN public.estado                e  ON e.id  = ce.estado_id
		LEFT JOIN public.compromisso_municipio cm ON cm.compromisso_id = c.id
		LEFT JOIN public.municipio             mm ON mm.id = cm.municipio_id
		LEFT JOIN public.compromisso_bairro    cb ON cb.compromisso_id = c.id
		LEFT JOIN public.municipio             mb ON mb.id = cb.municipio_id
		WHERE %s
		ORDER BY %s
		LIMIT $%d OFFSET $%d`, where, orderBy, argIndex, argIndex+1)

	args = append(args, params.Rows, params.First)

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list compromissos: %w", err)
	}
	defer rows.Close()

	items := make([]CompromissoListItem, 0)
	for rows.Next() {
		var id, tipoEmpresaID, tipoEmpresaNome, natureza, descricao, periodicidade, abrangencia string
		var valor sql.NullFloat64
		var observacao, estadoID, estadoNome, municipioID, municipioNome, bairro sql.NullString

		if err := rows.Scan(
			&id, &tipoEmpresaID, &tipoEmpresaNome, &natureza, &descricao, &periodicidade, &abrangencia,
			&valor, &observacao,
			&estadoID, &estadoNome,
			&municipioID, &municipioNome,
			&bairro,
		); err != nil {
			return nil, 0, fmt.Errorf("scan compromisso: %w", err)
		}

		item := CompromissoListItem{
			ID:            id,
			TipoEmpresaID: tipoEmpresaID,
			TipoEmpresa:   &CompromissoRef{ID: tipoEmpresaID, Nome: tipoEmpresaNome},
			Natureza:      natureza,
			Descricao:     descricao,
			Periodicidade: periodicidade,
			Abrangencia:   abrangencia,
		}
		if valor.Valid {
			item.Valor = &valor.Float64
		}
		if observacao.Valid {
			item.Observacao = observacao.String
		}
		if estadoID.Valid {
			item.Estado = &CompromissoRef{ID: estadoID.String, Nome: estadoNome.String}
		}
		if municipioID.Valid {
			item.Municipio = &CompromissoRef{ID: municipioID.String, Nome: municipioNome.String}
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
		FROM public.compromisso_financeiro c
		JOIN public.tipoempresa            te ON te.id = c.tipo_empresa_id
		LEFT JOIN public.compromisso_estado    ce ON ce.compromisso_id = c.id
		LEFT JOIN public.estado                e  ON e.id  = ce.estado_id
		LEFT JOIN public.compromisso_municipio cm ON cm.compromisso_id = c.id
		LEFT JOIN public.municipio             mm ON mm.id = cm.municipio_id
		LEFT JOIN public.compromisso_bairro    cb ON cb.compromisso_id = c.id
		LEFT JOIN public.municipio             mb ON mb.id = cb.municipio_id
		WHERE %s`, where)
	var total int64
	if err := r.pool.QueryRow(ctx, countQuery, args[:len(args)-2]...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count compromissos: %w", err)
	}

	return items, total, nil
}

func (r *CompromissoRepository) Create(ctx context.Context, input CompromissoUpsertInput) ([]CompromissoMutationItem, int64, error) {
	const existsQuery = `
		SELECT count(*) FROM public.compromisso_financeiro
		WHERE tipo_empresa_id = $1 AND descricao = $2 AND abrangencia = $3 AND ativo = true`
	var count int64
	if err := r.pool.QueryRow(ctx, existsQuery, input.TipoEmpresaID, input.Descricao, input.Abrangencia).Scan(&count); err != nil {
		return nil, 0, fmt.Errorf("check compromisso exists: %w", err)
	}
	if count > 0 {
		return nil, 0, fmt.Errorf("Compromisso já cadastrado para este tipo de empresa com esta descrição e abrangência")
	}

	const query = `
		INSERT INTO public.compromisso_financeiro (tipo_empresa_id, natureza, descricao, periodicidade, abrangencia, valor, observacao)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id, tipo_empresa_id, natureza, descricao, periodicidade, abrangencia, valor, observacao, ativo`

	rows, err := r.pool.Query(ctx, query,
		input.TipoEmpresaID, input.Natureza, input.Descricao, input.Periodicidade, input.Abrangencia,
		compromissoNullFloat(input.Valor), compromissoNullStr(input.Observacao),
	)
	if err != nil {
		return nil, 0, fmt.Errorf("create compromisso: %w", err)
	}
	defer rows.Close()

	result := make([]CompromissoMutationItem, 0)
	var createdID string
	for rows.Next() {
		item, id, err := scanMutation(rows)
		if err != nil {
			return nil, 0, err
		}
		createdID = id
		result = append(result, item)
	}

	r.upsertRelations(ctx, createdID, input)
	return result, int64(len(result)), nil
}

func (r *CompromissoRepository) Update(ctx context.Context, input CompromissoUpsertInput) ([]CompromissoMutationItem, int64, error) {
	const query = `
		UPDATE public.compromisso_financeiro
		SET tipo_empresa_id = $1, natureza = $2, descricao = $3, periodicidade = $4, abrangencia = $5,
		    valor = $6, observacao = $7, atualizado_em = NOW()
		WHERE id = $8
		RETURNING id, tipo_empresa_id, natureza, descricao, periodicidade, abrangencia, valor, observacao, ativo`

	rows, err := r.pool.Query(ctx, query,
		input.TipoEmpresaID, input.Natureza, input.Descricao, input.Periodicidade, input.Abrangencia,
		compromissoNullFloat(input.Valor), compromissoNullStr(input.Observacao),
		input.ID,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("update compromisso: %w", err)
	}
	defer rows.Close()

	result := make([]CompromissoMutationItem, 0)
	for rows.Next() {
		item, _, err := scanMutation(rows)
		if err != nil {
			return nil, 0, err
		}
		result = append(result, item)
	}

	r.clearRelations(ctx, input.ID)
	r.upsertRelations(ctx, input.ID, input)
	return result, int64(len(result)), nil
}

func (r *CompromissoRepository) Delete(ctx context.Context, id string) ([]CompromissoMutationItem, int64, error) {
	const query = `
		UPDATE public.compromisso_financeiro
		SET ativo = false, atualizado_em = NOW()
		WHERE id = $1
		RETURNING id, tipo_empresa_id, natureza, descricao, periodicidade, abrangencia, valor, observacao, ativo`

	rows, err := r.pool.Query(ctx, query, id)
	if err != nil {
		return nil, 0, fmt.Errorf("delete compromisso: %w", err)
	}
	defer rows.Close()

	result := make([]CompromissoMutationItem, 0)
	for rows.Next() {
		item, _, err := scanMutation(rows)
		if err != nil {
			return nil, 0, err
		}
		result = append(result, item)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("rows error: %w", err)
	}
	return result, int64(len(result)), nil
}

// ── helpers ─────────────────────────────────────────────────────────────────

type mutationScanner interface {
	Scan(dest ...any) error
}

func scanMutation(row mutationScanner) (CompromissoMutationItem, string, error) {
	var id, tipoEmpresaID, natureza, descricao, periodicidade, abrangencia string
	var valor sql.NullFloat64
	var observacao sql.NullString
	var ativo bool

	if err := row.Scan(&id, &tipoEmpresaID, &natureza, &descricao, &periodicidade, &abrangencia, &valor, &observacao, &ativo); err != nil {
		return CompromissoMutationItem{}, "", fmt.Errorf("scan mutation compromisso: %w", err)
	}

	item := CompromissoMutationItem{
		ID:            id,
		TipoEmpresaID: tipoEmpresaID,
		Natureza:      natureza,
		Descricao:     descricao,
		Periodicidade: periodicidade,
		Abrangencia:   abrangencia,
		Ativo:         ativo,
	}
	if valor.Valid {
		item.Valor = &valor.Float64
	}
	if observacao.Valid {
		item.Observacao = observacao.String
	}
	return item, id, nil
}

func (r *CompromissoRepository) upsertRelations(ctx context.Context, id string, input CompromissoUpsertInput) {
	switch input.Abrangencia {
	case "ESTADUAL":
		if strings.TrimSpace(input.EstadoID) != "" {
			_, _ = r.pool.Exec(ctx,
				`INSERT INTO public.compromisso_estado (compromisso_id, estado_id)
				 VALUES ($1, $2)
				 ON CONFLICT (compromisso_id) DO UPDATE SET estado_id = EXCLUDED.estado_id`,
				id, input.EstadoID)
		}
	case "MUNICIPAL":
		if strings.TrimSpace(input.MunicipioID) != "" {
			_, _ = r.pool.Exec(ctx,
				`INSERT INTO public.compromisso_municipio (compromisso_id, municipio_id)
				 VALUES ($1, $2)
				 ON CONFLICT (compromisso_id) DO UPDATE SET municipio_id = EXCLUDED.municipio_id`,
				id, input.MunicipioID)
		}
	case "BAIRRO":
		if strings.TrimSpace(input.MunicipioID) != "" && strings.TrimSpace(input.Bairro) != "" {
			_, _ = r.pool.Exec(ctx,
				`INSERT INTO public.compromisso_bairro (compromisso_id, municipio_id, bairro)
				 VALUES ($1, $2, $3)
				 ON CONFLICT (compromisso_id) DO UPDATE SET municipio_id = EXCLUDED.municipio_id, bairro = EXCLUDED.bairro`,
				id, input.MunicipioID, input.Bairro)
		}
	}
}

func (r *CompromissoRepository) clearRelations(ctx context.Context, id string) {
	_, _ = r.pool.Exec(ctx, `DELETE FROM public.compromisso_estado    WHERE compromisso_id = $1`, id)
	_, _ = r.pool.Exec(ctx, `DELETE FROM public.compromisso_municipio WHERE compromisso_id = $1`, id)
	_, _ = r.pool.Exec(ctx, `DELETE FROM public.compromisso_bairro    WHERE compromisso_id = $1`, id)
}

func compromissoNullFloat(v *float64) any {
	if v == nil {
		return nil
	}
	return *v
}

func compromissoNullStr(s string) any {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return s
}
