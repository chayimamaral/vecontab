package service

import (
	"context"
	"fmt"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/chayimamaral/vecontab/backend/internal/repository"
)

type ConfiguracaoIntegracaoService struct {
	repo *repository.ConfiguracaoIntegracaoRepository
}

func NewConfiguracaoIntegracaoService(repo *repository.ConfiguracaoIntegracaoRepository) *ConfiguracaoIntegracaoService {
	return &ConfiguracaoIntegracaoService{repo: repo}
}

func (s *ConfiguracaoIntegracaoService) SaveChavesSuper(ctx context.Context, item domain.ChavesSuper) error {
	if strings.TrimSpace(item.TenantID) == "" {
		return fmt.Errorf("tenant obrigatorio")
	}
	if strings.TrimSpace(item.ConsumerKey) == "" || strings.TrimSpace(item.ConsumerSecret) == "" {
		return fmt.Errorf("consumer key e consumer secret obrigatorios")
	}
	return s.repo.UpsertChavesSuper(ctx, item)
}

func (s *ConfiguracaoIntegracaoService) GetChavesSuper(ctx context.Context, tenantID string) (domain.ChavesSuper, error) {
	return s.repo.GetChavesSuper(ctx, tenantID)
}

func (s *ConfiguracaoIntegracaoService) SaveTenantConfiguracoes(ctx context.Context, item domain.TenantConfiguracoes) error {
	if strings.TrimSpace(item.TenantID) == "" {
		return fmt.Errorf("tenant obrigatorio")
	}
	tipo := strings.ToUpper(strings.TrimSpace(item.TipoCertificado))
	if tipo != "" && tipo != "A1" && tipo != "A3" {
		return fmt.Errorf("tipo_certificado deve ser A1 ou A3")
	}
	item.TipoCertificado = tipo
	return s.repo.UpsertTenantConfiguracoes(ctx, item)
}

func (s *ConfiguracaoIntegracaoService) GetTenantConfiguracoes(ctx context.Context, tenantID string) (domain.TenantConfiguracoes, error) {
	return s.repo.GetTenantConfiguracoes(ctx, tenantID)
}
