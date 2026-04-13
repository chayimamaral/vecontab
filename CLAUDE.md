CLAUDE.md - Diretrizes do Projeto vecontab

📌 Contexto do Projeto
Nome: vecontab 

Objetivo: Sistema de Controle de Passos para Manutenção de Empresas (abertura, alterações, manutenções, encerramento, etc), Controle de Compromissos (Tributos, Taxas, Obrigações Financeiras, etc), Controle de PF (IRRF, etc).
Objetivo a curto prazo: consumir API's para geração de Boletos, DARF's, DAS'S, etc.

Stack: Backend em Go (Golang), Frontend em React.

Pastas Principais:
  Backend: vecontab/backend
  Frontend: vecontab/frontend

Ambiente de Desenvolvimento: Fedora 43 (utilizar dnf para pacotes).

Banco de Dados: PostgreSQL 18.3 (utilizando driver pgx); Claude tem permissão para executar migrations quando pertinente.

Acesso a Dados: Proibido o uso de ORMs. O controle deve ser total via SQL puro e drivers nativos para garantir otimização.

Comandos para o Banco de Dados: psql -h localhost -U [camaral] -d vecontab

Migrations: toda e qualquer migration, relacionada a banco de dados, sempre na pasta raiz do vecontab: vecontab/migrations

🛠 Princípios de Engenharia
Arquitetura: Clean Architecture, SOLID e Domain-Driven Design (DDD).

Performance: Prioridade absoluta. Go é escolhido especificamente pela velocidade (benchmark de referência: 4.5x superior ao Python).

Segurança: Basear estratégias de proteção de código no projeto VECONTAB.

📝 Padrões de Código e Escrita
Nomenclatura (Ortografia): Seguir a regra gramatical de que o "ç" nunca é utilizado antes de "e" ou "i". Em nomes de variáveis ou funções, o som de "s" antes destas vogais deve ser garantido pelo "c" simples. 
O mesmo para palavras acentuadas.

Documentação: Não apresentar resumos ortográficos em respostas de busca.

Tradução: Utilizar termos técnicos de mercado (ex: "issue" como tarefa/problema, "good first issue" como ponto de partida).

🚫 Restrições de Contexto (Strict)
Separação de Domínios: É terminantemente proibido associar textos ou conceitos religiosos a temas de TI (desenvolvimento, banco de dados, agilidade, etc).

Terminologia: Não usar qualquer contexto religioso ou político.

Licenciamento: O projeto é Proprietário. Todos os direitos reservados (Copyright 2026). Não sugerir licenças permissivas (como MIT/Apache) para o núcleo do sistema.

🚀 Comandos Úteis (Fedora)
Instalação: sudo dnf install [pacote]

Backend: go run cmd/api/main.go
Frontend: npm run dev

Layout: botão "Atualizar" será sempre um ícone no canto inferior da página, nunca botão na parte superior.
  Exemplo: const paginatorLeft = <Button type="button" icon="pi pi-refresh" tooltip='Atualizar' className="p-button-text" onClick={loadLazy_Rotina_Tal}
Os botões nas linhas das tables ou treetables, deverão seguir o modelo em Municípios (quando aplicável).

Frontend: sempre que possível, dar preferência ao useQuery em lugar de useEffect.

Usuários: temos 3 tipos de usuários:
  SUPER: sou eu, chayimamaral, o dono do vecontab, que é um aplicativo SaaS que será alugado;
  ADMIN: o usuário administrador da empresa de contabilidade, com maiores poderes de usuário, sempre separado por tenant, e que incluirá novos usuário no mesmo tenant que o próprio;
  USER: serão os usuários do mesmo escritório de contabilidade, mas com poderes restritos;

Campos 'id' sempre criar como uuid.

📑 TabView + Dialog (PrimeReact) — lições do cadastro de Clientes
- O `<li>` da **ink bar** é irmão das abas no mesmo `<ul>`; evitar `space-between` no flex da nav. Ink bar oculta via `pt` quando o tema gerar artefatos visuais.
- Bordas inferiores do tema em `.p-tabview-nav` e `.p-tabview-nav-link`: para diálogos “limpos”, sobrescrever em escopo (classe no `TabView`, estilos em `frontend/styles/layout/layout.scss`).
- **Altura:** `min-height` fixa em CSS no `.p-tabview-panels` (ex. `min(58vh, 38rem)`); não medir com `ResizeObserver` ao mudar de aba (efeito colateral: scroll espúrio e crescimento de `minHeight`).
- Atalhos numéricos + botão desabilitado alinhado às abas `disabled` por perfil (ex.: Certificado só ADMIN/SUPER; USER com `TabPanel disabled` e fallback de índice ativo).
