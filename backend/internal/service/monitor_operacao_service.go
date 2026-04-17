package service

import (
	"context"
	"fmt"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/chayimamaral/vecontab/backend/internal/repository"
)

type MonitorOperacaoService struct {
	repo *repository.MonitorOperacaoRepository
}

func NewMonitorOperacaoService(repo *repository.MonitorOperacaoRepository) *MonitorOperacaoService {
	return &MonitorOperacaoService{repo: repo}
}

type MonitorOperacaoListResponse struct {
	Itens []domain.MonitorOperacaoItem `json:"itens"`
	Total int64                        `json:"total"`
}

type MonitorOperacaoListFilter struct {
	ClienteNome string
	Status      string
	DataDeISO   string
	DataAteISO string
}

func (s *MonitorOperacaoService) Registrar(ctx context.Context, in repository.MonitorOperacaoInsert) (string, error) {
	o := strings.TrimSpace(in.Origem)
	t := strings.TrimSpace(in.Tipo)
	st := strings.TrimSpace(in.Status)
	if o == "" || t == "" || st == "" {
		return "", fmt.Errorf("origem, tipo e status sao obrigatorios")
	}
	if strings.TrimSpace(in.TenantID) == "" {
		return "", fmt.Errorf("tenant_id obrigatorio")
	}
	return s.repo.Insert(ctx, in)
}

func (s *MonitorOperacaoService) VincularCompromissos(ctx context.Context, monitorID string, compromissoIDs []string) error {
	return s.repo.InsertCompromissosRefs(ctx, monitorID, compromissoIDs)
}

func (s *MonitorOperacaoService) ListPage(ctx context.Context, viewerRole, viewerTenantID string, limit, offset int, f MonitorOperacaoListFilter) (MonitorOperacaoListResponse, error) {
	role := strings.TrimSpace(strings.ToUpper(viewerRole))
	if role != "SUPER" && role != "ADMIN" {
		return MonitorOperacaoListResponse{}, fmt.Errorf("perfil nao autorizado")
	}
	if role == "ADMIN" && strings.TrimSpace(viewerTenantID) == "" {
		return MonitorOperacaoListResponse{}, fmt.Errorf("tenant nao identificado")
	}
	rf := repository.MonitorOperacaoListFilter{
		ClienteNome: strings.TrimSpace(f.ClienteNome),
		Status:      strings.TrimSpace(strings.ToUpper(f.Status)),
		DataDeISO:   strings.TrimSpace(f.DataDeISO),
		DataAteISO: strings.TrimSpace(f.DataAteISO),
	}
	total, err := s.repo.CountList(ctx, role, viewerTenantID, rf)
	if err != nil {
		return MonitorOperacaoListResponse{}, err
	}
	items, err := s.repo.ListPage(ctx, role, viewerTenantID, limit, offset, rf)
	if err != nil {
		return MonitorOperacaoListResponse{}, err
	}
	return MonitorOperacaoListResponse{Itens: items, Total: total}, nil
}
