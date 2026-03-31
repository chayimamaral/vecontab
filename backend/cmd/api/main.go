package main

import (
	"context"
	"log"
	"net/http"
	"os/signal"
	"syscall"
	"time"

	"github.com/chayimamaral/vecontab/backend/internal/config"
	"github.com/chayimamaral/vecontab/backend/internal/db"
	"github.com/chayimamaral/vecontab/backend/internal/httpapi"
	"github.com/chayimamaral/vecontab/backend/internal/worker"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("load config: %v", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	pool, err := db.NewPostgresPool(ctx, cfg)
	if err != nil {
		log.Fatalf("connect postgres: %v", err)
	}
	defer pool.Close()

	server := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           httpapi.NewRouter(cfg, pool),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errCh := make(chan error, 1)

	if cfg.CompromissosWorkerEnabled {
		w, err := worker.NewCompromissosWorker(pool, cfg)
		if err != nil {
			log.Fatalf("init compromissos worker: %v", err)
		}
		go w.Start(ctx)
	}

	go func() {
		log.Printf("backendgo listening on :%s", cfg.Port)
		errCh <- server.ListenAndServe()
	}()

	select {
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		if err := server.Shutdown(shutdownCtx); err != nil {
			log.Printf("server shutdown: %v", err)
		}
	case err := <-errCh:
		if err != nil && err != http.ErrServerClosed {
			log.Fatalf("serve http: %v", err)
		}
	}
}
