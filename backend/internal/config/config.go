package config

import (
	"fmt"
	"os"

	"github.com/joho/godotenv"
)

type Config struct {
	Port                           string
	DatabaseURL                    string
	JWTSecret                      string
	SSLRootCertPath                string
	SSLInsecure                    bool
	CompromissosWorkerEnabled      bool
	CompromissosWorkerCron         string
	CompromissosWorkerRunOnStartup bool
	CompromissosWorkerTimezone     string

	// CertCryptoKeyHex: 64 caracteres hex (32 bytes) para AES-256-GCM de PFX/senha (issue #55).
	CertCryptoKeyHex string
	// SERPRO Integra Contador — OAuth2 cliente (credenciais de desenvolvedor); URLs conforme documentação oficial.
	SerproOAuthTokenURL string
	SerproClientID      string
	SerproClientSecret  string
	SerproAPIBaseURL    string
}

func Load() (Config, error) {
	// Tenta carregar o .env do diretório atual
	err := godotenv.Load()
	if err != nil {
		fmt.Println("Aviso: .env não encontrado no diretório atual, tentando caminho relativo...")
	}
	err = godotenv.Load(".env") // Ajuste o caminho se necessário
	if err != nil {
		// Se este também falhar, talvez seja um problema real
		fmt.Printf("Erro ao carregar ../../.env: %v\n", err)
	}

	cfg := Config{
		Port:                           getEnv("PORT", "8080"),
		DatabaseURL:                    os.Getenv("PG_URL"),
		JWTSecret:                      os.Getenv("JWT_SECRET"),
		SSLRootCertPath:                getEnv("PG_SSL_ROOT_CERT", "/home/camaral/.postgres/ca.crt"),
		SSLInsecure:                    getEnv("PG_SSL_INSECURE", "true") == "true",
		CompromissosWorkerEnabled:      getEnv("COMPROMISSOS_WORKER_ENABLED", "false") == "true",
		CompromissosWorkerCron:         getEnv("COMPROMISSOS_WORKER_CRON", "0 5 25 * *"),
		CompromissosWorkerRunOnStartup: getEnv("COMPROMISSOS_WORKER_RUN_ON_STARTUP", "false") == "true",
		CompromissosWorkerTimezone:     getEnv("COMPROMISSOS_WORKER_TIMEZONE", "America/Sao_Paulo"),
		CertCryptoKeyHex:               os.Getenv("VECONTAB_CERT_CRYPTO_KEY_HEX"),
		SerproOAuthTokenURL:              getEnv("SERPRO_OAUTH_TOKEN_URL", ""),
		SerproClientID:                   os.Getenv("SERPRO_CLIENT_ID"),
		SerproClientSecret:               os.Getenv("SERPRO_CLIENT_SECRET"),
		SerproAPIBaseURL:                 getEnv("SERPRO_API_BASE_URL", ""),
	}

	if cfg.DatabaseURL == "" {
		return Config{}, fmt.Errorf("PG_URL is required")
	}

	if cfg.JWTSecret == "" {
		return Config{}, fmt.Errorf("JWT_SECRET is required")
	}

	return cfg, nil
}

func getEnv(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}

	return value
}
