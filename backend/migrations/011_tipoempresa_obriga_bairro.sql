-- Issue #34: obrigações por bairro em tabela dedicada.
-- Cria public.tipoempresa_obriga_bairro e migra dados legados de compromisso_bairro.

BEGIN;

CREATE TABLE IF NOT EXISTS public.tipoempresa_obriga_bairro (
    tipoempresa_obrigacao_id UUID         NOT NULL,
    municipio_id             TEXT         NOT NULL,
    bairro                   VARCHAR(255),
    CONSTRAINT tipoempresa_obriga_bairro_pkey PRIMARY KEY (tipoempresa_obrigacao_id),
    CONSTRAINT fk_obriga_bairro_municipio FOREIGN KEY (municipio_id)
        REFERENCES public.municipio(id) ON UPDATE NO ACTION ON DELETE NO ACTION,
    CONSTRAINT fk_obriga_bairro_obrigacao FOREIGN KEY (tipoempresa_obrigacao_id)
        REFERENCES public.tipoempresa_obrigacao(id) ON UPDATE NO ACTION ON DELETE CASCADE
);

INSERT INTO public.tipoempresa_obriga_bairro (tipoempresa_obrigacao_id, municipio_id, bairro)
SELECT cb.compromisso_id, cb.municipio_id, cb.bairro
FROM public.compromisso_bairro cb
INNER JOIN public.tipoempresa_obrigacao o ON o.id = cb.compromisso_id
ON CONFLICT (tipoempresa_obrigacao_id)
DO UPDATE SET
    municipio_id = EXCLUDED.municipio_id,
    bairro = EXCLUDED.bairro;

COMMIT;
