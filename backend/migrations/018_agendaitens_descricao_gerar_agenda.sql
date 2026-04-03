-- Issue #53: copiar descricao do passo nos itens da agenda; itens sem passo_id permitidos (somente BD).

ALTER TABLE public.agendaitens
    ADD COLUMN IF NOT EXISTS descricao text;

UPDATE public.agendaitens ai
SET descricao = p.descricao
FROM public.passos p
WHERE ai.passo_id = p.id
  AND (ai.descricao IS NULL OR btrim(ai.descricao) = '');

ALTER TABLE public.agendaitens
    ALTER COLUMN passo_id DROP NOT NULL;

CREATE OR REPLACE FUNCTION public.gerar_agenda(in_empresa_id text, in_tenant_id text, in_rotina_id text)
RETURNS void
LANGUAGE plpgsql
COST 20
AS $$
DECLARE
    agenda_id text;
    agenda_termino date;
    tempo_estimado_passo integer;
    maior_data_termino date := CURRENT_DATE;
    passo_record RECORD;
BEGIN
    INSERT INTO public.agenda (empresa_id, tenant_id, rotina_id, inicio)
    VALUES (in_empresa_id, in_tenant_id, in_rotina_id, CURRENT_DATE)
    RETURNING id INTO agenda_id;

    agenda_termino := public.calcular_data_termino(CURRENT_DATE, 0);

    FOR passo_record IN
        SELECT ri.passo_id, p.tempoestimado, p.descricao
        FROM public.rotinaitens ri
        LEFT JOIN public.passos p ON p.id = ri.passo_id
        WHERE ri.rotina_id = in_rotina_id
        ORDER BY ri.ordem
    LOOP
        CONTINUE WHEN passo_record.passo_id IS NULL;
        tempo_estimado_passo := COALESCE(passo_record.tempoestimado, 0);
        agenda_termino := public.calcular_data_termino(CURRENT_DATE, tempo_estimado_passo);

        INSERT INTO public.agendaitens (agenda_id, passo_id, inicio, termino, descricao)
        VALUES (
            agenda_id,
            passo_record.passo_id,
            CURRENT_DATE,
            agenda_termino,
            COALESCE(passo_record.descricao, '')
        );

        IF agenda_termino > maior_data_termino THEN
            maior_data_termino := agenda_termino;
        END IF;
    END LOOP;

    UPDATE public.agenda
    SET termino = maior_data_termino
    WHERE id = agenda_id;
END;
$$;
