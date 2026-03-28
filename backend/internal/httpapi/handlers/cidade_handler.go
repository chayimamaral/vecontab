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

type CidadeHandler struct {
	service *service.CidadeService
}

type cidadeEnvelope struct {
	Params struct {
		ID     string `json:"id"`
		Nome   string `json:"nome"`
		Codigo string `json:"codigo"`
		Ufid   string `json:"ufid"`
	} `json:"params"`
}

func NewCidadeHandler(service *service.CidadeService) *CidadeHandler {
	return &CidadeHandler{service: service}
}

func (h *CidadeHandler) List(w http.ResponseWriter, r *http.Request) {
	params := repository.CidadeListParams{
		First:     parseIntCidade(r.URL.Query().Get("first"), 0),
		Rows:      parseIntCidade(r.URL.Query().Get("rows"), 25),
		SortField: r.URL.Query().Get("sortField"),
		SortOrder: parseIntCidade(r.URL.Query().Get("sortOrder"), 1),
		Nome:      parseNomeFilterCidade(r.URL.Query().Get("filters")),
	}

	response, err := h.service.List(r.Context(), params)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *CidadeHandler) Create(w http.ResponseWriter, r *http.Request) {
	var payload cidadeEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if payload.Params.Nome == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar todos os dados!")
		return
	}

	response, err := h.service.Create(r.Context(), payload.Params.Nome, payload.Params.Codigo, payload.Params.Ufid)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *CidadeHandler) Update(w http.ResponseWriter, r *http.Request) {
	var payload cidadeEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if payload.Params.Nome == "" || payload.Params.Codigo == "" || payload.Params.Ufid == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar todos os dados!")
		return
	}

	response, err := h.service.Update(r.Context(), payload.Params.ID, payload.Params.Nome, payload.Params.Codigo, payload.Params.Ufid)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *CidadeHandler) Delete(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(r.URL.Query().Get("id"))
	if id == "" {
		var payload cidadeEnvelope
		if err := json.NewDecoder(r.Body).Decode(&payload); err == nil {
			id = strings.TrimSpace(payload.Params.ID)
		}
	}

	if id == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar o id!")
		return
	}

	response, err := h.service.Delete(r.Context(), id)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *CidadeHandler) ListLite(w http.ResponseWriter, r *http.Request) {
	response, err := h.service.ListLite(r.Context())
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func parseIntCidade(value string, fallback int) int {
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}

	return parsed
}

func parseNomeFilterCidade(raw string) string {
	if strings.TrimSpace(raw) == "" {
		return ""
	}

	type filtersPayload struct {
		Nome struct {
			Value string `json:"value"`
		} `json:"nome"`
	}

	var payload filtersPayload
	if err := json.Unmarshal([]byte(raw), &payload); err == nil {
		return payload.Nome.Value
	}

	return ""
}
