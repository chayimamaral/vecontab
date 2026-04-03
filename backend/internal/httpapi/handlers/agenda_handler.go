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

type agendaCreateItemPayload struct {
	AgendaID  string `json:"agenda_id"`
	Descricao string `json:"descricao"`
	Inicio    string `json:"inicio"`
	Termino   string `json:"termino"`
}

type agendaUpdateItemPayload struct {
	AgendaID     string  `json:"agenda_id"`
	AgendaItemID string  `json:"agenda_item_id"`
	Descricao    *string `json:"descricao"`
	Inicio       *string `json:"inicio"`
	Termino      *string `json:"termino"`
}

func (h *AgendaHandler) CreateAgendaItem(w http.ResponseWriter, r *http.Request) {
	var payload agendaCreateItemPayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}
	payload.AgendaID = strings.TrimSpace(payload.AgendaID)
	payload.Descricao = strings.TrimSpace(payload.Descricao)
	payload.Inicio = strings.TrimSpace(payload.Inicio)
	payload.Termino = strings.TrimSpace(payload.Termino)
	if payload.AgendaID == "" || payload.Descricao == "" || payload.Inicio == "" {
		render.WriteError(w, http.StatusBadRequest, "agenda_id, descricao e inicio sao obrigatorios")
		return
	}
	resp, err := h.service.CreateAgendaItem(r.Context(), middleware.TenantID(r.Context()), payload.AgendaID, payload.Descricao, payload.Inicio, payload.Termino)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusCreated, resp)
}

func (h *AgendaHandler) UpdateAgendaItem(w http.ResponseWriter, r *http.Request) {
	var payload agendaUpdateItemPayload
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
	if payload.Descricao != nil {
		t := strings.TrimSpace(*payload.Descricao)
		payload.Descricao = &t
	}
	if payload.Inicio != nil {
		t := strings.TrimSpace(*payload.Inicio)
		payload.Inicio = &t
	}
	if payload.Termino != nil {
		t := strings.TrimSpace(*payload.Termino)
		payload.Termino = &t
	}
	err := h.service.UpdateAgendaItem(r.Context(), middleware.TenantID(r.Context()), payload.AgendaID, payload.AgendaItemID, payload.Descricao, payload.Inicio, payload.Termino)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, map[string]string{"ok": "true"})
}

func (h *AgendaHandler) DeleteAgendaItem(w http.ResponseWriter, r *http.Request) {
	agendaID := strings.TrimSpace(r.URL.Query().Get("agenda_id"))
	itemID := strings.TrimSpace(r.URL.Query().Get("agenda_item_id"))
	if agendaID == "" || itemID == "" {
		render.WriteError(w, http.StatusBadRequest, "agenda_id e agenda_item_id sao obrigatorios")
		return
	}
	if err := h.service.DeleteAgendaItem(r.Context(), middleware.TenantID(r.Context()), agendaID, itemID); err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, map[string]string{"ok": "true"})
}

func (h *AgendaHandler) ReabrirPasso(w http.ResponseWriter, r *http.Request) {
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

	response, err := h.service.ReabrirPasso(r.Context(), middleware.TenantID(r.Context()), payload.AgendaID, payload.AgendaItemID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}
