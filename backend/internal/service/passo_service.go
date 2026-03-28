package service

import (
	"context"

	"github.com/chayimamaral/mare/backend/internal/repository"
)

type PassoService struct {
	repo *repository.PassoRepository
}

type PassoListResponse struct {
	Passos       []repository.PassoListItem `json:"passos"`
	TotalRecords int64                      `json:"totalRecords"`
}

type PassoMutationResponse struct {
	Passos       []repository.PassoMutationItem `json:"passos"`
	TotalRecords int64                          `json:"totalRecords"`
}

type PassoDetailResponse struct {
	Passos       []repository.PassoDetailItem `json:"passos"`
	TotalRecords int64                        `json:"totalRecords"`
}

type PassoCidadeResponse struct {
	Passos       []repository.PassoCidadeItem `json:"passos"`
	TotalRecords int64                        `json:"totalRecords"`
}

type PassoCreateInput struct {
	Descricao   string `json:"descricao"`
	Tempo       int    `json:"tempoestimado"`
	TipoPasso   string `json:"tipopasso"`
	MunicipioID string `json:"municipio_id"`
	Link        string `json:"link"`
}

type PassoUpdateInput struct {
	ID          string `json:"id"`
	Descricao   string `json:"descricao"`
	Tempo       int    `json:"tempoestimado"`
	TipoPasso   string `json:"tipopasso"`
	MunicipioID string `json:"municipio_id"`
	Link        string `json:"link"`
}

func NewPassoService(repo *repository.PassoRepository) *PassoService {
	return &PassoService{repo: repo}
}

func (s *PassoService) List(ctx context.Context, params repository.PassoListParams) (PassoListResponse, error) {
	passos, total, err := s.repo.List(ctx, params)
	if err != nil {
		return PassoListResponse{}, err
	}

	return PassoListResponse{Passos: passos, TotalRecords: total}, nil
}

func (s *PassoService) Create(ctx context.Context, input PassoCreateInput) (PassoMutationResponse, error) {
	passos, total, err := s.repo.Create(ctx, input.Descricao, input.Tempo, input.TipoPasso, input.MunicipioID, input.Link)
	if err != nil {
		return PassoMutationResponse{}, err
	}

	return PassoMutationResponse{Passos: passos, TotalRecords: total}, nil
}

func (s *PassoService) Update(ctx context.Context, input PassoUpdateInput) (PassoMutationResponse, error) {
	passos, total, err := s.repo.Update(ctx, input.ID, input.Descricao, input.Tempo, input.TipoPasso, input.MunicipioID, input.Link)
	if err != nil {
		return PassoMutationResponse{}, err
	}

	return PassoMutationResponse{Passos: passos, TotalRecords: total}, nil
}

func (s *PassoService) Delete(ctx context.Context, id string) (PassoMutationResponse, error) {
	passos, total, err := s.repo.Delete(ctx, id)
	if err != nil {
		return PassoMutationResponse{}, err
	}

	return PassoMutationResponse{Passos: passos, TotalRecords: total}, nil
}

func (s *PassoService) GetByID(ctx context.Context, id string) (PassoDetailResponse, error) {
	passos, total, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return PassoDetailResponse{}, err
	}

	return PassoDetailResponse{Passos: passos, TotalRecords: total}, nil
}

func (s *PassoService) ListByCidade(ctx context.Context, municipioID, rotinaID string) (PassoCidadeResponse, error) {
	passos, total, err := s.repo.ListByCidade(ctx, repository.PassoCidadeParams{MunicipioID: municipioID, RotinaID: rotinaID})
	if err != nil {
		return PassoCidadeResponse{}, err
	}

	return PassoCidadeResponse{Passos: passos, TotalRecords: total}, nil
}
