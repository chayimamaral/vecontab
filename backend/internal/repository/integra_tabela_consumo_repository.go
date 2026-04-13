package repository

import (
	"context"
	"fmt"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/jackc/pgx/v5/pgxpool"
)

type IntegraTabelaConsumoRepository struct {
	pool *pgxpool.Pool
}

type IntegraTabelaConsumoInput struct {
	ID            string
	Tipo          string
	Faixa         int
	QuantidadeDe  int
	QuantidadeAte *int
	Preco         float64
}

type IntegraRegistrarGastoInput struct {
	TenantID         string
	EmpresaDocumento string
	Tipo             string
	IDSistema        string
	IDServico        string
	Quantidade       int
}

func NewIntegraTabelaConsumoRepository(pool *pgxpool.Pool) *IntegraTabelaConsumoRepository {
	return &IntegraTabelaConsumoRepository{pool: pool}
}

func (r *IntegraTabelaConsumoRepository) ListFaixas(ctx context.Context, tipo string) ([]domain.IntegraTabelaConsumoFaixa, error) {
	query := `
		SELECT id, tipo, faixa, quantidade_de, quantidade_ate, preco, ativo
		  FROM public.integra_contador_tabela_consumo
		 WHERE ativo = true`
	args := []any{}
	if strings.TrimSpace(tipo) != "" {
		query += " AND lower(tipo) = lower($1)"
		args = append(args, strings.TrimSpace(tipo))
	}
	query += " ORDER BY tipo ASC, faixa ASC"

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list integra tabela consumo: %w", err)
	}
	defer rows.Close()

	out := make([]domain.IntegraTabelaConsumoFaixa, 0)
	for rows.Next() {
		var item domain.IntegraTabelaConsumoFaixa
		if err := rows.Scan(
			&item.ID,
			&item.Tipo,
			&item.Faixa,
			&item.QuantidadeDe,
			&item.QuantidadeAte,
			&item.Preco,
			&item.Ativo,
		); err != nil {
			return nil, fmt.Errorf("scan integra tabela consumo: %w", err)
		}
		out = append(out, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows integra tabela consumo: %w", err)
	}
	return out, nil
}

func (r *IntegraTabelaConsumoRepository) CreateFaixa(ctx context.Context, input IntegraTabelaConsumoInput) (domain.IntegraTabelaConsumoFaixa, error) {
	const query = `
		INSERT INTO public.integra_contador_tabela_consumo
			(tipo, faixa, quantidade_de, quantidade_ate, preco)
		VALUES ($1,$2,$3,$4,$5)
		RETURNING id, tipo, faixa, quantidade_de, quantidade_ate, preco, ativo`
	var out domain.IntegraTabelaConsumoFaixa
	if err := r.pool.QueryRow(
		ctx,
		query,
		input.Tipo,
		input.Faixa,
		input.QuantidadeDe,
		input.QuantidadeAte,
		input.Preco,
	).Scan(
		&out.ID,
		&out.Tipo,
		&out.Faixa,
		&out.QuantidadeDe,
		&out.QuantidadeAte,
		&out.Preco,
		&out.Ativo,
	); err != nil {
		return domain.IntegraTabelaConsumoFaixa{}, fmt.Errorf("create integra tabela consumo: %w", err)
	}
	return out, nil
}

func (r *IntegraTabelaConsumoRepository) UpdateFaixa(ctx context.Context, input IntegraTabelaConsumoInput) (domain.IntegraTabelaConsumoFaixa, error) {
	const query = `
		UPDATE public.integra_contador_tabela_consumo
		   SET tipo = $1, faixa = $2, quantidade_de = $3, quantidade_ate = $4, preco = $5, atualizado_em = now()
		 WHERE id = $6 AND ativo = true
		RETURNING id, tipo, faixa, quantidade_de, quantidade_ate, preco, ativo`
	var out domain.IntegraTabelaConsumoFaixa
	if err := r.pool.QueryRow(
		ctx,
		query,
		input.Tipo,
		input.Faixa,
		input.QuantidadeDe,
		input.QuantidadeAte,
		input.Preco,
		input.ID,
	).Scan(
		&out.ID,
		&out.Tipo,
		&out.Faixa,
		&out.QuantidadeDe,
		&out.QuantidadeAte,
		&out.Preco,
		&out.Ativo,
	); err != nil {
		return domain.IntegraTabelaConsumoFaixa{}, fmt.Errorf("update integra tabela consumo: %w", err)
	}
	return out, nil
}

func (r *IntegraTabelaConsumoRepository) DeleteFaixa(ctx context.Context, id string) error {
	const query = `
		UPDATE public.integra_contador_tabela_consumo
		   SET ativo = false, atualizado_em = now()
		 WHERE id = $1 AND ativo = true`
	ct, err := r.pool.Exec(ctx, query, id)
	if err != nil {
		return fmt.Errorf("delete integra tabela consumo: %w", err)
	}
	if ct.RowsAffected() == 0 {
		return fmt.Errorf("registro nao encontrado")
	}
	return nil
}

func (r *IntegraTabelaConsumoRepository) RegistrarGasto(ctx context.Context, in IntegraRegistrarGastoInput) (domain.IntegraContadorGasto, error) {
	const consumoMesQuery = `
		SELECT COALESCE(SUM(quantidade), 0)
		  FROM public.integra_contador_gasto
		 WHERE tenant_id = $1
		   AND lower(tipo) = lower($2)
		   AND date_trunc('month', processado_em) = date_trunc('month', now())`
	var consumoAtual int
	if err := r.pool.QueryRow(ctx, consumoMesQuery, in.TenantID, in.Tipo).Scan(&consumoAtual); err != nil {
		return domain.IntegraContadorGasto{}, fmt.Errorf("consulta consumo mensal: %w", err)
	}
	consumoMes := consumoAtual + in.Quantidade

	const faixaQuery = `
		SELECT faixa, preco
		  FROM public.integra_contador_tabela_consumo
		 WHERE ativo = true
		   AND lower(tipo) = lower($1)
		   AND $2 >= quantidade_de
		   AND (quantidade_ate IS NULL OR $2 <= quantidade_ate)
		 ORDER BY faixa ASC
		 LIMIT 1`
	var faixa int
	var preco float64
	if err := r.pool.QueryRow(ctx, faixaQuery, in.Tipo, consumoMes).Scan(&faixa, &preco); err != nil {
		return domain.IntegraContadorGasto{}, fmt.Errorf("faixa de consumo nao encontrada para tipo '%s' e consumo %d", in.Tipo, consumoMes)
	}

	valorTotal := preco * float64(in.Quantidade)
	const insertQuery = `
		INSERT INTO public.integra_contador_gasto
			(tenant_id, empresa_documento, tipo, id_sistema, id_servico, quantidade, consumo_mes, faixa_aplicada, preco_unitario, valor_total)
		VALUES
			($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
		RETURNING id, tenant_id, empresa_documento, tipo, id_sistema, id_servico, quantidade, consumo_mes, faixa_aplicada, preco_unitario, valor_total, to_char(processado_em, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')`
	var out domain.IntegraContadorGasto
	if err := r.pool.QueryRow(
		ctx,
		insertQuery,
		in.TenantID,
		in.EmpresaDocumento,
		in.Tipo,
		in.IDSistema,
		in.IDServico,
		in.Quantidade,
		consumoMes,
		faixa,
		preco,
		valorTotal,
	).Scan(
		&out.ID,
		&out.TenantID,
		&out.EmpresaDocumento,
		&out.Tipo,
		&out.IDSistema,
		&out.IDServico,
		&out.Quantidade,
		&out.ConsumoMes,
		&out.FaixaAplicada,
		&out.PrecoUnitario,
		&out.ValorTotal,
		&out.ProcessadoEm,
	); err != nil {
		return domain.IntegraContadorGasto{}, fmt.Errorf("registrar gasto integra contador: %w", err)
	}
	return out, nil
}

func (r *IntegraTabelaConsumoRepository) ListGastos(ctx context.Context, tenantID, empresaDocumento, tipo string) ([]domain.IntegraContadorGasto, error) {
	query := `
		SELECT id, tenant_id, empresa_documento, tipo, id_sistema, id_servico, quantidade, consumo_mes, faixa_aplicada, preco_unitario, valor_total, to_char(processado_em, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
		  FROM public.integra_contador_gasto
		 WHERE tenant_id = $1`
	args := []any{tenantID}
	if strings.TrimSpace(empresaDocumento) != "" {
		query += fmt.Sprintf(" AND empresa_documento = $%d", len(args)+1)
		args = append(args, strings.TrimSpace(empresaDocumento))
	}
	if strings.TrimSpace(tipo) != "" {
		query += fmt.Sprintf(" AND lower(tipo) = lower($%d)", len(args)+1)
		args = append(args, strings.TrimSpace(tipo))
	}
	query += " ORDER BY processado_em DESC, id DESC"

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list gastos integra contador: %w", err)
	}
	defer rows.Close()

	out := make([]domain.IntegraContadorGasto, 0)
	for rows.Next() {
		var item domain.IntegraContadorGasto
		if err := rows.Scan(
			&item.ID,
			&item.TenantID,
			&item.EmpresaDocumento,
			&item.Tipo,
			&item.IDSistema,
			&item.IDServico,
			&item.Quantidade,
			&item.ConsumoMes,
			&item.FaixaAplicada,
			&item.PrecoUnitario,
			&item.ValorTotal,
			&item.ProcessadoEm,
		); err != nil {
			return nil, fmt.Errorf("scan gastos integra contador: %w", err)
		}
		out = append(out, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows gastos integra contador: %w", err)
	}
	return out, nil
}
