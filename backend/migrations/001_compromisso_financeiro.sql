-- Migration: Cadastro de Compromissos Financeiros
-- Data: 2026-03-24

CREATE TABLE IF NOT EXISTS public.compromisso_financeiro (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    descricao     VARCHAR(255) NOT NULL,
    periodicidade VARCHAR(20)  NOT NULL DEFAULT 'MENSAL',  -- MENSAL | ANUAL
    abrangencia   VARCHAR(20)  NOT NULL DEFAULT 'FEDERAL', -- FEDERAL | ESTADUAL | MUNICIPAL | BAIRRO
    valor         NUMERIC(15,2),
    observacao    TEXT,
    ativo         BOOLEAN      NOT NULL DEFAULT TRUE,
    criado_em     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    atualizado_em TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ESTADUAL: um estado vinculado
CREATE TABLE IF NOT EXISTS public.compromisso_estado (
    compromisso_id UUID PRIMARY KEY REFERENCES public.compromisso_financeiro(id) ON DELETE CASCADE,
    estado_id      TEXT NOT NULL REFERENCES public.estado(id)
);

-- MUNICIPAL: um município vinculado
CREATE TABLE IF NOT EXISTS public.compromisso_municipio (
    compromisso_id UUID PRIMARY KEY REFERENCES public.compromisso_financeiro(id) ON DELETE CASCADE,
    municipio_id   TEXT NOT NULL REFERENCES public.municipio(id)
);

-- BAIRRO: um bairro específico dentro de um município (ex: taxa indígena Alphaville/Barueri)
CREATE TABLE IF NOT EXISTS public.compromisso_bairro (
    compromisso_id UUID         PRIMARY KEY REFERENCES public.compromisso_financeiro(id) ON DELETE CASCADE,
    municipio_id   TEXT         NOT NULL REFERENCES public.municipio(id),
    bairro         VARCHAR(255)
);

-- Mantem compatibilidade para bases onde a coluna foi criada como NOT NULL
ALTER TABLE IF EXISTS public.compromisso_bairro
    ALTER COLUMN bairro DROP NOT NULL;
