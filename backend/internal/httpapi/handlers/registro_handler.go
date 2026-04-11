package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/httpapi/middleware"
	"github.com/chayimamaral/vecontab/backend/internal/httpapi/render"
	"github.com/chayimamaral/vecontab/backend/internal/service"
)

type RegistroHandler struct {
	service *service.RegistroService
}

type registroCreatePayload struct {
	Nome     string `json:"nome"`
	Email    string `json:"email"`
	Password string `json:"password"`
}

type registroUpdatePayload struct {
	CNPJ        string `json:"cnpj"`
	CEP         string `json:"cep"`
	Endereco    string `json:"endereco"`
	Bairro      string `json:"bairro"`
	Cidade      string `json:"cidade"`
	Estado      string `json:"estado"`
	Telefone    string `json:"telefone"`
	Email       string `json:"email"`
	IE          string `json:"ie"`
	IM          string `json:"im"`
	RazaoSocial string `json:"razaosocial"`
	Fantasia    string `json:"fantasia"`
	Observacoes string `json:"observacoes"`
}

type tenantDadosUpdatePayload struct {
	TenantID    string `json:"tenantId"`
	CNPJ        string `json:"cnpj"`
	CEP         string `json:"cep"`
	Endereco    string `json:"endereco"`
	Bairro      string `json:"bairro"`
	Cidade      string `json:"cidade"`
	Estado      string `json:"estado"`
	Telefone    string `json:"telefone"`
	Email       string `json:"email"`
	IE          string `json:"ie"`
	IM          string `json:"im"`
	RazaoSocial string `json:"razaosocial"`
	Fantasia    string `json:"fantasia"`
	Observacoes string `json:"observacoes"`
}

func NewRegistroHandler(service *service.RegistroService) *RegistroHandler {
	return &RegistroHandler{service: service}
}

func (h *RegistroHandler) Create(w http.ResponseWriter, r *http.Request) {
	var payload registroCreatePayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if strings.TrimSpace(payload.Nome) == "" || strings.TrimSpace(payload.Email) == "" || strings.TrimSpace(payload.Password) == "" {
		render.WriteError(w, http.StatusBadRequest, "Informacoes faltando!")
		return
	}

	response, err := h.service.Create(r.Context(), service.RegistroCreateInput{
		Nome:     payload.Nome,
		Email:    payload.Email,
		Password: payload.Password,
	})
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *RegistroHandler) Detail(w http.ResponseWriter, r *http.Request) {
	response, err := h.service.Detail(r.Context(), middleware.TenantID(r.Context()))
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *RegistroHandler) TenantDadosDetail(w http.ResponseWriter, r *http.Request) {
	tenantID := strings.TrimSpace(r.URL.Query().Get("tenantId"))
	if tenantID == "" {
		render.WriteError(w, http.StatusBadRequest, "Informe tenantId")
		return
	}

	response, err := h.service.Detail(r.Context(), tenantID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *RegistroHandler) TenantDadosUpdate(w http.ResponseWriter, r *http.Request) {
	var payload tenantDadosUpdatePayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if strings.TrimSpace(payload.TenantID) == "" {
		render.WriteError(w, http.StatusBadRequest, "tenantId obrigatorio")
		return
	}

	response, err := h.service.UpdateByTenantID(r.Context(), payload.TenantID, service.RegistroUpdateInput{
		CNPJ:        payload.CNPJ,
		CEP:         payload.CEP,
		Endereco:    payload.Endereco,
		Bairro:      payload.Bairro,
		Cidade:      payload.Cidade,
		Estado:      payload.Estado,
		Telefone:    payload.Telefone,
		Email:       payload.Email,
		IE:          payload.IE,
		IM:          payload.IM,
		RazaoSocial: payload.RazaoSocial,
		Fantasia:    payload.Fantasia,
		Observacoes: payload.Observacoes,
	})
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *RegistroHandler) Update(w http.ResponseWriter, r *http.Request) {
	var payload registroUpdatePayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	response, err := h.service.Update(r.Context(), middleware.UserID(r.Context()), service.RegistroUpdateInput{
		CNPJ:        payload.CNPJ,
		CEP:         payload.CEP,
		Endereco:    payload.Endereco,
		Bairro:      payload.Bairro,
		Cidade:      payload.Cidade,
		Estado:      payload.Estado,
		Telefone:    payload.Telefone,
		Email:       payload.Email,
		IE:          payload.IE,
		IM:          payload.IM,
		RazaoSocial: payload.RazaoSocial,
		Fantasia:    payload.Fantasia,
		Observacoes: payload.Observacoes,
	})
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}
