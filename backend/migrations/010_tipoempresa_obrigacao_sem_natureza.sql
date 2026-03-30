-- Remove coluna `natureza` de tipoempresa_obrigacao; classificação única em `tipo_classificacao`.
-- Normaliza legado: TRIBUTO -> TRIBUTARIA; preenche tipo_classificacao a partir de natureza quando existir.

BEGIN;

UPDATE public.tipoempresa_obrigacao
SET tipo_classificacao = 'TRIBUTARIA'
WHERE UPPER(TRIM(COALESCE(tipo_classificacao, ''))) = 'TRIBUTO';

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'tipoempresa_obrigacao'
      AND column_name = 'natureza'
  ) THEN
    UPDATE public.tipoempresa_obrigacao
    SET tipo_classificacao = CASE
        WHEN UPPER(TRIM(COALESCE(natureza, ''))) = 'FINANCEIRO' THEN 'TRIBUTARIA'
        ELSE 'INFORMATIVA'
      END
    WHERE tipo_classificacao IS NULL OR TRIM(tipo_classificacao) = '';

    ALTER TABLE public.tipoempresa_obrigacao DROP COLUMN natureza;
  END IF;
END $$;

COMMIT;
