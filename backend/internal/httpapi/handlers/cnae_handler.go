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

type CnaeHandler struct {
	service *service.CnaeService
}

type cnaeEnvelope struct {
	Params struct {
		ID          string `json:"id"`
		Denominacao string `json:"denominacao"`
		Subclasse   string `json:"subclasse"`
	} `json:"params"`
}

func NewCnaeHandler(service *service.CnaeService) *CnaeHandler {
	return &CnaeHandler{service: service}
}

func (h *CnaeHandler) List(w http.ResponseWriter, r *http.Request) {
	params := repository.CnaeListParams{
		First:       parseIntCnae(r.URL.Query().Get("first"), 0),
		Rows:        parseIntCnae(r.URL.Query().Get("rows"), 25),
		SortField:   r.URL.Query().Get("sortField"),
		SortOrder:   parseIntCnae(r.URL.Query().Get("sortOrder"), 1),
		Denominacao: parseDenominacaoFilterCnae(r.URL.Query().Get("filters")),
		Subclasse:   parseSubclasseFilterCnae(r.URL.Query().Get("filters")),
	}

	response, err := h.service.List(r.Context(), params)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *CnaeHandler) Create(w http.ResponseWriter, r *http.Request) {
	var payload cnaeEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if strings.TrimSpace(payload.Params.Denominacao) == "" {
		render.WriteError(w, http.StatusBadRequest, "Denominacao e obrigatoria")
		return
	}

	response, err := h.service.Create(r.Context(), service.CnaeInput(payload.Params))
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *CnaeHandler) Update(w http.ResponseWriter, r *http.Request) {
	var payload cnaeEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	response, err := h.service.Update(r.Context(), service.CnaeInput(payload.Params))
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *CnaeHandler) Delete(w http.ResponseWriter, r *http.Request) {
	var payload cnaeEnvelope
	_ = json.NewDecoder(r.Body).Decode(&payload)
	id := strings.TrimSpace(payload.Params.ID)
	if id == "" {
		id = strings.TrimSpace(r.URL.Query().Get("id"))
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

func (h *CnaeHandler) Lite(w http.ResponseWriter, r *http.Request) {
	response, err := h.service.Lite(r.Context())
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *CnaeHandler) Validate(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		Cnae string `json:"cnae"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	response, err := h.service.Validate(r.Context(), payload.Cnae)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func parseIntCnae(value string, fallback int) int {
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func parseDenominacaoFilterCnae(raw string) string {
	type filtersPayload struct {
		Denominacao struct {
			Value string `json:"value"`
		} `json:"denominacao"`
	}

	if strings.TrimSpace(raw) == "" {
		return ""
	}

	var payload filtersPayload
	if err := json.Unmarshal([]byte(raw), &payload); err == nil {
		return payload.Denominacao.Value
	}
	return ""
}

func parseSubclasseFilterCnae(raw string) string {
	type filtersPayload struct {
		Subclasse struct {
			Value string `json:"value"`
		} `json:"subclasse"`
	}

	if strings.TrimSpace(raw) == "" {
		return ""
	}

	var payload filtersPayload
	if err := json.Unmarshal([]byte(raw), &payload); err == nil {
		return payload.Subclasse.Value
	}
	return ""
}
