package worker

import (
	"context"
	"fmt"
	"log"
	"sync/atomic"
	"time"

	"github.com/chayimamaral/vecontab/backend/internal/config"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/robfig/cron/v3"
)

type CompromissosWorker struct {
	pool    *pgxpool.Pool
	cfg     config.Config
	cron    *cron.Cron
	running int32
}

const compromissosAdvisoryLockKey int64 = 9482217701

func NewCompromissosWorker(pool *pgxpool.Pool, cfg config.Config) (*CompromissosWorker, error) {
	loc, err := time.LoadLocation(cfg.CompromissosWorkerTimezone)
	if err != nil {
		return nil, fmt.Errorf("timezone inválida do worker: %w", err)
	}

	c := cron.New(
		cron.WithLocation(loc),
		cron.WithParser(cron.NewParser(cron.Minute|cron.Hour|cron.Dom|cron.Month|cron.Dow)),
		cron.WithChain(cron.SkipIfStillRunning(cron.DefaultLogger)),
	)

	w := &CompromissosWorker{
		pool: pool,
		cfg:  cfg,
		cron: c,
	}

	if _, err := c.AddFunc(cfg.CompromissosWorkerCron, func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		defer cancel()
		if err := w.runOnce(ctx); err != nil {
			log.Printf("worker compromissos: erro na execução agendada: %v", err)
		}
	}); err != nil {
		return nil, fmt.Errorf("cron inválido do worker: %w", err)
	}

	return w, nil
}

func (w *CompromissosWorker) Start(ctx context.Context) {
	log.Printf("worker compromissos: habilitado cron=%q tz=%q", w.cfg.CompromissosWorkerCron, w.cfg.CompromissosWorkerTimezone)
	w.cron.Start()

	if w.cfg.CompromissosWorkerRunOnStartup {
		go func() {
			startupCtx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
			defer cancel()
			if err := w.runOnce(startupCtx); err != nil {
				log.Printf("worker compromissos: erro no run_on_startup: %v", err)
			}
		}()
	}

	<-ctx.Done()
	stopCtx := w.cron.Stop()
	select {
	case <-stopCtx.Done():
	case <-time.After(10 * time.Second):
	}
	log.Printf("worker compromissos: finalizado")
}

func (w *CompromissosWorker) runOnce(ctx context.Context) error {
	if !atomic.CompareAndSwapInt32(&w.running, 0, 1) {
		return nil
	}
	defer atomic.StoreInt32(&w.running, 0)

	tx, err := w.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx worker: %w", err)
	}
	defer tx.Rollback(ctx)

	var gotLock bool
	if err := tx.QueryRow(ctx, `SELECT pg_try_advisory_xact_lock($1)`, compromissosAdvisoryLockKey).Scan(&gotLock); err != nil {
		return fmt.Errorf("obter advisory lock: %w", err)
	}
	if !gotLock {
		log.Printf("worker compromissos: execução já em andamento em outra réplica")
		return nil
	}

	rows, err := tx.Query(ctx, `SELECT id FROM public.tenant WHERE active = true`)
	if err != nil {
		return fmt.Errorf("listar tenants ativos: %w", err)
	}
	defer rows.Close()

	totalTenants := 0
	totalInseridos := 0

	for rows.Next() {
		var tenantID string
		if err := rows.Scan(&tenantID); err != nil {
			return fmt.Errorf("scan tenant: %w", err)
		}
		totalTenants++

		var inseridos int
		if err := tx.QueryRow(
			ctx,
			`SELECT public.gerar_compromissos_mensais($1, CURRENT_DATE, NULL)`,
			tenantID,
		).Scan(&inseridos); err != nil {
			log.Printf("worker compromissos: tenant=%s erro=%v", tenantID, err)
			continue
		}
		totalInseridos += inseridos
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("iterar tenants: %w", err)
	}

	log.Printf("worker compromissos: tenants=%d inseridos=%d", totalTenants, totalInseridos)
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit tx worker: %w", err)
	}
	return nil
}
