// Demo equivalente ao Program.cs do projeto .NET de exemplo.
package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/chayimamaral/vecontab/docs/serpro-autenticacao-loja-go/lojaserpro"
)

func main() {
	customerKey := "sua_customer_key"
	customerSecret := "sua_customer_secret"
	certificado := "certificado.pfx"
	senha := "senha_do_certificado"

	// Defina a URL base real (variável de ambiente) — no C# o valor era constante interna.
	baseURL := os.Getenv("SERPRO_LOJA_BASE_URL")
	if baseURL == "" {
		log.Fatal("Defina SERPRO_LOJA_BASE_URL com a URL base do endpoint de autenticação (documentação do produto).")
	}

	ctx := context.Background()
	tokens, err := lojaserpro.GerarTokensTemporarios(ctx, baseURL, customerKey, customerSecret, certificado, senha)
	if err != nil {
		log.Fatal(err)
	}

	fmt.Printf("expires_in (segundos): %d\n", tokens.ExpiresIn)
	fmt.Printf("scope: %s\n", tokens.Scope)
	fmt.Printf("token_type: %s\n", tokens.TokenType)
	fmt.Printf("access_token: %s\n", tokens.AccessToken)
	fmt.Printf("jwt_token: %s\n", tokens.JwtToken)
}
