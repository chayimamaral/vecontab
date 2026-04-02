package repository

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

type EmpresaListParams struct {
	First     int
	Rows      int
	SortField string
	SortOrder int
	Nome      string
	TenantID  string
}

type EmpresaUpsertInput struct {
	ID          string
	Nome        string
	MunicipioID string
	TenantID    string
	RotinaID    string
	Cnaes       any
	Bairro      string
}

type EmpresaRepository struct {
	pool *pgxpool.Pool
}

type EmpresaRef struct {
	ID   string `json:"id"`
	Nome string `json:"nome"`
}

type EmpresaListItem struct {
	ID        string     `json:"id"`
	Nome      string     `json:"nome"`
	Municipio EmpresaRef `json:"municipio"`
	Rotina    struct {
		ID        string `json:"id"`
		Descricao string `json:"descricao"`
	} `json:"rotina"`
	TipoEmpresa struct {
		ID        string `json:"id"`
		Descricao string `json:"descricao"`
	} `json:"tipo_empresa"`
	Cnaes               any    `json:"cnaes"`
	Bairro              string `json:"bairro"`
	Iniciado            bool   `json:"iniciado"`
	PassosConcluidos    bool   `json:"passos_concluidos"`
	CompromissosGerados bool   `json:"compromissos_gerados"`
}

type EmpresaMutationItem struct {
	ID          string `json:"id"`
	Nome        string `json:"nome"`
	MunicipioID string `json:"municipio_id"`
	TenantID    string `json:"tenant_id"`
	RotinaID    string `json:"rotina_id"`
	Cnaes       any    `json:"cnaes"`
	Iniciado    bool   `json:"iniciado"`
	Ativo       bool   `json:"ativo"`
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

func (r *EmpresaRepository) List(ctx context.Context, params EmpresaListParams) ([]EmpresaListItem, int64, error) {
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
			m.id,
			m.nome,
			r.id,
			r.descricao,
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
		JOIN public.municipio m ON m.id = e.municipio_id
		JOIN public.rotinas r ON r.id = e.rotina_id
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

	empresas := make([]EmpresaListItem, 0)
	for rows.Next() {
		var id, nome, mid, mnome, rid, rdesc, teid, tedesc, ebairro string
		var iniciado, passosConcluidos, compromissosGerados bool
		var cnaes any
		if err := rows.Scan(&id, &nome, &mid, &mnome, &rid, &rdesc, &teid, &tedesc, &cnaes, &ebairro, &iniciado, &passosConcluidos, &compromissosGerados); err != nil {
			return nil, 0, fmt.Errorf("scan empresa: %w", err)
		}

		item := EmpresaListItem{
			ID:   id,
			Nome: nome,
			Municipio: EmpresaRef{
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

func (r *EmpresaRepository) Create(ctx context.Context, input EmpresaUpsertInput) ([]EmpresaMutationItem, int64, error) {
	const existsQuery = `SELECT count(*) FROM public.empresa WHERE nome = $1`
	var count int64
	if err := r.pool.QueryRow(ctx, existsQuery, input.Nome).Scan(&count); err != nil {
		return nil, 0, fmt.Errorf("check empresa exists: %w", err)
	}
	if count > 0 {
		return nil, 0, fmt.Errorf("Empresa ja cadastrada")
	}

	const query = `
		INSERT INTO public.empresa (nome, municipio_id, tenant_id, rotina_id, cnaes, bairro)
		VALUES ($1, $2, $3, $4, $5, NULLIF(TRIM($6), ''))
		RETURNING id, nome, municipio_id, tenant_id, rotina_id, cnaes, iniciado, ativo`

	cnaes := normalizeCnaesParaTextArray(input.Cnaes)
	if cnaes == nil {
		cnaes = []string{}
	}
	rows, err := r.pool.Query(ctx, query, input.Nome, input.MunicipioID, input.TenantID, input.RotinaID, cnaes, input.Bairro)
	if err != nil {
		return nil, 0, fmt.Errorf("create empresa: %w", err)
	}
	defer rows.Close()

	empresas := make([]EmpresaMutationItem, 0)
	for rows.Next() {
		var id, nome, municipioID, tenantID, rotinaID string
		var cnaes any
		var iniciado, ativo bool
		if err := rows.Scan(&id, &nome, &municipioID, &tenantID, &rotinaID, &cnaes, &iniciado, &ativo); err != nil {
			return nil, 0, fmt.Errorf("scan created empresa: %w", err)
		}
		empresas = append(empresas, EmpresaMutationItem{
			ID:          id,
			Nome:        nome,
			MunicipioID: municipioID,
			TenantID:    tenantID,
			RotinaID:    rotinaID,
			Cnaes:       cnaes,
			Iniciado:    iniciado,
			Ativo:       ativo,
		})
	}

	return empresas, int64(len(empresas)), nil
}

func (r *EmpresaRepository) Update(ctx context.Context, input EmpresaUpsertInput) ([]EmpresaMutationItem, int64, error) {
	const query = `
		UPDATE public.empresa
		SET nome = $1, municipio_id = $2, tenant_id = $3, rotina_id = $4, cnaes = $5, bairro = NULLIF(TRIM($8), '')
		WHERE id = $6 AND tenant_id = $7
		RETURNING id, nome, municipio_id, tenant_id, rotina_id, cnaes, iniciado, ativo`

	cnaes := normalizeCnaesParaTextArray(input.Cnaes)
	if cnaes == nil {
		cnaes = []string{}
	}
	rows, err := r.pool.Query(ctx, query, input.Nome, input.MunicipioID, input.TenantID, input.RotinaID, cnaes, input.ID, input.TenantID, input.Bairro)
	if err != nil {
		return nil, 0, fmt.Errorf("update empresa: %w", err)
	}
	defer rows.Close()

	empresas := make([]EmpresaMutationItem, 0)
	for rows.Next() {
		var id, nome, municipioID, tenantID, rotinaID string
		var cnaes any
		var iniciado, ativo bool
		if err := rows.Scan(&id, &nome, &municipioID, &tenantID, &rotinaID, &cnaes, &iniciado, &ativo); err != nil {
			return nil, 0, fmt.Errorf("scan updated empresa: %w", err)
		}
		empresas = append(empresas, EmpresaMutationItem{
			ID:          id,
			Nome:        nome,
			MunicipioID: municipioID,
			TenantID:    tenantID,
			RotinaID:    rotinaID,
			Cnaes:       cnaes,
			Iniciado:    iniciado,
			Ativo:       ativo,
		})
	}

	return empresas, int64(len(empresas)), nil
}

func (r *EmpresaRepository) IniciarProcesso(ctx context.Context, id, tenantID string) ([]EmpresaMutationItem, int64, error) {
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

	empresas := make([]EmpresaMutationItem, 0)
	for rows.Next() {
		var eid, nome, municipioID, tenantID, rotinaID string
		var cnaes any
		var iniciado, ativo bool
		if err := rows.Scan(&eid, &nome, &municipioID, &tenantID, &rotinaID, &cnaes, &iniciado, &ativo); err != nil {
			return nil, 0, fmt.Errorf("scan iniciar processo empresa: %w", err)
		}
		empresas = append(empresas, EmpresaMutationItem{
			ID:          eid,
			Nome:        nome,
			MunicipioID: municipioID,
			TenantID:    tenantID,
			RotinaID:    rotinaID,
			Cnaes:       cnaes,
			Iniciado:    iniciado,
			Ativo:       ativo,
		})
	}

	return empresas, int64(len(empresas)), nil
}

func (r *EmpresaRepository) Delete(ctx context.Context, id, tenantID string) ([]EmpresaMutationItem, int64, error) {
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

	empresas := make([]EmpresaMutationItem, 0)
	for rows.Next() {
		var eid, nome, municipioID, tenantID, rotinaID string
		var cnaes any
		var iniciado, ativo bool
		if err := rows.Scan(&eid, &nome, &municipioID, &tenantID, &rotinaID, &cnaes, &iniciado, &ativo); err != nil {
			return nil, 0, fmt.Errorf("scan deleted empresa: %w", err)
		}
		empresas = append(empresas, EmpresaMutationItem{
			ID:          eid,
			Nome:        nome,
			MunicipioID: municipioID,
			TenantID:    tenantID,
			RotinaID:    rotinaID,
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
		SELECT e.municipio_id, m.ufid
		FROM public.empresa e
		INNER JOIN public.municipio m ON m.id = e.municipio_id
		WHERE e.id = $1 AND e.tenant_id = $2 AND e.ativo = true`,
		empresaID, tenantID,
	).Scan(&municipioID, &ufID)
	if err != nil {
		return "", "", fmt.Errorf("empresa nao encontrada neste tenant: %w", err)
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
