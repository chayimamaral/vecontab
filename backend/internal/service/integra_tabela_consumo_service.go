package service

import (
	"context"
	"fmt"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/chayimamaral/vecontab/backend/internal/repository"
)

type IntegraTabelaConsumoService struct {
	repo *repository.IntegraTabelaConsumoRepository
}

type IntegraTabelaConsumoInput struct {
	ID            string  `json:"id"`
	Tipo          string  `json:"tipo"`
	Faixa         int     `json:"faixa"`
	QuantidadeDe  int     `json:"quantidade_de"`
	QuantidadeAte *int    `json:"quantidade_ate"`
	Preco         float64 `json:"preco"`
}

func NewIntegraTabelaConsumoService(repo *repository.IntegraTabelaConsumoRepository) *IntegraTabelaConsumoService {
	return &IntegraTabelaConsumoService{repo: repo}
}

func (s *IntegraTabelaConsumoService) ListFaixas(ctx context.Context, tipo string) ([]domain.IntegraTabelaConsumoFaixa, error) {
	return s.repo.ListFaixas(ctx, strings.TrimSpace(tipo))
}

func (s *IntegraTabelaConsumoService) CreateFaixa(ctx context.Context, in IntegraTabelaConsumoInput) (domain.IntegraTabelaConsumoFaixa, error) {
	if err := validarFaixaConsumo(in); err != nil {
		return domain.IntegraTabelaConsumoFaixa{}, err
	}
	return s.repo.CreateFaixa(ctx, repository.IntegraTabelaConsumoInput{
		Tipo:          strings.TrimSpace(in.Tipo),
		Faixa:         in.Faixa,
		QuantidadeDe:  in.QuantidadeDe,
		QuantidadeAte: in.QuantidadeAte,
		Preco:         in.Preco,
	})
}

func (s *IntegraTabelaConsumoService) UpdateFaixa(ctx context.Context, in IntegraTabelaConsumoInput) (domain.IntegraTabelaConsumoFaixa, error) {
	if strings.TrimSpace(in.ID) == "" {
		return domain.IntegraTabelaConsumoFaixa{}, fmt.Errorf("id obrigatorio")
	}
	if err := validarFaixaConsumo(in); err != nil {
		return domain.IntegraTabelaConsumoFaixa{}, err
	}
	return s.repo.UpdateFaixa(ctx, repository.IntegraTabelaConsumoInput{
		ID:            strings.TrimSpace(in.ID),
		Tipo:          strings.TrimSpace(in.Tipo),
		Faixa:         in.Faixa,
		QuantidadeDe:  in.QuantidadeDe,
		QuantidadeAte: in.QuantidadeAte,
		Preco:         in.Preco,
	})
}

func (s *IntegraTabelaConsumoService) DeleteFaixa(ctx context.Context, id string) error {
	if strings.TrimSpace(id) == "" {
		return fmt.Errorf("id obrigatorio")
	}
	return s.repo.DeleteFaixa(ctx, strings.TrimSpace(id))
}

func (s *IntegraTabelaConsumoService) ListGastos(ctx context.Context, tenantID, empresaDocumento, tipo string) ([]domain.IntegraContadorGasto, error) {
	if strings.TrimSpace(tenantID) == "" {
		return nil, fmt.Errorf("tenant obrigatorio")
	}
	return s.repo.ListGastos(ctx, strings.TrimSpace(tenantID), strings.TrimSpace(empresaDocumento), strings.TrimSpace(tipo))
}

func (s *IntegraTabelaConsumoService) RegistrarGasto(ctx context.Context, in repository.IntegraRegistrarGastoInput) (domain.IntegraContadorGasto, error) {
	if strings.TrimSpace(in.TenantID) == "" {
		return domain.IntegraContadorGasto{}, fmt.Errorf("tenant obrigatorio")
	}
	if strings.TrimSpace(in.Tipo) == "" {
		return domain.IntegraContadorGasto{}, fmt.Errorf("tipo obrigatorio")
	}
	if strings.TrimSpace(in.EmpresaDocumento) == "" {
		return domain.IntegraContadorGasto{}, fmt.Errorf("empresa_documento obrigatorio")
	}
	if in.Quantidade <= 0 {
		in.Quantidade = 1
	}
	return s.repo.RegistrarGasto(ctx, in)
}

func validarFaixaConsumo(in IntegraTabelaConsumoInput) error {
	if strings.TrimSpace(in.Tipo) == "" {
		return fmt.Errorf("tipo obrigatorio")
	}
	if in.Faixa <= 0 {
		return fmt.Errorf("faixa deve ser maior que zero")
	}
	if in.QuantidadeDe <= 0 {
		return fmt.Errorf("quantidade_de deve ser maior que zero")
	}
	if in.QuantidadeAte != nil && *in.QuantidadeAte < in.QuantidadeDe {
		return fmt.Errorf("quantidade_ate nao pode ser menor que quantidade_de")
	}
	if in.Preco < 0 {
		return fmt.Errorf("preco nao pode ser negativo")
	}
	return nil
}
