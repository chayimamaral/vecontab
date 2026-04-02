CLAUDE.md - Diretrizes do Projeto vecontab
📌 Contexto do Projeto
Nome: vecontab (ou vecontab_go)

Objetivo: Sistema contábil/financeiro de alta performance.

Stack: Backend em Go (Golang), Frontend em React.

Ambiente de Desenvolvimento: Fedora 43 (utilizar dnf para pacotes).

Banco de Dados: PostgreSQL (utilizando driver pgx).

🛠 Princípios de Engenharia
Arquitetura: Clean Architecture, SOLID e Domain-Driven Design (DDD).

Performance: Prioridade absoluta. Go é escolhido especificamente pela velocidade (benchmark de referência: 4.5x superior ao Python).

Acesso a Dados: Proibido o uso de ORMs. O controle deve ser total via SQL puro e drivers nativos para garantir otimização.

Segurança: Basear estratégias de proteção de código no projeto MARE.

Legado: Compatibilidade mental com arquiteturas robustas (referência histórica: sistemas 8086/TK85).

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

Banco: psql -h localhost -U [camaral] -d vecontab