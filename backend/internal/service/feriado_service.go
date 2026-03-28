package service

import (
	"context"

	"github.com/chayimamaral/mare/backend/internal/repository"
)

type FeriadoService struct {
	repo *repository.FeriadoRepository
}

type FeriadoListResponse struct {
	Feriados     []repository.FeriadoListItem `json:"feriados"`
	TotalRecords int64                        `json:"totalRecords"`
}

type FeriadoCreateResponse struct {
	FeriadoCriado []repository.FeriadoMutationItem `json:"feriadoCriado"`
	TotalRecords  int64                            `json:"totalRecords"`
}

type FeriadoUpdateResponse struct {
	Feriado      []repository.FeriadoMutationItem `json:"feriado"`
	TotalRecords int64                            `json:"totalRecords"`
}

type FeriadoDeleteResponse struct {
	Feriados     []repository.FeriadoMutationItem `json:"feriados"`
	TotalRecords int64                            `json:"totalRecords"`
}

type FeriadoInput struct {
	ID          string `json:"id"`
	Descricao   string `json:"descricao"`
	Data        string `json:"data"`
	HolidayCode string `json:"holidayCode"`
	MunicipioID string `json:"municipioId"`
	EstadoID    string `json:"estadoId"`
}

func NewFeriadoService(repo *repository.FeriadoRepository) *FeriadoService {
	return &FeriadoService{repo: repo}
}

func (s *FeriadoService) List(ctx context.Context, params repository.FeriadoListParams) (FeriadoListResponse, error) {
	feriados, total, err := s.repo.List(ctx, params)
	if err != nil {
		return FeriadoListResponse{}, err
	}

	return FeriadoListResponse{Feriados: feriados, TotalRecords: total}, nil
}

func (s *FeriadoService) Create(ctx context.Context, input FeriadoInput) (FeriadoCreateResponse, error) {
	feriados, total, err := s.repo.Create(ctx, repository.FeriadoUpsertInput{
		Descricao:   input.Descricao,
		Data:        input.Data,
		HolidayCode: input.HolidayCode,
		MunicipioID: input.MunicipioID,
		EstadoID:    input.EstadoID,
	})
	if err != nil {
		return FeriadoCreateResponse{}, err
	}

	return FeriadoCreateResponse{FeriadoCriado: feriados, TotalRecords: total}, nil
}

func (s *FeriadoService) Update(ctx context.Context, input FeriadoInput) (FeriadoUpdateResponse, error) {
	feriados, total, err := s.repo.Update(ctx, repository.FeriadoUpsertInput{
		ID:          input.ID,
		Descricao:   input.Descricao,
		Data:        input.Data,
		HolidayCode: input.HolidayCode,
		MunicipioID: input.MunicipioID,
		EstadoID:    input.EstadoID,
	})
	if err != nil {
		return FeriadoUpdateResponse{}, err
	}

	return FeriadoUpdateResponse{Feriado: feriados, TotalRecords: total}, nil
}

func (s *FeriadoService) Delete(ctx context.Context, id string) (FeriadoDeleteResponse, error) {
	feriados, total, err := s.repo.Delete(ctx, id)
	if err != nil {
		return FeriadoDeleteResponse{}, err
	}

	return FeriadoDeleteResponse{Feriados: feriados, TotalRecords: total}, nil
}
