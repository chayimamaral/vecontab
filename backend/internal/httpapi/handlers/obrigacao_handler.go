package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/chayimamaral/mare/backend/internal/httpapi/render"
	"github.com/chayimamaral/mare/backend/internal/repository"
	"github.com/chayimamaral/mare/backend/internal/service"
)

type ObrigacaoHandler struct {
	service *service.ObrigacaoService
}

type obrigacaoEnvelope struct {
	Params struct {
		ID            string `json:"id"`
		TipoEmpresaID string `json:"tipo_empresa_id"`
		Descricao     string `json:"descricao"`
		DiaBase       int    `json:"dia_base"`
		MesBase       *int   `json:"mes_base"`
		Frequencia    string `json:"frequencia"`
		Tipo          string `json:"tipo"`
	} `json:"params"`
}

func NewObrigacaoHandler(service *service.ObrigacaoService) *ObrigacaoHandler {
	return &ObrigacaoHandler{service: service}
}

func (h *ObrigacaoHandler) List(w http.ResponseWriter, r *http.Request) {
	tipoEmpresaID := strings.TrimSpace(r.URL.Query().Get("tipo_empresa_id"))
	if tipoEmpresaID == "" {
		render.WriteError(w, http.StatusBadRequest, "tipo_empresa_id e obrigatorio")
		return
	}

	response, err := h.service.ListByTipoEmpresa(r.Context(), tipoEmpresaID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *ObrigacaoHandler) Create(w http.ResponseWriter, r *http.Request) {
	var payload obrigacaoEnvelope
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	p := payload.Params
	if p.TipoEmpresaID == "" || p.Descricao == "" {
		render.WriteError(w, http.StatusBadRequest, "tipo_empresa_id e descricao sao obrigatorios")
		return
	}

	freq := strings.ToUpper(strings.TrimSpace(p.Frequencia))
	if freq != "MENSAL" && freq != "ANUAL" {
		freq = "MENSAL"
	}

	tipo := strings.ToUpper(strings.TrimSpace(p.Tipo))
	if tipo != "TRIBUTO" && tipo != "INFORMATIVA" {
		tipo = "TRIBUTO"
	}

	input := repository.ObrigacaoUpsertInput{
		TipoEmpresaID: p.TipoEmpresaID,
		Descricao:     p.Descricao,
		DiaBase:       p.DiaBase,
		MesBase:       p.MesBase,
		Frequencia:    freq,
		Tipo:          tipo,
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
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	p := payload.Params
	if p.ID == "" {
		render.WriteError(w, http.StatusBadRequest, "ID e obrigatorio")
		return
	}

	freq := strings.ToUpper(strings.TrimSpace(p.Frequencia))
	if freq != "MENSAL" && freq != "ANUAL" {
		freq = "MENSAL"
	}

	tipo := strings.ToUpper(strings.TrimSpace(p.Tipo))
	if tipo != "TRIBUTO" && tipo != "INFORMATIVA" {
		tipo = "TRIBUTO"
	}

	input := repository.ObrigacaoUpsertInput{
		ID:         p.ID,
		Descricao:  p.Descricao,
		DiaBase:    p.DiaBase,
		MesBase:    p.MesBase,
		Frequencia: freq,
		Tipo:       tipo,
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
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if payload.Params.ID == "" {
		render.WriteError(w, http.StatusBadRequest, "ID e obrigatorio")
		return
	}

	if err := h.service.Delete(r.Context(), payload.Params.ID); err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, map[string]string{"message": "obrigacao removida"})
}
