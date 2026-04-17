package handlers

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/chayimamaral/vecontab/backend/internal/httpapi/middleware"
	"github.com/chayimamaral/vecontab/backend/internal/httpapi/render"
	"github.com/chayimamaral/vecontab/backend/internal/repository"
	"github.com/chayimamaral/vecontab/backend/internal/service"
)

type EmpresaAgendaHandler struct {
	service *service.EmpresaAgendaService
	monitor *service.MonitorOperacaoService
}

func NewEmpresaAgendaHandler(svc *service.EmpresaAgendaService, m *service.MonitorOperacaoService) *EmpresaAgendaHandler {
	return &EmpresaAgendaHandler{service: svc, monitor: m}
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
	tenantID := middleware.TenantID(r.Context())
	if strings.TrimSpace(tenantID) == "" {
		render.WriteError(w, http.StatusUnauthorized, "tenant nao identificado")
		return
	}

	var payload gerarAgendaEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	p := payload.Params
	if p.EmpresaID == "" {
		render.WriteError(w, http.StatusBadRequest, "empresa_id e obrigatorio")
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
	if h.monitor != nil {
		tid := tenantID
		uid := strings.TrimSpace(middleware.UserID(r.Context()))
		var uidPtr *string
		if uid != "" {
			uidPtr = &uid
		}
		det := map[string]any{
			"empresa_id":      strings.TrimSpace(p.EmpresaID),
			"tipo_empresa_id": strings.TrimSpace(p.TipoEmpresaID),
			"data_inicio":     dataInicio.Format("2006-01-02"),
		}
		st := domain.MonitorOperacaoStatusSucesso
		var msg string
		if err != nil {
			st = domain.MonitorOperacaoStatusErro
			msg = err.Error()
		} else {
			msg = response.Message
			det["quantidade_obrigacoes"] = len(response.Itens)
		}
		_, _ = h.monitor.Registrar(r.Context(), repository.MonitorOperacaoInsert{
			TenantID: tid,
			UserID:   uidPtr,
			Origem:   domain.MonitorOperacaoOrigemManual,
			Tipo:     domain.MonitorOperacaoTipoGeracaoAgenda,
			Status:   st,
			Mensagem: &msg,
			Detalhe:  det,
		})
	}
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
	if status != "PENDENTE" && status != "PAGO" && status != "ATRASADO" && status != "CONCLUIDO" {
		render.WriteError(w, http.StatusBadRequest, "status invalido (PENDENTE|PAGO|ATRASADO|CONCLUIDO)")
		return
	}

	tenantID := middleware.TenantID(r.Context())
	if strings.TrimSpace(tenantID) == "" {
		render.WriteError(w, http.StatusUnauthorized, "tenant nao identificado")
		return
	}

	if err := h.service.UpdateStatus(r.Context(), tenantID, p.ID, status); err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, map[string]string{"message": "status atualizado"})
}

type updateItemEnvelope struct {
	Params struct {
		ID             string   `json:"id"`
		DataVencimento *string  `json:"data_vencimento"`
		ValorEstimado  *float64 `json:"valor_estimado"`
	} `json:"params"`
}

func (h *EmpresaAgendaHandler) UpdateItem(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.TenantID(r.Context())
	if strings.TrimSpace(tenantID) == "" {
		render.WriteError(w, http.StatusUnauthorized, "tenant nao identificado")
		return
	}

	var payload updateItemEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	p := payload.Params
	if strings.TrimSpace(p.ID) == "" {
		render.WriteError(w, http.StatusBadRequest, "id e obrigatorio")
		return
	}

	if err := h.service.UpdateItem(r.Context(), tenantID, p.ID, p.DataVencimento, p.ValorEstimado); err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, map[string]string{"message": "item atualizado"})
}
