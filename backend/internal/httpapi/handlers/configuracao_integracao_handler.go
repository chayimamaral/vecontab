package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/domain"
	"github.com/chayimamaral/vecontab/backend/internal/httpapi/middleware"
	"github.com/chayimamaral/vecontab/backend/internal/httpapi/render"
	"github.com/chayimamaral/vecontab/backend/internal/service"
)

type ConfiguracaoIntegracaoHandler struct {
	service *service.ConfiguracaoIntegracaoService
}

func NewConfiguracaoIntegracaoHandler(service *service.ConfiguracaoIntegracaoService) *ConfiguracaoIntegracaoHandler {
	return &ConfiguracaoIntegracaoHandler{service: service}
}

func (h *ConfiguracaoIntegracaoHandler) GetChavesSuper(w http.ResponseWriter, r *http.Request) {
	role := strings.ToUpper(strings.TrimSpace(middleware.Role(r.Context())))
	if role != "SUPER" {
		render.WriteError(w, http.StatusForbidden, "Somente SUPER")
		return
	}
	tenantID := middleware.TenantID(r.Context())
	resp, err := h.service.GetChavesSuper(r.Context(), tenantID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, map[string]any{"chaves": resp})
}

func (h *ConfiguracaoIntegracaoHandler) SaveChavesSuper(w http.ResponseWriter, r *http.Request) {
	role := strings.ToUpper(strings.TrimSpace(middleware.Role(r.Context())))
	if role != "SUPER" {
		render.WriteError(w, http.StatusForbidden, "Somente SUPER")
		return
	}
	var payload domain.ChavesSuper
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}
	payload.TenantID = middleware.TenantID(r.Context())
	if err := h.service.SaveChavesSuper(r.Context(), payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, map[string]any{"success": true})
}

func (h *ConfiguracaoIntegracaoHandler) GetTenantConfiguracoes(w http.ResponseWriter, r *http.Request) {
	role := strings.ToUpper(strings.TrimSpace(middleware.Role(r.Context())))
	if role != "ADMIN" && role != "SUPER" {
		render.WriteError(w, http.StatusForbidden, "Somente ADMIN/SUPER")
		return
	}
	tenantID := middleware.TenantID(r.Context())
	resp, err := h.service.GetTenantConfiguracoes(r.Context(), tenantID)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, map[string]any{"configuracoes": resp})
}

func (h *ConfiguracaoIntegracaoHandler) SaveTenantConfiguracoes(w http.ResponseWriter, r *http.Request) {
	role := strings.ToUpper(strings.TrimSpace(middleware.Role(r.Context())))
	if role != "ADMIN" && role != "SUPER" {
		render.WriteError(w, http.StatusForbidden, "Somente ADMIN/SUPER")
		return
	}
	var payload domain.TenantConfiguracoes
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}
	payload.TenantID = middleware.TenantID(r.Context())
	if err := h.service.SaveTenantConfiguracoes(r.Context(), payload); err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, map[string]any{"success": true})
}
