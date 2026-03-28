package service

import (
	"context"
	"fmt"
	"time"

	"github.com/chayimamaral/mare/backend/internal/repository"
)

type EmpresaAgendaService struct {
	agendaRepo  *repository.EmpresaAgendaRepository
	feriadoRepo *repository.FeriadoRepository
	empresaRepo *repository.EmpresaRepository
}

type EmpresaAgendaListResponse struct {
	Itens []repository.EmpresaAgendaItem `json:"itens"`
}

type EmpresaAgendaGerarResponse struct {
	Itens   []repository.EmpresaAgendaItem `json:"itens"`
	Message string                         `json:"message"`
}

type EmpresaAgendaAcompanhamentoResponse struct {
	Itens []repository.EmpresaAgendaAcompanhamentoItem `json:"itens"`
}

func NewEmpresaAgendaService(
	agendaRepo *repository.EmpresaAgendaRepository,
	feriadoRepo *repository.FeriadoRepository,
	empresaRepo *repository.EmpresaRepository,
) *EmpresaAgendaService {
	return &EmpresaAgendaService{
		agendaRepo:  agendaRepo,
		feriadoRepo: feriadoRepo,
		empresaRepo: empresaRepo,
	}
}

func (s *EmpresaAgendaService) ListByEmpresa(ctx context.Context, empresaID string) (EmpresaAgendaListResponse, error) {
	items, err := s.agendaRepo.ListByEmpresa(ctx, empresaID)
	if err != nil {
		return EmpresaAgendaListResponse{}, err
	}
	return EmpresaAgendaListResponse{Itens: items}, nil
}

func (s *EmpresaAgendaService) UpdateStatus(ctx context.Context, id, status string) error {
	return s.agendaRepo.UpdateStatus(ctx, id, status)
}

func (s *EmpresaAgendaService) AcompanhamentoByTenant(ctx context.Context, tenantID string) (EmpresaAgendaAcompanhamentoResponse, error) {
	items, err := s.agendaRepo.ListAcompanhamentoByTenant(ctx, tenantID)
	if err != nil {
		return EmpresaAgendaAcompanhamentoResponse{}, err
	}

	return EmpresaAgendaAcompanhamentoResponse{Itens: items}, nil
}

// GerarAgenda gera a agenda de obrigações para uma empresa.
// Busca todos os feriados (fixos, variáveis, municipais e estaduais) e monta
// um mapa de datas para que ajustarVencimento possa postergar vencimentos.
func (s *EmpresaAgendaService) GerarAgenda(ctx context.Context, empresaID, tipoEmpresaID string, dataInicio time.Time) (EmpresaAgendaGerarResponse, error) {
	// Construir mapa de feriados a partir do banco
	feriados, err := s.buildFeriadosMap(ctx, dataInicio)
	if err != nil {
		return EmpresaAgendaGerarResponse{}, fmt.Errorf("build feriados map: %w", err)
	}

	items, err := s.agendaRepo.GerarAgenda(ctx, empresaID, tipoEmpresaID, dataInicio, feriados)
	if err != nil {
		return EmpresaAgendaGerarResponse{}, err
	}

	return EmpresaAgendaGerarResponse{
		Itens:   items,
		Message: fmt.Sprintf("%d obrigações geradas", len(items)),
	}, nil
}

// buildFeriadosMap carrega todos os feriados do banco e expande no intervalo
// de 2 anos (período máximo de geração), retornando um mapa date→true.
func (s *EmpresaAgendaService) buildFeriadosMap(ctx context.Context, dataInicio time.Time) (map[string]bool, error) {
	m := make(map[string]bool)

	// Carregar feriados fixos + variáveis
	for _, codigo := range []string{"FIXO", "VARIAVEL", "MUNICIPAL", "ESTADUAL"} {
		items, _, err := s.feriadoRepo.List(ctx, repository.FeriadoListParams{
			First:       0,
			Rows:        1000,
			HolidayCode: codigo,
		})
		if err != nil {
			return nil, fmt.Errorf("list feriados %s: %w", codigo, err)
		}

		for _, f := range items {
			// f.Data é no formato "DD/MM"
			// Expandir para os próximos 2 anos
			for y := dataInicio.Year(); y <= dataInicio.Year()+1; y++ {
				chave := fmt.Sprintf("%s/%d", f.Data, y)
				t, err := time.Parse("02/01/2006", chave)
				if err != nil {
					continue
				}
				m[t.Format("2006-01-02")] = true
			}
		}
	}

	return m, nil
}
