# Vecontab - Sistema de Gestão de Contabilidade

Vecontab é uma aplicação Full Stack para gestão de empresas e contabilidade, construída com um backend robusto em Go e um frontend moderno em Next.js/React.

## 🏗️ Arquitetura

O projeto está dividido em dois componentes principais:

```
vecontab/
├── backend/          # API REST em Go
├── frontend/         # Interface em Next.js + React
└── README.md         # Este arquivo
```

## 🚀 Stack Tecnológico

### Backend

- **Linguagem:** Go 1.26.2
- **Banco de Dados:** PostgreSQL
- **Servidor HTTP:** integrado em Go
- **Reverse Proxy:** Nginx (nginx.conf)
- **Autenticação:** JWT

#### Backend Go - Tecnologias e Diretrizes

**Tecnologias utilizadas no backend:**

- **Go Modules (`go.mod`)** para versionamento e reprodutibilidade de dependências
- **`pgx/v5` (`pgxpool`)** para acesso ao PostgreSQL com pooling
- **JWT** para autenticação e autorização baseada em claims
- **Middlewares HTTP** para autenticação, CORS e tratamento transversal de requisições
- **Nginx** como reverse proxy em cenários de produção

**Melhores práticas aplicadas no backend:**

- **Arquitetura em camadas** (`handler -> service -> repository`) para separar transporte HTTP, regra de negócio e persistência
- **Separação por domínio** em módulos (`agenda`, `empresa`, `usuario`, `registro`, etc.) para facilitar manutenção e evolução
- **Multi-tenant por token**: isolamento de dados por tenant usando informações do JWT
- **Controle de acesso por perfil (role)** em operações administrativas
- **Redução progressiva de estruturas dinâmicas** (`map[string]any`) em favor de respostas tipadas
- **Tratamento padronizado de respostas de API** para consistência entre endpoints

**Diretrizes e convenções Go respeitadas:**

- **Organização idiomática de projeto** com `cmd/` (entrypoint) e `internal/` (domínio da aplicação)
- **Pacotes pequenos e com responsabilidade clara** (`auth`, `db`, `httpapi`, `repository`, `service`)
- **Nomes simples e idiomáticos** para funções, tipos e pacotes
- **Tratamento explícito de erros** com retorno de erro entre camadas
- **Encapsulamento por pacote** e controle de visibilidade por inicial maiúscula/minúscula
- **Build e execução nativos do ecossistema Go** (`go run`, `go build`, `go mod tidy`)

#### Checklist de Conformidade (Fluxo Usuário x Tenant)

- [X] API exige autenticação JWT para listar usuários (`GET /usuarios`)
- [X] API exige role ADMIN/SUPER para criar/alterar/excluir usuários (`POST/PUT/DELETE /usuario`)
- [X] ADMIN não pode criar usuário SUPER
- [X] ADMIN fica preso ao próprio tenant ao criar/editar usuário
- [X] SUPER pode informar `tenantId` no payload para criar/editar usuário em outro tenant
- [X] Listagem de tenants para SUPER disponível (`GET /tenants`)
- [X] Frontend de usuários expõe fluxo de SUPER para escolher tenant do novo usuário
- [X] Frontend de usuários exibe ação Criar para role SUPER
- [X] Endpoint de criação de tenant está protegido por autenticação/role (`POST /tenant` exige SUPER)
- [X] Update/Delete de usuário valida escopo de tenant no backend antes de persistir por `id`

Observação: hoje o backend já suporta o vínculo de usuário com tenant por payload para SUPER, mas a tela de usuários está orientada ao fluxo de ADMIN do próprio tenant.

### Frontend

- **Framework:** Next.js 16.2.1
- **Biblioteca UI:** React 18.3.1
- **Linguagem:** TypeScript
- **UI Components:** PrimeReact 10.9.7
- **Calendário:** FullCalendar 6.1.20
- **Bundler:** Webpack (dev mode)

## 📋 Funcionalidades

- **Gestão de Empresas** - Cadastro e administração de empresas
- **Gestão de Usuários** - Controle de acesso por tenant
- **Agenda** - Calendário integrado
- **Contabilidade** - Registro de registros contábeis
- **Workflows** - Rotinas e passos automatizados
- **Multi-tenant** - Isolamento de dados por empresa

## 🔧 Configuração e Execução

### Backend

```bash
cd backend
go run ./cmd/api
# API estará disponível em http://localhost:3333
```

**Dependências:**

- Go (versão recente)
- PostgreSQL

**Variáveis de Ambiente:**

- `PG_URL` - String de conexão PostgreSQL
- `JWT_SECRET` - Chave secreta para JWT

### Frontend

```bash
cd frontend
npm install
npm run dev
# Aplicação estará disponível em http://localhost:3000
```

**Dependências:**

- Node.js 22.x
- npm 11.x

**Requisitos:**

- Backend rodando em http://localhost:3333

## 📚 Documentação Detalhada

- [Backend Documentation](./backend/README.md)
- [Frontend Documentation](./frontend/README.md)

## 🔐 Autenticação

A aplicação utiliza JWT (JSON Web Token) para autenticação:

1. Login com email/senha
2. Retorno de token JWT
3. Token enviado em Authorization header (Bearer)
4. Isolamento de dados por tenant

## 📦 Build

### Backend

```bash
cd backend
go build -o vecontab ./cmd/api/main.go
```

### Frontend

```bash
cd frontend
npm run build
npm start
```

## 🐛 Troubleshooting

### Frontend não conecta ao Backend

- Verificar se backend está rodando em `localhost:3333`
- Verificar CORS headers
- Verificar token JWT válido

### Erro "no rows in result set"

- Backend retorna 400 para queries vazias
- Frontend trata este erro graciosamente

### Página de usuários não carrega

- Verificar `/api/registro` retorna dados ou erro tratado
- Verificar autenticação do usuário

## 📝 Notas de Desenvolvimento

- Frontend usa Webpack em dev mode (não Turbopack)
- React 18.3.1 para compatibilidade com PrimeReact 10
- Multi-tenant isolado por token JWT

## 🔄 Ciclo de Desenvolvimento

1. Backend: alterações em `backend/internal` requerem rebuild
2. Frontend: hot reload automático com `npm run dev`
3. Logs: verificar console do backend e browser (F12)

## 📞 Suporte

Para mais informações, consulte a documentação específica de cada módulo:

- [Backend](./backend/README.md)
- [Frontend](./frontend/README.md)
