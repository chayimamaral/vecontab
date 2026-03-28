package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/httpapi/middleware"
	"github.com/chayimamaral/vecontab/backend/internal/httpapi/render"
	"github.com/chayimamaral/vecontab/backend/internal/service"
)

type AgendaHandler struct {
	service *service.AgendaService
}

type agendaConcluirPassoPayload struct {
	AgendaID     string `json:"agenda_id"`
	AgendaItemID string `json:"agenda_item_id"`
}

func NewAgendaHandler(service *service.AgendaService) *AgendaHandler {
	return &AgendaHandler{service: service}
}

func (h *AgendaHandler) List(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.TenantID(r.Context())
	response, err := h.service.List(r.Context(), tenantID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *AgendaHandler) Detail(w http.ResponseWriter, r *http.Request) {
	agendaID := strings.TrimSpace(r.URL.Query().Get("agenda_id"))
	response, err := h.service.Detail(r.Context(), middleware.TenantID(r.Context()), agendaID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *AgendaHandler) ConcluirPasso(w http.ResponseWriter, r *http.Request) {
	var payload agendaConcluirPassoPayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	payload.AgendaID = strings.TrimSpace(payload.AgendaID)
	payload.AgendaItemID = strings.TrimSpace(payload.AgendaItemID)
	if payload.AgendaID == "" || payload.AgendaItemID == "" {
		render.WriteError(w, http.StatusBadRequest, "agenda_id e agenda_item_id sao obrigatorios")
		return
	}

	response, err := h.service.ConcluirPasso(r.Context(), middleware.TenantID(r.Context()), payload.AgendaID, payload.AgendaItemID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}
