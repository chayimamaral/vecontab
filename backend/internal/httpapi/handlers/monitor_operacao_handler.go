package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/httpapi/middleware"
	"github.com/chayimamaral/vecontab/backend/internal/httpapi/render"
	"github.com/chayimamaral/vecontab/backend/internal/service"
)

type MonitorOperacaoHandler struct {
	svc *service.MonitorOperacaoService
}

func NewMonitorOperacaoHandler(svc *service.MonitorOperacaoService) *MonitorOperacaoHandler {
	return &MonitorOperacaoHandler{svc: svc}
}

func (h *MonitorOperacaoHandler) List(w http.ResponseWriter, r *http.Request) {
	role := strings.TrimSpace(strings.ToUpper(middleware.Role(r.Context())))
	tenantID := middleware.TenantID(r.Context())

	limit := 50
	if v := strings.TrimSpace(r.URL.Query().Get("limit")); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			limit = n
		}
	}
	offset := 0
	if v := strings.TrimSpace(r.URL.Query().Get("offset")); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			offset = n
		}
	}
	filtro := service.MonitorOperacaoListFilter{
		ClienteNome: strings.TrimSpace(r.URL.Query().Get("cliente_nome")),
		Status:      strings.TrimSpace(r.URL.Query().Get("status")),
		DataDeISO:   strings.TrimSpace(r.URL.Query().Get("data_de")),
		DataAteISO: strings.TrimSpace(r.URL.Query().Get("data_ate")),
	}

	resp, err := h.svc.ListPage(r.Context(), role, tenantID, limit, offset, filtro)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, resp)
}
