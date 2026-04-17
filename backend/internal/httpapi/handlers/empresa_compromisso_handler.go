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

type EmpresaCompromissoHandler struct {
	service *service.EmpresaCompromissoService
	monitor *service.MonitorOperacaoService
}

func NewEmpresaCompromissoHandler(s *service.EmpresaCompromissoService, m *service.MonitorOperacaoService) *EmpresaCompromissoHandler {
	return &EmpresaCompromissoHandler{service: s, monitor: m}
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

func (h *EmpresaCompromissoHandler) FormOptions(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.TenantID(r.Context())
	if strings.TrimSpace(tenantID) == "" {
		render.WriteError(w, http.StatusUnauthorized, "tenant nao identificado")
		return
	}
	resp, err := h.service.FormOptionsByTenant(r.Context(), tenantID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, resp)
}

func (h *EmpresaCompromissoHandler) ObrigacoesByEmpresa(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.TenantID(r.Context())
	if strings.TrimSpace(tenantID) == "" {
		render.WriteError(w, http.StatusUnauthorized, "tenant nao identificado")
		return
	}
	empresaID := strings.TrimSpace(r.URL.Query().Get("empresa_id"))
	resp, err := h.service.ObrigacoesByEmpresa(r.Context(), tenantID, empresaID)
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
	if h.monitor != nil {
		tid := tenantID
		uid := strings.TrimSpace(middleware.UserID(r.Context()))
		var uidPtr *string
		if uid != "" {
			uidPtr = &uid
		}
		det := map[string]any{
			"empresa_id":  strings.TrimSpace(payload.Params.EmpresaID),
			"data_inicio": dataInicio.Format("2006-01-02"),
		}
		st := domain.MonitorOperacaoStatusSucesso
		var msg string
		if err != nil {
			st = domain.MonitorOperacaoStatusErro
			msg = err.Error()
		} else {
			msg = resp.Message
			det["quantidade"] = resp.Quantidade
		}
		monitorID, regErr := h.monitor.Registrar(r.Context(), repository.MonitorOperacaoInsert{
			TenantID: tid,
			UserID:   uidPtr,
			Origem:   domain.MonitorOperacaoOrigemManual,
			Tipo:     domain.MonitorOperacaoTipoGeracaoCompromissos,
			Status:   st,
			Mensagem: &msg,
			Detalhe:  det,
		})
		if regErr == nil && err == nil && len(resp.Itens) > 0 {
			compromissoIDs := make([]string, 0, len(resp.Itens))
			for _, it := range resp.Itens {
				if strings.TrimSpace(it.ID) != "" {
					compromissoIDs = append(compromissoIDs, it.ID)
				}
			}
			_ = h.monitor.VincularCompromissos(r.Context(), monitorID, compromissoIDs)
		}
	}
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

type empresaCompromissoCreateManualEnvelope struct {
	Params struct {
		EmpresaID              string   `json:"empresa_id"`
		TipoempresaObrigacaoID string   `json:"tipoempresa_obrigacao_id"`
		Descricao              string   `json:"descricao"`
		DataVencimento         string   `json:"data_vencimento"`
		Valor                  *float64 `json:"valor"`
		Observacao             string   `json:"observacao"`
		Status                 string   `json:"status"`
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

func (h *EmpresaCompromissoHandler) CreateManual(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.TenantID(r.Context())
	if strings.TrimSpace(tenantID) == "" {
		render.WriteError(w, http.StatusUnauthorized, "tenant nao identificado")
		return
	}
	var payload empresaCompromissoCreateManualEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}
	venc, err := time.Parse("2006-01-02", strings.TrimSpace(payload.Params.DataVencimento))
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, "data_vencimento invalida (use YYYY-MM-DD)")
		return
	}
	id, err := h.service.CreateManual(r.Context(), tenantID, service.EmpresaCompromissoCreateManualInput{
		EmpresaID:              payload.Params.EmpresaID,
		TipoempresaObrigacaoID: payload.Params.TipoempresaObrigacaoID,
		Descricao:              payload.Params.Descricao,
		Vencimento:             venc,
		Valor:                  payload.Params.Valor,
		Observacao:             payload.Params.Observacao,
		Status:                 payload.Params.Status,
	})
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, map[string]string{"id": id, "message": "compromisso incluido"})
}
