package repository

import (
	"context"
	"fmt"

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
				WHEN CURRENT_DATE > a.termino THEN 'pink'
				WHEN CURRENT_DATE BETWEEN a.inicio AND a.termino THEN '#FFDAB9'
				WHEN CURRENT_DATE < a.termino THEN '#A0D6B4'
				ELSE ''
			END AS background_color,
			CASE
				WHEN CURRENT_DATE > a.termino THEN 'black'
				WHEN CURRENT_DATE BETWEEN a.inicio AND a.termino THEN 'black'
				WHEN CURRENT_DATE < a.inicio THEN 'black'
				ELSE ''
			END AS text_color,
			CASE
				WHEN CURRENT_DATE > a.termino THEN 'pink'
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
				WHEN CURRENT_DATE > a.termino THEN 'pink'
				WHEN CURRENT_DATE BETWEEN a.inicio AND a.termino THEN '#FFDAB9'
				WHEN CURRENT_DATE < a.termino THEN '#A0D6B4'
				ELSE ''
			END AS background_color,
			CASE
				WHEN CURRENT_DATE > a.termino THEN 'black'
				WHEN CURRENT_DATE BETWEEN a.inicio AND a.termino THEN 'black'
				WHEN CURRENT_DATE < a.inicio THEN 'black'
				ELSE ''
			END AS text_color,
			CASE
				WHEN CURRENT_DATE > a.termino THEN 'pink'
				WHEN CURRENT_DATE BETWEEN a.inicio AND a.termino THEN '#FFDAB9'
				WHEN CURRENT_DATE < a.inicio THEN '#A0D6B4'
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
