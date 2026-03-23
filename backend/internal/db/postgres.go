package db

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"os"

	"github.com/chayimamaral/vecontab/backendgo/internal/config"
	"github.com/jackc/pgx/v5/pgxpool"
)

func NewPostgresPool(ctx context.Context, cfg config.Config) (*pgxpool.Pool, error) {
	poolConfig, err := pgxpool.ParseConfig(cfg.DatabaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse pg config: %w", err)
	}

	// if cfg.SSLRootCertPath != "" {
	// 	certBytes, certErr := os.ReadFile(cfg.SSLRootCertPath)
	// 	if certErr == nil {
	// 		rootCAs := x509.NewCertPool()
	// 		rootCAs.AppendCertsFromPEM(certBytes)

	// 		poolConfig.ConnConfig.TLSConfig = &tls.Config{
	// 			MinVersion:         tls.VersionTLS12,
	// 			RootCAs:            rootCAs,
	// 			InsecureSkipVerify: cfg.SSLInsecure,
	// 		}
	// 	}
	// }

	// Só entra aqui se houver um caminho E se NÃO for para ser inseguro/desabilitado
	if cfg.SSLRootCertPath != "" && !cfg.SSLInsecure {
		certBytes, certErr := os.ReadFile(cfg.SSLRootCertPath)
		if certErr == nil {
			rootCAs := x509.NewCertPool()
			rootCAs.AppendCertsFromPEM(certBytes)

			poolConfig.ConnConfig.TLSConfig = &tls.Config{
				MinVersion: tls.VersionTLS12,
				RootCAs:    rootCAs,
			}
		}
	} else {
		// Garante que o TLSConfig seja nulo se sslmode=disable for a intenção
		poolConfig.ConnConfig.TLSConfig = nil
	}

	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		return nil, fmt.Errorf("create pg pool: %w", err)
	}

	if err := pool.Ping(ctx); err != nil {
		return nil, fmt.Errorf("ping pg: %w", err)
	}

	return pool, nil
}
