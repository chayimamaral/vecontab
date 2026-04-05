package service

import (
	"context"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/chayimamaral/vecontab/backend/internal/repository"
)

type ClienteService struct {
	repo *repository.ClienteRepository
}

type ClienteListResponse struct {
	Clientes []domain.Cliente `json:"clientes"`
}

func NewClienteService(repo *repository.ClienteRepository) *ClienteService {
	return &ClienteService{repo: repo}
}

func (s *ClienteService) List(ctx context.Context, tenantID string, limit, offset int) (ClienteListResponse, error) {
	clientes, err := s.repo.ListByTenant(ctx, tenantID, limit, offset)
	if err != nil {
		return ClienteListResponse{}, err
	}
	return ClienteListResponse{Clientes: clientes}, nil
}
