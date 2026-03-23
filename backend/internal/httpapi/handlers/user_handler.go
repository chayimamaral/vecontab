package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"github.com/chayimamaral/vecontab/backendgo/internal/httpapi/middleware"
	"github.com/chayimamaral/vecontab/backendgo/internal/httpapi/render"
	"github.com/chayimamaral/vecontab/backendgo/internal/service"
)

type UserHandler struct {
	service *service.UserService
}

type createUserPayload struct {
	ID       string `json:"id"`
	Nome     string `json:"nome"`
	Email    string `json:"email"`
	Password string `json:"password"`
	Role     string `json:"role"`
	TenantID string `json:"tenantId"`
}

func NewUserHandler(service *service.UserService) *UserHandler {
	return &UserHandler{service: service}
}

func (h *UserHandler) Me(w http.ResponseWriter, r *http.Request) {
	response, err := h.service.Detail(r.Context(), middleware.UserID(r.Context()))
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *UserHandler) UserRole(w http.ResponseWriter, r *http.Request) {
	response, err := h.service.UserRole(r.Context(), middleware.UserID(r.Context()))
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *UserHandler) TenantID(w http.ResponseWriter, r *http.Request) {
	response, err := h.service.TenantID(r.Context(), middleware.UserID(r.Context()))
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *UserHandler) List(w http.ResponseWriter, r *http.Request) {
	input := service.ListUsersInput{
		First:     parseIntUser(r.URL.Query().Get("first"), 0),
		Rows:      parseIntUser(r.URL.Query().Get("rows"), 25),
		SortField: r.URL.Query().Get("sortField"),
		SortOrder: parseIntUser(r.URL.Query().Get("sortOrder"), 1),
		Nome:      parseNomeFilterUser(r.URL.Query().Get("filters")),
		TenantID:  middleware.TenantID(r.Context()),
		Role:      middleware.Role(r.Context()),
	}

	response, err := h.service.List(r.Context(), input)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *UserHandler) Create(w http.ResponseWriter, r *http.Request) {
	var payload createUserPayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if payload.Nome == "" || payload.Email == "" || payload.Password == "" {
		render.WriteError(w, http.StatusBadRequest, "Informacoes faltando!")
		return
	}

	requesterRole := middleware.Role(r.Context())
	requesterTenantID := middleware.TenantID(r.Context())
	if requesterRole != "ADMIN" && requesterRole != "SUPER" {
		render.WriteError(w, http.StatusForbidden, "Usuario nao autorizado")
		return
	}

	targetRole := strings.ToUpper(strings.TrimSpace(payload.Role))
	if targetRole == "" {
		targetRole = "USER"
	}

	if targetRole != "USER" && targetRole != "ADMIN" && targetRole != "SUPER" {
		render.WriteError(w, http.StatusBadRequest, "Role invalida")
		return
	}

	if requesterRole == "ADMIN" && targetRole == "SUPER" {
		render.WriteError(w, http.StatusForbidden, "Usuario nao autorizado")
		return
	}

	targetTenantID := payload.TenantID
	if requesterRole == "ADMIN" {
		targetTenantID = requesterTenantID
	}

	if strings.TrimSpace(targetTenantID) == "" {
		render.WriteError(w, http.StatusBadRequest, "Tenant do usuario nao informado")
		return
	}

	response, err := h.service.Create(r.Context(), service.CreateUserInput{
		Nome:     payload.Nome,
		Email:    payload.Email,
		Password: payload.Password,
		Role:     targetRole,
		TenantID: targetTenantID,
	})
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *UserHandler) Update(w http.ResponseWriter, r *http.Request) {
	var payload createUserPayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if strings.TrimSpace(payload.ID) == "" {
		render.WriteError(w, http.StatusBadRequest, "ID e obrigatorio")
		return
	}

	if strings.TrimSpace(payload.Nome) == "" || strings.TrimSpace(payload.Email) == "" {
		render.WriteError(w, http.StatusBadRequest, "Informacoes faltando!")
		return
	}

	requesterRole := middleware.Role(r.Context())
	requesterTenantID := middleware.TenantID(r.Context())
	if requesterRole != "ADMIN" && requesterRole != "SUPER" {
		render.WriteError(w, http.StatusForbidden, "Usuario nao autorizado")
		return
	}

	targetRole := strings.ToUpper(strings.TrimSpace(payload.Role))
	if targetRole == "" {
		targetRole = "USER"
	}

	if targetRole != "USER" && targetRole != "ADMIN" && targetRole != "SUPER" {
		render.WriteError(w, http.StatusBadRequest, "Role invalida")
		return
	}

	if requesterRole == "ADMIN" && targetRole == "SUPER" {
		render.WriteError(w, http.StatusForbidden, "Usuario nao autorizado")
		return
	}

	targetTenantID := payload.TenantID
	if requesterRole == "ADMIN" {
		targetTenantID = requesterTenantID
	}

	if strings.TrimSpace(targetTenantID) == "" {
		render.WriteError(w, http.StatusBadRequest, "Tenant do usuario nao informado")
		return
	}

	response, err := h.service.Update(r.Context(), service.UpdateUserInput{
		ID:       payload.ID,
		Nome:     payload.Nome,
		Email:    payload.Email,
		Role:     targetRole,
		TenantID: targetTenantID,
	})
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func (h *UserHandler) Delete(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(r.URL.Query().Get("id"))
	if id == "" {
		var payload createUserPayload
		if err := json.NewDecoder(r.Body).Decode(&payload); err == nil {
			id = strings.TrimSpace(payload.ID)
		}
	}

	if id == "" {
		render.WriteError(w, http.StatusBadRequest, "ID e obrigatorio")
		return
	}

	requesterRole := middleware.Role(r.Context())
	if requesterRole != "ADMIN" && requesterRole != "SUPER" {
		render.WriteError(w, http.StatusForbidden, "Usuario nao autorizado")
		return
	}

	response, err := h.service.Delete(r.Context(), id)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}

func parseIntUser(value string, fallback int) int {
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}

	return parsed
}

func parseNomeFilterUser(raw string) string {
	if strings.TrimSpace(raw) == "" {
		return ""
	}

	type filtersPayload struct {
		Nome struct {
			Value string `json:"value"`
		} `json:"nome"`
	}

	var payload filtersPayload
	if err := json.Unmarshal([]byte(raw), &payload); err == nil {
		return payload.Nome.Value
	}

	return ""
}
