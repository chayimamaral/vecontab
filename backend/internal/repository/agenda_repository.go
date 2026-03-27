package repository

import (
	"context"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

type AgendaRepository struct {
	pool *pgxpool.Pool
}

type AgendaEvent struct {
	ID              string `json:"id"`
	Title           string `json:"title"`
	RotinaID        string `json:"rotina_id,omitempty"`
	PassoID         string `json:"passo_id,omitempty"`
	AgendaID        string `json:"agenda_id,omitempty"`
	Start           string `json:"start"`
	End             string `json:"end"`
	BackgroundColor string `json:"backgroundColor"`
	TextColor       string `json:"textColor"`
	BorderColor     string `json:"borderColor"`
}

type ConcluirPassoResult struct {
	AgendaID              string `json:"agenda_id"`
	AgendaItemID          string `json:"agenda_item_id"`
	TodosPassosConcluidos bool   `json:"todos_passos_concluidos"`
}

func NewAgendaRepository(pool *pgxpool.Pool) *AgendaRepository {
	return &AgendaRepository{pool: pool}
}

func (r *AgendaRepository) ListEvents(ctx context.Context, tenantID string) ([]AgendaEvent, error) {
	const query = `
		SELECT
			a.id,
			COALESCE(e.nome, ''),
			COALESCE(r.descricao, ''),
			COALESCE(e.rotina_id, ''),
			a.inicio::text,
			COALESCE(a.termino::text, a.inicio::text),
			CASE
				WHEN lower(COALESCE(a.status, '')) IN ('concluido', 'concluida', 'finalizado', 'finalizada', 'passos_concluidos') THEN '#22C55E'
				WHEN CURRENT_DATE > COALESCE(a.termino, a.inicio) THEN '#FDE2E0'
				WHEN CURRENT_DATE BETWEEN a.inicio AND a.termino THEN '#FFDAB9'
				WHEN CURRENT_DATE < COALESCE(a.termino, a.inicio) THEN '#A0D6B4'
				ELSE ''
			END AS background_color,
			CASE
				WHEN lower(COALESCE(a.status, '')) IN ('concluido', 'concluida', 'finalizado', 'finalizada', 'passos_concluidos') THEN 'white'
				WHEN CURRENT_DATE > COALESCE(a.termino, a.inicio) THEN 'black'
				WHEN CURRENT_DATE BETWEEN a.inicio AND a.termino THEN 'black'
				WHEN CURRENT_DATE < a.inicio THEN 'black'
				ELSE ''
			END AS text_color,
			CASE
				WHEN lower(COALESCE(a.status, '')) IN ('concluido', 'concluida', 'finalizado', 'finalizada', 'passos_concluidos') THEN '#16A34A'
				WHEN CURRENT_DATE > COALESCE(a.termino, a.inicio) THEN '#F8C9C4'
				WHEN CURRENT_DATE BETWEEN a.inicio AND a.termino THEN '#FFDAB9'
				WHEN CURRENT_DATE < a.inicio THEN '#A0D6B4'
				ELSE ''
			END AS border_color
		FROM public.agenda a
		LEFT JOIN public.empresa e ON e.id = a.empresa_id
		LEFT JOIN public.rotinas r ON r.id = a.rotina_id
		WHERE a.tenant_id = $1`

	rows, err := r.pool.Query(ctx, query, tenantID)
	if err != nil {
		return nil, fmt.Errorf("list agenda events: %w", err)
	}
	defer rows.Close()

	events := make([]AgendaEvent, 0)
	for rows.Next() {
		var id, empresaNome, rotinaDesc, rotinaID, inicio, termino, background, textColor, border string
		if err := rows.Scan(&id, &empresaNome, &rotinaDesc, &rotinaID, &inicio, &termino, &background, &textColor, &border); err != nil {
			return nil, fmt.Errorf("scan agenda event: %w", err)
		}

		events = append(events, AgendaEvent{
			ID:              id,
			Title:           empresaNome + " => " + rotinaDesc,
			RotinaID:        rotinaID,
			Start:           inicio,
			End:             termino,
			BackgroundColor: background,
			TextColor:       textColor,
			BorderColor:     border,
		})
	}

	return events, nil
}

func (r *AgendaRepository) DetailEvents(ctx context.Context, tenantID, agendaID string) ([]AgendaEvent, error) {
	const query = `
		SELECT
			ai.id,
			COALESCE(p.descricao, ''),
			COALESCE(p.id, ''),
			ai.agenda_id,
			ai.inicio::text,
			COALESCE(ai.termino::text, ai.inicio::text),
			CASE
				WHEN COALESCE(ai.concluido, false) = true THEN '#22C55E'
				WHEN CURRENT_DATE > COALESCE(ai.termino, ai.inicio, a.termino, a.inicio) THEN '#FDE2E0'
				WHEN CURRENT_DATE BETWEEN COALESCE(ai.inicio, a.inicio) AND COALESCE(ai.termino, ai.inicio, a.termino, a.inicio) THEN '#FFDAB9'
				WHEN CURRENT_DATE < COALESCE(ai.termino, ai.inicio, a.termino, a.inicio) THEN '#A0D6B4'
				ELSE ''
			END AS background_color,
			CASE
				WHEN COALESCE(ai.concluido, false) = true THEN 'white'
				WHEN CURRENT_DATE > COALESCE(ai.termino, ai.inicio, a.termino, a.inicio) THEN 'black'
				WHEN CURRENT_DATE BETWEEN COALESCE(ai.inicio, a.inicio) AND COALESCE(ai.termino, ai.inicio, a.termino, a.inicio) THEN 'black'
				WHEN CURRENT_DATE < COALESCE(ai.inicio, a.inicio) THEN 'black'
				ELSE ''
			END AS text_color,
			CASE
				WHEN COALESCE(ai.concluido, false) = true THEN '#16A34A'
				WHEN CURRENT_DATE > COALESCE(ai.termino, ai.inicio, a.termino, a.inicio) THEN '#F8C9C4'
				WHEN CURRENT_DATE BETWEEN COALESCE(ai.inicio, a.inicio) AND COALESCE(ai.termino, ai.inicio, a.termino, a.inicio) THEN '#FFDAB9'
				WHEN CURRENT_DATE < COALESCE(ai.inicio, a.inicio) THEN '#A0D6B4'
				ELSE ''
			END AS border_color
		FROM public.agendaitens ai
		LEFT JOIN public.agenda a ON a.id = ai.agenda_id
		LEFT JOIN public.passos p ON p.id = ai.passo_id
		WHERE ai.agenda_id = $1
		  AND a.tenant_id = $2`

	rows, err := r.pool.Query(ctx, query, agendaID, tenantID)
	if err != nil {
		return nil, fmt.Errorf("list agenda detail events: %w", err)
	}
	defer rows.Close()

	events := make([]AgendaEvent, 0)
	for rows.Next() {
		var id, title, passoID, agendaIDRow, inicio, termino, background, textColor, border string
		if err := rows.Scan(&id, &title, &passoID, &agendaIDRow, &inicio, &termino, &background, &textColor, &border); err != nil {
			return nil, fmt.Errorf("scan agenda detail event: %w", err)
		}

		events = append(events, AgendaEvent{
			ID:              id,
			Title:           title,
			PassoID:         passoID,
			AgendaID:        agendaIDRow,
			Start:           inicio,
			End:             termino,
			BackgroundColor: background,
			TextColor:       textColor,
			BorderColor:     border,
		})
	}

	return events, nil
}

func (r *AgendaRepository) ConcluirPasso(ctx context.Context, tenantID, agendaID, agendaItemID string) (ConcluirPassoResult, error) {
	const ownershipQuery = `
		SELECT EXISTS (
			SELECT 1
			FROM public.agendaitens ai
			JOIN public.agenda a ON a.id = ai.agenda_id
			WHERE ai.id = $1
			  AND ai.agenda_id = $2
			  AND a.tenant_id = $3
		)`

	var owned bool
	if err := r.pool.QueryRow(ctx, ownershipQuery, agendaItemID, agendaID, tenantID).Scan(&owned); err != nil {
		return ConcluirPassoResult{}, fmt.Errorf("validar ownership agenda item: %w", err)
	}
	if !owned {
		return ConcluirPassoResult{}, fmt.Errorf("passo da agenda nao encontrado para este tenant")
	}

	hasConcluido, err := r.columnExists(ctx, "agendaitens", "concluido")
	if err != nil {
		return ConcluirPassoResult{}, err
	}
	hasStatus, err := r.columnExists(ctx, "agendaitens", "status")
	if err != nil {
		return ConcluirPassoResult{}, err
	}
	hasConcluidoEm, err := r.columnExists(ctx, "agendaitens", "concluido_em")
	if err != nil {
		return ConcluirPassoResult{}, err
	}
	hasTermino, err := r.columnExists(ctx, "agendaitens", "termino")
	if err != nil {
		return ConcluirPassoResult{}, err
	}

	setParts := make([]string, 0, 4)
	if hasConcluido {
		setParts = append(setParts, "concluido = true")
	}
	if hasStatus {
		setParts = append(setParts, "status = 'concluido'")
	}
	if hasConcluidoEm {
		setParts = append(setParts, "concluido_em = NOW()")
	}
	if len(setParts) == 0 && hasTermino {
		// Fallback para schemas legados sem campos explicitos de conclusao.
		setParts = append(setParts, "termino = COALESCE(termino, NOW())")
	}

	if len(setParts) == 0 {
		return ConcluirPassoResult{}, fmt.Errorf("schema de agendaitens sem coluna de conclusao suportada")
	}

	updateQuery := fmt.Sprintf("UPDATE public.agendaitens SET %s WHERE id = $1 AND agenda_id = $2", strings.Join(setParts, ", "))
	if _, err := r.pool.Exec(ctx, updateQuery, agendaItemID, agendaID); err != nil {
		return ConcluirPassoResult{}, fmt.Errorf("concluir passo da agenda: %w", err)
	}

	todosConcluidos, err := r.todosPassosConcluidos(ctx, agendaID)
	if err != nil {
		return ConcluirPassoResult{}, err
	}

	if todosConcluidos {
		_ = r.marcarAgendaConcluida(ctx, agendaID)
	}

	return ConcluirPassoResult{
		AgendaID:              agendaID,
		AgendaItemID:          agendaItemID,
		TodosPassosConcluidos: todosConcluidos,
	}, nil
}

func (r *AgendaRepository) todosPassosConcluidos(ctx context.Context, agendaID string) (bool, error) {
	hasConcluido, err := r.columnExists(ctx, "agendaitens", "concluido")
	if err != nil {
		return false, err
	}
	hasStatus, err := r.columnExists(ctx, "agendaitens", "status")
	if err != nil {
		return false, err
	}
	hasConcluidoEm, err := r.columnExists(ctx, "agendaitens", "concluido_em")
	if err != nil {
		return false, err
	}

	query := ""
	switch {
	case hasConcluido:
		query = `SELECT count(*) FROM public.agendaitens WHERE agenda_id = $1 AND COALESCE(concluido, false) = false`
	case hasStatus:
		query = `SELECT count(*) FROM public.agendaitens WHERE agenda_id = $1 AND lower(COALESCE(status, '')) NOT IN ('concluido', 'concluida', 'dispensado')`
	case hasConcluidoEm:
		query = `SELECT count(*) FROM public.agendaitens WHERE agenda_id = $1 AND concluido_em IS NULL`
	default:
		return false, nil
	}

	var pendentes int64
	if err := r.pool.QueryRow(ctx, query, agendaID).Scan(&pendentes); err != nil {
		return false, fmt.Errorf("contar passos pendentes da agenda: %w", err)
	}

	return pendentes == 0, nil
}

func (r *AgendaRepository) marcarAgendaConcluida(ctx context.Context, agendaID string) error {
	hasPassosConcluidos, err := r.columnExists(ctx, "agenda", "passos_concluidos")
	if err != nil {
		return err
	}
	hasConcluida, err := r.columnExists(ctx, "agenda", "concluida")
	if err != nil {
		return err
	}
	hasStatus, err := r.columnExists(ctx, "agenda", "status")
	if err != nil {
		return err
	}

	setParts := make([]string, 0, 3)
	if hasPassosConcluidos {
		setParts = append(setParts, "passos_concluidos = true")
	}
	if hasConcluida {
		setParts = append(setParts, "concluida = true")
	}
	if hasStatus {
		setParts = append(setParts, "status = 'passos_concluidos'")
	}

	if len(setParts) == 0 {
		return nil
	}

	query := fmt.Sprintf("UPDATE public.agenda SET %s WHERE id = $1", strings.Join(setParts, ", "))
	if _, err := r.pool.Exec(ctx, query, agendaID); err != nil {
		return fmt.Errorf("marcar agenda concluida: %w", err)
	}

	return nil
}

func (r *AgendaRepository) columnExists(ctx context.Context, tableName, columnName string) (bool, error) {
	const query = `
		SELECT EXISTS (
			SELECT 1
			FROM information_schema.columns
			WHERE table_schema = 'public'
			  AND table_name = $1
			  AND column_name = $2
		)`

	var exists bool
	if err := r.pool.QueryRow(ctx, query, tableName, columnName).Scan(&exists); err != nil {
		return false, fmt.Errorf("verificar coluna %s.%s: %w", tableName, columnName, err)
	}

	return exists, nil
}
