package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/httpapi/middleware"
	"github.com/chayimamaral/vecontab/backend/internal/httpapi/render"
	"github.com/chayimamaral/vecontab/backend/internal/repository"
	"github.com/chayimamaral/vecontab/backend/internal/service"
)

type EmpresaHandler struct {
	service *service.EmpresaService
}

type empresaEnvelope struct {
	Params struct {
		ID         string `json:"id"`
		ProcessoID string `json:"processo_id"`
		EmpresaID  string `json:"empresa_id"`
		Nome       string `json:"nome"`
		Descricao  string `json:"descricao"`
		Municipio  struct {
			ID string `json:"id"`
		} `json:"municipio"`
		TenantID string `json:"tenantid"`
		Rotina   struct {
			ID string `json:"id"`
		} `json:"rotina"`
		RotinaPF struct {
			ID string `json:"id"`
		} `json:"rotina_pf"`
		RegimeTributario struct {
			ID string `json:"id"`
		} `json:"regime_tributario"`
		TipoEmpresa struct {
			ID string `json:"id"`
		} `json:"tipo_empresa"`
		Cnaes      any    `json:"cnaes"`
		Bairro     string `json:"bairro"`
		TipoPessoa string `json:"tipo_pessoa"`
		Documento  string `json:"documento"`
		IE         string `json:"ie"`
		IM         string `json:"im"`
	} `json:"params"`
}

func NewEmpresaHandler(service *service.EmpresaService) *EmpresaHandler {
	return &EmpresaHandler{service: service}
}

func parseTipoPessoaPayload(s string) string {
	if strings.ToUpper(strings.TrimSpace(s)) == "PF" {
		return "PF"
	}
	return "PJ"
}

func (h *EmpresaHandler) List(w http.ResponseWriter, r *http.Request) {
	params := repository.EmpresaListParams{
		First:     parseIntEmpresa(r.URL.Query().Get("first"), 0),
		Rows:      parseIntEmpresa(r.URL.Query().Get("rows"), 25),
		SortField: r.URL.Query().Get("sortField"),
		SortOrder: parseIntEmpresa(r.URL.Query().Get("sortOrder"), 1),
		Nome:      parseNomeFilterEmpresa(r.URL.Query().Get("filters")),
		TenantID:  middleware.TenantID(r.Context()),
	}

	response, err := h.service.List(r.Context(), params)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *EmpresaHandler) Create(w http.ResponseWriter, r *http.Request) {
	var payload empresaEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	tenantID := middleware.TenantID(r.Context())
	tp := parseTipoPessoaPayload(payload.Params.TipoPessoa)
	if payload.Params.Nome == "" || tenantID == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar o nome!")
		return
	}
	if tp == "PF" && strings.TrimSpace(payload.Params.Documento) == "" {
		render.WriteError(w, http.StatusBadRequest, "Documento (CPF) obrigatorio para pessoa fisica")
		return
	}
	if strings.TrimSpace(payload.Params.Municipio.ID) == "" {
		render.WriteError(w, http.StatusBadRequest, "Municipio e obrigatorio")
		return
	}

	response, err := h.service.Create(r.Context(), service.EmpresaInput{
		Nome:               payload.Params.Nome,
		TenantID:           tenantID,
		MunicipioID:        strings.TrimSpace(payload.Params.Municipio.ID),
		RotinaID:           payload.Params.Rotina.ID,
		RotinaPFID:         strings.TrimSpace(payload.Params.RotinaPF.ID),
		Cnaes:              payload.Params.Cnaes,
		Bairro:             payload.Params.Bairro,
		TipoPessoa:         tp,
		Documento:          payload.Params.Documento,
		IE:                 payload.Params.IE,
		IM:                 payload.Params.IM,
		RegimeTributarioID: strings.TrimSpace(payload.Params.RegimeTributario.ID),
		TipoEmpresaID:      strings.TrimSpace(payload.Params.TipoEmpresa.ID),
	})
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *EmpresaHandler) Update(w http.ResponseWriter, r *http.Request) {
	var payload empresaEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	tenantID := middleware.TenantID(r.Context())
	tp := parseTipoPessoaPayload(payload.Params.TipoPessoa)
	if payload.Params.Nome == "" || tenantID == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar o nome!")
		return
	}
	if tp == "PF" && strings.TrimSpace(payload.Params.Documento) == "" {
		render.WriteError(w, http.StatusBadRequest, "Documento (CPF) obrigatorio para pessoa fisica")
		return
	}
	if strings.TrimSpace(payload.Params.Municipio.ID) == "" {
		render.WriteError(w, http.StatusBadRequest, "Municipio e obrigatorio")
		return
	}
	if strings.TrimSpace(payload.Params.ID) == "" {
		render.WriteError(w, http.StatusBadRequest, "Id da empresa e obrigatorio")
		return
	}

	response, err := h.service.Update(r.Context(), service.EmpresaInput{
		ID:                 strings.TrimSpace(payload.Params.ID),
		Nome:               payload.Params.Nome,
		TenantID:           tenantID,
		MunicipioID:        strings.TrimSpace(payload.Params.Municipio.ID),
		RotinaID:           payload.Params.Rotina.ID,
		RotinaPFID:         strings.TrimSpace(payload.Params.RotinaPF.ID),
		Cnaes:              payload.Params.Cnaes,
		Bairro:             payload.Params.Bairro,
		TipoPessoa:         tp,
		Documento:          payload.Params.Documento,
		IE:                 payload.Params.IE,
		IM:                 payload.Params.IM,
		RegimeTributarioID: strings.TrimSpace(payload.Params.RegimeTributario.ID),
		TipoEmpresaID:      strings.TrimSpace(payload.Params.TipoEmpresa.ID),
	})
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *EmpresaHandler) IniciarProcesso(w http.ResponseWriter, r *http.Request) {
	var payload empresaEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	id := strings.TrimSpace(payload.Params.ID)
	if id == "" {
		render.WriteError(w, http.StatusBadRequest, "Id nao informado")
		return
	}

	response, err := h.service.IniciarProcesso(r.Context(), id, middleware.TenantID(r.Context()))
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *EmpresaHandler) Delete(w http.ResponseWriter, r *http.Request) {
	var payload empresaEnvelope
	_ = json.NewDecoder(r.Body).Decode(&payload)
	id := strings.TrimSpace(payload.Params.ID)
	if id == "" {
		id = strings.TrimSpace(r.URL.Query().Get("id"))
	}

	if id == "" {
		render.WriteError(w, http.StatusBadRequest, "Favor informar o id!")
		return
	}

	response, err := h.service.Delete(r.Context(), id, middleware.TenantID(r.Context()))
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *EmpresaHandler) ListProcessos(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.TenantID(r.Context())
	empresaID := strings.TrimSpace(r.URL.Query().Get("empresa_id"))
	response, err := h.service.ListProcessos(r.Context(), empresaID, tenantID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}

func (h *EmpresaHandler) CreateProcesso(w http.ResponseWriter, r *http.Request) {
	var payload empresaEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	tenantID := middleware.TenantID(r.Context())
	empresaID := strings.TrimSpace(payload.Params.EmpresaID)
	descricao := strings.TrimSpace(payload.Params.Descricao)
	if empresaID == "" {
		render.WriteError(w, http.StatusBadRequest, "Empresa e obrigatoria")
		return
	}
	if descricao == "" {
		render.WriteError(w, http.StatusBadRequest, "Descricao do processo e obrigatoria")
		return
	}

	response, err := h.service.CreateProcesso(r.Context(), repository.EmpresaProcessoInput{
		EmpresaID: empresaID,
		TenantID:  tenantID,
		RotinaID:  strings.TrimSpace(payload.Params.Rotina.ID),
		Descricao: descricao,
	})
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}

func (h *EmpresaHandler) IniciarProcessoFilho(w http.ResponseWriter, r *http.Request) {
	var payload empresaEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	processoID := strings.TrimSpace(payload.Params.ProcessoID)
	empresaID := strings.TrimSpace(payload.Params.EmpresaID)
	if processoID == "" {
		render.WriteError(w, http.StatusBadRequest, "Processo nao informado")
		return
	}
	if empresaID == "" {
		render.WriteError(w, http.StatusBadRequest, "Empresa nao informada")
		return
	}
	tenantID := middleware.TenantID(r.Context())

	if _, err := h.service.IniciarProcesso(r.Context(), empresaID, tenantID); err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	response, err := h.service.IniciarProcessoFilho(r.Context(), processoID, tenantID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}

func (h *EmpresaHandler) MarcarCompromissosProcesso(w http.ResponseWriter, r *http.Request) {
	var payload empresaEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	processoID := strings.TrimSpace(payload.Params.ProcessoID)
	if processoID == "" {
		render.WriteError(w, http.StatusBadRequest, "Processo nao informado")
		return
	}
	response, err := h.service.MarcarCompromissosProcesso(r.Context(), processoID, middleware.TenantID(r.Context()))
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}

func parseIntEmpresa(value string, fallback int) int {
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func parseNomeFilterEmpresa(raw string) string {
	type filtersPayload struct {
		Nome struct {
			Value string `json:"value"`
		} `json:"nome"`
	}

	if strings.TrimSpace(raw) == "" {
		return ""
	}

	var payload filtersPayload
	if err := json.Unmarshal([]byte(raw), &payload); err == nil {
		return payload.Nome.Value
	}

	return ""
}
