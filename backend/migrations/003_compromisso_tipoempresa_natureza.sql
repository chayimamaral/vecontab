-- Migration: vincula compromisso ao tipo de empresa e adiciona natureza
-- Data: 2026-03-26

ALTER TABLE IF EXISTS public.compromisso_financeiro
    ADD COLUMN IF NOT EXISTS tipo_empresa_id TEXT;

ALTER TABLE IF EXISTS public.compromisso_financeiro
    ADD COLUMN IF NOT EXISTS natureza VARCHAR(20) NOT NULL DEFAULT 'FINANCEIRO';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_compromisso_tipoempresa'
    ) THEN
        ALTER TABLE public.compromisso_financeiro
            ADD CONSTRAINT fk_compromisso_tipoempresa
            FOREIGN KEY (tipo_empresa_id) REFERENCES public.tipoempresa(id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_compromisso_financeiro_tipoempresa
    ON public.compromisso_financeiro(tipo_empresa_id);

-- Ajusta registros existentes sem vínculo para evitar inconsistência futura.
-- Se houver dados legados, eles devem ser revisados e associados ao tipoempresa correto.