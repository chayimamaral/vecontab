package repository

import (
	"context"
	"fmt"
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
	Cnaes               any  `json:"cnaes"`
	Iniciado            bool `json:"iniciado"`
	PassosConcluidos    bool `json:"passos_concluidos"`
	CompromissosGerados bool `json:"compromissos_gerados"`
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
			e.cnaes,
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
				FROM public.empresa_agenda ea
				WHERE ea.empresa_id = e.id
			) AS compromissos_gerados
		FROM public.empresa e
		JOIN public.municipio m ON m.id = e.municipio_id
		JOIN public.rotinas r ON r.id = e.rotina_id
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
		var id, nome, mid, mnome, rid, rdesc string
		var iniciado, passosConcluidos, compromissosGerados bool
		var cnaes any
		if err := rows.Scan(&id, &nome, &mid, &mnome, &rid, &rdesc, &cnaes, &iniciado, &passosConcluidos, &compromissosGerados); err != nil {
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
			Iniciado:            iniciado,
			PassosConcluidos:    passosConcluidos,
			CompromissosGerados: compromissosGerados,
		}
		item.Rotina.ID = rid
		item.Rotina.Descricao = rdesc
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
		INSERT INTO public.empresa (nome, municipio_id, tenant_id, rotina_id, cnaes)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, nome, municipio_id, tenant_id, rotina_id, cnaes, iniciado, ativo`

	rows, err := r.pool.Query(ctx, query, input.Nome, input.MunicipioID, input.TenantID, input.RotinaID, input.Cnaes)
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
		SET nome = $1, municipio_id = $2, tenant_id = $3, rotina_id = $4, cnaes = $5
		WHERE id = $6 AND tenant_id = $7
		RETURNING id, nome, municipio_id, tenant_id, rotina_id, cnaes, iniciado, ativo`

	rows, err := r.pool.Query(ctx, query, input.Nome, input.MunicipioID, input.TenantID, input.RotinaID, input.Cnaes, input.ID, input.TenantID)
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
