-- Dados complementares da empresa (1:1 com public.empresa).
-- Issue #45 — referência apenas por empresa_id.

CREATE TABLE IF NOT EXISTS public.empresa_dados (
    empresa_id         TEXT PRIMARY KEY
        REFERENCES public.empresa(id) ON DELETE CASCADE,
    cnpj               VARCHAR(18),
    endereco           TEXT,
    email_contato      VARCHAR(255),
    telefone           VARCHAR(40),
    telefone2          VARCHAR(40),
    data_abertura      DATE                 NULL,
    data_encerramento  DATE                 NULL,
    observacao         TEXT,
    criado_em          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    atualizado_em      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
