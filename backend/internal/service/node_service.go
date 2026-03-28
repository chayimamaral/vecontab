package service

import (
	"context"

	"github.com/chayimamaral/vecontab/backend/internal/repository"
)

type NodeService struct {
	repo *repository.NodeRepository
}

type NodeResponse struct {
	Data any `json:"data"`
}

type NodeTreeNode struct {
	ID        string         `json:"id"`
	Descricao string         `json:"descricao"`
	ParentID  *string        `json:"parent_id"`
	Children  []NodeTreeNode `json:"children,omitempty"`
}

func NewNodeService(repo *repository.NodeRepository) *NodeService {
	return &NodeService{repo: repo}
}

func (s *NodeService) Nodes(ctx context.Context) (NodeResponse, error) {
	data, err := s.repo.Nodes(ctx)
	if err != nil {
		return NodeResponse{}, err
	}
	return NodeResponse{Data: data}, nil
}

func (s *NodeService) Family(ctx context.Context) (NodeResponse, error) {
	data, err := s.repo.Family(ctx)
	if err != nil {
		return NodeResponse{}, err
	}
	return NodeResponse{Data: data}, nil
}

func (s *NodeService) Recurso(ctx context.Context) (NodeResponse, error) {
	flat, err := s.repo.Recurso(ctx)
	if err != nil {
		return NodeResponse{}, err
	}
	return NodeResponse{Data: buildNestedPassos(flat, nil)}, nil
}

// buildNestedPassos mirrors the TypeScript buildNestedObjects function.
func buildNestedPassos(all []repository.NodePasso, parentID *string) []NodeTreeNode {
	result := make([]NodeTreeNode, 0)
	for _, p := range all {
		if strPtrEq(p.ParentID, parentID) {
			node := NodeTreeNode{
				ID:        p.ID,
				Descricao: p.Descricao,
				ParentID:  p.ParentID,
			}
			children := buildNestedPassos(all, &p.ID)
			if len(children) > 0 {
				node.Children = children
			}
			result = append(result, node)
		}
	}
	return result
}

func strPtrEq(a, b *string) bool {
	if a == nil && b == nil {
		return true
	}
	if a == nil || b == nil {
		return false
	}
	return *a == *b
}
