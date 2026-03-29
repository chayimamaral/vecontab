package publicapi

import (
	"github.com/chayimamaral/vecontab/backend/internal/config"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

// NewRouter monta o sub-roteador Gin da Public API (sem prefixo /v1/public — use Mount no Chi).
func NewRouter(cfg config.Config, pool *pgxpool.Pool) *gin.Engine {
	gin.SetMode(gin.ReleaseMode)

	engine := gin.New()
	engine.Use(gin.Recovery())
	engine.Use(RequireAPIKey(cfg))

	repo := NewRepository(pool)
	h := NewHandler(repo)

	engine.GET("/rotinas/:municipio_id/:tipo_empresa_id", h.GetRotinas)

	return engine
}
