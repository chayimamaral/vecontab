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

type ObrigacaoHandler struct {
	service *service.ObrigacaoService
}

type obrigacaoEnvelope struct {
	Params struct {
		ID                 string   `json:"id"`
		TipoEmpresa        any      `json:"tipoempresa"`
		TipoClassificacao  any      `json:"tipo_classificacao"`
		Descricao          string   `json:"descricao"`
		Periodicidade      any      `json:"periodicidade"`
		Abrangencia        any      `json:"abrangencia"`
		DiaBase            int      `json:"dia_base"`
		MesBase            any      `json:"mes_base"`
		Valor              *float64 `json:"valor"`
		Observacao         string   `json:"observacao"`
		Municipio          any      `json:"municipio"`
		Estado             any      `json:"estado"`
		Bairro             string   `json:"bairro"`
		CatalogoServicoIDs []string `json:"catalogo_servico_ids"`
	} `json:"params"`
}

func NewObrigacaoHandler(s *service.ObrigacaoService) *ObrigacaoHandler {
	return &ObrigacaoHandler{service: s}
}

func (h *ObrigacaoHandler) List(w http.ResponseWriter, r *http.Request) {
	params := repository.ObrigacaoListParams{
		First:             parseObrigacaoInt(r.URL.Query().Get("first"), 0),
		Rows:              parseObrigacaoInt(r.URL.Query().Get("rows"), 25),
		SortField:         strings.TrimSpace(r.URL.Query().Get("sortField")),
		SortOrder:         parseObrigacaoInt(r.URL.Query().Get("sortOrder"), 1),
		Descricao:         parseObrigacaoFilterDescricao(r.URL.Query().Get("filters")),
		Abrangencia:       parseObrigacaoAbrangencia(r),
		TipoEmpresa:       strings.TrimSpace(r.URL.Query().Get("tipo_empresa_id")),
		TipoClassificacao: parseObrigacaoCodeParam(r, "tipo_classificacao"),
		Periodicidade:     parseObrigacaoCodeParam(r, "periodicidade"),
		Localizacao:       strings.TrimSpace(r.URL.Query().Get("localizacao")),
	}

	response, err := h.service.List(r.Context(), params)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *ObrigacaoHandler) Create(w http.ResponseWriter, r *http.Request) {
	var payload obrigacaoEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON inválido")
		return
	}

	desc := strings.TrimSpace(payload.Params.Descricao)
	if desc == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar a descrição!")
		return
	}

	input := service.ObrigacaoInput{
		TipoEmpresaID:      objectIDFromAny(payload.Params.TipoEmpresa),
		TipoClassificacao:  obrigacaoCodeFromAny(payload.Params.TipoClassificacao),
		Descricao:          desc,
		Periodicidade:      obrigacaoCodeFromAny(payload.Params.Periodicidade),
		Abrangencia:        obrigacaoCodeFromAny(payload.Params.Abrangencia),
		DiaBase:            payload.Params.DiaBase,
		MesBase:            service.MesBaseFromAny(payload.Params.MesBase),
		Valor:              payload.Params.Valor,
		Observacao:         strings.TrimSpace(payload.Params.Observacao),
		EstadoID:           objectIDFromAny(payload.Params.Estado),
		MunicipioID:        objectIDFromAny(payload.Params.Municipio),
		Bairro:             strings.TrimSpace(payload.Params.Bairro),
		CatalogoServicoIDs: normalizeUUIDList(payload.Params.CatalogoServicoIDs),
	}

	if input.Periodicidade == "" {
		input.Periodicidade = "MENSAL"
	}
	if input.TipoClassificacao == "" {
		input.TipoClassificacao = "TRIBUTARIA"
	}
	if input.Abrangencia == "" {
		input.Abrangencia = "FEDERAL"
	}
	if input.TipoEmpresaID == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar o tipo de empresa!")
		return
	}
	if input.DiaBase <= 0 {
		input.DiaBase = 20
	}

	response, err := h.service.Create(r.Context(), input)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *ObrigacaoHandler) Update(w http.ResponseWriter, r *http.Request) {
	var payload obrigacaoEnvelope
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

	input := service.ObrigacaoInput{
		ID:                 id,
		TipoEmpresaID:      objectIDFromAny(payload.Params.TipoEmpresa),
		TipoClassificacao:  obrigacaoCodeFromAny(payload.Params.TipoClassificacao),
		Descricao:          desc,
		Periodicidade:      obrigacaoCodeFromAny(payload.Params.Periodicidade),
		Abrangencia:        obrigacaoCodeFromAny(payload.Params.Abrangencia),
		DiaBase:            payload.Params.DiaBase,
		MesBase:            service.MesBaseFromAny(payload.Params.MesBase),
		Valor:              payload.Params.Valor,
		Observacao:         strings.TrimSpace(payload.Params.Observacao),
		EstadoID:           objectIDFromAny(payload.Params.Estado),
		MunicipioID:        objectIDFromAny(payload.Params.Municipio),
		Bairro:             strings.TrimSpace(payload.Params.Bairro),
		CatalogoServicoIDs: normalizeUUIDList(payload.Params.CatalogoServicoIDs),
	}

	if input.Periodicidade == "" {
		input.Periodicidade = "MENSAL"
	}
	if input.TipoClassificacao == "" {
		input.TipoClassificacao = "TRIBUTARIA"
	}
	if input.Abrangencia == "" {
		input.Abrangencia = "FEDERAL"
	}
	if input.TipoEmpresaID == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar o tipo de empresa!")
		return
	}
	if input.DiaBase <= 0 {
		input.DiaBase = 20
	}

	response, err := h.service.Update(r.Context(), input)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *ObrigacaoHandler) Delete(w http.ResponseWriter, r *http.Request) {
	var payload obrigacaoEnvelope
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

func parseObrigacaoInt(value string, fallback int) int {
	n, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return n
}

func parseObrigacaoFilterDescricao(raw string) string {
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

func parseObrigacaoAbrangencia(r *http.Request) string {
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

func parseObrigacaoCodeParam(r *http.Request, key string) string {
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

func obrigacaoCodeFromAny(value any) string {
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

func normalizeUUIDList(values []string) []string {
	if len(values) == 0 {
		return nil
	}
	out := make([]string, 0, len(values))
	seen := make(map[string]struct{}, len(values))
	for _, raw := range values {
		id := strings.TrimSpace(raw)
		if id == "" {
			continue
		}
		if _, exists := seen[id]; exists {
			continue
		}
		seen[id] = struct{}{}
		out = append(out, id)
	}
	return out
}
