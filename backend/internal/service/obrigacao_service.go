package service

import (
	"context"

	"github.com/chayimamaral/mare/backend/internal/repository"
)

type ObrigacaoService struct {
	repo *repository.ObrigacaoRepository
}

type ObrigacaoListResponse struct {
	Obrigacoes []repository.ObrigacaoListItem `json:"obrigacoes"`
}

type ObrigacaoMutationResponse struct {
	Obrigacao repository.ObrigacaoListItem `json:"obrigacao"`
}

func NewObrigacaoService(repo *repository.ObrigacaoRepository) *ObrigacaoService {
	return &ObrigacaoService{repo: repo}
}

func (s *ObrigacaoService) ListByTipoEmpresa(ctx context.Context, tipoEmpresaID string) (ObrigacaoListResponse, error) {
	items, err := s.repo.ListByTipoEmpresa(ctx, tipoEmpresaID)
	if err != nil {
		return ObrigacaoListResponse{}, err
	}
	return ObrigacaoListResponse{Obrigacoes: items}, nil
}

func (s *ObrigacaoService) Create(ctx context.Context, input repository.ObrigacaoUpsertInput) (ObrigacaoMutationResponse, error) {
	item, err := s.repo.Create(ctx, input)
	if err != nil {
		return ObrigacaoMutationResponse{}, err
	}
	return ObrigacaoMutationResponse{Obrigacao: item}, nil
}

func (s *ObrigacaoService) Update(ctx context.Context, input repository.ObrigacaoUpsertInput) (ObrigacaoMutationResponse, error) {
	item, err := s.repo.Update(ctx, input)
	if err != nil {
		return ObrigacaoMutationResponse{}, err
	}
	return ObrigacaoMutationResponse{Obrigacao: item}, nil
}

func (s *ObrigacaoService) Delete(ctx context.Context, id string) error {
	return s.repo.Delete(ctx, id)
}
