package service

import (
	"context"

	"github.com/chayimamaral/vecontab/backend/internal/repository"
)

type EmpresaDadosService struct {
	repo *repository.EmpresaDadosRepository
}

func NewEmpresaDadosService(repo *repository.EmpresaDadosRepository) *EmpresaDadosService {
	return &EmpresaDadosService{repo: repo}
}

func (s *EmpresaDadosService) Get(ctx context.Context, empresaID, tenantID string) (*repository.EmpresaDadosItem, error) {
	return s.repo.GetByEmpresa(ctx, empresaID, tenantID)
}

func (s *EmpresaDadosService) Save(ctx context.Context, in repository.EmpresaDadosUpsertInput) error {
	return s.repo.Upsert(ctx, in)
}
