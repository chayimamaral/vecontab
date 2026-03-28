package service

import (
	"context"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/repository"
)

type TenantService struct {
	repo *repository.TenantRepository
}

type TenantCreatedResponse struct {
	TenantCreated repository.TenantEntity `json:"tenantCreated"`
}

type TenantDetailResponse struct {
	Tenant repository.TenantEntity `json:"tenant"`
}

func NewTenantService(repo *repository.TenantRepository) *TenantService {
	return &TenantService{repo: repo}
}

func (s *TenantService) Create(ctx context.Context, nome, contato string) (TenantCreatedResponse, error) {
	tenant, err := s.repo.Create(ctx, nome, contato)
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

func (s *TenantService) Update(ctx context.Context, id, nome, contato string, active bool) (repository.TenantEntity, error) {
	tenant, err := s.repo.Update(ctx, id, nome, contato, active)
	if err != nil {
		return repository.TenantEntity{}, err
	}

	return tenant, nil
}

func (s *TenantService) List(ctx context.Context, role, tenantID string) (any, error) {
	role = strings.ToUpper(strings.TrimSpace(role))
	tenantID = strings.TrimSpace(tenantID)

	if role != "SUPER" && tenantID == "" {
		return []repository.TenantEntity{}, nil
	}

	tenants, err := s.repo.List(ctx, role, tenantID)
	if err != nil {
		return nil, err
	}

	if role == "SUPER" {
		return tenants, nil
	}

	if len(tenants) == 0 {
		return []repository.TenantEntity{}, nil
	}

	return tenants[0], nil
}
