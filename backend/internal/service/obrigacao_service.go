package service

import (
	"context"
	"strconv"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/repository"
)

type ObrigacaoService struct {
	repo *repository.ObrigacaoRepository
}

type ObrigacaoListResponse struct {
	Obrigacoes   []repository.ObrigacaoListItem `json:"obrigacoes"`
	TotalRecords int64                          `json:"totalRecords"`
}

type ObrigacaoCreateResponse struct {
	ObrigacaoCriado []repository.ObrigacaoMutationItem `json:"obrigacaoCriado"`
	TotalRecords    int64                              `json:"totalRecords"`
}

type ObrigacaoUpdateResponse struct {
	Obrigacao    []repository.ObrigacaoMutationItem `json:"obrigacao"`
	TotalRecords int64                              `json:"totalRecords"`
}

type ObrigacaoDeleteResponse struct {
	Obrigacoes   []repository.ObrigacaoMutationItem `json:"obrigacoes"`
	TotalRecords int64                              `json:"totalRecords"`
}

type ObrigacaoInput struct {
	ID                string   `json:"id"`
	TipoEmpresaID     string   `json:"tipo_empresa_id"`
	TipoClassificacao string   `json:"tipo_classificacao"`
	Descricao         string   `json:"descricao"`
	Periodicidade     string   `json:"periodicidade"`
	Abrangencia       string   `json:"abrangencia"`
	DiaBase           int      `json:"dia_base"`
	MesBase           string   `json:"mes_base"`
	Valor             *float64 `json:"valor"`
	Observacao        string   `json:"observacao"`
	EstadoID          string   `json:"estadoId"`
	MunicipioID       string   `json:"municipioId"`
	Bairro            string   `json:"bairro"`
}

func NewObrigacaoService(repo *repository.ObrigacaoRepository) *ObrigacaoService {
	return &ObrigacaoService{repo: repo}
}

func (s *ObrigacaoService) List(ctx context.Context, params repository.ObrigacaoListParams) (ObrigacaoListResponse, error) {
	items, total, err := s.repo.List(ctx, params)
	if err != nil {
		return ObrigacaoListResponse{}, err
	}
	return ObrigacaoListResponse{Obrigacoes: items, TotalRecords: total}, nil
}

func (s *ObrigacaoService) Create(ctx context.Context, input ObrigacaoInput) (ObrigacaoCreateResponse, error) {
	items, total, err := s.repo.Create(ctx, toUpsert(input))
	if err != nil {
		return ObrigacaoCreateResponse{}, err
	}
	return ObrigacaoCreateResponse{ObrigacaoCriado: items, TotalRecords: total}, nil
}

func (s *ObrigacaoService) Update(ctx context.Context, input ObrigacaoInput) (ObrigacaoUpdateResponse, error) {
	items, total, err := s.repo.Update(ctx, toUpsert(input))
	if err != nil {
		return ObrigacaoUpdateResponse{}, err
	}
	return ObrigacaoUpdateResponse{Obrigacao: items, TotalRecords: total}, nil
}

func (s *ObrigacaoService) Delete(ctx context.Context, id string) (ObrigacaoDeleteResponse, error) {
	items, total, err := s.repo.Delete(ctx, id)
	if err != nil {
		return ObrigacaoDeleteResponse{}, err
	}
	return ObrigacaoDeleteResponse{Obrigacoes: items, TotalRecords: total}, nil
}

func toUpsert(input ObrigacaoInput) repository.ObrigacaoUpsertInput {
	return repository.ObrigacaoUpsertInput{
		ID:                input.ID,
		TipoEmpresaID:     input.TipoEmpresaID,
		TipoClassificacao: input.TipoClassificacao,
		Descricao:         input.Descricao,
		Periodicidade:     input.Periodicidade,
		Abrangencia:       input.Abrangencia,
		DiaBase:           input.DiaBase,
		MesBase:           strings.TrimSpace(input.MesBase),
		Valor:             input.Valor,
		Observacao:        input.Observacao,
		EstadoID:          input.EstadoID,
		MunicipioID:       input.MunicipioID,
		Bairro:            input.Bairro,
	}
}

// MesBaseFromAny aceita string ou número no JSON legado.
func MesBaseFromAny(v any) string {
	if v == nil {
		return ""
	}
	switch t := v.(type) {
	case string:
		return strings.TrimSpace(t)
	case float64:
		if t == 0 {
			return ""
		}
		return strconv.Itoa(int(t))
	default:
		return ""
	}
}
