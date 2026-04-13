-- Regime tributario (CRT federal + metadados de obrigacoes). Issue #74.
-- Aplicar manualmente no Postgres (pasta raiz migrations/ pode estar no .gitignore).

DO $$ BEGIN
    CREATE TYPE public.tipo_apuracao_regime AS ENUM ('MENSAL', 'TRIMESTRAL');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.regime_tributario (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    nome text NOT NULL,
    codigo_crt smallint NOT NULL CHECK (codigo_crt >= 1 AND codigo_crt <= 4),
    tipo_apuracao public.tipo_apuracao_regime NOT NULL DEFAULT 'MENSAL',
    ativo boolean NOT NULL DEFAULT true,
    configuracao_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT regime_tributario_codigo_crt_key UNIQUE (codigo_crt)
);

CREATE INDEX IF NOT EXISTS idx_regime_tributario_nome ON public.regime_tributario (lower(nome));

COMMENT ON TABLE public.regime_tributario IS 'Regimes tributarios (codigo CRT SPED) e configuracao_json com metadados de obrigacoes sugeridas.';

-- Seeds idempotentes (nao sobrescreve linhas ja existentes com mesmo codigo_crt)
INSERT INTO public.regime_tributario (nome, codigo_crt, tipo_apuracao, ativo, configuracao_json)
SELECT v.nome, v.codigo_crt, v.tipo_apuracao, v.ativo, v.configuracao_json::jsonb
FROM (
    VALUES
        (
            'Simples Nacional',
            1::smallint,
            'MENSAL'::public.tipo_apuracao_regime,
            true,
            '{"apuracao_padrao":"MENSAL","obrigacoes_federais":[{"codigo":"DAS_SIMPLES","periodicidade":"MENSAL"},{"codigo":"PGDAS_D","periodicidade":"MENSAL"},{"codigo":"DEFIS","periodicidade":"ANUAL"}],"efd":{"ICMS_IPI":false,"Contribuicoes":false,"Fiscal":false,"Reinf":true}}'
        ),
        (
            'Simples Nacional - excesso de sublimite de receita bruta',
            2::smallint,
            'MENSAL'::public.tipo_apuracao_regime,
            true,
            '{"apuracao_padrao":"MENSAL","obrigacoes_federais":[{"codigo":"DAS_SIMPLES","periodicidade":"MENSAL"},{"codigo":"PGDAS_D","periodicidade":"MENSAL"},{"codigo":"DEFIS","periodicidade":"ANUAL"}],"efd":{"ICMS_IPI":false,"Contribuicoes":true,"Fiscal":true,"Reinf":true},"nota":"A partir do excesso, EFDs podem ser exigidas conforme caso; revisar enquadramento."}'
        ),
        (
            'Regime Normal — Lucro Presumido',
            3::smallint,
            'MENSAL'::public.tipo_apuracao_regime,
            true,
            '{"apuracao_padrao":"MENSAL","obrigacoes_federais":[{"codigo":"DCTF","periodicidade":"MENSAL"},{"codigo":"DARF_IRPJ_CSLL","periodicidade":"MENSAL"}],"efd":{"ICMS_IPI":true,"Contribuicoes":true,"Fiscal":true,"Reinf":true}}'
        ),
        (
            'Regime Normal — Lucro Real',
            4::smallint,
            'MENSAL'::public.tipo_apuracao_regime,
            true,
            '{"apuracao_padrao":"MENSAL","obrigacoes_federais":[{"codigo":"DCTF","periodicidade":"MENSAL"},{"codigo":"DARF_IRPJ_CSLL","periodicidade":"MENSAL"}],"efd":{"ICMS_IPI":true,"Contribuicoes":true,"Fiscal":true,"Reinf":true},"nota":"Lucro Real admite apuracao trimestral opcional conforme escrituracao; tipo_apuracao cadastral pode ser TRIMESTRAL."}'
        )
) AS v(nome, codigo_crt, tipo_apuracao, ativo, configuracao_json)
WHERE NOT EXISTS (SELECT 1 FROM public.regime_tributario r WHERE r.codigo_crt = v.codigo_crt);
