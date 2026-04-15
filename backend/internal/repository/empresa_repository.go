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

type EmpresaListParams struct {
	First      int
	Rows       int
	SortField  string
	SortOrder  int
	Nome       string
	TenantID   string
	TipoPessoa string
}

type EmpresaUpsertInput struct {
	ID                 string
	Nome               string
	TenantID           string
	MunicipioID        string
	RotinaID           string
	RotinaPFID         string
	Cnaes              any
	Bairro             string
	TipoPessoa         string
	Documento          string
	IE                 string
	IM                 string
	RegimeTributarioID string
	TipoEmpresaID      string
}

type EmpresaProcessoInput struct {
	ID        string
	EmpresaID string
	TenantID  string
	RotinaID  string
	Descricao string
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

func empresaMunicipioIDParam(s string) any {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return strings.TrimSpace(s)
}

func empresaRegimeTributarioIDParam(tipo, regimeID string) any {
	if normalizeEmpresaTipoPessoa(tipo) == "PF" {
		return nil
	}
	if id := strings.TrimSpace(regimeID); id != "" {
		return id
	}
	return nil
}

func empresaTipoEmpresaIDParam(tipo, tipoEmpresaID string) any {
	if normalizeEmpresaTipoPessoa(tipo) == "PF" {
		return nil
	}
	if id := strings.TrimSpace(tipoEmpresaID); id != "" {
		return id
	}
	return nil
}

func (r *EmpresaRepository) List(ctx context.Context, params EmpresaListParams) ([]domain.EmpresaListItem, int64, error) {
	whereParts := []string{"e.ativo = true", "e.tenant_id = $1", "c.ativo = true"}
	args := []any{params.TenantID}
	argIndex := 2

	if strings.TrimSpace(params.Nome) != "" {
		whereParts = append(whereParts, fmt.Sprintf("c.nome ILIKE $%d", argIndex))
		args = append(args, "%"+strings.TrimSpace(params.Nome)+"%")
		argIndex++
	}
	if tp := strings.ToUpper(strings.TrimSpace(params.TipoPessoa)); tp == "PF" || tp == "PJ" {
		whereParts = append(whereParts, fmt.Sprintf("UPPER(COALESCE(NULLIF(BTRIM(c.tipo_pessoa::text), ''), 'PJ')) = $%d", argIndex))
		args = append(args, tp)
		argIndex++
	}

	orderBy := "c.nome ASC"
	switch params.SortField {
	case "nome":
		if params.SortOrder == -1 {
			orderBy = "c.nome ASC"
		} else {
			orderBy = "c.nome DESC"
		}
	case "codigo":
		if params.SortOrder == -1 {
			orderBy = "e.id ASC"
		} else {
			orderBy = "e.id DESC"
		}
	}

	query := fmt.Sprintf(`
		SELECT
			e.id,
			c.nome,
			COALESCE(NULLIF(BTRIM(c.tipo_pessoa::text), ''), 'PJ'),
			COALESCE(NULLIF(BTRIM(c.documento), ''), ''),
			COALESCE(c.ie, ''),
			COALESCE(c.im, ''),
			COALESCE(rt.id::text, ''),
			COALESCE(rt.nome, ''),
			COALESCE(rt.codigo_crt, 0),
			COALESCE(m.id::text, ''),
			COALESCE(m.nome, ''),
			'' AS rotina_id,
			'' AS rotina_descricao,
			COALESCE(NULLIF(BTRIM(te_cli.id::text), ''), ''),
			COALESCE(NULLIF(BTRIM(te_cli.descricao), ''), ''),
			'' AS rotina_pf_id,
			'' AS rotina_pf_nome,
			'' AS rotina_pf_categoria,
			c.cnaes,
			COALESCE(c.bairro, ''),
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
		INNER JOIN public.cliente c ON c.id = e.cliente_id
		LEFT JOIN public.clientes_dados ed ON ed.cliente_id = c.id
		LEFT JOIN public.municipio m ON m.id = COALESCE(c.municipio_id, ed.municipio_id)
		LEFT JOIN public.tipoempresa te_cli ON te_cli.id = c.tipo_empresa_id
		LEFT JOIN public.regime_tributario rt ON rt.id = c.regime_tributario_id
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
		var id, nome, tpessoa, doc, ie, im, rtid, rtnome string
		var rtcod int32
		var mid, mnome, rid, rdesc, teid, tedesc, rpfid, rpfnome, rpfcat, ebairro string
		var iniciado, passosConcluidos, compromissosGerados bool
		var cnaes any
		if err := rows.Scan(&id, &nome, &tpessoa, &doc, &ie, &im, &rtid, &rtnome, &rtcod, &mid, &mnome, &rid, &rdesc, &teid, &tedesc, &rpfid, &rpfnome, &rpfcat, &cnaes, &ebairro, &iniciado, &passosConcluidos, &compromissosGerados); err != nil {
			return nil, 0, fmt.Errorf("scan empresa: %w", err)
		}

		item := domain.EmpresaListItem{
			ID:         id,
			Nome:       nome,
			TipoPessoa: tpessoa,
			Documento:  doc,
			IE:         ie,
			IM:         im,
			Municipio: domain.EmpresaRef{
				ID:   mid,
				Nome: mnome,
			},
			Cnaes:               cnaes,
			Bairro:              ebairro,
			Iniciado:            iniciado,
			PassosConcluidos:    passosConcluidos,
			CompromissosGerados: compromissosGerados,
			RegimeTributario: domain.EmpresaRegimeTributarioRef{
				ID:        rtid,
				Nome:      rtnome,
				CodigoCRT: int(rtcod),
			},
		}
		item.Rotina.ID = rid
		item.Rotina.Descricao = rdesc
		item.RotinaPF.ID = rpfid
		item.RotinaPF.Nome = rpfnome
		item.RotinaPF.Categoria = rpfcat
		item.TipoEmpresa.ID = teid
		item.TipoEmpresa.Descricao = tedesc
		empresas = append(empresas, item)
	}

	countQuery := fmt.Sprintf(
		"SELECT count(*) FROM public.empresa e INNER JOIN public.cliente c ON c.id = e.cliente_id WHERE %s",
		strings.Join(whereParts, " AND "))
	var total int64
	if err := r.pool.QueryRow(ctx, countQuery, args[:len(args)-2]...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count empresa: %w", err)
	}

	return empresas, total, nil
}

func (r *EmpresaRepository) Create(ctx context.Context, input EmpresaUpsertInput) ([]domain.EmpresaMutationItem, int64, error) {
	const existsQuery = `
		SELECT count(*) FROM public.cliente c
		WHERE c.tenant_id = $1 AND lower(trim(c.nome)) = lower(trim($2)) AND c.ativo = true`
	var count int64
	if err := r.pool.QueryRow(ctx, existsQuery, input.TenantID, input.Nome).Scan(&count); err != nil {
		return nil, 0, fmt.Errorf("check cliente exists: %w", err)
	}
	if count > 0 {
		return nil, 0, fmt.Errorf("Empresa ja cadastrada")
	}

	tipo := normalizeEmpresaTipoPessoa(input.TipoPessoa)
	doc := strings.TrimSpace(input.Documento)

	cnaes := normalizeCnaesParaTextArray(input.Cnaes)
	if cnaes == nil {
		cnaes = []string{}
	}
	cnaesArg := empresaCnaesParam(tipo, cnaes)
	tipoEmpresaArg := empresaTipoEmpresaIDParam(tipo, input.TipoEmpresaID)

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, 0, fmt.Errorf("begin create empresa: %w", err)
	}
	defer tx.Rollback(ctx)

	const insCliente = `
		INSERT INTO public.cliente (tenant_id, nome, tipo_pessoa, documento, municipio_id, cnaes, bairro, ie, im, regime_tributario_id, tipo_empresa_id)
		VALUES ($1, $2, $3, NULLIF(TRIM($4), ''), $5, $6, NULLIF(TRIM($7), ''), TRIM(COALESCE($8::text, '')), TRIM(COALESCE($9::text, '')), $10, $11)
		RETURNING id::text`

	var clienteID string
	if err := tx.QueryRow(ctx, insCliente,
		input.TenantID,
		input.Nome,
		tipo,
		doc,
		empresaMunicipioIDParam(input.MunicipioID),
		cnaesArg,
		input.Bairro,
		strings.TrimSpace(input.IE),
		strings.TrimSpace(input.IM),
		empresaRegimeTributarioIDParam(tipo, input.RegimeTributarioID),
		tipoEmpresaArg,
	).Scan(&clienteID); err != nil {
		return nil, 0, fmt.Errorf("create cliente: %w", err)
	}

	const insEmpresa = `
		INSERT INTO public.empresa (tenant_id, cliente_id)
		VALUES ($1, $2)
		RETURNING id::text`

	var empresaID string
	if err := tx.QueryRow(ctx, insEmpresa, input.TenantID, clienteID).Scan(&empresaID); err != nil {
		return nil, 0, fmt.Errorf("create empresa: %w", err)
	}

	const sel = `
		SELECT e.id, c.nome, c.municipio_id, e.tenant_id, c.cnaes, e.iniciado, e.ativo
		FROM public.empresa e
		INNER JOIN public.cliente c ON c.id = e.cliente_id
		WHERE e.id = $1`

	rows, err := tx.Query(ctx, sel, empresaID)
	if err != nil {
		return nil, 0, fmt.Errorf("load created empresa: %w", err)
	}
	defer rows.Close()

	empresas := make([]domain.EmpresaMutationItem, 0)
	for rows.Next() {
		var id, nome, tenantID string
		var municipioID sql.NullString
		var cnaesOut any
		var iniciado, ativo bool
		if err := rows.Scan(&id, &nome, &municipioID, &tenantID, &cnaesOut, &iniciado, &ativo); err != nil {
			return nil, 0, fmt.Errorf("scan created empresa: %w", err)
		}
		empresas = append(empresas, domain.EmpresaMutationItem{
			ID:          id,
			Nome:        nome,
			MunicipioID: empresaMunicipioScanString(municipioID),
			TenantID:    tenantID,
			RotinaID:    "",
			RotinaPFID:  "",
			Cnaes:       cnaesOut,
			Iniciado:    iniciado,
			Ativo:       ativo,
		})
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, 0, fmt.Errorf("commit create empresa: %w", err)
	}

	return empresas, int64(len(empresas)), nil
}

func (r *EmpresaRepository) Update(ctx context.Context, input EmpresaUpsertInput) ([]domain.EmpresaMutationItem, int64, error) {
	tipo := normalizeEmpresaTipoPessoa(input.TipoPessoa)
	doc := strings.TrimSpace(input.Documento)

	const query = `
		UPDATE public.cliente c
		SET nome = $1,
		    tenant_id = $2,
		    cnaes = $3,
		    bairro = NULLIF(TRIM($6), ''),
		    tipo_pessoa = $7,
		    documento = NULLIF(TRIM($8), ''),
		    municipio_id = $9,
		    ie = TRIM(COALESCE($10::text, '')),
		    im = TRIM(COALESCE($11::text, '')),
		    regime_tributario_id = $12,
		    tipo_empresa_id = $13,
		    atualizado_em = NOW()
		FROM public.empresa e
		WHERE c.id = e.cliente_id AND e.id = $4 AND e.tenant_id = $5
		RETURNING e.id, c.nome, c.municipio_id, e.tenant_id, c.cnaes, e.iniciado, e.ativo`

	cnaes := normalizeCnaesParaTextArray(input.Cnaes)
	if cnaes == nil {
		cnaes = []string{}
	}
	cnaesArg := empresaCnaesParam(tipo, cnaes)
	regimeArg := empresaRegimeTributarioIDParam(tipo, input.RegimeTributarioID)
	tipoEmpresaArg := empresaTipoEmpresaIDParam(tipo, input.TipoEmpresaID)
	rows, err := r.pool.Query(ctx, query, input.Nome, input.TenantID, cnaesArg, input.ID, input.TenantID, input.Bairro, tipo, doc, empresaMunicipioIDParam(input.MunicipioID), strings.TrimSpace(input.IE), strings.TrimSpace(input.IM), regimeArg, tipoEmpresaArg)
	if err != nil {
		return nil, 0, fmt.Errorf("update empresa: %w", err)
	}
	defer rows.Close()

	empresas := make([]domain.EmpresaMutationItem, 0)
	for rows.Next() {
		var id, nome, tenantID string
		var municipioID sql.NullString
		var cnaes any
		var iniciado, ativo bool
		if err := rows.Scan(&id, &nome, &municipioID, &tenantID, &cnaes, &iniciado, &ativo); err != nil {
			return nil, 0, fmt.Errorf("scan updated empresa: %w", err)
		}
		empresas = append(empresas, domain.EmpresaMutationItem{
			ID:          id,
			Nome:        nome,
			MunicipioID: empresaMunicipioScanString(municipioID),
			TenantID:    tenantID,
			RotinaID:    "",
			RotinaPFID:  "",
			Cnaes:       cnaes,
			Iniciado:    iniciado,
			Ativo:       ativo,
		})
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("update empresa rows: %w", err)
	}
	if len(empresas) == 0 {
		return nil, 0, fmt.Errorf("nenhuma linha atualizada: verifique id da empresa e tenant")
	}

	return empresas, int64(len(empresas)), nil
}

func (r *EmpresaRepository) IniciarProcesso(ctx context.Context, id, tenantID string) ([]domain.EmpresaMutationItem, int64, error) {
	const query = `
		UPDATE public.empresa e
		SET iniciado = true
		FROM public.cliente c
		WHERE e.cliente_id = c.id AND e.id = $1 AND e.tenant_id = $2
		RETURNING e.id, c.nome, c.municipio_id, e.tenant_id, c.cnaes, e.iniciado, e.ativo`

	rows, err := r.pool.Query(ctx, query, id, tenantID)
	if err != nil {
		return nil, 0, fmt.Errorf("iniciar processo empresa: %w", err)
	}
	defer rows.Close()

	empresas := make([]domain.EmpresaMutationItem, 0)
	for rows.Next() {
		var eid, nome, tenantID string
		var municipioID sql.NullString
		var cnaes any
		var iniciado, ativo bool
		if err := rows.Scan(&eid, &nome, &municipioID, &tenantID, &cnaes, &iniciado, &ativo); err != nil {
			return nil, 0, fmt.Errorf("scan iniciar processo empresa: %w", err)
		}
		empresas = append(empresas, domain.EmpresaMutationItem{
			ID:          eid,
			Nome:        nome,
			MunicipioID: empresaMunicipioScanString(municipioID),
			TenantID:    tenantID,
			RotinaID:    "",
			RotinaPFID:  "",
			Cnaes:       cnaes,
			Iniciado:    iniciado,
			Ativo:       ativo,
		})
	}

	return empresas, int64(len(empresas)), nil
}

func (r *EmpresaRepository) ListProcessos(ctx context.Context, empresaID, tenantID string) ([]domain.EmpresaProcessoItem, int64, error) {
	whereParts := []string{"ep.tenant_id = $1", "ep.ativo = true"}
	args := []any{tenantID}
	argIndex := 2

	if strings.TrimSpace(empresaID) != "" {
		whereParts = append(whereParts, fmt.Sprintf("ep.empresa_id = $%d", argIndex))
		args = append(args, strings.TrimSpace(empresaID))
		argIndex++
	}

	query := fmt.Sprintf(`
		SELECT
			ep.id::text,
			ep.empresa_id::text,
			ep.tenant_id::text,
			COALESCE(ep.rotina_id::text, ''),
			ep.descricao,
			ep.criado_em::text,
			ep.iniciado,
			ep.passos_concluidos,
			ep.compromissos_gerados,
			ep.ativo
		FROM public.empresa_processos ep
		WHERE %s
		ORDER BY ep.criado_em DESC, ep.id DESC`, strings.Join(whereParts, " AND "))

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list empresa processos: %w", err)
	}
	defer rows.Close()

	items := make([]domain.EmpresaProcessoItem, 0)
	for rows.Next() {
		var item domain.EmpresaProcessoItem
		if err := rows.Scan(
			&item.ID,
			&item.EmpresaID,
			&item.TenantID,
			&item.RotinaID,
			&item.Descricao,
			&item.CriadoEm,
			&item.Iniciado,
			&item.PassosConcluidos,
			&item.CompromissosGerados,
			&item.Ativo,
		); err != nil {
			return nil, 0, fmt.Errorf("scan empresa processo: %w", err)
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("list empresa processos rows: %w", err)
	}
	return items, int64(len(items)), nil
}

func (r *EmpresaRepository) CreateProcesso(ctx context.Context, input EmpresaProcessoInput) ([]domain.EmpresaProcessoItem, int64, error) {
	const query = `
		INSERT INTO public.empresa_processos (tenant_id, empresa_id, rotina_id, descricao)
		VALUES ($1, $2, NULLIF($3::text, '')::uuid, $4)
		RETURNING id::text, empresa_id::text, tenant_id::text, COALESCE(rotina_id::text, ''), descricao, criado_em::text, iniciado, passos_concluidos, compromissos_gerados, ativo`

	rows, err := r.pool.Query(ctx, query, input.TenantID, input.EmpresaID, strings.TrimSpace(input.RotinaID), strings.TrimSpace(input.Descricao))
	if err != nil {
		return nil, 0, fmt.Errorf("create empresa processo: %w", err)
	}
	defer rows.Close()

	items := make([]domain.EmpresaProcessoItem, 0, 1)
	for rows.Next() {
		var item domain.EmpresaProcessoItem
		if err := rows.Scan(
			&item.ID,
			&item.EmpresaID,
			&item.TenantID,
			&item.RotinaID,
			&item.Descricao,
			&item.CriadoEm,
			&item.Iniciado,
			&item.PassosConcluidos,
			&item.CompromissosGerados,
			&item.Ativo,
		); err != nil {
			return nil, 0, fmt.Errorf("scan created empresa processo: %w", err)
		}
		items = append(items, item)
	}
	if len(items) == 0 {
		return nil, 0, fmt.Errorf("processo nao encontrado neste tenant ou ja inativo")
	}
	return items, int64(len(items)), nil
}

func (r *EmpresaRepository) IniciarProcessoFilho(ctx context.Context, processoID, tenantID string) ([]domain.EmpresaProcessoItem, int64, error) {
	const query = `
		UPDATE public.empresa_processos ep
		SET iniciado = true, atualizado_em = NOW()
		WHERE ep.id = $1 AND ep.tenant_id = $2 AND ep.ativo = true
		RETURNING id::text, empresa_id::text, tenant_id::text, COALESCE(rotina_id::text, ''), descricao, criado_em::text, iniciado, passos_concluidos, compromissos_gerados, ativo`

	rows, err := r.pool.Query(ctx, query, processoID, tenantID)
	if err != nil {
		return nil, 0, fmt.Errorf("iniciar empresa processo: %w", err)
	}
	defer rows.Close()

	items := make([]domain.EmpresaProcessoItem, 0, 1)
	for rows.Next() {
		var item domain.EmpresaProcessoItem
		if err := rows.Scan(
			&item.ID,
			&item.EmpresaID,
			&item.TenantID,
			&item.RotinaID,
			&item.Descricao,
			&item.CriadoEm,
			&item.Iniciado,
			&item.PassosConcluidos,
			&item.CompromissosGerados,
			&item.Ativo,
		); err != nil {
			return nil, 0, fmt.Errorf("scan iniciar empresa processo: %w", err)
		}
		if err := r.ensureAgendaForProcesso(ctx, item.EmpresaID, item.TenantID, item.RotinaID); err != nil {
			return nil, 0, fmt.Errorf("gerar agenda do processo iniciado: %w", err)
		}
		items = append(items, item)
	}
	return items, int64(len(items)), nil
}

func (r *EmpresaRepository) ensureAgendaForProcesso(ctx context.Context, empresaID, tenantID, rotinaID string) error {
	empresaID = strings.TrimSpace(empresaID)
	tenantID = strings.TrimSpace(tenantID)
	rotinaID = strings.TrimSpace(rotinaID)
	if empresaID == "" || tenantID == "" || rotinaID == "" {
		return nil
	}

	const q = `
		WITH nova_agenda AS (
			INSERT INTO public.agenda (empresa_id, tenant_id, rotina_id, inicio)
			VALUES ($1::uuid, $2::uuid, $3::uuid, CURRENT_DATE)
			RETURNING id
		),
		itens AS (
			INSERT INTO public.agendaitens (agenda_id, passo_id, inicio, termino, descricao)
			SELECT
				na.id,
				ri.passo_id,
				CURRENT_DATE,
				public.calcular_data_termino(CURRENT_DATE, COALESCE(p.tempoestimado, 0)),
				COALESCE(p.descricao, '')
			FROM nova_agenda na
			JOIN public.rotinaitens ri ON ri.rotina_id = $3::uuid
			LEFT JOIN public.passos p ON p.id = ri.passo_id
			ORDER BY ri.ordem
			RETURNING agenda_id, termino
		)
		UPDATE public.agenda a
		SET termino = COALESCE((SELECT MAX(i.termino) FROM itens i), CURRENT_DATE)
		FROM nova_agenda na
		WHERE a.id = na.id`

	if _, err := r.pool.Exec(ctx, q, empresaID, tenantID, rotinaID); err != nil {
		return err
	}
	return nil
}

func (r *EmpresaRepository) MarcarCompromissosProcesso(ctx context.Context, processoID, tenantID string) ([]domain.EmpresaProcessoItem, int64, error) {
	const query = `
		UPDATE public.empresa_processos ep
		SET compromissos_gerados = true, passos_concluidos = true, atualizado_em = NOW()
		WHERE ep.id = $1 AND ep.tenant_id = $2 AND ep.ativo = true
		RETURNING id::text, empresa_id::text, tenant_id::text, COALESCE(rotina_id::text, ''), descricao, criado_em::text, iniciado, passos_concluidos, compromissos_gerados, ativo`

	rows, err := r.pool.Query(ctx, query, processoID, tenantID)
	if err != nil {
		return nil, 0, fmt.Errorf("marcar compromissos processo: %w", err)
	}
	defer rows.Close()

	items := make([]domain.EmpresaProcessoItem, 0, 1)
	for rows.Next() {
		var item domain.EmpresaProcessoItem
		if err := rows.Scan(
			&item.ID,
			&item.EmpresaID,
			&item.TenantID,
			&item.RotinaID,
			&item.Descricao,
			&item.CriadoEm,
			&item.Iniciado,
			&item.PassosConcluidos,
			&item.CompromissosGerados,
			&item.Ativo,
		); err != nil {
			return nil, 0, fmt.Errorf("scan compromissos processo: %w", err)
		}
		items = append(items, item)
	}
	return items, int64(len(items)), nil
}

func (r *EmpresaRepository) Delete(ctx context.Context, id, tenantID string) ([]domain.EmpresaMutationItem, int64, error) {
	const query = `
		UPDATE public.empresa e
		SET ativo = false
		FROM public.cliente c
		WHERE e.cliente_id = c.id AND e.id = $1 AND e.tenant_id = $2
		RETURNING e.id, c.nome, c.municipio_id, e.tenant_id, c.cnaes, e.iniciado, e.ativo`

	rows, err := r.pool.Query(ctx, query, id, tenantID)
	if err != nil {
		return nil, 0, fmt.Errorf("delete empresa: %w", err)
	}
	defer rows.Close()

	empresas := make([]domain.EmpresaMutationItem, 0)
	for rows.Next() {
		var eid, nome, tenantID string
		var municipioID sql.NullString
		var cnaes any
		var iniciado, ativo bool
		if err := rows.Scan(&eid, &nome, &municipioID, &tenantID, &cnaes, &iniciado, &ativo); err != nil {
			return nil, 0, fmt.Errorf("scan deleted empresa: %w", err)
		}
		empresas = append(empresas, domain.EmpresaMutationItem{
			ID:          eid,
			Nome:        nome,
			MunicipioID: empresaMunicipioScanString(municipioID),
			TenantID:    tenantID,
			RotinaID:    "",
			RotinaPFID:  "",
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
		SELECT COALESCE(c.municipio_id, ed.municipio_id)::text, m.ufid
		FROM public.empresa e
		INNER JOIN public.cliente c ON c.id = e.cliente_id
		LEFT JOIN public.clientes_dados ed ON ed.cliente_id = c.id
		INNER JOIN public.municipio m ON m.id = COALESCE(c.municipio_id, ed.municipio_id)
		WHERE e.id = $1 AND e.tenant_id = $2 AND e.ativo = true`,
		empresaID, tenantID,
	).Scan(&municipioID, &ufID)
	if err != nil {
		return "", "", fmt.Errorf("empresa nao encontrada neste tenant ou município não informado nos dados complementares: %w", err)
	}
	return municipioID, ufID, nil
}

// TipoEmpresaIDFromRotina retorna o tipo de empresa do cliente ou da rotina do processo mais recente.
func (r *EmpresaRepository) TipoEmpresaIDFromRotina(ctx context.Context, empresaID string) (string, error) {
	var tid *string
	err := r.pool.QueryRow(ctx, `
		SELECT COALESCE(
			NULLIF(TRIM(c.tipo_empresa_id::text), ''),
			NULLIF(TRIM(r.tipo_empresa_id::text), '')
		)
		FROM public.empresa e
		INNER JOIN public.cliente c ON c.id = e.cliente_id
		LEFT JOIN public.empresa_processos ep ON ep.empresa_id = e.id AND ep.ativo = true
		LEFT JOIN public.rotinas r ON r.id = ep.rotina_id
		WHERE e.id = $1 AND e.ativo = true
		ORDER BY ep.criado_em DESC NULLS LAST
		LIMIT 1`, empresaID).Scan(&tid)
	if err != nil {
		return "", fmt.Errorf("buscar tipo de empresa da rotina: %w", err)
	}
	if tid == nil || strings.TrimSpace(*tid) == "" {
		return "", fmt.Errorf("cadastre o tipo de empresa na rotina desta empresa antes de gerar compromissos")
	}
	return strings.TrimSpace(*tid), nil
}
