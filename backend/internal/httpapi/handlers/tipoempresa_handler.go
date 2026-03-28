package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"github.com/chayimamaral/mare/backend/internal/httpapi/render"
	"github.com/chayimamaral/mare/backend/internal/repository"
	"github.com/chayimamaral/mare/backend/internal/service"
)

type TipoEmpresaHandler struct {
	service *service.TipoEmpresaService
}

type tipoEmpresaEnvelope struct {
	Params struct {
		ID        string  `json:"id"`
		Descricao string  `json:"descricao"`
		Capital   float64 `json:"capital"`
		Anual     float64 `json:"anual"`
	} `json:"params"`
}

func NewTipoEmpresaHandler(service *service.TipoEmpresaService) *TipoEmpresaHandler {
	return &TipoEmpresaHandler{service: service}
}

func (h *TipoEmpresaHandler) List(w http.ResponseWriter, r *http.Request) {
	params := repository.TipoEmpresaListParams{
		First:     parseIntTipoEmpresa(r.URL.Query().Get("first"), 0),
		Rows:      parseIntTipoEmpresa(r.URL.Query().Get("rows"), 25),
		SortField: r.URL.Query().Get("sortField"),
		SortOrder: parseIntTipoEmpresa(r.URL.Query().Get("sortOrder"), 1),
		Descricao: parseDescricaoFilterTipoEmpresa(r.URL.Query().Get("filters")),
	}

	response, err := h.service.List(r.Context(), params)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *TipoEmpresaHandler) Create(w http.ResponseWriter, r *http.Request) {
	var payload tipoEmpresaEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if payload.Params.Descricao == "" {
		render.WriteError(w, http.StatusBadRequest, "Descricao e obrigatoria")
		return
	}

	response, err := h.service.Create(r.Context(), payload.Params.Descricao, payload.Params.Capital, payload.Params.Anual)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *TipoEmpresaHandler) Update(w http.ResponseWriter, r *http.Request) {
	var payload tipoEmpresaEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if payload.Params.ID == "" {
		render.WriteError(w, http.StatusBadRequest, "ID e obrigatorio")
		return
	}

	response, err := h.service.Update(r.Context(), payload.Params.ID, payload.Params.Descricao, payload.Params.Capital, payload.Params.Anual)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *TipoEmpresaHandler) Delete(w http.ResponseWriter, r *http.Request) {
	var payload tipoEmpresaEnvelope
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

func (h *TipoEmpresaHandler) Lite(w http.ResponseWriter, r *http.Request) {
	response, err := h.service.Lite(r.Context())
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func parseIntTipoEmpresa(value string, fallback int) int {
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}

	return parsed
}

func parseDescricaoFilterTipoEmpresa(raw string) string {
	if strings.TrimSpace(raw) == "" {
		return ""
	}

	type filtersPayload struct {
		Descricao struct {
			Value string `json:"value"`
		} `json:"descricao"`
	}

	var payload filtersPayload
	if err := json.Unmarshal([]byte(raw), &payload); err == nil {
		return payload.Descricao.Value
	}

	return ""
}
