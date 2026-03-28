package service

import (
	"context"

	"github.com/chayimamaral/mare/backend/internal/repository"
)

type CidadeService struct {
	repo *repository.CidadeRepository
}

type CidadeListResponse struct {
	Municipios   []repository.CidadeListItem `json:"municipios"`
	TotalRecords int64                       `json:"totalRecords"`
}

type CidadeMutationResponse struct {
	Cidades      []repository.Cidade `json:"cidades"`
	TotalRecords int64               `json:"totalRecords"`
}

type CidadeLiteResponse struct {
	Municipios []repository.CidadeLiteItem `json:"municipios"`
}

func NewCidadeService(repo *repository.CidadeRepository) *CidadeService {
	return &CidadeService{repo: repo}
}

func (s *CidadeService) List(ctx context.Context, params repository.CidadeListParams) (CidadeListResponse, error) {
	municipios, total, err := s.repo.List(ctx, params)
	if err != nil {
		return CidadeListResponse{}, err
	}

	return CidadeListResponse{Municipios: municipios, TotalRecords: total}, nil
}

func (s *CidadeService) Create(ctx context.Context, nome, codigo, ufID string) (CidadeMutationResponse, error) {
	cidades, total, err := s.repo.Create(ctx, nome, codigo, ufID)
	if err != nil {
		return CidadeMutationResponse{}, err
	}

	return CidadeMutationResponse{Cidades: cidades, TotalRecords: total}, nil
}

func (s *CidadeService) Update(ctx context.Context, id, nome, codigo, ufID string) (CidadeMutationResponse, error) {
	cidades, total, err := s.repo.Update(ctx, id, nome, codigo, ufID)
	if err != nil {
		return CidadeMutationResponse{}, err
	}

	return CidadeMutationResponse{Cidades: cidades, TotalRecords: total}, nil
}

func (s *CidadeService) Delete(ctx context.Context, id string) (CidadeMutationResponse, error) {
	cidades, total, err := s.repo.Delete(ctx, id)
	if err != nil {
		return CidadeMutationResponse{}, err
	}

	return CidadeMutationResponse{Cidades: cidades, TotalRecords: total}, nil
}

func (s *CidadeService) ListLite(ctx context.Context) (CidadeLiteResponse, error) {
	municipios, err := s.repo.ListLite(ctx)
	if err != nil {
		return CidadeLiteResponse{}, err
	}

	return CidadeLiteResponse{Municipios: municipios}, nil
}
