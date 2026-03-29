package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ── Types ────────────────────────────────────────────────────────────────────

type EmpresaAgendaItem struct {
	ID             string   `json:"id"`
	EmpresaID      string   `json:"empresa_id"`
	TemplateID     string   `json:"template_id"`
	Descricao      string   `json:"descricao"`
	DataVencimento string   `json:"data_vencimento"`
	Status         string   `json:"status"`
	ValorEstimado  *float64 `json:"valor_estimado"`
}

type EmpresaAgendaAcompanhamentoItem struct {
	EmpresaID       string   `json:"empresa_id"`
	EmpresaNome     string   `json:"empresa_nome"`
	CompromissoID   string   `json:"compromisso_id"`
	Descricao       string   `json:"descricao"`
	DataVencimento  string   `json:"data_vencimento"`
	Status          string   `json:"status"`
	Tipo            string   `json:"tipo"`            // TRIBUTO | INFORMATIVA (template)
	Classificacao   string   `json:"classificacao"`   // FINANCEIRO | NAO_FINANCEIRO | vazio se sem instância
	AgendaItemID    string   `json:"agenda_item_id"`  // UUID em empresa_agenda; vazio = só catálogo (não editável)
	ValorEstimado   *float64 `json:"valor_estimado"`  // nil se sem valor
}

type EmpresaAgendaRepository struct {
	pool *pgxpool.Pool
}

func NewEmpresaAgendaRepository(pool *pgxpool.Pool) *EmpresaAgendaRepository {
	return &EmpresaAgendaRepository{pool: pool}
}

// ── Listar agenda de uma empresa ─────────────────────────────────────────────

func (r *EmpresaAgendaRepository) ListByEmpresa(ctx context.Context, empresaID string) ([]EmpresaAgendaItem, error) {
	const query = `
		SELECT id, empresa_id, template_id, descricao, data_vencimento::text, status, valor_estimado
		FROM public.empresa_agenda
		WHERE empresa_id = $1
		ORDER BY data_vencimento ASC`

	rows, err := r.pool.Query(ctx, query, empresaID)
	if err != nil {
		return nil, fmt.Errorf("list empresa_agenda: %w", err)
	}
	defer rows.Close()

	items := make([]EmpresaAgendaItem, 0)
	for rows.Next() {
		var a EmpresaAgendaItem
		if err := rows.Scan(&a.ID, &a.EmpresaID, &a.TemplateID, &a.Descricao, &a.DataVencimento, &a.Status, &a.ValorEstimado); err != nil {
			return nil, fmt.Errorf("scan empresa_agenda: %w", err)
		}
		items = append(items, a)
	}

	return items, nil
}

// ── Atualizar status de um item (escopo tenant) ─────────────────────────────

func (r *EmpresaAgendaRepository) UpdateStatusForTenant(ctx context.Context, tenantID, id, status string) error {
	ct, err := r.pool.Exec(ctx, `
		UPDATE public.empresa_agenda ea
		SET status = $1, atualizado_em = NOW()
		FROM public.empresa e
		WHERE ea.id = $2::uuid AND ea.empresa_id = e.id AND e.tenant_id = $3`,
		status, id, tenantID)
	if err != nil {
		return fmt.Errorf("update status empresa_agenda: %w", err)
	}
	if ct.RowsAffected() == 0 {
		return fmt.Errorf("item nao encontrado neste tenant")
	}
	return nil
}

// UpdateItem atualiza vencimento e/ou valor de uma linha de empresa_agenda do tenant.
func (r *EmpresaAgendaRepository) UpdateItem(ctx context.Context, tenantID, agendaItemID string, dataVencimento *string, valorEstimado *float64) error {
	agendaItemID = strings.TrimSpace(agendaItemID)
	if agendaItemID == "" {
		return fmt.Errorf("id obrigatorio")
	}
	hasDate := dataVencimento != nil && strings.TrimSpace(*dataVencimento) != ""
	if !hasDate && valorEstimado == nil {
		return fmt.Errorf("informe data_vencimento e/ou valor_estimado")
	}

	var rowsAff int64
	var err error
	switch {
	case hasDate && valorEstimado != nil:
		ct, e := r.pool.Exec(ctx, `
			UPDATE public.empresa_agenda ea
			SET data_vencimento = $1::date, valor_estimado = $2, atualizado_em = NOW()
			FROM public.empresa e
			WHERE ea.id = $3::uuid AND ea.empresa_id = e.id AND e.tenant_id = $4`,
			strings.TrimSpace(*dataVencimento), *valorEstimado, agendaItemID, tenantID)
		err = e
		if err == nil {
			rowsAff = ct.RowsAffected()
		}
	case hasDate:
		ct, e := r.pool.Exec(ctx, `
			UPDATE public.empresa_agenda ea
			SET data_vencimento = $1::date, atualizado_em = NOW()
			FROM public.empresa e
			WHERE ea.id = $2::uuid AND ea.empresa_id = e.id AND e.tenant_id = $3`,
			strings.TrimSpace(*dataVencimento), agendaItemID, tenantID)
		err = e
		if err == nil {
			rowsAff = ct.RowsAffected()
		}
	default:
		ct, e := r.pool.Exec(ctx, `
			UPDATE public.empresa_agenda ea
			SET valor_estimado = $1, atualizado_em = NOW()
			FROM public.empresa e
			WHERE ea.id = $2::uuid AND ea.empresa_id = e.id AND e.tenant_id = $3`,
			*valorEstimado, agendaItemID, tenantID)
		err = e
		if err == nil {
			rowsAff = ct.RowsAffected()
		}
	}
	if err != nil {
		return fmt.Errorf("update empresa_agenda: %w", err)
	}
	if rowsAff == 0 {
		return fmt.Errorf("item nao encontrado neste tenant")
	}
	return nil
}

func (r *EmpresaAgendaRepository) ListAcompanhamentoByTenant(ctx context.Context, tenantID string) ([]EmpresaAgendaAcompanhamentoItem, error) {
	const queryAgenda = `
		SELECT
			e.id,
			e.nome,
			COALESCE(ea.id::text, ''),
			COALESCE(ea.descricao, ''),
			COALESCE(ea.data_vencimento::text, ''),
			COALESCE(ea.status, ''),
			COALESCE(teo.tipo, ''),
			CASE
				WHEN ea.id IS NULL THEN ''
				WHEN UPPER(COALESCE(teo.tipo, '')) = 'TRIBUTO' THEN 'FINANCEIRO'
				ELSE 'NAO_FINANCEIRO'
			END,
			CASE WHEN ea.id IS NOT NULL THEN ea.id::text ELSE '' END,
			ea.valor_estimado
		FROM public.empresa e
		LEFT JOIN public.empresa_agenda ea ON ea.empresa_id = e.id
		LEFT JOIN public.tipoempresa_obrigacao teo ON teo.id = ea.template_id
		WHERE e.ativo = true
		  AND e.tenant_id = $1
		ORDER BY e.nome ASC, ea.data_vencimento ASC NULLS LAST, ea.descricao ASC`

	items, err := scanAcompanhamentoRows(ctx, r.pool, queryAgenda, tenantID)
	if err != nil {
		return nil, err
	}

	// Cadastro legal (compromisso_financeiro) pelo tipo de empresa da rotina vinculada à empresa.
	const queryCatalog = `
		SELECT
			e.id,
			e.nome,
			c.id::text,
			c.descricao,
			'',
			'PENDENTE',
			'',
			CASE
				WHEN UPPER(COALESCE(c.natureza, '')) = 'FINANCEIRO' THEN 'FINANCEIRO'
				ELSE 'NAO_FINANCEIRO'
			END,
			'',
			NULL::numeric
		FROM public.empresa e
		INNER JOIN public.rotinas r ON r.id = e.rotina_id
		INNER JOIN public.compromisso_financeiro c
			ON c.tipo_empresa_id = r.tipo_empresa_id AND c.ativo = true
		WHERE e.ativo = true
		  AND e.tenant_id = $1
		  AND r.ativo = true
		  AND r.tipo_empresa_id IS NOT NULL
		  AND trim(r.tipo_empresa_id) <> ''
		  AND NOT EXISTS (
		  	SELECT 1 FROM public.empresa_agenda ea
		  	WHERE ea.empresa_id = e.id AND ea.descricao = c.descricao
		  )
		ORDER BY e.nome ASC, c.descricao ASC`

	catalog, err := scanAcompanhamentoRows(ctx, r.pool, queryCatalog, tenantID)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "42703" {
			// Colunas de migração (ex.: rotinas.tipo_empresa_id, compromisso_financeiro.natureza) ainda ausentes: retorna só agenda gerada.
			return items, nil
		}
		return nil, fmt.Errorf("list acompanhamento catalogo compromissos: %w", err)
	}

	return append(items, catalog...), nil
}

func scanAcompanhamentoRows(ctx context.Context, pool *pgxpool.Pool, query string, tenantID string) ([]EmpresaAgendaAcompanhamentoItem, error) {
	rows, err := pool.Query(ctx, query, tenantID)
	if err != nil {
		return nil, fmt.Errorf("list acompanhamento: %w", err)
	}
	defer rows.Close()

	items := make([]EmpresaAgendaAcompanhamentoItem, 0)
	for rows.Next() {
		var item EmpresaAgendaAcompanhamentoItem
		var nf sql.NullFloat64
		if err := rows.Scan(
			&item.EmpresaID,
			&item.EmpresaNome,
			&item.CompromissoID,
			&item.Descricao,
			&item.DataVencimento,
			&item.Status,
			&item.Tipo,
			&item.Classificacao,
			&item.AgendaItemID,
			&nf,
		); err != nil {
			return nil, fmt.Errorf("scan acompanhamento: %w", err)
		}
		if nf.Valid {
			v := nf.Float64
			item.ValorEstimado = &v
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list acompanhamento: %w", err)
	}
	return items, nil
}

// ── Gerar agenda (transação atômica) ─────────────────────────────────────────
// Busca os templates de obrigação do tipo_empresa, gera 12 meses (mensal)
// ou 1 instância (anual) para a empresa, ajustando feriados e fins de semana.

func (r *EmpresaAgendaRepository) GerarAgenda(ctx context.Context, empresaID, tipoEmpresaID string, dataInicio time.Time, feriados map[string]bool) ([]EmpresaAgendaItem, error) {
	// 1) Buscar templates de obrigação
	const tmplQuery = `
		SELECT id, descricao, dia_base, mes_base, frequencia
		FROM public.tipoempresa_obrigacao
		WHERE tipo_empresa_id = $1 AND ativo = true`

	tmplRows, err := r.pool.Query(ctx, tmplQuery, tipoEmpresaID)
	if err != nil {
		return nil, fmt.Errorf("buscar templates: %w", err)
	}

	type template struct {
		ID         string
		Descricao  string
		DiaBase    int
		MesBase    *int
		Frequencia string
	}

	templates := make([]template, 0)
	for tmplRows.Next() {
		var t template
		if err := tmplRows.Scan(&t.ID, &t.Descricao, &t.DiaBase, &t.MesBase, &t.Frequencia); err != nil {
			tmplRows.Close()
			return nil, fmt.Errorf("scan template: %w", err)
		}
		templates = append(templates, t)
	}
	tmplRows.Close()

	// 2) Transação: persiste tipo na empresa e regenera instâncias da agenda
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	if _, err = tx.Exec(ctx,
		`UPDATE public.empresa SET tipo_empresa_id = $1 WHERE id = $2`,
		tipoEmpresaID, empresaID,
	); err != nil {
		return nil, fmt.Errorf("atualizar tipo_empresa da empresa: %w", err)
	}

	if len(templates) == 0 {
		if err := tx.Commit(ctx); err != nil {
			return nil, fmt.Errorf("commit tx: %w", err)
		}
		return nil, nil
	}

	// Limpar agenda anterior desta empresa (para permitir re-geração)
	_, err = tx.Exec(ctx, `DELETE FROM public.empresa_agenda WHERE empresa_id = $1`, empresaID)
	if err != nil {
		return nil, fmt.Errorf("limpar agenda anterior: %w", err)
	}

	const insertQuery = `
		INSERT INTO public.empresa_agenda (empresa_id, template_id, descricao, data_vencimento, status)
		VALUES ($1, $2, $3, $4, 'PENDENTE')
		RETURNING id, empresa_id, template_id, descricao, data_vencimento::text, status, valor_estimado`

	batch := &pgx.Batch{}
	for _, t := range templates {
		if t.Frequencia == "MENSAL" {
			// Gerar 12 meses a partir da dataInicio
			for i := 0; i < 12; i++ {
				dt := time.Date(dataInicio.Year(), dataInicio.Month()+time.Month(i), t.DiaBase, 0, 0, 0, 0, time.Local)
				dt = ajustarVencimento(dt, feriados)
				batch.Queue(insertQuery, empresaID, t.ID, t.Descricao, dt)
			}
		} else {
			// ANUAL – gerar para o mês base
			mesAlvo := time.Month(1)
			if t.MesBase != nil {
				mesAlvo = time.Month(*t.MesBase)
			}
			ano := dataInicio.Year()
			// Se o mês alvo já passou neste ano, usa o próximo ano
			if mesAlvo < dataInicio.Month() || (mesAlvo == dataInicio.Month() && t.DiaBase < dataInicio.Day()) {
				ano++
			}
			dt := time.Date(ano, mesAlvo, t.DiaBase, 0, 0, 0, 0, time.Local)
			dt = ajustarVencimento(dt, feriados)
			batch.Queue(insertQuery, empresaID, t.ID, t.Descricao, dt)
		}
	}

	br := tx.SendBatch(ctx, batch)
	items := make([]EmpresaAgendaItem, 0, batch.Len())
	for i := 0; i < batch.Len(); i++ {
		var a EmpresaAgendaItem
		if err := br.QueryRow().Scan(&a.ID, &a.EmpresaID, &a.TemplateID, &a.Descricao, &a.DataVencimento, &a.Status, &a.ValorEstimado); err != nil {
			br.Close()
			return nil, fmt.Errorf("scan batch item %d: %w", i, err)
		}
		items = append(items, a)
	}
	br.Close()

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("commit tx: %w", err)
	}

	return items, nil
}

// ── AjustarVencimento ────────────────────────────────────────────────────────
// Se a data cai em sábado, domingo ou feriado, posterga para o próximo dia útil.

func ajustarVencimento(data time.Time, feriados map[string]bool) time.Time {
	for {
		wd := data.Weekday()
		chave := data.Format("2006-01-02")

		if wd == time.Saturday {
			data = data.AddDate(0, 0, 2) // Sáb → Seg
			continue
		}
		if wd == time.Sunday {
			data = data.AddDate(0, 0, 1) // Dom → Seg
			continue
		}
		if feriados[chave] {
			data = data.AddDate(0, 0, 1)
			continue
		}

		return data
	}
}
