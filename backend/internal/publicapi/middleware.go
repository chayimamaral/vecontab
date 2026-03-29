package publicapi

import (
	"crypto/subtle"
	"net/http"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/config"
	"github.com/gin-gonic/gin"
)

const headerAPIKey = "X-API-Key"

// RequireAPIKey valida o header X-API-Key contra config.PublicAPIKey (comparação em tempo constante quando os tamanhos coincidem).
func RequireAPIKey(cfg config.Config) gin.HandlerFunc {
	expected := strings.TrimSpace(cfg.PublicAPIKey)
	return func(c *gin.Context) {
		if expected == "" {
			c.AbortWithStatusJSON(http.StatusServiceUnavailable, gin.H{
				"error": "public API desabilitada: defina PUBLIC_API_KEY",
			})
			return
		}
		got := strings.TrimSpace(c.GetHeader(headerAPIKey))
		if len(got) != len(expected) || subtle.ConstantTimeCompare([]byte(got), []byte(expected)) != 1 {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": "API key inválida ou ausente",
			})
			return
		}
		c.Next()
	}
}
