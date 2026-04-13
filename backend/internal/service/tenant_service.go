package service

import (
	"context"
	"fmt"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/chayimamaral/vecontab/backend/internal/repository"
)

type TenantService struct {
	repo *repository.TenantRepository
}

type TenantCreatedResponse struct {
	TenantCreated domain.TenantEntity `json:"tenantCreated"`
}

type TenantDetailResponse struct {
	Tenant domain.TenantEntity `json:"tenant"`
}

func NewTenantService(repo *repository.TenantRepository) *TenantService {
	return &TenantService{repo: repo}
}

func normalizePlanoTenant(plano string) (string, error) {
	p := strings.ToUpper(strings.TrimSpace(plano))
	if p == "" {
		return "DEMO", nil
	}
	switch p {
	case "DEMO", "BASICO", "PRO", "PREMIUM":
		return p, nil
	default:
		return "", fmt.Errorf("Plano invalido: use DEMO, BASICO, PRO ou PREMIUM")
	}
}

func (s *TenantService) Create(ctx context.Context, nome, contato, plano string) (TenantCreatedResponse, error) {
	p, err := normalizePlanoTenant(plano)
	if err != nil {
		return TenantCreatedResponse{}, err
	}
	tenant, err := s.repo.Create(ctx, nome, contato, p)
	if err != nil {
		return TenantCreatedResponse{}, err
	}

	return TenantCreatedResponse{TenantCreated: tenant}, nil
}

func (s *TenantService) Detail(ctx context.Context, id string) (TenantDetailResponse, error) {
	tenant, err := s.repo.Detail(ctx, id)
	if err != nil {
		return TenantDetailResponse{}, err
	}

	return TenantDetailResponse{Tenant: tenant}, nil
}

func (s *TenantService) Update(ctx context.Context, id, nome, contato, plano string, active bool) (domain.TenantEntity, error) {
	p := strings.TrimSpace(plano)
	if p != "" {
		normalized, err := normalizePlanoTenant(p)
		if err != nil {
			return domain.TenantEntity{}, err
		}
		p = normalized
	}

	tenant, err := s.repo.Update(ctx, id, nome, contato, p, active)
	if err != nil {
		return domain.TenantEntity{}, err
	}

	return tenant, nil
}

func (s *TenantService) List(ctx context.Context, role, tenantID string) (any, error) {
	role = strings.ToUpper(strings.TrimSpace(role))
	tenantID = strings.TrimSpace(tenantID)

	if role != "SUPER" && tenantID == "" {
		return []domain.TenantEntity{}, nil
	}

	if role == "SUPER" {
		return s.repo.ListWithDadosForSuper(ctx)
	}

	tenants, err := s.repo.List(ctx, role, tenantID)
	if err != nil {
		return nil, err
	}

	if len(tenants) == 0 {
		return []domain.TenantEntity{}, nil
	}

	return tenants[0], nil
}
