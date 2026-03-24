package httpapi

import (
	"net/http"

	"github.com/chayimamaral/vecontab/backendgo/internal/auth"
	"github.com/chayimamaral/vecontab/backendgo/internal/config"
	"github.com/chayimamaral/vecontab/backendgo/internal/httpapi/handlers"
	apiMiddleware "github.com/chayimamaral/vecontab/backendgo/internal/httpapi/middleware"
	"github.com/chayimamaral/vecontab/backendgo/internal/httpapi/render"
	"github.com/chayimamaral/vecontab/backendgo/internal/repository"
	"github.com/chayimamaral/vecontab/backendgo/internal/service"
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
	feriadoService := service.NewFeriadoService(repository.NewFeriadoRepository(pool))
	empresaService := service.NewEmpresaService(repository.NewEmpresaRepository(pool))
	cnaeService := service.NewCnaeService(repository.NewCnaeRepository(pool))
	agendaService := service.NewAgendaService(repository.NewAgendaRepository(pool))
	rotinaService := service.NewRotinaService(repository.NewRotinaRepository(pool))
	registroService := service.NewRegistroService(repository.NewRegistroRepository(pool))
	nodeService := service.NewNodeService(repository.NewNodeRepository(pool))

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
	agendaHandler := handlers.NewAgendaHandler(agendaService)
	rotinaHandler := handlers.NewRotinaHandler(rotinaService)
	registroHandler := handlers.NewRegistroHandler(registroService)
	nodeHandler := handlers.NewNodeHandler(nodeService)
	requireAuth := apiMiddleware.RequireAuth(tokenService)
	requireAdmin := apiMiddleware.RequireAnyRole("ADMIN", "SUPER")
	requireSuper := apiMiddleware.RequireAnyRole("SUPER")

	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		render.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	registerRoutes(r, authHandler, userHandler, estadoHandler, cidadeHandler, tenantHandler, tipoEmpresaHandler, passoHandler, grupoPassosHandler, feriadoHandler, empresaHandler, cnaeHandler, agendaHandler, rotinaHandler, registroHandler, nodeHandler, requireAuth, requireAdmin, requireSuper)
	r.Route("/api", func(api chi.Router) {
		registerRoutes(api, authHandler, userHandler, estadoHandler, cidadeHandler, tenantHandler, tipoEmpresaHandler, passoHandler, grupoPassosHandler, feriadoHandler, empresaHandler, cnaeHandler, agendaHandler, rotinaHandler, registroHandler, nodeHandler, requireAuth, requireAdmin, requireSuper)
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
	cnaeHandler *handlers.CnaeHandler,
	agendaHandler *handlers.AgendaHandler,
	rotinaHandler *handlers.RotinaHandler,
	registroHandler *handlers.RegistroHandler,
	nodeHandler *handlers.NodeHandler,
	requireAuth func(http.Handler) http.Handler,
	requireAdmin func(http.Handler) http.Handler,
	requireSuper func(http.Handler) http.Handler,
) {
	r.Post("/registro", registroHandler.Create)
	r.With(requireAuth).Put("/registro", registroHandler.Update)
	r.With(requireAuth).Get("/registro", registroHandler.Detail)

	r.With(requireAuth, requireSuper).Post("/tenant", tenantHandler.Create)
	r.With(requireAuth).Get("/tenant", tenantHandler.Detail)
	r.With(requireAuth, requireAdmin).Put("/tenant", tenantHandler.Update)
	r.With(requireAuth).Get("/tenants", tenantHandler.List)

	r.Post("/session", authHandler.Login)
	r.With(requireAuth).Get("/me", userHandler.Me)
	r.With(requireAuth).Get("/usuarios", userHandler.List)
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
	r.With(requireAuth, requireAdmin).Post("/rotina", rotinaHandler.Create)
	r.With(requireAuth, requireAdmin).Put("/deleterotina", rotinaHandler.Delete)
	r.With(requireAuth, requireAdmin).Put("/rotina", rotinaHandler.Update)
	r.With(requireAuth).Get("/rotinaitens", rotinaHandler.RotinaItens)
	r.With(requireAuth, requireAdmin).Get("/rotinaitemcreate", rotinaHandler.RotinaItemCreate)
	r.With(requireAuth, requireAdmin).Get("/rotinaitemupdate", rotinaHandler.RotinaItemUpdate)
	r.With(requireAuth, requireAdmin).Get("/rotinaitemdelete", rotinaHandler.RotinaItemDelete)
	r.With(requireAuth).Get("/listrotinas", rotinaHandler.ListRotinas)
	r.With(requireAuth, requireAdmin).Put("/salvarselecao", rotinaHandler.SaveSelectedItens)
	r.With(requireAuth).Get("/listrotinaslite", rotinaHandler.ListLite)
	r.With(requireAuth).Get("/listrotinaitensselected", rotinaHandler.ListSelectedItens)
	r.With(requireAuth, requireAdmin).Put("/removepassoselecionado", rotinaHandler.RemoveSelectedItens)

	r.With(requireAuth).Get("/feriados", feriadoHandler.List)
	r.With(requireAuth, requireAdmin).Post("/feriado", feriadoHandler.Create)
	r.With(requireAuth, requireAdmin).Put("/feriado", feriadoHandler.Update)
	r.With(requireAuth, requireAdmin).Put("/deleteferiado", feriadoHandler.Delete)

	r.With(requireAuth).Get("/empresas", empresaHandler.List)
	r.With(requireAuth, requireAdmin).Post("/empresa", empresaHandler.Create)
	r.With(requireAuth, requireAdmin).Put("/updateempresa", empresaHandler.Update)
	r.With(requireAuth, requireAdmin).Put("/deleteempresa", empresaHandler.Delete)
	r.With(requireAuth, requireAdmin).Put("/iniciarprocesso", empresaHandler.IniciarProcesso)

	r.With(requireAuth).Get("/cnaes", cnaeHandler.List)
	r.With(requireAuth, requireAdmin).Post("/cnae", cnaeHandler.Create)
	r.With(requireAuth, requireAdmin).Put("/cnae", cnaeHandler.Update)
	r.With(requireAuth, requireAdmin).Put("/deletecnae", cnaeHandler.Delete)
	r.With(requireAuth).Get("/cnaelite", cnaeHandler.Lite)
	r.With(requireAuth).Post("/validacnae", cnaeHandler.Validate)

	r.With(requireAuth).Get("/agendalist", agendaHandler.List)
	r.With(requireAuth).Get("/agendadetalhes", agendaHandler.Detail)
	r.With(requireAuth).Post("/agenda/concluir-passo", agendaHandler.ConcluirPasso)
}
