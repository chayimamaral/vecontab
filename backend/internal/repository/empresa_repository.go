package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strconv"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5/pgxpool"
)

func empresaMunicipioScanString(ns sql.NullString) string {
	if ns.Valid {
		return ns.String
	}
	return ""
}

func empresaRotinaScanString(ns sql.NullString) string {
	if ns.Valid {
		return ns.String
	}
	return ""
}

type EmpresaListParams struct {
	First     int
	Rows      int
	SortField string
	SortOrder int
	Nome      string
	TenantID  string
}

type EmpresaUpsertInput struct {
	ID         string
	Nome       string
	TenantID   string
	RotinaID   string
	Cnaes      any
	Bairro     string
	TipoPessoa string
	Documento  string
}

type EmpresaRepository struct {
	pool *pgxpool.Pool
}

func NewEmpresaRepository(pool *pgxpool.Pool) *EmpresaRepository {
	return &EmpresaRepository{pool: pool}
}

// normalizeCnaesParaTextArray converte o payload JSON ([]any após decode, []string, etc.)
// em []string para a coluna PostgreSQL text[]. O pgx v5 não codifica []any como text[].
func normalizeCnaesParaTextArray(v any) []string {
	if v == nil {
		return nil
	}
	switch x := v.(type) {
	case []string:
		out := make([]string, 0, len(x))
		for _, s := range x {
			s = strings.TrimSpace(s)
			if s != "" {
				out = append(out, s)
			}
		}
		return out
	case []any:
		out := make([]string, 0, len(x))
		for _, e := range x {
			switch t := e.(type) {
			case string:
				if s := strings.TrimSpace(t); s != "" {
					out = append(out, s)
				}
			case float64:
				s := strconv.FormatInt(int64(t), 10)
				if s != "" {
					out = append(out, s)
				}
			default:
				if s := strings.TrimSpace(fmt.Sprint(e)); s != "" {
					out = append(out, s)
				}
			}
		}
		return out
	case string:
		s := strings.TrimSpace(x)
		if s == "" {
			return nil
		}
		return []string{s}
	default:
		return nil
	}
}

func normalizeEmpresaTipoPessoa(s string) string {
	if strings.ToUpper(strings.TrimSpace(s)) == "PF" {
		return "PF"
	}
	return "PJ"
}

func empresaRotinaIDParam(tipo, rotinaID string) any {
	if normalizeEmpresaTipoPessoa(tipo) == "PF" {
		return nil
	}
	if rid := strings.TrimSpace(rotinaID); rid != "" {
		return rid
	}
	return nil
}

func empresaCnaesParam(tipo string, cnaes []string) any {
	if normalizeEmpresaTipoPessoa(tipo) == "PF" {
		if len(cnaes) == 0 {
			return nil
		}
		return cnaes
	}
	if cnaes == nil {
		return []string{}
	}
	return cnaes
}

func (r *EmpresaRepository) List(ctx context.Context, params EmpresaListParams) ([]domain.EmpresaListItem, int64, error) {
	whereParts := []string{"e.ativo = true", "e.tenant_id = $1"}
	args := []any{params.TenantID}
	argIndex := 2

	if strings.TrimSpace(params.Nome) != "" {
		whereParts = append(whereParts, fmt.Sprintf("e.nome ILIKE $%d", argIndex))
		args = append(args, "%"+strings.TrimSpace(params.Nome)+"%")
		argIndex++
	}

	orderBy := "e.nome ASC"
	switch params.SortField {
	case "nome":
		if params.SortOrder == -1 {
			orderBy = "e.nome ASC"
		} else {
			orderBy = "e.nome DESC"
		}
	case "codigo":
		if params.SortOrder == -1 {
			orderBy = "e.codigo ASC"
		} else {
			orderBy = "e.codigo DESC"
		}
	}

	query := fmt.Sprintf(`
		SELECT
			e.id,
			e.nome,
			COALESCE(NULLIF(BTRIM(e.tipo_pessoa::text), ''), 'PJ'),
			COALESCE(NULLIF(BTRIM(e.documento), ''), ''),
			m.id,
			m.nome,
			COALESCE(r.id, ''),
			COALESCE(r.descricao, ''),
			COALESCE(te.id, ''),
			COALESCE(te.descricao, ''),
			e.cnaes,
			COALESCE(e.bairro, ''),
			e.iniciado,
			COALESCE((
				SELECT CASE
					WHEN COUNT(ai.id) = 0 THEN false
					ELSE BOOL_AND(COALESCE(ai.concluido, false))
				END
				FROM public.agenda a
				LEFT JOIN public.agendaitens ai ON ai.agenda_id = a.id
				WHERE a.empresa_id = e.id
				  AND a.tenant_id = e.tenant_id
			), false) AS passos_concluidos,
			EXISTS(
				SELECT 1
				FROM public.empresa_compromissos ec
				WHERE ec.empresa_id = e.id
			) AS compromissos_gerados
		FROM public.empresa e
		LEFT JOIN public.empresa_dados ed ON ed.empresa_id = e.id
		LEFT JOIN public.municipio m ON m.id = COALESCE(e.municipio_id, ed.municipio_id)
		LEFT JOIN public.rotinas r ON r.id = e.rotina_id
		LEFT JOIN public.tipoempresa te ON te.id = r.tipo_empresa_id
		WHERE %s
		ORDER BY %s
		LIMIT $%d OFFSET $%d`, strings.Join(whereParts, " AND "), orderBy, argIndex, argIndex+1)
	args = append(args, params.Rows, params.First)

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list empresa: %w", err)
	}
	defer rows.Close()

	empresas := make([]domain.EmpresaListItem, 0)
	for rows.Next() {
		var id, nome, tpessoa, doc, mid, mnome, rid, rdesc, teid, tedesc, ebairro string
		var iniciado, passosConcluidos, compromissosGerados bool
		var cnaes any
		if err := rows.Scan(&id, &nome, &tpessoa, &doc, &mid, &mnome, &rid, &rdesc, &teid, &tedesc, &cnaes, &ebairro, &iniciado, &passosConcluidos, &compromissosGerados); err != nil {
			return nil, 0, fmt.Errorf("scan empresa: %w", err)
		}

		item := domain.EmpresaListItem{
			ID:          id,
			Nome:        nome,
			TipoPessoa:  tpessoa,
			Documento:   doc,
			Municipio: domain.EmpresaRef{
				ID:   mid,
				Nome: mnome,
			},
			Cnaes:               cnaes,
			Bairro:              ebairro,
			Iniciado:            iniciado,
			PassosConcluidos:    passosConcluidos,
			CompromissosGerados: compromissosGerados,
		}
		item.Rotina.ID = rid
		item.Rotina.Descricao = rdesc
		item.TipoEmpresa.ID = teid
		item.TipoEmpresa.Descricao = tedesc
		empresas = append(empresas, item)
	}

	countQuery := fmt.Sprintf("SELECT count(*) FROM public.empresa e WHERE %s", strings.Join(whereParts, " AND "))
	var total int64
	if err := r.pool.QueryRow(ctx, countQuery, args[:len(args)-2]...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count empresa: %w", err)
	}

	return empresas, total, nil
}

func (r *EmpresaRepository) Create(ctx context.Context, input EmpresaUpsertInput) ([]domain.EmpresaMutationItem, int64, error) {
	const existsQuery = `SELECT count(*) FROM public.empresa WHERE nome = $1`
	var count int64
	if err := r.pool.QueryRow(ctx, existsQuery, input.Nome).Scan(&count); err != nil {
		return nil, 0, fmt.Errorf("check empresa exists: %w", err)
	}
	if count > 0 {
		return nil, 0, fmt.Errorf("Empresa ja cadastrada")
	}

	tipo := normalizeEmpresaTipoPessoa(input.TipoPessoa)
	doc := strings.TrimSpace(input.Documento)

	const query = `
		INSERT INTO public.empresa (nome, municipio_id, tenant_id, rotina_id, cnaes, bairro, tipo_pessoa, documento)
		VALUES ($1, NULL, $2, $3, $4, NULLIF(TRIM($5), ''), $6, NULLIF(TRIM($7), ''))
		RETURNING id, nome, municipio_id, tenant_id, rotina_id, cnaes, iniciado, ativo`

	cnaes := normalizeCnaesParaTextArray(input.Cnaes)
	if cnaes == nil {
		cnaes = []string{}
	}
	cnaesArg := empresaCnaesParam(tipo, cnaes)
	rotinaArg := empresaRotinaIDParam(tipo, input.RotinaID)
	rows, err := r.pool.Query(ctx, query, input.Nome, input.TenantID, rotinaArg, cnaesArg, input.Bairro, tipo, doc)
	if err != nil {
		return nil, 0, fmt.Errorf("create empresa: %w", err)
	}
	defer rows.Close()

	empresas := make([]domain.EmpresaMutationItem, 0)
	for rows.Next() {
		var id, nome, tenantID string
		var municipioID, rotinaID sql.NullString
		var cnaes any
		var iniciado, ativo bool
		if err := rows.Scan(&id, &nome, &municipioID, &tenantID, &rotinaID, &cnaes, &iniciado, &ativo); err != nil {
			return nil, 0, fmt.Errorf("scan created empresa: %w", err)
		}
		empresas = append(empresas, domain.EmpresaMutationItem{
			ID:          id,
			Nome:        nome,
			MunicipioID: empresaMunicipioScanString(municipioID),
			TenantID:    tenantID,
			RotinaID:    empresaRotinaScanString(rotinaID),
			Cnaes:       cnaes,
			Iniciado:    iniciado,
			Ativo:       ativo,
		})
	}

	return empresas, int64(len(empresas)), nil
}

func (r *EmpresaRepository) Update(ctx context.Context, input EmpresaUpsertInput) ([]domain.EmpresaMutationItem, int64, error) {
	tipo := normalizeEmpresaTipoPessoa(input.TipoPessoa)
	doc := strings.TrimSpace(input.Documento)

	const query = `
		UPDATE public.empresa
		SET nome = $1, tenant_id = $2, rotina_id = $3, cnaes = $4, bairro = NULLIF(TRIM($7), ''), tipo_pessoa = $8, documento = NULLIF(TRIM($9), '')
		WHERE id = $5 AND tenant_id = $6
		RETURNING id, nome, municipio_id, tenant_id, rotina_id, cnaes, iniciado, ativo`

	cnaes := normalizeCnaesParaTextArray(input.Cnaes)
	if cnaes == nil {
		cnaes = []string{}
	}
	cnaesArg := empresaCnaesParam(tipo, cnaes)
	rotinaArg := empresaRotinaIDParam(tipo, input.RotinaID)
	rows, err := r.pool.Query(ctx, query, input.Nome, input.TenantID, rotinaArg, cnaesArg, input.ID, input.TenantID, input.Bairro, tipo, doc)
	if err != nil {
		return nil, 0, fmt.Errorf("update empresa: %w", err)
	}
	defer rows.Close()

	empresas := make([]domain.EmpresaMutationItem, 0)
	for rows.Next() {
		var id, nome, tenantID string
		var municipioID, rotinaID sql.NullString
		var cnaes any
		var iniciado, ativo bool
		if err := rows.Scan(&id, &nome, &municipioID, &tenantID, &rotinaID, &cnaes, &iniciado, &ativo); err != nil {
			return nil, 0, fmt.Errorf("scan updated empresa: %w", err)
		}
		empresas = append(empresas, domain.EmpresaMutationItem{
			ID:          id,
			Nome:        nome,
			MunicipioID: empresaMunicipioScanString(municipioID),
			TenantID:    tenantID,
			RotinaID:    empresaRotinaScanString(rotinaID),
			Cnaes:       cnaes,
			Iniciado:    iniciado,
			Ativo:       ativo,
		})
	}

	return empresas, int64(len(empresas)), nil
}

func (r *EmpresaRepository) IniciarProcesso(ctx context.Context, id, tenantID string) ([]domain.EmpresaMutationItem, int64, error) {
	const query = `
		UPDATE public.empresa
		SET iniciado = true
		WHERE id = $1 AND tenant_id = $2
		RETURNING id, nome, municipio_id, tenant_id, rotina_id, cnaes, iniciado, ativo`

	rows, err := r.pool.Query(ctx, query, id, tenantID)
	if err != nil {
		return nil, 0, fmt.Errorf("iniciar processo empresa: %w", err)
	}
	defer rows.Close()

	empresas := make([]domain.EmpresaMutationItem, 0)
	for rows.Next() {
		var eid, nome, tenantID string
		var municipioID, rotinaID sql.NullString
		var cnaes any
		var iniciado, ativo bool
		if err := rows.Scan(&eid, &nome, &municipioID, &tenantID, &rotinaID, &cnaes, &iniciado, &ativo); err != nil {
			return nil, 0, fmt.Errorf("scan iniciar processo empresa: %w", err)
		}
		empresas = append(empresas, domain.EmpresaMutationItem{
			ID:          eid,
			Nome:        nome,
			MunicipioID: empresaMunicipioScanString(municipioID),
			TenantID:    tenantID,
			RotinaID:    empresaRotinaScanString(rotinaID),
			Cnaes:       cnaes,
			Iniciado:    iniciado,
			Ativo:       ativo,
		})
	}

	return empresas, int64(len(empresas)), nil
}

func (r *EmpresaRepository) Delete(ctx context.Context, id, tenantID string) ([]domain.EmpresaMutationItem, int64, error) {
	const query = `
		UPDATE public.empresa
		SET ativo = false
		WHERE id = $1 AND tenant_id = $2
		RETURNING id, nome, municipio_id, tenant_id, rotina_id, cnaes, iniciado, ativo`

	rows, err := r.pool.Query(ctx, query, id, tenantID)
	if err != nil {
		return nil, 0, fmt.Errorf("delete empresa: %w", err)
	}
	defer rows.Close()

	empresas := make([]domain.EmpresaMutationItem, 0)
	for rows.Next() {
		var eid, nome, tenantID string
		var municipioID, rotinaID sql.NullString
		var cnaes any
		var iniciado, ativo bool
		if err := rows.Scan(&eid, &nome, &municipioID, &tenantID, &rotinaID, &cnaes, &iniciado, &ativo); err != nil {
			return nil, 0, fmt.Errorf("scan deleted empresa: %w", err)
		}
		empresas = append(empresas, domain.EmpresaMutationItem{
			ID:          eid,
			Nome:        nome,
			MunicipioID: empresaMunicipioScanString(municipioID),
			TenantID:    tenantID,
			RotinaID:    empresaRotinaScanString(rotinaID),
			Cnaes:       cnaes,
			Iniciado:    iniciado,
			Ativo:       ativo,
		})
	}

	return empresas, int64(len(empresas)), nil
}

// MunicipioEUfIDs retorna municipio_id e ufid do município da empresa (escopo tenant).
func (r *EmpresaRepository) MunicipioEUfIDs(ctx context.Context, empresaID, tenantID string) (municipioID string, ufID string, err error) {
	err = r.pool.QueryRow(ctx, `
		SELECT COALESCE(e.municipio_id, ed.municipio_id)::text, m.ufid
		FROM public.empresa e
		LEFT JOIN public.empresa_dados ed ON ed.empresa_id = e.id
		INNER JOIN public.municipio m ON m.id = COALESCE(e.municipio_id, ed.municipio_id)
		WHERE e.id = $1 AND e.tenant_id = $2 AND e.ativo = true`,
		empresaID, tenantID,
	).Scan(&municipioID, &ufID)
	if err != nil {
		return "", "", fmt.Errorf("empresa nao encontrada neste tenant ou município não informado nos dados complementares: %w", err)
	}
	return municipioID, ufID, nil
}

// TipoEmpresaIDFromRotina retorna o tipo de empresa cadastrado na rotina vinculada à empresa.
func (r *EmpresaRepository) TipoEmpresaIDFromRotina(ctx context.Context, empresaID string) (string, error) {
	var tid *string
	err := r.pool.QueryRow(ctx, `
		SELECT r.tipo_empresa_id
		FROM public.empresa e
		INNER JOIN public.rotinas r ON r.id = e.rotina_id
		WHERE e.id = $1 AND e.ativo = true`, empresaID).Scan(&tid)
	if err != nil {
		return "", fmt.Errorf("buscar tipo de empresa da rotina: %w", err)
	}
	if tid == nil || strings.TrimSpace(*tid) == "" {
		return "", fmt.Errorf("cadastre o tipo de empresa na rotina desta empresa antes de gerar compromissos")
	}
	return strings.TrimSpace(*tid), nil
}
