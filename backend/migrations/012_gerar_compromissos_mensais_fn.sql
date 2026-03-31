-- Issue #36
-- Geração idempotente de compromissos por tenant e competência.

BEGIN;

-- Idempotência: empresa + obrigação + competência (mês/ano).
ALTER TABLE IF EXISTS public.empresa_compromissos
    ADD COLUMN IF NOT EXISTS competencia date;

UPDATE public.empresa_compromissos
SET competencia = date_trunc('month', vencimento::date)::date
WHERE competencia IS NULL;

ALTER TABLE IF EXISTS public.empresa_compromissos
    ALTER COLUMN competencia SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_empresa_compromissos_empresa_obrigacao_competencia
    ON public.empresa_compromissos (empresa_id, tipoempresa_obrigacao_id, competencia);

CREATE OR REPLACE FUNCTION public.gerar_compromissos_mensais(
    in_tenant_id text,
    in_data_referencia date DEFAULT CURRENT_DATE,
    in_empresa_id text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_inserido integer := 0;
    v_competencia date := date_trunc('month', COALESCE(in_data_referencia, CURRENT_DATE))::date;
    v_ref_ano integer := EXTRACT(YEAR FROM v_competencia);
    v_ref_mes integer := EXTRACT(MONTH FROM v_competencia);
    rec record;
    v_mes_base integer;
    v_dia integer;
    v_data_venc date;
    v_valor numeric(12,3);
    v_status varchar(20) := 'pendente';
BEGIN
    IF trim(COALESCE(in_tenant_id, '')) = '' THEN
        RAISE EXCEPTION 'tenant_id é obrigatório';
    END IF;

    FOR rec IN
        SELECT
            e.id AS empresa_id,
            e.municipio_id,
            m.ufid AS estado_id,
            COALESCE(NULLIF(trim(e.bairro), ''), '') AS bairro_empresa,
            o.id AS obrigacao_id,
            o.descricao,
            upper(trim(COALESCE(o.periodicidade, 'MENSAL'))) AS periodicidade,
            upper(trim(COALESCE(o.abrangencia, 'FEDERAL'))) AS abrangencia,
            upper(trim(COALESCE(o.tipo_classificacao, 'TRIBUTARIA'))) AS tipo_classificacao,
            COALESCE(NULLIF(trim(o.mes_base), ''), '') AS mes_base_txt,
            COALESCE(o.dia_base::int, 20) AS dia_base,
            COALESCE(o.valor, 0)::numeric(12,3) AS valor_raw,
            COALESCE(o.observacao, '') AS observacao
        FROM public.empresa e
        INNER JOIN public.municipio m ON m.id = e.municipio_id
        INNER JOIN public.rotinas r ON r.id = e.rotina_id AND r.ativo = true
        INNER JOIN public.tipoempresa_obrigacao o ON o.tipo_empresa_id = r.tipo_empresa_id AND o.ativo = true
        LEFT JOIN public.tipoempresa_obriga_estado oe ON oe.obrigacao_id = o.id
        LEFT JOIN public.tipoempresa_obriga_municipio om ON om.obrigacao_id = o.id
        LEFT JOIN public.tipoempresa_obriga_bairro ob ON ob.tipoempresa_obrigacao_id = o.id
        WHERE e.ativo = true
          AND e.tenant_id = in_tenant_id
          AND (in_empresa_id IS NULL OR e.id = in_empresa_id)
          AND (
            o.abrangencia = 'FEDERAL'
            OR (o.abrangencia = 'ESTADUAL' AND oe.estado_id = m.ufid)
            OR (o.abrangencia = 'MUNICIPAL' AND om.municipio_id = e.municipio_id)
            OR (
                o.abrangencia = 'BAIRRO'
                AND ob.municipio_id = e.municipio_id
                AND (
                    ob.bairro IS NULL OR trim(ob.bairro) = ''
                    OR lower(trim(ob.bairro)) = lower(trim(COALESCE(e.bairro, '')))
                )
            )
          )
    LOOP
        -- Mês base default para periodicidade anual/trimestral.
        BEGIN
            v_mes_base := NULLIF(rec.mes_base_txt, '')::int;
        EXCEPTION WHEN others THEN
            v_mes_base := NULL;
        END;
        IF v_mes_base IS NULL OR v_mes_base < 1 OR v_mes_base > 12 THEN
            v_mes_base := v_ref_mes;
        END IF;

        -- Filtro por periodicidade.
        IF rec.periodicidade = 'ANUAL' AND v_ref_mes <> v_mes_base THEN
            CONTINUE;
        END IF;

        IF rec.periodicidade = 'TRIMESTRAL' THEN
            -- Se mês base for 2, gera em 2/5/8/11. Se 3, 3/6/9/12 etc.
            IF ((v_ref_mes - v_mes_base + 12) % 3) <> 0 THEN
                CONTINUE;
            END IF;
        END IF;

        -- MENSAL (e não reconhecidas): gera no mês corrente.
        v_dia := LEAST(GREATEST(rec.dia_base, 1), EXTRACT(DAY FROM (date_trunc('month', v_competencia) + interval '1 month - 1 day'))::int);
        v_data_venc := make_date(v_ref_ano, v_ref_mes, v_dia);

        -- Ajuste inteligente: usa função existente (finais de semana + feriado fixo/variável).
        v_data_venc := public.calcular_data_termino(v_data_venc, 0);

        -- Complementa com escopo municipal/estadual.
        WHILE EXISTS (
            SELECT 1
            FROM public.feriados f
            LEFT JOIN public.feriado_municipal fm ON fm.feriado_id = f.id
            LEFT JOIN public.feriado_estadual fe ON fe.feriado_id = f.id
            WHERE f.ativo = true
              AND (
                (f.feriado = 'MUNICIPAL' AND fm.municipio_id = rec.municipio_id)
                OR (f.feriado = 'ESTADUAL' AND fe.uf_id = rec.estado_id)
              )
              AND to_date(f.data || '/' || EXTRACT(YEAR FROM v_data_venc)::int, 'DD/MM/YYYY') = v_data_venc
        ) LOOP
            v_data_venc := v_data_venc + interval '1 day';
            v_data_venc := public.calcular_data_termino(v_data_venc, 0);
        END LOOP;

        IF upper(trim(COALESCE(rec.tipo_classificacao, ''))) IN ('TRIBUTARIA', 'TRIBUTO') THEN
            v_valor := rec.valor_raw;
        ELSE
            v_valor := NULL;
        END IF;

        INSERT INTO public.empresa_compromissos (
            descricao, valor, vencimento, observacao, status, empresa_id, tipoempresa_obrigacao_id, competencia
        )
        VALUES (
            rec.descricao, v_valor, v_data_venc::timestamptz, rec.observacao, v_status, rec.empresa_id, rec.obrigacao_id, v_competencia
        )
        ON CONFLICT (empresa_id, tipoempresa_obrigacao_id, competencia)
        DO NOTHING;

        IF FOUND THEN
            v_total_inserido := v_total_inserido + 1;
        END IF;
    END LOOP;

    RETURN v_total_inserido;
END;
$$;

COMMIT;
