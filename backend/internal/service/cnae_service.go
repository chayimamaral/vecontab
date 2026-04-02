package service

import (
	"context"

	"github.com/chayimamaral/vecontab/backend/internal/repository"
)

type CnaeService struct {
	repo *repository.CnaeRepository
}

type CnaeInput struct {
	ID          string `json:"id"`
	Secao       string `json:"secao"`
	Divisao     string `json:"divisao"`
	Grupo       string `json:"grupo"`
	Classe      string `json:"classe"`
	Subclasse   string `json:"subclasse"`
	Denominacao string `json:"denominacao"`
}

type CnaeListResponse struct {
	Cnaes        []repository.CnaeRecord `json:"cnaes"`
	TotalRecords int64                   `json:"totalRecords"`
}

type CnaeLiteResponse struct {
	Cnaes []repository.CnaeLiteItem `json:"cnaes"`
}

type CnaeValidateResponse struct {
	Valid bool `json:"valid"`
}

// CnaeIbgeResolveResponse espelha repository.CnaeIbgeResolve (JSON da API).
type CnaeIbgeResolveResponse = repository.CnaeIbgeResolve

func NewCnaeService(repo *repository.CnaeRepository) *CnaeService {
	return &CnaeService{repo: repo}
}

func (s *CnaeService) List(ctx context.Context, params repository.CnaeListParams) (CnaeListResponse, error) {
	cnaes, total, err := s.repo.List(ctx, params)
	if err != nil {
		return CnaeListResponse{}, err
	}

	return CnaeListResponse{Cnaes: cnaes, TotalRecords: total}, nil
}

func (s *CnaeService) Create(ctx context.Context, input CnaeInput) (CnaeListResponse, error) {
	cnaes, total, err := s.repo.Create(ctx, input.Secao, input.Divisao, input.Grupo, input.Classe, input.Denominacao, input.Subclasse)
	if err != nil {
		return CnaeListResponse{}, err
	}

	return CnaeListResponse{Cnaes: cnaes, TotalRecords: total}, nil
}

func (s *CnaeService) Update(ctx context.Context, input CnaeInput) (CnaeListResponse, error) {
	cnaes, total, err := s.repo.Update(ctx, input.ID, input.Secao, input.Divisao, input.Grupo, input.Classe, input.Denominacao, input.Subclasse)
	if err != nil {
		return CnaeListResponse{}, err
	}

	return CnaeListResponse{Cnaes: cnaes, TotalRecords: total}, nil
}

func (s *CnaeService) Delete(ctx context.Context, id string) (CnaeListResponse, error) {
	cnaes, total, err := s.repo.Delete(ctx, id)
	if err != nil {
		return CnaeListResponse{}, err
	}

	return CnaeListResponse{Cnaes: cnaes, TotalRecords: total}, nil
}

func (s *CnaeService) Lite(ctx context.Context) (CnaeLiteResponse, error) {
	cnaes, err := s.repo.Lite(ctx)
	if err != nil {
		return CnaeLiteResponse{}, err
	}

	return CnaeLiteResponse{Cnaes: cnaes}, nil
}

func (s *CnaeService) Validate(ctx context.Context, cnae string) (CnaeValidateResponse, error) {
	cnaes, err := s.repo.Validate(ctx, cnae)
	if err != nil {
		return CnaeValidateResponse{}, err
	}

	return CnaeValidateResponse{Valid: len(cnaes) > 0}, nil
}

func (s *CnaeService) ResolveIbge(ctx context.Context, subclasse string) (CnaeIbgeResolveResponse, error) {
	return s.repo.ResolveIbge(ctx, subclasse)
}
