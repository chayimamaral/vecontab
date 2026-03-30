-- Issue #31: unifica cadastro legal em public.tipoempresa_obrigacao (ex-compromisso_financeiro + templates);
-- renomeia vínculos estaduais/municipais; empresa_compromissos.tipoempresa_obrigacao_id.
-- Sem esta migração, GET /api/obrigacoes falha: a tabela tipoempresa_obrigacao ainda é só o template (002), sem periodicidade/abrangencia etc.

BEGIN;

-- 1) Template de agenda vira tabela temporária (FK de empresa_agenda segue válida)
ALTER TABLE IF EXISTS public.tipoempresa_obrigacao
    RENAME TO tipoempresa_obrigacao_template_old;

ALTER TABLE IF EXISTS public.compromisso_financeiro
    ADD COLUMN IF NOT EXISTS dia_base NUMERIC NOT NULL DEFAULT 20;
ALTER TABLE IF EXISTS public.compromisso_financeiro
    ADD COLUMN IF NOT EXISTS mes_base VARCHAR(20);
ALTER TABLE IF EXISTS public.compromisso_financeiro
    ADD COLUMN IF NOT EXISTS tipo_classificacao VARCHAR(15);

UPDATE public.compromisso_financeiro cf
SET
    dia_base = t.dia_base,
    mes_base = CASE WHEN t.mes_base IS NULL THEN NULL ELSE trim(t.mes_base::text) END,
    tipo_classificacao = t.tipo
FROM public.tipoempresa_obrigacao_template_old t
WHERE cf.tipo_empresa_id = t.tipo_empresa_id
  AND cf.periodicidade = t.frequencia
  AND cf.ativo = true
  AND t.ativo = true
  AND (
        (cf.descricao ILIKE '%DAS%' AND t.descricao ILIKE '%DAS-MEI%')
     OR (cf.descricao ILIKE '%DASN%' AND t.descricao ILIKE '%DASN%')
     OR (cf.descricao ILIKE '%receita%' AND t.descricao ILIKE '%faturamento%')
     OR (cf.descricao ILIKE '%Taxas anuais%' AND t.descricao ILIKE '%Renovac%')
  );

UPDATE public.empresa_agenda ea
SET template_id = cf.id
FROM public.tipoempresa_obrigacao_template_old t
INNER JOIN public.compromisso_financeiro cf
    ON cf.tipo_empresa_id = t.tipo_empresa_id
   AND cf.periodicidade = t.frequencia
   AND cf.ativo = true
   AND t.ativo = true
   AND (
        (cf.descricao ILIKE '%DAS%' AND t.descricao ILIKE '%DAS-MEI%')
     OR (cf.descricao ILIKE '%DASN%' AND t.descricao ILIKE '%DASN%')
     OR (cf.descricao ILIKE '%receita%' AND t.descricao ILIKE '%faturamento%')
     OR (cf.descricao ILIKE '%Taxas anuais%' AND t.descricao ILIKE '%Renovac%')
   )
WHERE ea.template_id = t.id;

INSERT INTO public.compromisso_financeiro (
    id,
    tipo_empresa_id,
    natureza,
    descricao,
    periodicidade,
    abrangencia,
    valor,
    observacao,
    dia_base,
    mes_base,
    tipo_classificacao,
    ativo
)
SELECT
    t.id,
    t.tipo_empresa_id,
    CASE WHEN t.tipo = 'TRIBUTO' THEN 'FINANCEIRO' ELSE 'NAO_FINANCEIRO' END,
    t.descricao,
    t.frequencia,
    'FEDERAL',
    NULL,
    NULL,
    t.dia_base,
    CASE WHEN t.mes_base IS NULL THEN NULL ELSE trim(t.mes_base::text) END,
    t.tipo,
    true
FROM public.tipoempresa_obrigacao_template_old t
WHERE EXISTS (SELECT 1 FROM public.empresa_agenda ea WHERE ea.template_id = t.id)
  AND NOT EXISTS (SELECT 1 FROM public.compromisso_financeiro cf WHERE cf.id = t.id);

ALTER TABLE IF EXISTS public.empresa_agenda DROP CONSTRAINT IF EXISTS empresa_agenda_template_id_fkey;

DROP TABLE IF EXISTS public.tipoempresa_obrigacao_template_old;

ALTER TABLE public.empresa_agenda
    ADD CONSTRAINT empresa_agenda_template_id_fkey
    FOREIGN KEY (template_id) REFERENCES public.compromisso_financeiro(id) ON DELETE CASCADE;

ALTER TABLE IF EXISTS public.compromisso_estado RENAME COLUMN compromisso_id TO obrigacao_id;
ALTER TABLE IF EXISTS public.compromisso_estado RENAME TO tipoempresa_obriga_estado;

ALTER TABLE IF EXISTS public.compromisso_municipio RENAME COLUMN compromisso_id TO obrigacao_id;
ALTER TABLE IF EXISTS public.compromisso_municipio RENAME TO tipoempresa_obriga_municipio;

ALTER TABLE IF EXISTS public.compromisso_financeiro RENAME TO tipoempresa_obrigacao;

ALTER TABLE IF EXISTS public.empresa_compromissos DROP CONSTRAINT IF EXISTS empresa_compromissos_compromisso_financeiro_id_fkey;

ALTER TABLE IF EXISTS public.empresa_compromissos
    RENAME COLUMN compromisso_financeiro_id TO tipoempresa_obrigacao_id;

ALTER TABLE public.empresa_compromissos
    ADD CONSTRAINT empresa_compromissos_tipoempresa_obrigacao_id_fkey
    FOREIGN KEY (tipoempresa_obrigacao_id) REFERENCES public.tipoempresa_obrigacao(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_empresa_compromissos_tipo_obrigacao
    ON public.empresa_compromissos(tipoempresa_obrigacao_id);

CREATE INDEX IF NOT EXISTS idx_tipoempresa_obrigacao_tipo_empresa
    ON public.tipoempresa_obrigacao(tipo_empresa_id);

COMMIT;
