package service

import (
	"context"

	"github.com/chayimamaral/vecontab/backend/internal/repository"
)

type RotinaService struct {
	repo *repository.RotinaRepository
}

type RotinaListResponse struct {
	Rotinas      any   `json:"rotinas"`
	TotalRecords int64 `json:"totalRecords"`
}

type RotinaItensResponse struct {
	RotinaItens  any   `json:"rotinasitens"`
	TotalRecords int64 `json:"totalRecords"`
}

type RotinaPassosResponse struct {
	Passos       any   `json:"passos"`
	TotalRecords int64 `json:"totalRecords"`
}

type RotinaSuccessResponse struct {
	Success bool `json:"success"`
}

type RotinaInput struct {
	ID            string `json:"id"`
	Descricao     string `json:"descricao"`
	CidadeID      string `json:"cidade_id"`
	Link          string `json:"link"`
	TempoEstimado int    `json:"tempoestimado"`
}

func NewRotinaService(repo *repository.RotinaRepository) *RotinaService {
	return &RotinaService{repo: repo}
}

func (s *RotinaService) List(ctx context.Context, params repository.RotinaListParams) (RotinaListResponse, error) {
	rotinas, total, err := s.repo.List(ctx, params)
	if err != nil {
		return RotinaListResponse{}, err
	}
	return RotinaListResponse{Rotinas: rotinas, TotalRecords: total}, nil
}

// ListRotinas atende a grade /listrotinas: usa a mesma consulta paginada de List (uma linha por rotina).
// ListWithItens fazia JOIN com passos e era mais complexa; a tela carrega passos via endpoints dedicados.
func (s *RotinaService) ListRotinas(ctx context.Context, params repository.RotinaListParams) (RotinaListResponse, error) {
	rotinas, total, err := s.repo.List(ctx, params)
	if err != nil {
		return RotinaListResponse{}, err
	}
	out := make([]repository.RotinaWithItensItem, 0, len(rotinas))
	for _, r := range rotinas {
		out = append(out, repository.RotinaWithItensItem{
			ID:          r.ID,
			Descricao:   r.Descricao,
			MunicipioID: r.MunicipioID,
			Municipio:   r.Municipio,
			RotinaItens: []repository.RotinaPassoItem{},
		})
	}
	return RotinaListResponse{Rotinas: out, TotalRecords: total}, nil
}

func (s *RotinaService) ListLite(ctx context.Context, municipioID string) (RotinaListResponse, error) {
	rotinas, total, err := s.repo.ListLite(ctx, municipioID)
	if err != nil {
		return RotinaListResponse{}, err
	}
	return RotinaListResponse{Rotinas: rotinas, TotalRecords: total}, nil
}

func (s *RotinaService) Create(ctx context.Context, input RotinaInput) (RotinaListResponse, error) {
	rotinas, total, err := s.repo.Create(ctx, repository.RotinaInput{
		Descricao:   input.Descricao,
		MunicipioID: input.CidadeID,
		Link:        input.Link,
	})
	if err != nil {
		return RotinaListResponse{}, err
	}
	return RotinaListResponse{Rotinas: rotinas, TotalRecords: total}, nil
}

func (s *RotinaService) Update(ctx context.Context, input RotinaInput) (RotinaListResponse, error) {
	rotinas, total, err := s.repo.Update(ctx, repository.RotinaInput{
		ID:          input.ID,
		Descricao:   input.Descricao,
		MunicipioID: input.CidadeID,
		Link:        input.Link,
	})
	if err != nil {
		return RotinaListResponse{}, err
	}
	return RotinaListResponse{Rotinas: rotinas, TotalRecords: total}, nil
}

func (s *RotinaService) Delete(ctx context.Context, id string) (RotinaListResponse, error) {
	rotinas, total, err := s.repo.Delete(ctx, id)
	if err != nil {
		return RotinaListResponse{}, err
	}
	return RotinaListResponse{Rotinas: rotinas, TotalRecords: total}, nil
}

func (s *RotinaService) RotinaItens(ctx context.Context, id string) (RotinaItensResponse, error) {
	itens, total, err := s.repo.RotinaItens(ctx, id)
	if err != nil {
		return RotinaItensResponse{}, err
	}
	return RotinaItensResponse{RotinaItens: itens, TotalRecords: total}, nil
}

func (s *RotinaService) RotinaItemCreate(ctx context.Context, rotinaID, descricao string, tempoestimado int, link string) (RotinaItensResponse, error) {
	itens, total, err := s.repo.RotinaItemCreate(ctx, rotinaID, descricao, tempoestimado, link)
	if err != nil {
		return RotinaItensResponse{}, err
	}
	return RotinaItensResponse{RotinaItens: itens, TotalRecords: total}, nil
}

func (s *RotinaService) RotinaItemUpdate(ctx context.Context, id, descricao string, tempoestimado int, link string) (RotinaItensResponse, error) {
	itens, total, err := s.repo.RotinaItemUpdate(ctx, id, descricao, tempoestimado, link)
	if err != nil {
		return RotinaItensResponse{}, err
	}
	return RotinaItensResponse{RotinaItens: itens, TotalRecords: total}, nil
}

func (s *RotinaService) RotinaItemDelete(ctx context.Context, id string) (RotinaItensResponse, error) {
	itens, total, err := s.repo.RotinaItemDelete(ctx, id)
	if err != nil {
		return RotinaItensResponse{}, err
	}
	return RotinaItensResponse{RotinaItens: itens, TotalRecords: total}, nil
}

func (s *RotinaService) ListSelectedItens(ctx context.Context, rotinaID string) (RotinaPassosResponse, error) {
	passos, total, err := s.repo.ListSelectedItens(ctx, rotinaID)
	if err != nil {
		return RotinaPassosResponse{}, err
	}
	return RotinaPassosResponse{Passos: passos, TotalRecords: total}, nil
}

func (s *RotinaService) SaveSelectedItens(ctx context.Context, selections []repository.RotinaPassoSelection) (RotinaSuccessResponse, error) {
	if err := s.repo.SaveSelectedItens(ctx, selections); err != nil {
		return RotinaSuccessResponse{}, err
	}
	return RotinaSuccessResponse{Success: true}, nil
}

func (s *RotinaService) RemoveSelectedItens(ctx context.Context, selections []repository.RotinaPassoSelection) (RotinaSuccessResponse, error) {
	if err := s.repo.RemoveSelectedItens(ctx, selections); err != nil {
		return RotinaSuccessResponse{}, err
	}
	return RotinaSuccessResponse{Success: true}, nil
}
