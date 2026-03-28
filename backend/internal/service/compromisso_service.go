package service

import (
	"context"

	"github.com/chayimamaral/vecontab/backend/internal/repository"
)

type CompromissoService struct {
	repo *repository.CompromissoRepository
}

// ── Response types ────────────────────────────────────────────────────────────

type CompromissoListResponse struct {
	Compromissos []repository.CompromissoListItem `json:"compromissos"`
	TotalRecords int64                            `json:"totalRecords"`
}

type CompromissoCreateResponse struct {
	CompromissoCriado []repository.CompromissoMutationItem `json:"compromissoCriado"`
	TotalRecords      int64                                `json:"totalRecords"`
}

type CompromissoUpdateResponse struct {
	Compromisso  []repository.CompromissoMutationItem `json:"compromisso"`
	TotalRecords int64                                `json:"totalRecords"`
}

type CompromissoDeleteResponse struct {
	Compromissos []repository.CompromissoMutationItem `json:"compromissos"`
	TotalRecords int64                                `json:"totalRecords"`
}

// ── Input ─────────────────────────────────────────────────────────────────────

type CompromissoInput struct {
	ID            string   `json:"id"`
	TipoEmpresaID string   `json:"tipo_empresa_id"`
	Natureza      string   `json:"natureza"`
	Descricao     string   `json:"descricao"`
	Periodicidade string   `json:"periodicidade"`
	Abrangencia   string   `json:"abrangencia"`
	Valor         *float64 `json:"valor"`
	Observacao    string   `json:"observacao"`
	EstadoID      string   `json:"estadoId"`
	MunicipioID   string   `json:"municipioId"`
	Bairro        string   `json:"bairro"`
}

// ── Constructor ───────────────────────────────────────────────────────────────

func NewCompromissoService(repo *repository.CompromissoRepository) *CompromissoService {
	return &CompromissoService{repo: repo}
}

// ── Methods ───────────────────────────────────────────────────────────────────

func (s *CompromissoService) List(ctx context.Context, params repository.CompromissoListParams) (CompromissoListResponse, error) {
	items, total, err := s.repo.List(ctx, params)
	if err != nil {
		return CompromissoListResponse{}, err
	}
	return CompromissoListResponse{Compromissos: items, TotalRecords: total}, nil
}

func (s *CompromissoService) Create(ctx context.Context, input CompromissoInput) (CompromissoCreateResponse, error) {
	items, total, err := s.repo.Create(ctx, repository.CompromissoUpsertInput{
		TipoEmpresaID: input.TipoEmpresaID,
		Natureza:      input.Natureza,
		Descricao:     input.Descricao,
		Periodicidade: input.Periodicidade,
		Abrangencia:   input.Abrangencia,
		Valor:         input.Valor,
		Observacao:    input.Observacao,
		EstadoID:      input.EstadoID,
		MunicipioID:   input.MunicipioID,
		Bairro:        input.Bairro,
	})
	if err != nil {
		return CompromissoCreateResponse{}, err
	}
	return CompromissoCreateResponse{CompromissoCriado: items, TotalRecords: total}, nil
}

func (s *CompromissoService) Update(ctx context.Context, input CompromissoInput) (CompromissoUpdateResponse, error) {
	items, total, err := s.repo.Update(ctx, repository.CompromissoUpsertInput{
		ID:            input.ID,
		TipoEmpresaID: input.TipoEmpresaID,
		Natureza:      input.Natureza,
		Descricao:     input.Descricao,
		Periodicidade: input.Periodicidade,
		Abrangencia:   input.Abrangencia,
		Valor:         input.Valor,
		Observacao:    input.Observacao,
		EstadoID:      input.EstadoID,
		MunicipioID:   input.MunicipioID,
		Bairro:        input.Bairro,
	})
	if err != nil {
		return CompromissoUpdateResponse{}, err
	}
	return CompromissoUpdateResponse{Compromisso: items, TotalRecords: total}, nil
}

func (s *CompromissoService) Delete(ctx context.Context, id string) (CompromissoDeleteResponse, error) {
	items, total, err := s.repo.Delete(ctx, id)
	if err != nil {
		return CompromissoDeleteResponse{}, err
	}
	return CompromissoDeleteResponse{Compromissos: items, TotalRecords: total}, nil
}
