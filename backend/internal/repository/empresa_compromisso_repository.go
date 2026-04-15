package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type EmpresaCompromissoCreateManualInput struct {
	EmpresaID              string
	TipoempresaObrigacaoID string
	Descricao              string
	Vencimento             time.Time
	Valor                  *float64
	Observacao             string
	Status                 string
}

type empresaGeracaoContext struct {
	EmpresaID     string
	TenantID      string
	MunicipioID   string
	EstadoID      string
	Bairro        string
	TipoEmpresaID string
}

type compromissoTemplateRow struct {
	ID                string
	Descricao         string
	Periodicidade     string
	Valor             sql.NullFloat64
	Observacao        sql.NullString
	TipoClassificacao string
}

type EmpresaCompromissoRepository struct {
	pool *pgxpool.Pool
}

func NewEmpresaCompromissoRepository(pool *pgxpool.Pool) *EmpresaCompromissoRepository {
	return &EmpresaCompromissoRepository{pool: pool}
}

// GerarCompromissosEmpresa executa a function SQL idempotente por empresa/competência.
func (r *EmpresaCompromissoRepository) GerarCompromissosEmpresa(ctx context.Context, tenantID string, dataRef time.Time, empresaID string) (int, error) {
	eid := strings.TrimSpace(empresaID)
	tid := strings.TrimSpace(tenantID)
	if eid == "" {
		return 0, fmt.Errorf("empresa nao informada")
	}
	if tid == "" {
		return 0, fmt.Errorf("tenant nao informado")
	}

	// Evita dependência de function SQL legada (com colunas antigas) e usa fluxo Go compatível com UUID.
	items, err := r.GerarCompromissos(ctx, eid, tid, dataRef, map[string]bool{})
	if err != nil {
		msg := strings.ToLower(err.Error())
		if strings.Contains(msg, "compromiss") && strings.Contains(msg, "gerad") && strings.Contains(msg, "empresa") {
			return 0, nil
		}
		return 0, fmt.Errorf("executar gerar_compromissos_empresa: %w", err)
	}
	return len(items), nil
}

func (r *EmpresaCompromissoRepository) GerarCompromissosGeral(ctx context.Context, dataRef time.Time) (int, error) {
	var total int
	err := r.pool.QueryRow(
		ctx,
		`SELECT public.gerar_compromissos_geral($1::date)`,
		dataRef.Format("2006-01-02"),
	).Scan(&total)
	if err != nil {
		return 0, fmt.Errorf("executar gerar_compromissos_geral: %w", err)
	}
	return total, nil
}

func (r *EmpresaCompromissoRepository) loadGeracaoContext(ctx context.Context, empresaID, tenantID string) (empresaGeracaoContext, error) {
	var out empresaGeracaoContext
	err := r.pool.QueryRow(ctx, `
		SELECT e.id, e.tenant_id, COALESCE(c.municipio_id, ed.municipio_id), m.ufid, COALESCE(NULLIF(TRIM(c.bairro), ''), ''),
		       COALESCE(NULLIF(TRIM(c.tipo_empresa_id::text), ''), '')
		FROM public.empresa e
		INNER JOIN public.cliente c ON c.id = e.cliente_id
		LEFT JOIN public.clientes_dados ed ON ed.cliente_id = c.id
		INNER JOIN public.municipio m ON m.id = COALESCE(c.municipio_id, ed.municipio_id)
		WHERE e.id = $1 AND e.tenant_id = $2 AND e.ativo = true`,
		empresaID, tenantID,
	).Scan(&out.EmpresaID, &out.TenantID, &out.MunicipioID, &out.EstadoID, &out.Bairro, &out.TipoEmpresaID)
	if err != nil {
		return empresaGeracaoContext{}, fmt.Errorf("empresa nao encontrada neste tenant: %w", err)
	}
	if out.TipoEmpresaID == "" {
		return empresaGeracaoContext{}, fmt.Errorf("cadastre o enquadramento juridico desta empresa antes de gerar compromissos")
	}
	return out, nil
}

func (r *EmpresaCompromissoRepository) countByEmpresaTx(ctx context.Context, tx pgx.Tx, empresaID string) (int64, error) {
	var n int64
	err := tx.QueryRow(ctx, `SELECT count(*) FROM public.empresa_compromissos WHERE empresa_id = $1`, empresaID).Scan(&n)
	return n, err
}

func (r *EmpresaCompromissoRepository) listTemplatesForEmpresaTx(ctx context.Context, tx pgx.Tx, tipoEmpresaID, municipioID, bairro string) ([]compromissoTemplateRow, error) {
	const q = `
		SELECT c.id, c.descricao, c.periodicidade, c.valor, c.observacao, COALESCE(c.tipo_classificacao, '')
		FROM public.tipoempresa_obrigacao c
		WHERE c.ativo = true AND c.tipo_empresa_id = $1
		  AND (
			c.abrangencia = 'FEDERAL'
			OR (
				c.abrangencia = 'ESTADUAL' AND EXISTS (
					SELECT 1 FROM public.tipoempresa_obriga_estado ce
					INNER JOIN public.municipio m ON m.ufid = ce.estado_id
					WHERE ce.obrigacao_id = c.id AND m.id = $2
				)
			)
			OR (
				c.abrangencia = 'MUNICIPAL' AND EXISTS (
					SELECT 1 FROM public.tipoempresa_obriga_municipio cm
					WHERE cm.obrigacao_id = c.id AND cm.municipio_id = $2
				)
			)
			OR (
				c.abrangencia = 'BAIRRO' AND EXISTS (
					SELECT 1 FROM public.tipoempresa_obriga_bairro cb
					WHERE cb.tipoempresa_obrigacao_id = c.id AND cb.municipio_id = $2
					  AND (
						cb.bairro IS NULL OR TRIM(cb.bairro) = ''
						OR LOWER(TRIM(cb.bairro)) = LOWER(TRIM(COALESCE($3::text, '')))
					  )
				)
			)
		  )
		ORDER BY c.descricao ASC`

	rows, err := tx.Query(ctx, q, tipoEmpresaID, municipioID, bairroArg(bairro))
	if err != nil {
		return nil, fmt.Errorf("listar compromissos aplicaveis: %w", err)
	}
	defer rows.Close()

	out := make([]compromissoTemplateRow, 0)
	for rows.Next() {
		var row compromissoTemplateRow
		if err := rows.Scan(&row.ID, &row.Descricao, &row.Periodicidade, &row.Valor, &row.Observacao, &row.TipoClassificacao); err != nil {
			return nil, fmt.Errorf("scan compromisso template: %w", err)
		}
		out = append(out, row)
	}
	return out, rows.Err()
}

func bairroArg(s string) any {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return strings.TrimSpace(s)
}

// GerarCompromissos cria linhas em empresa_compromissos (idempotente: falha se já existir).
func (r *EmpresaCompromissoRepository) GerarCompromissos(ctx context.Context, empresaID, tenantID string, dataInicio time.Time, feriados map[string]bool) ([]domain.EmpresaCompromissoItem, error) {
	ctxEmp, err := r.loadGeracaoContext(ctx, empresaID, tenantID)
	if err != nil {
		return nil, err
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	n, err := r.countByEmpresaTx(ctx, tx, empresaID)
	if err != nil {
		return nil, err
	}
	if n > 0 {
		return nil, fmt.Errorf("compromissos ja gerados para esta empresa")
	}

	templates, err := r.listTemplatesForEmpresaTx(ctx, tx, ctxEmp.TipoEmpresaID, ctxEmp.MunicipioID, ctxEmp.Bairro)
	if err != nil {
		return nil, err
	}

	const ins = `
		INSERT INTO public.empresa_compromissos (descricao, valor, vencimento, observacao, status, empresa_id, tipoempresa_obrigacao_id)
		VALUES ($1, $2, $3::timestamptz, $4, 'pendente', $5, $6::uuid)
		RETURNING id, descricao, valor, vencimento::text, COALESCE(observacao, ''), status, empresa_id, tipoempresa_obrigacao_id::text`

	items := make([]domain.EmpresaCompromissoItem, 0)

	for _, t := range templates {
		per := strings.ToUpper(strings.TrimSpace(t.Periodicidade))
		tc := strings.ToUpper(strings.TrimSpace(t.TipoClassificacao))
		var valorIns *float64
		if (tc == "TRIBUTARIA" || tc == "TRIBUTO") && t.Valor.Valid {
			v := t.Valor.Float64
			valorIns = &v
		}

		obs := ""
		if t.Observacao.Valid {
			obs = t.Observacao.String
		}

		switch per {
		case "MENSAL":
			for i := 0; i < 12; i++ {
				dt := addMonthsSameDay(dataInicio, i)
				dt = ajustarVencimento(dt, feriados)
				var row domain.EmpresaCompromissoItem
				err := tx.QueryRow(ctx, ins, t.Descricao, valorIns, dt.Format(time.RFC3339), obs, empresaID, t.ID).Scan(
					&row.ID, &row.Descricao, &row.Valor, &row.Vencimento, &row.Observacao, &row.Status, &row.EmpresaID, &row.TipoempresaObrigacaoID,
				)
				if err != nil {
					return nil, fmt.Errorf("insert compromisso mensal: %w", err)
				}
				items = append(items, row)
			}
		case "ANUAL":
			dt := dataInicio.AddDate(1, 0, 0)
			dt = ajustarVencimento(dt, feriados)
			var row domain.EmpresaCompromissoItem
			err := tx.QueryRow(ctx, ins, t.Descricao, valorIns, dt.Format(time.RFC3339), obs, empresaID, t.ID).Scan(
				&row.ID, &row.Descricao, &row.Valor, &row.Vencimento, &row.Observacao, &row.Status, &row.EmpresaID, &row.TipoempresaObrigacaoID,
			)
			if err != nil {
				return nil, fmt.Errorf("insert compromisso anual: %w", err)
			}
			items = append(items, row)
		default:
			return nil, fmt.Errorf("periodicidade nao suportada: %s", t.Periodicidade)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("commit tx: %w", err)
	}

	return items, nil
}

func addMonthsSameDay(t time.Time, months int) time.Time {
	year, month, day := t.Date()
	loc := t.Location()
	first := time.Date(year, month+time.Month(months), 1, 0, 0, 0, 0, loc)
	lastDay := time.Date(first.Year(), first.Month()+1, 0, 0, 0, 0, 0, loc).Day()
	d := day
	if d > lastDay {
		d = lastDay
	}
	return time.Date(first.Year(), first.Month(), d, 0, 0, 0, 0, loc)
}

func (r *EmpresaCompromissoRepository) ListAcompanhamentoByTenant(ctx context.Context, tenantID string) ([]domain.EmpresaCompromissoAcompanhamentoItem, error) {
	const q = `
		SELECT
			e.id,
			c.nome,
			ec.id::text,
			ec.descricao,
			ec.vencimento::date::text,
			ec.status,
			'',
			CASE
				WHEN UPPER(TRIM(COALESCE(cf.tipo_classificacao, ''))) IN ('TRIBUTARIA','TRIBUTO') THEN 'FINANCEIRO'
				ELSE 'NAO_FINANCEIRO'
			END,
			ec.id::text,
			ec.valor
		FROM public.empresa_compromissos ec
		INNER JOIN public.empresa e ON e.id = ec.empresa_id
		INNER JOIN public.cliente c ON c.id = e.cliente_id
		INNER JOIN public.tipoempresa_obrigacao cf ON cf.id = ec.tipoempresa_obrigacao_id
		WHERE e.ativo = true AND e.tenant_id = $1
		ORDER BY c.nome ASC, ec.vencimento ASC, ec.descricao ASC`

	rows, err := r.pool.Query(ctx, q, tenantID)
	if err != nil {
		return nil, fmt.Errorf("list acompanhamento empresa compromissos: %w", err)
	}
	defer rows.Close()

	out := make([]domain.EmpresaCompromissoAcompanhamentoItem, 0)
	for rows.Next() {
		var it domain.EmpresaCompromissoAcompanhamentoItem
		var nf sql.NullFloat64
		if err := rows.Scan(&it.EmpresaID, &it.EmpresaNome, &it.CompromissoID, &it.Descricao, &it.DataVencimento, &it.Status, &it.Tipo, &it.Classificacao, &it.AgendaItemID, &nf); err != nil {
			return nil, fmt.Errorf("scan: %w", err)
		}
		if nf.Valid {
			v := nf.Float64
			it.ValorEstimado = &v
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

func (r *EmpresaCompromissoRepository) ListEmpresaOptionsByTenant(ctx context.Context, tenantID string) ([]domain.EmpresaCompromissoEmpresaOption, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT e.id, c.nome
		FROM public.empresa e
		INNER JOIN public.cliente c ON c.id = e.cliente_id
		WHERE e.ativo = true AND e.tenant_id = $1
		ORDER BY c.nome ASC`, strings.TrimSpace(tenantID))
	if err != nil {
		return nil, fmt.Errorf("listar empresas para compromissos: %w", err)
	}
	defer rows.Close()

	out := make([]domain.EmpresaCompromissoEmpresaOption, 0)
	for rows.Next() {
		var it domain.EmpresaCompromissoEmpresaOption
		if err := rows.Scan(&it.ID, &it.Nome); err != nil {
			return nil, fmt.Errorf("scan empresa option: %w", err)
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

func (r *EmpresaCompromissoRepository) ListObrigacaoOptionsByEmpresa(ctx context.Context, tenantID, empresaID string) ([]domain.EmpresaCompromissoObrigacaoOption, error) {
	ctxEmp, err := r.loadGeracaoContext(ctx, strings.TrimSpace(empresaID), strings.TrimSpace(tenantID))
	if err != nil {
		return nil, err
	}

	rows, err := r.pool.Query(ctx, `
		SELECT c.id::text, c.descricao, COALESCE(c.periodicidade, 'MENSAL')
		FROM public.tipoempresa_obrigacao c
		WHERE c.ativo = true
		  AND c.tipo_empresa_id = $1
		  AND (
			c.abrangencia = 'FEDERAL'
			OR (
				c.abrangencia = 'ESTADUAL' AND EXISTS (
					SELECT 1 FROM public.tipoempresa_obriga_estado ce
					INNER JOIN public.municipio m ON m.ufid = ce.estado_id
					WHERE ce.obrigacao_id = c.id AND m.id = $2
				)
			)
			OR (
				c.abrangencia = 'MUNICIPAL' AND EXISTS (
					SELECT 1 FROM public.tipoempresa_obriga_municipio cm
					WHERE cm.obrigacao_id = c.id AND cm.municipio_id = $2
				)
			)
			OR (
				c.abrangencia = 'BAIRRO' AND EXISTS (
					SELECT 1 FROM public.tipoempresa_obriga_bairro cb
					WHERE cb.tipoempresa_obrigacao_id = c.id AND cb.municipio_id = $2
					  AND (
						cb.bairro IS NULL OR TRIM(cb.bairro) = ''
						OR LOWER(TRIM(cb.bairro)) = LOWER(TRIM(COALESCE($3::text, '')))
					  )
				)
			)
		  )
		ORDER BY c.descricao ASC`,
		ctxEmp.TipoEmpresaID, ctxEmp.MunicipioID, bairroArg(ctxEmp.Bairro),
	)
	if err != nil {
		return nil, fmt.Errorf("listar obrigacoes para empresa: %w", err)
	}
	defer rows.Close()

	out := make([]domain.EmpresaCompromissoObrigacaoOption, 0)
	for rows.Next() {
		var it domain.EmpresaCompromissoObrigacaoOption
		if err := rows.Scan(&it.ID, &it.Descricao, &it.Periodicidade); err != nil {
			return nil, fmt.Errorf("scan obrigacao option: %w", err)
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

func (r *EmpresaCompromissoRepository) CreateManualForTenant(ctx context.Context, tenantID string, in EmpresaCompromissoCreateManualInput) (string, error) {
	var id string
	err := r.pool.QueryRow(ctx, `
		INSERT INTO public.empresa_compromissos (
			descricao, valor, vencimento, observacao, status, empresa_id, tipoempresa_obrigacao_id, competencia
		)
		SELECT
			$1, $2, $3::timestamptz, $4, $5, $6, $7::uuid, date_trunc('month', $3::date)::date
		WHERE EXISTS (
			SELECT 1
			FROM public.empresa e
			WHERE e.id = $6 AND e.tenant_id = $8 AND e.ativo = true
		)
		RETURNING id::text`,
		in.Descricao,
		in.Valor,
		in.Vencimento.Format(time.RFC3339),
		strings.TrimSpace(in.Observacao),
		in.Status,
		in.EmpresaID,
		in.TipoempresaObrigacaoID,
		strings.TrimSpace(tenantID),
	).Scan(&id)
	if err != nil {
		return "", fmt.Errorf("incluir compromisso manual: %w", err)
	}
	return id, nil
}

func (r *EmpresaCompromissoRepository) UpdateStatusForTenant(ctx context.Context, tenantID, id, status string) error {
	status = strings.ToLower(strings.TrimSpace(status))
	if status != "pendente" && status != "concluido" {
		return fmt.Errorf("status invalido (pendente|concluido)")
	}
	ct, err := r.pool.Exec(ctx, `
		UPDATE public.empresa_compromissos ec
		SET status = $1, atualizado_em = NOW()
		FROM public.empresa e
		WHERE ec.id = $2::uuid AND ec.empresa_id = e.id AND e.tenant_id = $3`,
		status, id, tenantID)
	if err != nil {
		return fmt.Errorf("update status: %w", err)
	}
	if ct.RowsAffected() == 0 {
		return fmt.Errorf("item nao encontrado neste tenant")
	}
	return nil
}

func (r *EmpresaCompromissoRepository) UpdateItem(ctx context.Context, tenantID, itemID string, dataVencimento *string, valor *float64) error {
	itemID = strings.TrimSpace(itemID)
	if itemID == "" {
		return fmt.Errorf("id obrigatorio")
	}
	hasDate := dataVencimento != nil && strings.TrimSpace(*dataVencimento) != ""
	if !hasDate && valor == nil {
		return fmt.Errorf("informe data_vencimento e/ou valor")
	}

	var rowsAff int64
	var err error
	switch {
	case hasDate && valor != nil:
		ct, e := r.pool.Exec(ctx, `
			UPDATE public.empresa_compromissos ec
			SET vencimento = $1::date, valor = $2, atualizado_em = NOW()
			FROM public.empresa e
			WHERE ec.id = $3::uuid AND ec.empresa_id = e.id AND e.tenant_id = $4`,
			strings.TrimSpace(*dataVencimento), *valor, itemID, tenantID)
		err = e
		if err == nil {
			rowsAff = ct.RowsAffected()
		}
	case hasDate:
		ct, e := r.pool.Exec(ctx, `
			UPDATE public.empresa_compromissos ec
			SET vencimento = $1::date, atualizado_em = NOW()
			FROM public.empresa e
			WHERE ec.id = $2::uuid AND ec.empresa_id = e.id AND e.tenant_id = $3`,
			strings.TrimSpace(*dataVencimento), itemID, tenantID)
		err = e
		if err == nil {
			rowsAff = ct.RowsAffected()
		}
	default:
		ct, e := r.pool.Exec(ctx, `
			UPDATE public.empresa_compromissos ec
			SET valor = $1, atualizado_em = NOW()
			FROM public.empresa e
			WHERE ec.id = $2::uuid AND ec.empresa_id = e.id AND e.tenant_id = $3`,
			*valor, itemID, tenantID)
		err = e
		if err == nil {
			rowsAff = ct.RowsAffected()
		}
	}
	if err != nil {
		return fmt.Errorf("update empresa compromisso: %w", err)
	}
	if rowsAff == 0 {
		return fmt.Errorf("item nao encontrado neste tenant")
	}
	return nil
}
