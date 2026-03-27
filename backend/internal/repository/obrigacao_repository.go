package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ── Types ────────────────────────────────────────────────────────────────────

type ObrigacaoListItem struct {
	ID            string `json:"id"`
	TipoEmpresaID string `json:"tipo_empresa_id"`
	Descricao     string `json:"descricao"`
	DiaBase       int    `json:"dia_base"`
	MesBase       *int   `json:"mes_base"`
	Frequencia    string `json:"frequencia"`
	Tipo          string `json:"tipo"`
}

type ObrigacaoUpsertInput struct {
	ID            string
	TipoEmpresaID string
	Descricao     string
	DiaBase       int
	MesBase       *int
	Frequencia    string
	Tipo          string
}

// ── Repository ───────────────────────────────────────────────────────────────

type ObrigacaoRepository struct {
	pool *pgxpool.Pool
}

func NewObrigacaoRepository(pool *pgxpool.Pool) *ObrigacaoRepository {
	return &ObrigacaoRepository{pool: pool}
}

func (r *ObrigacaoRepository) ListByTipoEmpresa(ctx context.Context, tipoEmpresaID string) ([]ObrigacaoListItem, error) {
	const query = `
		SELECT id, tipo_empresa_id, descricao, dia_base, mes_base, frequencia, tipo
		FROM public.tipoempresa_obrigacao
		WHERE tipo_empresa_id = $1 AND ativo = true
		ORDER BY descricao ASC`

	rows, err := r.pool.Query(ctx, query, tipoEmpresaID)
	if err != nil {
		return nil, fmt.Errorf("list obrigacoes: %w", err)
	}
	defer rows.Close()

	items := make([]ObrigacaoListItem, 0)
	for rows.Next() {
		var o ObrigacaoListItem
		if err := rows.Scan(&o.ID, &o.TipoEmpresaID, &o.Descricao, &o.DiaBase, &o.MesBase, &o.Frequencia, &o.Tipo); err != nil {
			return nil, fmt.Errorf("scan obrigacao: %w", err)
		}
		items = append(items, o)
	}

	return items, nil
}

func (r *ObrigacaoRepository) Create(ctx context.Context, input ObrigacaoUpsertInput) (ObrigacaoListItem, error) {
	const query = `
		INSERT INTO public.tipoempresa_obrigacao (tipo_empresa_id, descricao, dia_base, mes_base, frequencia, tipo)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, tipo_empresa_id, descricao, dia_base, mes_base, frequencia, tipo`

	var o ObrigacaoListItem
	err := r.pool.QueryRow(ctx, query,
		input.TipoEmpresaID, input.Descricao, input.DiaBase, input.MesBase, input.Frequencia, input.Tipo,
	).Scan(&o.ID, &o.TipoEmpresaID, &o.Descricao, &o.DiaBase, &o.MesBase, &o.Frequencia, &o.Tipo)
	if err != nil {
		return ObrigacaoListItem{}, fmt.Errorf("create obrigacao: %w", err)
	}

	return o, nil
}

func (r *ObrigacaoRepository) Update(ctx context.Context, input ObrigacaoUpsertInput) (ObrigacaoListItem, error) {
	const query = `
		UPDATE public.tipoempresa_obrigacao
		SET descricao = $1, dia_base = $2, mes_base = $3, frequencia = $4, tipo = $5, atualizado_em = NOW()
		WHERE id = $6 AND ativo = true
		RETURNING id, tipo_empresa_id, descricao, dia_base, mes_base, frequencia, tipo`

	var o ObrigacaoListItem
	err := r.pool.QueryRow(ctx, query,
		input.Descricao, input.DiaBase, input.MesBase, input.Frequencia, input.Tipo, input.ID,
	).Scan(&o.ID, &o.TipoEmpresaID, &o.Descricao, &o.DiaBase, &o.MesBase, &o.Frequencia, &o.Tipo)
	if err != nil {
		return ObrigacaoListItem{}, fmt.Errorf("update obrigacao: %w", err)
	}

	return o, nil
}

func (r *ObrigacaoRepository) Delete(ctx context.Context, id string) error {
	const query = `UPDATE public.tipoempresa_obrigacao SET ativo = false, atualizado_em = NOW() WHERE id = $1`
	_, err := r.pool.Exec(ctx, query, id)
	if err != nil {
		return fmt.Errorf("delete obrigacao: %w", err)
	}
	return nil
}
