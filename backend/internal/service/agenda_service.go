package service

import (
	"context"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/repository"
)

// AgendaRepository descreve o acesso a dados da agenda (calendário de rotinas).
// *repository.AgendaRepository satisfaz esta interface.
type AgendaRepository interface {
	ListEvents(ctx context.Context, tenantID string) ([]repository.AgendaEvent, error)
	DetailEvents(ctx context.Context, tenantID, agendaID string) ([]repository.AgendaEvent, error)
	ConcluirPasso(ctx context.Context, tenantID, agendaID, agendaItemID string) (repository.ConcluirPassoResult, error)
	ReabrirPasso(ctx context.Context, tenantID, agendaID, agendaItemID string) (repository.ConcluirPassoResult, error)
	InsertAgendaItem(ctx context.Context, tenantID, agendaID, descricao, inicio, termino string) (string, error)
	UpdateAgendaItem(ctx context.Context, tenantID, agendaID, itemID string, descricao, inicio, termino *string) error
	DeleteAgendaItem(ctx context.Context, tenantID, agendaID, itemID string) error
}

type AgendaService struct {
	repo AgendaRepository
}

type AgendaResponse struct {
	Events []repository.AgendaEvent `json:"events"`
}

type AgendaConcluirPassoResponse struct {
	AgendaID              string `json:"agenda_id"`
	AgendaItemID          string `json:"agenda_item_id"`
	TodosPassosConcluidos bool   `json:"todos_passos_concluidos"`
}

func NewAgendaService(repo AgendaRepository) *AgendaService {
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

func (s *AgendaService) ReabrirPasso(ctx context.Context, tenantID, agendaID, agendaItemID string) (AgendaConcluirPassoResponse, error) {
	result, err := s.repo.ReabrirPasso(ctx, tenantID, agendaID, agendaItemID)
	if err != nil {
		return AgendaConcluirPassoResponse{}, err
	}

	return AgendaConcluirPassoResponse{
		AgendaID:              result.AgendaID,
		AgendaItemID:          result.AgendaItemID,
		TodosPassosConcluidos: result.TodosPassosConcluidos,
	}, nil
}

type AgendaItemCriadoResponse struct {
	AgendaID     string `json:"agenda_id"`
	AgendaItemID string `json:"agenda_item_id"`
}

func (s *AgendaService) CreateAgendaItem(ctx context.Context, tenantID, agendaID, descricao, inicio, termino string) (AgendaItemCriadoResponse, error) {
	agendaID = strings.TrimSpace(agendaID)
	id, err := s.repo.InsertAgendaItem(ctx, tenantID, agendaID, descricao, inicio, termino)
	if err != nil {
		return AgendaItemCriadoResponse{}, err
	}
	return AgendaItemCriadoResponse{AgendaID: agendaID, AgendaItemID: id}, nil
}

func (s *AgendaService) UpdateAgendaItem(ctx context.Context, tenantID, agendaID, itemID string, descricao, inicio, termino *string) error {
	return s.repo.UpdateAgendaItem(ctx, tenantID, agendaID, itemID, descricao, inicio, termino)
}

func (s *AgendaService) DeleteAgendaItem(ctx context.Context, tenantID, agendaID, itemID string) error {
	return s.repo.DeleteAgendaItem(ctx, tenantID, agendaID, itemID)
}
