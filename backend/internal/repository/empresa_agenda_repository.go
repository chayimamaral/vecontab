package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
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
	EmpresaID      string `json:"empresa_id"`
	EmpresaNome    string `json:"empresa_nome"`
	CompromissoID  string `json:"compromisso_id"`
	Descricao      string `json:"descricao"`
	DataVencimento string `json:"data_vencimento"`
	Status         string `json:"status"`
	Tipo           string `json:"tipo"`
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

// ── Atualizar status de um item ──────────────────────────────────────────────

func (r *EmpresaAgendaRepository) UpdateStatus(ctx context.Context, id, status string) error {
	const query = `UPDATE public.empresa_agenda SET status = $1, atualizado_em = NOW() WHERE id = $2`
	_, err := r.pool.Exec(ctx, query, status, id)
	if err != nil {
		return fmt.Errorf("update status empresa_agenda: %w", err)
	}
	return nil
}

func (r *EmpresaAgendaRepository) ListAcompanhamentoByTenant(ctx context.Context, tenantID string) ([]EmpresaAgendaAcompanhamentoItem, error) {
	const query = `
		SELECT
			e.id,
			e.nome,
			COALESCE(ea.id::text, ''),
			COALESCE(ea.descricao, ''),
			COALESCE(ea.data_vencimento::text, ''),
			COALESCE(ea.status, ''),
			COALESCE(teo.tipo, '')
		FROM public.empresa e
		LEFT JOIN public.empresa_agenda ea ON ea.empresa_id = e.id
		LEFT JOIN public.tipoempresa_obrigacao teo ON teo.id = ea.template_id
		WHERE e.ativo = true
		  AND e.tenant_id = $1
		ORDER BY e.nome ASC, ea.data_vencimento ASC NULLS LAST, ea.descricao ASC`

	rows, err := r.pool.Query(ctx, query, tenantID)
	if err != nil {
		return nil, fmt.Errorf("list acompanhamento empresa_agenda: %w", err)
	}
	defer rows.Close()

	items := make([]EmpresaAgendaAcompanhamentoItem, 0)
	for rows.Next() {
		var item EmpresaAgendaAcompanhamentoItem
		if err := rows.Scan(
			&item.EmpresaID,
			&item.EmpresaNome,
			&item.CompromissoID,
			&item.Descricao,
			&item.DataVencimento,
			&item.Status,
			&item.Tipo,
		); err != nil {
			return nil, fmt.Errorf("scan acompanhamento empresa_agenda: %w", err)
		}

		items = append(items, item)
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

	if len(templates) == 0 {
		return nil, nil
	}

	// 2) Transação atômica
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

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
