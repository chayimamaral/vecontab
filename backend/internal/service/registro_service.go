package service

import (
	"context"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/chayimamaral/vecontab/backend/internal/repository"
	"golang.org/x/crypto/bcrypt"
)

type RegistroCreateInput struct {
	Nome     string `json:"nome"`
	Email    string `json:"email"`
	Password string `json:"password"`
}

type RegistroUpdateInput struct {
	CNPJ        string `json:"cnpj"`
	CEP         string `json:"cep"`
	Endereco    string `json:"endereco"`
	Bairro      string `json:"bairro"`
	Cidade      string `json:"cidade"`
	Estado      string `json:"estado"`
	Telefone    string `json:"telefone"`
	Email       string `json:"email"`
	IE          string `json:"ie"`
	IM          string `json:"im"`
	RazaoSocial string `json:"razaosocial"`
	Fantasia    string `json:"fantasia"`
	Observacoes string `json:"observacoes"`
}

type RegistroService struct {
	repo *repository.RegistroRepository
}

type DadosComplementaresResponse struct {
	Tenantid    string `json:"tenantid"`
	CNPJ        string `json:"cnpj"`
	CEP         string `json:"cep"`
	Endereco    string `json:"endereco"`
	Bairro      string `json:"bairro"`
	Cidade      string `json:"cidade"`
	Estado      string `json:"estado"`
	Telefone    string `json:"telefone"`
	Email       string `json:"email"`
	IE          string `json:"ie"`
	IM          string `json:"im"`
	RazaoSocial string `json:"razaosocial"`
	Fantasia    string `json:"fantasia"`
	Observacoes string `json:"observacoes"`
}

func NewRegistroService(repo *repository.RegistroRepository) *RegistroService {
	return &RegistroService{repo: repo}
}

func (s *RegistroService) Detail(ctx context.Context, tenantID string) (DadosComplementaresResponse, error) {
	record, err := s.repo.DetailByTenant(ctx, tenantID)
	if err != nil {
		return DadosComplementaresResponse{}, err
	}
	return mapDadosComplementares(record), nil
}

func (s *RegistroService) UpdateByTenantID(ctx context.Context, tenantID string, input RegistroUpdateInput) (DadosComplementaresResponse, error) {
	record, err := s.repo.UpdateByTenantID(ctx, tenantID, repository.RegistroUpdateInput{
		CNPJ:        input.CNPJ,
		CEP:         input.CEP,
		Endereco:    input.Endereco,
		Bairro:      input.Bairro,
		Cidade:      input.Cidade,
		Estado:      input.Estado,
		Telefone:    input.Telefone,
		Email:       input.Email,
		IE:          input.IE,
		IM:          input.IM,
		RazaoSocial: input.RazaoSocial,
		Fantasia:    input.Fantasia,
		Observacoes: input.Observacoes,
	})
	if err != nil {
		return DadosComplementaresResponse{}, err
	}
	return mapDadosComplementares(record), nil
}

func (s *RegistroService) Update(ctx context.Context, userID string, input RegistroUpdateInput) (DadosComplementaresResponse, error) {
	record, err := s.repo.UpdateByUser(ctx, userID, repository.RegistroUpdateInput{
		CNPJ:        input.CNPJ,
		CEP:         input.CEP,
		Endereco:    input.Endereco,
		Bairro:      input.Bairro,
		Cidade:      input.Cidade,
		Estado:      input.Estado,
		Telefone:    input.Telefone,
		Email:       input.Email,
		IE:          input.IE,
		IM:          input.IM,
		RazaoSocial: input.RazaoSocial,
		Fantasia:    input.Fantasia,
		Observacoes: input.Observacoes,
	})
	if err != nil {
		return DadosComplementaresResponse{}, err
	}
	return mapDadosComplementares(record), nil
}

func (s *RegistroService) Create(ctx context.Context, input RegistroCreateInput) (domain.RegistroUserRecord, error) {
	passwordHash, err := bcrypt.GenerateFromPassword([]byte(input.Password), 8)
	if err != nil {
		return domain.RegistroUserRecord{}, err
	}

	return s.repo.Create(ctx, repository.RegistroCreateInput{
		Nome:     input.Nome,
		Email:    input.Email,
		Password: string(passwordHash),
	})
}

func mapDadosComplementares(r domain.DadosComplementaresRecord) DadosComplementaresResponse {
	ptrToStr := func(p *string) string {
		if p == nil {
			return ""
		}
		return *p
	}
	return DadosComplementaresResponse{
		Tenantid:    r.Tenantid,
		CNPJ:        ptrToStr(r.CNPJ),
		CEP:         ptrToStr(r.CEP),
		Endereco:    ptrToStr(r.Endereco),
		Bairro:      ptrToStr(r.Bairro),
		Cidade:      ptrToStr(r.Cidade),
		Estado:      ptrToStr(r.Estado),
		Telefone:    ptrToStr(r.Telefone),
		Email:       ptrToStr(r.Email),
		IE:          ptrToStr(r.IE),
		IM:          ptrToStr(r.IM),
		RazaoSocial: ptrToStr(r.RazaoSocial),
		Fantasia:    ptrToStr(r.Fantasia),
		Observacoes: ptrToStr(r.Observacoes),
	}
}
