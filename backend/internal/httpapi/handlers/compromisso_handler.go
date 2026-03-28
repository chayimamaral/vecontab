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

type CompromissoHandler struct {
	service *service.CompromissoService
}

type compromissoEnvelope struct {
	Params struct {
		ID            string   `json:"id"`
		TipoEmpresa   any      `json:"tipoempresa"`
		Natureza      any      `json:"natureza"`
		Descricao     string   `json:"descricao"`
		Periodicidade any      `json:"periodicidade"`
		Abrangencia   any      `json:"abrangencia"`
		Valor         *float64 `json:"valor"`
		Observacao    string   `json:"observacao"`
		Municipio     any      `json:"municipio"`
		Estado        any      `json:"estado"`
		Bairro        string   `json:"bairro"`
	} `json:"params"`
}

func NewCompromissoHandler(service *service.CompromissoService) *CompromissoHandler {
	return &CompromissoHandler{service: service}
}

func (h *CompromissoHandler) List(w http.ResponseWriter, r *http.Request) {
	params := repository.CompromissoListParams{
		First:         parseCompromissoInt(r.URL.Query().Get("first"), 0),
		Rows:          parseCompromissoInt(r.URL.Query().Get("rows"), 25),
		SortField:     strings.TrimSpace(r.URL.Query().Get("sortField")),
		SortOrder:     parseCompromissoInt(r.URL.Query().Get("sortOrder"), 1),
		Descricao:     parseCompromissoFilterDescricao(r.URL.Query().Get("filters")),
		Abrangencia:   parseCompromissoAbrangencia(r),
		TipoEmpresa:   strings.TrimSpace(r.URL.Query().Get("tipo_empresa_id")),
		Natureza:      parseCompromissoCodeParam(r, "natureza"),
		Periodicidade: parseCompromissoCodeParam(r, "periodicidade"),
		Localizacao:   strings.TrimSpace(r.URL.Query().Get("localizacao")),
	}

	response, err := h.service.List(r.Context(), params)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *CompromissoHandler) Create(w http.ResponseWriter, r *http.Request) {
	var payload compromissoEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON inválido")
		return
	}

	desc := strings.TrimSpace(payload.Params.Descricao)
	if desc == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar a descrição!")
		return
	}

	input := service.CompromissoInput{
		TipoEmpresaID: objectIDFromAny(payload.Params.TipoEmpresa),
		Natureza:      compromissoCodeFromAny(payload.Params.Natureza),
		Descricao:     desc,
		Periodicidade: compromissoCodeFromAny(payload.Params.Periodicidade),
		Abrangencia:   compromissoCodeFromAny(payload.Params.Abrangencia),
		Valor:         payload.Params.Valor,
		Observacao:    strings.TrimSpace(payload.Params.Observacao),
		EstadoID:      objectIDFromAny(payload.Params.Estado),
		MunicipioID:   objectIDFromAny(payload.Params.Municipio),
		Bairro:        strings.TrimSpace(payload.Params.Bairro),
	}

	// Default periodicidade/abrangencia when not provided
	if input.Periodicidade == "" {
		input.Periodicidade = "MENSAL"
	}
	if input.Natureza == "" {
		input.Natureza = "FINANCEIRO"
	}
	if input.Abrangencia == "" {
		input.Abrangencia = "FEDERAL"
	}
	if input.TipoEmpresaID == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar o tipo de empresa!")
		return
	}

	response, err := h.service.Create(r.Context(), input)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *CompromissoHandler) Update(w http.ResponseWriter, r *http.Request) {
	var payload compromissoEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON inválido")
		return
	}

	id := strings.TrimSpace(payload.Params.ID)
	desc := strings.TrimSpace(payload.Params.Descricao)
	if id == "" || desc == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar o id e a descrição!")
		return
	}

	input := service.CompromissoInput{
		ID:            id,
		TipoEmpresaID: objectIDFromAny(payload.Params.TipoEmpresa),
		Natureza:      compromissoCodeFromAny(payload.Params.Natureza),
		Descricao:     desc,
		Periodicidade: compromissoCodeFromAny(payload.Params.Periodicidade),
		Abrangencia:   compromissoCodeFromAny(payload.Params.Abrangencia),
		Valor:         payload.Params.Valor,
		Observacao:    strings.TrimSpace(payload.Params.Observacao),
		EstadoID:      objectIDFromAny(payload.Params.Estado),
		MunicipioID:   objectIDFromAny(payload.Params.Municipio),
		Bairro:        strings.TrimSpace(payload.Params.Bairro),
	}

	if input.Periodicidade == "" {
		input.Periodicidade = "MENSAL"
	}
	if input.Natureza == "" {
		input.Natureza = "FINANCEIRO"
	}
	if input.Abrangencia == "" {
		input.Abrangencia = "FEDERAL"
	}
	if input.TipoEmpresaID == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar o tipo de empresa!")
		return
	}

	response, err := h.service.Update(r.Context(), input)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *CompromissoHandler) Delete(w http.ResponseWriter, r *http.Request) {
	var payload compromissoEnvelope
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

// ── parse helpers ──────────────────────────────────────────────────────────

func parseCompromissoInt(value string, fallback int) int {
	n, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return n
}

func parseCompromissoFilterDescricao(raw string) string {
	type fp struct {
		Descricao struct {
			Value string `json:"value"`
		} `json:"descricao"`
	}
	if strings.TrimSpace(raw) == "" {
		return ""
	}
	var p fp
	if err := json.Unmarshal([]byte(raw), &p); err == nil {
		return p.Descricao.Value
	}
	return ""
}

// parseCompromissoAbrangencia reads the abrangencia filter from query params.
// Supports: abrangencia.code, abrangencia[code], abrangencia (raw string / JSON).
func parseCompromissoAbrangencia(r *http.Request) string {
	if v := strings.TrimSpace(r.URL.Query().Get("abrangencia.code")); v != "" {
		return v
	}
	if v := strings.TrimSpace(r.URL.Query().Get("abrangencia[code]")); v != "" {
		return v
	}
	raw := strings.TrimSpace(r.URL.Query().Get("abrangencia"))
	if raw == "" {
		return ""
	}
	var obj struct {
		Code string `json:"code"`
	}
	if err := json.Unmarshal([]byte(raw), &obj); err == nil {
		return obj.Code
	}
	return raw
}

// parseCompromissoCodeParam reads generic code-like filters from query params.
// Supports: key.code, key[code], key (raw string / JSON object with code).
func parseCompromissoCodeParam(r *http.Request, key string) string {
	if v := strings.TrimSpace(r.URL.Query().Get(key + ".code")); v != "" {
		return strings.ToUpper(v)
	}
	if v := strings.TrimSpace(r.URL.Query().Get(key + "[code]")); v != "" {
		return strings.ToUpper(v)
	}
	raw := strings.TrimSpace(r.URL.Query().Get(key))
	if raw == "" {
		return ""
	}
	var obj struct {
		Code string `json:"code"`
	}
	if err := json.Unmarshal([]byte(raw), &obj); err == nil {
		return strings.ToUpper(strings.TrimSpace(obj.Code))
	}
	return strings.ToUpper(raw)
}

// compromissoCodeFromAny extracts a code string from either a {code,name} object or a plain string.
func compromissoCodeFromAny(value any) string {
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
