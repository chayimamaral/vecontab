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

type FeriadoHandler struct {
	service *service.FeriadoService
}

type feriadoEnvelope struct {
	Params struct {
		ID        string `json:"id"`
		Descricao string `json:"descricao"`
		Data      string `json:"data"`
		Municipio any    `json:"municipio"`
		Estado    any    `json:"estado"`
		Holiday   any    `json:"holiday"`
	} `json:"params"`
}

func NewFeriadoHandler(service *service.FeriadoService) *FeriadoHandler {
	return &FeriadoHandler{service: service}
}

func (h *FeriadoHandler) List(w http.ResponseWriter, r *http.Request) {
	params := repository.FeriadoListParams{
		First:       parseIntFeriado(r.URL.Query().Get("first"), 0),
		Rows:        parseIntFeriado(r.URL.Query().Get("rows"), 25),
		Descricao:   parseDescricaoFilterFeriado(r.URL.Query().Get("filters")),
		HolidayCode: parseHolidayCodeFeriado(r),
	}

	response, err := h.service.List(r.Context(), params)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *FeriadoHandler) Create(w http.ResponseWriter, r *http.Request) {
	var payload feriadoEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if strings.TrimSpace(payload.Params.Descricao) == "" || strings.TrimSpace(payload.Params.Data) == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar todos os dados!")
		return
	}

	response, err := h.service.Create(r.Context(), service.FeriadoInput{
		Descricao:   payload.Params.Descricao,
		Data:        payload.Params.Data,
		HolidayCode: holidayCodeFromAny(payload.Params.Holiday),
		MunicipioID: objectIDFromAny(payload.Params.Municipio),
		EstadoID:    objectIDFromAny(payload.Params.Estado),
	})
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *FeriadoHandler) Update(w http.ResponseWriter, r *http.Request) {
	var payload feriadoEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if strings.TrimSpace(payload.Params.Descricao) == "" || strings.TrimSpace(payload.Params.Data) == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar todos os dados!")
		return
	}

	response, err := h.service.Update(r.Context(), service.FeriadoInput{
		ID:          payload.Params.ID,
		Descricao:   payload.Params.Descricao,
		Data:        payload.Params.Data,
		HolidayCode: holidayCodeFromAny(payload.Params.Holiday),
		MunicipioID: objectIDFromAny(payload.Params.Municipio),
		EstadoID:    objectIDFromAny(payload.Params.Estado),
	})
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *FeriadoHandler) Delete(w http.ResponseWriter, r *http.Request) {
	var payload feriadoEnvelope
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

func parseIntFeriado(value string, fallback int) int {
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func parseDescricaoFilterFeriado(raw string) string {
	type filtersPayload struct {
		Descricao struct {
			Value string `json:"value"`
		} `json:"descricao"`
	}

	if strings.TrimSpace(raw) == "" {
		return ""
	}

	var payload filtersPayload
	if err := json.Unmarshal([]byte(raw), &payload); err == nil {
		return payload.Descricao.Value
	}

	return ""
}

func parseHolidayCodeFeriado(r *http.Request) string {
	if v := strings.TrimSpace(r.URL.Query().Get("holiday.code")); v != "" {
		return v
	}

	if v := strings.TrimSpace(r.URL.Query().Get("holiday[code]")); v != "" {
		return v
	}

	hRaw := strings.TrimSpace(r.URL.Query().Get("holiday"))
	if hRaw == "" {
		return ""
	}

	var holiday struct {
		Code string `json:"code"`
	}
	if err := json.Unmarshal([]byte(hRaw), &holiday); err == nil {
		return holiday.Code
	}

	return hRaw
}

func holidayCodeFromAny(value any) string {
	if value == nil {
		return ""
	}

	if m, ok := value.(map[string]any); ok {
		if code, ok := m["code"].(string); ok {
			return code
		}
	}

	if s, ok := value.(string); ok {
		return s
	}

	return ""
}

func objectIDFromAny(value any) string {
	if value == nil {
		return ""
	}

	if m, ok := value.(map[string]any); ok {
		if id, ok := m["id"].(string); ok {
			return id
		}
	}

	return ""
}
