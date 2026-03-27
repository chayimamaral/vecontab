-- Migration: Obrigações por Tipo de Empresa + Agenda de Obrigações da Empresa
-- Data: 2026-03-26

-- Template de obrigações vinculado ao tipo de empresa
CREATE TABLE IF NOT EXISTS public.tipoempresa_obrigacao (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tipo_empresa_id  TEXT         NOT NULL REFERENCES public.tipoempresa(id) ON DELETE CASCADE,
    descricao        VARCHAR(255) NOT NULL,
    dia_base         INT          NOT NULL DEFAULT 20,
    mes_base         INT,                                 -- NULL = mensal; 1-12 = mês específico (anual)
    frequencia       VARCHAR(10)  NOT NULL DEFAULT 'MENSAL',  -- MENSAL | ANUAL
    tipo             VARCHAR(15)  NOT NULL DEFAULT 'TRIBUTO', -- TRIBUTO | INFORMATIVA
    ativo            BOOLEAN      NOT NULL DEFAULT TRUE,
    criado_em        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    atualizado_em    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Instâncias reais geradas para cada empresa
CREATE TABLE IF NOT EXISTS public.empresa_agenda (
    id               UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id       TEXT           NOT NULL REFERENCES public.empresa(id) ON DELETE CASCADE,
    template_id      UUID           NOT NULL REFERENCES public.tipoempresa_obrigacao(id) ON DELETE CASCADE,
    descricao        VARCHAR(255)   NOT NULL,
    data_vencimento  DATE           NOT NULL,
    status           VARCHAR(10)    NOT NULL DEFAULT 'PENDENTE', -- PENDENTE | PAGO | ATRASADO
    valor_estimado   NUMERIC(15,2),
    criado_em        TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    atualizado_em    TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tipoempresa_obrigacao_tipo_empresa
    ON public.tipoempresa_obrigacao(tipo_empresa_id);

CREATE INDEX IF NOT EXISTS idx_empresa_agenda_empresa
    ON public.empresa_agenda(empresa_id);

CREATE INDEX IF NOT EXISTS idx_empresa_agenda_template
    ON public.empresa_agenda(template_id);

CREATE INDEX IF NOT EXISTS idx_empresa_agenda_vencimento
    ON public.empresa_agenda(data_vencimento);
