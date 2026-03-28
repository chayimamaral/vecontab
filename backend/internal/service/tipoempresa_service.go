package service

import (
	"context"

	"github.com/chayimamaral/mare/backend/internal/repository"
)

type TipoEmpresaService struct {
	repo *repository.TipoEmpresaRepository
}

type TipoEmpresaListResponse struct {
	TiposEmpresa []repository.TipoEmpresa `json:"tiposEmpresa"`
	TotalRecords int64                    `json:"totalRecords"`
}

type TipoEmpresaLiteResponse struct {
	TiposEmpresa []repository.TipoEmpresaLiteItem `json:"tiposEmpresa"`
}

func NewTipoEmpresaService(repo *repository.TipoEmpresaRepository) *TipoEmpresaService {
	return &TipoEmpresaService{repo: repo}
}

func (s *TipoEmpresaService) List(ctx context.Context, params repository.TipoEmpresaListParams) (TipoEmpresaListResponse, error) {
	tipos, total, err := s.repo.List(ctx, params)
	if err != nil {
		return TipoEmpresaListResponse{}, err
	}

	return TipoEmpresaListResponse{TiposEmpresa: tipos, TotalRecords: total}, nil
}

func (s *TipoEmpresaService) Create(ctx context.Context, descricao string, capital, anual float64) (TipoEmpresaListResponse, error) {
	tipos, total, err := s.repo.Create(ctx, descricao, capital, anual)
	if err != nil {
		return TipoEmpresaListResponse{}, err
	}

	return TipoEmpresaListResponse{TiposEmpresa: tipos, TotalRecords: total}, nil
}

func (s *TipoEmpresaService) Update(ctx context.Context, id, descricao string, capital, anual float64) (TipoEmpresaListResponse, error) {
	tipos, total, err := s.repo.Update(ctx, id, descricao, capital, anual)
	if err != nil {
		return TipoEmpresaListResponse{}, err
	}

	return TipoEmpresaListResponse{TiposEmpresa: tipos, TotalRecords: total}, nil
}

func (s *TipoEmpresaService) Delete(ctx context.Context, id string) (TipoEmpresaListResponse, error) {
	tipos, total, err := s.repo.Delete(ctx, id)
	if err != nil {
		return TipoEmpresaListResponse{}, err
	}

	return TipoEmpresaListResponse{TiposEmpresa: tipos, TotalRecords: total}, nil
}

func (s *TipoEmpresaService) Lite(ctx context.Context) (TipoEmpresaLiteResponse, error) {
	tipos, err := s.repo.Lite(ctx)
	if err != nil {
		return TipoEmpresaLiteResponse{}, err
	}

	return TipoEmpresaLiteResponse{TiposEmpresa: tipos}, nil
}
