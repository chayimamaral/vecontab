package worker

import (
	"context"
	"fmt"
	"log"
	"sync/atomic"
	"time"

	"github.com/chayimamaral/vecontab/backend/internal/config"
	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/chayimamaral/vecontab/backend/internal/repository"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/robfig/cron/v3"
)

type CompromissosWorker struct {
	pool    *pgxpool.Pool
	cfg     config.Config
	cron    *cron.Cron
	running int32
	monitor *repository.MonitorOperacaoRepository
}

const compromissosAdvisoryLockKey int64 = 9482217701

func NewCompromissosWorker(pool *pgxpool.Pool, cfg config.Config, monitor *repository.MonitorOperacaoRepository) (*CompromissosWorker, error) {
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
		pool:    pool,
		cfg:     cfg,
		cron:    c,
		monitor: monitor,
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

	refDate := time.Now().AddDate(0, 1, 0)
	refMonth := time.Date(refDate.Year(), refDate.Month(), 1, 0, 0, 0, 0, refDate.Location())

	rows, err := tx.Query(ctx, `
		SELECT e.id::text, e.tenant_id::text
		FROM public.empresa e
		WHERE e.ativo = true
		  AND e.iniciado = true
		  AND NOT EXISTS (
			SELECT 1 FROM public.empresa_compromissos ec WHERE ec.empresa_id = e.id
		  )
		ORDER BY e.id ASC
	`)
	if err != nil {
		return fmt.Errorf("listar empresas elegiveis para worker: %w", err)
	}
	type empresaAlvo struct {
		ID       string
		TenantID string
	}
	type tenantResumo struct {
		EmpresasAlvo int
		Inseridos    int
		Erros        int
	}
	alvos := make([]empresaAlvo, 0)
	for rows.Next() {
		var a empresaAlvo
		if err := rows.Scan(&a.ID, &a.TenantID); err != nil {
			rows.Close()
			return fmt.Errorf("scan empresas elegiveis para worker: %w", err)
		}
		alvos = append(alvos, a)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return fmt.Errorf("rows empresas elegiveis para worker: %w", err)
	}
	rows.Close()

	repo := repository.NewEmpresaCompromissoRepository(w.pool)
	compromissoIDs := make([]string, 0, 256)
	var totalInseridos int
	var totalComErro int
	porTenant := make(map[string]*tenantResumo)
	for _, alvo := range alvos {
		resumo, ok := porTenant[alvo.TenantID]
		if !ok {
			resumo = &tenantResumo{}
			porTenant[alvo.TenantID] = resumo
		}
		resumo.EmpresasAlvo++

		items, err := repo.GerarCompromissosEmpresa(ctx, alvo.TenantID, refMonth, alvo.ID)
		if err != nil {
			totalComErro++
			resumo.Erros++
			log.Printf("worker compromissos: erro empresa=%s tenant=%s: %v", alvo.ID, alvo.TenantID, err)
			continue
		}
		inseridos := len(items)
		for _, it := range items {
			if it.ID != "" {
				compromissoIDs = append(compromissoIDs, it.ID)
			}
		}
		totalInseridos += inseridos
		resumo.Inseridos += inseridos
	}

	for tenantID, r := range porTenant {
		log.Printf(
			"worker compromissos: tenant=%s competencia=%s empresas_alvo=%d inseridos=%d erros=%d",
			tenantID,
			refMonth.Format("2006-01-02"),
			r.EmpresasAlvo,
			r.Inseridos,
			r.Erros,
		)
	}

	log.Printf(
		"worker compromissos: competencia=%s empresas_alvo=%d inseridos=%d erros=%d",
		refMonth.Format("2006-01-02"),
		len(alvos),
		totalInseridos,
		totalComErro,
	)
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit tx worker: %w", err)
	}

	status := domain.MonitorOperacaoStatusSucesso
	msg := fmt.Sprintf("inseridos=%d empresas_alvo=%d", totalInseridos, len(alvos))
	if totalComErro > 0 {
		status = domain.MonitorOperacaoStatusErro
		msg = fmt.Sprintf("%s erros=%d", msg, totalComErro)
	}
	w.recordMonitorOperacao(context.Background(), status, msg, map[string]any{
		"competencia":   refMonth.Format("2006-01-02"),
		"inseridos":     totalInseridos,
		"empresas_alvo": len(alvos),
		"erros":         totalComErro,
	}, compromissoIDs)
	return nil
}

func (w *CompromissosWorker) recordMonitorOperacao(ctx context.Context, status, msg string, det map[string]any, compromissoIDs []string) {
	if w.monitor == nil {
		return
	}
	ctx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	m := msg
	monitorID, err := w.monitor.Insert(ctx, repository.MonitorOperacaoInsert{
		TenantID: domain.MonitorOperacaoTenantPlataformaID,
		UserID:   nil,
		Origem:   domain.MonitorOperacaoOrigemAutomatico,
		Tipo:     domain.MonitorOperacaoTipoWorkerCompromissosMensal,
		Status:   status,
		Mensagem: &m,
		Detalhe:  det,
	})
	if err != nil {
		return
	}
	_ = w.monitor.InsertCompromissosRefs(ctx, monitorID, compromissoIDs)
}
