-- Issue #46: estrutura hierárquica CNAE 2.3 (IBGE), alinhada a kelvinsousa/ibge-cnae-2.3
-- Execute antes de 015_cnae_ibge_seed.sql

ALTER TABLE public.cnae
    ADD COLUMN IF NOT EXISTS secao TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS divisao TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS grupo TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS classe TEXT NOT NULL DEFAULT '';

COMMENT ON COLUMN public.cnae.secao IS 'Descrição da seção (CNAE 2.3 IBGE)';
COMMENT ON COLUMN public.cnae.divisao IS 'Descrição da divisão';
COMMENT ON COLUMN public.cnae.grupo IS 'Descrição do grupo';
COMMENT ON COLUMN public.cnae.classe IS 'Descrição da classe';
COMMENT ON COLUMN public.cnae.subclasse IS 'Código da subclasse (7 dígitos, sem máscara)';

-- Catálogo auxiliar (repovoado em 015). Permite JOIN na API quando colunas acima estiverem vazias.
CREATE TABLE IF NOT EXISTS public.cnae_ibge_hierarquia (
    subclasse TEXT PRIMARY KEY,
    secao     TEXT NOT NULL,
    divisao   TEXT NOT NULL,
    grupo     TEXT NOT NULL,
    classe    TEXT NOT NULL
);
