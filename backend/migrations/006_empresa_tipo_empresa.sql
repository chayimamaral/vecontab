-- Vincula empresa ao tipo de empresa (MEI, etc.) para dashboard e catálogo de compromissos.
-- Preenchido ao gerar agenda; permite listar compromissos do cadastro legal mesmo sem instância na agenda.

ALTER TABLE public.empresa
    ADD COLUMN IF NOT EXISTS tipo_empresa_id TEXT REFERENCES public.tipoempresa(id);

CREATE INDEX IF NOT EXISTS idx_empresa_tipo_empresa
    ON public.empresa(tipo_empresa_id);
