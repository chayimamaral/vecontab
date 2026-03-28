package handlers

import (
	"net/http"

	"github.com/chayimamaral/mare/backend/internal/httpapi/render"
)

func NotImplemented(route string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		render.WriteJSON(w, http.StatusNotImplemented, map[string]any{
			"error":   "rota ainda nao portada para Go",
			"route":   route,
			"method":  r.Method,
			"backend": "backendgo",
		})
	}
}
