package service

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/chayimamaral/vecontab/backend/internal/repository"
	"github.com/jackc/pgx/v5/pgconn"
)

type RegimeTributarioService struct {
	repo *repository.RegimeTributarioRepository
}

type RegimeTributarioListResponse struct {
	Regimes      []domain.RegimeTributario `json:"regimes"`
	TotalRecords int64                     `json:"totalRecords"`
}

func NewRegimeTributarioService(repo *repository.RegimeTributarioRepository) *RegimeTributarioService {
	return &RegimeTributarioService{repo: repo}
}

func (s *RegimeTributarioService) List(ctx context.Context, params repository.RegimeTributarioListParams) (RegimeTributarioListResponse, error) {
	regimes, total, err := s.repo.List(ctx, params)
	if err != nil {
		return RegimeTributarioListResponse{}, err
	}
	return RegimeTributarioListResponse{Regimes: regimes, TotalRecords: total}, nil
}

func (s *RegimeTributarioService) Create(ctx context.Context, nome string, codigoCRT int, tipoApuracao string, ativo bool, configuracaoJSON []byte) (RegimeTributarioListResponse, error) {
	regimes, total, err := s.repo.Create(ctx, nome, codigoCRT, tipoApuracao, ativo, configuracaoJSON)
	if err != nil {
		return RegimeTributarioListResponse{}, mapRegimeRepoErr(err)
	}
	return RegimeTributarioListResponse{Regimes: regimes, TotalRecords: total}, nil
}

func (s *RegimeTributarioService) Update(ctx context.Context, id, nome string, codigoCRT int, tipoApuracao string, ativo bool, configuracaoJSON []byte) (RegimeTributarioListResponse, error) {
	regimes, total, err := s.repo.Update(ctx, id, nome, codigoCRT, tipoApuracao, ativo, configuracaoJSON)
	if err != nil {
		return RegimeTributarioListResponse{}, mapRegimeRepoErr(err)
	}
	if total == 0 {
		return RegimeTributarioListResponse{}, fmt.Errorf("regime nao encontrado")
	}
	return RegimeTributarioListResponse{Regimes: regimes, TotalRecords: total}, nil
}

func (s *RegimeTributarioService) Delete(ctx context.Context, id string) (RegimeTributarioListResponse, error) {
	regimes, total, err := s.repo.Delete(ctx, id)
	if err != nil {
		return RegimeTributarioListResponse{}, mapRegimeRepoErr(err)
	}
	if total == 0 {
		return RegimeTributarioListResponse{}, fmt.Errorf("regime nao encontrado")
	}
	return RegimeTributarioListResponse{Regimes: regimes, TotalRecords: total}, nil
}

func mapRegimeRepoErr(err error) error {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		if strings.Contains(pgErr.ConstraintName, "codigo_crt") {
			return fmt.Errorf("ja existe regime com este codigo CRT")
		}
		return fmt.Errorf("violacao de unicidade no cadastro")
	}
	return err
}
