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

type RotinaHandler struct {
	service *service.RotinaService
}

type rotinaEnvelope struct {
	Params struct {
		ID            string `json:"id"`
		Descricao     string `json:"descricao"`
		CidadeID      string `json:"cidade_id"`
		Link          string `json:"link"`
		TempoEstimado int    `json:"tempoestimado"`
		RotinaID      string `json:"rotina_id"`
		Passos        any    `json:"passos"`
	} `json:"params"`
}

func NewRotinaHandler(service *service.RotinaService) *RotinaHandler {
	return &RotinaHandler{service: service}
}

func (h *RotinaHandler) List(w http.ResponseWriter, r *http.Request) {
	first, rows := rotinaListPaging(r.URL.Query().Get("first"), r.URL.Query().Get("rows"))
	params := repository.RotinaListParams{
		First:     first,
		Rows:      rows,
		SortField: r.URL.Query().Get("sortField"),
		SortOrder: parseIntRotina(r.URL.Query().Get("sortOrder"), 1),
		Descricao: parseDescricaoFilterRotina(r.URL.Query().Get("filters")),
	}

	response, err := h.service.List(r.Context(), params)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}

func (h *RotinaHandler) ListRotinas(w http.ResponseWriter, r *http.Request) {
	first, rows := rotinaListPaging(r.URL.Query().Get("first"), r.URL.Query().Get("rows"))
	params := repository.RotinaListParams{
		First:     first,
		Rows:      rows,
		SortField: r.URL.Query().Get("sortField"),
		SortOrder: parseIntRotina(r.URL.Query().Get("sortOrder"), 1),
		Descricao: parseDescricaoFilterRotina(r.URL.Query().Get("filters")),
	}

	response, err := h.service.ListRotinas(r.Context(), params)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}

func (h *RotinaHandler) ListLite(w http.ResponseWriter, r *http.Request) {
	municipioID := strings.TrimSpace(r.URL.Query().Get("id"))
	response, err := h.service.ListLite(r.Context(), municipioID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}

func (h *RotinaHandler) Create(w http.ResponseWriter, r *http.Request) {
	var payload rotinaEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}
	if strings.TrimSpace(payload.Params.Descricao) == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar a descricao da Rotina!")
		return
	}
	if strings.TrimSpace(payload.Params.CidadeID) == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar o município da rotina!")
		return
	}

	response, err := h.service.Create(r.Context(), service.RotinaInput{
		Descricao: payload.Params.Descricao,
		CidadeID:  payload.Params.CidadeID,
		Link:      payload.Params.Link,
	})
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}

func (h *RotinaHandler) Update(w http.ResponseWriter, r *http.Request) {
	var payload rotinaEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}
	if strings.TrimSpace(payload.Params.Descricao) == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar todos os dados!")
		return
	}
	if strings.TrimSpace(payload.Params.CidadeID) == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar o município da rotina!")
		return
	}

	response, err := h.service.Update(r.Context(), service.RotinaInput{
		ID:        payload.Params.ID,
		Descricao: payload.Params.Descricao,
		CidadeID:  payload.Params.CidadeID,
		Link:      payload.Params.Link,
	})
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}

func (h *RotinaHandler) Delete(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(r.PathValue("id"))
	if id == "" {
		id = strings.TrimSpace(r.URL.Query().Get("id"))
	}
	if id == "" {
		var payload rotinaEnvelope
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

func (h *RotinaHandler) RotinaItens(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(r.PathValue("id"))
	if id == "" {
		id = strings.TrimSpace(r.URL.Query().Get("id"))
	}
	if id == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar o id!")
		return
	}

	response, err := h.service.RotinaItens(r.Context(), id)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}

func (h *RotinaHandler) RotinaItemCreate(w http.ResponseWriter, r *http.Request) {
	var payload rotinaEnvelope
	if err := decodeFromBodyOrQuery(r, &payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	descricao := payload.Params.Descricao
	if descricao == "" {
		descricao = r.URL.Query().Get("descricao")
	}
	if strings.TrimSpace(descricao) == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar a descricao do Passo!")
		return
	}

	rotinaID := payload.Params.RotinaID
	if rotinaID == "" {
		rotinaID = r.URL.Query().Get("rotina_id")
	}
	tempo := payload.Params.TempoEstimado
	if tempo == 0 {
		tempo = parseIntRotina(r.URL.Query().Get("tempoestimado"), 0)
	}
	link := payload.Params.Link
	if link == "" {
		link = r.URL.Query().Get("link")
	}

	response, err := h.service.RotinaItemCreate(r.Context(), rotinaID, descricao, tempo, link)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}

func (h *RotinaHandler) RotinaItemUpdate(w http.ResponseWriter, r *http.Request) {
	var payload rotinaEnvelope
	if err := decodeFromBodyOrQuery(r, &payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	id := payload.Params.ID
	if id == "" {
		id = r.URL.Query().Get("id")
	}
	descricao := payload.Params.Descricao
	if descricao == "" {
		descricao = r.URL.Query().Get("descricao")
	}
	tempo := payload.Params.TempoEstimado
	if tempo == 0 {
		tempo = parseIntRotina(r.URL.Query().Get("tempoestimado"), 0)
	}
	link := payload.Params.Link
	if link == "" {
		link = r.URL.Query().Get("link")
	}

	if strings.TrimSpace(descricao) == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar todos os dados!")
		return
	}

	response, err := h.service.RotinaItemUpdate(r.Context(), id, descricao, tempo, link)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}

func (h *RotinaHandler) RotinaItemDelete(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(r.PathValue("id"))
	if id == "" {
		id = strings.TrimSpace(r.URL.Query().Get("id"))
	}
	if id == "" {
		var payload rotinaEnvelope
		if err := decodeFromBodyOrQuery(r, &payload); err == nil {
			id = strings.TrimSpace(payload.Params.ID)
		}
	}
	if id == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar o id!")
		return
	}

	response, err := h.service.RotinaItemDelete(r.Context(), id)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}

func (h *RotinaHandler) ListSelectedItens(w http.ResponseWriter, r *http.Request) {
	rotinaID := strings.TrimSpace(r.URL.Query().Get("id"))
	response, err := h.service.ListSelectedItens(r.Context(), rotinaID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}

func (h *RotinaHandler) SaveSelectedItens(w http.ResponseWriter, r *http.Request) {
	var payload rotinaEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	selections := toSelectionList(payload.Params.Passos)
	response, err := h.service.SaveSelectedItens(r.Context(), selections)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}

func (h *RotinaHandler) RemoveSelectedItens(w http.ResponseWriter, r *http.Request) {
	var payload rotinaEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	selections := toSelectionList(payload.Params)
	response, err := h.service.RemoveSelectedItens(r.Context(), selections)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}

func rotinaListPaging(firstRaw, rowsRaw string) (first int, rows int) {
	first = parseIntRotina(firstRaw, 0)
	if first < 0 {
		first = 0
	}
	rows = parseIntRotina(rowsRaw, 25)
	if rows <= 0 {
		rows = 25
	}
	return first, rows
}

func parseIntRotina(value string, fallback int) int {
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func parseDescricaoFilterRotina(raw string) string {
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

func decodeFromBodyOrQuery(r *http.Request, payload *rotinaEnvelope) error {
	if r.ContentLength > 0 {
		return json.NewDecoder(r.Body).Decode(payload)
	}
	return nil
}

func toSelectionList(value any) []repository.RotinaPassoSelection {
	items := make([]repository.RotinaPassoSelection, 0)

	switch typed := value.(type) {
	case []any:
		for _, v := range typed {
			if m, ok := v.(map[string]any); ok {
				items = append(items, repository.RotinaPassoSelection{
					ID:       asString(m["id"]),
					RotinaID: asString(m["rotina_id"]),
					Ordem:    asInt(m["ordem"]),
				})
			}
		}
	case map[string]any:
		for _, v := range typed {
			if m, ok := v.(map[string]any); ok {
				items = append(items, repository.RotinaPassoSelection{
					ID:       asString(m["id"]),
					RotinaID: asString(m["rotina_id"]),
					Ordem:    asInt(m["ordem"]),
				})
			}
		}
	}

	return items
}

func asString(v any) string {
	if s, ok := v.(string); ok {
		return s
	}
	return ""
}

func asInt(v any) int {
	switch x := v.(type) {
	case float64:
		return int(x)
	case int:
		return x
	case string:
		return parseIntRotina(x, 0)
	default:
		return 0
	}
}
