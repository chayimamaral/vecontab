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

type GrupoPassosHandler struct {
	service *service.GrupoPassosService
}

type grupoPassosEnvelope struct {
	Params struct {
		ID            string `json:"id"`
		Descricao     string `json:"descricao"`
		MunicipioID   string `json:"municipio_id"`
		TipoEmpresaID string `json:"tipoempresa_id"`
	} `json:"params"`
}

func NewGrupoPassosHandler(service *service.GrupoPassosService) *GrupoPassosHandler {
	return &GrupoPassosHandler{service: service}
}

func (h *GrupoPassosHandler) List(w http.ResponseWriter, r *http.Request) {
	params := repository.GrupoPassosListParams{
		First:     parseIntGrupoPassos(r.URL.Query().Get("first"), 0),
		Rows:      parseIntGrupoPassos(r.URL.Query().Get("rows"), 25),
		SortField: r.URL.Query().Get("sortField"),
		SortOrder: parseIntGrupoPassos(r.URL.Query().Get("sortOrder"), 1),
		Descricao: parseDescricaoFilterGrupoPassos(r.URL.Query().Get("filters")),
	}

	response, err := h.service.List(r.Context(), params)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *GrupoPassosHandler) Create(w http.ResponseWriter, r *http.Request) {
	var payload grupoPassosEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if strings.TrimSpace(payload.Params.Descricao) == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar a descricao do Grupo de Passos!")
		return
	}

	response, err := h.service.Create(r.Context(), service.GrupoPassosInput(payload.Params))
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *GrupoPassosHandler) Update(w http.ResponseWriter, r *http.Request) {
	var payload grupoPassosEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if strings.TrimSpace(payload.Params.Descricao) == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar a descricao!")
		return
	}

	response, err := h.service.Update(r.Context(), service.GrupoPassosInput(payload.Params))
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *GrupoPassosHandler) Delete(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(r.URL.Query().Get("id"))
	if id == "" {
		id = strings.TrimSpace(r.PathValue("id"))
	}
	if id == "" {
		var payload grupoPassosEnvelope
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

func (h *GrupoPassosHandler) GetByID(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(r.URL.Query().Get("id"))
	if id == "" {
		id = strings.TrimSpace(r.PathValue("id"))
	}
	if id == "" {
		var payload grupoPassosEnvelope
		if err := json.NewDecoder(r.Body).Decode(&payload); err == nil {
			id = strings.TrimSpace(payload.Params.ID)
		}
	}

	if id == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar o id!")
		return
	}

	response, err := h.service.GetByID(r.Context(), id)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func parseIntGrupoPassos(value string, fallback int) int {
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}

	return parsed
}

func parseDescricaoFilterGrupoPassos(raw string) string {
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
