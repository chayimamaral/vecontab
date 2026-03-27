package handlers

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/chayimamaral/vecontab/backendgo/internal/httpapi/middleware"
	"github.com/chayimamaral/vecontab/backendgo/internal/httpapi/render"
	"github.com/chayimamaral/vecontab/backendgo/internal/service"
)

type EmpresaAgendaHandler struct {
	service *service.EmpresaAgendaService
}

func NewEmpresaAgendaHandler(service *service.EmpresaAgendaService) *EmpresaAgendaHandler {
	return &EmpresaAgendaHandler{service: service}
}

func (h *EmpresaAgendaHandler) List(w http.ResponseWriter, r *http.Request) {
	empresaID := strings.TrimSpace(r.URL.Query().Get("empresa_id"))
	if empresaID == "" {
		render.WriteError(w, http.StatusBadRequest, "empresa_id e obrigatorio")
		return
	}

	response, err := h.service.ListByEmpresa(r.Context(), empresaID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *EmpresaAgendaHandler) Acompanhamento(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.TenantID(r.Context())
	if strings.TrimSpace(tenantID) == "" {
		render.WriteError(w, http.StatusUnauthorized, "tenant nao identificado")
		return
	}

	response, err := h.service.AcompanhamentoByTenant(r.Context(), tenantID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

type gerarAgendaEnvelope struct {
	Params struct {
		EmpresaID     string `json:"empresa_id"`
		TipoEmpresaID string `json:"tipo_empresa_id"`
		DataInicio    string `json:"data_inicio"` // formato YYYY-MM-DD
	} `json:"params"`
}

func (h *EmpresaAgendaHandler) Gerar(w http.ResponseWriter, r *http.Request) {
	_ = middleware.TenantID(r.Context())

	var payload gerarAgendaEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	p := payload.Params
	if p.EmpresaID == "" || p.TipoEmpresaID == "" {
		render.WriteError(w, http.StatusBadRequest, "empresa_id e tipo_empresa_id sao obrigatorios")
		return
	}

	dataInicio := time.Now()
	if p.DataInicio != "" {
		parsed, err := time.Parse("2006-01-02", p.DataInicio)
		if err != nil {
			render.WriteError(w, http.StatusBadRequest, "data_inicio invalida (use YYYY-MM-DD)")
			return
		}
		dataInicio = parsed
	}

	response, err := h.service.GerarAgenda(r.Context(), p.EmpresaID, p.TipoEmpresaID, dataInicio)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

type updateStatusEnvelope struct {
	Params struct {
		ID     string `json:"id"`
		Status string `json:"status"`
	} `json:"params"`
}

func (h *EmpresaAgendaHandler) UpdateStatus(w http.ResponseWriter, r *http.Request) {
	var payload updateStatusEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	p := payload.Params
	if p.ID == "" || p.Status == "" {
		render.WriteError(w, http.StatusBadRequest, "id e status sao obrigatorios")
		return
	}

	status := strings.ToUpper(p.Status)
	if status != "PENDENTE" && status != "PAGO" && status != "ATRASADO" {
		render.WriteError(w, http.StatusBadRequest, "status invalido (PENDENTE|PAGO|ATRASADO)")
		return
	}

	if err := h.service.UpdateStatus(r.Context(), p.ID, status); err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, map[string]string{"message": "status atualizado"})
}
