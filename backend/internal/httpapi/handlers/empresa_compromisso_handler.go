package handlers

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/chayimamaral/vecontab/backend/internal/httpapi/middleware"
	"github.com/chayimamaral/vecontab/backend/internal/httpapi/render"
	"github.com/chayimamaral/vecontab/backend/internal/service"
)

type EmpresaCompromissoHandler struct {
	service *service.EmpresaCompromissoService
}

func NewEmpresaCompromissoHandler(s *service.EmpresaCompromissoService) *EmpresaCompromissoHandler {
	return &EmpresaCompromissoHandler{service: s}
}

func (h *EmpresaCompromissoHandler) Acompanhamento(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.TenantID(r.Context())
	if strings.TrimSpace(tenantID) == "" {
		render.WriteError(w, http.StatusUnauthorized, "tenant nao identificado")
		return
	}
	resp, err := h.service.AcompanhamentoByTenant(r.Context(), tenantID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, resp)
}

type gerarEmpresaCompromissoEnvelope struct {
	Params struct {
		EmpresaID  string `json:"empresa_id"`
		DataInicio string `json:"data_inicio"`
	} `json:"params"`
}

func (h *EmpresaCompromissoHandler) Gerar(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.TenantID(r.Context())
	if strings.TrimSpace(tenantID) == "" {
		render.WriteError(w, http.StatusUnauthorized, "tenant nao identificado")
		return
	}

	var payload gerarEmpresaCompromissoEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}
	dataInicio := time.Now()
	if payload.Params.DataInicio != "" {
		parsed, err := time.Parse("2006-01-02", payload.Params.DataInicio)
		if err != nil {
			render.WriteError(w, http.StatusBadRequest, "data_inicio invalida (use YYYY-MM-DD)")
			return
		}
		dataInicio = parsed
	}

	resp, err := h.service.Gerar(r.Context(), payload.Params.EmpresaID, tenantID, dataInicio)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, resp)
}

type empresaCompromissoStatusEnvelope struct {
	Params struct {
		ID     string `json:"id"`
		Status string `json:"status"`
	} `json:"params"`
}

func (h *EmpresaCompromissoHandler) UpdateStatus(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.TenantID(r.Context())
	if strings.TrimSpace(tenantID) == "" {
		render.WriteError(w, http.StatusUnauthorized, "tenant nao identificado")
		return
	}
	var payload empresaCompromissoStatusEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}
	if strings.TrimSpace(payload.Params.ID) == "" || strings.TrimSpace(payload.Params.Status) == "" {
		render.WriteError(w, http.StatusBadRequest, "id e status sao obrigatorios")
		return
	}
	if err := h.service.UpdateStatus(r.Context(), tenantID, payload.Params.ID, payload.Params.Status); err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, map[string]string{"message": "status atualizado"})
}

type empresaCompromissoItemEnvelope struct {
	Params struct {
		ID             string   `json:"id"`
		DataVencimento *string  `json:"data_vencimento"`
		Valor          *float64 `json:"valor"`
	} `json:"params"`
}

func (h *EmpresaCompromissoHandler) UpdateItem(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.TenantID(r.Context())
	if strings.TrimSpace(tenantID) == "" {
		render.WriteError(w, http.StatusUnauthorized, "tenant nao identificado")
		return
	}
	var payload empresaCompromissoItemEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}
	if strings.TrimSpace(payload.Params.ID) == "" {
		render.WriteError(w, http.StatusBadRequest, "id e obrigatorio")
		return
	}
	if err := h.service.UpdateItem(r.Context(), tenantID, payload.Params.ID, payload.Params.DataVencimento, payload.Params.Valor); err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, map[string]string{"message": "item atualizado"})
}
