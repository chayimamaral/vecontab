package service_test

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/chayimamaral/vecontab/backend/internal/repository"
	"github.com/chayimamaral/vecontab/backend/internal/service"
)

var errSentinelDB = errors.New("erro simulado do repositório")

type mockAgendaRepository struct {
	listEvents    func(ctx context.Context, tenantID string) ([]repository.AgendaEvent, error)
	detailEvents  func(ctx context.Context, tenantID, agendaID string) ([]repository.AgendaEvent, error)
	concluirPasso func(ctx context.Context, tenantID, agendaID, agendaItemID string) (repository.ConcluirPassoResult, error)
}

func (m *mockAgendaRepository) ListEvents(ctx context.Context, tenantID string) ([]repository.AgendaEvent, error) {
	if m.listEvents != nil {
		return m.listEvents(ctx, tenantID)
	}
	return nil, nil
}

func (m *mockAgendaRepository) DetailEvents(ctx context.Context, tenantID, agendaID string) ([]repository.AgendaEvent, error) {
	if m.detailEvents != nil {
		return m.detailEvents(ctx, tenantID, agendaID)
	}
	return nil, nil
}

func (m *mockAgendaRepository) ConcluirPasso(ctx context.Context, tenantID, agendaID, agendaItemID string) (repository.ConcluirPassoResult, error) {
	if m.concluirPasso != nil {
		return m.concluirPasso(ctx, tenantID, agendaID, agendaItemID)
	}
	return repository.ConcluirPassoResult{}, nil
}

func TestAgendaService_List(t *testing.T) {
	ctx := context.Background()
	sample := []repository.AgendaEvent{{ID: "1", Title: "A"}}

	tests := []struct {
		name       string
		mock       *mockAgendaRepository
		wantEvents []repository.AgendaEvent
		wantErr    error
	}{
		{
			name: "sucesso repassa eventos",
			mock: &mockAgendaRepository{
				listEvents: func(_ context.Context, tenantID string) ([]repository.AgendaEvent, error) {
					if tenantID != "t1" {
						t.Errorf("tenantID = %q", tenantID)
					}
					return sample, nil
				},
			},
			wantEvents: sample,
		},
		{
			name: "erro do banco propagado com unwrap",
			mock: &mockAgendaRepository{
				listEvents: func(context.Context, string) ([]repository.AgendaEvent, error) {
					return nil, fmt.Errorf("list agenda events: %w", errSentinelDB)
				},
			},
			wantErr: errSentinelDB,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			svc := service.NewAgendaService(tt.mock)
			got, err := svc.List(ctx, "t1")
			if tt.wantErr != nil {
				if err == nil {
					t.Fatal("esperava erro")
				}
				if !errors.Is(err, tt.wantErr) {
					t.Fatalf("errors.Is: got %v, want unwrap até %v", err, tt.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if len(got.Events) != len(tt.wantEvents) {
				t.Fatalf("len(events) = %d, want %d", len(got.Events), len(tt.wantEvents))
			}
			if len(tt.wantEvents) > 0 && got.Events[0].ID != tt.wantEvents[0].ID {
				t.Fatalf("Events[0].ID = %q, want %q", got.Events[0].ID, tt.wantEvents[0].ID)
			}
		})
	}
}

func TestAgendaService_Detail(t *testing.T) {
	ctx := context.Background()
	sample := []repository.AgendaEvent{{ID: "item-1", Title: "Passo"}}

	tests := []struct {
		name       string
		mock       *mockAgendaRepository
		wantEvents []repository.AgendaEvent
		wantErr    error
	}{
		{
			name: "sucesso",
			mock: &mockAgendaRepository{
				detailEvents: func(_ context.Context, tenantID, agendaID string) ([]repository.AgendaEvent, error) {
					if tenantID != "t1" || agendaID != "ag-1" {
						t.Errorf("tenant=%q agenda=%q", tenantID, agendaID)
					}
					return sample, nil
				},
			},
			wantEvents: sample,
		},
		{
			name: "erro do banco propagado",
			mock: &mockAgendaRepository{
				detailEvents: func(context.Context, string, string) ([]repository.AgendaEvent, error) {
					return nil, fmt.Errorf("list agenda detail events: %w", errSentinelDB)
				},
			},
			wantErr: errSentinelDB,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			svc := service.NewAgendaService(tt.mock)
			got, err := svc.Detail(ctx, "t1", "ag-1")
			if tt.wantErr != nil {
				if err == nil {
					t.Fatal("esperava erro")
				}
				if !errors.Is(err, tt.wantErr) {
					t.Fatalf("errors.Is: got %v, want %v", err, tt.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if len(got.Events) != 1 || got.Events[0].ID != "item-1" {
				t.Fatalf("response inesperada: %+v", got.Events)
			}
		})
	}
}

func TestAgendaService_ConcluirPasso(t *testing.T) {
	ctx := context.Background()
	wantResult := repository.ConcluirPassoResult{
		AgendaID:              "ag-1",
		AgendaItemID:          "ai-1",
		TodosPassosConcluidos: true,
	}

	tests := []struct {
		name     string
		mock     *mockAgendaRepository
		wantResp service.AgendaConcluirPassoResponse
		wantErr  error
	}{
		{
			name: "sucesso mapeia resultado do repositório",
			mock: &mockAgendaRepository{
				concluirPasso: func(_ context.Context, tenantID, agendaID, itemID string) (repository.ConcluirPassoResult, error) {
					if tenantID != "t1" || agendaID != "ag-1" || itemID != "ai-1" {
						t.Errorf("args tenant=%q agenda=%q item=%q", tenantID, agendaID, itemID)
					}
					return wantResult, nil
				},
			},
			wantResp: service.AgendaConcluirPassoResponse{
				AgendaID:              wantResult.AgendaID,
				AgendaItemID:          wantResult.AgendaItemID,
				TodosPassosConcluidos: wantResult.TodosPassosConcluidos,
			},
		},
		{
			name: "erro do banco propagado sem perder causa",
			mock: &mockAgendaRepository{
				concluirPasso: func(context.Context, string, string, string) (repository.ConcluirPassoResult, error) {
					return repository.ConcluirPassoResult{}, fmt.Errorf("concluir passo da agenda: %w", errSentinelDB)
				},
			},
			wantErr: errSentinelDB,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			svc := service.NewAgendaService(tt.mock)
			got, err := svc.ConcluirPasso(ctx, "t1", "ag-1", "ai-1")
			if tt.wantErr != nil {
				if err == nil {
					t.Fatal("esperava erro")
				}
				if !errors.Is(err, tt.wantErr) {
					t.Fatalf("errors.Is: got %v, want %v", err, tt.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if got != tt.wantResp {
				t.Fatalf("got %+v, want %+v", got, tt.wantResp)
			}
		})
	}
}
