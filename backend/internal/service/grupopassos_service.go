package service

import (
	"context"

	"github.com/chayimamaral/mare/backend/internal/repository"
)

type GrupoPassosService struct {
	repo *repository.GrupoPassosRepository
}

type GrupoPassosListResponse struct {
	GrupoPassos  []repository.GrupoPassosListItem `json:"grupopassos"`
	TotalRecords int64                            `json:"totalRecords"`
}

type GrupoPassosMutationResponse struct {
	GrupoPassos  []repository.GrupoPassosMutationItem `json:"grupopassos"`
	TotalRecords int64                                `json:"totalRecords"`
}

type GrupoPassosInput struct {
	ID            string `json:"id"`
	Descricao     string `json:"descricao"`
	MunicipioID   string `json:"municipio_id"`
	TipoEmpresaID string `json:"tipoempresa_id"`
}

func NewGrupoPassosService(repo *repository.GrupoPassosRepository) *GrupoPassosService {
	return &GrupoPassosService{repo: repo}
}

func (s *GrupoPassosService) List(ctx context.Context, params repository.GrupoPassosListParams) (GrupoPassosListResponse, error) {
	grupos, total, err := s.repo.List(ctx, params)
	if err != nil {
		return GrupoPassosListResponse{}, err
	}

	return GrupoPassosListResponse{GrupoPassos: grupos, TotalRecords: total}, nil
}

func (s *GrupoPassosService) Create(ctx context.Context, input GrupoPassosInput) (GrupoPassosMutationResponse, error) {
	grupos, total, err := s.repo.Create(ctx, input.Descricao, input.MunicipioID, input.TipoEmpresaID)
	if err != nil {
		return GrupoPassosMutationResponse{}, err
	}

	return GrupoPassosMutationResponse{GrupoPassos: grupos, TotalRecords: total}, nil
}

func (s *GrupoPassosService) Update(ctx context.Context, input GrupoPassosInput) (GrupoPassosMutationResponse, error) {
	grupos, total, err := s.repo.Update(ctx, input.ID, input.Descricao, input.MunicipioID, input.TipoEmpresaID)
	if err != nil {
		return GrupoPassosMutationResponse{}, err
	}

	return GrupoPassosMutationResponse{GrupoPassos: grupos, TotalRecords: total}, nil
}

func (s *GrupoPassosService) Delete(ctx context.Context, id string) (GrupoPassosMutationResponse, error) {
	grupos, total, err := s.repo.Delete(ctx, id)
	if err != nil {
		return GrupoPassosMutationResponse{}, err
	}

	return GrupoPassosMutationResponse{GrupoPassos: grupos, TotalRecords: total}, nil
}

func (s *GrupoPassosService) GetByID(ctx context.Context, id string) (GrupoPassosMutationResponse, error) {
	grupos, total, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return GrupoPassosMutationResponse{}, err
	}

	return GrupoPassosMutationResponse{GrupoPassos: grupos, TotalRecords: total}, nil
}
