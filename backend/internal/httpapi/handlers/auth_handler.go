package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/chayimamaral/mare/backend/internal/httpapi/render"
	"github.com/chayimamaral/mare/backend/internal/service"
)

type AuthHandler struct {
	service *service.AuthService
}

func NewAuthHandler(service *service.AuthService) *AuthHandler {
	return &AuthHandler{service: service}
}

func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var input service.LoginInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		render.WriteError(w, http.StatusBadRequest, "JSON invalido")
		return
	}

	if input.Email == "" || input.Password == "" {
		render.WriteError(w, http.StatusBadRequest, "Email e password sao obrigatorios")
		return
	}

	response, err := h.service.Login(r.Context(), input)
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}

	render.WriteJSON(w, http.StatusOK, response)
}
