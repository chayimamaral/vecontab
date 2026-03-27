-- Seed inicial para MEI (Microempreendedor Individual)
-- Tipo empresa informado pelo usuario:
-- 21a4bf05-3100-41e2-a3b2-e59ff67fc897
--
-- Este script cria:
-- 1) templates em tipoempresa_obrigacao (MENSAL/ANUAL, TRIBUTO/INFORMATIVA)
-- 2) compromissos em compromisso_financeiro (MENSAL/ANUAL, FINANCEIRO/NAO_FINANCEIRO)
--
-- Observacao:
-- - Feriados foram intencionalmente ignorados neste seed.
-- - Abrangencia escolhida como FEDERAL para nao exigir vinculos em compromisso_estado/municipio/bairro.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) OBRIGACOES (TEMPLATE POR TIPO DE EMPRESA)
-- ---------------------------------------------------------------------------

-- MENSAL + TRIBUTO (financeiro)
INSERT INTO public.tipoempresa_obrigacao (
    tipo_empresa_id,
    descricao,
    dia_base,
    mes_base,
    frequencia,
    tipo,
    ativo
)
SELECT
    '21a4bf05-3100-41e2-a3b2-e59ff67fc897',
    'DAS-MEI (Documento de Arrecadacao do Simples Nacional)',
    20,
    NULL,
    'MENSAL',
    'TRIBUTO',
    TRUE
WHERE NOT EXISTS (
    SELECT 1
    FROM public.tipoempresa_obrigacao o
    WHERE o.tipo_empresa_id = '21a4bf05-3100-41e2-a3b2-e59ff67fc897'
      AND o.descricao = 'DAS-MEI (Documento de Arrecadacao do Simples Nacional)'
      AND o.frequencia = 'MENSAL'
      AND o.ativo = TRUE
);

-- ANUAL + INFORMATIVA (nao financeiro)
INSERT INTO public.tipoempresa_obrigacao (
    tipo_empresa_id,
    descricao,
    dia_base,
    mes_base,
    frequencia,
    tipo,
    ativo
)
SELECT
    '21a4bf05-3100-41e2-a3b2-e59ff67fc897',
    'DASN-SIMEI (Declaracao Anual do Simples Nacional - MEI)',
    31,
    5,
    'ANUAL',
    'INFORMATIVA',
    TRUE
WHERE NOT EXISTS (
    SELECT 1
    FROM public.tipoempresa_obrigacao o
    WHERE o.tipo_empresa_id = '21a4bf05-3100-41e2-a3b2-e59ff67fc897'
      AND o.descricao = 'DASN-SIMEI (Declaracao Anual do Simples Nacional - MEI)'
      AND o.frequencia = 'ANUAL'
      AND o.ativo = TRUE
);

-- MENSAL + INFORMATIVA (nao financeiro)
INSERT INTO public.tipoempresa_obrigacao (
    tipo_empresa_id,
    descricao,
    dia_base,
    mes_base,
    frequencia,
    tipo,
    ativo
)
SELECT
    '21a4bf05-3100-41e2-a3b2-e59ff67fc897',
    'Registro e conferencias mensais de faturamento do MEI',
    5,
    NULL,
    'MENSAL',
    'INFORMATIVA',
    TRUE
WHERE NOT EXISTS (
    SELECT 1
    FROM public.tipoempresa_obrigacao o
    WHERE o.tipo_empresa_id = '21a4bf05-3100-41e2-a3b2-e59ff67fc897'
      AND o.descricao = 'Registro e conferencias mensais de faturamento do MEI'
      AND o.frequencia = 'MENSAL'
      AND o.ativo = TRUE
);

-- ANUAL + TRIBUTO (financeiro)
INSERT INTO public.tipoempresa_obrigacao (
    tipo_empresa_id,
    descricao,
    dia_base,
    mes_base,
    frequencia,
    tipo,
    ativo
)
SELECT
    '21a4bf05-3100-41e2-a3b2-e59ff67fc897',
    'Renovacoes e taxas anuais obrigatorias de MEI (quando aplicavel)',
    31,
    1,
    'ANUAL',
    'TRIBUTO',
    TRUE
WHERE NOT EXISTS (
    SELECT 1
    FROM public.tipoempresa_obrigacao o
    WHERE o.tipo_empresa_id = '21a4bf05-3100-41e2-a3b2-e59ff67fc897'
      AND o.descricao = 'Renovacoes e taxas anuais obrigatorias de MEI (quando aplicavel)'
      AND o.frequencia = 'ANUAL'
      AND o.ativo = TRUE
);

-- ---------------------------------------------------------------------------
-- 2) COMPROMISSOS (CADASTRO DE COMPROMISSOS)
-- ---------------------------------------------------------------------------

-- MENSAL + FINANCEIRO
INSERT INTO public.compromisso_financeiro (
    tipo_empresa_id,
    natureza,
    descricao,
    periodicidade,
    abrangencia,
    valor,
    observacao,
    ativo
)
SELECT
    '21a4bf05-3100-41e2-a3b2-e59ff67fc897',
    'FINANCEIRO',
    'Pagamento mensal do DAS-MEI',
    'MENSAL',
    'FEDERAL',
    NULL,
    'Valor variavel conforme atividade e atualizacoes legais.',
    TRUE
WHERE NOT EXISTS (
    SELECT 1
    FROM public.compromisso_financeiro c
    WHERE c.tipo_empresa_id = '21a4bf05-3100-41e2-a3b2-e59ff67fc897'
      AND c.descricao = 'Pagamento mensal do DAS-MEI'
      AND c.periodicidade = 'MENSAL'
      AND c.natureza = 'FINANCEIRO'
      AND c.abrangencia = 'FEDERAL'
      AND c.ativo = TRUE
);

-- ANUAL + FINANCEIRO
INSERT INTO public.compromisso_financeiro (
    tipo_empresa_id,
    natureza,
    descricao,
    periodicidade,
    abrangencia,
    valor,
    observacao,
    ativo
)
SELECT
    '21a4bf05-3100-41e2-a3b2-e59ff67fc897',
    'FINANCEIRO',
    'Taxas anuais e renovacoes de MEI (quando houver)',
    'ANUAL',
    'FEDERAL',
    NULL,
    'Pode variar conforme municipio, estado e atividade economica.',
    TRUE
WHERE NOT EXISTS (
    SELECT 1
    FROM public.compromisso_financeiro c
    WHERE c.tipo_empresa_id = '21a4bf05-3100-41e2-a3b2-e59ff67fc897'
      AND c.descricao = 'Taxas anuais e renovacoes de MEI (quando houver)'
      AND c.periodicidade = 'ANUAL'
      AND c.natureza = 'FINANCEIRO'
      AND c.abrangencia = 'FEDERAL'
      AND c.ativo = TRUE
);

-- MENSAL + NAO_FINANCEIRO
INSERT INTO public.compromisso_financeiro (
    tipo_empresa_id,
    natureza,
    descricao,
    periodicidade,
    abrangencia,
    valor,
    observacao,
    ativo
)
SELECT
    '21a4bf05-3100-41e2-a3b2-e59ff67fc897',
    'NAO_FINANCEIRO',
    'Conferencia mensal de receitas e controles do MEI',
    'MENSAL',
    'FEDERAL',
    NULL,
    'Rotina administrativa sem recolhimento direto.',
    TRUE
WHERE NOT EXISTS (
    SELECT 1
    FROM public.compromisso_financeiro c
    WHERE c.tipo_empresa_id = '21a4bf05-3100-41e2-a3b2-e59ff67fc897'
      AND c.descricao = 'Conferencia mensal de receitas e controles do MEI'
      AND c.periodicidade = 'MENSAL'
      AND c.natureza = 'NAO_FINANCEIRO'
      AND c.abrangencia = 'FEDERAL'
      AND c.ativo = TRUE
);

-- ANUAL + NAO_FINANCEIRO
INSERT INTO public.compromisso_financeiro (
    tipo_empresa_id,
    natureza,
    descricao,
    periodicidade,
    abrangencia,
    valor,
    observacao,
    ativo
)
SELECT
    '21a4bf05-3100-41e2-a3b2-e59ff67fc897',
    'NAO_FINANCEIRO',
    'Entrega anual da DASN-SIMEI',
    'ANUAL',
    'FEDERAL',
    NULL,
    'Declaracao anual obrigatoria do MEI.',
    TRUE
WHERE NOT EXISTS (
    SELECT 1
    FROM public.compromisso_financeiro c
    WHERE c.tipo_empresa_id = '21a4bf05-3100-41e2-a3b2-e59ff67fc897'
      AND c.descricao = 'Entrega anual da DASN-SIMEI'
      AND c.periodicidade = 'ANUAL'
      AND c.natureza = 'NAO_FINANCEIRO'
      AND c.abrangencia = 'FEDERAL'
      AND c.ativo = TRUE
);

COMMIT;
