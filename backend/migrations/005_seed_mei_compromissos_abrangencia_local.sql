-- Seed complementar para MEI com abrangencia local
-- Tipo empresa: 21a4bf05-3100-41e2-a3b2-e59ff67fc897
--
-- Cobre compromissos:
-- - ESTADUAL, MUNICIPAL e BAIRRO
-- - MENSAL e ANUAL
-- - FINANCEIRO e NAO_FINANCEIRO
--
-- Regras do script:
-- - Idempotente para compromisso_financeiro
-- - Atualiza/garante vinculo em compromisso_estado/compromisso_municipio/compromisso_bairro
-- - Se nao encontrar UF SP, usa o primeiro estado ativo
-- - Se nao encontrar municipio da UF escolhida, usa o primeiro municipio ativo

BEGIN;

DO $$
DECLARE
    v_tipo_empresa_id TEXT := '21a4bf05-3100-41e2-a3b2-e59ff67fc897';
    v_estado_id       TEXT;
    v_municipio_id    TEXT;
    v_compromisso_id  UUID;
    r                 RECORD;
BEGIN
    -- Estado alvo preferencial: SP
    SELECT e.id
      INTO v_estado_id
      FROM public.estado e
     WHERE e.ativo = TRUE
       AND e.sigla = 'SP'
     ORDER BY e.nome
     LIMIT 1;

    IF v_estado_id IS NULL THEN
        SELECT e.id
          INTO v_estado_id
          FROM public.estado e
         WHERE e.ativo = TRUE
         ORDER BY e.nome
         LIMIT 1;
    END IF;

    IF v_estado_id IS NULL THEN
        RAISE NOTICE 'Nenhum estado ativo encontrado. Seed 005 ignorada.';
        RETURN;
    END IF;

    -- Municipio alvo preferencial: primeiro municipio ativo da UF escolhida
    SELECT m.id
      INTO v_municipio_id
      FROM public.municipio m
     WHERE m.ativo = TRUE
       AND m.ufid = v_estado_id
     ORDER BY m.nome
     LIMIT 1;

    IF v_municipio_id IS NULL THEN
        SELECT m.id
          INTO v_municipio_id
          FROM public.municipio m
         WHERE m.ativo = TRUE
         ORDER BY m.nome
         LIMIT 1;
    END IF;

    IF v_municipio_id IS NULL THEN
        RAISE NOTICE 'Nenhum municipio ativo encontrado. Seed 005 ignorada.';
        RETURN;
    END IF;

    FOR r IN
        SELECT *
          FROM (
                VALUES
                -- ESTADUAL
                ('FINANCEIRO',     'MENSAL', 'ESTADUAL',  'MEI - Compromisso estadual mensal financeiro',     NULL),
                ('FINANCEIRO',     'ANUAL',  'ESTADUAL',  'MEI - Compromisso estadual anual financeiro',      NULL),
                ('NAO_FINANCEIRO', 'MENSAL', 'ESTADUAL',  'MEI - Compromisso estadual mensal nao financeiro', NULL),
                ('NAO_FINANCEIRO', 'ANUAL',  'ESTADUAL',  'MEI - Compromisso estadual anual nao financeiro',  NULL),

                -- MUNICIPAL
                ('FINANCEIRO',     'MENSAL', 'MUNICIPAL', 'MEI - Compromisso municipal mensal financeiro',     NULL),
                ('FINANCEIRO',     'ANUAL',  'MUNICIPAL', 'MEI - Compromisso municipal anual financeiro',      NULL),
                ('NAO_FINANCEIRO', 'MENSAL', 'MUNICIPAL', 'MEI - Compromisso municipal mensal nao financeiro', NULL),
                ('NAO_FINANCEIRO', 'ANUAL',  'MUNICIPAL', 'MEI - Compromisso municipal anual nao financeiro',  NULL),

                -- BAIRRO
                ('FINANCEIRO',     'MENSAL', 'BAIRRO',    'MEI - Compromisso bairro mensal financeiro',       'CENTRO'),
                ('FINANCEIRO',     'ANUAL',  'BAIRRO',    'MEI - Compromisso bairro anual financeiro',        'CENTRO'),
                ('NAO_FINANCEIRO', 'MENSAL', 'BAIRRO',    'MEI - Compromisso bairro mensal nao financeiro',   'CENTRO'),
                ('NAO_FINANCEIRO', 'ANUAL',  'BAIRRO',    'MEI - Compromisso bairro anual nao financeiro',    'CENTRO')
          ) AS t(natureza, periodicidade, abrangencia, descricao, bairro)
    LOOP
        -- 1) Garante registro base em compromisso_financeiro
        SELECT c.id
          INTO v_compromisso_id
          FROM public.compromisso_financeiro c
         WHERE c.tipo_empresa_id = v_tipo_empresa_id
           AND c.natureza = r.natureza
           AND c.periodicidade = r.periodicidade
           AND c.abrangencia = r.abrangencia
           AND c.descricao = r.descricao
           AND c.ativo = TRUE
         LIMIT 1;

        IF v_compromisso_id IS NULL THEN
            INSERT INTO public.compromisso_financeiro (
                tipo_empresa_id,
                natureza,
                descricao,
                periodicidade,
                abrangencia,
                valor,
                observacao,
                ativo
            )
            VALUES (
                v_tipo_empresa_id,
                r.natureza,
                r.descricao,
                r.periodicidade,
                r.abrangencia,
                NULL,
                'Seed automatico MEI - abrangencia local.',
                TRUE
            )
            RETURNING id INTO v_compromisso_id;
        END IF;

        -- 2) Garante relacionamento por abrangencia
        IF r.abrangencia = 'ESTADUAL' THEN
            INSERT INTO public.compromisso_estado (compromisso_id, estado_id)
            VALUES (v_compromisso_id, v_estado_id)
            ON CONFLICT (compromisso_id)
            DO UPDATE SET estado_id = EXCLUDED.estado_id;

        ELSIF r.abrangencia = 'MUNICIPAL' THEN
            INSERT INTO public.compromisso_municipio (compromisso_id, municipio_id)
            VALUES (v_compromisso_id, v_municipio_id)
            ON CONFLICT (compromisso_id)
            DO UPDATE SET municipio_id = EXCLUDED.municipio_id;

        ELSIF r.abrangencia = 'BAIRRO' THEN
            INSERT INTO public.compromisso_bairro (compromisso_id, municipio_id, bairro)
            VALUES (v_compromisso_id, v_municipio_id, COALESCE(r.bairro, 'CENTRO'))
            ON CONFLICT (compromisso_id)
            DO UPDATE SET
                municipio_id = EXCLUDED.municipio_id,
                bairro = EXCLUDED.bairro;
        END IF;
    END LOOP;
END $$;

COMMIT;
