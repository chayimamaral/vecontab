# Serpro.Componentes.AutenticacaoLoja (Go)

Análogo em Go do projeto .NET `Serpro.Componentes.AutenticacaoLoja` (pasta irmã `../Serpro.Componentes.AutenticacaoLoja`).

## Descrição

Autenticação na Loja Serpro com **consumer key**, **consumer secret**, **certificado digital e-CNPJ (.pfx)** e **mTLS**, obtendo tokens temporários (`access_token`, `jwt_token`, etc.).

## Correspondência com o C#

| C# | Go |
|----|-----|
| `LojaSerpro.GerarTokensTemporariosAsync(...)` | `lojaserpro.GerarTokensTemporarios(ctx, ...)` |
| `ENDPOINT_LOJA_SERPRO` (constante placeholder) | `lojaserpro.EndpointPlaceholder` — **não use em produção**; passe `baseURL` real |
| `TokensLojaSerpro` | `lojaserpro.TokensLojaSerpro` |
| `HttpClientHandler` + certificado cliente | `http.Client` com `tls.Config{Certificates}` |
| Validação de servidor desabilitada | `InsecureSkipVerify: true` (igual ao exemplo C#) |

## Dependências

- [golang.org/x/crypto/pkcs12](https://pkg.go.dev/golang.org/x/crypto/pkcs12) — leitura do `.pfx`

## Uso rápido

```bash
cd Serpro.Componentes.AutenticacaoLoja.Go
export SERPRO_LOJA_BASE_URL="https://(URL-base-conforme-documentação-do-produto)/"
go run ./cmd/demo
```

Ajuste em `cmd/demo/main.go` as variáveis `customerKey`, `customerSecret`, caminho do `.pfx` e senha.

## Pacote importável

```go
import "github.com/chayimamaral/vecontab/docs/serpro-autenticacao-loja-go/lojaserpro"
```

## Avisos

1. O exemplo oficial C# envia `Content-Type: application/json` com corpo `grant_type=client_credentials`. Este código **replica** esse comportamento. Se a API passar a exigir `application/x-www-form-urlencoded`, ajuste o header e o corpo.
2. **`InsecureSkipVerify`** replica o exemplo; em produção, prefira validar a cadeia do servidor.
3. O **endpoint** não está embutido no código Go de biblioteca: informe sempre a URL via parâmetro (mais seguro que constante copiada).

## Licença

MIT — mesmo texto do projeto SERPRO em `../Serpro.Componentes.AutenticacaoLoja/LICENSE` (veja `LICENSE` nesta pasta).

## Créditos

Baseado no componente publicado pelo SERPRO em .NET 6.0 (`Serpro.Componentes.AutenticacaoLoja`).
