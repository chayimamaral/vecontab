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
	TotalRecords int64                    `json:"totalRecords"`
}

type EmpresaMutationResponse struct {
	Empresas     []domain.EmpresaMutationItem `json:"empresas"`
	TotalRecords int64                        `json:"totalRecords"`
}

type EmpresaProcessoResponse struct {
	Processos    []domain.EmpresaProcessoItem `json:"processos"`
	TotalRecords int64                        `json:"totalRecords"`
}

type EmpresaInput struct {
	ID                 string `json:"id"`
	Nome               string `json:"nome"`
	TenantID           string `json:"tenantid"`
	MunicipioID        string `json:"municipio_id"`
	RotinaID           string `json:"rotina_id"`
	RotinaPFID         string `json:"rotina_pf_id"`
	Cnaes              any    `json:"cnaes"`
	Bairro             string `json:"bairro"`
	TipoPessoa         string `json:"tipo_pessoa"`
	Documento          string `json:"documento"`
	IE                 string `json:"ie"`
	IM                 string `json:"im"`
	RegimeTributarioID string `json:"regime_tributario_id"`
	TipoEmpresaID      string `json:"tipo_empresa_id"`
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
		Nome:               input.Nome,
		TenantID:           input.TenantID,
		MunicipioID:        input.MunicipioID,
		RotinaID:           input.RotinaID,
		RotinaPFID:         input.RotinaPFID,
		Cnaes:              input.Cnaes,
		Bairro:             input.Bairro,
		TipoPessoa:         input.TipoPessoa,
		Documento:          input.Documento,
		IE:                 input.IE,
		IM:                 input.IM,
		RegimeTributarioID: input.RegimeTributarioID,
		TipoEmpresaID:      input.TipoEmpresaID,
	})
	if err != nil {
		return EmpresaMutationResponse{}, err
	}

	return EmpresaMutationResponse{Empresas: empresas, TotalRecords: total}, nil
}

func (s *EmpresaService) Update(ctx context.Context, input EmpresaInput) (EmpresaMutationResponse, error) {
	empresas, total, err := s.repo.Update(ctx, repository.EmpresaUpsertInput{
		ID:                 input.ID,
		Nome:               input.Nome,
		TenantID:           input.TenantID,
		MunicipioID:        input.MunicipioID,
		RotinaID:           input.RotinaID,
		RotinaPFID:         input.RotinaPFID,
		Cnaes:              input.Cnaes,
		Bairro:             input.Bairro,
		TipoPessoa:         input.TipoPessoa,
		Documento:          input.Documento,
		IE:                 input.IE,
		IM:                 input.IM,
		RegimeTributarioID: input.RegimeTributarioID,
		TipoEmpresaID:      input.TipoEmpresaID,
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

func (s *EmpresaService) ListProcessos(ctx context.Context, empresaID, tenantID string) (EmpresaProcessoResponse, error) {
	processos, total, err := s.repo.ListProcessos(ctx, empresaID, tenantID)
	if err != nil {
		return EmpresaProcessoResponse{}, err
	}
	return EmpresaProcessoResponse{Processos: processos, TotalRecords: total}, nil
}

func (s *EmpresaService) CreateProcesso(ctx context.Context, input repository.EmpresaProcessoInput) (EmpresaProcessoResponse, error) {
	processos, total, err := s.repo.CreateProcesso(ctx, input)
	if err != nil {
		return EmpresaProcessoResponse{}, err
	}
	return EmpresaProcessoResponse{Processos: processos, TotalRecords: total}, nil
}

func (s *EmpresaService) IniciarProcessoFilho(ctx context.Context, processoID, tenantID string) (EmpresaProcessoResponse, error) {
	processos, total, err := s.repo.IniciarProcessoFilho(ctx, processoID, tenantID)
	if err != nil {
		return EmpresaProcessoResponse{}, err
	}
	return EmpresaProcessoResponse{Processos: processos, TotalRecords: total}, nil
}

func (s *EmpresaService) MarcarCompromissosProcesso(ctx context.Context, processoID, tenantID string) (EmpresaProcessoResponse, error) {
	processos, total, err := s.repo.MarcarCompromissosProcesso(ctx, processoID, tenantID)
	if err != nil {
		return EmpresaProcessoResponse{}, err
	}
	return EmpresaProcessoResponse{Processos: processos, TotalRecords: total}, nil
}
