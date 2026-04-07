package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/httpapi/middleware"
	"github.com/chayimamaral/vecontab/backend/internal/httpapi/render"
	"github.com/chayimamaral/vecontab/backend/internal/service"
)

type TenantHandler struct {
	service *service.TenantService
}

type tenantCreatePayload struct {
	Nome    string `json:"nome"`
	Contato string `json:"contato"`
}

type tenantUpdatePayload struct {
	ID      string `json:"id"`
	Nome    string `json:"nome"`
	Active  bool   `json:"active"`
	Contato string `json:"contato"`
	Plano   string `json:"plano"`
}

type tenantDetailPayload struct {
	ID string `json:"id"`
}

func NewTenantHandler(service *service.TenantService) *TenantHandler {
	return &TenantHandler{service: service}
}

func (h *TenantHandler) Create(w http.ResponseWriter, r *http.Request) {
	var payload tenantCreatePayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if strings.TrimSpace(payload.Nome) == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar a Empresa!")
		return
	}

	response, err := h.service.Create(r.Context(), payload.Nome, payload.Contato)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *TenantHandler) Detail(w http.ResponseWriter, r *http.Request) {
	role := middleware.Role(r.Context())
	contextTenantID := middleware.TenantID(r.Context())

	id := strings.TrimSpace(r.URL.Query().Get("id"))
	if id == "" {
		var payload tenantDetailPayload
		if err := json.NewDecoder(r.Body).Decode(&payload); err == nil {
			id = strings.TrimSpace(payload.ID)
		}
	}

	if role != "SUPER" {
		id = contextTenantID
	}

	if id == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar o id do tenant")
		return
	}

	response, err := h.service.Detail(r.Context(), id)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *TenantHandler) Update(w http.ResponseWriter, r *http.Request) {
	role := middleware.Role(r.Context())
	contextTenantID := middleware.TenantID(r.Context())

	var payload tenantUpdatePayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if role != "SUPER" {
		payload.ID = contextTenantID
	}

	if payload.ID == "" || strings.TrimSpace(payload.Nome) == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar todos os dados!")
		return
	}

	payload.Plano = strings.ToUpper(strings.TrimSpace(payload.Plano))
	if role != "SUPER" {
		payload.Plano = ""
	}

	response, err := h.service.Update(r.Context(), payload.ID, payload.Nome, payload.Contato, payload.Plano, payload.Active)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *TenantHandler) List(w http.ResponseWriter, r *http.Request) {
	role := middleware.Role(r.Context())
	tenantID := middleware.TenantID(r.Context())

	response, err := h.service.List(r.Context(), role, tenantID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}
