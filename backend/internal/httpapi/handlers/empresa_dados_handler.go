package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/httpapi/middleware"
	"github.com/chayimamaral/vecontab/backend/internal/httpapi/render"
	"github.com/chayimamaral/vecontab/backend/internal/repository"
	"github.com/chayimamaral/vecontab/backend/internal/service"
)

type EmpresaDadosHandler struct {
	service *service.EmpresaDadosService
}

type empresaDadosEnvelope struct {
	Params struct {
		ID               string `json:"id"`
		MunicipioID      string `json:"municipio_id"`
		Bairro           string `json:"bairro"`
		CNPJ             string `json:"cnpj"`
		CapitalSocial    *float64 `json:"capital_social"`
		Endereco         string `json:"endereco"`
		Numero           string `json:"numero"`
		CEP              string `json:"cep"`
		EmailContato     string `json:"email_contato"`
		Telefone         string `json:"telefone"`
		Telefone2        string `json:"telefone2"`
		DataAbertura     string `json:"data_abertura"`
		DataEncerramento string `json:"data_encerramento"`
		Observacao       string `json:"observacao"`
	} `json:"params"`
}

func NewEmpresaDadosHandler(svc *service.EmpresaDadosService) *EmpresaDadosHandler {
	return &EmpresaDadosHandler{service: svc}
}

func (h *EmpresaDadosHandler) Get(w http.ResponseWriter, r *http.Request) {
	empresaID := strings.TrimSpace(r.URL.Query().Get("empresa_id"))
	if empresaID == "" {
		render.WriteError(w, http.StatusBadRequest, "empresa_id obrigatorio")
		return
	}

	tenantID := middleware.TenantID(r.Context())
	item, err := h.service.Get(r.Context(), empresaID, tenantID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, item)
}

func (h *EmpresaDadosHandler) Upsert(w http.ResponseWriter, r *http.Request) {
	var payload empresaDadosEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	id := strings.TrimSpace(payload.Params.ID)
	if id == "" {
		render.WriteError(w, http.StatusBadRequest, "id da empresa obrigatorio")
		return
	}

	err := h.service.Save(r.Context(), repository.EmpresaDadosUpsertInput{
		EmpresaID:        id,
		TenantID:         middleware.TenantID(r.Context()),
		MunicipioID:      strings.TrimSpace(payload.Params.MunicipioID),
		Bairro:           payload.Params.Bairro,
		CNPJ:             payload.Params.CNPJ,
		CapitalSocial:    payload.Params.CapitalSocial,
		Endereco:         payload.Params.Endereco,
		Numero:           payload.Params.Numero,
		CEP:              payload.Params.CEP,
		EmailContato:     payload.Params.EmailContato,
		Telefone:         payload.Params.Telefone,
		Telefone2:        payload.Params.Telefone2,
		DataAbertura:     payload.Params.DataAbertura,
		DataEncerramento: payload.Params.DataEncerramento,
		Observacao:       payload.Params.Observacao,
	})
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	item, err := h.service.Get(r.Context(), id, middleware.TenantID(r.Context()))
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, item)
}
