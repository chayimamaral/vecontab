package httpapi

import (
	"net/http"

	"github.com/chayimamaral/vecontab/backend/internal/auth"
	"github.com/chayimamaral/vecontab/backend/internal/config"
	"github.com/chayimamaral/vecontab/backend/internal/httpapi/handlers"
	apiMiddleware "github.com/chayimamaral/vecontab/backend/internal/httpapi/middleware"
	"github.com/chayimamaral/vecontab/backend/internal/httpapi/render"
	"github.com/chayimamaral/vecontab/backend/internal/repository"
	"github.com/chayimamaral/vecontab/backend/internal/service"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"
)

func NewRouter(cfg config.Config, pool *pgxpool.Pool) http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(apiMiddleware.CORS)

	tokenService := auth.NewTokenService(cfg.JWTSecret)
	authService := service.NewAuthService(repository.NewUserRepository(pool), tokenService)
	userService := service.NewUserService(repository.NewUserRepository(pool))
	estadoService := service.NewEstadoService(repository.NewEstadoRepository(pool))
	cidadeService := service.NewCidadeService(repository.NewCidadeRepository(pool))
	tenantService := service.NewTenantService(repository.NewTenantRepository(pool))
	tipoEmpresaService := service.NewTipoEmpresaService(repository.NewTipoEmpresaRepository(pool))
	passoService := service.NewPassoService(repository.NewPassoRepository(pool))
	grupoPassosService := service.NewGrupoPassosService(repository.NewGrupoPassosRepository(pool))
	empresaRepo := repository.NewEmpresaRepository(pool)
	feriadoRepo := repository.NewFeriadoRepository(pool)
	feriadoService := service.NewFeriadoService(feriadoRepo)
	empresaService := service.NewEmpresaService(empresaRepo)
	cnaeService := service.NewCnaeService(repository.NewCnaeRepository(pool))
	regimeTributarioService := service.NewRegimeTributarioService(repository.NewRegimeTributarioRepository(pool))
	agendaService := service.NewAgendaService(repository.NewAgendaRepository(pool))
	rotinaService := service.NewRotinaService(repository.NewRotinaRepository(pool))
	registroService := service.NewRegistroService(repository.NewRegistroRepository(pool))
	nodeService := service.NewNodeService(repository.NewNodeRepository(pool))
	obrigacaoService := service.NewObrigacaoService(repository.NewObrigacaoRepository(pool))
	empresaAgendaService := service.NewEmpresaAgendaService(
		repository.NewEmpresaAgendaRepository(pool),
		feriadoRepo,
		empresaRepo,
	)
	empresaCompromissoService := service.NewEmpresaCompromissoService(
		repository.NewEmpresaCompromissoRepository(pool),
		feriadoRepo,
		empresaRepo,
	)
	empresaDadosService := service.NewEmpresaDadosService(repository.NewEmpresaDadosRepository(pool))
	clienteService := service.NewClienteService(repository.NewClienteRepository(pool))
	monitorOperacaoRepo := repository.NewMonitorOperacaoRepository(pool)
	monitorOperacaoService := service.NewMonitorOperacaoService(monitorOperacaoRepo)
	rotinaPFService := service.NewRotinaPFService(repository.NewRotinaPFRepository(pool))
	configuracaoIntegracaoRepo := repository.NewConfiguracaoIntegracaoRepository(pool)
	configuracaoIntegracaoService := service.NewConfiguracaoIntegracaoService(configuracaoIntegracaoRepo)
	certificadoService, _ := service.NewCertificadoService(
		repository.NewCertificadoRepository(pool),
		repository.NewCertificadoClienteRepository(pool),
		cfg.CertCryptoKeyHex,
	)
	catalogoServicoService := service.NewCatalogoServicoService(repository.NewCatalogoServicoRepository(pool))
	integraServicoProcRepo := repository.NewIntegraContadorServicoProcuracaoRepository(pool)
	integraContadorService := service.NewIntegraContadorService(certificadoService, configuracaoIntegracaoRepo, integraServicoProcRepo)
	integraServicoProcService := service.NewIntegraContadorServicoProcuracaoService(integraServicoProcRepo)

	authHandler := handlers.NewAuthHandler(authService)
	userHandler := handlers.NewUserHandler(userService)
	estadoHandler := handlers.NewEstadoHandler(estadoService)
	cidadeHandler := handlers.NewCidadeHandler(cidadeService)
	tenantHandler := handlers.NewTenantHandler(tenantService)
	tipoEmpresaHandler := handlers.NewTipoEmpresaHandler(tipoEmpresaService)
	passoHandler := handlers.NewPassoHandler(passoService)
	grupoPassosHandler := handlers.NewGrupoPassosHandler(grupoPassosService)
	feriadoHandler := handlers.NewFeriadoHandler(feriadoService)
	empresaHandler := handlers.NewEmpresaHandler(empresaService)
	cnaeHandler := handlers.NewCnaeHandler(cnaeService)
	regimeTributarioHandler := handlers.NewRegimeTributarioHandler(regimeTributarioService)
	agendaHandler := handlers.NewAgendaHandler(agendaService)
	rotinaHandler := handlers.NewRotinaHandler(rotinaService)
	registroHandler := handlers.NewRegistroHandler(registroService)
	nodeHandler := handlers.NewNodeHandler(nodeService)
	obrigacaoHandler := handlers.NewObrigacaoHandler(obrigacaoService)
	empresaAgendaHandler := handlers.NewEmpresaAgendaHandler(empresaAgendaService, monitorOperacaoService)
	empresaCompromissoHandler := handlers.NewEmpresaCompromissoHandler(empresaCompromissoService, monitorOperacaoService)
	monitorOperacaoHandler := handlers.NewMonitorOperacaoHandler(monitorOperacaoService)
	empresaDadosHandler := handlers.NewEmpresaDadosHandler(empresaDadosService)
	clienteHandler := handlers.NewClienteHandler(clienteService)
	rotinaPFHandler := handlers.NewRotinaPFHandler(rotinaPFService)
	configuracaoIntegracaoHandler := handlers.NewConfiguracaoIntegracaoHandler(configuracaoIntegracaoService, certificadoService)
	certificadoClienteHandler := handlers.NewCertificadoClienteHandler(certificadoService)
	catalogoServicoHandler := handlers.NewCatalogoServicoHandler(catalogoServicoService)
	integraContadorHandler := handlers.NewIntegraContadorHandler(integraContadorService)
	integraServicoProcHandler := handlers.NewIntegraContadorServicoProcuracaoHandler(integraServicoProcService)
	requireAuth := apiMiddleware.RequireAuth(tokenService)
	requireAdmin := apiMiddleware.RequireAnyRole("ADMIN", "SUPER")
	requireAdminOnly := apiMiddleware.RequireAnyRole("ADMIN")
	requireAdminOrUser := apiMiddleware.RequireAnyRole("ADMIN", "USER")
	requireSuper := apiMiddleware.RequireAnyRole("SUPER")

	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		render.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	registerRoutes(r, authHandler, userHandler, estadoHandler, cidadeHandler, tenantHandler, tipoEmpresaHandler, passoHandler, grupoPassosHandler, feriadoHandler, empresaHandler, empresaDadosHandler, cnaeHandler, regimeTributarioHandler, agendaHandler, rotinaHandler, rotinaPFHandler, registroHandler, nodeHandler, obrigacaoHandler, empresaAgendaHandler, empresaCompromissoHandler, clienteHandler, monitorOperacaoHandler, configuracaoIntegracaoHandler, certificadoClienteHandler, catalogoServicoHandler, integraContadorHandler, integraServicoProcHandler, requireAuth, requireAdmin, requireAdminOnly, requireAdminOrUser, requireSuper)
	r.Route("/api", func(api chi.Router) {
		registerRoutes(api, authHandler, userHandler, estadoHandler, cidadeHandler, tenantHandler, tipoEmpresaHandler, passoHandler, grupoPassosHandler, feriadoHandler, empresaHandler, empresaDadosHandler, cnaeHandler, regimeTributarioHandler, agendaHandler, rotinaHandler, rotinaPFHandler, registroHandler, nodeHandler, obrigacaoHandler, empresaAgendaHandler, empresaCompromissoHandler, clienteHandler, monitorOperacaoHandler, configuracaoIntegracaoHandler, certificadoClienteHandler, catalogoServicoHandler, integraContadorHandler, integraServicoProcHandler, requireAuth, requireAdmin, requireAdminOnly, requireAdminOrUser, requireSuper)
	})

	return r
}

func registerRoutes(
	r chi.Router,
	authHandler *handlers.AuthHandler,
	userHandler *handlers.UserHandler,
	estadoHandler *handlers.EstadoHandler,
	cidadeHandler *handlers.CidadeHandler,
	tenantHandler *handlers.TenantHandler,
	tipoEmpresaHandler *handlers.TipoEmpresaHandler,
	passoHandler *handlers.PassoHandler,
	grupoPassosHandler *handlers.GrupoPassosHandler,
	feriadoHandler *handlers.FeriadoHandler,
	empresaHandler *handlers.EmpresaHandler,
	empresaDadosHandler *handlers.EmpresaDadosHandler,
	cnaeHandler *handlers.CnaeHandler,
	regimeTributarioHandler *handlers.RegimeTributarioHandler,
	agendaHandler *handlers.AgendaHandler,
	rotinaHandler *handlers.RotinaHandler,
	rotinaPFHandler *handlers.RotinaPFHandler,
	registroHandler *handlers.RegistroHandler,
	nodeHandler *handlers.NodeHandler,
	obrigacaoHandler *handlers.ObrigacaoHandler,
	empresaAgendaHandler *handlers.EmpresaAgendaHandler,
	empresaCompromissoHandler *handlers.EmpresaCompromissoHandler,
	clienteHandler *handlers.ClienteHandler,
	monitorOperacaoHandler *handlers.MonitorOperacaoHandler,
	configuracaoIntegracaoHandler *handlers.ConfiguracaoIntegracaoHandler,
	certificadoClienteHandler *handlers.CertificadoClienteHandler,
	catalogoServicoHandler *handlers.CatalogoServicoHandler,
	integraContadorHandler *handlers.IntegraContadorHandler,
	integraServicoProcHandler *handlers.IntegraContadorServicoProcuracaoHandler,
	requireAuth func(http.Handler) http.Handler,
	requireAdmin func(http.Handler) http.Handler,
	requireAdminOnly func(http.Handler) http.Handler,
	requireAdminOrUser func(http.Handler) http.Handler,
	requireSuper func(http.Handler) http.Handler,
) {
	r.Post("/registro", registroHandler.Create)
	r.With(requireAuth).Put("/registro", registroHandler.Update)
	r.With(requireAuth).Get("/registro", registroHandler.Detail)

	r.With(requireAuth, requireSuper).Post("/tenant", tenantHandler.Create)
	r.With(requireAuth).Get("/tenant", tenantHandler.Detail)
	r.With(requireAuth, requireAdmin).Put("/tenant", tenantHandler.Update)
	r.With(requireAuth).Get("/tenants", tenantHandler.List)
	r.With(requireAuth, requireSuper).Get("/tenant-dados", registroHandler.TenantDadosDetail)
	r.With(requireAuth, requireSuper).Put("/tenant-dados", registroHandler.TenantDadosUpdate)

	r.Post("/session", authHandler.Login)
	r.With(requireAuth).Get("/me", userHandler.Me)
	r.With(requireAuth, requireAdmin).Get("/usuarios", userHandler.List)
	r.With(requireAuth).Get("/usuariorole", userHandler.UserRole)
	r.With(requireAuth).Get("/usuariotenant", userHandler.TenantID)
	r.With(requireAuth, requireAdmin).Post("/usuario", userHandler.Create)
	r.With(requireAuth, requireAdmin).Put("/usuario", userHandler.Update)
	r.With(requireAuth, requireAdmin).Delete("/usuario", userHandler.Delete)

	r.With(requireAuth, requireAdmin).Post("/cidade", cidadeHandler.Create)
	r.With(requireAuth, requireAdmin).Put("/cidade", cidadeHandler.Update)
	r.With(requireAuth).Get("/cidades", cidadeHandler.List)
	r.With(requireAuth, requireAdmin).Delete("/cidade", cidadeHandler.Delete)
	r.With(requireAuth).Get("/cidadeslite", cidadeHandler.ListLite)

	r.With(requireAuth).Get("/estados", estadoHandler.List)
	r.With(requireAuth, requireAdmin).Post("/estado", estadoHandler.Create)
	r.With(requireAuth, requireAdmin).Put("/estado", estadoHandler.Update)
	r.With(requireAuth, requireAdmin).Put("/deleteestado", estadoHandler.Delete)
	r.With(requireAuth).Get("/ufscidade", estadoHandler.ListLite)

	r.With(requireAuth).Get("/node", nodeHandler.Nodes)
	r.With(requireAuth).Get("/family", nodeHandler.Family)
	r.With(requireAuth).Get("/recurso", nodeHandler.Recurso)

	r.With(requireAuth, requireAdmin).Post("/tipoempresa", tipoEmpresaHandler.Create)
	r.With(requireAuth, requireAdmin).Put("/deletetipoempresa", tipoEmpresaHandler.Delete)
	r.With(requireAuth, requireAdmin).Put("/tipoempresa", tipoEmpresaHandler.Update)
	r.With(requireAuth).Get("/tiposempresa", tipoEmpresaHandler.List)
	r.With(requireAuth).Get("/tiposempresalite", tipoEmpresaHandler.Lite)

	r.With(requireAuth, requireAdmin).Post("/passo", passoHandler.Create)
	r.With(requireAuth, requireAdmin).Put("/deletepasso", passoHandler.Delete)
	r.With(requireAuth, requireAdmin).Put("/passo", passoHandler.Update)
	r.With(requireAuth).Get("/passos", passoHandler.List)
	r.With(requireAuth).Get("/getPassoById", passoHandler.GetByID)
	r.With(requireAuth).Get("/passosporcidade", passoHandler.ListByCidade)

	r.With(requireAuth, requireAdmin).Post("/grupopassos", grupoPassosHandler.Create)
	r.With(requireAuth, requireAdmin).Put("/deletegrupopasso", grupoPassosHandler.Delete)
	r.With(requireAuth, requireAdmin).Put("/grupopasso", grupoPassosHandler.Update)
	r.With(requireAuth).Get("/grupopassos", grupoPassosHandler.List)
	r.With(requireAuth).Get("/getgrupopassobyid", grupoPassosHandler.GetByID)

	r.With(requireAuth).Get("/rotinas", rotinaHandler.List)
	r.With(requireAuth).Post("/rotina", rotinaHandler.Create)
	r.With(requireAuth).Put("/deleterotina", rotinaHandler.Delete)
	r.With(requireAuth).Put("/rotina", rotinaHandler.Update)
	r.With(requireAuth).Get("/rotinaitens", rotinaHandler.RotinaItens)
	r.With(requireAuth, requireAdmin).Get("/rotinaitemcreate", rotinaHandler.RotinaItemCreate)
	r.With(requireAuth, requireAdmin).Get("/rotinaitemupdate", rotinaHandler.RotinaItemUpdate)
	r.With(requireAuth, requireAdmin).Get("/rotinaitemdelete", rotinaHandler.RotinaItemDelete)
	r.With(requireAuth).Get("/listrotinas", rotinaHandler.ListRotinas)
	r.With(requireAuth, requireAdmin).Put("/salvarselecao", rotinaHandler.SaveSelectedItens)
	r.With(requireAuth).Get("/listrotinaslite", rotinaHandler.ListLite)
	r.With(requireAuth).Get("/listrotinapflite", rotinaPFHandler.ListLite)
	r.With(requireAuth).Get("/listrotinaspf", rotinaPFHandler.ListAdmin)
	r.With(requireAuth, requireAdmin).Post("/rotinapf", rotinaPFHandler.Create)
	r.With(requireAuth, requireAdmin).Put("/rotinapf", rotinaPFHandler.Update)
	r.With(requireAuth, requireAdmin).Put("/deleterotinapf", rotinaPFHandler.SoftDelete)
	r.With(requireAuth).Get("/rotinapfitens", rotinaPFHandler.ListItens)
	r.With(requireAuth, requireAdmin).Post("/rotinapfitem", rotinaPFHandler.CreateItem)
	r.With(requireAuth, requireAdmin).Put("/rotinapfitem", rotinaPFHandler.UpdateItem)
	r.With(requireAuth, requireAdmin).Put("/deleterotinapfitem", rotinaPFHandler.DeleteItem)
	r.With(requireAuth).Get("/listrotinaitensselected", rotinaHandler.ListSelectedItens)
	r.With(requireAuth, requireAdmin).Put("/removepassoselecionado", rotinaHandler.RemoveSelectedItens)

	r.With(requireAuth).Get("/feriados", feriadoHandler.List)
	r.With(requireAuth, requireAdmin).Post("/feriado", feriadoHandler.Create)
	r.With(requireAuth, requireAdmin).Put("/feriado", feriadoHandler.Update)
	r.With(requireAuth, requireAdmin).Put("/deleteferiado", feriadoHandler.Delete)

	r.With(requireAuth).Get("/empresas", empresaHandler.List)
	r.With(requireAuth).Get("/clientes", clienteHandler.List)
	r.With(requireAuth, requireAdminOnly).Post("/empresa", empresaHandler.Create)
	r.With(requireAuth, requireAdminOnly).Put("/updateempresa", empresaHandler.Update)
	r.With(requireAuth, requireAdminOnly).Put("/deleteempresa", empresaHandler.Delete)
	r.With(requireAuth, requireAdminOnly).Put("/iniciarprocesso", empresaHandler.IniciarProcesso)

	r.With(requireAuth).Get("/empresadados", empresaDadosHandler.Get)
	// ADMIN/USER: cadastro unificado de cliente (issue #59) grava empresa + clientes_dados.
	r.With(requireAuth, apiMiddleware.RequireAnyRole("ADMIN", "USER")).Put("/empresadados", empresaDadosHandler.Upsert)

	r.With(requireAuth).Get("/certificado-cliente", certificadoClienteHandler.Get)
	r.With(requireAuth, requireAdmin).Post("/certificado-cliente/upload", certificadoClienteHandler.Upload)

	r.With(requireAuth).Get("/cnaes", cnaeHandler.List)
	r.With(requireAuth, requireAdmin).Post("/cnae", cnaeHandler.Create)
	r.With(requireAuth, requireAdmin).Put("/cnae", cnaeHandler.Update)
	r.With(requireAuth, requireAdmin).Put("/deletecnae", cnaeHandler.Delete)
	r.With(requireAuth).Get("/cnaelite", cnaeHandler.Lite)
	r.With(requireAuth).Get("/cnaeresolve", cnaeHandler.ResolveIbge)
	r.With(requireAuth).Post("/validacnae", cnaeHandler.Validate)

	r.With(requireAuth).Get("/regimes-tributarios", regimeTributarioHandler.List)
	r.With(requireAuth, requireAdmin).Post("/regime-tributario", regimeTributarioHandler.Create)
	r.With(requireAuth, requireAdmin).Put("/regime-tributario", regimeTributarioHandler.Update)
	r.With(requireAuth, requireAdmin).Delete("/regime-tributario", regimeTributarioHandler.Delete)

	r.With(requireAuth).Get("/agendalist", agendaHandler.List)
	r.With(requireAuth).Get("/agendadetalhes", agendaHandler.Detail)
	r.With(requireAuth).Post("/agenda/concluir-passo", agendaHandler.ConcluirPasso)
	r.With(requireAuth).Post("/agenda/item", agendaHandler.CreateAgendaItem)
	r.With(requireAuth).Put("/agenda/item", agendaHandler.UpdateAgendaItem)
	r.With(requireAuth).Delete("/agenda/item", agendaHandler.DeleteAgendaItem)
	// Reabrir: mesmo payload que concluir; rota plana alinhada a /agendalist (aninhada mantida para simetria).
	r.With(requireAuth).Post("/agendareabrirpasso", agendaHandler.ReabrirPasso)
	r.With(requireAuth).Post("/agenda/reabrir-passo", agendaHandler.ReabrirPasso)

	r.With(requireAuth).Get("/obrigacoes", obrigacaoHandler.List)
	r.With(requireAuth, requireAdmin).Post("/obrigacao", obrigacaoHandler.Create)
	r.With(requireAuth, requireAdmin).Put("/obrigacao", obrigacaoHandler.Update)
	r.With(requireAuth, requireAdmin).Put("/deleteobrigacao", obrigacaoHandler.Delete)

	r.With(requireAuth).Get("/empresaagenda", empresaAgendaHandler.List)
	r.With(requireAuth).Get("/empresaagenda/acompanhamento", empresaAgendaHandler.Acompanhamento)
	r.With(requireAuth, requireAdmin).Post("/empresaagenda/gerar", empresaAgendaHandler.Gerar)
	r.With(requireAuth).Put("/empresaagenda/status", empresaAgendaHandler.UpdateStatus)
	r.With(requireAuth).Put("/empresaagenda/item", empresaAgendaHandler.UpdateItem)

	r.With(requireAuth).Get("/empresacompromissos/acompanhamento", empresaCompromissoHandler.Acompanhamento)
	r.With(requireAuth).Get("/empresacompromissos/form-options", empresaCompromissoHandler.FormOptions)
	r.With(requireAuth).Get("/empresacompromissos/obrigacoes", empresaCompromissoHandler.ObrigacoesByEmpresa)
	r.With(requireAuth, requireAdmin).Post("/empresacompromissos/gerar", empresaCompromissoHandler.Gerar)
	r.With(requireAuth, requireAdmin).Get("/monitor/operacoes", monitorOperacaoHandler.List)
	r.With(requireAuth).Post("/empresacompromissos/manual", empresaCompromissoHandler.CreateManual)
	r.With(requireAuth).Put("/empresacompromissos/status", empresaCompromissoHandler.UpdateStatus)
	r.With(requireAuth).Put("/empresacompromissos/item", empresaCompromissoHandler.UpdateItem)

	r.With(requireAuth, requireSuper).Get("/chavessuper", configuracaoIntegracaoHandler.GetChavesSuper)
	r.With(requireAuth, requireSuper).Put("/chavessuper", configuracaoIntegracaoHandler.SaveChavesSuper)
	r.With(requireAuth).Get("/tenant-configuracoes", configuracaoIntegracaoHandler.GetTenantConfiguracoes)
	r.With(requireAuth).Put("/tenant-configuracoes", configuracaoIntegracaoHandler.SaveTenantConfiguracoes)
	r.With(requireAuth).Get("/certificado-digital", configuracaoIntegracaoHandler.GetCertificadoDigital)
	r.With(requireAuth, requireAdmin).Post("/certificado-digital/upload", configuracaoIntegracaoHandler.UploadCertificadoDigital)
	r.With(requireAuth).Get("/catalogo-servicos", catalogoServicoHandler.List)
	r.With(requireAuth, requireSuper).Post("/catalogo-servico", catalogoServicoHandler.Create)
	r.With(requireAuth, requireSuper).Put("/catalogo-servico", catalogoServicoHandler.Update)
	r.With(requireAuth, requireSuper).Put("/deletecatalogo-servico", catalogoServicoHandler.Delete)

	r.With(requireAuth, apiMiddleware.RequireAnyRole("ADMIN", "SUPER")).Post("/integra-contador/autenticar", integraContadorHandler.Authenticate)
	r.With(requireAuth, apiMiddleware.RequireAnyRole("ADMIN", "SUPER")).Post("/integra-contador/chamar", integraContadorHandler.Call)
	r.With(requireAuth, apiMiddleware.RequireAnyRole("ADMIN", "SUPER")).Post("/integra-contador/pgmei/gerar-das", integraContadorHandler.PGMEIGerarDAS)
	r.With(requireAuth, apiMiddleware.RequireAnyRole("ADMIN", "SUPER")).Post("/integra-contador/pgmei/gerar-das-codigo-barras", integraContadorHandler.PGMEIGerarDASCodBarras)
	r.With(requireAuth, apiMiddleware.RequireAnyRole("ADMIN", "SUPER")).Post("/integra-contador/pgmei/atualizar-beneficio", integraContadorHandler.PGMEIAtualizarBeneficio)
	r.With(requireAuth, apiMiddleware.RequireAnyRole("ADMIN", "SUPER")).Post("/integra-contador/pgmei/consultar-divida-ativa", integraContadorHandler.PGMEIConsultarDividaAtiva)
	r.With(requireAuth, apiMiddleware.RequireAnyRole("ADMIN", "SUPER")).Get("/integra-contador/servicos-procuracao", integraServicoProcHandler.List)
}
