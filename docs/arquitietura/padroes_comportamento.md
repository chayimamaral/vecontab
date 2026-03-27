# [STD-0] Padrões de Comportamento Global - MARE

## Regras de Negócio Globais (RN)

* **[RN-G1] Idempotência:** Toda operação de escrita iniciada pelo botão "Concluir" deve verificar se o registro já existe para evitar duplicidade.
* **[RN-G2] Transacionalidade:** Operações que envolvam mais de uma tabela devem usar `db.Begin()` em Go.
* **[RN-G3] Feedback Visual:** Toda chamada ao backend deve disparar um componente de `Toast` no React para sucesso ou erro.

## Exceções Globais (E)

* **[E-G1] Registro Duplicado:** Retornar Status 409 (Conflict).
* **[E-G2] Erro de Conexão:** Retornar Status 503 e mostrar mensagem "Sistema temporariamente indisponível".
