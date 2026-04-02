---
name: Requisito complexo
about: Documentar uma necessidade funcional ou regra de negocio complexa
title: '[EF-XXX] Nome do Caso de Uso'
labels: enhancement
assignees: ''
---

###Resumo
Breve descrição do que o caso de uso realiza.

###Atores
Usuário (ou Sistema/Gatilho Automático)

###Contexto e Objetivo
Explique a origem da necessidade, o problema atual e o comportamento esperado após a implementação.

###Fluxo Principal
O sistema apresenta... [RN1]

O usuário preenche... [E1]

O sistema valida... [RN2]

O usuário clica em... [RN3][E2]

###Fluxos Alternativos / Extensões
[FA1] Campo Pick-list: Descrição do comportamento da janela auxiliar.

[FA2] Inclusão via busca: O que acontece se o dado não existir.

###Regras de Negócio (RN)
[RN1] Validação de Data: Descrição da regra (ex: Vencimento dia 20).

[RN2] Cálculo de Parcelas: Regra para gerar 12 meses.

[RN3] Idempotência: Não duplicar se clicar duas vezes.

###Tratamento de Exceções (E)
[E1] Campo Obrigatório: Mensagem de erro ao deixar vazio.

###[E2] Falha na Conectividade: Comportamento se o banco de dados falhar.

###Modelagem e Impacto Técnico
Banco de Dados (PostgreSQL)
Tabela: :nome_da_tabela

Campos: :campos, tipos e constraints

##Backend (Go)
Descrição da lógica de serviço, pacotes usados e transações.

##Frontend (React/PrimeReact)
Componentes usados (ex: TreeTable, Toast) e estados de tela.

##Critérios de Aceite
[ ] Cenário 1: Sucesso ao salvar.

[ ] Cenário 2: Validação de erro disparada.

Observações e Documentos de Apoio
##Autor: Carlos Amaral

Documento: docs/requisitos/NOME.md

Dependências: Listar se depende de outro UC ou tabela.
