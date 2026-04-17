package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5/pgxpool"
)

type MonitorOperacaoRepository struct {
	pool *pgxpool.Pool
}

type MonitorOperacaoListFilter struct {
	ClienteNome string
	Status      string
	DataDeISO   string
	DataAteISO string
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

func (r *MonitorOperacaoRepository) Insert(ctx context.Context, row MonitorOperacaoInsert) (string, error) {
	tid := strings.TrimSpace(row.TenantID)
	if tid == "" {
		return "", fmt.Errorf("tenant_id obrigatorio")
	}
	var detJSON []byte
	if row.Detalhe != nil {
		var err error
		detJSON, err = json.Marshal(row.Detalhe)
		if err != nil {
			return "", fmt.Errorf("marshal detalhe monitor_operacao: %w", err)
		}
	}

	const q = `
INSERT INTO public.monitor_operacao (tenant_id, user_id, origem, tipo, status, mensagem, detalhe)
VALUES ($1::uuid, $2, $3, $4, $5, $6, $7::jsonb)
RETURNING id::text
`
	var id string
	err := r.pool.QueryRow(ctx, q,
		tid,
		row.UserID,
		strings.TrimSpace(row.Origem),
		strings.TrimSpace(row.Tipo),
		strings.TrimSpace(row.Status),
		row.Mensagem,
		detJSON,
	).Scan(&id)
	if err != nil {
		return "", fmt.Errorf("insert monitor_operacao: %w", err)
	}
	return id, nil
}

func (r *MonitorOperacaoRepository) InsertCompromissosRefs(ctx context.Context, monitorID string, compromissoIDs []string) error {
	mid := strings.TrimSpace(monitorID)
	if mid == "" || len(compromissoIDs) == 0 {
		return nil
	}
	const q = `
INSERT INTO public.monitor_operacao_compromisso (monitor_operacao_id, empresa_compromisso_id)
VALUES ($1::uuid, $2::uuid)
ON CONFLICT DO NOTHING`
	for _, cid := range compromissoIDs {
		cid = strings.TrimSpace(cid)
		if cid == "" {
			continue
		}
		if _, err := r.pool.Exec(ctx, q, mid, cid); err != nil {
			return fmt.Errorf("insert monitor_operacao_compromisso: %w", err)
		}
	}
	return nil
}

func (r *MonitorOperacaoRepository) CountList(ctx context.Context, viewerRole, viewerTenantID string, f MonitorOperacaoListFilter) (int64, error) {
	role := strings.TrimSpace(strings.ToUpper(viewerRole))
	tid := strings.TrimSpace(viewerTenantID)
	filterClienteNome := strings.TrimSpace(f.ClienteNome)
	filterStatus := strings.TrimSpace(strings.ToUpper(f.Status))
	filterDataDe := strings.TrimSpace(f.DataDeISO)
	filterDataAte := strings.TrimSpace(f.DataAteISO)

	var n int64
	args := make([]any, 0, 4)
	q := `
SELECT count(*)
FROM public.monitor_operacao mo
LEFT JOIN public.empresa e
  ON e.id = CASE
    WHEN COALESCE(mo.detalhe->>'empresa_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      THEN (mo.detalhe->>'empresa_id')::uuid
    ELSE NULL
  END
LEFT JOIN public.cliente c ON c.id = e.cliente_id
WHERE 1=1`
	if role == "ADMIN" {
		q += fmt.Sprintf(" AND mo.tenant_id = $%d::uuid", len(args)+1)
		args = append(args, tid)
	}
	if filterClienteNome != "" {
		q += fmt.Sprintf(" AND c.nome ILIKE $%d", len(args)+1)
		args = append(args, "%"+filterClienteNome+"%")
	}
	if filterStatus != "" {
		q += fmt.Sprintf(" AND UPPER(TRIM(mo.status)) = $%d", len(args)+1)
		args = append(args, filterStatus)
	}
	if filterDataDe != "" {
		q += fmt.Sprintf(" AND mo.criado_em::date >= $%d::date", len(args)+1)
		args = append(args, filterDataDe)
	}
	if filterDataAte != "" {
		q += fmt.Sprintf(" AND mo.criado_em::date <= $%d::date", len(args)+1)
		args = append(args, filterDataAte)
	}
	err := r.pool.QueryRow(ctx, q, args...).Scan(&n)
	if err != nil {
		return 0, fmt.Errorf("count monitor_operacao: %w", err)
	}
	return n, nil
}

func (r *MonitorOperacaoRepository) ListPage(ctx context.Context, viewerRole, viewerTenantID string, limit, offset int, f MonitorOperacaoListFilter) ([]domain.MonitorOperacaoItem, error) {
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
	filterClienteNome := strings.TrimSpace(f.ClienteNome)
	filterStatus := strings.TrimSpace(strings.ToUpper(f.Status))
	filterDataDe := strings.TrimSpace(f.DataDeISO)
	filterDataAte := strings.TrimSpace(f.DataAteISO)

	args := make([]any, 0, 8)
	q := `
SELECT mo.id, mo.tenant_id, t.nome, c.nome, mo.user_id, mo.origem, mo.tipo, mo.status, mo.mensagem, mo.detalhe, mo.criado_em
FROM public.monitor_operacao mo
LEFT JOIN public.tenant t ON t.id = mo.tenant_id
LEFT JOIN public.empresa e
  ON e.id = CASE
    WHEN COALESCE(mo.detalhe->>'empresa_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      THEN (mo.detalhe->>'empresa_id')::uuid
    ELSE NULL
  END
LEFT JOIN public.cliente c ON c.id = e.cliente_id
WHERE 1=1`
	if role == "ADMIN" {
		q += fmt.Sprintf(" AND mo.tenant_id = $%d::uuid", len(args)+1)
		args = append(args, tid)
	}
	if filterClienteNome != "" {
		q += fmt.Sprintf(" AND c.nome ILIKE $%d", len(args)+1)
		args = append(args, "%"+filterClienteNome+"%")
	}
	if filterStatus != "" {
		q += fmt.Sprintf(" AND UPPER(TRIM(mo.status)) = $%d", len(args)+1)
		args = append(args, filterStatus)
	}
	if filterDataDe != "" {
		q += fmt.Sprintf(" AND mo.criado_em::date >= $%d::date", len(args)+1)
		args = append(args, filterDataDe)
	}
	if filterDataAte != "" {
		q += fmt.Sprintf(" AND mo.criado_em::date <= $%d::date", len(args)+1)
		args = append(args, filterDataAte)
	}
	q += fmt.Sprintf(" ORDER BY mo.criado_em DESC LIMIT $%d OFFSET $%d", len(args)+1, len(args)+2)
	args = append(args, limit, offset)

	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("list monitor_operacao: %w", err)
	}
	defer rows.Close()

	out := make([]domain.MonitorOperacaoItem, 0)
	for rows.Next() {
		var it domain.MonitorOperacaoItem
		var tenantNome, clienteNome, userID, mensagem *string
		var detBytes []byte
		if err := rows.Scan(
			&it.ID,
			&it.TenantID,
			&tenantNome,
			&clienteNome,
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
		it.ClienteNome = clienteNome
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
	if err := r.attachCompromissos(ctx, out); err != nil {
		return nil, err
	}
	return out, nil
}

func (r *MonitorOperacaoRepository) attachCompromissos(ctx context.Context, itens []domain.MonitorOperacaoItem) error {
	if len(itens) == 0 {
		return nil
	}
	monitorIDs := make([]string, 0, len(itens))
	index := make(map[string]int, len(itens))
	for i, it := range itens {
		monitorIDs = append(monitorIDs, it.ID)
		index[it.ID] = i
	}
	const q = `
SELECT
  rel.monitor_operacao_id::text,
  ec.id::text,
  ec.empresa_id::text,
  c.nome,
  ec.descricao,
  ec.competencia::date::text,
  ec.vencimento::date::text,
  ec.status,
  ec.valor
FROM public.monitor_operacao_compromisso rel
INNER JOIN public.empresa_compromissos ec ON ec.id = rel.empresa_compromisso_id
LEFT JOIN public.empresa e ON e.id = ec.empresa_id
LEFT JOIN public.cliente c ON c.id = e.cliente_id
WHERE rel.monitor_operacao_id = ANY($1::uuid[])
ORDER BY rel.criado_em ASC, ec.vencimento ASC, ec.descricao ASC`
	rows, err := r.pool.Query(ctx, q, monitorIDs)
	if err != nil {
		return fmt.Errorf("list monitor_operacao_compromisso: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var monitorID string
		var child domain.MonitorOperacaoCompromissoItem
		var clienteNome *string
		var valor *float64
		if err := rows.Scan(
			&monitorID,
			&child.CompromissoID,
			&child.EmpresaID,
			&clienteNome,
			&child.Descricao,
			&child.Competencia,
			&child.Vencimento,
			&child.Status,
			&valor,
		); err != nil {
			return fmt.Errorf("scan monitor_operacao_compromisso: %w", err)
		}
		child.ClienteNome = clienteNome
		child.Valor = valor
		if idx, ok := index[monitorID]; ok {
			itens[idx].Compromissos = append(itens[idx].Compromissos, child)
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	return nil
}
