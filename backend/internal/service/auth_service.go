package service

import (
	"context"
	"errors"
	"strings"

	"github.com/chayimamaral/vecontab/backend/internal/auth"
	"github.com/chayimamaral/vecontab/backend/internal/repository"
	"golang.org/x/crypto/bcrypt"
)

type LoginInput struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	Tenant   string `json:"tenant"`
}

type AuthService struct {
	users  *repository.UserRepository
	tokens *auth.TokenService
}

type LoginResponse struct {
	ID       string            `json:"id"`
	Nome     string            `json:"nome"`
	Email    string            `json:"email"`
	TenantID string            `json:"tenantid"`
	Token    string            `json:"token"`
	Tenant   repository.Tenant `json:"tenant"`
	Role     string            `json:"role"`
}

func NewAuthService(users *repository.UserRepository, tokens *auth.TokenService) *AuthService {
	return &AuthService{users: users, tokens: tokens}
}

func (s *AuthService) Login(ctx context.Context, input LoginInput) (LoginResponse, error) {
	input.Email = strings.TrimSpace(input.Email)
	user, err := s.users.FindByEmail(ctx, input.Email)
	if err != nil {
		return LoginResponse{}, errors.New("Email/password/empresa incorretos...")
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(input.Password)); err != nil {
		if user.Password != input.Password {
			return LoginResponse{}, errors.New("Email/password incorretos ...")
		}

		// Legacy migration path: old records may still store plaintext password.
		passwordHash, hashErr := bcrypt.GenerateFromPassword([]byte(input.Password), 8)
		if hashErr != nil {
			return LoginResponse{}, hashErr
		}

		if updateErr := s.users.UpdatePassword(ctx, user.ID, string(passwordHash)); updateErr != nil {
			return LoginResponse{}, updateErr
		}
	}

	if !user.Tenant.Active {
		return LoginResponse{}, errors.New("Empresa nao esta ativa...consulte seu Administrador")
	}

	token, err := s.tokens.Generate(auth.Claims{
		UserID: user.ID,
		Nome:   user.Nome,
		Email:  user.Email,
		Tenant: auth.TenantClaims(user.Tenant),
		Role:   user.Role,
	})
	if err != nil {
		return LoginResponse{}, err
	}

	return LoginResponse{
		ID:       user.ID,
		Nome:     user.Nome,
		Email:    user.Email,
		TenantID: user.TenantID,
		Token:    token,
		Tenant:   user.Tenant,
		Role:     user.Role,
	}, nil
}
