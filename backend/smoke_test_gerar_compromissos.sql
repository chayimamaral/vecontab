-- Smoke test: geração de compromissos (issue #36)
-- Uso:
--   1) Ajuste os parâmetros no bloco "params".
--   2) Execute em homolog/dev.
--   3) Verifique os SELECTs de validação.
--
-- Observação:
--   Este roteiro NÃO dá COMMIT. No final, você pode COMMIT ou ROLLBACK.

BEGIN;

-- =====================================================================
-- 0) Parâmetros
-- =====================================================================
WITH params AS (
    SELECT
        'SEU_TENANT_ID_AQUI'::text  AS tenant_id,
        NULL::text                  AS empresa_id,         -- opcional: informe ID para testar 1 empresa
        CURRENT_DATE::date          AS data_referencia
)
SELECT * FROM params;

-- =====================================================================
-- 1) Pré-checagem rápida
-- =====================================================================
-- Tenants/empresas/obrigações elegíveis
WITH params AS (
    SELECT
        '5bf1a2bc-b39e-4af6-97df-bb70326373ab'::text  AS tenant_id,
        NULL::text                  AS empresa_id
)
SELECT
    e.id AS empresa_id,
    e.nome,
    r.tipo_empresa_id,
    o.id AS obrigacao_id,
    o.descricao,
    o.periodicidade,
    o.abrangencia,
    o.dia_base,
    o.mes_base,
    o.tipo_classificacao
FROM public.empresa e
INNER JOIN public.rotinas r ON r.id = e.rotina_id AND r.ativo = true
INNER JOIN public.tipoempresa_obrigacao o ON o.tipo_empresa_id = r.tipo_empresa_id AND o.ativo = true
INNER JOIN params p ON p.tenant_id = e.tenant_id
WHERE e.ativo = true
  AND (p.empresa_id IS NULL OR e.id = p.empresa_id)
ORDER BY e.nome, o.descricao
LIMIT 100;

-- =====================================================================
-- 2) Execução da function
-- =====================================================================
WITH params AS (
    SELECT
        '5bf1a2bc-b39e-4af6-97df-bb70326373ab'::text  AS tenant_id,
        NULL::text                  AS empresa_id,
        CURRENT_DATE::date          AS data_referencia
)
SELECT public.gerar_compromissos_mensais(
    p.tenant_id,
    p.data_referencia,
    p.empresa_id
) AS total_inserido
FROM params p;

-- =====================================================================
-- 3) Idempotência: segunda execução deve inserir 0
-- =====================================================================
WITH params AS (
    SELECT
        '5bf1a2bc-b39e-4af6-97df-bb70326373ab'::text  AS tenant_id,
        NULL::text                  AS empresa_id,
        CURRENT_DATE::date          AS data_referencia
)
SELECT public.gerar_compromissos_mensais(
    p.tenant_id,
    p.data_referencia,
    p.empresa_id
) AS total_inserido_segunda_execucao
FROM params p;

-- =====================================================================
-- 4) Validação de duplicidade por chave composta
-- =====================================================================
WITH params AS (
    SELECT '5bf1a2bc-b39e-4af6-97df-bb70326373ab'::text AS tenant_id
)
SELECT
    ec.empresa_id,
    ec.tipoempresa_obrigacao_id,
    ec.competencia,
    COUNT(*) AS qtd
FROM public.empresa_compromissos ec
INNER JOIN public.empresa e ON e.id = ec.empresa_id
INNER JOIN params p ON p.tenant_id = e.tenant_id
GROUP BY ec.empresa_id, ec.tipoempresa_obrigacao_id, ec.competencia
HAVING COUNT(*) > 1;
-- esperado: 0 linhas

-- =====================================================================
-- 5) Validação de periodicidade (amostra)
-- =====================================================================
WITH params AS (
    SELECT '5bf1a2bc-b39e-4af6-97df-bb70326373ab'::text AS tenant_id
)
SELECT
    e.nome AS empresa,
    o.descricao,
    o.periodicidade,
    o.mes_base,
    ec.competencia,
    ec.vencimento::date AS vencimento,
    ec.valor
FROM public.empresa_compromissos ec
INNER JOIN public.empresa e ON e.id = ec.empresa_id
INNER JOIN public.tipoempresa_obrigacao o ON o.id = ec.tipoempresa_obrigacao_id
INNER JOIN params p ON p.tenant_id = e.tenant_id
WHERE ec.competencia = date_trunc('month', CURRENT_DATE)::date
ORDER BY empresa, o.descricao
LIMIT 200;

-- =====================================================================
-- 6) Validação de vencimento em fim de semana
-- =====================================================================
WITH params AS (
    SELECT '5bf1a2bc-b39e-4af6-97df-bb70326373ab'::text AS tenant_id
)
SELECT
    e.nome AS empresa,
    o.descricao,
    ec.vencimento::date AS vencimento,
    EXTRACT(ISODOW FROM ec.vencimento::date) AS isodow
FROM public.empresa_compromissos ec
INNER JOIN public.empresa e ON e.id = ec.empresa_id
INNER JOIN public.tipoempresa_obrigacao o ON o.id = ec.tipoempresa_obrigacao_id
INNER JOIN params p ON p.tenant_id = e.tenant_id
WHERE ec.competencia = date_trunc('month', CURRENT_DATE)::date
  AND EXTRACT(ISODOW FROM ec.vencimento::date) IN (6, 7)
ORDER BY empresa, o.descricao;
-- esperado: idealmente 0 linhas

-- =====================================================================
-- 7) Encerramento
-- =====================================================================
-- COMMIT;
ROLLBACK;

