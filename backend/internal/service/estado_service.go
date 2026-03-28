package service

import (
	"context"

	"github.com/chayimamaral/mare/backend/internal/repository"
)

type EstadoService struct {
	repo *repository.EstadoRepository
}

type EstadoListResponse struct {
	Estados      []repository.Estado `json:"estados"`
	TotalRecords int64               `json:"totalRecords"`
}

type EstadoLiteResponse struct {
	Estados []repository.Estado `json:"estados"`
}

func NewEstadoService(repo *repository.EstadoRepository) *EstadoService {
	return &EstadoService{repo: repo}
}

func (s *EstadoService) List(ctx context.Context, params repository.EstadoListParams) (EstadoListResponse, error) {
	estados, total, err := s.repo.List(ctx, params)
	if err != nil {
		return EstadoListResponse{}, err
	}

	return EstadoListResponse{Estados: estados, TotalRecords: total}, nil
}

func (s *EstadoService) Create(ctx context.Context, nome, sigla string) (EstadoListResponse, error) {
	estados, total, err := s.repo.Create(ctx, nome, sigla)
	if err != nil {
		return EstadoListResponse{}, err
	}

	return EstadoListResponse{Estados: estados, TotalRecords: total}, nil
}

func (s *EstadoService) Update(ctx context.Context, id, nome, sigla string) (EstadoListResponse, error) {
	estados, total, err := s.repo.Update(ctx, id, nome, sigla)
	if err != nil {
		return EstadoListResponse{}, err
	}

	return EstadoListResponse{Estados: estados, TotalRecords: total}, nil
}

func (s *EstadoService) Delete(ctx context.Context, id string) (EstadoListResponse, error) {
	estados, total, err := s.repo.Delete(ctx, id)
	if err != nil {
		return EstadoListResponse{}, err
	}

	return EstadoListResponse{Estados: estados, TotalRecords: total}, nil
}

func (s *EstadoService) ListLite(ctx context.Context) (EstadoLiteResponse, error) {
	estados, err := s.repo.ListLite(ctx)
	if err != nil {
		return EstadoLiteResponse{}, err
	}

	return EstadoLiteResponse{Estados: estados}, nil
}
