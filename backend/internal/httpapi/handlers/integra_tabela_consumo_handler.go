package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/httpapi/middleware"
	"github.com/chayimamaral/vecontab/backend/internal/httpapi/render"
	"github.com/chayimamaral/vecontab/backend/internal/service"
)

type IntegraTabelaConsumoHandler struct {
	service *service.IntegraTabelaConsumoService
}

type integraTabelaConsumoEnvelope struct {
	Params service.IntegraTabelaConsumoInput `json:"params"`
}

func NewIntegraTabelaConsumoHandler(s *service.IntegraTabelaConsumoService) *IntegraTabelaConsumoHandler {
	return &IntegraTabelaConsumoHandler{service: s}
}

func (h *IntegraTabelaConsumoHandler) ListFaixas(w http.ResponseWriter, r *http.Request) {
	tipo := strings.TrimSpace(r.URL.Query().Get("tipo"))
	items, err := h.service.ListFaixas(r.Context(), tipo)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, map[string]any{
		"faixas":       items,
		"totalRecords": len(items),
	})
}

func (h *IntegraTabelaConsumoHandler) CreateFaixa(w http.ResponseWriter, r *http.Request) {
	var payload integraTabelaConsumoEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}
	out, err := h.service.CreateFaixa(r.Context(), payload.Params)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, map[string]any{"faixa": out})
}

func (h *IntegraTabelaConsumoHandler) UpdateFaixa(w http.ResponseWriter, r *http.Request) {
	var payload integraTabelaConsumoEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}
	out, err := h.service.UpdateFaixa(r.Context(), payload.Params)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, map[string]any{"faixa": out})
}

func (h *IntegraTabelaConsumoHandler) DeleteFaixa(w http.ResponseWriter, r *http.Request) {
	var payload integraTabelaConsumoEnvelope
	_ = json.NewDecoder(r.Body).Decode(&payload)
	id := strings.TrimSpace(payload.Params.ID)
	if id == "" {
		id = strings.TrimSpace(r.URL.Query().Get("id"))
	}
	if err := h.service.DeleteFaixa(r.Context(), id); err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, map[string]any{"success": true})
}

func (h *IntegraTabelaConsumoHandler) ListGastos(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.TenantID(r.Context())
	empresaDocumento := strings.TrimSpace(r.URL.Query().Get("empresa_documento"))
	tipo := strings.TrimSpace(r.URL.Query().Get("tipo"))
	items, err := h.service.ListGastos(r.Context(), tenantID, empresaDocumento, tipo)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	totalValor := 0.0
	totalQuantidade := 0
	for _, item := range items {
		totalValor += item.ValorTotal
		totalQuantidade += item.Quantidade
	}
	render.WriteJSON(w, http.StatusOK, map[string]any{
		"gastos":           items,
		"totalRecords":     len(items),
		"total_valor":      totalValor,
		"total_quantidade": totalQuantidade,
	})
}
