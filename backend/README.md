# Vecontab Backend - API REST em Go

API REST robusta para o sistema Vecontab de gestão de contabilidade. Backend construído em Go com PostgreSQL, autenticação JWT e suporte multi-tenant.

## 📋 Índice

- [Estrutura do Projeto](#estrutura-do-projeto)
- [Requisitos](#requisitos)
- [Instalação](#instalação)
- [Execução](#execução)
- [Endpoints](#endpoints)
- [Autenticação](#autenticação)
- [Variáveis de Ambiente](#variáveis-de-ambiente)

## 📁 Estrutura do Projeto

```
backend/
├── cmd/
│   └── api/
│       ├── main.go          # Entrypoint da aplicação
│       └── main             # Binário compilado
├── internal/
│   ├── auth/
│   │   └── jwt.go           # Autenticação JWT
│   ├── config/
│   │   └── config.go        # Configurações da app
│   ├── db/
│   │   └── postgres.go      # Conexão com PostgreSQL
│   ├── httpapi/
│   │   ├── response.go      # Formatação de respostas
│   │   ├── router.go        # Rotas da API
│   │   ├── handlers/        # Handlers dos endpoints
│   │   ├── middleware/      # Middlewares (auth, CORS, etc)
│   │   └── render/          # Renderização de responses
│   ├── repository/          # Camada de dados
│   │   ├── agenda_repository.go
│   │   ├── cidade_repository.go
│   │   ├── cnae_repository.go
│   │   ├── empresa_repository.go
│   │   ├── estado_repository.go
│   │   ├── feriado_repository.go
│   │   ├── grupopassos_repository.go
│   │   ├── node_repository.go
│   │   ├── passo_repository.go
│   │   ├── registro_repository.go
│   │   ├── rotina_repository.go
│   │   ├── tenant_repository.go
│   │   ├── tipoempresa_repository.go
│   │   └── user_repository.go
│   └── service/             # Lógica de negócio
│       ├── agenda_service.go
│       ├── auth_service.go
│       ├── cidade_service.go
│       ├── cnae_service.go
│       ├── empresa_service.go
│       ├── estado_service.go
│       ├── feriado_service.go
│       ├── grupopassos_service.go
│       ├── node_service.go
│       ├── passo_service.go
│       ├── registro_service.go
│       ├── rotina_service.go
│       ├── tenant_service.go
│       ├── tipoempresa_service.go
│       └── user_service.go
├── go.mod                   # Dependências Go
├── nginx.conf               # Configuração Nginx (reverse proxy)
├── bkp_vecontab.sql        # Backup do banco de dados
└── README.md               # Este arquivo
```

## 🔧 Requisitos

- **Go:** 1.26+ (verificar com `go version`)
- **PostgreSQL:** 12+
- **Nginx:** (opcional, para reverse proxy em produção)

## ⚙️ Instalação

### 1. Preparar ambiente

```bash
cd backend
go mod download
go mod tidy
```

### 2. Configurar banco de dados

```bash
# Criar banco de dados
psql -U postgres -c "CREATE DATABASE vecontab;"

# Restaurar schema (se houver backup)
# psql -U postgres -d vecontab -f bkp_vecontab.sql
```

### 3. Variáveis de Ambiente

Criar arquivo `.env` na raiz do backend:

```bash
SERVER_PORT=3333
PG_URL=postgres://user:password@localhost:5432/vecontab
JWT_SECRET=sua_chave_secreta_super_segura_aqui
```

## 🚀 Execução

### Desenvolvimento

```bash
go run ./cmd/api
```

API estará em http://localhost:3333

### Build para Produção

```bash
go build -o vecontab ./cmd/api/main.go
./vecontab
```

### Com Nginx (Reverse Proxy)

```bash
nginx -c ./nginx.conf
# Acesso via http://localhost (porta 80 redireciona para 3333)
```

## 📡 Endpoints

### 🔐 Autenticação

| Método | Rota | Descrição |
|--------|------|-----------|
| POST | `/api/session` | Login com email/senha |
| GET | `/me` | Dados do usuário logado |
| GET | `/api/usuariorole` | Role do usuário (ADMIN/USER) |
| GET | `/api/usuariotenant` | Tenant do usuário |

### 👥 Usuários

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/usuarios` | Listar usuários (com lazy loading) |
| POST | `/api/usuario` | Criar usuário (ADMIN/SUPER) |
| PUT | `/api/usuario` | Atualizar usuário |
| DELETE | `/api/usuario` | Deletar usuário |

### 🏢 Empresas

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/empresas` | Listar empresas (lazy loading) |
| POST | `/api/empresa` | Criar empresa |
| PUT | `/api/updateempresa` | Atualizar empresa |
| PUT | `/api/deleteempresa` | Deletar empresa (soft delete) |
| PUT | `/api/iniciarprocesso` | Iniciar processo da empresa |
| POST | `/api/validacnae` | Validar CNAE |

### 📅 Agenda

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/agendalist` | Listar eventos |
| GET | `/api/agendadetalhes` | Detalhes do evento |
| POST | `/api/agenda/concluir-passo` | Concluir passo da agenda |

### 📋 Rotinas & Passos

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/rotinas` | Listar rotinas |
| GET | `/api/passos` | Listar passos |
| GET | `/api/grupopassos` | Listar grupos de passos |

### 📊 Registros Contábeis

| Método | Rota | Descrição |
|--------|------|-----------|
| POST | `/api/registro` | Criar registro (público) |
| GET | `/api/registro` | Detalhar registro |
| PUT | `/api/registro` | Atualizar registro |

### 📍 Localidades

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/estados` | Listar estados |
| GET | `/api/cidades` | Listar cidades |
| GET | `/api/cidades/:estado` | Cidades por estado |

### 🔧 Configuração

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/tiposempresa` | Tipos de empresa |
| GET | `/api/cnaes` | Listar CNAEs |

### 📌 Compromissos, Obrigações e Empresa Agenda

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/compromissos` | Listar compromissos (filtros + sort server-side) |
| POST | `/api/compromisso` | Criar compromisso |
| PUT | `/api/compromisso` | Atualizar compromisso |
| PUT | `/api/deletecompromisso` | Deletar compromisso |
| GET | `/api/obrigacoes` | Listar obrigações |
| POST | `/api/obrigacao` | Criar obrigação |
| PUT | `/api/obrigacao` | Atualizar obrigação |
| PUT | `/api/deleteobrigacao` | Deletar obrigação |
| GET | `/api/empresaagenda` | Listar agenda por empresa |
| GET | `/api/empresaagenda/acompanhamento` | Dashboard de acompanhamento |
| POST | `/api/empresaagenda/gerar` | Gerar agenda da empresa |
| PUT | `/api/empresaagenda/status` | Atualizar status do item da agenda |

## 🔐 Autenticação

### Header Requerido

Todas as requisições autenticadas precisam do header:

```
Authorization: Bearer <jwt_token>
```

### Fluxo de Login

```bash
# 1. POST /api/session com email/senha
curl -X POST http://localhost:3333/api/session \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"senha123"}'

# Resposta:
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "user-uuid",
    "nome": "João Silva",
    "email": "user@example.com",
    "role": "ADMIN"
  }
}

# 2. Usar token nas requisições
curl -H "Authorization: Bearer eyJhbGc..." http://localhost:3333/api/usuarios
```

### JWT Claims

```json
{
  "nome": "Valéria Amaral",
  "email": "val@vec.com",
  "tenant": {
    "id": "d1e9e353-9d14-4f94-a426-6af374a6a7e0",
    "active": true,
    "nome": "Betel Contabilidade",
    "contato": "Valéria Amaral",
    "plano": "DEMO"
  },
  "role": "ADMIN",
  "sub": "56bc8d60-a196-428c-a5fd-d3031ceb0d11",
  "exp": 1776896987,
  "iat": 1774304987
}
```

## 🔒 Segurança

### Hardening Implementado

- ✅ Isolamento por tenant (JWT sempre consultado)
- ✅ Validação de role em rotas administrativas (ADMIN/SUPER)
- ✅ Bloqueio de elevação de privilégio (USER → SUPER)
- ✅ Validação de entrada
- ✅ CORS headers configurados
- ✅ JWT invalidação em logout

### Roles Disponíveis

- `ADMIN` - Acesso total ao tenant
- `USER` - Acesso limitado a funcionalidades básicas

## 📊 Lazy Loading

Endpoints de listagem suportam paginação lazy:

```
GET /api/usuarios?
  page=1&
  rows=20&
  sortField=nome&
  sortOrder=1&
  filters[nome][value]=João&
  filters[nome][matchMode]=contains
```

Resposta:

```json
{
  "success": true,
  "data": {
    "usuarios": [...],
    "totalRecords": 150
  }
}
```

## 🛠️ Desenvolvimento

### Padrão de Resposta

```json
{
  "success": true,
  "data": {...},
  "error": null,
  "message": "Sucesso"
}
```

### Adicionar novo endpoint

1. Criar handler em `internal/httpapi/handlers/`
2. Criar service em `internal/service/`
3. Criar repository em `internal/repository/`
4. Registrar rota em `internal/httpapi/router.go`
5. Adicionar middleware de autenticação se necessário

### Estrutura típica

```go
// handler
func (h *Handler) ListarUsuarios(w http.ResponseWriter, r *http.Request) {
    // validações
    // chamada ao service
    // renderização da resposta
}

// service
func (s *UsuarioService) ListarUsuarios(ctx context.Context, tenantID string) ([]Usuario, error) {
    // lógica de negócio
    // chamada ao repository
}

// repository
func (r *UsuarioRepository) ListarByTenant(ctx context.Context, tenantID string) ([]Usuario, error) {
    // execução SQL
    // scan dos resultados
}
```

## 🐛 Troubleshooting

### "connection refused" ao conectar PostgreSQL

```bash
# Verificar se PostgreSQL está rodando
psql -U postgres

# Verificar DATABASE_URL está correto
echo $PG_URL
```

### "no rows in result set"

API retorna erro 400 para queries sem resultados. Considere retornar array vazio.

### "invalid token"

- JWT_SECRET está consistente?
- Token não expirou? (check claim `exp`)
- Authorization header tem "Bearer " prefixo?

### Erro 405 (Method Not Allowed)

- Endpoint existe em `router.go`?
- Método HTTP (GET/POST/PUT) está correto?

## 📝 Logs

### Ver logs em tempo real

```bash
go run ./cmd/api 2>&1 | tee app.log
```

### Verificar endpoint de saúde

```bash
curl http://localhost:3333/healthz || echo "Down"
```

## 🗃️ Migrations

Arquivos SQL em `backend/migrations`:

- `001_compromisso_financeiro.sql`
- `002_tipoempresa_obrigacao_empresa_agenda.sql`
- `003_compromisso_tipoempresa_natureza.sql`
- `004_seed_mei_compromissos_obrigacoes.sql`
- `005_seed_mei_compromissos_abrangencia_local.sql`

### Seeds MEI (004 e 005)

- A migration `004` cria templates e compromissos/obrigações para MEI.
- A migration `005` complementa com abrangência local (`ESTADUAL`, `MUNICIPAL`, `BAIRRO`).
- Ambas são idempotentes e podem ser reaplicadas com segurança.

## 🔄 Estratégia de Migração (Legacy)

Transição do Node.js/TypeScript:

1. ✅ Manter contrato HTTP existente
2. ✅ Portar módulo por módulo
3. ✅ SQL explícito em cada repository
4. ✅ Substituir stubs 501 por handlers reais

## 📞 Informações Adicionais

Consulte [README principal](../README.md) para visão geral do projeto.

## Arquitetura

O backend Go foi organizado em camadas. A divisao principal existe para separar responsabilidades e reduzir acoplamento entre HTTP, regra de negocio e acesso ao banco.

Fluxo principal:

`HTTP -> handler -> service -> repository -> PostgreSQL`

### Handler

Fica em `internal/httpapi/handlers`.

Responsabilidades:

- receber request HTTP
- ler `query`, `params` e `body`
- extrair informacoes do JWT pelo `context`
- validar entrada basica
- chamar o service
- transformar erro em resposta HTTP

O handler nao deve conhecer SQL. Ele tambem nao deve concentrar regra de negocio que pertence ao dominio.

### Service

Fica em `internal/service`.

Responsabilidades:

- concentrar regra de negocio
- aplicar autorizacao funcional quando isso nao for apenas transporte HTTP
- orquestrar mais de um repository quando necessario
- definir o contrato de uso da funcionalidade

O service existe para impedir que a regra de negocio fique espalhada entre controller/handler e SQL.

### Repository

Fica em `internal/repository`.

Responsabilidades:

- encapsular acesso ao PostgreSQL
- montar SQL explicitamente
- executar queries e transacoes
- mapear resultados do banco

O repository nao deve conhecer detalhes de HTTP. Ele recebe dados ja preparados pela camada superior.

## Por que separar em 3 pastas

A separacao parece redundante no inicio, mas resolve problemas diferentes:

- manutencao: fica claro onde mexer quando o problema esta no HTTP, na regra ou no banco
- teste: permite validar regra de negocio sem depender diretamente de request HTTP
- evolucao: trocar detalhes do banco ou do transporte afeta menos arquivos
- seguranca: fica mais facil centralizar regras como tenant do JWT e checks de role

Na pratica, a redundancia ruim nao esta nas pastas. Ela aparece quando tipos muito parecidos comecam a ser copiados entre as camadas sem necessidade.

## Sobre `model`

Nao foi criada uma pasta `model` generica de proposito.

Em Go, uma pasta `model` costuma virar um deposito misturando:

- entidade de negocio
- payload HTTP
- filtro de listagem
- resultado de query
- resposta de API

Quando isso acontece, uma struct que deveria pertencer a uma camada passa a ser usada por todas, e o acoplamento aumenta.

Por isso, neste porte, os tipos ficaram proximos da camada onde sao usados:

- structs de request/response perto dos handlers
- inputs e orchestration perto dos services
- filtros e structs de persistencia perto dos repositories

## O que esta bom e o que ainda pode melhorar

O desenho atual favorece a migracao incremental com baixo risco, porque preserva o contrato do backend original e deixa o SQL visivel.

Ao mesmo tempo, ainda ha pontos para evoluir:

- reduzir uso de `map[string]any`
- reduzir duplicacao de tipos muito parecidos entre handler/service/repository
- introduzir entidades compartilhadas apenas onde houver ganho real

## Direcao futura para modelos de dominio

Se o projeto evoluir alem da migracao, a recomendacao e criar uma camada de dominio explicita, por exemplo:

- `internal/domain/empresa.go`
- `internal/domain/user.go`
- `internal/domain/tenant.go`

Essa camada deve concentrar apenas entidades centrais do negocio.

Ela nao deve substituir DTOs HTTP nem structs especificas de query. A ideia e manter:

- handler com payloads HTTP
- service com contratos de caso de uso
- repository com tipos de persistencia
- domain com entidades realmente compartilhadas

## Matriz de permissoes por rota

Legenda:

- `PUBLICO`: sem token
- `AUTH`: exige token JWT valido
- `ADMIN/SUPER`: exige token + role `ADMIN` ou `SUPER`

### Autenticacao e cadastro inicial

- `POST /session`: `PUBLICO`
- `POST /registro`: `PUBLICO`
- `GET /registro`: `AUTH`
- `PUT /registro`: `AUTH`

### Tenant e usuario

- `POST /tenant`: `SUPER` (com JWT)
- `GET /tenant`: `AUTH`
- `PUT /tenant`: `ADMIN/SUPER`
- `GET /tenants`: `AUTH` (retorno depende do role)
- `GET /me`: `AUTH`
- `GET /usuarios`: `AUTH` (service restringe para `ADMIN`/`SUPER`)
- `GET /usuariorole`: `AUTH`
- `GET /usuariotenant`: `AUTH`
- `POST /usuario`: `ADMIN/SUPER`

### Cadastros administrativos

- `POST/PUT/DELETE /cidade`: `ADMIN/SUPER`
- `GET /cidades` e `GET /cidadeslite`: `AUTH`
- `POST /estado`, `PUT /estado`, `PUT /deleteestado`: `ADMIN/SUPER`
- `GET /estados` e `GET /ufscidade`: `AUTH`
- `POST /tipoempresa`, `PUT /tipoempresa`, `PUT /deletetipoempresa`: `ADMIN/SUPER`
- `GET /tiposempresa` e `GET /tiposempresalite`: `AUTH`
- `POST /passo`, `PUT /passo`, `PUT /deletepasso`: `ADMIN/SUPER`
- `GET /passos`, `GET /getPassoById`, `GET /passosporcidade`: `AUTH`
- `POST /grupopassos`, `PUT /grupopasso`, `PUT /deletegrupopasso`: `ADMIN/SUPER`
- `GET /grupopassos`, `GET /getgrupopassobyid`: `AUTH`

### Rotinas, feriados, empresas, cnae

- `POST /rotina`, `PUT /rotina`, `PUT /deleterotina`: `ADMIN/SUPER`
- `GET /rotinas`, `GET /rotinaitens`, `GET /listrotinas`, `GET /listrotinaslite`, `GET /listrotinaitensselected`: `AUTH`
- `GET /rotinaitemcreate`, `GET /rotinaitemupdate`, `GET /rotinaitemdelete`, `PUT /salvarselecao`, `PUT /removepassoselecionado`: `ADMIN/SUPER`
- `POST /feriado`, `PUT /feriado`, `PUT /deleteferiado`: `ADMIN/SUPER`
- `GET /feriados`: `AUTH`
- `POST /empresa`, `PUT /updateempresa`, `PUT /deleteempresa`, `PUT /iniciarprocesso`: `ADMIN/SUPER`
- `GET /empresas`: `AUTH`
- `POST /cnae`, `PUT /cnae`, `PUT /deletecnae`: `ADMIN/SUPER`
- `GET /cnaes`, `GET /cnaelite`, `POST /validacnae`: `AUTH`

### Agenda e arvore de passos

- `GET /agendalist`: `AUTH`
- `GET /agendadetalhes`: `AUTH`
- `GET /node`, `GET /family`, `GET /recurso`: `AUTH`

### Endpoints auxiliares

- `GET /healthz`: `PUBLICO`

Observacao:

- As rotas sao expostas em dois prefixos: raiz (`/`) e espelho em `/api`.
- O hardening de tenant em recursos sensiveis (`agenda` e `empresa`) usa o tenant do JWT para evitar acesso cruzado entre tenants.

## Checklist de homologacao por perfil

Use este roteiro para validar rapidamente se as permissoes estao corretas no ambiente.

### 1. Perfil USER

Esperado:

- consegue autenticar em `/session`
- consegue ler rotas `AUTH` (ex.: `/me`, `/agendalist`, `/empresas`, `/cnaes`)
- recebe `403` nas rotas `ADMIN/SUPER` (ex.: `POST /empresa`, `PUT /deletecnae`, `POST /usuario`)

Teste minimo sugerido:

1. fazer login como USER
2. chamar `GET /api/me` e confirmar `200`
3. chamar `POST /api/empresa` e confirmar `403`
4. chamar `POST /api/usuario` e confirmar `403`

### 2. Perfil ADMIN

Esperado:

- consegue ler rotas `AUTH`
- consegue operar rotas `ADMIN/SUPER` do proprio tenant
- nao consegue criar usuario com role `SUPER`
- ao criar usuario, tenant deve seguir o tenant do token (nao o tenant informado no body)

Teste minimo sugerido:

1. fazer login como ADMIN
2. chamar `POST /api/usuario` com role `USER` e confirmar `200`
3. chamar `POST /api/usuario` com role `SUPER` e confirmar `403`
4. chamar `PUT /api/updateempresa` com `id` de empresa de outro tenant e confirmar resposta sem alteracao

### 3. Perfil SUPER

Esperado:

- consegue ler rotas `AUTH`
- consegue operar rotas `ADMIN/SUPER`
- consegue criar usuario em tenant alvo (quando informado)
- consegue listar tenants em `/tenants`

Teste minimo sugerido:

1. fazer login como SUPER
2. chamar `GET /api/tenants` e confirmar retorno com lista
3. chamar `POST /api/usuario` com tenant alvo valido e confirmar `200`

### 4. Tenant isolation (smoke test)

Esperado:

- `agenda` e `empresa` nao permitem acesso cruzado entre tenants via query/body

Teste minimo sugerido:

1. com token do Tenant A, chamar `GET /api/agendadetalhes?agenda_id=<id_do_tenant_B>`
2. confirmar retorno vazio ou sem dados do Tenant B
3. com token do Tenant A, chamar `PUT /api/deleteempresa` em empresa do Tenant B
4. confirmar que nao houve alteracao no registro do Tenant B

### 5. Criterio de aceite rapido

- rotas `PUBLICO`: respondem sem token
- rotas `AUTH`: `401` sem token e `200` com token valido
- rotas `ADMIN/SUPER`: `403` para USER e `200` para ADMIN/SUPER
- nenhuma alteracao cruzada entre tenants em `agenda` e `empresa`

## Proximos passos sugeridos

1. concluir `tenant hardening` nos recursos restantes sensiveis (ownership em update/delete/detail)
2. revisar as regras ADMIN/SUPER junto ao frontend para confirmar se algum fluxo de escrita precisa de ajuste fino
3. reduzir `map[string]any` nos modulos mais estaveis
4. avaliar criacao de `internal/domain` depois da migracao estar funcional de ponta a ponta
