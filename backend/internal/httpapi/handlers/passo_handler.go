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

type PassoHandler struct {
	service *service.PassoService
}

type passoEnvelope struct {
	Params struct {
		ID          string `json:"id"`
		Descricao   string `json:"descricao"`
		Tempo       int    `json:"tempoestimado"`
		TipoPasso   string `json:"tipopasso"`
		MunicipioID string `json:"municipio_id"`
		Link        string `json:"link"`
	} `json:"params"`
}

func NewPassoHandler(service *service.PassoService) *PassoHandler {
	return &PassoHandler{service: service}
}

func (h *PassoHandler) List(w http.ResponseWriter, r *http.Request) {
	params := repository.PassoListParams{
		First:       parseIntPasso(r.URL.Query().Get("first"), 0),
		Rows:        parseIntPasso(r.URL.Query().Get("rows"), 25),
		SortField:   r.URL.Query().Get("sortField"),
		SortOrder:   parseIntPasso(r.URL.Query().Get("sortOrder"), 1),
		Descricao:   parseDescricaoFilterPasso(r.URL.Query().Get("filters")),
		MunicipioID: parseMunicipioFilterPasso(r.URL.Query().Get("filters")),
	}

	response, err := h.service.List(r.Context(), params)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *PassoHandler) Create(w http.ResponseWriter, r *http.Request) {
	var payload passoEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if strings.TrimSpace(payload.Params.Descricao) == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar a descricao do Passo!")
		return
	}

	response, err := h.service.Create(r.Context(), service.PassoCreateInput{
		Descricao:   payload.Params.Descricao,
		Tempo:       payload.Params.Tempo,
		TipoPasso:   payload.Params.TipoPasso,
		MunicipioID: payload.Params.MunicipioID,
		Link:        payload.Params.Link,
	})
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *PassoHandler) Update(w http.ResponseWriter, r *http.Request) {
	var payload passoEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if strings.TrimSpace(payload.Params.Descricao) == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar todos os dados!")
		return
	}

	response, err := h.service.Update(r.Context(), service.PassoUpdateInput{
		ID:          payload.Params.ID,
		Descricao:   payload.Params.Descricao,
		Tempo:       payload.Params.Tempo,
		TipoPasso:   payload.Params.TipoPasso,
		MunicipioID: payload.Params.MunicipioID,
		Link:        payload.Params.Link,
	})
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *PassoHandler) Delete(w http.ResponseWriter, r *http.Request) {
	var payload passoEnvelope
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

func (h *PassoHandler) GetByID(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(r.URL.Query().Get("id"))
	if id == "" {
		id = strings.TrimSpace(r.PathValue("id"))
	}
	if id == "" {
		var payload passoEnvelope
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

func (h *PassoHandler) ListByCidade(w http.ResponseWriter, r *http.Request) {
	municipioID := strings.TrimSpace(r.URL.Query().Get("municipio_id"))
	rotinaID := strings.TrimSpace(r.URL.Query().Get("id"))

	response, err := h.service.ListByCidade(r.Context(), municipioID, rotinaID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func parseIntPasso(value string, fallback int) int {
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}

	return parsed
}

func parseDescricaoFilterPasso(raw string) string {
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

func parseMunicipioFilterPasso(raw string) string {
	type filtersPayload struct {
		Municipio struct {
			Value struct {
				ID string `json:"id"`
			} `json:"value"`
		} `json:"municipio"`
	}

	if strings.TrimSpace(raw) == "" {
		return ""
	}

	var payload filtersPayload
	if err := json.Unmarshal([]byte(raw), &payload); err == nil {
		return payload.Municipio.Value.ID
	}

	return ""
}
