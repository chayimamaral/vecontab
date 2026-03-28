package handlers

import (
	"net/http"

	"github.com/chayimamaral/mare/backend/internal/httpapi/render"
	"github.com/chayimamaral/mare/backend/internal/service"
)

type NodeHandler struct {
	service *service.NodeService
}

func NewNodeHandler(service *service.NodeService) *NodeHandler {
	return &NodeHandler{service: service}
}

func (h *NodeHandler) Nodes(w http.ResponseWriter, r *http.Request) {
	response, err := h.service.Nodes(r.Context())
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}

func (h *NodeHandler) Family(w http.ResponseWriter, r *http.Request) {
	response, err := h.service.Family(r.Context())
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}

func (h *NodeHandler) Recurso(w http.ResponseWriter, r *http.Request) {
	response, err := h.service.Recurso(r.Context())
	if err != nil {
		render.WriteError(w, http.StatusBadRequest, err.Error())
		return
	}
	render.WriteJSON(w, http.StatusOK, response)
}
