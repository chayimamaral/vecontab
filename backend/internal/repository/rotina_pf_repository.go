package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5/pgxpool"
)

type RotinaPFRepository struct {
	pool *pgxpool.Pool
}

func NewRotinaPFRepository(pool *pgxpool.Pool) *RotinaPFRepository {
	return &RotinaPFRepository{pool: pool}
}

type RotinaPFListParams struct {
	First     int
	Rows      int
	SortField string
	SortOrder int
	Nome      string
	TenantID  string
}

type RotinaPFUpsertInput struct {
	ID          string
	TenantID    string
	Nome        string
	Categoria   string
	Descricao   string
	Ativo       bool
}

type RotinaPFItemUpsertInput struct {
	ID            string
	RotinaPFID    string
	TenantID      string
	Ordem         int
	PassoID       string
	Descricao     string
	TempoEstimado int
}

func validRotinaPFCategoria(s string) (string, error) {
	c := strings.ToUpper(strings.TrimSpace(s))
	switch c {
	case "MENSALISTA", "SAZONAL_IRPF", "AVULSO":
		return c, nil
	default:
		return "", fmt.Errorf("categoria invalida: use MENSALISTA, SAZONAL_IRPF ou AVULSO")
	}
}

func (r *RotinaPFRepository) tenantOwnsRotinaPF(ctx context.Context, rotinaPFID, tenantID string) (bool, error) {
	var ok bool
	err := r.pool.QueryRow(ctx, `
		SELECT EXISTS (SELECT 1 FROM public.rotina_pf WHERE id = $1::uuid AND tenant_id = $2)`,
		rotinaPFID, tenantID,
	).Scan(&ok)
	return ok, err
}

// ListLite retorna rotinas PF ativas do tenant (dropdown).
func (r *RotinaPFRepository) ListLite(ctx context.Context, tenantID string) ([]domain.RotinaPFLiteItem, int64, error) {
	const q = `
		SELECT id::text, nome, categoria
		FROM public.rotina_pf
		WHERE tenant_id = $1 AND ativo = true
		ORDER BY nome ASC, id ASC`

	rows, err := r.pool.Query(ctx, q, tenantID)
	if err != nil {
		return nil, 0, fmt.Errorf("list rotina_pf lite: %w", err)
	}
	defer rows.Close()

	out := make([]domain.RotinaPFLiteItem, 0)
	for rows.Next() {
		var it domain.RotinaPFLiteItem
		if err := rows.Scan(&it.ID, &it.Nome, &it.Categoria); err != nil {
			return nil, 0, fmt.Errorf("scan rotina_pf lite: %w", err)
		}
		out = append(out, it)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return out, int64(len(out)), nil
}

// List administrativa: todas as rotinas do tenant (ativas e inativas).
func (r *RotinaPFRepository) List(ctx context.Context, params RotinaPFListParams) ([]domain.RotinaPFListRow, int64, error) {
	whereParts := []string{"r.tenant_id = $1"}
	args := []any{params.TenantID}
	argIndex := 2

	if strings.TrimSpace(params.Nome) != "" {
		whereParts = append(whereParts, fmt.Sprintf("r.nome ILIKE $%d", argIndex))
		args = append(args, "%"+strings.TrimSpace(params.Nome)+"%")
		argIndex++
	}

	orderBy := "r.nome ASC, r.id ASC"
	switch params.SortField {
	case "categoria":
		if params.SortOrder == -1 {
			orderBy = "r.categoria DESC, r.nome ASC"
		} else {
			orderBy = "r.categoria ASC, r.nome ASC"
		}
	case "criado_em":
		if params.SortOrder == -1 {
			orderBy = "r.criado_em DESC, r.nome ASC"
		} else {
			orderBy = "r.criado_em ASC, r.nome ASC"
		}
	default:
		if params.SortOrder == -1 {
			orderBy = "r.nome DESC, r.id ASC"
		} else {
			orderBy = "r.nome ASC, r.id ASC"
		}
	}

	query := fmt.Sprintf(`
		SELECT
			r.id::text,
			r.nome,
			r.categoria,
			COALESCE(r.descricao, ''),
			r.ativo,
			r.criado_em,
			(SELECT COUNT(*)::bigint FROM public.rotina_pf_itens i WHERE i.rotina_pf_id = r.id)
		FROM public.rotina_pf r
		WHERE %s
		ORDER BY %s
		LIMIT $%d OFFSET $%d`, strings.Join(whereParts, " AND "), orderBy, argIndex, argIndex+1)
	args = append(args, params.Rows, params.First)

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list rotina_pf: %w", err)
	}
	defer rows.Close()

	out := make([]domain.RotinaPFListRow, 0)
	for rows.Next() {
		var row domain.RotinaPFListRow
		var ts time.Time
		if err := rows.Scan(&row.ID, &row.Nome, &row.Categoria, &row.Descricao, &row.Ativo, &ts, &row.ItemCount); err != nil {
			return nil, 0, fmt.Errorf("scan rotina_pf list: %w", err)
		}
		row.CriadoEm = ts.UTC().Format(time.RFC3339)
		out = append(out, row)
	}

	countQ := fmt.Sprintf(`SELECT count(*) FROM public.rotina_pf r WHERE %s`, strings.Join(whereParts, " AND "))
	var total int64
	if err := r.pool.QueryRow(ctx, countQ, args[:len(args)-2]...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count rotina_pf: %w", err)
	}
	return out, total, nil
}

func (r *RotinaPFRepository) Create(ctx context.Context, in RotinaPFUpsertInput) ([]domain.RotinaPFListRow, int64, error) {
	cat, err := validRotinaPFCategoria(in.Categoria)
	if err != nil {
		return nil, 0, err
	}
	nome := strings.TrimSpace(in.Nome)
	if nome == "" {
		return nil, 0, fmt.Errorf("nome obrigatorio")
	}

	const q = `
		INSERT INTO public.rotina_pf (tenant_id, nome, categoria, descricao, ativo)
		VALUES ($1, $2, $3, NULLIF(TRIM($4), ''), $5)
		RETURNING id::text`

	var id string
	if err := r.pool.QueryRow(ctx, q, in.TenantID, nome, cat, in.Descricao, in.Ativo).Scan(&id); err != nil {
		return nil, 0, fmt.Errorf("create rotina_pf: %w", err)
	}
	const one = `
		SELECT
			r.id::text, r.nome, r.categoria, COALESCE(r.descricao, ''), r.ativo, r.criado_em,
			(SELECT COUNT(*)::bigint FROM public.rotina_pf_itens i WHERE i.rotina_pf_id = r.id)
		FROM public.rotina_pf r WHERE r.id = $1::uuid AND r.tenant_id = $2`
	var row domain.RotinaPFListRow
	var ts time.Time
	if err := r.pool.QueryRow(ctx, one, id, in.TenantID).Scan(
		&row.ID, &row.Nome, &row.Categoria, &row.Descricao, &row.Ativo, &ts, &row.ItemCount,
	); err != nil {
		return nil, 0, fmt.Errorf("load rotina_pf criada: %w", err)
	}
	row.CriadoEm = ts.UTC().Format(time.RFC3339)
	return []domain.RotinaPFListRow{row}, 1, nil
}

func (r *RotinaPFRepository) Update(ctx context.Context, in RotinaPFUpsertInput) ([]domain.RotinaPFListRow, int64, error) {
	cat, err := validRotinaPFCategoria(in.Categoria)
	if err != nil {
		return nil, 0, err
	}
	nome := strings.TrimSpace(in.Nome)
	if nome == "" || strings.TrimSpace(in.ID) == "" {
		return nil, 0, fmt.Errorf("id e nome obrigatorios")
	}

	cmd, err := r.pool.Exec(ctx, `
		UPDATE public.rotina_pf
		SET nome = $1, categoria = $2, descricao = NULLIF(TRIM($3), ''), ativo = $4, atualizado_em = now()
		WHERE id = $5::uuid AND tenant_id = $6`,
		nome, cat, in.Descricao, in.Ativo, in.ID, in.TenantID,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("update rotina_pf: %w", err)
	}
	if cmd.RowsAffected() == 0 {
		return nil, 0, fmt.Errorf("rotina_pf nao encontrada neste tenant")
	}

	const one = `
		SELECT
			r.id::text, r.nome, r.categoria, COALESCE(r.descricao, ''), r.ativo, r.criado_em,
			(SELECT COUNT(*)::bigint FROM public.rotina_pf_itens i WHERE i.rotina_pf_id = r.id)
		FROM public.rotina_pf r WHERE r.id = $1::uuid AND r.tenant_id = $2`
	var row domain.RotinaPFListRow
	var ts time.Time
	if err := r.pool.QueryRow(ctx, one, in.ID, in.TenantID).Scan(
		&row.ID, &row.Nome, &row.Categoria, &row.Descricao, &row.Ativo, &ts, &row.ItemCount,
	); err != nil {
		return nil, 0, fmt.Errorf("load rotina_pf: %w", err)
	}
	row.CriadoEm = ts.UTC().Format(time.RFC3339)
	return []domain.RotinaPFListRow{row}, 1, nil
}

// SoftDelete marca ativo = false.
func (r *RotinaPFRepository) SoftDelete(ctx context.Context, id, tenantID string) ([]domain.RotinaPFListRow, int64, error) {
	cmd, err := r.pool.Exec(ctx, `
		UPDATE public.rotina_pf SET ativo = false, atualizado_em = now()
		WHERE id = $1::uuid AND tenant_id = $2`,
		id, tenantID,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("delete rotina_pf: %w", err)
	}
	if cmd.RowsAffected() == 0 {
		return nil, 0, fmt.Errorf("rotina_pf nao encontrada neste tenant")
	}
	return []domain.RotinaPFListRow{}, 0, nil
}

// ListItens lista passos da rotina (tenant pela rotina pai).
func (r *RotinaPFRepository) ListItens(ctx context.Context, rotinaPFID, tenantID string) ([]domain.RotinaPFItemRow, int64, error) {
	ok, err := r.tenantOwnsRotinaPF(ctx, rotinaPFID, tenantID)
	if err != nil {
		return nil, 0, err
	}
	if !ok {
		return nil, 0, fmt.Errorf("rotina_pf nao encontrada neste tenant")
	}

	const q = `
		SELECT
			i.id::text,
			i.rotina_pf_id::text,
			i.ordem,
			COALESCE(i.passo_id::text, ''),
			COALESCE(p.descricao, ''),
			COALESCE(i.descricao, ''),
			i.tempo_estimado
		FROM public.rotina_pf_itens i
		LEFT JOIN public.passos p ON p.id = i.passo_id
		WHERE i.rotina_pf_id = $1::uuid
		ORDER BY i.ordem ASC, i.id ASC`

	rows, err := r.pool.Query(ctx, q, rotinaPFID)
	if err != nil {
		return nil, 0, fmt.Errorf("list rotina_pf_itens: %w", err)
	}
	defer rows.Close()

	out := make([]domain.RotinaPFItemRow, 0)
	for rows.Next() {
		var it domain.RotinaPFItemRow
		if err := rows.Scan(&it.ID, &it.RotinaPFID, &it.Ordem, &it.PassoID, &it.PassoDescricao, &it.Descricao, &it.TempoEstimado); err != nil {
			return nil, 0, fmt.Errorf("scan rotina_pf_item: %w", err)
		}
		out = append(out, it)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return out, int64(len(out)), nil
}

func (r *RotinaPFRepository) CreateItem(ctx context.Context, in RotinaPFItemUpsertInput) ([]domain.RotinaPFItemRow, int64, error) {
	ok, err := r.tenantOwnsRotinaPF(ctx, in.RotinaPFID, in.TenantID)
	if err != nil {
		return nil, 0, err
	}
	if !ok {
		return nil, 0, fmt.Errorf("rotina_pf nao encontrada neste tenant")
	}

	passoArg := any(nil)
	if pid := strings.TrimSpace(in.PassoID); pid != "" {
		passoArg = pid
	}

	const q = `
		INSERT INTO public.rotina_pf_itens (rotina_pf_id, ordem, passo_id, descricao, tempo_estimado)
		VALUES ($1::uuid, $2, $3, NULLIF(TRIM($4), ''), $5)`

	if _, err := r.pool.Exec(ctx, q, in.RotinaPFID, in.Ordem, passoArg, in.Descricao, in.TempoEstimado); err != nil {
		return nil, 0, fmt.Errorf("create rotina_pf_item: %w", err)
	}
	return r.ListItens(ctx, in.RotinaPFID, in.TenantID)
}

func (r *RotinaPFRepository) UpdateItem(ctx context.Context, in RotinaPFItemUpsertInput) ([]domain.RotinaPFItemRow, int64, error) {
	if strings.TrimSpace(in.ID) == "" {
		return nil, 0, fmt.Errorf("id do item obrigatorio")
	}
	ok, err := r.tenantOwnsRotinaPF(ctx, in.RotinaPFID, in.TenantID)
	if err != nil {
		return nil, 0, err
	}
	if !ok {
		return nil, 0, fmt.Errorf("rotina_pf nao encontrada neste tenant")
	}

	passoArg := any(nil)
	if pid := strings.TrimSpace(in.PassoID); pid != "" {
		passoArg = pid
	}

	cmd, err := r.pool.Exec(ctx, `
		UPDATE public.rotina_pf_itens i
		SET ordem = $1, passo_id = $2, descricao = NULLIF(TRIM($3), ''), tempo_estimado = $4
		FROM public.rotina_pf r
		WHERE i.id = $5::uuid AND i.rotina_pf_id = r.id AND r.tenant_id = $6 AND i.rotina_pf_id = $7::uuid`,
		in.Ordem, passoArg, in.Descricao, in.TempoEstimado, in.ID, in.TenantID, in.RotinaPFID,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("update rotina_pf_item: %w", err)
	}
	if cmd.RowsAffected() == 0 {
		return nil, 0, fmt.Errorf("item nao encontrado neste tenant")
	}
	return r.ListItens(ctx, in.RotinaPFID, in.TenantID)
}

func (r *RotinaPFRepository) DeleteItem(ctx context.Context, itemID, rotinaPFID, tenantID string) ([]domain.RotinaPFItemRow, int64, error) {
	ok, err := r.tenantOwnsRotinaPF(ctx, rotinaPFID, tenantID)
	if err != nil {
		return nil, 0, err
	}
	if !ok {
		return nil, 0, fmt.Errorf("rotina_pf nao encontrada neste tenant")
	}

	cmd, err := r.pool.Exec(ctx, `
		DELETE FROM public.rotina_pf_itens i
		USING public.rotina_pf r
		WHERE i.id = $1::uuid AND i.rotina_pf_id = r.id AND r.tenant_id = $2 AND i.rotina_pf_id = $3::uuid`,
		itemID, tenantID, rotinaPFID,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("delete rotina_pf_item: %w", err)
	}
	if cmd.RowsAffected() == 0 {
		return nil, 0, fmt.Errorf("item nao encontrado neste tenant")
	}
	return r.ListItens(ctx, rotinaPFID, tenantID)
}

// NextOrdem retorna o próximo número de ordem livre para novos itens.
func (r *RotinaPFRepository) NextOrdem(ctx context.Context, rotinaPFID, tenantID string) (int, error) {
	ok, err := r.tenantOwnsRotinaPF(ctx, rotinaPFID, tenantID)
	if err != nil {
		return 0, err
	}
	if !ok {
		return 0, fmt.Errorf("rotina_pf nao encontrada neste tenant")
	}
	var max sql.NullInt64
	err = r.pool.QueryRow(ctx, `
		SELECT MAX(i.ordem) FROM public.rotina_pf_itens i
		WHERE i.rotina_pf_id = $1::uuid`, rotinaPFID).Scan(&max)
	if err != nil {
		return 0, err
	}
	if !max.Valid {
		return 0, nil
	}
	return int(max.Int64) + 1, nil
}
