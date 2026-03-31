package service

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/chayimamaral/vecontab/backend/internal/repository"
)

type EmpresaCompromissoService struct {
	repo        *repository.EmpresaCompromissoRepository
	feriadoRepo *repository.FeriadoRepository
	empresaRepo *repository.EmpresaRepository
}

type EmpresaCompromissoGerarResponse struct {
	Itens      []repository.EmpresaCompromissoItem `json:"itens"`
	Quantidade int                                 `json:"quantidade"`
	Message    string                              `json:"message"`
}

type EmpresaCompromissoAcompanhamentoResponse struct {
	Itens []repository.EmpresaCompromissoAcompanhamentoItem `json:"itens"`
}

func NewEmpresaCompromissoService(
	repo *repository.EmpresaCompromissoRepository,
	feriadoRepo *repository.FeriadoRepository,
	empresaRepo *repository.EmpresaRepository,
) *EmpresaCompromissoService {
	return &EmpresaCompromissoService{
		repo:        repo,
		feriadoRepo: feriadoRepo,
		empresaRepo: empresaRepo,
	}
}

func (s *EmpresaCompromissoService) Gerar(ctx context.Context, empresaID, tenantID string, dataInicio time.Time) (EmpresaCompromissoGerarResponse, error) {
	eid := strings.TrimSpace(empresaID)
	tid := strings.TrimSpace(tenantID)
	if tid == "" {
		return EmpresaCompromissoGerarResponse{}, fmt.Errorf("tenant nao identificado")
	}

	total, err := s.repo.GerarCompromissosMensais(ctx, tid, dataInicio, eid)
	if err != nil {
		return EmpresaCompromissoGerarResponse{}, err
	}

	return EmpresaCompromissoGerarResponse{
		Itens:      []repository.EmpresaCompromissoItem{},
		Quantidade: total,
		Message:    fmt.Sprintf("%d compromissos gerados", total),
	}, nil
}

func (s *EmpresaCompromissoService) AcompanhamentoByTenant(ctx context.Context, tenantID string) (EmpresaCompromissoAcompanhamentoResponse, error) {
	items, err := s.repo.ListAcompanhamentoByTenant(ctx, strings.TrimSpace(tenantID))
	if err != nil {
		return EmpresaCompromissoAcompanhamentoResponse{}, err
	}
	return EmpresaCompromissoAcompanhamentoResponse{Itens: items}, nil
}

func (s *EmpresaCompromissoService) UpdateStatus(ctx context.Context, tenantID, id, status string) error {
	st := strings.TrimSpace(status)
	u := strings.ToUpper(strings.ReplaceAll(st, "Í", "I"))
	switch u {
	case "PENDENTE":
		st = "pendente"
	case "CONCLUIDO":
		st = "concluido"
	default:
		low := strings.ToLower(st)
		if low == "pendente" || low == "concluido" {
			st = low
		} else {
			return fmt.Errorf("status invalido (pendente|concluido)")
		}
	}
	return s.repo.UpdateStatusForTenant(ctx, tenantID, id, st)
}

func (s *EmpresaCompromissoService) UpdateItem(ctx context.Context, tenantID, itemID string, dataVencimento *string, valor *float64) error {
	return s.repo.UpdateItem(ctx, tenantID, itemID, dataVencimento, valor)
}

// buildFeriadosMapForEmpresa: nacionais (FIXO/VARIÁVEL) + municipal só do município da empresa + estadual só da UF.
func (s *EmpresaCompromissoService) buildFeriadosMapForEmpresa(ctx context.Context, dataInicio time.Time, municipioID, estadoID string) (map[string]bool, error) {
	m := make(map[string]bool)
	y0 := dataInicio.Year()
	y1 := dataInicio.Year() + 2

	for _, codigo := range []string{"FIXO", "VARIAVEL"} {
		items, _, err := s.feriadoRepo.List(ctx, repository.FeriadoListParams{
			First:       0,
			Rows:        2000,
			HolidayCode: codigo,
		})
		if err != nil {
			return nil, fmt.Errorf("list feriados %s: %w", codigo, err)
		}
		for _, f := range items {
			for y := y0; y <= y1; y++ {
				chave := fmt.Sprintf("%s/%d", f.Data, y)
				t, err := time.Parse("02/01/2006", chave)
				if err != nil {
					continue
				}
				m[t.Format("2006-01-02")] = true
			}
		}
	}

	munID := strings.TrimSpace(municipioID)
	ufID := strings.TrimSpace(estadoID)

	itemsMun, _, err := s.feriadoRepo.List(ctx, repository.FeriadoListParams{
		First:       0,
		Rows:        2000,
		HolidayCode: "MUNICIPAL",
	})
	if err != nil {
		return nil, fmt.Errorf("list feriados municipal: %w", err)
	}
	for _, f := range itemsMun {
		if f.Municipio == nil || strings.TrimSpace(f.Municipio.ID) != munID {
			continue
		}
		for y := y0; y <= y1; y++ {
			chave := fmt.Sprintf("%s/%d", f.Data, y)
			t, err := time.Parse("02/01/2006", chave)
			if err != nil {
				continue
			}
			m[t.Format("2006-01-02")] = true
		}
	}

	itemsEst, _, err := s.feriadoRepo.List(ctx, repository.FeriadoListParams{
		First:       0,
		Rows:        2000,
		HolidayCode: "ESTADUAL",
	})
	if err != nil {
		return nil, fmt.Errorf("list feriados estadual: %w", err)
	}
	for _, f := range itemsEst {
		if f.Estado == nil || strings.TrimSpace(f.Estado.ID) != ufID {
			continue
		}
		for y := y0; y <= y1; y++ {
			chave := fmt.Sprintf("%s/%d", f.Data, y)
			t, err := time.Parse("02/01/2006", chave)
			if err != nil {
				continue
			}
			m[t.Format("2006-01-02")] = true
		}
	}

	return m, nil
}
