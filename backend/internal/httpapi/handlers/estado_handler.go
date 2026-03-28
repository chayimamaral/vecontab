package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/httpapi/render"
	"github.com/chayimamaral/vecontab/backend/internal/repository"
	"github.com/chayimamaral/vecontab/backend/internal/service"
)

type EstadoHandler struct {
	service *service.EstadoService
}

type estadoEnvelope struct {
	Params struct {
		ID    string `json:"id"`
		Nome  string `json:"nome"`
		Sigla string `json:"sigla"`
	} `json:"params"`
}

type filtersPayload struct {
	Nome struct {
		Value string `json:"value"`
	} `json:"nome"`
}

func NewEstadoHandler(service *service.EstadoService) *EstadoHandler {
	return &EstadoHandler{service: service}
}

func (h *EstadoHandler) List(w http.ResponseWriter, r *http.Request) {
	params := repository.EstadoListParams{
		First:     parseInt(r.URL.Query().Get("first"), 0),
		Rows:      parseInt(r.URL.Query().Get("rows"), 25),
		SortField: r.URL.Query().Get("sortField"),
		SortOrder: parseInt(r.URL.Query().Get("sortOrder"), 1),
		Nome:      parseNomeFilter(r.URL.Query().Get("filters")),
	}

	response, err := h.service.List(r.Context(), params)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *EstadoHandler) Create(w http.ResponseWriter, r *http.Request) {
	var payload estadoEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if payload.Params.Nome == "" || payload.Params.Sigla == "" {
		render.WriteError(w, http.StatusBadRequest, "Nome e Sigla sao obrigatorios")
		return
	}

	response, err := h.service.Create(r.Context(), payload.Params.Nome, payload.Params.Sigla)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *EstadoHandler) Update(w http.ResponseWriter, r *http.Request) {
	var payload estadoEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if payload.Params.ID == "" || payload.Params.Nome == "" || payload.Params.Sigla == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar todos os dados!")
		return
	}

	response, err := h.service.Update(r.Context(), payload.Params.ID, payload.Params.Nome, payload.Params.Sigla)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *EstadoHandler) Delete(w http.ResponseWriter, r *http.Request) {
	var payload estadoEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if payload.Params.ID == "" {
		render.WriteError(w, http.StatusBadRequest, "ID e obrigatorio")
		return
	}

	response, err := h.service.Delete(r.Context(), payload.Params.ID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *EstadoHandler) ListLite(w http.ResponseWriter, r *http.Request) {
	response, err := h.service.ListLite(r.Context())
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func parseInt(value string, fallback int) int {
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}

	return parsed
}

func parseNomeFilter(raw string) string {
	if strings.TrimSpace(raw) == "" {
		return ""
	}

	var payload filtersPayload
	if err := json.Unmarshal([]byte(raw), &payload); err == nil {
		return payload.Nome.Value
	}

	return ""
}
