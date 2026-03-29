-- Instâncias de compromissos legais por empresa (cadastro compromisso_financeiro + tipo de empresa).
-- Data: 2026-03-28

ALTER TABLE IF EXISTS public.empresa
    ADD COLUMN IF NOT EXISTS bairro VARCHAR(255);

CREATE TABLE IF NOT EXISTS public.empresa_compromissos (
    id                        UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    descricao                 VARCHAR(255) NOT NULL,
    valor                     NUMERIC(12, 3),
    vencimento                TIMESTAMPTZ  NOT NULL,
    observacao                TEXT,
    status                    VARCHAR(20)  NOT NULL DEFAULT 'pendente',
    empresa_id                TEXT         NOT NULL REFERENCES public.empresa(id) ON DELETE CASCADE,
    compromisso_financeiro_id UUID         NOT NULL REFERENCES public.compromisso_financeiro(id) ON DELETE RESTRICT,
    criado_em                 TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    atualizado_em             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_empresa_compromissos_status CHECK (status IN ('pendente', 'concluido'))
);

CREATE INDEX IF NOT EXISTS idx_empresa_compromissos_empresa
    ON public.empresa_compromissos(empresa_id);

CREATE INDEX IF NOT EXISTS idx_empresa_compromissos_vencimento
    ON public.empresa_compromissos(vencimento);

CREATE INDEX IF NOT EXISTS idx_empresa_compromissos_compromisso_fin
    ON public.empresa_compromissos(compromisso_financeiro_id);
