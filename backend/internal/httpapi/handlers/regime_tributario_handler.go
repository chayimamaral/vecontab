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

type RegimeTributarioHandler struct {
	service *service.RegimeTributarioService
}

type regimeTributarioEnvelope struct {
	Params struct {
		ID                 string          `json:"id"`
		Nome               string          `json:"nome"`
		CodigoCRT          int             `json:"codigo_crt"`
		TipoApuracao       string          `json:"tipo_apuracao"`
		Ativo              *bool           `json:"ativo"`
		ConfiguracaoJSON   json.RawMessage `json:"configuracao_json"`
	} `json:"params"`
}

func NewRegimeTributarioHandler(svc *service.RegimeTributarioService) *RegimeTributarioHandler {
	return &RegimeTributarioHandler{service: svc}
}

func (h *RegimeTributarioHandler) List(w http.ResponseWriter, r *http.Request) {
	params := repository.RegimeTributarioListParams{
		First:     parseIntRegimeTrib(r.URL.Query().Get("first"), 0),
		Rows:      parseIntRegimeTrib(r.URL.Query().Get("rows"), 25),
		SortField: r.URL.Query().Get("sortField"),
		SortOrder: parseIntRegimeTrib(r.URL.Query().Get("sortOrder"), 1),
		Nome:      parseNomeFilterRegimeTrib(r.URL.Query().Get("filters")),
	}

	out, err := h.service.List(r.Context(), params)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, out)
}

func (h *RegimeTributarioHandler) Create(w http.ResponseWriter, r *http.Request) {
	var payload regimeTributarioEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	tipoApur := strings.TrimSpace(strings.ToUpper(payload.Params.TipoApuracao))
	if errMsg := validateRegimeTributarioPayload(payload.Params.Nome, payload.Params.CodigoCRT, tipoApur); errMsg != "" {
		render.WriteError(w, http.StatusBadRequest, errMsg)
		return
	}

	cfg, err := normalizeRegimeConfigJSON(payload.Params.ConfiguracaoJSON)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, "configuracao_json invalido")
		return
	}

	ativo := true
	if payload.Params.Ativo != nil {
		ativo = *payload.Params.Ativo
	}

	out, err := h.service.Create(r.Context(), strings.TrimSpace(payload.Params.Nome), payload.Params.CodigoCRT, tipoApur, ativo, cfg)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, out)
}

func (h *RegimeTributarioHandler) Update(w http.ResponseWriter, r *http.Request) {
	var payload regimeTributarioEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if strings.TrimSpace(payload.Params.ID) == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar o id")
		return
	}

	tipoApur := strings.TrimSpace(strings.ToUpper(payload.Params.TipoApuracao))
	if errMsg := validateRegimeTributarioPayload(payload.Params.Nome, payload.Params.CodigoCRT, tipoApur); errMsg != "" {
		render.WriteError(w, http.StatusBadRequest, errMsg)
		return
	}

	cfg, err := normalizeRegimeConfigJSON(payload.Params.ConfiguracaoJSON)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, "configuracao_json invalido")
		return
	}

	ativo := true
	if payload.Params.Ativo != nil {
		ativo = *payload.Params.Ativo
	}

	out, err := h.service.Update(r.Context(), strings.TrimSpace(payload.Params.ID), strings.TrimSpace(payload.Params.Nome), payload.Params.CodigoCRT, tipoApur, ativo, cfg)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, out)
}

func (h *RegimeTributarioHandler) Delete(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(r.URL.Query().Get("id"))
	if id == "" {
		var payload regimeTributarioEnvelope
		if err := json.NewDecoder(r.Body).Decode(&payload); err == nil {
			id = strings.TrimSpace(payload.Params.ID)
		}
	}
	if id == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar o id")
		return
	}

	out, err := h.service.Delete(r.Context(), id)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, out)
}

func validateRegimeTributarioPayload(nome string, codigoCRT int, tipoApuracao string) string {
	if strings.TrimSpace(nome) == "" {
		return "Favor informar o nome"
	}
	if codigoCRT < 1 || codigoCRT > 4 {
		return "codigo_crt deve ser 1, 2, 3 ou 4"
	}
	t := strings.TrimSpace(strings.ToUpper(tipoApuracao))
	if t != "MENSAL" && t != "TRIMESTRAL" {
		return "tipo_apuracao deve ser MENSAL ou TRIMESTRAL"
	}
	return ""
}

func normalizeRegimeConfigJSON(raw json.RawMessage) ([]byte, error) {
	if len(raw) == 0 {
		return []byte("{}"), nil
	}
	var v any
	if err := json.Unmarshal(raw, &v); err != nil {
		return nil, err
	}
	return json.Marshal(v)
}

func parseIntRegimeTrib(value string, fallback int) int {
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func parseNomeFilterRegimeTrib(raw string) string {
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
