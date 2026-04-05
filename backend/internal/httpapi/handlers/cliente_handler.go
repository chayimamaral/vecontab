package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/httpapi/middleware"
	"github.com/chayimamaral/vecontab/backend/internal/httpapi/render"
	"github.com/chayimamaral/vecontab/backend/internal/service"
)

type ClienteHandler struct {
	service *service.ClienteService
}

func NewClienteHandler(svc *service.ClienteService) *ClienteHandler {
	return &ClienteHandler{service: svc}
}

func (h *ClienteHandler) List(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.TenantID(r.Context())
	if strings.TrimSpace(tenantID) == "" {
		render.WriteError(w, http.StatusUnauthorized, "tenant nao identificado")
		return
	}

	limit := parseClienteInt(r.URL.Query().Get("limit"), 500)
	offset := parseClienteInt(r.URL.Query().Get("offset"), 0)

	response, err := h.service.List(r.Context(), tenantID, limit, offset)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func parseClienteInt(value string, fallback int) int {
	parsed, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil {
		return fallback
	}
	return parsed
}
