package config

import (
	"fmt"
	"os"

	"github.com/joho/godotenv"
)

type Config struct {
	Port            string
	DatabaseURL     string
	JWTSecret       string
	SSLRootCertPath string
	SSLInsecure     bool
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
		Port:            getEnv("SERVER_PORT", "3333"),
		DatabaseURL:     os.Getenv("PG_URL"),
		JWTSecret:       os.Getenv("JWT_SECRET"),
		SSLRootCertPath: getEnv("PG_SSL_ROOT_CERT", "/home/camaral/.postgres/ca.crt"),
		SSLInsecure:     getEnv("PG_SSL_INSECURE", "true") == "true",
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
