package service

import (
	"context"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/chayimamaral/vecontab/backend/internal/repository"
)

type EmpresaService struct {
	repo *repository.EmpresaRepository
}

type EmpresaListResponse struct {
	Empresas     []domain.EmpresaListItem `json:"empresas"`
	TotalRecords int64                        `json:"totalRecords"`
}

type EmpresaMutationResponse struct {
	Empresas     []domain.EmpresaMutationItem `json:"empresas"`
	TotalRecords int64                            `json:"totalRecords"`
}

type EmpresaInput struct {
	ID         string `json:"id"`
	Nome       string `json:"nome"`
	TenantID   string `json:"tenantid"`
	RotinaID   string `json:"rotina_id"`
	Cnaes      any    `json:"cnaes"`
	Bairro     string `json:"bairro"`
	TipoPessoa string `json:"tipo_pessoa"`
	Documento  string `json:"documento"`
}

func NewEmpresaService(repo *repository.EmpresaRepository) *EmpresaService {
	return &EmpresaService{repo: repo}
}

func (s *EmpresaService) List(ctx context.Context, params repository.EmpresaListParams) (EmpresaListResponse, error) {
	empresas, total, err := s.repo.List(ctx, params)
	if err != nil {
		return EmpresaListResponse{}, err
	}

	return EmpresaListResponse{Empresas: empresas, TotalRecords: total}, nil
}

func (s *EmpresaService) Create(ctx context.Context, input EmpresaInput) (EmpresaMutationResponse, error) {
	empresas, total, err := s.repo.Create(ctx, repository.EmpresaUpsertInput{
		Nome:       input.Nome,
		TenantID:   input.TenantID,
		RotinaID:   input.RotinaID,
		Cnaes:      input.Cnaes,
		Bairro:     input.Bairro,
		TipoPessoa: input.TipoPessoa,
		Documento:  input.Documento,
	})
	if err != nil {
		return EmpresaMutationResponse{}, err
	}

	return EmpresaMutationResponse{Empresas: empresas, TotalRecords: total}, nil
}

func (s *EmpresaService) Update(ctx context.Context, input EmpresaInput) (EmpresaMutationResponse, error) {
	empresas, total, err := s.repo.Update(ctx, repository.EmpresaUpsertInput{
		ID:         input.ID,
		Nome:       input.Nome,
		TenantID:   input.TenantID,
		RotinaID:   input.RotinaID,
		Cnaes:      input.Cnaes,
		Bairro:     input.Bairro,
		TipoPessoa: input.TipoPessoa,
		Documento:  input.Documento,
	})
	if err != nil {
		return EmpresaMutationResponse{}, err
	}

	return EmpresaMutationResponse{Empresas: empresas, TotalRecords: total}, nil
}

func (s *EmpresaService) IniciarProcesso(ctx context.Context, id, tenantID string) (EmpresaMutationResponse, error) {
	empresas, total, err := s.repo.IniciarProcesso(ctx, id, tenantID)
	if err != nil {
		return EmpresaMutationResponse{}, err
	}

	return EmpresaMutationResponse{Empresas: empresas, TotalRecords: total}, nil
}

func (s *EmpresaService) Delete(ctx context.Context, id, tenantID string) (EmpresaMutationResponse, error) {
	empresas, total, err := s.repo.Delete(ctx, id, tenantID)
	if err != nil {
		return EmpresaMutationResponse{}, err
	}

	return EmpresaMutationResponse{Empresas: empresas, TotalRecords: total}, nil
}
