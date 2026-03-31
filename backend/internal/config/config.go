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
		CompromissosWorkerCron:         getEnv("COMPROMISSOS_WORKER_CRON", "0 5 1 * *"),
		CompromissosWorkerRunOnStartup: getEnv("COMPROMISSOS_WORKER_RUN_ON_STARTUP", "false") == "true",
		CompromissosWorkerTimezone:     getEnv("COMPROMISSOS_WORKER_TIMEZONE", "America/Sao_Paulo"),
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
