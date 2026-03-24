package service

import (
	"context"

	"github.com/chayimamaral/vecontab/backendgo/internal/repository"
)

type AgendaService struct {
	repo *repository.AgendaRepository
}

type AgendaResponse struct {
	Events []repository.AgendaEvent `json:"events"`
}

type AgendaConcluirPassoResponse struct {
	AgendaID              string `json:"agenda_id"`
	AgendaItemID          string `json:"agenda_item_id"`
	TodosPassosConcluidos bool   `json:"todos_passos_concluidos"`
}

func NewAgendaService(repo *repository.AgendaRepository) *AgendaService {
	return &AgendaService{repo: repo}
}

func (s *AgendaService) List(ctx context.Context, tenantID string) (AgendaResponse, error) {
	events, err := s.repo.ListEvents(ctx, tenantID)
	if err != nil {
		return AgendaResponse{}, err
	}

	return AgendaResponse{Events: events}, nil
}

func (s *AgendaService) Detail(ctx context.Context, tenantID, agendaID string) (AgendaResponse, error) {
	events, err := s.repo.DetailEvents(ctx, tenantID, agendaID)
	if err != nil {
		return AgendaResponse{}, err
	}

	return AgendaResponse{Events: events}, nil
}

func (s *AgendaService) ConcluirPasso(ctx context.Context, tenantID, agendaID, agendaItemID string) (AgendaConcluirPassoResponse, error) {
	result, err := s.repo.ConcluirPasso(ctx, tenantID, agendaID, agendaItemID)
	if err != nil {
		return AgendaConcluirPassoResponse{}, err
	}

	return AgendaConcluirPassoResponse{
		AgendaID:              result.AgendaID,
		AgendaItemID:          result.AgendaItemID,
		TodosPassosConcluidos: result.TodosPassosConcluidos,
	}, nil
}
