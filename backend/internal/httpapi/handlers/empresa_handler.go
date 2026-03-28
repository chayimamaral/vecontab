package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/httpapi/middleware"
	"github.com/chayimamaral/vecontab/backend/internal/httpapi/render"
	"github.com/chayimamaral/vecontab/backend/internal/repository"
	"github.com/chayimamaral/vecontab/backend/internal/service"
)

type EmpresaHandler struct {
	service *service.EmpresaService
}

type empresaEnvelope struct {
	Params struct {
		ID        string `json:"id"`
		Nome      string `json:"nome"`
		Municipio struct {
			ID string `json:"id"`
		} `json:"municipio"`
		TenantID string `json:"tenantid"`
		Rotina   struct {
			ID string `json:"id"`
		} `json:"rotina"`
		Cnaes any `json:"cnaes"`
	} `json:"params"`
}

func NewEmpresaHandler(service *service.EmpresaService) *EmpresaHandler {
	return &EmpresaHandler{service: service}
}

func (h *EmpresaHandler) List(w http.ResponseWriter, r *http.Request) {
	params := repository.EmpresaListParams{
		First:     parseIntEmpresa(r.URL.Query().Get("first"), 0),
		Rows:      parseIntEmpresa(r.URL.Query().Get("rows"), 25),
		SortField: r.URL.Query().Get("sortField"),
		SortOrder: parseIntEmpresa(r.URL.Query().Get("sortOrder"), 1),
		Nome:      parseNomeFilterEmpresa(r.URL.Query().Get("filters")),
		TenantID:  middleware.TenantID(r.Context()),
	}

	response, err := h.service.List(r.Context(), params)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *EmpresaHandler) Create(w http.ResponseWriter, r *http.Request) {
	var payload empresaEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	tenantID := middleware.TenantID(r.Context())
	if payload.Params.Nome == "" || payload.Params.Municipio.ID == "" || tenantID == "" || payload.Params.Rotina.ID == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar todos os dados!")
		return
	}

	response, err := h.service.Create(r.Context(), service.EmpresaInput{
		Nome:        payload.Params.Nome,
		MunicipioID: payload.Params.Municipio.ID,
		TenantID:    tenantID,
		RotinaID:    payload.Params.Rotina.ID,
		Cnaes:       payload.Params.Cnaes,
	})
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *EmpresaHandler) Update(w http.ResponseWriter, r *http.Request) {
	var payload empresaEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if payload.Params.Nome == "" || payload.Params.Municipio.ID == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar todos os dados!")
		return
	}

	response, err := h.service.Update(r.Context(), service.EmpresaInput{
		ID:          payload.Params.ID,
		Nome:        payload.Params.Nome,
		MunicipioID: payload.Params.Municipio.ID,
		TenantID:    middleware.TenantID(r.Context()),
		RotinaID:    payload.Params.Rotina.ID,
		Cnaes:       payload.Params.Cnaes,
	})
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *EmpresaHandler) IniciarProcesso(w http.ResponseWriter, r *http.Request) {
	var payload empresaEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	id := strings.TrimSpace(payload.Params.ID)
	if id == "" {
		render.WriteError(w, http.StatusBadRequest, "Id nao informado")
		return
	}

	response, err := h.service.IniciarProcesso(r.Context(), id, middleware.TenantID(r.Context()))
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *EmpresaHandler) Delete(w http.ResponseWriter, r *http.Request) {
	var payload empresaEnvelope
	_ = json.NewDecoder(r.Body).Decode(&payload)
	id := strings.TrimSpace(payload.Params.ID)
	if id == "" {
		id = strings.TrimSpace(r.URL.Query().Get("id"))
	}

	if id == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar o id!")
		return
	}

	response, err := h.service.Delete(r.Context(), id, middleware.TenantID(r.Context()))
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func parseIntEmpresa(value string, fallback int) int {
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func parseNomeFilterEmpresa(raw string) string {
	type filtersPayload struct {
		Nome struct {
			Value string `json:"value"`
		} `json:"nome"`
	}

	if strings.TrimSpace(raw) == "" {
		return ""
	}

	var payload filtersPayload
	if err := json.Unmarshal([]byte(raw), &payload); err == nil {
		return payload.Nome.Value
	}

	return ""
}
