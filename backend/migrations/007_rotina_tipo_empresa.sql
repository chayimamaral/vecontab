-- Rotina vinculada a um tipo de empresa (obrigações / compromissos gerados a partir da rotina da empresa).
ALTER TABLE public.rotinas
    ADD COLUMN IF NOT EXISTS tipo_empresa_id TEXT REFERENCES public.tipoempresa(id);

CREATE INDEX IF NOT EXISTS idx_rotinas_tipo_empresa
    ON public.rotinas(tipo_empresa_id);
