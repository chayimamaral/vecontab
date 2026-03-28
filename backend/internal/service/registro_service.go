package service

import (
	"context"

	"github.com/chayimamaral/mare/backend/internal/repository"
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

func NewRegistroService(repo *repository.RegistroRepository) *RegistroService {
	return &RegistroService{repo: repo}
}

func (s *RegistroService) Detail(ctx context.Context, tenantID string) (repository.DadosComplementaresRecord, error) {
	return s.repo.DetailByTenant(ctx, tenantID)
}

func (s *RegistroService) Update(ctx context.Context, userID string, input RegistroUpdateInput) (repository.DadosComplementaresRecord, error) {
	return s.repo.UpdateByUser(ctx, userID, repository.RegistroUpdateInput{
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
}

func (s *RegistroService) Create(ctx context.Context, input RegistroCreateInput) (repository.RegistroUserRecord, error) {
	passwordHash, err := bcrypt.GenerateFromPassword([]byte(input.Password), 8)
	if err != nil {
		return repository.RegistroUserRecord{}, err
	}

	return s.repo.Create(ctx, repository.RegistroCreateInput{
		Nome:     input.Nome,
		Email:    input.Email,
		Password: string(passwordHash),
	})
}
