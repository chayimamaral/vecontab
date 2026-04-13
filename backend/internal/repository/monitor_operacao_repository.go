package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type MonitorOperacaoRepository struct {
	pool *pgxpool.Pool
}

func NewMonitorOperacaoRepository(pool *pgxpool.Pool) *MonitorOperacaoRepository {
	return &MonitorOperacaoRepository{pool: pool}
}

type MonitorOperacaoInsert struct {
	TenantID string
	UserID   *string
	Origem   string
	Tipo     string
	Status   string
	Mensagem *string
	Detalhe  map[string]any
}

func (r *MonitorOperacaoRepository) Insert(ctx context.Context, row MonitorOperacaoInsert) error {
	tid := strings.TrimSpace(row.TenantID)
	if tid == "" {
		return fmt.Errorf("tenant_id obrigatorio")
	}
	var detJSON []byte
	if row.Detalhe != nil {
		var err error
		detJSON, err = json.Marshal(row.Detalhe)
		if err != nil {
			return fmt.Errorf("marshal detalhe monitor_operacao: %w", err)
		}
	}

	const q = `
INSERT INTO public.monitor_operacao (tenant_id, user_id, origem, tipo, status, mensagem, detalhe)
VALUES ($1::uuid, $2, $3, $4, $5, $6, $7::jsonb)
`
	_, err := r.pool.Exec(ctx, q,
		tid,
		row.UserID,
		strings.TrimSpace(row.Origem),
		strings.TrimSpace(row.Tipo),
		strings.TrimSpace(row.Status),
		row.Mensagem,
		detJSON,
	)
	if err != nil {
		return fmt.Errorf("insert monitor_operacao: %w", err)
	}
	return nil
}

func (r *MonitorOperacaoRepository) CountList(ctx context.Context, viewerRole, viewerTenantID string) (int64, error) {
	role := strings.TrimSpace(strings.ToUpper(viewerRole))
	tid := strings.TrimSpace(viewerTenantID)

	var n int64
	var err error
	if role == "SUPER" {
		err = r.pool.QueryRow(ctx, `SELECT count(*) FROM public.monitor_operacao`).Scan(&n)
	} else {
		err = r.pool.QueryRow(ctx, `SELECT count(*) FROM public.monitor_operacao WHERE tenant_id = $1::uuid`, tid).Scan(&n)
	}
	if err != nil {
		return 0, fmt.Errorf("count monitor_operacao: %w", err)
	}
	return n, nil
}

func (r *MonitorOperacaoRepository) ListPage(ctx context.Context, viewerRole, viewerTenantID string, limit, offset int) ([]domain.MonitorOperacaoItem, error) {
	if limit <= 0 {
		limit = 50
	}
	if limit > 500 {
		limit = 500
	}
	if offset < 0 {
		offset = 0
	}

	role := strings.TrimSpace(strings.ToUpper(viewerRole))
	tid := strings.TrimSpace(viewerTenantID)

	var rows pgx.Rows
	var err error
	if role == "SUPER" {
		const q = `
SELECT mo.id, mo.tenant_id, t.nome, mo.user_id, mo.origem, mo.tipo, mo.status, mo.mensagem, mo.detalhe, mo.criado_em
FROM public.monitor_operacao mo
LEFT JOIN public.tenant t ON t.id = mo.tenant_id
ORDER BY mo.criado_em DESC
LIMIT $1 OFFSET $2
`
		rows, err = r.pool.Query(ctx, q, limit, offset)
	} else {
		const q = `
SELECT mo.id, mo.tenant_id, t.nome, mo.user_id, mo.origem, mo.tipo, mo.status, mo.mensagem, mo.detalhe, mo.criado_em
FROM public.monitor_operacao mo
LEFT JOIN public.tenant t ON t.id = mo.tenant_id
WHERE mo.tenant_id = $1::uuid
ORDER BY mo.criado_em DESC
LIMIT $2 OFFSET $3
`
		rows, err = r.pool.Query(ctx, q, tid, limit, offset)
	}
	if err != nil {
		return nil, fmt.Errorf("list monitor_operacao: %w", err)
	}
	defer rows.Close()

	out := make([]domain.MonitorOperacaoItem, 0)
	for rows.Next() {
		var it domain.MonitorOperacaoItem
		var tenantNome, userID, mensagem *string
		var detBytes []byte
		if err := rows.Scan(
			&it.ID,
			&it.TenantID,
			&tenantNome,
			&userID,
			&it.Origem,
			&it.Tipo,
			&it.Status,
			&mensagem,
			&detBytes,
			&it.CriadoEm,
		); err != nil {
			return nil, fmt.Errorf("scan monitor_operacao: %w", err)
		}
		it.TenantNome = tenantNome
		it.UserID = userID
		it.Mensagem = mensagem
		if len(detBytes) > 0 {
			var m map[string]any
			if err := json.Unmarshal(detBytes, &m); err == nil {
				it.Detalhe = m
			}
		}
		out = append(out, it)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return out, nil
}
