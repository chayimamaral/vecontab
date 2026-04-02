--
-- PostgreSQL database dump
--

\restrict lXlIztUtigNpfTzEKI4XEKsJU89980CClofONytDviwldNFGecgF8KYB5ivB4jG

-- Dumped from database version 18.3
-- Dumped by pg_dump version 18.3

-- Started on 2026-04-02 10:20:59 -03

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 5 (class 2615 OID 2200)
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- TOC entry 911 (class 1247 OID 17605)
-- Name: feriado; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.feriado AS ENUM (
    'MUNICIPAL',
    'ESTADUAL',
    'FIXO',
    'VARIAVEL'
);


--
-- TOC entry 914 (class 1247 OID 17614)
-- Name: feriado_old; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.feriado_old AS ENUM (
    'MUNICIPAL',
    'ESTADUAL',
    'NACIONAL',
    'FIXO',
    'VARIAVEL'
);


--
-- TOC entry 917 (class 1247 OID 17626)
-- Name: plano; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.plano AS ENUM (
    'DEMO',
    'BASICO',
    'INTERMEDIARIO',
    'PRO'
);


--
-- TOC entry 920 (class 1247 OID 17636)
-- Name: role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.role AS ENUM (
    'SUPER',
    'ADMIN',
    'USER',
    'CONTADOR',
    'FISCAL',
    'FINANCEIRO',
    'TRIBUTARIO'
);


--
-- TOC entry 923 (class 1247 OID 17652)
-- Name: status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.status AS ENUM (
    'Pendente',
    'Concluída'
);


--
-- TOC entry 260 (class 1255 OID 17657)
-- Name: calcular_data_termino(date, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calcular_data_termino(inicio date, tempo_estimado integer) RETURNS date
    LANGUAGE plpgsql COST 20
    AS $$
DECLARE
    data_termino date;
BEGIN
    -- Inicialmente, a data de término é igual à data de início mais o tempo estimado em dias
    data_termino := inicio + tempo_estimado * interval '1 day';

    -- Verificar se a data de término cai em um feriado ou fim de semana
    WHILE EXTRACT(ISODOW FROM data_termino) IN (6, 7) OR EXISTS (
        SELECT 1 FROM feriados f WHERE to_date(f.data || ' ' || EXTRACT(YEAR FROM CURRENT_DATE), 'DD/MM/YYYY') = data_termino
    ) LOOP
        -- Se cair em um fim de semana ou feriado, adicione um dia útil
        data_termino := data_termino + interval '1 day';
    END LOOP;

    RETURN data_termino;
END;
$$;


--
-- TOC entry 277 (class 1255 OID 17658)
-- Name: gerar_agenda(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gerar_agenda(in_empresa_id text, in_tenant_id text, in_rotina_id text) RETURNS void
    LANGUAGE plpgsql COST 20
    AS $$
DECLARE
    agenda_id text;
    agenda_termino date;
	tempo_estimado_passo integer;
	maior_data_termino date := CURRENT_DATE; -- Inicialize com a data atual
	passo_record RECORD; -- Declare um cursor do tipo RECORD
BEGIN
    -- Inserir a nova empresa na tabela agenda
    INSERT INTO agenda (empresa_id, tenant_id, rotina_id, inicio)
    VALUES (in_empresa_id, in_tenant_id, in_rotina_id, CURRENT_DATE)
    RETURNING id INTO agenda_id;

	agenda_termino := calcular_data_termino(CURRENT_DATE, 0);

-- Iterar sobre os passos da rotina	
	FOR passo_record IN
		SELECT ri.passo_id, p.tempoestimado
		FROM rotinaitens ri
		LEFT JOIN passos p ON p.id = ri.passo_id
		WHERE rotina_id = in_rotina_id
		ORDER BY ordem
	LOOP
		-- Obter o tempo estimado do passo atual
		tempo_estimado_passo := passo_record.tempoestimado;
		-- Calcular a data de término para este passo
		agenda_termino := calcular_data_termino(CURRENT_DATE, tempo_estimado_passo);
		
		-- Inserir na tabela "agendaitens" com as datas calculadas
		INSERT INTO agendaitens(agenda_id, passo_id, inicio, termino) 
		VALUES (agenda_id, passo_record.passo_id, CURRENT_DATE, agenda_termino);
	
	-- Atualizar a maior data de término, se necessário
        IF agenda_termino > maior_data_termino THEN
            maior_data_termino := agenda_termino;
        END IF;
	
    END LOOP;

    -- Atualizar a data de término na tabela agenda
    UPDATE agenda
    SET termino = maior_data_termino
    WHERE id = agenda_id;

    -- Comitar a transação
    --COMMIT;
END;
$$;


--
-- TOC entry 278 (class 1255 OID 17659)
-- Name: gerar_agenda_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gerar_agenda_trigger() RETURNS trigger
    LANGUAGE plpgsql COST 20
    AS $$
BEGIN
    -- Chame a função intermediária passando os parâmetros necessários
    IF (NEW.iniciado = true AND OLD.iniciado = false) THEN
	  PERFORM gerar_agenda(NEW.id, NEW.tenant_id, NEW.rotina_id);
	END IF;
    RETURN NEW;
END;
$$;


--
-- TOC entry 286 (class 1255 OID 28904)
-- Name: gerar_compromissos_core(date, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gerar_compromissos_core(in_data_referencia date DEFAULT CURRENT_DATE, in_empresa_id text DEFAULT NULL::text, in_tenant_id text DEFAULT NULL::text) RETURNS integer
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
    IF in_empresa_id IS NOT NULL AND trim(in_empresa_id) = '' THEN
        RAISE EXCEPTION 'empresa_id inválido';
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
          AND (in_tenant_id IS NULL OR e.tenant_id = in_tenant_id)
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

        -- Posterga para próximo dia útil considerando finais de semana e todos os feriados aplicáveis.
        v_data_venc := public.postergar_para_proximo_dia_util(v_data_venc, rec.municipio_id, rec.estado_id);

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


--
-- TOC entry 287 (class 1255 OID 28906)
-- Name: gerar_compromissos_empresa(text, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gerar_compromissos_empresa(in_empresa_id text, in_data_referencia date DEFAULT CURRENT_DATE) RETURNS integer
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF trim(COALESCE(in_empresa_id, '')) = '' THEN
        RAISE EXCEPTION 'empresa_id é obrigatório';
    END IF;

    RETURN public.gerar_compromissos_core(in_data_referencia, in_empresa_id, NULL);
END;
$$;


--
-- TOC entry 288 (class 1255 OID 28907)
-- Name: gerar_compromissos_geral(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gerar_compromissos_geral(in_data_referencia date DEFAULT ((date_trunc('month'::text, (CURRENT_DATE)::timestamp with time zone) + '1 mon'::interval))::date) RETURNS integer
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN public.gerar_compromissos_core(in_data_referencia, NULL, NULL);
END;
$$;


--
-- TOC entry 289 (class 1255 OID 28901)
-- Name: gerar_compromissos_mensais(text, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gerar_compromissos_mensais(in_tenant_id text, in_data_referencia date DEFAULT CURRENT_DATE, in_empresa_id text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF trim(COALESCE(in_tenant_id, '')) = '' THEN
        RAISE EXCEPTION 'tenant_id é obrigatório';
    END IF;

    RETURN public.gerar_compromissos_core(in_data_referencia, in_empresa_id, in_tenant_id);
END;
$$;


--
-- TOC entry 279 (class 1255 OID 17660)
-- Name: get_cidades_with_ufs(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_cidades_with_ufs() RETURNS json
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN (
    SELECT json_agg(
      json_build_object(
        'id', c.id,
        'nome', c.nome,
        'codigo', c.codigo,
        'ufId', c.ufid,
        'uf', json_build_object(
          'id', e.id,
          'nome', e.nome
        )
      )
    )
    FROM municipio c
    JOIN estado e ON c.ufid = e.id
  );
END;
$$;


--
-- TOC entry 280 (class 1255 OID 17661)
-- Name: get_cidades_with_ufs2(character varying, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_cidades_with_ufs2(p_field character varying DEFAULT 'c.name'::character varying, p_order integer DEFAULT 1, p_first integer DEFAULT 0, p_rows integer DEFAULT 20) RETURNS json
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN (
    SELECT json_agg(
      json_build_object(
        'id', c.id,
        'nome', c.nome,
        'codigo', c.codigo,
        'ufId', c.ufid,
        'uf', json_build_object(
          'id', e.id,
          'nome', e.nome
        )
      )
    )
    FROM municipio c
    JOIN estado e ON c.ufid = e.id
	LIMIT p_rows OFFSET p_first
  );
END;
$$;


--
-- TOC entry 281 (class 1255 OID 17662)
-- Name: get_passos_nested(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_passos_nested() RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'key', p.id,
     'descricao', p.descricao,
     'tempoestimado', p.tempoestimado,
     'children', get_passos_nested_children(p.id)
  ) INTO result
  FROM passos p
  WHERE p.parent_id IS NULL;

  RETURN result;
END;
$$;


--
-- TOC entry 282 (class 1255 OID 17663)
-- Name: get_passos_nested_children(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_passos_nested_children(_parent_id text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object(
      'key', p.id,
       'descricao', p.descricao,
       'tempoestimado', p.tempoestimado,
       'children',get_passos_nested_children(p.id)
    )
  ) INTO result
  FROM passos p
  WHERE p.parent_id = _parent_id;

  RETURN result;
END;
$$;


--
-- TOC entry 283 (class 1255 OID 17664)
-- Name: get_passos_recur(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_passos_recur() RETURNS json
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN (
    SELECT json_agg(
      json_build_object(
        'id', p.id,
        'descricao', p.descricao,
        'tempoestimado', p.tempoestimado,
		'nodes', json_build_object(
      	  'id', f.id,
      	  'descricao', f.descricao,
      	  'tempoestimado', f.tempoestimado,
		  'parent_id', f.parent_id	 
        )
      )
    )
    FROM passos f
    JOIN passos p ON f.parent_id = p.id
  );
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 219 (class 1259 OID 17665)
-- Name: estado; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.estado (
    id text DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    sigla text NOT NULL,
    ativo boolean DEFAULT true
);


--
-- TOC entry 284 (class 1255 OID 17675)
-- Name: getfoo(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.getfoo(character varying) RETURNS SETOF public.estado
    LANGUAGE sql
    AS $_$
    SELECT * FROM public.estado WHERE id = $1;
$_$;


--
-- TOC entry 261 (class 1255 OID 17676)
-- Name: inserir_passos_na_agenda(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inserir_passos_na_agenda(empresa_id text, rotina_id text) RETURNS void
    LANGUAGE plpgsql
    AS $_$
BEGIN
    -- Inserir os passos da rotina na tabela de Agenda
    INSERT INTO agenda (empresa_id, passo_id)
    SELECT $1, passo_id
    FROM rotinaitens
    WHERE rotina_id = $2;
    
    -- Comitar a transação
    COMMIT;
END;
$_$;


--
-- TOC entry 262 (class 1255 OID 17677)
-- Name: nested(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.nested(_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
  _descricao TEXT;
BEGIN
  SELECT descricao INTO _descricao
  FROM node
  WHERE id = _Id;

  RETURN jsonb_pretty(jsonb_build_object(
    'id', _Id,
    'descricao', _descricao,
    'children', (
      SELECT jsonb_agg(r(id))
      FROM node
      WHERE node_parent_id = _Id
    )
  ));
END;
$$;


--
-- TOC entry 285 (class 1255 OID 28903)
-- Name: postergar_para_proximo_dia_util(date, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.postergar_para_proximo_dia_util(in_data date, in_municipio_id text DEFAULT NULL::text, in_estado_id text DEFAULT NULL::text) RETURNS date
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_data date := in_data;
BEGIN
    IF v_data IS NULL THEN
        RETURN NULL;
    END IF;

    LOOP
        -- Fim de semana.
        IF EXTRACT(ISODOW FROM v_data) IN (6, 7) THEN
            v_data := v_data + 1;
            CONTINUE;
        END IF;

        -- Feriado: FIXO / VARIAVEL / MUNICIPAL / ESTADUAL.
        IF EXISTS (
            SELECT 1
            FROM public.feriados f
            LEFT JOIN public.feriado_municipal fm ON fm.feriado_id = f.id
            LEFT JOIN public.feriado_estadual fe ON fe.feriado_id = f.id
            WHERE f.ativo = true
              AND (
                    f.feriado IN ('FIXO', 'VARIAVEL')
                    OR (f.feriado = 'MUNICIPAL' AND fm.municipio_id = in_municipio_id)
                    OR (f.feriado = 'ESTADUAL' AND fe.uf_id = in_estado_id)
                  )
              AND to_date(f.data || '/' || EXTRACT(YEAR FROM v_data)::int, 'DD/MM/YYYY') = v_data
        ) THEN
            v_data := v_data + 1;
            CONTINUE;
        END IF;

        RETURN v_data;
    END LOOP;
END;
$$;


--
-- TOC entry 263 (class 1255 OID 17678)
-- Name: r(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.r(_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
  _descricao TEXT;
BEGIN
  SELECT descricao INTO _descricao
  FROM node
  WHERE id = _Id;

  RETURN jsonb_build_object(
    'id', _Id,
    'descricao', _descricao,
    'children', (
      SELECT jsonb_agg(r(id))
      FROM node
      WHERE node_parent_id = _Id
    )
  );
END;
$$;


--
-- TOC entry 264 (class 1255 OID 17679)
-- Name: recur(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recur(_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
  _descricao TEXT;
BEGIN
  SELECT descricao INTO _descricao
  FROM node
  WHERE id = _Id;

  RETURN jsonb_build_object(
    'id', _Id,
    'descricao', _descricao,
    'children', (
      SELECT jsonb_agg(r(id))
      FROM node
      WHERE node_parent_id = _Id
    )
  );
END;
$$;


--
-- TOC entry 265 (class 1255 OID 17680)
-- Name: recursive_example(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recursive_example() RETURNS TABLE(id integer, value text)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY WITH RECURSIVE recursive_cte(id, value) AS (
    SELECT 1, 'Value 1'
    UNION ALL
    SELECT id + 1, 'Value ' || (id + 1)
    FROM recursive_cte
    WHERE id < 5
  )
  SELECT id, value
  FROM recursive_cte;
END;
$$;


--
-- TOC entry 220 (class 1259 OID 17681)
-- Name: agenda; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agenda (
    id text DEFAULT gen_random_uuid() NOT NULL,
    inicio date NOT NULL,
    descricao text,
    status text,
    tenant_id text NOT NULL,
    createdat timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updatedat timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    empresa_id text NOT NULL,
    rotina_id text NOT NULL,
    termino date
);


--
-- TOC entry 221 (class 1259 OID 17696)
-- Name: agendaitens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agendaitens (
    id text DEFAULT gen_random_uuid() NOT NULL,
    agenda_id text NOT NULL,
    passo_id text NOT NULL,
    inicio date,
    termino date,
    concluido boolean DEFAULT false NOT NULL
);


--
-- TOC entry 222 (class 1259 OID 17707)
-- Name: cnae; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cnae (
    id text DEFAULT gen_random_uuid() NOT NULL,
    subclasse text NOT NULL,
    denominacao text NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    secao text DEFAULT ''::text NOT NULL,
    divisao text DEFAULT ''::text NOT NULL,
    grupo text DEFAULT ''::text NOT NULL,
    classe text DEFAULT ''::text NOT NULL
);


--
-- TOC entry 4889 (class 0 OID 0)
-- Dependencies: 222
-- Name: COLUMN cnae.subclasse; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.cnae.subclasse IS 'Código da subclasse (7 dígitos, sem máscara)';


--
-- TOC entry 4890 (class 0 OID 0)
-- Dependencies: 222
-- Name: COLUMN cnae.secao; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.cnae.secao IS 'Descrição da seção (CNAE 2.3 IBGE)';


--
-- TOC entry 4891 (class 0 OID 0)
-- Dependencies: 222
-- Name: COLUMN cnae.divisao; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.cnae.divisao IS 'Descrição da divisão';


--
-- TOC entry 4892 (class 0 OID 0)
-- Dependencies: 222
-- Name: COLUMN cnae.grupo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.cnae.grupo IS 'Descrição do grupo';


--
-- TOC entry 4893 (class 0 OID 0)
-- Dependencies: 222
-- Name: COLUMN cnae.classe; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.cnae.classe IS 'Descrição da classe';


--
-- TOC entry 249 (class 1259 OID 28941)
-- Name: cnae_ibge_hierarquia; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cnae_ibge_hierarquia (
    subclasse text NOT NULL,
    secao text NOT NULL,
    divisao text NOT NULL,
    grupo text NOT NULL,
    classe text NOT NULL
);


--
-- TOC entry 223 (class 1259 OID 17718)
-- Name: dadoscomplementares; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dadoscomplementares (
    endereco text,
    bairro text,
    cidade text,
    estado text,
    cep text,
    telefone text,
    email text,
    cnpj text,
    ie text,
    im text,
    tenantid text NOT NULL,
    createdat timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updatedat timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fantasia text,
    razaosocial text,
    observacoes text
);


--
-- TOC entry 224 (class 1259 OID 17728)
-- Name: empresa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.empresa (
    id text DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    municipio_id text NOT NULL,
    dataabertura timestamp(3) without time zone,
    datafechamento timestamp(3) without time zone,
    ativo boolean DEFAULT true,
    tenant_id text NOT NULL,
    rotina_id text NOT NULL,
    cnaes text[],
    iniciado boolean DEFAULT false NOT NULL,
    bairro character varying(255)
);


--
-- TOC entry 246 (class 1259 OID 28766)
-- Name: empresa_agenda; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.empresa_agenda (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    empresa_id text NOT NULL,
    template_id uuid NOT NULL,
    descricao character varying(255) NOT NULL,
    data_vencimento date NOT NULL,
    status character varying(10) DEFAULT 'PENDENTE'::character varying NOT NULL,
    valor_estimado numeric(15,2),
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- TOC entry 247 (class 1259 OID 28851)
-- Name: empresa_compromissos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.empresa_compromissos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    descricao character varying(255) NOT NULL,
    valor numeric(12,3),
    vencimento timestamp with time zone NOT NULL,
    observacao text,
    status character varying(20) DEFAULT 'pendente'::character varying NOT NULL,
    empresa_id text NOT NULL,
    tipoempresa_obrigacao_id uuid CONSTRAINT empresa_compromissos_compromisso_financeiro_id_not_null NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    competencia date NOT NULL,
    CONSTRAINT chk_empresa_compromissos_status CHECK (((status)::text = ANY ((ARRAY['pendente'::character varying, 'concluido'::character varying])::text[])))
);


--
-- TOC entry 248 (class 1259 OID 28908)
-- Name: empresa_dados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.empresa_dados (
    empresa_id text NOT NULL,
    cnpj character varying(18),
    endereco text,
    email_contato character varying(255),
    telefone character varying(40),
    telefone2 character varying(40),
    data_abertura date,
    data_encerramento date,
    observacao text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- TOC entry 225 (class 1259 OID 17742)
-- Name: empresacnae; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.empresacnae (
    empresa text NOT NULL,
    cnae text NOT NULL
);


--
-- TOC entry 226 (class 1259 OID 17749)
-- Name: empresadados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.empresadados (
    id text DEFAULT gen_random_uuid() NOT NULL,
    razaosocial text NOT NULL,
    fantasia text,
    cnpj text,
    ie text,
    im text,
    empresaid text
);


--
-- TOC entry 227 (class 1259 OID 17757)
-- Name: feriado_estadual; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.feriado_estadual (
    feriado_id text NOT NULL,
    uf_id text NOT NULL
);


--
-- TOC entry 228 (class 1259 OID 17764)
-- Name: feriado_municipal; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.feriado_municipal (
    feriado_id text NOT NULL,
    municipio_id text NOT NULL
);


--
-- TOC entry 229 (class 1259 OID 17771)
-- Name: feriados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.feriados (
    id text DEFAULT gen_random_uuid() NOT NULL,
    descricao text NOT NULL,
    data character varying(5),
    ativo boolean DEFAULT true NOT NULL,
    feriado public.feriado DEFAULT 'VARIAVEL'::public.feriado NOT NULL
);


--
-- TOC entry 230 (class 1259 OID 17783)
-- Name: grupopassos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grupopassos (
    id text DEFAULT gen_random_uuid() NOT NULL,
    descricao text NOT NULL,
    municipio_id text NOT NULL,
    createdat timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updatedat timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    tipoempresa_id text NOT NULL,
    ativo boolean DEFAULT true NOT NULL
);


--
-- TOC entry 257 (class 1259 OID 29005)
-- Name: ibge_cnae_classe; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ibge_cnae_classe (
    id integer NOT NULL,
    grupo_id integer NOT NULL,
    nome text NOT NULL
);


--
-- TOC entry 256 (class 1259 OID 29004)
-- Name: ibge_cnae_classe_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ibge_cnae_classe_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 4894 (class 0 OID 0)
-- Dependencies: 256
-- Name: ibge_cnae_classe_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ibge_cnae_classe_id_seq OWNED BY public.ibge_cnae_classe.id;


--
-- TOC entry 253 (class 1259 OID 28967)
-- Name: ibge_cnae_divisao; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ibge_cnae_divisao (
    id integer NOT NULL,
    secao_id smallint NOT NULL,
    nome text NOT NULL
);


--
-- TOC entry 252 (class 1259 OID 28966)
-- Name: ibge_cnae_divisao_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ibge_cnae_divisao_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 4895 (class 0 OID 0)
-- Dependencies: 252
-- Name: ibge_cnae_divisao_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ibge_cnae_divisao_id_seq OWNED BY public.ibge_cnae_divisao.id;


--
-- TOC entry 255 (class 1259 OID 28986)
-- Name: ibge_cnae_grupo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ibge_cnae_grupo (
    id integer NOT NULL,
    divisao_id integer NOT NULL,
    nome text NOT NULL
);


--
-- TOC entry 254 (class 1259 OID 28985)
-- Name: ibge_cnae_grupo_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ibge_cnae_grupo_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 4896 (class 0 OID 0)
-- Dependencies: 254
-- Name: ibge_cnae_grupo_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ibge_cnae_grupo_id_seq OWNED BY public.ibge_cnae_grupo.id;


--
-- TOC entry 251 (class 1259 OID 28954)
-- Name: ibge_cnae_secao; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ibge_cnae_secao (
    id smallint NOT NULL,
    nome text NOT NULL
);


--
-- TOC entry 250 (class 1259 OID 28953)
-- Name: ibge_cnae_secao_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ibge_cnae_secao_id_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 4897 (class 0 OID 0)
-- Dependencies: 250
-- Name: ibge_cnae_secao_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ibge_cnae_secao_id_seq OWNED BY public.ibge_cnae_secao.id;


--
-- TOC entry 259 (class 1259 OID 29024)
-- Name: ibge_cnae_subclasse; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ibge_cnae_subclasse (
    id integer NOT NULL,
    classe_id integer NOT NULL,
    codigo character(7) NOT NULL,
    nome text NOT NULL
);


--
-- TOC entry 258 (class 1259 OID 29023)
-- Name: ibge_cnae_subclasse_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ibge_cnae_subclasse_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 4898 (class 0 OID 0)
-- Dependencies: 258
-- Name: ibge_cnae_subclasse_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ibge_cnae_subclasse_id_seq OWNED BY public.ibge_cnae_subclasse.id;


--
-- TOC entry 231 (class 1259 OID 17799)
-- Name: itenspassos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.itenspassos (
    id text DEFAULT gen_random_uuid() NOT NULL,
    grupopassos_id text NOT NULL,
    passos_id text NOT NULL
);


--
-- TOC entry 232 (class 1259 OID 17808)
-- Name: linkpassos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.linkpassos (
    passo_id text NOT NULL,
    link text NOT NULL
);


--
-- TOC entry 233 (class 1259 OID 17815)
-- Name: municipio; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.municipio (
    id text DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    codigo text NOT NULL,
    ufid text NOT NULL,
    ativo boolean DEFAULT true
);


--
-- TOC entry 234 (class 1259 OID 17826)
-- Name: passos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.passos (
    id text DEFAULT gen_random_uuid() NOT NULL,
    descricao text NOT NULL,
    tempoestimado integer,
    createdat timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updatedat timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    tipopasso character(1) NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    municipio_id text NOT NULL
);


--
-- TOC entry 235 (class 1259 OID 17842)
-- Name: rotinaitemlink; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rotinaitemlink (
    rotinaitem_id text NOT NULL,
    link text
);


--
-- TOC entry 236 (class 1259 OID 17848)
-- Name: rotinaitens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rotinaitens (
    rotina_id text NOT NULL,
    passo_id text NOT NULL,
    ordem integer
);


--
-- TOC entry 237 (class 1259 OID 17855)
-- Name: rotinas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rotinas (
    id text DEFAULT gen_random_uuid() NOT NULL,
    descricao text NOT NULL,
    municipio_id text NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    tipo_empresa_id text
);


--
-- TOC entry 238 (class 1259 OID 17866)
-- Name: tenant; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenant (
    id text DEFAULT gen_random_uuid() NOT NULL,
    nome text,
    contato text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    createdat timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updatedat timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    plano public.plano DEFAULT 'DEMO'::public.plano NOT NULL
);


--
-- TOC entry 239 (class 1259 OID 17882)
-- Name: tipoempresa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tipoempresa (
    descricao character varying(50),
    capital numeric(10,2),
    anual numeric(10,2),
    ativo boolean DEFAULT true,
    id text DEFAULT gen_random_uuid() NOT NULL
);


--
-- TOC entry 244 (class 1259 OID 27527)
-- Name: tipoempresa_obriga_bairro; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tipoempresa_obriga_bairro (
    tipoempresa_obrigacao_id uuid CONSTRAINT compromisso_bairro_compromisso_id_not_null NOT NULL,
    municipio_id text CONSTRAINT compromisso_bairro_municipio_id_not_null NOT NULL,
    bairro character varying(255)
);


--
-- TOC entry 242 (class 1259 OID 27489)
-- Name: tipoempresa_obriga_estado; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tipoempresa_obriga_estado (
    obrigacao_id uuid CONSTRAINT compromisso_estado_compromisso_id_not_null NOT NULL,
    estado_id text CONSTRAINT compromisso_estado_estado_id_not_null NOT NULL
);


--
-- TOC entry 243 (class 1259 OID 27508)
-- Name: tipoempresa_obriga_municipio; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tipoempresa_obriga_municipio (
    obrigacao_id uuid CONSTRAINT compromisso_municipio_compromisso_id_not_null NOT NULL,
    municipio_id text CONSTRAINT compromisso_municipio_municipio_id_not_null NOT NULL
);


--
-- TOC entry 241 (class 1259 OID 27358)
-- Name: tipoempresa_obrigacao; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tipoempresa_obrigacao (
    id uuid DEFAULT gen_random_uuid() CONSTRAINT compromisso_financeiro_id_not_null NOT NULL,
    descricao character varying(255) CONSTRAINT compromisso_financeiro_descricao_not_null NOT NULL,
    periodicidade character varying(20) DEFAULT 'MENSAL'::character varying CONSTRAINT compromisso_financeiro_periodicidade_not_null NOT NULL,
    abrangencia character varying(20) DEFAULT 'FEDERAL'::character varying CONSTRAINT compromisso_financeiro_abrangencia_not_null NOT NULL,
    valor numeric(15,2),
    observacao text,
    ativo boolean DEFAULT true CONSTRAINT compromisso_financeiro_ativo_not_null NOT NULL,
    criado_em timestamp with time zone DEFAULT now() CONSTRAINT compromisso_financeiro_criado_em_not_null NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() CONSTRAINT compromisso_financeiro_atualizado_em_not_null NOT NULL,
    tipo_empresa_id text,
    dia_base numeric DEFAULT 20 CONSTRAINT compromisso_financeiro_dia_base_not_null NOT NULL,
    mes_base character varying(20),
    tipo_classificacao character varying(15)
);


--
-- TOC entry 245 (class 1259 OID 28738)
-- Name: tipoempresa_obrigacao_old; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tipoempresa_obrigacao_old (
    id uuid DEFAULT gen_random_uuid() CONSTRAINT tipoempresa_obrigacao_id_not_null NOT NULL,
    tipo_empresa_id text CONSTRAINT tipoempresa_obrigacao_tipo_empresa_id_not_null NOT NULL,
    descricao character varying(255) CONSTRAINT tipoempresa_obrigacao_descricao_not_null NOT NULL,
    dia_base integer DEFAULT 20 CONSTRAINT tipoempresa_obrigacao_dia_base_not_null NOT NULL,
    mes_base integer,
    frequencia character varying(10) DEFAULT 'MENSAL'::character varying CONSTRAINT tipoempresa_obrigacao_frequencia_not_null NOT NULL,
    tipo character varying(15) DEFAULT 'TRIBUTO'::character varying CONSTRAINT tipoempresa_obrigacao_tipo_not_null NOT NULL,
    ativo boolean DEFAULT true CONSTRAINT tipoempresa_obrigacao_ativo_not_null NOT NULL,
    criado_em timestamp with time zone DEFAULT now() CONSTRAINT tipoempresa_obrigacao_criado_em_not_null NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() CONSTRAINT tipoempresa_obrigacao_atualizado_em_not_null NOT NULL
);


--
-- TOC entry 240 (class 1259 OID 17890)
-- Name: usuario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario (
    id text DEFAULT gen_random_uuid() NOT NULL,
    password text NOT NULL,
    email character varying(100) NOT NULL,
    tenantid text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    createdat timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    role public.role DEFAULT 'USER'::public.role NOT NULL,
    updatedat timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    nome character varying(50) NOT NULL
);


--
-- TOC entry 4566 (class 2604 OID 29008)
-- Name: ibge_cnae_classe id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_classe ALTER COLUMN id SET DEFAULT nextval('public.ibge_cnae_classe_id_seq'::regclass);


--
-- TOC entry 4564 (class 2604 OID 28970)
-- Name: ibge_cnae_divisao id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_divisao ALTER COLUMN id SET DEFAULT nextval('public.ibge_cnae_divisao_id_seq'::regclass);


--
-- TOC entry 4565 (class 2604 OID 28989)
-- Name: ibge_cnae_grupo id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_grupo ALTER COLUMN id SET DEFAULT nextval('public.ibge_cnae_grupo_id_seq'::regclass);


--
-- TOC entry 4563 (class 2604 OID 28957)
-- Name: ibge_cnae_secao id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_secao ALTER COLUMN id SET DEFAULT nextval('public.ibge_cnae_secao_id_seq'::regclass);


--
-- TOC entry 4567 (class 2604 OID 29027)
-- Name: ibge_cnae_subclasse id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_subclasse ALTER COLUMN id SET DEFAULT nextval('public.ibge_cnae_subclasse_id_seq'::regclass);


--
-- TOC entry 4844 (class 0 OID 17681)
-- Dependencies: 220
-- Data for Name: agenda; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agenda (id, inicio, descricao, status, tenant_id, createdat, updatedat, empresa_id, rotina_id, termino) FROM stdin;
5f251afd-3951-4e58-8fb2-0303bbc3bdad	2023-09-22	\N	\N	5bf1a2bc-b39e-4af6-97df-bb70326373ab	2023-09-22 15:24:35.639	2023-09-22 15:24:35.639	67207fad-07aa-4daf-b667-f3b926a120ad	005a21fd-3aaa-43ee-a2e8-647a4d8845ab	2023-10-02
a90b8b23-50d5-4ffd-9ffd-08a3eb578ce1	2023-09-26	\N	\N	5bf1a2bc-b39e-4af6-97df-bb70326373ab	2023-09-26 09:18:20.972	2023-09-26 09:18:20.972	32c99043-ae5e-47a6-b3db-e02f13b5aff9	ed925e14-d150-434f-b287-7154d67c1d0a	2023-09-26
e046dbb2-bfc7-49af-be92-924810821ab3	2023-09-22	\N	passos_concluidos	5bf1a2bc-b39e-4af6-97df-bb70326373ab	2023-09-22 16:34:51.735	2023-09-22 16:34:51.735	56fab307-b775-40f6-87ef-51daa7509698	595ac1c0-fe5e-4a87-8871-9d9cce8fce04	2023-09-27
4455250a-562b-4382-b41e-55bc39fe4792	2023-09-26	\N	passos_concluidos	5bf1a2bc-b39e-4af6-97df-bb70326373ab	2023-09-26 09:30:25.016	2023-09-26 09:30:25.016	3bd699c9-15dc-4a79-8ee8-0a098073203b	ed925e14-d150-434f-b287-7154d67c1d0a	2023-10-02
94decc02-dcbb-4d26-be3e-4a22d7a59851	2023-09-25	\N	passos_concluidos	5bf1a2bc-b39e-4af6-97df-bb70326373ab	2023-09-25 09:29:18.882	2023-09-25 09:29:18.882	2d969b03-f302-437a-8cfe-7b85da6e28fb	595ac1c0-fe5e-4a87-8871-9d9cce8fce04	2023-10-02
1ea777c7-574e-4b84-82b0-e0db28344ffc	2026-03-27	\N	passos_concluidos	5bf1a2bc-b39e-4af6-97df-bb70326373ab	2026-03-27 16:17:37.572	2026-03-27 16:17:37.572	5b2eacf9-5289-402d-85be-52f7233d20d2	1cd6c238-d805-4c94-829e-bad7a9b62cfb	2026-03-30
\.


--
-- TOC entry 4845 (class 0 OID 17696)
-- Dependencies: 221
-- Data for Name: agendaitens; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agendaitens (id, agenda_id, passo_id, inicio, termino, concluido) FROM stdin;
6dbc422d-495a-41f7-86e0-a0e2d0bef38a	5f251afd-3951-4e58-8fb2-0303bbc3bdad	136e1f3e-1705-485f-9927-3074cc416e43	2023-09-22	2023-09-25	f
a0977c38-0dd4-4dfb-b269-c061cc098a05	5f251afd-3951-4e58-8fb2-0303bbc3bdad	7b35949c-3740-4da9-99c0-a15bdf3ff6d5	2023-09-22	2023-09-25	f
52c45622-b6c0-4452-a80e-922c400e8ed3	5f251afd-3951-4e58-8fb2-0303bbc3bdad	31445cac-91dc-4c21-bec2-adc240905b2e	2023-09-22	2023-09-25	f
da03147e-6e7c-470e-b4e6-44eba97e9c29	5f251afd-3951-4e58-8fb2-0303bbc3bdad	1236690c-828f-4459-895b-cc53a27ba9f4	2023-09-22	2023-09-25	f
016cceac-191c-4fe5-8ae9-55066c6c13cc	5f251afd-3951-4e58-8fb2-0303bbc3bdad	e62ddd44-7581-4a91-8e9a-9200b92aba45	2023-09-22	2023-09-25	f
246ecd16-5222-43a0-bb29-9fa64d4eb4f9	5f251afd-3951-4e58-8fb2-0303bbc3bdad	5047a655-d6b3-431f-96fd-c7e4cbcb7ee0	2023-09-22	2023-09-25	f
1dd6cf0c-525e-452c-ad12-f8a735de8e38	5f251afd-3951-4e58-8fb2-0303bbc3bdad	3fe622f0-96c4-4457-8c90-ae6ebcaf19b3	2023-09-22	2023-09-25	f
5ebd0ab2-564e-4f09-8bf8-23cba9c61716	e046dbb2-bfc7-49af-be92-924810821ab3	78417170-c0d7-4ca6-bbf4-4c69d994ccd8	2023-09-22	2023-09-27	t
bc0ff9bf-8398-4f90-8f34-8bc832199282	e046dbb2-bfc7-49af-be92-924810821ab3	b9206898-3ecd-4bd5-b83a-9249d5dd1bc2	2023-09-22	2023-09-25	t
d84bb762-8363-4602-b7fa-795a1aa5946c	e046dbb2-bfc7-49af-be92-924810821ab3	d4ededcb-b5a2-402a-90e6-f4db735beb29	2023-09-22	2023-09-25	t
9c335e83-3e65-4464-ad23-120b161d4d75	e046dbb2-bfc7-49af-be92-924810821ab3	f45dc0a4-0a3e-4984-9a9d-a3ff706b3402	2023-09-22	2023-09-25	t
ce2b0c2a-fafb-4391-96f6-c013bc7a6569	5f251afd-3951-4e58-8fb2-0303bbc3bdad	1d64ff79-3192-4b28-a4b8-7654daea77f4	2023-09-22	2023-10-02	t
6ce47c34-780b-4c25-8f22-cbc42445326f	5f251afd-3951-4e58-8fb2-0303bbc3bdad	91168e21-df97-4ab2-b1f5-ec35e9103efc	2023-09-22	2023-10-02	t
1fae3841-8df0-4b2f-a0e4-a40d63591032	5f251afd-3951-4e58-8fb2-0303bbc3bdad	023b4bb7-6054-4e14-b93b-7354d5e95eb8	2023-09-22	2023-09-26	t
df374bf0-9433-40e0-aa55-ca8456224462	4455250a-562b-4382-b41e-55bc39fe4792	e58d4218-1fa0-4a8a-a80f-fdb5ef245bef	2023-09-26	2023-10-02	t
0348d7ce-fa9c-4f06-9894-ca6dbdd1bee6	4455250a-562b-4382-b41e-55bc39fe4792	264e9bfa-aac4-4524-be04-9e569feb1d30	2023-09-26	2023-10-02	t
3be13a6f-0056-4995-8573-721a1d1daa67	5f251afd-3951-4e58-8fb2-0303bbc3bdad	9e705234-9d64-4b41-bca3-d71d94d2c323	2023-09-22	2023-09-26	t
e02dca63-6171-482c-846d-01da41e39788	94decc02-dcbb-4d26-be3e-4a22d7a59851	78417170-c0d7-4ca6-bbf4-4c69d994ccd8	2023-09-25	2023-10-02	t
17b5a28d-e75a-4aa0-9545-75038624d647	94decc02-dcbb-4d26-be3e-4a22d7a59851	b9206898-3ecd-4bd5-b83a-9249d5dd1bc2	2023-09-25	2023-09-28	t
53dc7c5c-9d97-42b6-a858-7a30f45673d1	94decc02-dcbb-4d26-be3e-4a22d7a59851	d4ededcb-b5a2-402a-90e6-f4db735beb29	2023-09-25	2023-09-28	t
704980ff-1118-4994-9953-e8fa36be2dad	94decc02-dcbb-4d26-be3e-4a22d7a59851	f45dc0a4-0a3e-4984-9a9d-a3ff706b3402	2023-09-25	2023-09-28	t
ef3f73f9-34d1-4d83-8eba-ff1941ea2ada	1ea777c7-574e-4b84-82b0-e0db28344ffc	5047a655-d6b3-431f-96fd-c7e4cbcb7ee0	2026-03-27	2026-03-30	t
6f2df927-5605-4e86-af65-24d7f1b35b36	1ea777c7-574e-4b84-82b0-e0db28344ffc	7b35949c-3740-4da9-99c0-a15bdf3ff6d5	2026-03-27	2026-03-30	t
7e581fba-717f-4f50-b4c8-69806a5706e0	1ea777c7-574e-4b84-82b0-e0db28344ffc	31445cac-91dc-4c21-bec2-adc240905b2e	2026-03-27	2026-03-30	t
\.


--
-- TOC entry 4846 (class 0 OID 17707)
-- Dependencies: 222
-- Data for Name: cnae; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.cnae (id, subclasse, denominacao, ativo, secao, divisao, grupo, classe) FROM stdin;
db7aeb3b-e82f-4163-a65f-ecdc36c17c1a	0111301	CULTIVO DE ARROZ	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE CEREAIS
3164e6da-4913-4eaf-a3c1-bfbdcc35ca4c	0111302	CULTIVO DE MILHO	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE CEREAIS
4ee51d04-dc39-4e3e-b604-def3840c3f92	0111303	CULTIVO DE TRIGO	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE CEREAIS
e81240e3-9916-4e4f-be7f-9ed7fcf01a79	0111399	CULTIVO DE OUTROS CEREAIS NÃO ESPECIFICADOS ANTERIORMENTE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE CEREAIS
6b324f22-0494-49b3-bd35-07625d6cd28f	0112101	CULTIVO DE ALGODÃO HERBÁCEO	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE ALGODÃO HERBÁCEO E DE OUTRAS FIBRAS DE LAVOURA TEMPORÁRIA
5f4abf5c-790d-4621-83f5-3965e0429655	0112102	CULTIVO DE JUTA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE ALGODÃO HERBÁCEO E DE OUTRAS FIBRAS DE LAVOURA TEMPORÁRIA
aead227b-17e4-4f06-9091-79f98b1a6e8a	0112199	CULTIVO DE OUTRAS FIBRAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE ALGODÃO HERBÁCEO E DE OUTRAS FIBRAS DE LAVOURA TEMPORÁRIA
46a47acf-2e02-42f2-8118-de05d6cc26b0	0113000	CULTIVO DE CANA DE AÇÚCAR	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE CANA-DE-AÇÚCAR
8fe36f1a-f1ec-4bd4-93d6-385a35cd6c54	0114800	CULTIVO DE FUMO	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE FUMO
2bf44835-6906-4091-85cb-cd3a53bf646f	0115600	CULTIVO DE SOJA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE SOJA
5afe5ee5-d83d-4d62-9f27-b7514b71f665	0116401	CULTIVO DE AMENDOIM	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE OLEAGINOSAS DE LAVOURA TEMPORÁRIA, EXCETO SOJA
0d3244ae-aefe-43b2-90e4-8188e056db95	0116402	CULTIVO DE GIRASSOL	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE OLEAGINOSAS DE LAVOURA TEMPORÁRIA, EXCETO SOJA
4dd0819d-9485-41cf-9305-f56846091cb5	0116403	CULTIVO DE MAMONA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE OLEAGINOSAS DE LAVOURA TEMPORÁRIA, EXCETO SOJA
5114ec3f-cf6c-45a3-a030-4f5bbd43f5d5	0116499	CULTIVO DE OUTRAS OLEAGINOSAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE OLEAGINOSAS DE LAVOURA TEMPORÁRIA, EXCETO SOJA
275ea278-fcfe-4636-851c-cc75a0de3d59	0119901	CULTIVO DE ABACAXI	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
b805a0f7-94fd-4d75-9061-89b99e68168a	0119902	CULTIVO DE ALHO	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
a0136f4b-164f-4158-bdbb-6673a9be9afd	0119903	CULTIVO DE BATATA INGLESA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
de9dffe5-126a-47b8-9319-c8bbdf41186d	0119904	CULTIVO DE CEBOLA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
0adf256e-79b6-4355-b1ba-46096d17a279	0119905	CULTIVO DE FEIJÃO	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
7219a0d8-64d6-42c5-92a0-950ee6879643	0119906	CULTIVO DE MANDIOCA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
0a5d908f-cb41-4408-b903-7136cefc2e9d	0119907	CULTIVO DE MELÃO	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
3428cd73-d3e8-440e-bc42-197181f3ad72	0119908	CULTIVO DE MELANCIA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
dbb86e5e-857f-4af0-a143-2b36b0059e16	0119909	CULTIVO DE TOMATE RASTEIRO	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
cc3bc355-4274-4d25-9e4f-52cd2389a9a5	0119999	CULTIVO DE OUTRAS PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
39b25e62-62fd-425b-a339-894601d5dc5c	0121101	HORTICULTURA, EXCETO MORANGO	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	HORTICULTURA E FLORICULTURA	HORTICULTURA
9da42e48-0cc6-4d97-a3da-cfa7bf381068	0121102	CULTIVO DE MORANGO	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	HORTICULTURA E FLORICULTURA	HORTICULTURA
61753682-9ea4-402c-9c5e-16c3415783c5	0122900	CULTIVO DE FLORES E PLANTAS ORNAMENTAIS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	HORTICULTURA E FLORICULTURA	CULTIVO DE FLORES E PLANTAS ORNAMENTAIS
63bb29f8-8096-484f-a10d-36cb0428149b	0131800	CULTIVO DE LARANJA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE LARANJA
9efa0f4c-a296-4365-92ef-bab6556218c7	0132600	CULTIVO DE UVA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE UVA
f996c343-8a2e-4aa8-9420-cc276c176efc	0133401	CULTIVO DE AÇAÍ	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
f429ab28-3003-454e-8c29-5afda3a76a9b	0133402	CULTIVO DE BANANA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
7f6c98fb-cc07-45b1-9409-a162df705a1a	0133403	CULTIVO DE CAJU	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
44f3fc48-ea5e-4009-aa86-d8970937afd6	0133404	CULTIVO DE CÍTRICOS, EXCETO LARANJA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
f735e3ac-b2f9-4490-8ab5-62a175ea0dbc	0133405	CULTIVO DE COCO DA BAÍA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
e9ae76e1-982c-4d08-92f4-9b6a009e7359	0133406	CULTIVO DE GUARANÁ	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
ce1444ae-e99b-412e-8305-111a810a4c53	0133407	CULTIVO DE MAÇÃ	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
42322b76-8dac-426e-83e3-9b0cddd621a2	0133408	CULTIVO DE MAMÃO	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
e72369f8-9cff-464a-b798-41c15f97feb2	0133409	CULTIVO DE MARACUJÁ	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
a5313049-ac22-48b5-a727-3780944affc6	0133410	CULTIVO DE MANGA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
85a62201-7f93-4df6-a333-c5f6b30b3452	0133411	CULTIVO DE PÊSSEGO	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
e465a0ad-e865-44a0-b3e7-686679a87871	0133499	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
d0eb9c53-ec24-4959-96a8-d3fc51c471b0	0134200	CULTIVO DE CAFÉ	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE CAFÉ
555af518-c770-460c-b89f-cacf40d3f16c	0135100	CULTIVO DE CACAU	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE CACAU
3caf2614-5aad-4843-b33c-f185bd4cc2a4	0139301	CULTIVO DE CHÁ DA ÍNDIA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE PLANTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE
837bec0f-a56d-45d8-b8ea-f503868d1112	0139302	CULTIVO DE ERVA MATE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE PLANTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE
11e59cff-95aa-4659-bf34-a68d509e6156	0139303	CULTIVO DE PIMENTA DO REINO	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE PLANTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE
27b1637f-3626-472f-a4c7-cfc14037f20d	0139304	CULTIVO DE PLANTAS PARA CONDIMENTO, EXCETO PIMENTA DO REINO	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE PLANTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE
b4953e45-7bde-40ae-9d5e-37b3db7f5969	0139305	CULTIVO DE DENDÊ	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE PLANTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE
cb0de53b-534b-4ff7-a446-09896d853a5c	0139306	CULTIVO DE SERINGUEIRA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE PLANTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE
81f39e5e-e37b-459f-9101-8e2acc483010	0139399	CULTIVO DE OUTRAS PLANTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE PLANTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE
8d3043ec-a10c-44fe-b9b8-2598706db2cb	0141501	PRODUÇÃO DE SEMENTES CERTIFICADAS, EXCETO DE FORRAGEIRAS PARA PASTO	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE SEMENTES E MUDAS CERTIFICADAS	PRODUÇÃO DE SEMENTES CERTIFICADAS
f7139eae-be4b-40dc-b6fa-53b7c667e5cf	0141502	PRODUÇÃO DE SEMENTES CERTIFICADAS DE FORRAGEIRAS PARA FORMAÇÃO DE PASTO	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE SEMENTES E MUDAS CERTIFICADAS	PRODUÇÃO DE SEMENTES CERTIFICADAS
decf7c5e-4e49-44af-8974-9b06c304c83d	0142300	PRODUÇÃO DE MUDAS E OUTRAS FORMAS DE PROPAGAÇÃO VEGETAL, CERTIFICADAS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE SEMENTES E MUDAS CERTIFICADAS	PRODUÇÃO DE MUDAS E OUTRAS FORMAS DE PROPAGAÇÃO VEGETAL, CERTIFICADAS
a4fb252b-3daa-4d16-b091-ec6b086ced15	0151201	CRIAÇÃO DE BOVINOS PARA CORTE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE BOVINOS
6a16a568-4cc3-4e98-b859-82e4190d21c1	0151202	CRIAÇÃO DE BOVINOS PARA LEITE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE BOVINOS
b507551f-54bd-477f-8e8b-acbadbda6a26	0151203	CRIAÇÃO DE BOVINOS, EXCETO PARA CORTE E LEITE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE BOVINOS
936503d3-994a-4118-8651-6e789ec66703	0152101	CRIAÇÃO DE BUFALINOS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE OUTROS ANIMAIS DE GRANDE PORTE
025110f2-6f34-43fb-bc9a-6947075e6732	0152102	CRIAÇÃO DE EQUINOS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE OUTROS ANIMAIS DE GRANDE PORTE
00b5925c-061d-4889-85ef-a9271ca34f4a	0152103	CRIAÇÃO DE ASININOS E MUARES	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE OUTROS ANIMAIS DE GRANDE PORTE
4145c00c-c5ee-496e-8eac-2f9aa8f9c7a2	0153901	CRIAÇÃO DE CAPRINOS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE CAPRINOS E OVINOS
0edbfd66-c068-4a2f-826d-59e6e7d9d639	0153902	CRIAÇÃO DE OVINOS, INCLUSIVE PARA PRODUÇÃO DE LÃ	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE CAPRINOS E OVINOS
caf6272d-7113-48b6-ad34-0619ef77542b	0154700	CRIAÇÃO DE SUÍNOS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE SUÍNOS
b7e846ef-8d84-49c8-9127-c5cc8f841109	0155501	CRIAÇÃO DE FRANGOS PARA CORTE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE AVES
58315f17-0646-4352-a627-e331a2864cdd	0155502	PRODUÇÃO DE PINTOS DE UM DIA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE AVES
213f88ac-4b4a-4dee-823f-8ffc1b10c3f7	0155503	CRIAÇÃO DE OUTROS GALINÁCEOS, EXCETO PARA CORTE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE AVES
d23298d9-d59a-4175-8412-be2bf72f0d36	0155504	CRIAÇÃO DE AVES, EXCETO GALINÁCEOS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE AVES
9fb9806f-d9b4-4ce9-a62c-7115b99ad85a	0155505	PRODUÇÃO DE OVOS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE AVES
e2ecfea9-f25d-4214-a92c-a1bedb0e85c0	0159801	APICULTURA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE ANIMAIS NÃO ESPECIFICADOS ANTERIORMENTE
ec03ec23-d2b8-48a4-92ae-e3fb80bb675f	0159802	CRIAÇÃO DE ANIMAIS DE ESTIMAÇÃO	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE ANIMAIS NÃO ESPECIFICADOS ANTERIORMENTE
0b3468c2-8fef-4e91-bbce-846e27c8cf64	0159803	CRIAÇÃO DE ESCARGÔ	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE ANIMAIS NÃO ESPECIFICADOS ANTERIORMENTE
c9c144d9-7c59-4836-8485-a8db4ba754ec	0159804	CRIAÇÃO DE BICHO DA SEDA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE ANIMAIS NÃO ESPECIFICADOS ANTERIORMENTE
c15a032c-6961-4017-8005-3766eb8e7ce0	0159899	CRIAÇÃO DE OUTROS ANIMAIS NÃO ESPECIFICADOS ANTERIORMENTE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE ANIMAIS NÃO ESPECIFICADOS ANTERIORMENTE
494ab074-138f-4fdd-a85f-337fbb5e5a67	0161001	SERVIÇO DE PULVERIZAÇÃO E CONTROLE DE PRAGAS AGRÍCOLAS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA	ATIVIDADES DE APOIO À AGRICULTURA
360b4e07-024d-4f17-a5af-12d4ed3a58a1	0161002	SERVIÇO DE PODA DE ÁRVORES PARA LAVOURAS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA	ATIVIDADES DE APOIO À AGRICULTURA
160ac69c-53a6-4071-bdd5-973ea6c71687	0161003	SERVIÇO DE PREPARAÇÃO DE TERRENO, CULTIVO E COLHEITA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA	ATIVIDADES DE APOIO À AGRICULTURA
bc0d8037-2ed4-470f-b1ed-9b2f010841f9	0161099	ATIVIDADES DE APOIO À AGRICULTURA NÃO ESPECIFICADAS ANTERIORMENTE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA	ATIVIDADES DE APOIO À AGRICULTURA
fef99498-6bf6-4fdc-a9ce-d97c73e8f82f	0162801	SERVIÇO DE INSEMINAÇÃO ARTIFICIAL DE ANIMAIS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA	ATIVIDADES DE APOIO À PECUÁRIA
975fc796-0020-4ee9-af68-961314e3567f	0162802	SERVIÇO DE TOSQUIAMENTO DE OVINOS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA	ATIVIDADES DE APOIO À PECUÁRIA
bc3049c3-5ecd-4438-acbe-8dc0a398d4ec	0162803	SERVIÇO DE MANEJO DE ANIMAIS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA	ATIVIDADES DE APOIO À PECUÁRIA
b6a79844-578c-4de6-8b9d-6754c964caa6	0162899	ATIVIDADES DE APOIO À PECUÁRIA NÃO ESPECIFICADAS ANTERIORMENTE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA	ATIVIDADES DE APOIO À PECUÁRIA
a227a630-e890-45ad-bb41-2e8a08a3e802	0163600	ATIVIDADES DE PÓS COLHEITA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA	ATIVIDADES DE PÓS-COLHEITA
62c66453-34d2-426f-9e3a-be16c246a054	0170900	CAÇA E SERVIÇOS RELACIONADOS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	CAÇA E SERVIÇOS RELACIONADOS	CAÇA E SERVIÇOS RELACIONADOS
06b44f90-6f5a-49d9-a06d-14248c9536d3	0210101	CULTIVO DE EUCALIPTO	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
d378a471-36ad-4885-806d-395f2b6f8fad	0210102	CULTIVO DE ACÁCIA NEGRA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
0b87660e-a3ba-426e-b473-074ce8ec2eb2	0210103	CULTIVO DE PINUS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
70de1c87-25a8-4441-a9f6-600c1d264695	0210104	CULTIVO DE TECA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
92ed9b64-cf36-42c1-9c1c-58a268006217	0210105	CULTIVO DE ESPÉCIES MADEIREIRAS, EXCETO EUCALIPTO, ACÁCIA NEGRA, PINUS E TECA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
c6bf6a86-163a-4a42-b63a-c3408361c675	0210106	CULTIVO DE MUDAS EM VIVEIROS FLORESTAIS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
8c31f7f9-c0e1-41ef-8e1f-bb4835603477	0210107	EXTRAÇÃO DE MADEIRA EM FLORESTAS PLANTADAS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
7fa40058-5f98-4248-aef0-adee27a1a8da	0210108	PRODUÇÃO DE CARVÃO VEGETAL - FLORESTAS PLANTADAS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
6299dd03-30b2-4734-b664-45f759afe213	0210109	PRODUÇÃO DE CASCA DE ACÁCIA NEGRA - FLORESTAS PLANTADAS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
153028c9-899d-4b4d-b8c5-8e42889bdcd9	0210199	PRODUÇÃO DE PRODUTOS NÃO MADEIREIROS NÃO ESPECIFICADOS ANTERIORMENTE EM FLORESTAS PLANTADAS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
9d73e59f-524e-4837-a271-8463de2fa08e	0220901	EXTRAÇÃO DE MADEIRA EM FLORESTAS NATIVAS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS
46879f36-81b3-43ef-9da4-5eb975f360ed	0220902	PRODUÇÃO DE CARVÃO VEGETAL - FLORESTAS NATIVAS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS
b0854f5b-3d23-47e5-9a40-db90bcb36e2f	0220903	COLETA DE CASTANHA DO PARÁ EM FLORESTAS NATIVAS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS
0a879164-dbb9-4e7b-a1ea-32c9aaef1757	0220904	COLETA DE LÁTEX EM FLORESTAS NATIVAS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS
fd3a7afe-3d35-404d-b287-3ea7bf610378	0220905	COLETA DE PALMITO EM FLORESTAS NATIVAS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS
7fdaf6f2-7418-43f9-9b1a-295c8b29c5df	0220906	CONSERVAÇÃO DE FLORESTAS NATIVAS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS
7746774c-b9e0-4ec8-9101-24235fa96bb0	0220999	COLETA DE PRODUTOS NÃO MADEIREIROS NÃO ESPECIFICADOS ANTERIORMENTE EM FLORESTAS NATIVAS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS
f32b24eb-bd56-4734-ae9e-8a55de7dd637	0230600	ATIVIDADES DE APOIO À PRODUÇÃO FLORESTAL	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	ATIVIDADES DE APOIO À PRODUÇÃO FLORESTAL	ATIVIDADES DE APOIO À PRODUÇÃO FLORESTAL
3a26283f-2c37-409b-ad8d-763e22e1712c	0311601	PESCA DE PEIXES EM ÁGUA SALGADA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	PESCA	PESCA EM ÁGUA SALGADA
a14f0727-e529-4717-b6ba-2fa6d5fed077	0311602	PESCA DE CRUSTÁCEOS E MOLUSCOS EM ÁGUA SALGADA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	PESCA	PESCA EM ÁGUA SALGADA
918ffed7-cb14-4e2c-8996-c2e903c5d7f2	0311603	COLETA DE OUTROS PRODUTOS MARINHOS	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	PESCA	PESCA EM ÁGUA SALGADA
50068996-f3d1-46b9-b2e7-20cc66803e3b	0311604	ATIVIDADES DE APOIO À PESCA EM ÁGUA SALGADA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	PESCA	PESCA EM ÁGUA SALGADA
d52bfee1-6297-4b8c-bd41-ba7f69d73fd0	0312401	PESCA DE PEIXES EM ÁGUA DOCE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	PESCA	PESCA EM ÁGUA DOCE
0ea00ec3-4d04-4553-ba3c-e0ffa90deffb	0312402	PESCA DE CRUSTÁCEOS E MOLUSCOS EM ÁGUA DOCE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	PESCA	PESCA EM ÁGUA DOCE
7d4c77ad-d16c-4e44-b37a-4d6e00acf916	0312403	COLETA DE OUTROS PRODUTOS AQUÁTICOS DE ÁGUA DOCE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	PESCA	PESCA EM ÁGUA DOCE
1f68d90c-fa7d-4519-b892-1fa6ffe5ffd5	0312404	ATIVIDADES DE APOIO À PESCA EM ÁGUA DOCE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	PESCA	PESCA EM ÁGUA DOCE
aad4c683-b8f9-4528-9cd8-7edeb9d84bd4	0321301	CRIAÇÃO DE PEIXES EM ÁGUA SALGADA E SALOBRA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA SALGADA E SALOBRA
b5605218-f6b6-4049-83c7-bcb443a56688	0321302	CRIAÇÃO DE CAMARÕES EM ÁGUA SALGADA E SALOBRA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA SALGADA E SALOBRA
037760ee-ed35-4fb7-bcfb-d7b2b29aff0f	0321303	CRIAÇÃO DE OSTRAS E MEXILHÕES EM ÁGUA SALGADA E SALOBRA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA SALGADA E SALOBRA
69831462-795b-4ecc-8fda-4567d6c7bf47	0321304	CRIAÇÃO DE PEIXES ORNAMENTAIS EM ÁGUA SALGADA E SALOBRA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA SALGADA E SALOBRA
5369203f-c15b-4293-91ad-70708449a0b4	0321305	ATIVIDADES DE APOIO À AQUICULTURA EM ÁGUA SALGADA E SALOBRA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA SALGADA E SALOBRA
e0cafbbd-d8af-4d2f-8645-d512d1a98bac	0321399	CULTIVOS E SEMICULTIVOS DA AQUICULTURA EM ÁGUA SALGADA E SALOBRA NÃO ESPECIFICADOS ANTERIORMENTE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA SALGADA E SALOBRA
e8c8b7d4-ed6b-4e89-bfe8-a774f3651b1e	0322101	CRIAÇÃO DE PEIXES EM ÁGUA DOCE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA DOCE
c9915140-a72f-4469-bdf6-631f83e38ac9	0322102	CRIAÇÃO DE CAMARÕES EM ÁGUA DOCE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA DOCE
32fa88ac-2f16-4859-baa9-4dd6b273bf6f	0322103	CRIAÇÃO DE OSTRAS E MEXILHÕES EM ÁGUA DOCE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA DOCE
f91f7c1c-053d-4b33-8a7a-15dd95695e19	0322104	CRIAÇÃO DE PEIXES ORNAMENTAIS EM ÁGUA DOCE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA DOCE
7c694627-bc7f-459d-825a-0db6a36870f1	0322105	RANICULTURA	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA DOCE
a282a190-bdb9-4378-b911-7746e17e71c7	0322106	CRIAÇÃO DE JACARÉ	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA DOCE
fae2c342-b56c-4a7b-8570-4e3047df5abe	0322107	ATIVIDADES DE APOIO À AQUICULTURA EM ÁGUA DOCE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA DOCE
05b93a4e-a75b-44c2-8783-e51a22c8a967	0322199	CULTIVOS E SEMICULTIVOS DA AQUICULTURA EM ÁGUA DOCE NÃO ESPECIFICADOS ANTERIORMENTE	t	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA DOCE
22c3fc47-c09f-48ea-ac8d-2d163dd6525a	0500301	EXTRAÇÃO DE CARVÃO MINERAL	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE CARVÃO MINERAL	EXTRAÇÃO DE CARVÃO MINERAL	EXTRAÇÃO DE CARVÃO MINERAL
ea3378f2-7dce-482c-9fb5-9e4cb3fff328	0500302	BENEFICIAMENTO DE CARVÃO MINERAL	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE CARVÃO MINERAL	EXTRAÇÃO DE CARVÃO MINERAL	EXTRAÇÃO DE CARVÃO MINERAL
b4bc4ff8-f8e8-424b-9aa0-8e6deb5c45fd	0600001	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL
90734fc5-bafe-40e7-bf5b-e5ca855ef04a	0600002	EXTRAÇÃO E BENEFICIAMENTO DE XISTO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL
fa6f331c-12d2-47f1-93da-5c33c6a087b1	0600003	EXTRAÇÃO E BENEFICIAMENTO DE AREIAS BETUMINOSAS	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL
77cdaf51-00fe-4a4c-8d74-aeabcdf0b3a3	0710301	EXTRAÇÃO DE MINÉRIO DE FERRO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINÉRIO DE FERRO	EXTRAÇÃO DE MINÉRIO DE FERRO
74dd622d-d21c-4b8f-9146-06ad86168ff3	0710302	PELOTIZAÇÃO, SINTERIZAÇÃO E OUTROS BENEFICIAMENTOS DE MINÉRIO DE FERRO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINÉRIO DE FERRO	EXTRAÇÃO DE MINÉRIO DE FERRO
e5f3d117-404e-4fa8-ba21-4f36bad6f509	0721901	EXTRAÇÃO DE MINÉRIO DE ALUMÍNIO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINÉRIO DE ALUMÍNIO
39982e22-09b9-499b-b3bb-a908d69e222a	0721902	BENEFICIAMENTO DE MINÉRIO DE ALUMÍNIO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINÉRIO DE ALUMÍNIO
4065cda0-3f01-4727-b19a-9eee5d07723f	0722701	EXTRAÇÃO DE MINÉRIO DE ESTANHO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINÉRIO DE ESTANHO
75d869ca-8b72-4699-81a9-ce4ee1519b65	0722702	BENEFICIAMENTO DE MINÉRIO DE ESTANHO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINÉRIO DE ESTANHO
47f8f7ad-3175-4e37-b2c6-008ffcc000d7	0723501	EXTRAÇÃO DE MINÉRIO DE MANGANÊS	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINÉRIO DE MANGANÊS
02713386-96a3-45f6-bfaa-b926f57f3225	0723502	BENEFICIAMENTO DE MINÉRIO DE MANGANÊS	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINÉRIO DE MANGANÊS
e442167e-86f5-4439-a832-aa2da87342ed	0724301	EXTRAÇÃO DE MINÉRIO DE METAIS PRECIOSOS	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINÉRIO DE METAIS PRECIOSOS
577c0abd-72a3-47f2-bc1a-921d85db3eec	0724302	BENEFICIAMENTO DE MINÉRIO DE METAIS PRECIOSOS	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINÉRIO DE METAIS PRECIOSOS
f6dfc15f-67e7-42db-940a-b97edba1d448	0725100	EXTRAÇÃO DE MINERAIS RADIOATIVOS	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINERAIS RADIOATIVOS
ef9e98c4-fcac-4d69-a1db-f4f3453efa6d	0729401	EXTRAÇÃO DE MINÉRIOS DE NIÓBIO E TITÂNIO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS NÃO ESPECIFICADOS ANTERIORMENTE
9f3e7e89-99ca-415b-8362-dfb8f28302b0	0729402	EXTRAÇÃO DE MINÉRIO DE TUNGSTÊNIO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS NÃO ESPECIFICADOS ANTERIORMENTE
7d7441e6-90c6-475f-9408-05257d01730c	0729403	EXTRAÇÃO DE MINÉRIO DE NÍQUEL	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS NÃO ESPECIFICADOS ANTERIORMENTE
2bbb0167-835d-4cee-aba6-b0b7c19e1e86	0729404	EXTRAÇÃO DE MINÉRIOS DE COBRE, CHUMBO, ZINCO E OUTROS MINERAIS METÁLICOS NÃO FERROSOS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS NÃO ESPECIFICADOS ANTERIORMENTE
71627e5f-85b3-457d-971b-1f8244b39f72	0729405	BENEFICIAMENTO DE MINÉRIOS DE COBRE, CHUMBO, ZINCO E OUTROS MINERAIS METÁLICOS NÃO FERROSOS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS NÃO ESPECIFICADOS ANTERIORMENTE
11db3ffd-d0b9-4474-9cf6-212df9b0c6f9	0810001	EXTRAÇÃO DE ARDÓSIA E BENEFICIAMENTO ASSOCIADO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
955eae09-1457-4b99-85be-8e96d17f9257	0810002	EXTRAÇÃO DE GRANITO E BENEFICIAMENTO ASSOCIADO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
861c2f64-7c27-4ef3-9991-c474f7bd874a	0810003	EXTRAÇÃO DE MÁRMORE E BENEFICIAMENTO ASSOCIADO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
9add1511-8a53-40f2-8dae-80ef04bf891c	0810004	EXTRAÇÃO DE CALCÁRIO E DOLOMITA E BENEFICIAMENTO ASSOCIADO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
5af8c183-1115-4ae2-bee0-202e13a5e652	0810005	EXTRAÇÃO DE GESSO E CAULIM	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
8e3987b3-fea5-47fd-8511-a93d8935fff7	0810006	EXTRAÇÃO DE AREIA, CASCALHO OU PEDREGULHO E BENEFICIAMENTO ASSOCIADO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
3f13ef95-8eca-4699-a20d-1ff433cab669	0810007	EXTRAÇÃO DE ARGILA E BENEFICIAMENTO ASSOCIADO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
863d88dc-5f95-4372-b13c-d0318313f7a5	0810008	EXTRAÇÃO DE SAIBRO E BENEFICIAMENTO ASSOCIADO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
e745d74a-2891-48ea-96aa-49d45f255ccc	0810009	EXTRAÇÃO DE BASALTO E BENEFICIAMENTO ASSOCIADO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
eaa2a921-c65a-4168-a2de-014fd133c3e2	0810010	BENEFICIAMENTO DE GESSO E CAULIM ASSOCIADO À EXTRAÇÃO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
e1983ee4-e466-4aaa-9f3f-79d533fcef65	0810099	EXTRAÇÃO E BRITAMENTO DE PEDRAS E OUTROS MATERIAIS PARA CONSTRUÇÃO E BENEFICIAMENTO ASSOCIADO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
bcbefa3c-eba1-4fad-a961-552f26b92e3e	0891600	EXTRAÇÃO DE MINERAIS PARA FABRICAÇÃO DE ADUBOS, FERTILIZANTES E OUTROS PRODUTOS QUÍMICOS	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE MINERAIS PARA FABRICAÇÃO DE ADUBOS, FERTILIZANTES E OUTROS PRODUTOS QUÍMICOS
0ab9c07d-815d-48aa-bc28-6a6f89b3a61c	0892401	EXTRAÇÃO DE SAL MARINHO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS	EXTRAÇÃO E REFINO DE SAL MARINHO E SAL-GEMA
10b519b7-de9c-4aea-a17a-30cc5f2295fe	0892402	EXTRAÇÃO DE SAL GEMA	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS	EXTRAÇÃO E REFINO DE SAL MARINHO E SAL-GEMA
91dabbd2-bdfc-4891-ba3e-944bfbdaa9ed	0892403	REFINO E OUTROS TRATAMENTOS DO SAL	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS	EXTRAÇÃO E REFINO DE SAL MARINHO E SAL-GEMA
0b38d6fd-4109-4d9d-b50f-96754a5744ef	0893200	EXTRAÇÃO DE GEMAS (PEDRAS PRECIOSAS E SEMIPRECIOSAS)	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE GEMAS (PEDRAS PRECIOSAS E SEMIPRECIOSAS)
55c915fd-d715-4f3e-b299-49d4b192ac8f	0899101	EXTRAÇÃO DE GRAFITA	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE
40e7d959-3c23-45f1-9d03-91c9f03c418a	0899102	EXTRAÇÃO DE QUARTZO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE
8b41b064-c93c-477d-a3d6-e055442bedf3	0899103	EXTRAÇÃO DE AMIANTO	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE
18f142ce-d568-4243-835f-d617098fb818	0899199	EXTRAÇÃO DE OUTROS MINERAIS NÃO METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE
c4fcfbc5-0e26-4fb8-b414-c5d0b49d8ec2	0910600	ATIVIDADES DE APOIO À EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL	t	INDÚSTRIAS EXTRATIVAS	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS	ATIVIDADES DE APOIO À EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL	ATIVIDADES DE APOIO À EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL
911f6114-9422-46b1-bf80-0a5cbc8bf46b	0990401	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINÉRIO DE FERRO	t	INDÚSTRIAS EXTRATIVAS	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS, EXCETO PETRÓLEO E GÁS NATURAL	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS, EXCETO PETRÓLEO E GÁS NATURAL
c791aec9-ea21-419e-84ca-342aad1506fa	0990402	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS METÁLICOS NÃO FERROSOS	t	INDÚSTRIAS EXTRATIVAS	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS, EXCETO PETRÓLEO E GÁS NATURAL	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS, EXCETO PETRÓLEO E GÁS NATURAL
f236f39f-7bdf-4162-8bc8-76325e41d833	0990403	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS NÃO METÁLICOS	t	INDÚSTRIAS EXTRATIVAS	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS, EXCETO PETRÓLEO E GÁS NATURAL	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS, EXCETO PETRÓLEO E GÁS NATURAL
cb27c2f7-02ea-4448-b8ba-e3c5f7880447	1011201	FRIGORÍFICO - ABATE DE BOVINOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	ABATE DE RESES, EXCETO SUÍNOS
743d61de-8229-4a78-9637-819afb8113d1	1011202	FRIGORÍFICO - ABATE DE EQUINOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	ABATE DE RESES, EXCETO SUÍNOS
30756d29-d5c5-42f1-94d6-a09aa223533f	1011203	FRIGORÍFICO - ABATE DE OVINOS E CAPRINOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	ABATE DE RESES, EXCETO SUÍNOS
0616470a-2c88-4388-a00c-255844f15451	1011204	FRIGORÍFICO - ABATE DE BUFALINOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	ABATE DE RESES, EXCETO SUÍNOS
45488106-2442-468e-85d8-6eed9fb5c98c	1011205	MATADOURO - ABATE DE RESES SOB CONTRATO - EXCETO ABATE DE SUÍNOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	ABATE DE RESES, EXCETO SUÍNOS
77164ecb-04cd-4d33-8cc0-10d522833757	1012101	ABATE DE AVES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	ABATE DE SUÍNOS, AVES E OUTROS PEQUENOS ANIMAIS
2dceff85-3282-422c-bc81-b02b4f7616f2	1012102	ABATE DE PEQUENOS ANIMAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	ABATE DE SUÍNOS, AVES E OUTROS PEQUENOS ANIMAIS
5c1ab849-758b-4705-9003-10861c33bb55	1012103	FRIGORÍFICO - ABATE DE SUÍNOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	ABATE DE SUÍNOS, AVES E OUTROS PEQUENOS ANIMAIS
2de75c7b-c84d-459b-a927-66fcc3724ed9	1012104	MATADOURO - ABATE DE SUÍNOS SOB CONTRATO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	ABATE DE SUÍNOS, AVES E OUTROS PEQUENOS ANIMAIS
6f082832-bcb7-411e-94ad-9a029d1f1707	1013901	FABRICAÇÃO DE PRODUTOS DE CARNE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	FABRICAÇÃO DE PRODUTOS DE CARNE
05c2d414-5f77-4794-97a8-4a9c9c0e84b4	1013902	PREPARAÇÃO DE SUBPRODUTOS DO ABATE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	FABRICAÇÃO DE PRODUTOS DE CARNE
add85fe4-af13-4404-8f65-5c61a534052c	1020101	PRESERVAÇÃO DE PEIXES, CRUSTÁCEOS E MOLUSCOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	PRESERVAÇÃO DO PESCADO E FABRICAÇÃO DE PRODUTOS DO PESCADO	PRESERVAÇÃO DO PESCADO E FABRICAÇÃO DE PRODUTOS DO PESCADO
4835ee86-843d-4cd4-836d-a128d22865ee	1020102	FABRICAÇÃO DE CONSERVAS DE PEIXES, CRUSTÁCEOS E MOLUSCOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	PRESERVAÇÃO DO PESCADO E FABRICAÇÃO DE PRODUTOS DO PESCADO	PRESERVAÇÃO DO PESCADO E FABRICAÇÃO DE PRODUTOS DO PESCADO
1cfc6ed8-ca14-4647-9928-7d9a64182852	1031700	FABRICAÇÃO DE CONSERVAS DE FRUTAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE CONSERVAS DE FRUTAS, LEGUMES E OUTROS VEGETAIS	FABRICAÇÃO DE CONSERVAS DE FRUTAS
c851998a-3f70-4796-aab7-6a250b7c28e0	1032501	FABRICAÇÃO DE CONSERVAS DE PALMITO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE CONSERVAS DE FRUTAS, LEGUMES E OUTROS VEGETAIS	FABRICAÇÃO DE CONSERVAS DE LEGUMES E OUTROS VEGETAIS
f5f5a0cc-1bc4-4826-8499-6c8dd809d7ec	1032599	FABRICAÇÃO DE CONSERVAS DE LEGUMES E OUTROS VEGETAIS, EXCETO PALMITO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE CONSERVAS DE FRUTAS, LEGUMES E OUTROS VEGETAIS	FABRICAÇÃO DE CONSERVAS DE LEGUMES E OUTROS VEGETAIS
4abf26e1-6aab-4212-9b26-f82f69923898	1033301	FABRICAÇÃO DE SUCOS CONCENTRADOS DE FRUTAS, HORTALIÇAS E LEGUMES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE CONSERVAS DE FRUTAS, LEGUMES E OUTROS VEGETAIS	FABRICAÇÃO DE SUCOS DE FRUTAS, HORTALIÇAS E LEGUMES
4a893129-c73e-4a35-a60d-438d76f182d4	1033302	FABRICAÇÃO DE SUCOS DE FRUTAS, HORTALIÇAS E LEGUMES, EXCETO CONCENTRADOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE CONSERVAS DE FRUTAS, LEGUMES E OUTROS VEGETAIS	FABRICAÇÃO DE SUCOS DE FRUTAS, HORTALIÇAS E LEGUMES
b09ed80d-9ff5-4ef4-bfce-31d8385af13a	1041400	FABRICAÇÃO DE ÓLEOS VEGETAIS EM BRUTO, EXCETO ÓLEO DE MILHO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE ÓLEOS E GORDURAS VEGETAIS E ANIMAIS	FABRICAÇÃO DE ÓLEOS VEGETAIS EM BRUTO, EXCETO ÓLEO DE MILHO
725f3c29-375a-4efb-b380-7264d1509c2d	1042200	FABRICAÇÃO DE ÓLEOS VEGETAIS REFINADOS, EXCETO ÓLEO DE MILHO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE ÓLEOS E GORDURAS VEGETAIS E ANIMAIS	FABRICAÇÃO DE ÓLEOS VEGETAIS REFINADOS, EXCETO ÓLEO DE MILHO
2d29b065-90ea-493f-ba2a-da2ef84922b1	1043100	FABRICAÇÃO DE MARGARINA E OUTRAS GORDURAS VEGETAIS E DE ÓLEOS NÃO COMESTÍVEIS DE ANIMAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE ÓLEOS E GORDURAS VEGETAIS E ANIMAIS	FABRICAÇÃO DE MARGARINA E OUTRAS GORDURAS VEGETAIS E DE ÓLEOS NÃO-COMESTÍVEIS DE ANIMAIS
06451569-a79d-4c42-a8c3-9bc033585a19	1051100	PREPARAÇÃO DO LEITE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	LATICÍNIOS	PREPARAÇÃO DO LEITE
ed488fac-4eed-4cbe-b27d-0c64899f059e	1052000	FABRICAÇÃO DE LATICÍNIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	LATICÍNIOS	FABRICAÇÃO DE LATICÍNIOS
075d735f-57ed-41f7-883f-7c40852328b4	1053800	FABRICAÇÃO DE SORVETES E OUTROS GELADOS COMESTÍVEIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	LATICÍNIOS	FABRICAÇÃO DE SORVETES E OUTROS GELADOS COMESTÍVEIS
1f2c5259-9ec9-4ccd-a2d6-9b978910a00b	1061901	BENEFICIAMENTO DE ARROZ	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	BENEFICIAMENTO DE ARROZ E FABRICAÇÃO DE PRODUTOS DO ARROZ
f2e1987e-7855-4ebd-8da4-0b6a9913c542	1061902	FABRICAÇÃO DE PRODUTOS DO ARROZ	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	BENEFICIAMENTO DE ARROZ E FABRICAÇÃO DE PRODUTOS DO ARROZ
176974d3-9f82-4f96-b993-e85ec7b89211	1062700	MOAGEM DE TRIGO E FABRICAÇÃO DE DERIVADOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	MOAGEM DE TRIGO E FABRICAÇÃO DE DERIVADOS
f0b25b27-c767-430a-9dce-3c9403c5c049	1063500	FABRICAÇÃO DE FARINHA DE MANDIOCA E DERIVADOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	FABRICAÇÃO DE FARINHA DE MANDIOCA E DERIVADOS
d5a3f20d-b80b-41bc-9000-0dc0a683f327	1064300	FABRICAÇÃO DE FARINHA DE MILHO E DERIVADOS, EXCETO ÓLEOS DE MILHO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	FABRICAÇÃO DE FARINHA DE MILHO E DERIVADOS, EXCETO ÓLEOS DE MILHO
40d16d28-5d4c-48df-ae41-7d04cd5f2184	1065101	FABRICAÇÃO DE AMIDOS E FÉCULAS DE VEGETAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	FABRICAÇÃO DE AMIDOS E FÉCULAS DE VEGETAIS E DE ÓLEOS DE MILHO
9394e407-a983-4b89-8685-afbb7c9b8ee4	1065102	FABRICAÇÃO DE ÓLEO DE MILHO EM BRUTO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	FABRICAÇÃO DE AMIDOS E FÉCULAS DE VEGETAIS E DE ÓLEOS DE MILHO
10ecdd75-0834-457f-b25e-c5ebe39cf664	1065103	FABRICAÇÃO DE ÓLEO DE MILHO REFINADO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	FABRICAÇÃO DE AMIDOS E FÉCULAS DE VEGETAIS E DE ÓLEOS DE MILHO
11f32eb2-cc00-4568-afce-b848c3ba6ae7	1066000	FABRICAÇÃO DE ALIMENTOS PARA ANIMAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	FABRICAÇÃO DE ALIMENTOS PARA ANIMAIS
a19ea748-f6f0-4eb7-9893-60ddb40e2a2e	1069400	MOAGEM E FABRICAÇÃO DE PRODUTOS DE ORIGEM VEGETAL NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	MOAGEM E FABRICAÇÃO DE PRODUTOS DE ORIGEM VEGETAL NÃO ESPECIFICADOS ANTERIORMENTE
8ab9b13c-25bc-4907-b01d-2ab8bebf91e2	1071600	FABRICAÇÃO DE AÇÚCAR EM BRUTO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO E REFINO DE AÇÚCAR	FABRICAÇÃO DE AÇÚCAR EM BRUTO
f6b06fd7-55f6-4a36-b978-07940b763666	1072401	FABRICAÇÃO DE AÇÚCAR DE CANA REFINADO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO E REFINO DE AÇÚCAR	FABRICAÇÃO DE AÇÚCAR REFINADO
b0217333-d311-4964-aed2-f1905e762152	1072402	FABRICAÇÃO DE AÇÚCAR DE CEREAIS (DEXTROSE) E DE BETERRABA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO E REFINO DE AÇÚCAR	FABRICAÇÃO DE AÇÚCAR REFINADO
5b406f90-8a82-4901-9e3c-7e5ffe5bf74d	1081301	BENEFICIAMENTO DE CAFÉ	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	TORREFAÇÃO E MOAGEM DE CAFÉ	TORREFAÇÃO E MOAGEM DE CAFÉ
e99a3d2b-ef71-49bf-ae01-24375ce8fa98	1081302	TORREFAÇÃO E MOAGEM DE CAFÉ	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	TORREFAÇÃO E MOAGEM DE CAFÉ	TORREFAÇÃO E MOAGEM DE CAFÉ
c6385097-440b-4c54-9855-66a9781fd854	1082100	FABRICAÇÃO DE PRODUTOS À BASE DE CAFÉ	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	TORREFAÇÃO E MOAGEM DE CAFÉ	FABRICAÇÃO DE PRODUTOS À BASE DE CAFÉ
9f1b8cca-e334-41e5-b22b-1320ddd4cebd	1091101	FABRICAÇÃO DE PRODUTOS DE PANIFICAÇÃO INDUSTRIAL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS DE PANIFICAÇÃO
32390018-6c9f-4ee3-b372-d6e41f10e5d7	1091102	FABRICAÇÃO DE PRODUTOS DE PADARIA E CONFEITARIA COM PREDOMINÂNCIA  DE PRODUÇÃO PRÓPRIA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS DE PANIFICAÇÃO
0d3d090d-e11b-4fa7-9865-a9c696006895	1092900	FABRICAÇÃO DE BISCOITOS E BOLACHAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE BISCOITOS E BOLACHAS
ba0e2443-8da8-4d8a-976b-9fdbdc3ea93b	1093701	FABRICAÇÃO DE PRODUTOS DERIVADOS DO CACAU E DE CHOCOLATES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS DERIVADOS DO CACAU, DE CHOCOLATES E CONFEITOS
80699f09-0bf2-4b71-9220-72a7f9f74efd	1093702	FABRICAÇÃO DE FRUTAS CRISTALIZADAS, BALAS E SEMELHANTES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS DERIVADOS DO CACAU, DE CHOCOLATES E CONFEITOS
66a831ba-ff69-4a7d-869c-af53b45095a1	1094500	FABRICAÇÃO DE MASSAS ALIMENTÍCIAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE MASSAS ALIMENTÍCIAS
7ba413f6-84e4-4014-be2d-8ada81c1f60d	1095300	FABRICAÇÃO DE ESPECIARIAS, MOLHOS, TEMPEROS E CONDIMENTOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE ESPECIARIAS, MOLHOS, TEMPEROS E CONDIMENTOS
dee055b1-3b6b-4569-bc5b-b6127186a807	1096100	FABRICAÇÃO DE ALIMENTOS E PRATOS PRONTOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE ALIMENTOS E PRATOS PRONTOS
419a9e19-59a5-4b6c-bfd6-eaa7809caa7e	1099601	FABRICAÇÃO DE VINAGRES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
68f940b8-7ecd-42a2-9a05-9a8b12ee28cd	1099602	FABRICAÇÃO DE PÓS ALIMENTÍCIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
b4769961-927d-4897-bce6-bfa93a71254c	1099603	FABRICAÇÃO DE FERMENTOS E LEVEDURAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
78e95bb2-b7f5-4d85-b2ad-be63b1b3ef18	1099604	FABRICAÇÃO DE GELO COMUM	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
84f88a93-bb1f-46bc-b6b0-db2e672a73a2	1099605	FABRICAÇÃO DE PRODUTOS PARA INFUSÃO (CHÁ, MATE, ETC.)	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
68fde72f-bdc0-4ff7-b45f-c8c9dc30da4a	1099606	FABRICAÇÃO DE ADOÇANTES NATURAIS E ARTIFICIAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
f1fcac23-abfd-44ec-adfd-1afe2e6561c5	1099607	FABRICAÇÃO DE ALIMENTOS DIETÉTICOS E COMPLEMENTOS ALIMENTARES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
881248e6-74bd-4481-ab97-cf64bc23cbf6	1099699	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
b201e18c-cca7-4dfb-9f70-41f8e9a76a83	1111901	FABRICAÇÃO DE AGUARDENTE DE CANA DE AÇÚCAR	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS ALCOÓLICAS	FABRICAÇÃO DE AGUARDENTES E OUTRAS BEBIDAS DESTILADAS
569cd973-af77-4e73-8e92-7ce08896d965	1111902	FABRICAÇÃO DE OUTRAS AGUARDENTES E BEBIDAS DESTILADAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS ALCOÓLICAS	FABRICAÇÃO DE AGUARDENTES E OUTRAS BEBIDAS DESTILADAS
3a24017a-f947-43f4-b169-51d4cbd5b0a0	1112700	FABRICAÇÃO DE VINHO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS ALCOÓLICAS	FABRICAÇÃO DE VINHO
614c98a6-bbe2-4b9a-bc37-b962ca48f0e9	1113501	FABRICAÇÃO DE MALTE, INCLUSIVE MALTE UÍSQUE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS ALCOÓLICAS	FABRICAÇÃO DE MALTE, CERVEJAS E CHOPES
a38a6fb9-d745-49af-8083-8ae5022e5838	1113502	FABRICAÇÃO DE CERVEJAS E CHOPES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS ALCOÓLICAS	FABRICAÇÃO DE MALTE, CERVEJAS E CHOPES
1005e64e-19a8-4610-b4a2-38bb120bbd26	1121600	FABRICAÇÃO DE ÁGUAS ENVASADAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS NÃO-ALCOÓLICAS	FABRICAÇÃO DE ÁGUAS ENVASADAS
1a9c62a4-ba19-474c-8862-980187485718	1122401	FABRICAÇÃO DE REFRIGERANTES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS NÃO-ALCOÓLICAS	FABRICAÇÃO DE REFRIGERANTES E DE OUTRAS BEBIDAS NÃO-ALCOÓLICAS
e5cd02ae-cc7f-4c3c-8cb9-3c3bba7ca56a	1122402	FABRICAÇÃO DE CHÁ MATE E OUTROS CHÁS PRONTOS PARA CONSUMO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS NÃO-ALCOÓLICAS	FABRICAÇÃO DE REFRIGERANTES E DE OUTRAS BEBIDAS NÃO-ALCOÓLICAS
d3a66546-5024-497d-84db-8fc9b8a5efc7	1122403	FABRICAÇÃO DE REFRESCOS, XAROPES E PÓS PARA REFRESCOS, EXCETO REFRESCOS DE FRUTAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS NÃO-ALCOÓLICAS	FABRICAÇÃO DE REFRIGERANTES E DE OUTRAS BEBIDAS NÃO-ALCOÓLICAS
9d35eb88-664b-4f43-b01f-c07d027a2752	1122404	FABRICAÇÃO DE BEBIDAS ISOTÔNICAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS NÃO-ALCOÓLICAS	FABRICAÇÃO DE REFRIGERANTES E DE OUTRAS BEBIDAS NÃO-ALCOÓLICAS
437bb503-fa52-49e3-90d9-db28b345f92d	1122499	FABRICAÇÃO DE OUTRAS BEBIDAS NÃO ALCOÓLICAS NÃO ESPECIFICADAS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS NÃO-ALCOÓLICAS	FABRICAÇÃO DE REFRIGERANTES E DE OUTRAS BEBIDAS NÃO-ALCOÓLICAS
a09f82e7-1751-44bd-965e-9419c8091800	1210700	PROCESSAMENTO INDUSTRIAL DO FUMO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DO FUMO	PROCESSAMENTO INDUSTRIAL DO FUMO	PROCESSAMENTO INDUSTRIAL DO FUMO
71e6e4d5-2e37-43fe-be16-2e2b9d70f9c5	1220401	FABRICAÇÃO DE CIGARROS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DO FUMO	FABRICAÇÃO DE PRODUTOS DO FUMO	FABRICAÇÃO DE PRODUTOS DO FUMO
41ef60fb-295f-489b-b0b1-a2adadc96f44	1220402	FABRICAÇÃO DE CIGARRILHAS E CHARUTOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DO FUMO	FABRICAÇÃO DE PRODUTOS DO FUMO	FABRICAÇÃO DE PRODUTOS DO FUMO
834677d4-d8ff-4e1b-9d3c-cea1f5f5c72d	1220403	FABRICAÇÃO DE FILTROS PARA CIGARROS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DO FUMO	FABRICAÇÃO DE PRODUTOS DO FUMO	FABRICAÇÃO DE PRODUTOS DO FUMO
205eb7eb-bc3c-4e6f-a554-40e4ad8e3cfb	1220499	FABRICAÇÃO DE OUTROS PRODUTOS DO FUMO, EXCETO CIGARROS, CIGARRILHAS E CHARUTOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DO FUMO	FABRICAÇÃO DE PRODUTOS DO FUMO	FABRICAÇÃO DE PRODUTOS DO FUMO
c4ca2cb6-8ed3-44a1-9396-0c72184fb65b	1311100	PREPARAÇÃO E FIAÇÃO DE FIBRAS DE ALGODÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	PREPARAÇÃO E FIAÇÃO DE FIBRAS TÊXTEIS	PREPARAÇÃO E FIAÇÃO DE FIBRAS DE ALGODÃO
c8f6a142-6809-4ab4-9a5b-a4321efaebda	1312000	PREPARAÇÃO E FIAÇÃO DE FIBRAS TÊXTEIS NATURAIS, EXCETO ALGODÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	PREPARAÇÃO E FIAÇÃO DE FIBRAS TÊXTEIS	PREPARAÇÃO E FIAÇÃO DE FIBRAS TÊXTEIS NATURAIS, EXCETO ALGODÃO
32a54294-6aaa-4478-b9d4-e43835bed003	1313800	FIAÇÃO DE FIBRAS ARTIFICIAIS E SINTÉTICAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	PREPARAÇÃO E FIAÇÃO DE FIBRAS TÊXTEIS	FIAÇÃO DE FIBRAS ARTIFICIAIS E SINTÉTICAS
97ad7f20-7e59-434f-a8b5-a0a054b71e47	1314600	FABRICAÇÃO DE LINHAS PARA COSTURAR E BORDAR	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	PREPARAÇÃO E FIAÇÃO DE FIBRAS TÊXTEIS	FABRICAÇÃO DE LINHAS PARA COSTURAR E BORDAR
e232e2b1-b39b-4ff3-bdf5-26b1a2b39e50	1321900	TECELAGEM DE FIOS DE ALGODÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	TECELAGEM, EXCETO MALHA	TECELAGEM DE FIOS DE ALGODÃO
e31c829f-dcb3-48fa-9a35-65fba2cf73b7	1322700	TECELAGEM DE FIOS DE FIBRAS TÊXTEIS NATURAIS, EXCETO ALGODÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	TECELAGEM, EXCETO MALHA	TECELAGEM DE FIOS DE FIBRAS TÊXTEIS NATURAIS, EXCETO ALGODÃO
0a430cd7-51e3-4aec-968f-2dca69a538cf	1323500	TECELAGEM DE FIOS DE FIBRAS ARTIFICIAIS E SINTÉTICAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	TECELAGEM, EXCETO MALHA	TECELAGEM DE FIOS DE FIBRAS ARTIFICIAIS E SINTÉTICAS
495da739-c9a3-404d-8419-fbd2682b5a7d	1330800	FABRICAÇÃO DE TECIDOS DE MALHA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	FABRICAÇÃO DE TECIDOS DE MALHA	FABRICAÇÃO DE TECIDOS DE MALHA
9526fe42-0349-4b7d-ab24-3767e322a9f2	1340501	ESTAMPARIA E TEXTURIZAÇÃO EM FIOS, TECIDOS, ARTEFATOS TÊXTEIS E PEÇAS DO VESTUÁRIO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	ACABAMENTOS EM FIOS, TECIDOS E ARTEFATOS TÊXTEIS	ACABAMENTOS EM FIOS, TECIDOS E ARTEFATOS TÊXTEIS
61f02b12-f667-4182-8d02-e1fb055bf993	1340502	ALVEJAMENTO, TINGIMENTO E TORÇÃO EM FIOS, TECIDOS, ARTEFATOS TÊXTEIS E PEÇAS DO VESTUÁRIO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	ACABAMENTOS EM FIOS, TECIDOS E ARTEFATOS TÊXTEIS	ACABAMENTOS EM FIOS, TECIDOS E ARTEFATOS TÊXTEIS
9b508220-2a22-4d31-b46e-491dff5dff76	1340599	OUTROS SERVIÇOS DE ACABAMENTO EM FIOS, TECIDOS, ARTEFATOS TÊXTEIS E PEÇAS DO VESTUÁRIO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	ACABAMENTOS EM FIOS, TECIDOS E ARTEFATOS TÊXTEIS	ACABAMENTOS EM FIOS, TECIDOS E ARTEFATOS TÊXTEIS
5452bb2c-a66e-4ac2-bfbb-c3edb75f019f	1351100	FABRICAÇÃO DE ARTEFATOS TÊXTEIS PARA USO DOMÉSTICO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	FABRICAÇÃO DE ARTEFATOS TÊXTEIS, EXCETO VESTUÁRIO	FABRICAÇÃO DE ARTEFATOS TÊXTEIS PARA USO DOMÉSTICO
29123e16-9185-4abc-aed2-5cf96bf539c1	1352900	FABRICAÇÃO DE ARTEFATOS DE TAPEÇARIA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	FABRICAÇÃO DE ARTEFATOS TÊXTEIS, EXCETO VESTUÁRIO	FABRICAÇÃO DE ARTEFATOS DE TAPEÇARIA
5904ddd5-24ca-48d5-8af4-597db7eccb4c	1353700	FABRICAÇÃO DE ARTEFATOS DE CORDOARIA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	FABRICAÇÃO DE ARTEFATOS TÊXTEIS, EXCETO VESTUÁRIO	FABRICAÇÃO DE ARTEFATOS DE CORDOARIA
a80a7d42-2719-4141-bb9e-b6ccb3e9c4ba	1354500	FABRICAÇÃO DE TECIDOS ESPECIAIS, INCLUSIVE ARTEFATOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	FABRICAÇÃO DE ARTEFATOS TÊXTEIS, EXCETO VESTUÁRIO	FABRICAÇÃO DE TECIDOS ESPECIAIS, INCLUSIVE ARTEFATOS
c0ae0eec-80cb-47e7-9b75-49d27724570d	1359600	FABRICAÇÃO DE OUTROS PRODUTOS TÊXTEIS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	FABRICAÇÃO DE ARTEFATOS TÊXTEIS, EXCETO VESTUÁRIO	FABRICAÇÃO DE OUTROS PRODUTOS TÊXTEIS NÃO ESPECIFICADOS ANTERIORMENTE
7b63009f-38a5-4b2d-a23f-6c5d6ab67e18	1411801	CONFECÇÃO DE ROUPAS ÍNTIMAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ROUPAS ÍNTIMAS
72b699f4-20c8-4f61-aa4e-7814cfeeff56	1411802	FACÇÃO DE ROUPAS ÍNTIMAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ROUPAS ÍNTIMAS
9715183f-4b50-43ce-b6e1-d6a7c56e0fa0	1412601	CONFECÇÃO DE PEÇAS DE VESTUÁRIO, EXCETO ROUPAS ÍNTIMAS E AS CONFECCIONADAS SOB MEDIDA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE PEÇAS DE VESTUÁRIO, EXCETO ROUPAS ÍNTIMAS
93ee17c2-0721-434f-8068-1dc96c2a8161	1412602	CONFECÇÃO, SOB MEDIDA, DE PEÇAS DO VESTUÁRIO, EXCETO ROUPAS ÍNTIMAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE PEÇAS DE VESTUÁRIO, EXCETO ROUPAS ÍNTIMAS
e47356ac-0747-43e1-b934-8c75c244943a	1412603	FACÇÃO DE PEÇAS DO VESTUÁRIO, EXCETO ROUPAS ÍNTIMAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE PEÇAS DE VESTUÁRIO, EXCETO ROUPAS ÍNTIMAS
76bad2ba-d4b2-4f22-bedc-155496de6dcb	1413401	CONFECÇÃO DE ROUPAS PROFISSIONAIS, EXCETO SOB MEDIDA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ROUPAS PROFISSIONAIS
194bc328-27e7-4d32-ba72-5040d4d459e3	1413402	CONFECÇÃO, SOB MEDIDA, DE ROUPAS PROFISSIONAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ROUPAS PROFISSIONAIS
ad7c8cef-1b78-4398-8443-423b2845f0b2	1413403	FACÇÃO DE ROUPAS PROFISSIONAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ROUPAS PROFISSIONAIS
46ed0b3e-fcd5-42e6-96e6-428b8ace5340	1414200	FABRICAÇÃO DE ACESSÓRIOS DO VESTUÁRIO, EXCETO PARA SEGURANÇA E PROTEÇÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	FABRICAÇÃO DE ACESSÓRIOS DO VESTUÁRIO, EXCETO PARA SEGURANÇA E PROTEÇÃO
c441fc29-586f-4291-add9-919360951c4e	1421500	FABRICAÇÃO DE MEIAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	FABRICAÇÃO DE ARTIGOS DE MALHARIA E TRICOTAGEM	FABRICAÇÃO DE MEIAS
dc904a39-6706-420c-932e-e7a0109fa7d9	1422300	FABRICAÇÃO DE ARTIGOS DO VESTUÁRIO, PRODUZIDOS EM MALHARIAS E TRICOTAGENS, EXCETO MEIAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	FABRICAÇÃO DE ARTIGOS DE MALHARIA E TRICOTAGEM	FABRICAÇÃO DE ARTIGOS DO VESTUÁRIO, PRODUZIDOS EM MALHARIAS E TRICOTAGENS, EXCETO MEIAS
f873e77a-cb0c-46af-92bc-fa8676c217cf	1510600	CURTIMENTO E OUTRAS PREPARAÇÕES DE COURO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS	CURTIMENTO E OUTRAS PREPARAÇÕES DE COURO	CURTIMENTO E OUTRAS PREPARAÇÕES DE COURO
31b31128-fbee-4827-80c6-ab34a3caf347	1521100	FABRICAÇÃO DE ARTIGOS PARA VIAGEM, BOLSAS E SEMELHANTES DE QUALQUER MATERIAL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS	FABRICAÇÃO DE ARTIGOS PARA VIAGEM E DE ARTEFATOS DIVERSOS DE COURO	FABRICAÇÃO DE ARTIGOS PARA VIAGEM, BOLSAS E SEMELHANTES DE QUALQUER MATERIAL
3fd03fc2-a84a-43bc-9de8-a7a4f3d00e64	1529700	FABRICAÇÃO DE ARTEFATOS DE COURO NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS	FABRICAÇÃO DE ARTIGOS PARA VIAGEM E DE ARTEFATOS DIVERSOS DE COURO	FABRICAÇÃO DE ARTEFATOS DE COURO NÃO ESPECIFICADOS ANTERIORMENTE
1072345c-56dd-46ac-9c4b-415538f3481b	1531901	FABRICAÇÃO DE CALÇADOS DE COURO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS	FABRICAÇÃO DE CALÇADOS	FABRICAÇÃO DE CALÇADOS DE COURO
c4429140-8c2b-4371-926e-d804b2dcf6ad	1531902	ACABAMENTO DE CALÇADOS DE COURO SOB CONTRATO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS	FABRICAÇÃO DE CALÇADOS	FABRICAÇÃO DE CALÇADOS DE COURO
b62de29c-7e06-4df4-a25e-934f488bb344	1532700	FABRICAÇÃO DE TÊNIS DE QUALQUER MATERIAL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS	FABRICAÇÃO DE CALÇADOS	FABRICAÇÃO DE TÊNIS DE QUALQUER MATERIAL
658fbec0-f54f-44a1-bfd0-7e7ddbc8fbff	1533500	FABRICAÇÃO DE CALÇADOS DE MATERIAL SINTÉTICO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS	FABRICAÇÃO DE CALÇADOS	FABRICAÇÃO DE CALÇADOS DE MATERIAL SINTÉTICO
20c19948-3531-452d-98ad-fbb5d4db0774	1539400	FABRICAÇÃO DE CALÇADOS DE MATERIAIS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS	FABRICAÇÃO DE CALÇADOS	FABRICAÇÃO DE CALÇADOS DE MATERIAIS NÃO ESPECIFICADOS ANTERIORMENTE
64647636-f2b0-4925-87c7-f9279aa3b3a6	1540800	FABRICAÇÃO DE PARTES PARA CALÇADOS, DE QUALQUER MATERIAL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS	FABRICAÇÃO DE PARTES PARA CALÇADOS, DE QUALQUER MATERIAL	FABRICAÇÃO DE PARTES PARA CALÇADOS, DE QUALQUER MATERIAL
8b080f79-d91c-44f0-817f-b69a62dc35fa	1610203	SERRARIAS COM DESDOBRAMENTO DE MADEIRA EM BRUTO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	DESDOBRAMENTO DE MADEIRA	DESDOBRAMENTO DE MADEIRA
a0cb5330-1d04-49d2-b7fc-446e702fe8e3	1610204	SERRARIAS SEM DESDOBRAMENTO DE MADEIRA EM BRUTO - RESSERRAGEM	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	DESDOBRAMENTO DE MADEIRA	DESDOBRAMENTO DE MADEIRA
1fa3de20-192b-48a9-8f2e-f27b340785cd	1610205	SERVIÇO DE TRATAMENTO DE MADEIRA REALIZADO SOB CONTRATO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	DESDOBRAMENTO DE MADEIRA	DESDOBRAMENTO DE MADEIRA
aec5e3e3-b5c2-4841-82e8-48b4ce800a24	1621800	FABRICAÇÃO DE MADEIRA LAMINADA E DE CHAPAS DE MADEIRA COMPENSADA, PRENSADA E AGLOMERADA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	FABRICAÇÃO DE PRODUTOS DE MADEIRA, CORTIÇA E MATERIAL TRANÇADO, EXCETO MÓVEIS	FABRICAÇÃO DE MADEIRA LAMINADA E DE CHAPAS DE MADEIRA COMPENSADA, PRENSADA E AGLOMERADA
19f0c504-3111-4fbb-ba26-3a11baa7d66c	1622601	FABRICAÇÃO DE CASAS DE MADEIRA PRÉ FABRICADAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	FABRICAÇÃO DE PRODUTOS DE MADEIRA, CORTIÇA E MATERIAL TRANÇADO, EXCETO MÓVEIS	FABRICAÇÃO DE ESTRUTURAS DE MADEIRA E DE ARTIGOS DE CARPINTARIA PARA CONSTRUÇÃO
d4869c8f-bfb0-455c-823e-44df514e3201	1622602	FABRICAÇÃO DE ESQUADRIAS DE MADEIRA E DE PEÇAS DE MADEIRA PARA INSTALAÇÕES INDUSTRIAIS E COMERCIAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	FABRICAÇÃO DE PRODUTOS DE MADEIRA, CORTIÇA E MATERIAL TRANÇADO, EXCETO MÓVEIS	FABRICAÇÃO DE ESTRUTURAS DE MADEIRA E DE ARTIGOS DE CARPINTARIA PARA CONSTRUÇÃO
49f0a4a7-50f1-46cc-91b8-e4c512dde6d3	1622699	FABRICAÇÃO DE OUTROS ARTIGOS DE CARPINTARIA PARA CONSTRUÇÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	FABRICAÇÃO DE PRODUTOS DE MADEIRA, CORTIÇA E MATERIAL TRANÇADO, EXCETO MÓVEIS	FABRICAÇÃO DE ESTRUTURAS DE MADEIRA E DE ARTIGOS DE CARPINTARIA PARA CONSTRUÇÃO
4588ece0-a104-41a4-9fea-e3c373710b31	1623400	FABRICAÇÃO DE ARTEFATOS DE TANOARIA E DE EMBALAGENS DE MADEIRA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	FABRICAÇÃO DE PRODUTOS DE MADEIRA, CORTIÇA E MATERIAL TRANÇADO, EXCETO MÓVEIS	FABRICAÇÃO DE ARTEFATOS DE TANOARIA E DE EMBALAGENS DE MADEIRA
ad3e7624-8959-4848-b3ad-812ebdfe62b8	1629301	FABRICAÇÃO DE ARTEFATOS DIVERSOS DE MADEIRA, EXCETO MÓVEIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	FABRICAÇÃO DE PRODUTOS DE MADEIRA, CORTIÇA E MATERIAL TRANÇADO, EXCETO MÓVEIS	FABRICAÇÃO DE ARTEFATOS DE MADEIRA, PALHA, CORTIÇA, VIME E MATERIAL TRANÇADO NÃO ESPECIFICADOS ANTERIORMENTE, EXCETO MÓVEIS
7ee127f8-bc2d-4025-85cd-d999561b9bde	1629302	FABRICAÇÃO DE ARTEFATOS DIVERSOS DE CORTIÇA, BAMBU, PALHA, VIME E OUTROS MATERIAIS TRANÇADOS, EXCETO MÓVEIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	FABRICAÇÃO DE PRODUTOS DE MADEIRA, CORTIÇA E MATERIAL TRANÇADO, EXCETO MÓVEIS	FABRICAÇÃO DE ARTEFATOS DE MADEIRA, PALHA, CORTIÇA, VIME E MATERIAL TRANÇADO NÃO ESPECIFICADOS ANTERIORMENTE, EXCETO MÓVEIS
941e6561-d2ac-4b08-84d8-1e118ea41d28	1710900	FABRICAÇÃO DE CELULOSE E OUTRAS PASTAS PARA A FABRICAÇÃO DE PAPEL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE CELULOSE E OUTRAS PASTAS PARA A FABRICAÇÃO DE PAPEL	FABRICAÇÃO DE CELULOSE E OUTRAS PASTAS PARA A FABRICAÇÃO DE PAPEL
f8804ad0-7806-46c3-85f2-b75f491b9f25	1721400	FABRICAÇÃO DE PAPEL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE PAPEL, CARTOLINA E PAPEL-CARTÃO	FABRICAÇÃO DE PAPEL
b3833400-ad56-4ea7-9d0c-c57b09486322	1722200	FABRICAÇÃO DE CARTOLINA E PAPEL CARTÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE PAPEL, CARTOLINA E PAPEL-CARTÃO	FABRICAÇÃO DE CARTOLINA E PAPEL-CARTÃO
57c9491d-5e26-4279-9a7c-5d7436400b78	1731100	FABRICAÇÃO DE EMBALAGENS DE PAPEL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE EMBALAGENS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO	FABRICAÇÃO DE EMBALAGENS DE PAPEL
1a307387-f54a-4c51-bf72-31969e7291cd	1732000	FABRICAÇÃO DE EMBALAGENS DE CARTOLINA E PAPEL CARTÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE EMBALAGENS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO	FABRICAÇÃO DE EMBALAGENS DE CARTOLINA E PAPEL-CARTÃO
8e2cabb6-3b82-4550-afac-ce5b25749438	1733800	FABRICAÇÃO DE CHAPAS E DE EMBALAGENS DE PAPELÃO ONDULADO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE EMBALAGENS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO	FABRICAÇÃO DE CHAPAS E DE EMBALAGENS DE PAPELÃO ONDULADO
12fb4624-a18b-4202-bd07-57828e10f28b	1741901	FABRICAÇÃO DE FORMULÁRIOS CONTÍNUOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE PRODUTOS DIVERSOS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO	FABRICAÇÃO DE PRODUTOS DE PAPEL, CARTOLINA, PAPEL CARTÃO E PAPELÃO ONDULADO PARA USO COMERCIAL E DE ESCRITÓRIO
33439ec0-2972-4aaf-8b64-ff41b6f38581	1741902	FABRICAÇÃO DE PRODUTOS DE PAPEL, CARTOLINA, PAPEL CARTÃO E PAPELÃO ONDULADO PARA USO INDUSTRIAL, COMERCIAL E DE ESCRITÓRIO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE PRODUTOS DIVERSOS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO	FABRICAÇÃO DE PRODUTOS DE PAPEL, CARTOLINA, PAPEL CARTÃO E PAPELÃO ONDULADO PARA USO COMERCIAL E DE ESCRITÓRIO
abf77b44-2573-41f6-b18c-91e4f8b8d7b2	1742701	FABRICAÇÃO DE FRALDAS DESCARTÁVEIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE PRODUTOS DIVERSOS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO	FABRICAÇÃO DE PRODUTOS DE PAPEL PARA USOS DOMÉSTICO E HIGIÊNICO-SANITÁRIO
422dc3ff-d280-4b56-bae4-7f6e0da20e81	1742702	FABRICAÇÃO DE ABSORVENTES HIGIÊNICOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE PRODUTOS DIVERSOS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO	FABRICAÇÃO DE PRODUTOS DE PAPEL PARA USOS DOMÉSTICO E HIGIÊNICO-SANITÁRIO
017528e2-916a-4092-9424-5c3e868784e7	1742799	FABRICAÇÃO DE PRODUTOS DE PAPEL PARA USO DOMÉSTICO E HIGIÊNICO SANITÁRIO NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE PRODUTOS DIVERSOS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO	FABRICAÇÃO DE PRODUTOS DE PAPEL PARA USOS DOMÉSTICO E HIGIÊNICO-SANITÁRIO
56852dae-d087-4a34-ab5d-8c67917f2f34	1749400	FABRICAÇÃO DE PRODUTOS DE PASTAS CELULÓSICAS, PAPEL, CARTOLINA, PAPEL CARTÃO E PAPELÃO ONDULADO NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE PRODUTOS DIVERSOS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO	FABRICAÇÃO DE PRODUTOS DE PASTAS CELULÓSICAS, PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO NÃO ESPECIFICADOS ANTERIORMENTE
63951d34-f36c-4d8d-aab2-a95ea6f0d05a	1811301	IMPRESSÃO DE JORNAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	ATIVIDADE DE IMPRESSÃO	IMPRESSÃO DE JORNAIS, LIVROS, REVISTAS E OUTRAS PUBLICAÇÕES PERIÓDICAS
fb7a07f5-1d2a-4745-82c6-22bced353e2c	1811302	IMPRESSÃO DE LIVROS, REVISTAS E OUTRAS PUBLICAÇÕES PERIÓDICAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	ATIVIDADE DE IMPRESSÃO	IMPRESSÃO DE JORNAIS, LIVROS, REVISTAS E OUTRAS PUBLICAÇÕES PERIÓDICAS
05c4e80a-3510-48df-9977-bfc1f1ec16af	1812100	IMPRESSÃO DE MATERIAL DE SEGURANÇA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	ATIVIDADE DE IMPRESSÃO	IMPRESSÃO DE MATERIAL DE SEGURANÇA
dd1ac88a-e696-47f0-9f7e-a14f43763044	1813001	IMPRESSÃO DE MATERIAL PARA USO PUBLICITÁRIO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	ATIVIDADE DE IMPRESSÃO	IMPRESSÃO DE MATERIAIS PARA OUTROS USOS
f3e8d7d6-2017-4527-b5fc-3e7964a64e5e	1813099	IMPRESSÃO DE MATERIAL PARA OUTROS USOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	ATIVIDADE DE IMPRESSÃO	IMPRESSÃO DE MATERIAIS PARA OUTROS USOS
019cc809-8ed1-4372-870b-998276cab916	1821100	SERVIÇOS DE PRÉ IMPRESSÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	SERVIÇOS DE PRÉ-IMPRESSÃO E ACABAMENTOS GRÁFICOS	SERVIÇOS DE PRÉ-IMPRESSÃO
2f47d8f4-f636-460a-8c4f-015c8f3d64f0	1822901	SERVIÇOS DE ENCADERNAÇÃO E PLASTIFICAÇÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	SERVIÇOS DE PRÉ-IMPRESSÃO E ACABAMENTOS GRÁFICOS	SERVIÇOS DE ACABAMENTOS GRÁFICOS
28e29895-e561-4208-8c21-ebe06208a2f0	1822999	SERVIÇOS DE ACABAMENTOS GRÁFICOS, EXCETO ENCADERNAÇÃO E PLASTIFICAÇÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	SERVIÇOS DE PRÉ-IMPRESSÃO E ACABAMENTOS GRÁFICOS	SERVIÇOS DE ACABAMENTOS GRÁFICOS
f65fc238-912d-484b-8407-d2b42cb18f15	1830001	REPRODUÇÃO DE SOM EM QUALQUER SUPORTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	REPRODUÇÃO DE MATERIAIS GRAVADOS EM QUALQUER SUPORTE	REPRODUÇÃO DE MATERIAIS GRAVADOS EM QUALQUER SUPORTE
f5e55b1d-e9b4-4a51-b1cc-826881143108	1830002	REPRODUÇÃO DE VÍDEO EM QUALQUER SUPORTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	REPRODUÇÃO DE MATERIAIS GRAVADOS EM QUALQUER SUPORTE	REPRODUÇÃO DE MATERIAIS GRAVADOS EM QUALQUER SUPORTE
6a229b10-c6e0-405e-b49e-b1f878a24fd6	1830003	REPRODUÇÃO DE SOFTWARE EM QUALQUER SUPORTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	REPRODUÇÃO DE MATERIAIS GRAVADOS EM QUALQUER SUPORTE	REPRODUÇÃO DE MATERIAIS GRAVADOS EM QUALQUER SUPORTE
02374207-afc3-4e06-9869-7c57a1c01d6a	1910100	COQUERIAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE COQUE, DE PRODUTOS DERIVADOS DO PETRÓLEO E DE BIOCOMBUSTÍVEIS	COQUERIAS	COQUERIAS
62f17382-4765-48e2-aeda-ed42ee094e94	1921700	FABRICAÇÃO DE PRODUTOS DO REFINO DE PETRÓLEO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE COQUE, DE PRODUTOS DERIVADOS DO PETRÓLEO E DE BIOCOMBUSTÍVEIS	FABRICAÇÃO DE PRODUTOS DERIVADOS DO PETRÓLEO	FABRICAÇÃO DE PRODUTOS DO REFINO DE PETRÓLEO
68885ee0-61a5-4122-9cf7-6390585ed477	1922501	FORMULAÇÃO DE COMBUSTÍVEIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE COQUE, DE PRODUTOS DERIVADOS DO PETRÓLEO E DE BIOCOMBUSTÍVEIS	FABRICAÇÃO DE PRODUTOS DERIVADOS DO PETRÓLEO	FABRICAÇÃO DE PRODUTOS DERIVADOS DO PETRÓLEO, EXCETO PRODUTOS DO REFINO
37bf8710-5980-44f4-b3d6-e5f49e27a988	1922502	RERREFINO DE ÓLEOS LUBRIFICANTES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE COQUE, DE PRODUTOS DERIVADOS DO PETRÓLEO E DE BIOCOMBUSTÍVEIS	FABRICAÇÃO DE PRODUTOS DERIVADOS DO PETRÓLEO	FABRICAÇÃO DE PRODUTOS DERIVADOS DO PETRÓLEO, EXCETO PRODUTOS DO REFINO
954f6333-c2a7-4143-ba48-31cf31890945	1922599	FABRICAÇÃO DE OUTROS PRODUTOS DERIVADOS DO PETRÓLEO, EXCETO PRODUTOS DO REFINO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE COQUE, DE PRODUTOS DERIVADOS DO PETRÓLEO E DE BIOCOMBUSTÍVEIS	FABRICAÇÃO DE PRODUTOS DERIVADOS DO PETRÓLEO	FABRICAÇÃO DE PRODUTOS DERIVADOS DO PETRÓLEO, EXCETO PRODUTOS DO REFINO
1dd7ddc9-c338-4fbe-bd38-b7bc32ac1397	1931400	FABRICAÇÃO DE ÁLCOOL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE COQUE, DE PRODUTOS DERIVADOS DO PETRÓLEO E DE BIOCOMBUSTÍVEIS	FABRICAÇÃO DE BIOCOMBUSTÍVEIS	FABRICAÇÃO DE ÁLCOOL
d32c2095-ca49-473e-bfee-be85a280f18e	1932200	FABRICAÇÃO DE BIOCOMBUSTÍVEIS, EXCETO ÁLCOOL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE COQUE, DE PRODUTOS DERIVADOS DO PETRÓLEO E DE BIOCOMBUSTÍVEIS	FABRICAÇÃO DE BIOCOMBUSTÍVEIS	FABRICAÇÃO DE BIOCOMBUSTÍVEIS, EXCETO ÁLCOOL
153c4edf-1c2d-44d1-801f-9b9f0d1e0931	2011800	FABRICAÇÃO DE CLORO E ÁLCALIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS	FABRICAÇÃO DE CLORO E ÁLCALIS
70400e4c-bf6f-4937-a425-2b2fdbc41a39	2012600	FABRICAÇÃO DE INTERMEDIÁRIOS PARA FERTILIZANTES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS	FABRICAÇÃO DE INTERMEDIÁRIOS PARA FERTILIZANTES
a02b69d4-c10d-4e02-b90e-7d8f6d09fa5f	2013401	FABRICAÇÃO DE ADUBOS E FERTILIZANTES ORGANOMINERAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS	FABRICAÇÃO DE ADUBOS E FERTILIZANTES
87ea71d6-22e9-4a3f-b8bc-f6977f667daa	2013402	FABRICAÇÃO DE ADUBOS E FERTILIZANTES, EXCETO ORGANOMINERAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS	FABRICAÇÃO DE ADUBOS E FERTILIZANTES
247278d6-35fc-4839-bbb7-4111cd4992f3	2014200	FABRICAÇÃO DE GASES INDUSTRIAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS	FABRICAÇÃO DE GASES INDUSTRIAIS
8e24f442-7dc0-49de-b91c-e44bff28dbef	2019301	ELABORAÇÃO DE COMBUSTÍVEIS NUCLEARES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS NÃO ESPECIFICADOS ANTERIORMENTE
1dd93fc6-d1f4-4621-a14f-67ae124c5559	2019399	FABRICAÇÃO DE OUTROS PRODUTOS QUÍMICOS INORGÂNICOS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS NÃO ESPECIFICADOS ANTERIORMENTE
1244c649-72d2-412d-ac78-4c3425ce6209	2021500	FABRICAÇÃO DE PRODUTOS PETROQUÍMICOS BÁSICOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS ORGÂNICOS	FABRICAÇÃO DE PRODUTOS PETROQUÍMICOS BÁSICOS
53170993-0e08-4809-8120-7f900b5f6c84	2022300	FABRICAÇÃO DE INTERMEDIÁRIOS PARA PLASTIFICANTES, RESINAS E FIBRAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS ORGÂNICOS	FABRICAÇÃO DE INTERMEDIÁRIOS PARA PLASTIFICANTES, RESINAS E FIBRAS
9bfff2ab-c996-46b6-8dc0-1c5c6e856eac	2029100	FABRICAÇÃO DE PRODUTOS QUÍMICOS ORGÂNICOS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS ORGÂNICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS ORGÂNICOS NÃO ESPECIFICADOS ANTERIORMENTE
34dc0015-f498-44f1-8976-4f4089cf0177	2031200	FABRICAÇÃO DE RESINAS TERMOPLÁSTICAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE RESINAS E ELASTÔMEROS	FABRICAÇÃO DE RESINAS TERMOPLÁSTICAS
b3d4c6d2-94d9-461f-9ab5-501bdd9a1159	2032100	FABRICAÇÃO DE RESINAS TERMOFIXAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE RESINAS E ELASTÔMEROS	FABRICAÇÃO DE RESINAS TERMOFIXAS
ee6376ca-2aa4-49fb-8a69-f0a653295185	2033900	FABRICAÇÃO DE ELASTÔMEROS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE RESINAS E ELASTÔMEROS	FABRICAÇÃO DE ELASTÔMEROS
c0ab15ba-426a-4865-a8f1-7dc9c4be21f3	2040100	FABRICAÇÃO DE FIBRAS ARTIFICIAIS E SINTÉTICAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE FIBRAS ARTIFICIAIS E SINTÉTICAS	FABRICAÇÃO DE FIBRAS ARTIFICIAIS E SINTÉTICAS
eaaec153-90ce-4a76-9be9-e2eb26984c76	2051700	FABRICAÇÃO DE DEFENSIVOS AGRÍCOLAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE DEFENSIVOS AGRÍCOLAS E DESINFESTANTES DOMISSANITÁRIOS	FABRICAÇÃO DE DEFENSIVOS AGRÍCOLAS
5439ad7d-72b4-453d-825d-719bfde3255e	2052500	FABRICAÇÃO DE DESINFESTANTES DOMISSANITÁRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE DEFENSIVOS AGRÍCOLAS E DESINFESTANTES DOMISSANITÁRIOS	FABRICAÇÃO DE DESINFESTANTES DOMISSANITÁRIOS
cbc4261f-7a3d-48ea-8941-992cc732d8b9	2061400	FABRICAÇÃO DE SABÕES E DETERGENTES SINTÉTICOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE SABÕES, DETERGENTES, PRODUTOS DE LIMPEZA, COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL	FABRICAÇÃO DE SABÕES E DETERGENTES SINTÉTICOS
2e0a5cf9-01b6-4fd5-a4f4-34adbe5d00b2	2062200	FABRICAÇÃO DE PRODUTOS DE LIMPEZA E POLIMENTO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE SABÕES, DETERGENTES, PRODUTOS DE LIMPEZA, COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL	FABRICAÇÃO DE PRODUTOS DE LIMPEZA E POLIMENTO
5d4f163e-36a8-4ccf-8bf2-bcf23801d407	2063100	FABRICAÇÃO DE COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE SABÕES, DETERGENTES, PRODUTOS DE LIMPEZA, COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL	FABRICAÇÃO DE COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL
965f72c5-826e-454e-8538-59cfe5a80a45	2071100	FABRICAÇÃO DE TINTAS, VERNIZES, ESMALTES E LACAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE TINTAS, VERNIZES, ESMALTES, LACAS E PRODUTOS AFINS	FABRICAÇÃO DE TINTAS, VERNIZES, ESMALTES E LACAS
75aa450a-f718-4d12-a858-9e2fc9994c8f	2072000	FABRICAÇÃO DE TINTAS DE IMPRESSÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE TINTAS, VERNIZES, ESMALTES, LACAS E PRODUTOS AFINS	FABRICAÇÃO DE TINTAS DE IMPRESSÃO
a4b41d8c-48c6-434c-932b-96ae7282a6a0	2073800	FABRICAÇÃO DE IMPERMEABILIZANTES, SOLVENTES E PRODUTOS AFINS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE TINTAS, VERNIZES, ESMALTES, LACAS E PRODUTOS AFINS	FABRICAÇÃO DE IMPERMEABILIZANTES, SOLVENTES E PRODUTOS AFINS
842636ee-589f-42c3-be16-54e91644a10a	2091600	FABRICAÇÃO DE ADESIVOS E SELANTES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS E PREPARADOS QUÍMICOS DIVERSOS	FABRICAÇÃO DE ADESIVOS E SELANTES
d6d3bba8-fcdc-4cf9-94e7-36df9928656a	2092401	FABRICAÇÃO DE PÓLVORAS, EXPLOSIVOS E DETONANTES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS E PREPARADOS QUÍMICOS DIVERSOS	FABRICAÇÃO DE EXPLOSIVOS
40be38b8-e8d9-4cd9-b4ba-dedd7c2a5a92	2092402	FABRICAÇÃO DE ARTIGOS PIROTÉCNICOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS E PREPARADOS QUÍMICOS DIVERSOS	FABRICAÇÃO DE EXPLOSIVOS
98ddb408-fb19-4f92-a864-cc3133a88c66	2092403	FABRICAÇÃO DE FÓSFOROS DE SEGURANÇA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS E PREPARADOS QUÍMICOS DIVERSOS	FABRICAÇÃO DE EXPLOSIVOS
8b2fedc3-8e08-4a2d-9c6d-a89023ae20fc	2093200	FABRICAÇÃO DE ADITIVOS DE USO INDUSTRIAL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS E PREPARADOS QUÍMICOS DIVERSOS	FABRICAÇÃO DE ADITIVOS DE USO INDUSTRIAL
b9f49bcd-4121-4d27-9d90-a75345e76e09	2094100	FABRICAÇÃO DE CATALISADORES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS E PREPARADOS QUÍMICOS DIVERSOS	FABRICAÇÃO DE CATALISADORES
649468e8-4aab-443c-9292-b24a62350a8f	2099101	FABRICAÇÃO DE CHAPAS, FILMES, PAPÉIS E OUTROS MATERIAIS E PRODUTOS QUÍMICOS PARA FOTOGRAFIA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS E PREPARADOS QUÍMICOS DIVERSOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS NÃO ESPECIFICADOS ANTERIORMENTE
cb4ac072-8ab5-4ce8-beda-538eb66c85a1	2099199	FABRICAÇÃO DE OUTROS PRODUTOS QUÍMICOS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS E PREPARADOS QUÍMICOS DIVERSOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS NÃO ESPECIFICADOS ANTERIORMENTE
c971ded7-d72d-4179-a642-1f9ddf198ce2	2110600	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS E FARMACÊUTICOS	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS
d0fe7df3-1a89-4b35-8db6-2e6f28b98889	2121101	FABRICAÇÃO DE MEDICAMENTOS ALOPÁTICOS PARA USO HUMANO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS E FARMACÊUTICOS	FABRICAÇÃO DE PRODUTOS FARMACÊUTICOS	FABRICAÇÃO DE MEDICAMENTOS PARA USO HUMANO
54932900-bb1a-4dfa-98ba-20c57ebe0bdf	2121102	FABRICAÇÃO DE MEDICAMENTOS HOMEOPÁTICOS PARA USO HUMANO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS E FARMACÊUTICOS	FABRICAÇÃO DE PRODUTOS FARMACÊUTICOS	FABRICAÇÃO DE MEDICAMENTOS PARA USO HUMANO
031ff944-9c0c-4946-8070-de75c8c64ab7	2121103	FABRICAÇÃO DE MEDICAMENTOS FITOTERÁPICOS PARA USO HUMANO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS E FARMACÊUTICOS	FABRICAÇÃO DE PRODUTOS FARMACÊUTICOS	FABRICAÇÃO DE MEDICAMENTOS PARA USO HUMANO
af552340-764e-45f1-90f3-0f881598b17f	2122000	FABRICAÇÃO DE MEDICAMENTOS PARA USO VETERINÁRIO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS E FARMACÊUTICOS	FABRICAÇÃO DE PRODUTOS FARMACÊUTICOS	FABRICAÇÃO DE MEDICAMENTOS PARA USO VETERINÁRIO
f8e15186-d4e3-47da-9077-2e073f49b8b6	2123800	FABRICAÇÃO DE PREPARAÇÕES FARMACÊUTICAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS E FARMACÊUTICOS	FABRICAÇÃO DE PRODUTOS FARMACÊUTICOS	FABRICAÇÃO DE PREPARAÇÕES FARMACÊUTICAS
af5f7df7-01eb-498d-b951-f7046a79600b	2211100	FABRICAÇÃO DE PNEUMÁTICOS E DE CÂMARAS DE AR	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE BORRACHA	FABRICAÇÃO DE PNEUMÁTICOS E DE CÂMARAS-DE-AR
fd575b02-74bd-411b-968a-68c2c979081a	2212900	REFORMA DE PNEUMÁTICOS USADOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE BORRACHA	REFORMA DE PNEUMÁTICOS USADOS
dcbfd81a-b4f2-45c3-a51a-0f89c325747d	2219600	FABRICAÇÃO DE ARTEFATOS DE BORRACHA NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE BORRACHA	FABRICAÇÃO DE ARTEFATOS DE BORRACHA NÃO ESPECIFICADOS ANTERIORMENTE
e4994a63-4c97-478a-8f2a-77ea6eb4b124	2221800	FABRICAÇÃO DE LAMINADOS PLANOS E TUBULARES DE MATERIAL PLÁSTICO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE MATERIAL PLÁSTICO	FABRICAÇÃO DE LAMINADOS PLANOS E TUBULARES DE MATERIAL PLÁSTICO
55ad9d0e-0c1a-4890-9085-5f981362da6c	2222600	FABRICAÇÃO DE EMBALAGENS DE MATERIAL PLÁSTICO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE MATERIAL PLÁSTICO	FABRICAÇÃO DE EMBALAGENS DE MATERIAL PLÁSTICO
da158220-2a49-4124-bb46-c8b11c906977	2223400	FABRICAÇÃO DE TUBOS E ACESSÓRIOS DE MATERIAL PLÁSTICO PARA USO NA CONSTRUÇÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE MATERIAL PLÁSTICO	FABRICAÇÃO DE TUBOS E ACESSÓRIOS DE MATERIAL PLÁSTICO PARA USO NA CONSTRUÇÃO
75640c6e-ff7c-4e97-8ded-eb6a3a237857	2229301	FABRICAÇÃO DE ARTEFATOS DE MATERIAL PLÁSTICO PARA USO PESSOAL E DOMÉSTICO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE MATERIAL PLÁSTICO	FABRICAÇÃO DE ARTEFATOS DE MATERIAL PLÁSTICO NÃO ESPECIFICADOS ANTERIORMENTE
d8310f95-a9ef-4d2b-9295-e6af69b33fdb	2229302	FABRICAÇÃO DE ARTEFATOS DE MATERIAL PLÁSTICO PARA USOS INDUSTRIAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE MATERIAL PLÁSTICO	FABRICAÇÃO DE ARTEFATOS DE MATERIAL PLÁSTICO NÃO ESPECIFICADOS ANTERIORMENTE
b54c08ba-9c12-4cae-b331-72399b1b407f	2229303	FABRICAÇÃO DE ARTEFATOS DE MATERIAL PLÁSTICO PARA USO NA CONSTRUÇÃO, EXCETO TUBOS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE MATERIAL PLÁSTICO	FABRICAÇÃO DE ARTEFATOS DE MATERIAL PLÁSTICO NÃO ESPECIFICADOS ANTERIORMENTE
f91c9d56-1941-496b-b68c-c91ac39aa3ad	2229399	FABRICAÇÃO DE ARTEFATOS DE MATERIAL PLÁSTICO PARA OUTROS USOS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE MATERIAL PLÁSTICO	FABRICAÇÃO DE ARTEFATOS DE MATERIAL PLÁSTICO NÃO ESPECIFICADOS ANTERIORMENTE
0b2fcbc6-1018-43ad-9fe3-dec023f0b8dc	2311700	FABRICAÇÃO DE VIDRO PLANO E DE SEGURANÇA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE VIDRO E DE PRODUTOS DO VIDRO	FABRICAÇÃO DE VIDRO PLANO E DE SEGURANÇA
1e4f5c09-6cb6-4d06-95de-463767227eb7	2312500	FABRICAÇÃO DE EMBALAGENS DE VIDRO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE VIDRO E DE PRODUTOS DO VIDRO	FABRICAÇÃO DE EMBALAGENS DE VIDRO
8406df90-623c-4733-b895-fe80fbbe07ad	2319200	FABRICAÇÃO DE ARTIGOS DE VIDRO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE VIDRO E DE PRODUTOS DO VIDRO	FABRICAÇÃO DE ARTIGOS DE VIDRO
99abed93-8917-4e30-8816-68e06787e5d8	2320600	FABRICAÇÃO DE CIMENTO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE CIMENTO	FABRICAÇÃO DE CIMENTO
9f68b5de-2740-47c4-b668-1727455f0962	2330301	FABRICAÇÃO DE ESTRUTURAS PRÉ MOLDADAS DE CONCRETO ARMADO, EM SÉRIE E SOB ENCOMENDA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES
c351fc9e-a953-432d-8950-ee64b82b8005	2330302	FABRICAÇÃO DE ARTEFATOS DE CIMENTO PARA USO NA CONSTRUÇÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES
49d46c48-e1ef-4e65-8cac-bc2ec16367d3	2330303	FABRICAÇÃO DE ARTEFATOS DE FIBROCIMENTO PARA USO NA CONSTRUÇÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES
73affddd-dbed-445e-a677-8f7b500aed15	2330304	FABRICAÇÃO DE CASAS PRÉ MOLDADAS DE CONCRETO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES
cc810f71-fd11-4bdf-8720-a5597d782168	2330305	PREPARAÇÃO DE MASSA DE CONCRETO E ARGAMASSA PARA CONSTRUÇÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES
9a54f74e-7881-4ab4-bb4e-64201aa179bb	2330399	FABRICAÇÃO DE OUTROS ARTEFATOS E PRODUTOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES
02c281cc-545d-4a01-b45b-09efc694ec67	2341900	FABRICAÇÃO DE PRODUTOS CERÂMICOS REFRATÁRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS REFRATÁRIOS
b8a5419a-00d2-488d-9865-9940aaf98c65	2342701	FABRICAÇÃO DE AZULEJOS E PISOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS NÃO-REFRATÁRIOS PARA USO ESTRUTURAL NA CONSTRUÇÃO
bf44304e-606a-4ff7-81fd-370613cdb27b	2342702	FABRICAÇÃO DE ARTEFATOS DE CERÂMICA E BARRO COZIDO PARA USO NA CONSTRUÇÃO, EXCETO AZULEJOS E PISOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS NÃO-REFRATÁRIOS PARA USO ESTRUTURAL NA CONSTRUÇÃO
97c710f5-ed08-42ae-ae8c-4eb2a42879c3	2349401	FABRICAÇÃO DE MATERIAL SANITÁRIO DE CERÂMICA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS NÃO-REFRATÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
2af8f76b-e680-4505-8338-ba9416c6a1cf	2349499	FABRICAÇÃO DE PRODUTOS CERÂMICOS NÃO REFRATÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS NÃO-REFRATÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
da38ed9b-7770-49e2-82c1-db05eea3834c	2391501	BRITAMENTO DE PEDRAS, EXCETO ASSOCIADO À EXTRAÇÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO DE PEDRAS E FABRICAÇÃO DE OUTROS PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO E OUTROS TRABALHOS EM PEDRAS
df2786c7-4dad-43cc-9938-2fa9cda525b3	2391502	APARELHAMENTO DE PEDRAS PARA CONSTRUÇÃO, EXCETO ASSOCIADO À EXTRAÇÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO DE PEDRAS E FABRICAÇÃO DE OUTROS PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO E OUTROS TRABALHOS EM PEDRAS
b8d1099b-024b-4cde-8c33-0f5903efab2d	2391503	APARELHAMENTO DE PLACAS E EXECUÇÃO DE TRABALHOS EM MÁRMORE, GRANITO, ARDÓSIA E OUTRAS PEDRAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO DE PEDRAS E FABRICAÇÃO DE OUTROS PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO E OUTROS TRABALHOS EM PEDRAS
f2b512f1-dbe5-4206-aae9-db172d30cd6a	2392300	FABRICAÇÃO DE CAL E GESSO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO DE PEDRAS E FABRICAÇÃO DE OUTROS PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE CAL E GESSO
8a1474dd-1355-46fd-b1e4-8714cf14ff89	2399101	DECORAÇÃO, LAPIDAÇÃO, GRAVAÇÃO, VITRIFICAÇÃO E OUTROS TRABALHOS EM CERÂMICA, LOUÇA, VIDRO E CRISTAL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO DE PEDRAS E FABRICAÇÃO DE OUTROS PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE
b302f5e2-4a7a-4059-859b-aba23fbf824d	2399102	FABRICAÇÃO DE ABRASIVOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO DE PEDRAS E FABRICAÇÃO DE OUTROS PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE
bed54ced-7a02-441f-9177-4dc33a3de594	2399199	FABRICAÇÃO DE OUTROS PRODUTOS DE MINERAIS NÃO METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO DE PEDRAS E FABRICAÇÃO DE OUTROS PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE
d137d711-0cca-434d-9504-cf35c9ab227a	2411300	PRODUÇÃO DE FERRO GUSA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	PRODUÇÃO DE FERRO-GUSA E DE FERROLIGAS	PRODUÇÃO DE FERRO-GUSA
449b81e3-3557-49ec-b3d8-1b218c52b946	2412100	PRODUÇÃO DE FERROLIGAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	PRODUÇÃO DE FERRO-GUSA E DE FERROLIGAS	PRODUÇÃO DE FERROLIGAS
cf2b4ac7-d6d5-42c0-b794-35904ebcd7d1	2421100	PRODUÇÃO DE SEMI ACABADOS DE AÇO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	SIDERURGIA	PRODUÇÃO DE SEMI-ACABADOS DE AÇO
4babb1ee-b22f-408e-97d1-20fd7e1f5e40	2422901	PRODUÇÃO DE LAMINADOS PLANOS DE AÇO AO CARBONO, REVESTIDOS OU NÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	SIDERURGIA	PRODUÇÃO DE LAMINADOS PLANOS DE AÇO
bf565875-91d6-4be3-a63d-55935e3c41ae	2422902	PRODUÇÃO DE LAMINADOS PLANOS DE AÇOS ESPECIAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	SIDERURGIA	PRODUÇÃO DE LAMINADOS PLANOS DE AÇO
795ddbaa-d7ea-4ae4-ac92-4b99b97a9ab4	2423701	PRODUÇÃO DE TUBOS DE AÇO SEM COSTURA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	SIDERURGIA	PRODUÇÃO DE LAMINADOS LONGOS DE AÇO
26cf7029-f06b-44c8-a324-71bbe11dcb65	2423702	PRODUÇÃO DE LAMINADOS LONGOS DE AÇO, EXCETO TUBOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	SIDERURGIA	PRODUÇÃO DE LAMINADOS LONGOS DE AÇO
d4fc2a56-89e4-4ddb-bd73-dae4c245121b	2424501	PRODUÇÃO DE ARAMES DE AÇO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	SIDERURGIA	PRODUÇÃO DE RELAMINADOS, TREFILADOS E PERFILADOS DE AÇO
59e884ca-ae06-4dab-979c-86f2c19d4df8	2424502	PRODUÇÃO DE RELAMINADOS, TREFILADOS E PERFILADOS DE AÇO, EXCETO ARAMES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	SIDERURGIA	PRODUÇÃO DE RELAMINADOS, TREFILADOS E PERFILADOS DE AÇO
b50e8762-d476-4f9f-83a1-bfdff21df5cc	2431800	PRODUÇÃO DE TUBOS DE AÇO COM COSTURA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	PRODUÇÃO DE TUBOS DE AÇO, EXCETO TUBOS SEM COSTURA	PRODUÇÃO DE CANOS E TUBOS COM COSTURA
a8c6e518-c5ea-4636-88a5-202eeda7f387	2439300	PRODUÇÃO DE OUTROS TUBOS DE FERRO E AÇO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	PRODUÇÃO DE TUBOS DE AÇO, EXCETO TUBOS SEM COSTURA	PRODUÇÃO DE OUTROS TUBOS DE FERRO E AÇO
bee280a3-c718-4cc4-bf78-662d01f6bf25	2441501	PRODUÇÃO DE ALUMÍNIO E SUAS LIGAS EM FORMAS PRIMÁRIAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	METALURGIA DOS METAIS NÃO-FERROSOS	METALURGIA DO ALUMÍNIO E SUAS LIGAS
0af258cd-cce7-4e67-8aa1-051357c8b6b0	2441502	PRODUÇÃO DE LAMINADOS DE ALUMÍNIO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	METALURGIA DOS METAIS NÃO-FERROSOS	METALURGIA DO ALUMÍNIO E SUAS LIGAS
bf8f54d8-3f37-4b54-8bb3-5a84376aa3a9	2442300	METALURGIA DOS METAIS PRECIOSOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	METALURGIA DOS METAIS NÃO-FERROSOS	METALURGIA DOS METAIS PRECIOSOS
ffbd790b-2aad-4041-90be-40e17e1591f9	2443100	METALURGIA DO COBRE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	METALURGIA DOS METAIS NÃO-FERROSOS	METALURGIA DO COBRE
0a606ed7-ed30-4e97-8130-f67aca03ec9b	2449101	PRODUÇÃO DE ZINCO EM FORMAS PRIMÁRIAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	METALURGIA DOS METAIS NÃO-FERROSOS	METALURGIA DOS METAIS NÃO-FERROSOS E SUAS LIGAS NÃO ESPECIFICADOS ANTERIORMENTE
2ca3a222-45d0-4765-84f9-05409c8d655b	2449102	PRODUÇÃO DE LAMINADOS DE ZINCO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	METALURGIA DOS METAIS NÃO-FERROSOS	METALURGIA DOS METAIS NÃO-FERROSOS E SUAS LIGAS NÃO ESPECIFICADOS ANTERIORMENTE
722ee422-ad0b-4bc1-aa3c-a71deab34625	2449103	FABRICAÇÃO DE ÂNODOS PARA GALVANOPLASTIA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	METALURGIA DOS METAIS NÃO-FERROSOS	METALURGIA DOS METAIS NÃO-FERROSOS E SUAS LIGAS NÃO ESPECIFICADOS ANTERIORMENTE
c400cc13-7a40-4dc2-a29b-ad857f409d90	2449199	METALURGIA DE OUTROS METAIS NÃO FERROSOS E SUAS LIGAS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	METALURGIA DOS METAIS NÃO-FERROSOS	METALURGIA DOS METAIS NÃO-FERROSOS E SUAS LIGAS NÃO ESPECIFICADOS ANTERIORMENTE
5fe30dd4-9fc0-49f6-9f36-e0be10082181	2451200	FUNDIÇÃO DE FERRO E AÇO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	FUNDIÇÃO	FUNDIÇÃO DE FERRO E AÇO
3688df06-46ea-4963-84b8-28de684d4a55	2452100	FUNDIÇÃO DE METAIS NÃO FERROSOS E SUAS LIGAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	FUNDIÇÃO	FUNDIÇÃO DE METAIS NÃO-FERROSOS E SUAS LIGAS
3ad435bb-5dc5-4c22-87fe-d8dd8b5ff76a	2511000	FABRICAÇÃO DE ESTRUTURAS METÁLICAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE ESTRUTURAS METÁLICAS E OBRAS DE CALDEIRARIA PESADA	FABRICAÇÃO DE ESTRUTURAS METÁLICAS
f9252d17-717e-41f6-aed1-21d78005f914	2512800	FABRICAÇÃO DE ESQUADRIAS DE METAL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE ESTRUTURAS METÁLICAS E OBRAS DE CALDEIRARIA PESADA	FABRICAÇÃO DE ESQUADRIAS DE METAL
d7ab975e-8d0a-496e-acbb-d3210a070c59	2513600	FABRICAÇÃO DE OBRAS DE CALDEIRARIA PESADA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE ESTRUTURAS METÁLICAS E OBRAS DE CALDEIRARIA PESADA	FABRICAÇÃO DE OBRAS DE CALDEIRARIA PESADA
9be3d532-f9b9-4c83-ada3-2cbbe81d5e40	2521700	FABRICAÇÃO DE TANQUES, RESERVATÓRIOS METÁLICOS E CALDEIRAS PARA AQUECIMENTO CENTRAL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE TANQUES, RESERVATÓRIOS METÁLICOS E CALDEIRAS	FABRICAÇÃO DE TANQUES, RESERVATÓRIOS METÁLICOS E CALDEIRAS PARA AQUECIMENTO CENTRAL
8a35f7a0-70f5-420c-b136-9185ce75ab40	2522500	FABRICAÇÃO DE CALDEIRAS GERADORAS DE VAPOR, EXCETO PARA AQUECIMENTO CENTRAL E PARA VEÍCULOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE TANQUES, RESERVATÓRIOS METÁLICOS E CALDEIRAS	FABRICAÇÃO DE CALDEIRAS GERADORAS DE VAPOR, EXCETO PARA AQUECIMENTO CENTRAL E PARA VEÍCULOS
45c933cd-1830-46b3-ab67-be6cb32c9d81	2531401	PRODUÇÃO DE FORJADOS DE AÇO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FORJARIA, ESTAMPARIA, METALURGIA DO PÓ E SERVIÇOS DE TRATAMENTO DE METAIS	PRODUÇÃO DE FORJADOS DE AÇO E DE METAIS NÃO-FERROSOS E SUAS LIGAS
d0e7b176-8782-4fbd-af6b-7d7ee1dd2013	2531402	PRODUÇÃO DE FORJADOS DE METAIS NÃO FERROSOS E SUAS LIGAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FORJARIA, ESTAMPARIA, METALURGIA DO PÓ E SERVIÇOS DE TRATAMENTO DE METAIS	PRODUÇÃO DE FORJADOS DE AÇO E DE METAIS NÃO-FERROSOS E SUAS LIGAS
c4270910-8d5d-468b-81ba-81b2de87e2da	2532201	PRODUÇÃO DE ARTEFATOS ESTAMPADOS DE METAL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FORJARIA, ESTAMPARIA, METALURGIA DO PÓ E SERVIÇOS DE TRATAMENTO DE METAIS	PRODUÇÃO DE ARTEFATOS ESTAMPADOS DE METAL; METALURGIA DO PÓ
cc706ed0-e0ac-4c50-9efb-16503e82301b	2532202	METALURGIA DO PÓ	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FORJARIA, ESTAMPARIA, METALURGIA DO PÓ E SERVIÇOS DE TRATAMENTO DE METAIS	PRODUÇÃO DE ARTEFATOS ESTAMPADOS DE METAL; METALURGIA DO PÓ
45f2b4fa-c895-4646-9378-6382651d0a3e	2539001	SERVIÇOS DE USINAGEM, TORNEARIA E SOLDA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FORJARIA, ESTAMPARIA, METALURGIA DO PÓ E SERVIÇOS DE TRATAMENTO DE METAIS	SERVIÇOS DE USINAGEM, SOLDA, TRATAMENTO E REVESTIMENTO EM METAIS
9030aa07-7add-47c1-968f-bec90dfe4996	2539002	SERVIÇOS DE TRATAMENTO E REVESTIMENTO EM METAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FORJARIA, ESTAMPARIA, METALURGIA DO PÓ E SERVIÇOS DE TRATAMENTO DE METAIS	SERVIÇOS DE USINAGEM, SOLDA, TRATAMENTO E REVESTIMENTO EM METAIS
558832ef-2cb4-4dbc-ba2f-71200e70cd87	2541100	FABRICAÇÃO DE ARTIGOS DE CUTELARIA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE ARTIGOS DE CUTELARIA, DE SERRALHERIA E FERRAMENTAS	FABRICAÇÃO DE ARTIGOS DE CUTELARIA
f346b2d1-60ec-40ca-80df-0a62a4965cc1	2542000	FABRICAÇÃO DE ARTIGOS DE SERRALHERIA, EXCETO ESQUADRIAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE ARTIGOS DE CUTELARIA, DE SERRALHERIA E FERRAMENTAS	FABRICAÇÃO DE ARTIGOS DE SERRALHERIA, EXCETO ESQUADRIAS
1713071b-2c37-484e-aaeb-8536f91d0811	2543800	FABRICAÇÃO DE FERRAMENTAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE ARTIGOS DE CUTELARIA, DE SERRALHERIA E FERRAMENTAS	FABRICAÇÃO DE FERRAMENTAS
527fd7ad-f3b2-40d4-b139-1eb2fe157065	2550101	FABRICAÇÃO DE EQUIPAMENTO BÉLICO PESADO, EXCETO VEÍCULOS MILITARES DE COMBATE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE EQUIPAMENTO BÉLICO PESADO, ARMAS E MUNIÇÕES	FABRICAÇÃO DE EQUIPAMENTO BÉLICO PESADO, ARMAS E MUNIÇÕES
0fdfaa02-e2c5-4953-b528-f7ce2c7d1762	2550102	FABRICAÇÃO DE ARMAS DE FOGO, OUTRAS ARMAS  E MUNIÇÕES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE EQUIPAMENTO BÉLICO PESADO, ARMAS E MUNIÇÕES	FABRICAÇÃO DE EQUIPAMENTO BÉLICO PESADO, ARMAS E MUNIÇÕES
961f1641-f92c-471c-b8ec-5776c5073bd1	2591800	FABRICAÇÃO DE EMBALAGENS METÁLICAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE EMBALAGENS METÁLICAS
5a03895a-2a28-47cf-be04-8224bf6b3a48	2592601	FABRICAÇÃO DE PRODUTOS DE TREFILADOS DE METAL PADRONIZADOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE PRODUTOS DE TREFILADOS DE METAL
22caac12-14eb-4dab-b249-d77eeb2560ca	2592602	FABRICAÇÃO DE PRODUTOS DE TREFILADOS DE METAL, EXCETO PADRONIZADOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE PRODUTOS DE TREFILADOS DE METAL
66e7ce24-f468-4bfa-b616-321dd3eb3c17	2593400	FABRICAÇÃO DE ARTIGOS DE METAL PARA USO DOMÉSTICO E PESSOAL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE ARTIGOS DE METAL PARA USO DOMÉSTICO E PESSOAL
79bf08c8-9301-4839-ab8e-613aef097978	2599301	SERVIÇOS DE CONFECÇÃO DE ARMAÇÕES METÁLICAS PARA A CONSTRUÇÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE
567d7d08-2c28-42cc-b31d-4b83a6322012	2599302	SERVIÇO DE CORTE E DOBRA DE METAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE
e7eb5aca-93bb-4c01-9283-932f55e741d5	2599399	FABRICAÇÃO DE OUTROS PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE
cf40771a-b360-48a7-86d3-21fc26ebc03c	2610800	FABRICAÇÃO DE COMPONENTES ELETRÔNICOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE COMPONENTES ELETRÔNICOS	FABRICAÇÃO DE COMPONENTES ELETRÔNICOS
369326be-ca1f-4155-895a-7abdcdb23251	2621300	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E PERIFÉRICOS	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA
bf1a8853-4260-4d0d-8f96-fcf486bc38bf	2622100	FABRICAÇÃO DE PERIFÉRICOS PARA EQUIPAMENTOS DE INFORMÁTICA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E PERIFÉRICOS	FABRICAÇÃO DE PERIFÉRICOS PARA EQUIPAMENTOS DE INFORMÁTICA
e366fcec-d35d-4037-abb3-e5683c707607	2631100	FABRICAÇÃO DE EQUIPAMENTOS TRANSMISSORES DE COMUNICAÇÃO, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE EQUIPAMENTOS DE COMUNICAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS TRANSMISSORES DE COMUNICAÇÃO
82dd7308-7606-4ddc-977c-2907807b8ee3	2632900	FABRICAÇÃO DE APARELHOS TELEFÔNICOS E DE OUTROS EQUIPAMENTOS DE COMUNICAÇÃO, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE EQUIPAMENTOS DE COMUNICAÇÃO	FABRICAÇÃO DE APARELHOS TELEFÔNICOS E DE OUTROS EQUIPAMENTOS DE COMUNICAÇÃO
e74942c5-441a-4f6e-9fe9-7e3e0ef3b24b	2640000	FABRICAÇÃO DE APARELHOS DE RECEPÇÃO, REPRODUÇÃO, GRAVAÇÃO E AMPLIFICAÇÃO DE ÁUDIO E VÍDEO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE APARELHOS DE RECEPÇÃO, REPRODUÇÃO, GRAVAÇÃO E AMPLIFICAÇÃO DE ÁUDIO E VÍDEO	FABRICAÇÃO DE APARELHOS DE RECEPÇÃO, REPRODUÇÃO, GRAVAÇÃO E AMPLIFICAÇÃO DE ÁUDIO E VÍDEO
d85ffad2-2a9d-4d99-a971-afa02155f7a0	2651500	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS DE MEDIDA, TESTE E CONTROLE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE APARELHOS E INSTRUMENTOS DE MEDIDA, TESTE E CONTROLE; CRONÔMETROS E RELÓGIOS	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS DE MEDIDA, TESTE E CONTROLE
8b8e356e-1b9e-4720-a523-94d0e3a9e025	2652300	FABRICAÇÃO DE CRONÔMETROS E RELÓGIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE APARELHOS E INSTRUMENTOS DE MEDIDA, TESTE E CONTROLE; CRONÔMETROS E RELÓGIOS	FABRICAÇÃO DE CRONÔMETROS E RELÓGIOS
c1c04eb6-29b9-4e1f-b755-604536cf87b7	2660400	FABRICAÇÃO DE APARELHOS ELETROMÉDICOS E ELETROTERAPÊUTICOS E EQUIPAMENTOS DE IRRADIAÇÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE APARELHOS ELETROMÉDICOS E ELETROTERAPÊUTICOS E EQUIPAMENTOS DE IRRADIAÇÃO	FABRICAÇÃO DE APARELHOS ELETROMÉDICOS E ELETROTERAPÊUTICOS E EQUIPAMENTOS DE IRRADIAÇÃO
40659d20-ae36-4c13-86d6-4e5d5236e43a	2670101	FABRICAÇÃO DE EQUIPAMENTOS E INSTRUMENTOS ÓPTICOS, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE EQUIPAMENTOS E INSTRUMENTOS ÓPTICOS, FOTOGRÁFICOS E CINEMATOGRÁFICOS	FABRICAÇÃO DE EQUIPAMENTOS E INSTRUMENTOS ÓPTICOS, FOTOGRÁFICOS E CINEMATOGRÁFICOS
dfda34d3-5b31-45cc-af1c-6d3e179f8e93	2670102	FABRICAÇÃO DE APARELHOS FOTOGRÁFICOS E CINEMATOGRÁFICOS, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE EQUIPAMENTOS E INSTRUMENTOS ÓPTICOS, FOTOGRÁFICOS E CINEMATOGRÁFICOS	FABRICAÇÃO DE EQUIPAMENTOS E INSTRUMENTOS ÓPTICOS, FOTOGRÁFICOS E CINEMATOGRÁFICOS
a286d14f-cd76-46c4-8eb7-a42bf232185d	2680900	FABRICAÇÃO DE MÍDIAS VIRGENS, MAGNÉTICAS E ÓPTICAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE MÍDIAS VIRGENS, MAGNÉTICAS E ÓPTICAS	FABRICAÇÃO DE MÍDIAS VIRGENS, MAGNÉTICAS E ÓPTICAS
d523ae52-aa7d-47cb-9a5b-f65d8946b7cc	2710401	FABRICAÇÃO DE GERADORES DE CORRENTE CONTÍNUA E ALTERNADA, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE GERADORES, TRANSFORMADORES E MOTORES ELÉTRICOS	FABRICAÇÃO DE GERADORES, TRANSFORMADORES E MOTORES ELÉTRICOS
38415a3d-6bad-474b-94e7-0ca1faf8c7db	2710402	FABRICAÇÃO DE TRANSFORMADORES, INDUTORES, CONVERSORES, SINCRONIZADORES E SEMELHANTES, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE GERADORES, TRANSFORMADORES E MOTORES ELÉTRICOS	FABRICAÇÃO DE GERADORES, TRANSFORMADORES E MOTORES ELÉTRICOS
b17618ee-cdea-4773-a50f-31653dd014dd	2710403	FABRICAÇÃO DE MOTORES ELÉTRICOS, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE GERADORES, TRANSFORMADORES E MOTORES ELÉTRICOS	FABRICAÇÃO DE GERADORES, TRANSFORMADORES E MOTORES ELÉTRICOS
fac759f8-95ba-4348-92be-88dbd32814ea	2721000	FABRICAÇÃO DE PILHAS, BATERIAS E ACUMULADORES ELÉTRICOS, EXCETO PARA VEÍCULOS AUTOMOTORES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE PILHAS, BATERIAS E ACUMULADORES ELÉTRICOS	FABRICAÇÃO DE PILHAS, BATERIAS E ACUMULADORES ELÉTRICOS, EXCETO PARA VEÍCULOS AUTOMOTORES
64f1a60a-b98a-4b84-af80-65fe2b8d4b6f	2722801	FABRICAÇÃO DE BATERIAS E ACUMULADORES PARA VEÍCULOS AUTOMOTORES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE PILHAS, BATERIAS E ACUMULADORES ELÉTRICOS	FABRICAÇÃO DE BATERIAS E ACUMULADORES PARA VEÍCULOS AUTOMOTORES
b6c02ff1-7daf-4bc5-8dd3-9bdc1b3f654d	2722802	RECONDICIONAMENTO DE BATERIAS E ACUMULADORES PARA VEÍCULOS AUTOMOTORES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE PILHAS, BATERIAS E ACUMULADORES ELÉTRICOS	FABRICAÇÃO DE BATERIAS E ACUMULADORES PARA VEÍCULOS AUTOMOTORES
e9920f83-fcc6-48fe-8d8d-766ba26502cc	2731700	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS PARA DISTRIBUIÇÃO E CONTROLE DE ENERGIA ELÉTRICA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE EQUIPAMENTOS PARA DISTRIBUIÇÃO E CONTROLE DE ENERGIA ELÉTRICA	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS PARA DISTRIBUIÇÃO E CONTROLE DE ENERGIA ELÉTRICA
33ecb7ce-cfdc-4d65-9023-7b097282e465	2732500	FABRICAÇÃO DE MATERIAL ELÉTRICO PARA INSTALAÇÕES EM CIRCUITO DE CONSUMO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE EQUIPAMENTOS PARA DISTRIBUIÇÃO E CONTROLE DE ENERGIA ELÉTRICA	FABRICAÇÃO DE MATERIAL ELÉTRICO PARA INSTALAÇÕES EM CIRCUITO DE CONSUMO
8c52b647-69fd-4bbb-81b0-5109c588a6d3	2733300	FABRICAÇÃO DE FIOS, CABOS E CONDUTORES ELÉTRICOS ISOLADOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE EQUIPAMENTOS PARA DISTRIBUIÇÃO E CONTROLE DE ENERGIA ELÉTRICA	FABRICAÇÃO DE FIOS, CABOS E CONDUTORES ELÉTRICOS ISOLADOS
c6d77e6f-fcbd-4a95-8fb6-db6ed256994b	2740601	FABRICAÇÃO DE LÂMPADAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE LÂMPADAS E OUTROS EQUIPAMENTOS DE ILUMINAÇÃO	FABRICAÇÃO DE LÂMPADAS E OUTROS EQUIPAMENTOS DE ILUMINAÇÃO
71f7aceb-f002-452f-aaa1-640a9b837878	2740602	FABRICAÇÃO DE LUMINÁRIAS E OUTROS EQUIPAMENTOS DE ILUMINAÇÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE LÂMPADAS E OUTROS EQUIPAMENTOS DE ILUMINAÇÃO	FABRICAÇÃO DE LÂMPADAS E OUTROS EQUIPAMENTOS DE ILUMINAÇÃO
23cd7313-ddaf-4c4f-8438-3848a50a78c6	2751100	FABRICAÇÃO DE FOGÕES, REFRIGERADORES E MÁQUINAS DE LAVAR E SECAR PARA USO DOMÉSTICO, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE ELETRODOMÉSTICOS	FABRICAÇÃO DE FOGÕES, REFRIGERADORES E MÁQUINAS DE LAVAR E SECAR PARA USO DOMÉSTICO
662a6b72-809b-4401-8a14-4ec8204544c7	2759701	FABRICAÇÃO DE APARELHOS ELÉTRICOS DE USO PESSOAL, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE ELETRODOMÉSTICOS	FABRICAÇÃO DE APARELHOS ELETRODOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
cf7fe00f-cf17-4462-92c5-34c838beadd5	2759799	FABRICAÇÃO DE OUTROS APARELHOS ELETRODOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE ELETRODOMÉSTICOS	FABRICAÇÃO DE APARELHOS ELETRODOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
dae881a8-19d6-40f2-9fe5-32edfeeca78a	2790201	FABRICAÇÃO DE ELETRODOS, CONTATOS E OUTROS ARTIGOS DE CARVÃO E GRAFITA PARA USO ELÉTRICO, ELETROÍMÃS E ISOLADORES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE EQUIPAMENTOS E APARELHOS ELÉTRICOS NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE EQUIPAMENTOS E APARELHOS ELÉTRICOS NÃO ESPECIFICADOS ANTERIORMENTE
b68dd312-afe4-4292-853d-9d044b149534	2790202	FABRICAÇÃO DE EQUIPAMENTOS PARA SINALIZAÇÃO E ALARME	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE EQUIPAMENTOS E APARELHOS ELÉTRICOS NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE EQUIPAMENTOS E APARELHOS ELÉTRICOS NÃO ESPECIFICADOS ANTERIORMENTE
eff58f22-c517-4f32-aeaf-b0385adc2b1b	2790299	FABRICAÇÃO DE OUTROS EQUIPAMENTOS E APARELHOS ELÉTRICOS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE EQUIPAMENTOS E APARELHOS ELÉTRICOS NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE EQUIPAMENTOS E APARELHOS ELÉTRICOS NÃO ESPECIFICADOS ANTERIORMENTE
5a4955b4-906d-410a-b719-840120764004	2811900	FABRICAÇÃO DE MOTORES E TURBINAS, PEÇAS E ACESSÓRIOS, EXCETO PARA AVIÕES E VEÍCULOS RODOVIÁRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MOTORES, BOMBAS, COMPRESSORES E EQUIPAMENTOS DE TRANSMISSÃO	FABRICAÇÃO DE MOTORES E TURBINAS, EXCETO PARA AVIÕES E VEÍCULOS RODOVIÁRIOS
6e52e84f-6b56-4294-a0d1-f1af2892b80e	2812700	FABRICAÇÃO DE EQUIPAMENTOS HIDRÁULICOS E PNEUMÁTICOS, PEÇAS E ACESSÓRIOS, EXCETO VÁLVULAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MOTORES, BOMBAS, COMPRESSORES E EQUIPAMENTOS DE TRANSMISSÃO	FABRICAÇÃO DE EQUIPAMENTOS HIDRÁULICOS E PNEUMÁTICOS, EXCETO VÁLVULAS
9f6c22bb-895b-4060-93bb-f20e6b85d4ec	2813500	FABRICAÇÃO DE VÁLVULAS, REGISTROS E DISPOSITIVOS SEMELHANTES, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MOTORES, BOMBAS, COMPRESSORES E EQUIPAMENTOS DE TRANSMISSÃO	FABRICAÇÃO DE VÁLVULAS, REGISTROS E DISPOSITIVOS SEMELHANTES
1fe7a4af-7a4d-4ba2-a733-9fd7ad414a4b	2814301	FABRICAÇÃO DE COMPRESSORES PARA USO INDUSTRIAL, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MOTORES, BOMBAS, COMPRESSORES E EQUIPAMENTOS DE TRANSMISSÃO	FABRICAÇÃO DE COMPRESSORES
3baacf03-0576-4beb-9d01-993b19a0e0b2	2814302	FABRICAÇÃO DE COMPRESSORES PARA USO NÃO INDUSTRIAL, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MOTORES, BOMBAS, COMPRESSORES E EQUIPAMENTOS DE TRANSMISSÃO	FABRICAÇÃO DE COMPRESSORES
43206ff0-f6ce-4a32-b805-7be3d69ae811	2815101	FABRICAÇÃO DE ROLAMENTOS PARA FINS INDUSTRIAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MOTORES, BOMBAS, COMPRESSORES E EQUIPAMENTOS DE TRANSMISSÃO	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSMISSÃO PARA FINS INDUSTRIAIS
9e814105-cd05-4203-bcae-c78927b7b9aa	2815102	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSMISSÃO PARA FINS INDUSTRIAIS, EXCETO ROLAMENTOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MOTORES, BOMBAS, COMPRESSORES E EQUIPAMENTOS DE TRANSMISSÃO	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSMISSÃO PARA FINS INDUSTRIAIS
16acf9c7-68ee-4429-b081-4e438a124cc0	2821601	FABRICAÇÃO DE FORNOS INDUSTRIAIS, APARELHOS E EQUIPAMENTOS NÃO ELÉTRICOS PARA INSTALAÇÕES TÉRMICAS, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS PARA INSTALAÇÕES TÉRMICAS
92ddbc98-be0d-4097-8300-0e37e39bac71	2821602	FABRICAÇÃO DE ESTUFAS E FORNOS ELÉTRICOS PARA FINS INDUSTRIAIS, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS PARA INSTALAÇÕES TÉRMICAS
aa282e2b-901d-4637-acbb-3ef4666fa66f	2822401	FABRICAÇÃO DE MÁQUINAS, EQUIPAMENTOS E APARELHOS PARA TRANSPORTE E ELEVAÇÃO DE PESSOAS, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE MÁQUINAS, EQUIPAMENTOS E APARELHOS PARA TRANSPORTE E ELEVAÇÃO DE CARGAS E PESSOAS
5a8adafe-003e-46b0-a921-4c4a3b6b5590	2822402	FABRICAÇÃO DE MÁQUINAS, EQUIPAMENTOS E APARELHOS PARA TRANSPORTE E ELEVAÇÃO DE CARGAS, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE MÁQUINAS, EQUIPAMENTOS E APARELHOS PARA TRANSPORTE E ELEVAÇÃO DE CARGAS E PESSOAS
a184bacf-3332-4b74-b7cc-fbfd970e4e0f	2823200	FABRICAÇÃO DE MÁQUINAS E APARELHOS DE REFRIGERAÇÃO E VENTILAÇÃO PARA USO INDUSTRIAL E COMERCIAL, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE MÁQUINAS E APARELHOS DE REFRIGERAÇÃO E VENTILAÇÃO PARA USO INDUSTRIAL E COMERCIAL
6174a04e-df1c-4220-a2dc-43ae7dca8f36	2824101	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS DE AR CONDICIONADO PARA USO INDUSTRIAL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS DE AR CONDICIONADO
a7316518-bf6b-4204-b536-ed6b3666bfcd	2824102	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS DE AR CONDICIONADO PARA USO NÃO INDUSTRIAL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS DE AR CONDICIONADO
6a8d9428-c6e0-4fc4-8027-4cd7b3cb35e2	2825900	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA SANEAMENTO BÁSICO E AMBIENTAL, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA SANEAMENTO BÁSICO E AMBIENTAL
1e3c7e2a-9c4b-45d7-b94c-8da8343a1448	2829101	FABRICAÇÃO DE MÁQUINAS DE ESCREVER, CALCULAR E OUTROS EQUIPAMENTOS NÃO ELETRÔNICOS PARA ESCRITÓRIO, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL NÃO ESPECIFICADOS ANTERIORMENTE
5dad94c8-49bf-4848-b9fa-96ebddaa089c	2829199	FABRICAÇÃO DE OUTRAS MÁQUINAS E EQUIPAMENTOS DE USO GERAL NÃO ESPECIFICADOS ANTERIORMENTE, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL NÃO ESPECIFICADOS ANTERIORMENTE
b576a8b6-3a1c-437d-9581-4ec55aefaf2a	2831300	FABRICAÇÃO DE TRATORES AGRÍCOLAS, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE TRATORES E DE MÁQUINAS E EQUIPAMENTOS PARA A AGRICULTURA E PECUÁRIA	FABRICAÇÃO DE TRATORES AGRÍCOLAS
0cb54c5e-92cd-4539-bb73-8a8a33a296df	2832100	FABRICAÇÃO DE EQUIPAMENTOS PARA IRRIGAÇÃO AGRÍCOLA, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE TRATORES E DE MÁQUINAS E EQUIPAMENTOS PARA A AGRICULTURA E PECUÁRIA	FABRICAÇÃO DE EQUIPAMENTOS PARA IRRIGAÇÃO AGRÍCOLA
232888b7-fd2b-466b-8d2d-eff899fee7e9	2833000	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A AGRICULTURA E PECUÁRIA, PEÇAS E ACESSÓRIOS, EXCETO PARA IRRIGAÇÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE TRATORES E DE MÁQUINAS E EQUIPAMENTOS PARA A AGRICULTURA E PECUÁRIA	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A AGRICULTURA E PECUÁRIA, EXCETO PARA IRRIGAÇÃO
629087c8-d805-44bd-a724-8af67063cc05	2840200	FABRICAÇÃO DE MÁQUINAS FERRAMENTA, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS-FERRAMENTA	FABRICAÇÃO DE MÁQUINAS-FERRAMENTA
16efeaa1-c373-453e-9058-7581eb8f4105	2851800	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A PROSPECÇÃO E EXTRAÇÃO DE PETRÓLEO, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO NA EXTRAÇÃO MINERAL E NA CONSTRUÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A PROSPECÇÃO E EXTRAÇÃO DE PETRÓLEO
c8b79b2e-3309-446c-bb0d-138943ed8dd7	2852600	FABRICAÇÃO DE OUTRAS MÁQUINAS E EQUIPAMENTOS PARA USO NA EXTRAÇÃO MINERAL, PEÇAS E ACESSÓRIOS, EXCETO NA EXTRAÇÃO DE PETRÓLEO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO NA EXTRAÇÃO MINERAL E NA CONSTRUÇÃO	FABRICAÇÃO DE OUTRAS MÁQUINAS E EQUIPAMENTOS PARA USO NA EXTRAÇÃO MINERAL, EXCETO NA EXTRAÇÃO DE PETRÓLEO
ab9e568e-427b-4680-b3ab-99843b24fbe7	2853400	FABRICAÇÃO DE TRATORES, PEÇAS E ACESSÓRIOS, EXCETO AGRÍCOLAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO NA EXTRAÇÃO MINERAL E NA CONSTRUÇÃO	FABRICAÇÃO DE TRATORES, EXCETO AGRÍCOLAS
7108976b-f821-457a-9b1b-651ef447118e	2854200	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA TERRAPLENAGEM, PAVIMENTAÇÃO E CONSTRUÇÃO, PEÇAS E ACESSÓRIOS, EXCETO TRATORES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO NA EXTRAÇÃO MINERAL E NA CONSTRUÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA TERRAPLENAGEM, PAVIMENTAÇÃO E CONSTRUÇÃO, EXCETO TRATORES
da06f94c-9dad-4574-8db6-551b054d57e9	2861500	FABRICAÇÃO DE MÁQUINAS PARA A INDÚSTRIA METALÚRGICA, PEÇAS E ACESSÓRIOS, EXCETO MÁQUINAS FERRAMENTA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO INDUSTRIAL ESPECÍFICO	FABRICAÇÃO DE MÁQUINAS PARA A INDÚSTRIA METALÚRGICA, EXCETO MÁQUINAS-FERRAMENTA
673d9e3f-51dc-4d9c-97a2-32128053a2f7	2862300	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AS INDÚSTRIAS DE ALIMENTOS, BEBIDAS E FUMO, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO INDUSTRIAL ESPECÍFICO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AS INDÚSTRIAS DE ALIMENTOS, BEBIDAS E FUMO
93659a99-f101-4689-9640-10cfcd4835e6	2863100	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A INDÚSTRIA TÊXTIL, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO INDUSTRIAL ESPECÍFICO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A INDÚSTRIA TÊXTIL
b4fc2cd1-bd96-4717-92de-dd107cdbf992	2864000	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AS INDÚSTRIAS DO VESTUÁRIO, DO COURO E DE CALÇADOS, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO INDUSTRIAL ESPECÍFICO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AS INDÚSTRIAS DO VESTUÁRIO, DO COURO E DE CALÇADOS
f4df3858-e144-4d1f-8ce3-c6448792282e	2865800	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AS INDÚSTRIAS DE CELULOSE, PAPEL E PAPELÃO E ARTEFATOS, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO INDUSTRIAL ESPECÍFICO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AS INDÚSTRIAS DE CELULOSE, PAPEL E PAPELÃO E ARTEFATOS
f3e6e479-409d-471c-9872-a49499886f32	2866600	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A INDÚSTRIA DO PLÁSTICO, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO INDUSTRIAL ESPECÍFICO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A INDÚSTRIA DO PLÁSTICO
cf004d3f-88eb-4e90-8824-8226801e7e03	2869100	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA USO INDUSTRIAL ESPECÍFICO NÃO ESPECIFICADOS ANTERIORMENTE, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO INDUSTRIAL ESPECÍFICO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA USO INDUSTRIAL ESPECÍFICO NÃO ESPECIFICADOS ANTERIORMENTE
729b3bb4-9ab3-4bbb-94e5-de61737414cf	2910701	FABRICAÇÃO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS	FABRICAÇÃO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS
d4ea2c31-b68a-453a-b114-6e365b69fe7d	2910702	FABRICAÇÃO DE CHASSIS COM MOTOR PARA AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS	FABRICAÇÃO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS
0f39e2dd-0ee6-4144-9f25-f6abde99b730	2910703	FABRICAÇÃO DE MOTORES PARA AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS	FABRICAÇÃO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS
333181dd-644f-4d33-a4f4-c8f0dfa8e18b	2920401	FABRICAÇÃO DE CAMINHÕES E ÔNIBUS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE CAMINHÕES E ÔNIBUS	FABRICAÇÃO DE CAMINHÕES E ÔNIBUS
abdd941e-9211-4152-bb82-4c46122db06b	2920402	FABRICAÇÃO DE MOTORES PARA CAMINHÕES E ÔNIBUS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE CAMINHÕES E ÔNIBUS	FABRICAÇÃO DE CAMINHÕES E ÔNIBUS
ea3a2ccb-09a9-40ce-87f9-035e08a80960	2930101	FABRICAÇÃO DE CABINES, CARROCERIAS E REBOQUES PARA CAMINHÕES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE CABINES, CARROCERIAS E REBOQUES PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE CABINES, CARROCERIAS E REBOQUES PARA VEÍCULOS AUTOMOTORES
743095b4-8c09-44d2-959d-72cab7612fa9	2930102	FABRICAÇÃO DE CARROCERIAS PARA ÔNIBUS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE CABINES, CARROCERIAS E REBOQUES PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE CABINES, CARROCERIAS E REBOQUES PARA VEÍCULOS AUTOMOTORES
0d62cb6b-5b36-4cd2-a80b-267c2d19cd90	2930103	FABRICAÇÃO DE CABINES, CARROCERIAS E REBOQUES PARA OUTROS VEÍCULOS AUTOMOTORES, EXCETO CAMINHÕES E ÔNIBUS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE CABINES, CARROCERIAS E REBOQUES PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE CABINES, CARROCERIAS E REBOQUES PARA VEÍCULOS AUTOMOTORES
b177358c-2cbc-444e-8d52-59659a10b540	2941700	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA O SISTEMA MOTOR DE VEÍCULOS AUTOMOTORES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA O SISTEMA MOTOR DE VEÍCULOS AUTOMOTORES
0b7bc843-4582-473d-901f-c14fd6356f40	2942500	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA OS SISTEMAS DE MARCHA E TRANSMISSÃO DE VEÍCULOS AUTOMOTORES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA OS SISTEMAS DE MARCHA E TRANSMISSÃO DE VEÍCULOS AUTOMOTORES
86d20699-595c-4e94-8d4b-49d5da6e941a	2943300	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA O SISTEMA DE FREIOS DE VEÍCULOS AUTOMOTORES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA O SISTEMA DE FREIOS DE VEÍCULOS AUTOMOTORES
8e467539-13eb-46ed-a743-9e84eaa3817c	2944100	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA O SISTEMA DE DIREÇÃO E SUSPENSÃO DE VEÍCULOS AUTOMOTORES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA O SISTEMA DE DIREÇÃO E SUSPENSÃO DE VEÍCULOS AUTOMOTORES
598a569c-f1c4-4abb-980d-f9b3a747e45a	2945000	FABRICAÇÃO DE MATERIAL ELÉTRICO E ELETRÔNICO PARA VEÍCULOS AUTOMOTORES, EXCETO BATERIAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE MATERIAL ELÉTRICO E ELETRÔNICO PARA VEÍCULOS AUTOMOTORES, EXCETO BATERIAS
52221eb6-47e3-406e-b706-d3275e56a02e	2949201	FABRICAÇÃO DE BANCOS E ESTOFADOS PARA VEÍCULOS AUTOMOTORES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES NÃO ESPECIFICADOS ANTERIORMENTE
e0c533ef-6134-4046-96aa-7703c6e5271a	2949299	FABRICAÇÃO DE OUTRAS PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES NÃO ESPECIFICADAS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES NÃO ESPECIFICADOS ANTERIORMENTE
5e86a152-7034-4b0b-b2e1-99699f4f0494	2950600	RECONDICIONAMENTO E RECUPERAÇÃO DE MOTORES PARA VEÍCULOS AUTOMOTORES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	RECONDICIONAMENTO E RECUPERAÇÃO DE MOTORES PARA VEÍCULOS AUTOMOTORES	RECONDICIONAMENTO E RECUPERAÇÃO DE MOTORES PARA VEÍCULOS AUTOMOTORES
3f7ee712-83d8-45ee-be33-b175bb212a76	3011301	CONSTRUÇÃO DE EMBARCAÇÕES DE GRANDE PORTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	CONSTRUÇÃO DE EMBARCAÇÕES	CONSTRUÇÃO DE EMBARCAÇÕES E ESTRUTURAS FLUTUANTES
c31f7951-93df-4224-bd61-674d8de3ed49	3011302	CONSTRUÇÃO DE EMBARCAÇÕES PARA USO COMERCIAL E PARA USOS ESPECIAIS, EXCETO DE GRANDE PORTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	CONSTRUÇÃO DE EMBARCAÇÕES	CONSTRUÇÃO DE EMBARCAÇÕES E ESTRUTURAS FLUTUANTES
b3f77518-db94-41b2-84b0-126ddc37b459	3012100	CONSTRUÇÃO DE EMBARCAÇÕES PARA ESPORTE E LAZER	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	CONSTRUÇÃO DE EMBARCAÇÕES	CONSTRUÇÃO DE EMBARCAÇÕES PARA ESPORTE E LAZER
993e4d6f-d996-4d53-b4b1-53c5d546c0b4	3031800	FABRICAÇÃO DE LOCOMOTIVAS, VAGÕES E OUTROS MATERIAIS RODANTES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE VEÍCULOS FERROVIÁRIOS	FABRICAÇÃO DE LOCOMOTIVAS, VAGÕES E OUTROS MATERIAIS RODANTES
de1b61bd-97a5-48d3-a57c-f8052b18c440	3032600	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS FERROVIÁRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE VEÍCULOS FERROVIÁRIOS	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS FERROVIÁRIOS
b34d07d7-99ad-4da9-afda-e26a7d9d0aff	3041500	FABRICAÇÃO DE AERONAVES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE AERONAVES	FABRICAÇÃO DE AERONAVES
4f569272-adeb-4a3a-a9a5-6960d7180084	3042300	FABRICAÇÃO DE TURBINAS, MOTORES E OUTROS COMPONENTES E PEÇAS PARA AERONAVES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE AERONAVES	FABRICAÇÃO DE TURBINAS, MOTORES E OUTROS COMPONENTES E PEÇAS PARA AERONAVES
e4ec9198-7f34-45c5-9df5-66b9369845c0	3050400	FABRICAÇÃO DE VEÍCULOS MILITARES DE COMBATE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE VEÍCULOS MILITARES DE COMBATE	FABRICAÇÃO DE VEÍCULOS MILITARES DE COMBATE
79402cca-b271-4659-8738-63f06afe867d	3091101	FABRICAÇÃO DE MOTOCICLETAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSPORTE NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE MOTOCICLETAS
ae571df6-26f2-4f37-8983-8a8502edd4c7	3091102	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA MOTOCICLETAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSPORTE NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE MOTOCICLETAS
316a7be6-bafa-4e1f-9dd4-75f78b48f5e6	3092000	FABRICAÇÃO DE BICICLETAS E TRICICLOS NÃO MOTORIZADOS, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSPORTE NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE BICICLETAS E TRICICLOS NÃO-MOTORIZADOS
1cef8d04-d048-468c-b8c5-359457aa0187	3099700	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSPORTE NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSPORTE NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSPORTE NÃO ESPECIFICADOS ANTERIORMENTE
7bb77859-1dd6-4731-9585-ddf2ae932c36	3101200	FABRICAÇÃO DE MÓVEIS COM PREDOMINÂNCIA DE MADEIRA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÓVEIS	FABRICAÇÃO DE MÓVEIS	FABRICAÇÃO DE MÓVEIS COM PREDOMINÂNCIA DE MADEIRA
5e97e388-a9dc-415d-a20e-35e5703c59c1	3102100	FABRICAÇÃO DE MÓVEIS COM PREDOMINÂNCIA DE METAL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÓVEIS	FABRICAÇÃO DE MÓVEIS	FABRICAÇÃO DE MÓVEIS COM PREDOMINÂNCIA DE METAL
b2afa279-4d1f-4936-a677-b128ed8df7a7	3103900	FABRICAÇÃO DE MÓVEIS DE OUTROS MATERIAIS, EXCETO MADEIRA E METAL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÓVEIS	FABRICAÇÃO DE MÓVEIS	FABRICAÇÃO DE MÓVEIS DE OUTROS MATERIAIS, EXCETO MADEIRA E METAL
0bd6f08e-d641-4fd9-9996-d3be9b264b04	3104700	FABRICAÇÃO DE COLCHÕES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÓVEIS	FABRICAÇÃO DE MÓVEIS	FABRICAÇÃO DE COLCHÕES
ff25c43c-eb4d-4bd6-b040-994cd182ab5e	3211601	LAPIDAÇÃO DE GEMAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE ARTIGOS DE JOALHERIA, BIJUTERIA E SEMELHANTES	LAPIDAÇÃO DE GEMAS E FABRICAÇÃO DE ARTEFATOS DE OURIVESARIA E JOALHERIA
b684479a-dc83-4bbb-a8e1-be9e4dabff2c	3211602	FABRICAÇÃO DE ARTEFATOS DE JOALHERIA E OURIVESARIA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE ARTIGOS DE JOALHERIA, BIJUTERIA E SEMELHANTES	LAPIDAÇÃO DE GEMAS E FABRICAÇÃO DE ARTEFATOS DE OURIVESARIA E JOALHERIA
50c670cf-8d39-4e5e-a27b-23a6dcac8f5a	3211603	CUNHAGEM DE MOEDAS E MEDALHAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE ARTIGOS DE JOALHERIA, BIJUTERIA E SEMELHANTES	LAPIDAÇÃO DE GEMAS E FABRICAÇÃO DE ARTEFATOS DE OURIVESARIA E JOALHERIA
e2ff10db-ba13-4359-955d-1bab54dd0915	3212400	FABRICAÇÃO DE BIJUTERIAS E ARTEFATOS SEMELHANTES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE ARTIGOS DE JOALHERIA, BIJUTERIA E SEMELHANTES	FABRICAÇÃO DE BIJUTERIAS E ARTEFATOS SEMELHANTES
32b87de1-a921-4def-b0b0-37555a1d1c09	3220500	FABRICAÇÃO DE INSTRUMENTOS MUSICAIS, PEÇAS E ACESSÓRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE INSTRUMENTOS MUSICAIS	FABRICAÇÃO DE INSTRUMENTOS MUSICAIS
2a55bb76-a317-461d-ab5a-32091c17b63d	3230200	FABRICAÇÃO DE ARTEFATOS PARA PESCA E ESPORTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE ARTEFATOS PARA PESCA E ESPORTE	FABRICAÇÃO DE ARTEFATOS PARA PESCA E ESPORTE
20da67af-d5e1-48ff-bce6-293fde29472d	3240001	FABRICAÇÃO DE JOGOS ELETRÔNICOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE BRINQUEDOS E JOGOS RECREATIVOS	FABRICAÇÃO DE BRINQUEDOS E JOGOS RECREATIVOS
2ed6ae24-b405-41bd-8b73-9cf0c464fb72	3240002	FABRICAÇÃO DE MESAS DE BILHAR, DE SINUCA E ACESSÓRIOS NÃO ASSOCIADA À LOCAÇÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE BRINQUEDOS E JOGOS RECREATIVOS	FABRICAÇÃO DE BRINQUEDOS E JOGOS RECREATIVOS
42956647-0e31-4b9f-8801-e17d54eb3405	3240003	FABRICAÇÃO DE MESAS DE BILHAR, DE SINUCA E ACESSÓRIOS ASSOCIADA À LOCAÇÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE BRINQUEDOS E JOGOS RECREATIVOS	FABRICAÇÃO DE BRINQUEDOS E JOGOS RECREATIVOS
7cd0aa01-a1c9-40e1-a07b-40c5267e3ef3	3240099	FABRICAÇÃO DE OUTROS BRINQUEDOS E JOGOS RECREATIVOS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE BRINQUEDOS E JOGOS RECREATIVOS	FABRICAÇÃO DE BRINQUEDOS E JOGOS RECREATIVOS
0984a2f7-fd77-46f6-91e8-32b22c4e0f26	3250701	FABRICAÇÃO DE INSTRUMENTOS NÃO ELETRÔNICOS E UTENSÍLIOS PARA USO MÉDICO, CIRÚRGICO, ODONTOLÓGICO E DE LABORATÓRIO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS
57ffae4c-adf9-41d6-9342-c04e471bec22	3250702	FABRICAÇÃO DE MOBILIÁRIO PARA USO MÉDICO, CIRÚRGICO, ODONTOLÓGICO E DE LABORATÓRIO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS
3dc2a33d-3267-4e7e-b9f0-00aa6a91857a	3250703	FABRICAÇÃO DE APARELHOS E UTENSÍLIOS PARA CORREÇÃO DE DEFEITOS FÍSICOS E APARELHOS ORTOPÉDICOS EM GERAL SOB ENCOMENDA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS
7a0fe3a5-3f22-4190-b5ea-a5aa4581fae7	3250704	FABRICAÇÃO DE APARELHOS E UTENSÍLIOS PARA CORREÇÃO DE DEFEITOS FÍSICOS E APARELHOS ORTOPÉDICOS EM GERAL, EXCETO SOB ENCOMENDA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS
1761fc66-25bf-489c-b670-1384259e7592	3250705	FABRICAÇÃO DE MATERIAIS PARA MEDICINA E ODONTOLOGIA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS
168971ff-310e-471b-8fe1-3855a7ea569f	3250706	SERVIÇOS DE PRÓTESE DENTÁRIA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS
96d09189-40ba-4a04-b57d-af3b2f5b5ae5	3250707	FABRICAÇÃO DE ARTIGOS ÓPTICOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS
4c18c115-6de5-4cf2-94e9-ec17a7ce9f82	3250709	SERVIÇO DE LABORATÓRIO ÓPTICO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS
dfcfe308-1458-4899-b34d-8049c48f971e	3291400	FABRICAÇÃO DE ESCOVAS, PINCÉIS E VASSOURAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE ESCOVAS, PINCÉIS E VASSOURAS
2a67760d-5809-46b0-b8a9-bdf69d181b46	3292201	FABRICAÇÃO DE ROUPAS DE PROTEÇÃO E SEGURANÇA E RESISTENTES A FOGO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE EQUIPAMENTOS E ACESSÓRIOS PARA SEGURANÇA E PROTEÇÃO PESSOAL E PROFISSIONAL
ed68075b-ebbb-43fc-832f-5f95cdd1f290	3292202	FABRICAÇÃO DE EQUIPAMENTOS E ACESSÓRIOS PARA SEGURANÇA PESSOAL E PROFISSIONAL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE EQUIPAMENTOS E ACESSÓRIOS PARA SEGURANÇA E PROTEÇÃO PESSOAL E PROFISSIONAL
8294797c-702a-4f0c-bf31-0b80b0936468	3299001	FABRICAÇÃO DE GUARDA CHUVAS E SIMILARES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS NÃO ESPECIFICADOS ANTERIORMENTE
8c0b4a10-38cf-4dec-a19b-c8bde6fe1e7f	3299002	FABRICAÇÃO DE CANETAS, LÁPIS E OUTROS ARTIGOS PARA ESCRITÓRIO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS NÃO ESPECIFICADOS ANTERIORMENTE
54f99505-ac28-4eaf-a4c1-204b24a90034	3299003	FABRICAÇÃO DE LETRAS, LETREIROS E PLACAS DE QUALQUER MATERIAL, EXCETO LUMINOSOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS NÃO ESPECIFICADOS ANTERIORMENTE
9ff304a4-ba7d-44ca-ae6c-c4d423bc3159	3299004	FABRICAÇÃO DE PAINÉIS E LETREIROS LUMINOSOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS NÃO ESPECIFICADOS ANTERIORMENTE
bfc15eb5-b715-4732-87e1-d62724287510	3299005	FABRICAÇÃO DE AVIAMENTOS PARA COSTURA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS NÃO ESPECIFICADOS ANTERIORMENTE
7cccc2be-0f78-432e-91e1-d5b362f01e82	3299006	FABRICAÇÃO DE VELAS, INCLUSIVE DECORATIVAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS NÃO ESPECIFICADOS ANTERIORMENTE
9163a535-1420-4639-b03b-4528e8049b54	3299099	FABRICAÇÃO DE PRODUTOS DIVERSOS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS NÃO ESPECIFICADOS ANTERIORMENTE
ab2d51e1-4918-4cdc-a84b-fea4b92d8856	3311200	MANUTENÇÃO E REPARAÇÃO DE TANQUES, RESERVATÓRIOS METÁLICOS E CALDEIRAS, EXCETO PARA VEÍCULOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE TANQUES, RESERVATÓRIOS METÁLICOS E CALDEIRAS, EXCETO PARA VEÍCULOS
bbf1f94a-6e19-4b92-ac9e-8f2c3a901dfb	3312102	MANUTENÇÃO E REPARAÇÃO DE APARELHOS E INSTRUMENTOS DE MEDIDA, TESTE E CONTROLE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE EQUIPAMENTOS ELETRÔNICOS E ÓPTICOS
72dfd73b-7de7-45ab-a02e-e2a0684f90b8	3312103	MANUTENÇÃO E REPARAÇÃO DE APARELHOS ELETROMÉDICOS E ELETROTERAPÊUTICOS E EQUIPAMENTOS DE IRRADIAÇÃO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE EQUIPAMENTOS ELETRÔNICOS E ÓPTICOS
15de6008-a04f-4a5c-abc0-6930ba4952dc	3312104	MANUTENÇÃO E REPARAÇÃO DE EQUIPAMENTOS E INSTRUMENTOS ÓPTICOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE EQUIPAMENTOS ELETRÔNICOS E ÓPTICOS
caca098e-074e-40cf-b951-f8f0a349ce28	3313901	MANUTENÇÃO E REPARAÇÃO DE GERADORES, TRANSFORMADORES E MOTORES ELÉTRICOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS ELÉTRICOS
b13fbd20-0345-485e-972d-b983359f725e	3313902	MANUTENÇÃO E REPARAÇÃO DE BATERIAS E ACUMULADORES ELÉTRICOS, EXCETO PARA VEÍCULOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS ELÉTRICOS
e850d3b5-d3ac-484a-bca9-3807579b3eca	3313999	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS ELÉTRICOS
94afa6d2-8eeb-4350-bd13-dc0d3bfa2c88	3314701	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS MOTRIZES NÃO ELÉTRICAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
d593db9a-2636-4a54-83e0-409da8e8d6f0	3314702	MANUTENÇÃO E REPARAÇÃO DE EQUIPAMENTOS HIDRÁULICOS E PNEUMÁTICOS, EXCETO VÁLVULAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
c50dee86-e816-4bb1-920c-f922c8cdbea0	3314703	MANUTENÇÃO E REPARAÇÃO DE VÁLVULAS INDUSTRIAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
25af89d1-0895-4a58-b087-84544c316f56	3314704	MANUTENÇÃO E REPARAÇÃO DE COMPRESSORES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
1089b511-c43c-4543-b07b-073cebc83528	3314705	MANUTENÇÃO E REPARAÇÃO DE EQUIPAMENTOS DE TRANSMISSÃO PARA FINS INDUSTRIAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
a9e315e8-4a5c-4c1d-86e1-03d69a4123b0	3314706	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS, APARELHOS E EQUIPAMENTOS PARA INSTALAÇÕES TÉRMICAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
2e78a2e3-43ae-4cb2-8b33-28a23c1a8698	3314707	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E APARELHOS DE REFRIGERAÇÃO E VENTILAÇÃO PARA USO INDUSTRIAL E COMERCIAL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
7f411faf-a759-4629-a493-d3210698e98b	3314708	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS, EQUIPAMENTOS E APARELHOS PARA TRANSPORTE E ELEVAÇÃO DE CARGAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
59d089e6-0d9b-4fdf-a234-351bf8d62c67	3314709	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS DE ESCREVER, CALCULAR E DE OUTROS EQUIPAMENTOS NÃO ELETRÔNICOS PARA ESCRITÓRIO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
bbad4f25-1202-48e0-90fd-006e265abd36	3314710	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA USO GERAL NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
95a5b803-cefa-4746-b259-ee10d93adfdb	3314711	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AGRICULTURA E PECUÁRIA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
90fe3e45-65bc-4ea7-a4fa-1f68fa964fd4	3314712	MANUTENÇÃO E REPARAÇÃO DE TRATORES AGRÍCOLAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
db419cd2-5e27-401c-8bad-4658d20312d3	3314713	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS FERRAMENTA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
62c9dcdf-0ccf-4da3-81b3-224da1840057	3314714	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A PROSPECÇÃO E EXTRAÇÃO DE PETRÓLEO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
0f0da447-45ce-4cfb-a230-7964f0f5c3ea	3314715	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA USO NA EXTRAÇÃO MINERAL, EXCETO NA EXTRAÇÃO DE PETRÓLEO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
a66a0479-028e-40c2-aa6f-edc31fc7c1a9	3314716	MANUTENÇÃO E REPARAÇÃO DE TRATORES, EXCETO AGRÍCOLAS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
5770fc95-5d2a-44be-9574-8afc4a841d3d	3314717	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE TERRAPLENAGEM, PAVIMENTAÇÃO E CONSTRUÇÃO, EXCETO TRATORES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
5366a4d5-79af-45e9-afae-47805b106ffb	3314718	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS PARA A INDÚSTRIA METALÚRGICA, EXCETO MÁQUINAS FERRAMENTA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
d23a9636-e5cd-4fc3-abbb-a263ac8cdfca	3314719	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AS INDÚSTRIAS DE ALIMENTOS, BEBIDAS E FUMO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
988ed9f4-878d-4de0-bf13-d48afd5d735a	3314720	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A INDÚSTRIA TÊXTIL, DO VESTUÁRIO, DO COURO E CALÇADOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
aabe40dc-3090-45cc-9b20-fae4628e5389	3314721	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E APARELHOS PARA A INDÚSTRIA DE CELULOSE, PAPEL E PAPELÃO E ARTEFATOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
453072ac-0941-424a-b4b4-b91e55e582f0	3314722	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E APARELHOS PARA A INDÚSTRIA DO PLÁSTICO	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
ada8feb1-3e00-42a9-9ab8-e6648e99a6a4	3314799	MANUTENÇÃO E REPARAÇÃO DE OUTRAS MÁQUINAS E EQUIPAMENTOS PARA USOS INDUSTRIAIS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
33cad44f-17f6-427e-b831-7af7a090339d	3315500	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS FERROVIÁRIOS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS FERROVIÁRIOS
af21d3ba-4f25-4dea-a99c-128fa691cd43	3316301	MANUTENÇÃO E REPARAÇÃO DE AERONAVES, EXCETO A MANUTENÇÃO NA PISTA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE AERONAVES
899e79bd-b41d-4830-a173-62a53d8231a8	3316302	MANUTENÇÃO DE AERONAVES NA PISTA	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE AERONAVES
e6b1088a-dddd-41ec-a8d3-d4db89efea52	3317101	MANUTENÇÃO E REPARAÇÃO DE EMBARCAÇÕES E ESTRUTURAS FLUTUANTES	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE EMBARCAÇÕES
e69557fb-b16b-4da1-ae60-f6d3af6326b8	3317102	MANUTENÇÃO E REPARAÇÃO DE EMBARCAÇÕES PARA ESPORTE E LAZER	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE EMBARCAÇÕES
b0fa60db-8341-49ef-9ee3-2fcc3cf9d5e2	3319800	MANUTENÇÃO E REPARAÇÃO DE EQUIPAMENTOS E PRODUTOS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE EQUIPAMENTOS E PRODUTOS NÃO ESPECIFICADOS ANTERIORMENTE
af6523da-4f4c-4d45-850e-9159bfb50015	3321000	INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS INDUSTRIAIS	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS INDUSTRIAIS
2fbf934d-5fdd-4839-92c5-199c345fd681	3329501	SERVIÇOS DE MONTAGEM DE MÓVEIS DE QUALQUER MATERIAL	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	INSTALAÇÃO DE EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE
e392e3bb-2039-4c90-af88-abac7e53cda9	3329599	INSTALAÇÃO DE OUTROS EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE	t	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	INSTALAÇÃO DE EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE
22ffae56-b159-42a4-8bfd-059857c44f46	3511501	GERAÇÃO DE ENERGIA ELÉTRICA	t	ELETRICIDADE E GÁS	ELETRICIDADE, GÁS E OUTRAS UTILIDADES	GERAÇÃO, TRANSMISSÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA	GERAÇÃO DE ENERGIA ELÉTRICA
ed629c9e-fada-422a-ae76-ee0559ebd69c	3511502	ATIVIDADES DE COORDENAÇÃO E CONTROLE DA OPERAÇÃO DA GERAÇÃO E TRANSMISSÃO DE ENERGIA ELÉTRICA	t	ELETRICIDADE E GÁS	ELETRICIDADE, GÁS E OUTRAS UTILIDADES	GERAÇÃO, TRANSMISSÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA	GERAÇÃO DE ENERGIA ELÉTRICA
08677bdc-7092-4a13-9d45-27c456863795	3512300	TRANSMISSÃO DE ENERGIA ELÉTRICA	t	ELETRICIDADE E GÁS	ELETRICIDADE, GÁS E OUTRAS UTILIDADES	GERAÇÃO, TRANSMISSÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA	TRANSMISSÃO DE ENERGIA ELÉTRICA
0f3b5d59-b6ea-41e3-985b-fab49f02d29c	3513100	COMÉRCIO ATACADISTA DE ENERGIA ELÉTRICA	t	ELETRICIDADE E GÁS	ELETRICIDADE, GÁS E OUTRAS UTILIDADES	GERAÇÃO, TRANSMISSÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA	COMÉRCIO ATACADISTA DE ENERGIA ELÉTRICA
896ed532-f815-4e5b-8ed4-56ad96150c0a	3514000	DISTRIBUIÇÃO DE ENERGIA ELÉTRICA	t	ELETRICIDADE E GÁS	ELETRICIDADE, GÁS E OUTRAS UTILIDADES	GERAÇÃO, TRANSMISSÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA	DISTRIBUIÇÃO DE ENERGIA ELÉTRICA
ea4f4f9b-849c-4d65-959d-51d09a920489	3520401	PRODUÇÃO DE GÁS; PROCESSAMENTO DE GÁS NATURAL	t	ELETRICIDADE E GÁS	ELETRICIDADE, GÁS E OUTRAS UTILIDADES	PRODUÇÃO E DISTRIBUIÇÃO DE COMBUSTÍVEIS GASOSOS POR REDES URBANAS	PRODUÇÃO DE GÁS; PROCESSAMENTO DE GÁS NATURAL; DISTRIBUIÇÃO DE COMBUSTÍVEIS GASOSOS POR REDES URBANAS
a3b6d5d1-6019-4b0d-9844-36aed6324392	3520402	DISTRIBUIÇÃO DE COMBUSTÍVEIS GASOSOS POR REDES URBANAS	t	ELETRICIDADE E GÁS	ELETRICIDADE, GÁS E OUTRAS UTILIDADES	PRODUÇÃO E DISTRIBUIÇÃO DE COMBUSTÍVEIS GASOSOS POR REDES URBANAS	PRODUÇÃO DE GÁS; PROCESSAMENTO DE GÁS NATURAL; DISTRIBUIÇÃO DE COMBUSTÍVEIS GASOSOS POR REDES URBANAS
c8361060-3a06-401d-859e-b3bcd4500755	3530100	PRODUÇÃO E DISTRIBUIÇÃO DE VAPOR, ÁGUA QUENTE E AR CONDICIONADO	t	ELETRICIDADE E GÁS	ELETRICIDADE, GÁS E OUTRAS UTILIDADES	PRODUÇÃO E DISTRIBUIÇÃO DE VAPOR, ÁGUA QUENTE E AR CONDICIONADO	PRODUÇÃO E DISTRIBUIÇÃO DE VAPOR, ÁGUA QUENTE E AR CONDICIONADO
bf117cfb-da14-449c-ad3b-65525ef594c6	3600601	CAPTAÇÃO, TRATAMENTO E DISTRIBUIÇÃO DE ÁGUA	t	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	CAPTAÇÃO, TRATAMENTO E DISTRIBUIÇÃO DE ÁGUA	CAPTAÇÃO, TRATAMENTO E DISTRIBUIÇÃO DE ÁGUA	CAPTAÇÃO, TRATAMENTO E DISTRIBUIÇÃO DE ÁGUA
42c061a8-caae-4d62-9e39-22d42c8050cb	3600602	DISTRIBUIÇÃO DE ÁGUA POR CAMINHÕES	t	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	CAPTAÇÃO, TRATAMENTO E DISTRIBUIÇÃO DE ÁGUA	CAPTAÇÃO, TRATAMENTO E DISTRIBUIÇÃO DE ÁGUA	CAPTAÇÃO, TRATAMENTO E DISTRIBUIÇÃO DE ÁGUA
e0bc3652-e4c2-437d-93ea-fb817699ab77	3701100	GESTÃO DE REDES DE ESGOTO	t	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	ESGOTO E ATIVIDADES RELACIONADAS	ESGOTO E ATIVIDADES RELACIONADAS	GESTÃO DE REDES DE ESGOTO
4cc2b8b5-a9b2-4b4e-bb42-87a7a3fa7795	3702900	ATIVIDADES RELACIONADAS A ESGOTO, EXCETO A GESTÃO DE REDES	t	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	ESGOTO E ATIVIDADES RELACIONADAS	ESGOTO E ATIVIDADES RELACIONADAS	ATIVIDADES RELACIONADAS A ESGOTO, EXCETO A GESTÃO DE REDES
b2310b8d-3743-4a56-8134-e67bc1c1e20d	3811400	COLETA DE RESÍDUOS NÃO PERIGOSOS	t	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS	COLETA DE RESÍDUOS	COLETA DE RESÍDUOS NÃO-PERIGOSOS
41f89c5e-fcdb-4b0d-bce6-eb0940195808	3812200	COLETA DE RESÍDUOS PERIGOSOS	t	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS	COLETA DE RESÍDUOS	COLETA DE RESÍDUOS PERIGOSOS
4de40ec0-3162-4a1e-b161-ea9b8acc501c	3821100	TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS NÃO PERIGOSOS	t	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS	TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS	TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS NÃO-PERIGOSOS
69a7579f-8176-4ec5-b08e-753409f400ad	3822000	TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS PERIGOSOS	t	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS	TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS	TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS PERIGOSOS
8aa66a9f-758b-40be-8829-d6ad69bb8d2a	3831901	RECUPERAÇÃO DE SUCATAS DE ALUMÍNIO	t	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS METÁLICOS
ec8bcc3d-ffb9-44c6-ad99-8b9b4b1f7e6e	3831999	RECUPERAÇÃO DE MATERIAIS METÁLICOS, EXCETO ALUMÍNIO	t	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS METÁLICOS
29361c2a-cde2-4c42-989a-b665a6adaa13	3832700	RECUPERAÇÃO DE MATERIAIS PLÁSTICOS	t	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS PLÁSTICOS
a75fc410-859a-4617-b233-b2e3a81fd512	3839401	USINAS DE COMPOSTAGEM	t	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS NÃO ESPECIFICADOS ANTERIORMENTE
99c324b5-bfaa-4bf6-9269-5f007d916fc8	3839499	RECUPERAÇÃO DE MATERIAIS NÃO ESPECIFICADOS ANTERIORMENTE	t	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS NÃO ESPECIFICADOS ANTERIORMENTE
94990a05-e6aa-4008-a86e-62c2f7b32084	3900500	DESCONTAMINAÇÃO E OUTROS SERVIÇOS DE GESTÃO DE RESÍDUOS	t	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	DESCONTAMINAÇÃO E OUTROS SERVIÇOS DE GESTÃO DE RESÍDUOS	DESCONTAMINAÇÃO E OUTROS SERVIÇOS DE GESTÃO DE RESÍDUOS	DESCONTAMINAÇÃO E OUTROS SERVIÇOS DE GESTÃO DE RESÍDUOS
e4e84fd7-5abd-4e17-8304-811e3d14528c	4110700	INCORPORAÇÃO DE EMPREENDIMENTOS IMOBILIÁRIOS	t	CONSTRUÇÃO	CONSTRUÇÃO DE EDIFÍCIOS	INCORPORAÇÃO DE EMPREENDIMENTOS IMOBILIÁRIOS	INCORPORAÇÃO DE EMPREENDIMENTOS IMOBILIÁRIOS
00defbd6-dbb9-4455-974d-0eeac7523d83	4120400	CONSTRUÇÃO DE EDIFÍCIOS	t	CONSTRUÇÃO	CONSTRUÇÃO DE EDIFÍCIOS	CONSTRUÇÃO DE EDIFÍCIOS	CONSTRUÇÃO DE EDIFÍCIOS
0b8126f8-4715-4ff5-a594-ec12ba6ad227	4211101	CONSTRUÇÃO DE RODOVIAS E FERROVIAS	t	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	CONSTRUÇÃO DE RODOVIAS, FERROVIAS, OBRAS URBANAS E OBRAS-DE-ARTE ESPECIAIS	CONSTRUÇÃO DE RODOVIAS E FERROVIAS
ec1d97d9-fc19-4e94-ac51-63a9c65e639b	4211102	PINTURA PARA SINALIZAÇÃO EM PISTAS RODOVIÁRIAS E AEROPORTOS	t	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	CONSTRUÇÃO DE RODOVIAS, FERROVIAS, OBRAS URBANAS E OBRAS-DE-ARTE ESPECIAIS	CONSTRUÇÃO DE RODOVIAS E FERROVIAS
82fc955b-8c33-4c8d-b7db-83b8d9e6750b	4212000	CONSTRUÇÃO DE OBRAS DE ARTE ESPECIAIS	t	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	CONSTRUÇÃO DE RODOVIAS, FERROVIAS, OBRAS URBANAS E OBRAS-DE-ARTE ESPECIAIS	CONSTRUÇÃO DE OBRAS-DE-ARTE ESPECIAIS
e23e7050-d81c-415c-a21b-0b3a1e1f3024	4213800	OBRAS DE URBANIZAÇÃO - RUAS, PRAÇAS E CALÇADAS	t	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	CONSTRUÇÃO DE RODOVIAS, FERROVIAS, OBRAS URBANAS E OBRAS-DE-ARTE ESPECIAIS	OBRAS DE URBANIZAÇÃO - RUAS, PRAÇAS E CALÇADAS
d73691bf-2570-4cdb-ad3d-251acf2bf9ba	4221901	CONSTRUÇÃO DE BARRAGENS E REPRESAS PARA GERAÇÃO DE ENERGIA ELÉTRICA	t	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	OBRAS DE INFRA-ESTRUTURA PARA ENERGIA ELÉTRICA, TELECOMUNICAÇÕES, ÁGUA, ESGOTO E TRANSPORTE POR DUTOS	OBRAS PARA GERAÇÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA E PARA TELECOMUNICAÇÕES
d822095a-a79b-410c-91ac-b865020cc21f	4221902	CONSTRUÇÃO DE ESTAÇÕES E REDES DE DISTRIBUIÇÃO DE ENERGIA ELÉTRICA	t	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	OBRAS DE INFRA-ESTRUTURA PARA ENERGIA ELÉTRICA, TELECOMUNICAÇÕES, ÁGUA, ESGOTO E TRANSPORTE POR DUTOS	OBRAS PARA GERAÇÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA E PARA TELECOMUNICAÇÕES
10775a5f-616f-4d80-8657-e9185a762a46	4221903	MANUTENÇÃO DE REDES DE DISTRIBUIÇÃO DE ENERGIA ELÉTRICA	t	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	OBRAS DE INFRA-ESTRUTURA PARA ENERGIA ELÉTRICA, TELECOMUNICAÇÕES, ÁGUA, ESGOTO E TRANSPORTE POR DUTOS	OBRAS PARA GERAÇÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA E PARA TELECOMUNICAÇÕES
1ec3f422-a81d-4d1f-8a10-8c59ba11bc36	4221904	CONSTRUÇÃO DE ESTAÇÕES E REDES DE TELECOMUNICAÇÕES	t	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	OBRAS DE INFRA-ESTRUTURA PARA ENERGIA ELÉTRICA, TELECOMUNICAÇÕES, ÁGUA, ESGOTO E TRANSPORTE POR DUTOS	OBRAS PARA GERAÇÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA E PARA TELECOMUNICAÇÕES
e3e5b586-dd4e-447e-8709-98a28cb2abd6	4221905	MANUTENÇÃO DE ESTAÇÕES E REDES DE TELECOMUNICAÇÕES	t	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	OBRAS DE INFRA-ESTRUTURA PARA ENERGIA ELÉTRICA, TELECOMUNICAÇÕES, ÁGUA, ESGOTO E TRANSPORTE POR DUTOS	OBRAS PARA GERAÇÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA E PARA TELECOMUNICAÇÕES
a9cb9e43-c64d-4b18-adad-3125c429456c	4222701	CONSTRUÇÃO DE REDES DE ABASTECIMENTO DE ÁGUA, COLETA DE ESGOTO E CONSTRUÇÕES CORRELATAS, EXCETO OBRAS DE IRRIGAÇÃO	t	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	OBRAS DE INFRA-ESTRUTURA PARA ENERGIA ELÉTRICA, TELECOMUNICAÇÕES, ÁGUA, ESGOTO E TRANSPORTE POR DUTOS	CONSTRUÇÃO DE REDES DE ABASTECIMENTO DE ÁGUA, COLETA DE ESGOTO E CONSTRUÇÕES CORRELATAS
1d48cbe0-0dfb-4ddc-afbf-d63315a9bf67	4222702	OBRAS DE IRRIGAÇÃO	t	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	OBRAS DE INFRA-ESTRUTURA PARA ENERGIA ELÉTRICA, TELECOMUNICAÇÕES, ÁGUA, ESGOTO E TRANSPORTE POR DUTOS	CONSTRUÇÃO DE REDES DE ABASTECIMENTO DE ÁGUA, COLETA DE ESGOTO E CONSTRUÇÕES CORRELATAS
d2e385f0-5bde-477f-886e-611610ba3de9	4223500	CONSTRUÇÃO DE REDES DE TRANSPORTES POR DUTOS, EXCETO PARA ÁGUA E ESGOTO	t	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	OBRAS DE INFRA-ESTRUTURA PARA ENERGIA ELÉTRICA, TELECOMUNICAÇÕES, ÁGUA, ESGOTO E TRANSPORTE POR DUTOS	CONSTRUÇÃO DE REDES DE TRANSPORTES POR DUTOS, EXCETO PARA ÁGUA E ESGOTO
7ca514c3-eb78-46d4-bfed-f741834ec472	4291000	OBRAS PORTUÁRIAS, MARÍTIMAS E FLUVIAIS	t	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	CONSTRUÇÃO DE OUTRAS OBRAS DE INFRA-ESTRUTURA	OBRAS PORTUÁRIAS, MARÍTIMAS E FLUVIAIS
99269277-c277-492e-94dc-41eea076833f	4292801	MONTAGEM DE ESTRUTURAS METÁLICAS	t	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	CONSTRUÇÃO DE OUTRAS OBRAS DE INFRA-ESTRUTURA	MONTAGEM DE INSTALAÇÕES INDUSTRIAIS E DE ESTRUTURAS METÁLICAS
146c2293-ab96-4d45-ba17-c31317900ecf	4292802	OBRAS DE MONTAGEM INDUSTRIAL	t	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	CONSTRUÇÃO DE OUTRAS OBRAS DE INFRA-ESTRUTURA	MONTAGEM DE INSTALAÇÕES INDUSTRIAIS E DE ESTRUTURAS METÁLICAS
7a9d12b8-5486-4c37-9a6f-c2f1db8e4148	4299501	CONSTRUÇÃO DE INSTALAÇÕES ESPORTIVAS E RECREATIVAS	t	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	CONSTRUÇÃO DE OUTRAS OBRAS DE INFRA-ESTRUTURA	OBRAS DE ENGENHARIA CIVIL NÃO ESPECIFICADAS ANTERIORMENTE
06fcbc77-6d83-48fe-b4dd-8a4105685dcd	4299599	OUTRAS OBRAS DE ENGENHARIA CIVIL NÃO ESPECIFICADAS ANTERIORMENTE	t	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	CONSTRUÇÃO DE OUTRAS OBRAS DE INFRA-ESTRUTURA	OBRAS DE ENGENHARIA CIVIL NÃO ESPECIFICADAS ANTERIORMENTE
0cd66cb8-61f8-4a60-8c66-3d171b9bca45	4311801	DEMOLIÇÃO DE EDIFÍCIOS E OUTRAS ESTRUTURAS	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	DEMOLIÇÃO E PREPARAÇÃO DO TERRENO	DEMOLIÇÃO E PREPARAÇÃO DE CANTEIROS DE OBRAS
a2949da7-950e-4046-a1ce-ea53d56cde4f	4311802	PREPARAÇÃO DE CANTEIRO E LIMPEZA DE TERRENO	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	DEMOLIÇÃO E PREPARAÇÃO DO TERRENO	DEMOLIÇÃO E PREPARAÇÃO DE CANTEIROS DE OBRAS
01823f00-bbab-4a8c-8ab7-c72924314947	4312600	PERFURAÇÕES E SONDAGENS	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	DEMOLIÇÃO E PREPARAÇÃO DO TERRENO	PERFURAÇÕES E SONDAGENS
1924da5a-95a6-44d5-8fea-83951c843979	4313400	OBRAS DE TERRAPLENAGEM	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	DEMOLIÇÃO E PREPARAÇÃO DO TERRENO	OBRAS DE TERRAPLENAGEM
af795999-06b1-4743-9392-93f89931fc3e	4319300	SERVIÇOS DE PREPARAÇÃO DO TERRENO NÃO ESPECIFICADOS ANTERIORMENTE	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	DEMOLIÇÃO E PREPARAÇÃO DO TERRENO	SERVIÇOS DE PREPARAÇÃO DO TERRENO NÃO ESPECIFICADOS ANTERIORMENTE
159d1266-ebdd-4b82-8cee-69cb20f07e33	4321500	INSTALAÇÃO E MANUTENÇÃO ELÉTRICA	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	INSTALAÇÕES ELÉTRICAS
1ff28a36-4bfc-4fca-8316-6f56efce8fd2	4322301	INSTALAÇÕES HIDRÁULICAS, SANITÁRIAS E DE GÁS	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	INSTALAÇÕES HIDRÁULICAS, DE SISTEMAS DE VENTILAÇÃO E REFRIGERAÇÃO
2da052fb-1fdf-4a9d-bbbb-92c3f564acbe	4322302	INSTALAÇÃO E MANUTENÇÃO DE SISTEMAS CENTRAIS DE AR CONDICIONADO, DE VENTILAÇÃO E REFRIGERAÇÃO	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	INSTALAÇÕES HIDRÁULICAS, DE SISTEMAS DE VENTILAÇÃO E REFRIGERAÇÃO
529bbb83-fa1b-47cf-892d-285279e623f8	4322303	INSTALAÇÕES DE SISTEMA DE PREVENÇÃO CONTRA INCÊNDIO	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	INSTALAÇÕES HIDRÁULICAS, DE SISTEMAS DE VENTILAÇÃO E REFRIGERAÇÃO
16e2bf3e-0a38-46e7-8b52-1126e100522b	4329101	INSTALAÇÃO DE PAINÉIS PUBLICITÁRIOS	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	OBRAS DE INSTALAÇÕES EM CONSTRUÇÕES NÃO ESPECIFICADAS ANTERIORMENTE
ad87fc4d-7769-4bd6-ba0d-8658e62eb60c	4329102	INSTALAÇÃO DE EQUIPAMENTOS PARA ORIENTAÇÃO À NAVEGAÇÃO MARÍTIMA FLUVIAL E LACUSTRE	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	OBRAS DE INSTALAÇÕES EM CONSTRUÇÕES NÃO ESPECIFICADAS ANTERIORMENTE
ca60f057-08a8-4209-9b93-bbb0f9b3fab3	4329103	INSTALAÇÃO, MANUTENÇÃO E REPARAÇÃO DE ELEVADORES, ESCADAS E ESTEIRAS ROLANTES	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	OBRAS DE INSTALAÇÕES EM CONSTRUÇÕES NÃO ESPECIFICADAS ANTERIORMENTE
f06dcc84-b698-4b66-8241-73d9a05872cb	4329104	MONTAGEM E INSTALAÇÃO DE SISTEMAS E EQUIPAMENTOS DE ILUMINAÇÃO E SINALIZAÇÃO EM VIAS PÚBLICAS, PORTOS E AEROPORTOS	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	OBRAS DE INSTALAÇÕES EM CONSTRUÇÕES NÃO ESPECIFICADAS ANTERIORMENTE
e4b5862b-51f9-4950-b5af-a37080504dce	4329105	TRATAMENTOS TÉRMICOS, ACÚSTICOS OU DE VIBRAÇÃO	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	OBRAS DE INSTALAÇÕES EM CONSTRUÇÕES NÃO ESPECIFICADAS ANTERIORMENTE
cad96df0-4c3f-4c33-9708-ddecfd46f441	4329199	OUTRAS OBRAS DE INSTALAÇÕES EM CONSTRUÇÕES NÃO ESPECIFICADAS ANTERIORMENTE	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	OBRAS DE INSTALAÇÕES EM CONSTRUÇÕES NÃO ESPECIFICADAS ANTERIORMENTE
ea454c15-7a73-45a9-b15d-4ecd8262bd73	4330401	IMPERMEABILIZAÇÃO EM OBRAS DE ENGENHARIA CIVIL	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OBRAS DE ACABAMENTO	OBRAS DE ACABAMENTO
d595b9e3-171b-4f67-8697-8284ff186ad2	4330402	INSTALAÇÃO DE PORTAS, JANELAS, TETOS, DIVISÓRIAS E ARMÁRIOS EMBUTIDOS DE QUALQUER MATERIAL	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OBRAS DE ACABAMENTO	OBRAS DE ACABAMENTO
359f2724-6962-413e-bff0-2173a284a9f5	4330403	OBRAS DE ACABAMENTO EM GESSO E ESTUQUE	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OBRAS DE ACABAMENTO	OBRAS DE ACABAMENTO
d1a88223-da96-4af3-a7f2-240f63ac28ba	4330404	SERVIÇOS DE PINTURA DE EDIFÍCIOS EM GERAL	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OBRAS DE ACABAMENTO	OBRAS DE ACABAMENTO
5ba653f6-a57b-4bec-b312-2cf535fdc207	4330405	APLICAÇÃO DE REVESTIMENTOS E DE RESINAS EM INTERIORES E EXTERIORES	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OBRAS DE ACABAMENTO	OBRAS DE ACABAMENTO
892ffa14-0cfa-4443-aef5-423ac584c58c	4330499	OUTRAS OBRAS DE ACABAMENTO DA CONSTRUÇÃO	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OBRAS DE ACABAMENTO	OBRAS DE ACABAMENTO
864a6220-5229-4d28-83de-8aad98880a00	4391600	OBRAS DE FUNDAÇÕES	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OUTROS SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OBRAS DE FUNDAÇÕES
12fa4822-0a87-4713-9f20-239f77c944b5	4399101	ADMINISTRAÇÃO DE OBRAS	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OUTROS SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE
4a90dc06-b0de-4642-a857-1ca20ecbed46	4399102	MONTAGEM E DESMONTAGEM DE ANDAIMES E OUTRAS ESTRUTURAS TEMPORÁRIAS	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OUTROS SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE
f868fc32-0e22-4b70-ac61-17afc0528acc	4399103	OBRAS DE ALVENARIA	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OUTROS SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE
442619f5-d015-4530-a3fc-13ff2d30329e	4399104	SERVIÇOS DE OPERAÇÃO E FORNECIMENTO DE EQUIPAMENTOS PARA TRANSPORTE E ELEVAÇÃO DE CARGAS E PESSOAS PARA USO EM OBRAS	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OUTROS SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE
6353391b-3e63-4793-880c-13fb73c5f257	4399105	PERFURAÇÃO E CONSTRUÇÃO DE POÇOS DE ÁGUA	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OUTROS SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE
6e5efda8-4b0e-4087-9e55-d979656b6881	4399199	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE	t	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OUTROS SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE
e80a0dd6-e888-4bc2-99e4-d8f61cbbf496	4511101	COMÉRCIO A VAREJO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS NOVOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE VEÍCULOS AUTOMOTORES	COMÉRCIO A VAREJO E POR ATACADO DE VEÍCULOS AUTOMOTORES
db87300c-2475-48f4-be41-1005bc2e0b9a	4511102	COMÉRCIO A VAREJO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS USADOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE VEÍCULOS AUTOMOTORES	COMÉRCIO A VAREJO E POR ATACADO DE VEÍCULOS AUTOMOTORES
a4faa3e2-e294-4d55-99e3-f6c6b6a16952	4511103	COMÉRCIO POR ATACADO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS NOVOS E USADOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE VEÍCULOS AUTOMOTORES	COMÉRCIO A VAREJO E POR ATACADO DE VEÍCULOS AUTOMOTORES
b7a86c84-68ff-4f52-9b63-b0a7b7a53465	4511104	COMÉRCIO POR ATACADO DE CAMINHÕES NOVOS E USADOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE VEÍCULOS AUTOMOTORES	COMÉRCIO A VAREJO E POR ATACADO DE VEÍCULOS AUTOMOTORES
9b56afd1-80be-4e5b-9ec6-603057f46443	4511105	COMÉRCIO POR ATACADO DE REBOQUES E SEMI REBOQUES NOVOS E USADOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE VEÍCULOS AUTOMOTORES	COMÉRCIO A VAREJO E POR ATACADO DE VEÍCULOS AUTOMOTORES
99c7ead3-90a0-46c2-8b5a-6e5851aeb51b	4511106	COMÉRCIO POR ATACADO DE ÔNIBUS E MICROÔNIBUS NOVOS E USADOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE VEÍCULOS AUTOMOTORES	COMÉRCIO A VAREJO E POR ATACADO DE VEÍCULOS AUTOMOTORES
5d38180f-71c6-4c10-b38e-ed248e70298b	4512901	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE VEÍCULOS AUTOMOTORES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE VEÍCULOS AUTOMOTORES	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE VEÍCULOS AUTOMOTORES
2140ad34-1f3e-4e9d-b31b-c90438b29953	4512902	COMÉRCIO SOB CONSIGNAÇÃO DE VEÍCULOS AUTOMOTORES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE VEÍCULOS AUTOMOTORES	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE VEÍCULOS AUTOMOTORES
dc6c786d-04e0-441f-862c-60b273d4c61b	4520001	SERVIÇOS DE MANUTENÇÃO E REPARAÇÃO MECÂNICA DE VEÍCULOS AUTOMOTORES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES
d984b887-8f06-41aa-9fe0-38b869a0f5d9	4520002	SERVIÇOS DE LANTERNAGEM OU FUNILARIA E PINTURA DE VEÍCULOS AUTOMOTORES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES
431b543f-218e-40c7-86b0-7a7173196ed6	4520003	SERVIÇOS DE MANUTENÇÃO E REPARAÇÃO ELÉTRICA DE VEÍCULOS AUTOMOTORES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES
574f5a08-08ab-4245-a793-faaa473a2c95	4520004	SERVIÇOS DE ALINHAMENTO E BALANCEAMENTO DE VEÍCULOS AUTOMOTORES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES
d5c750cb-f11f-4672-b398-593266b3275c	4520005	SERVIÇOS DE LAVAGEM, LUBRIFICAÇÃO E POLIMENTO DE VEÍCULOS AUTOMOTORES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES
07ea6db5-930e-4381-81e1-8c551f7ca09a	4520006	SERVIÇOS DE BORRACHARIA PARA VEÍCULOS AUTOMOTORES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES
6e081800-bd74-46ec-978d-e376325697c4	4520007	SERVIÇOS DE INSTALAÇÃO, MANUTENÇÃO E REPARAÇÃO DE ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES
f656b1f5-f727-4269-b46e-b960409532c0	4520008	SERVIÇOS DE CAPOTARIA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES
65b83329-c518-4ad1-9bef-d6bc9ab23fff	4530701	COMÉRCIO POR ATACADO DE PEÇAS E ACESSÓRIOS NOVOS PARA VEÍCULOS AUTOMOTORES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES
4bfc4627-c804-464b-9bb3-724463f1e848	4530702	COMÉRCIO POR ATACADO DE PNEUMÁTICOS E CÂMARAS DE AR	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES
2ddd3a13-be51-483f-964c-b177cc966eee	4530703	COMÉRCIO A VAREJO DE PEÇAS E ACESSÓRIOS NOVOS PARA VEÍCULOS AUTOMOTORES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES
bf1b8521-43dd-4fec-ae39-f079fede1815	4530704	COMÉRCIO A VAREJO DE PEÇAS E ACESSÓRIOS USADOS PARA VEÍCULOS AUTOMOTORES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES
cb03d0dc-0d3d-44a0-8c2c-96a81555eb09	4530705	COMÉRCIO A VAREJO DE PNEUMÁTICOS E CÂMARAS DE AR	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES
59b12ba0-8c89-4aa8-9141-d93e75e91dc4	4530706	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE PEÇAS E ACESSÓRIOS NOVOS E USADOS PARA VEÍCULOS AUTOMOTORES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES
c22e5b90-1816-4fcb-98ca-a760db9a25ee	4541201	COMÉRCIO POR ATACADO DE MOTOCICLETAS E MOTONETAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS	COMÉRCIO POR ATACADO E A VAREJO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
97792c39-8b63-4444-be98-3ef72c1fcd2e	4541202	COMÉRCIO POR ATACADO DE PEÇAS E ACESSÓRIOS PARA MOTOCICLETAS E MOTONETAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS	COMÉRCIO POR ATACADO E A VAREJO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
a98a208f-b03e-4b11-b16a-ce30d08bb6ca	4541203	COMÉRCIO A VAREJO DE MOTOCICLETAS E MOTONETAS NOVAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS	COMÉRCIO POR ATACADO E A VAREJO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
62ef7aef-691e-43a4-9603-8911358b87ff	4541204	COMÉRCIO A VAREJO DE MOTOCICLETAS E MOTONETAS USADAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS	COMÉRCIO POR ATACADO E A VAREJO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
b9cd3698-3bec-476d-839c-efabf73d4cac	4541206	COMÉRCIO A VAREJO DE PEÇAS E ACESSÓRIOS NOVOS PARA MOTOCICLETAS E MOTONETAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS	COMÉRCIO POR ATACADO E A VAREJO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
d3548c42-598e-41a9-a91f-99a726c5bf0e	4541207	COMÉRCIO A VAREJO DE PEÇAS E ACESSÓRIOS USADOS PARA MOTOCICLETAS E MOTONETAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS	COMÉRCIO POR ATACADO E A VAREJO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
3d57bc25-90ea-4a8a-9fa2-7147e7deebcb	4542101	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MOTOCICLETAS E MOTONETAS, PEÇAS E ACESSÓRIOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
3066099d-be56-4543-9389-29ea65bd1cfd	4542102	COMÉRCIO SOB CONSIGNAÇÃO DE MOTOCICLETAS E MOTONETAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
8df55fe8-0a34-477b-ba15-aa738a597b50	4543900	MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS E MOTONETAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS	MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS
47a0d7b2-5d82-407e-81bc-e70e3e29bd58	4611700	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MATÉRIAS PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS
28607dc1-1cc6-4912-abe1-be427d5694bc	4612500	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE COMBUSTÍVEIS, MINERAIS, PRODUTOS SIDERÚRGICOS E QUÍMICOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE COMBUSTÍVEIS, MINERAIS, PRODUTOS SIDERÚRGICOS E QUÍMICOS
854cd3d4-0da4-491b-a3ef-22c50297d475	4613300	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MADEIRA, MATERIAL DE CONSTRUÇÃO E FERRAGENS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MADEIRA, MATERIAL DE CONSTRUÇÃO E FERRAGENS
e9357cff-1f73-468f-b0ed-b3cb1310cdda	4614100	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MÁQUINAS, EQUIPAMENTOS, EMBARCAÇÕES E AERONAVES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MÁQUINAS, EQUIPAMENTOS, EMBARCAÇÕES E AERONAVES
f2b7e3ca-63bd-4a60-8dae-7ef905503f31	4615000	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE ELETRODOMÉSTICOS, MÓVEIS E ARTIGOS DE USO DOMÉSTICO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE ELETRODOMÉSTICOS, MÓVEIS E ARTIGOS DE USO DOMÉSTICO
3195831d-cf72-427c-84bf-3f30c528df42	4616800	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE TÊXTEIS, VESTUÁRIO, CALÇADOS E ARTIGOS DE VIAGEM	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE TÊXTEIS, VESTUÁRIO, CALÇADOS E ARTIGOS DE VIAGEM
03754776-cbe3-4172-8190-6f0758674c32	4617600	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO
a922f203-0c0c-4e74-ad79-4666c8d61576	4618401	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MEDICAMENTOS, COSMÉTICOS E PRODUTOS DE PERFUMARIA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO ESPECIALIZADO EM PRODUTOS NÃO ESPECIFICADOS ANTERIORMENTE
fb3157ef-7f31-44e5-9641-eb87d005adbc	4618402	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE INSTRUMENTOS E MATERIAIS ODONTO MÉDICO HOSPITALARES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO ESPECIALIZADO EM PRODUTOS NÃO ESPECIFICADOS ANTERIORMENTE
aaa8eb19-d75b-4ee3-a9ed-d69bf4585855	4618403	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE JORNAIS, REVISTAS E OUTRAS PUBLICAÇÕES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO ESPECIALIZADO EM PRODUTOS NÃO ESPECIFICADOS ANTERIORMENTE
76d844a1-f551-476a-80ad-b5be3dcce89f	4618499	OUTROS REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO ESPECIALIZADO EM PRODUTOS NÃO ESPECIFICADOS ANTERIORMENTE	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO ESPECIALIZADO EM PRODUTOS NÃO ESPECIFICADOS ANTERIORMENTE
ad55eed6-5ac5-4a26-931d-3368102ddc31	4619200	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MERCADORIAS EM GERAL NÃO ESPECIALIZADO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MERCADORIAS EM GERAL NÃO ESPECIALIZADO
bf42ba15-adbc-4d2f-b875-bb59778db33c	4621400	COMÉRCIO ATACADISTA DE CAFÉ EM GRÃO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE CAFÉ EM GRÃO
8bf1fa98-7602-4c7c-983d-be9c5d121598	4622200	COMÉRCIO ATACADISTA DE SOJA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE SOJA
c0beb2d2-3712-43bf-a13a-5819f3052a0e	4623101	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
e20d2c2d-7ee5-44ff-a735-32dbde12c98b	4623102	COMÉRCIO ATACADISTA DE COUROS, LÃS, PELES E OUTROS SUBPRODUTOS NÃO COMESTÍVEIS DE ORIGEM ANIMAL	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
64a10b77-196f-4ccb-b29d-ddf0215d4285	4623103	COMÉRCIO ATACADISTA DE ALGODÃO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
e905f914-473d-48fb-852b-b9393ad82144	4623104	COMÉRCIO ATACADISTA DE FUMO EM FOLHA NÃO BENEFICIADO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
45c47db7-ca5f-4ab8-ba32-fdfa48658a82	4623105	COMÉRCIO ATACADISTA DE CACAU	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
b7218d21-7989-4442-ad7c-460cef02fb09	4623106	COMÉRCIO ATACADISTA DE SEMENTES, FLORES, PLANTAS E GRAMAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
22a19d20-8422-412e-b570-7ae40df75025	4623107	COMÉRCIO ATACADISTA DE SISAL	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
5063bc68-0e6f-40e1-bb82-b0b04febd8d2	4623108	COMÉRCIO ATACADISTA DE MATÉRIAS PRIMAS AGRÍCOLAS COM ATIVIDADE DE FRACIONAMENTO E ACONDICIONAMENTO ASSOCIADA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
6adb6e94-022b-458d-803f-2103a4a0f6d1	4623109	COMÉRCIO ATACADISTA DE ALIMENTOS PARA ANIMAIS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
b23cfd71-1cd3-41b0-bc58-c851846c14e2	4623199	COMÉRCIO ATACADISTA DE MATÉRIAS PRIMAS AGRÍCOLAS NÃO ESPECIFICADAS ANTERIORMENTE	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
9f30a86a-91ce-4ef4-b0e0-ee593ebdf650	4631100	COMÉRCIO ATACADISTA DE LEITE E LATICÍNIOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE LEITE E LATICÍNIOS
a7453499-cecf-4e15-bc5f-c6d0c060b146	4632001	COMÉRCIO ATACADISTA DE CEREAIS E LEGUMINOSAS BENEFICIADOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE CEREAIS E LEGUMINOSAS BENEFICIADOS, FARINHAS, AMIDOS E FÉCULAS
a8502149-b6d3-4a17-a623-66e8ce2daf93	4632002	COMÉRCIO ATACADISTA DE FARINHAS, AMIDOS E FÉCULAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE CEREAIS E LEGUMINOSAS BENEFICIADOS, FARINHAS, AMIDOS E FÉCULAS
9cbb504e-8bf3-4a60-a0ce-b57b3177b0b7	4632003	COMÉRCIO ATACADISTA DE CEREAIS E LEGUMINOSAS BENEFICIADOS, FARINHAS, AMIDOS E FÉCULAS, COM ATIVIDADE DE FRACIONAMENTO E ACONDICIONAMENTO ASSOCIADA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE CEREAIS E LEGUMINOSAS BENEFICIADOS, FARINHAS, AMIDOS E FÉCULAS
7389fe8a-d381-4397-85b4-5eec8fae1565	4633801	COMÉRCIO ATACADISTA DE FRUTAS, VERDURAS, RAÍZES, TUBÉRCULOS, HORTALIÇAS E LEGUMES FRESCOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE HORTIFRUTIGRANJEIROS
f234d21f-3831-4aaf-99a6-0db4fd4b8dfa	4633802	COMÉRCIO ATACADISTA DE AVES VIVAS E OVOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE HORTIFRUTIGRANJEIROS
5b2a03f3-fec5-4d1e-80bf-a530b0e47dc1	4633803	COMÉRCIO ATACADISTA DE COELHOS E OUTROS PEQUENOS ANIMAIS VIVOS PARA ALIMENTAÇÃO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE HORTIFRUTIGRANJEIROS
6a79a4f4-2fec-4874-8231-ad0ee5222247	4634601	COMÉRCIO ATACADISTA DE CARNES BOVINAS E SUÍNAS E DERIVADOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE CARNES, PRODUTOS DA CARNE E PESCADO
7c328979-0481-44c9-989c-05c24b2e47ec	4634602	COMÉRCIO ATACADISTA DE AVES ABATIDAS E DERIVADOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE CARNES, PRODUTOS DA CARNE E PESCADO
160a1d75-8b69-4bb5-8847-1f8a7edf1168	4634603	COMÉRCIO ATACADISTA DE PESCADOS E FRUTOS DO MAR	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE CARNES, PRODUTOS DA CARNE E PESCADO
bb90d179-f830-43d1-92f3-2add58c079a0	4634699	COMÉRCIO ATACADISTA DE CARNES E DERIVADOS DE OUTROS ANIMAIS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE CARNES, PRODUTOS DA CARNE E PESCADO
dd3b9502-516b-4f4a-b984-d60a823bf382	4635401	COMÉRCIO ATACADISTA DE ÁGUA MINERAL	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE BEBIDAS
86f44d38-3929-49dd-91c1-ac3b8405d3cc	4635402	COMÉRCIO ATACADISTA DE CERVEJA, CHOPE E REFRIGERANTE	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE BEBIDAS
97f29d2a-3e48-48ca-af68-58497972a076	4635403	COMÉRCIO ATACADISTA DE BEBIDAS COM ATIVIDADE DE FRACIONAMENTO E ACONDICIONAMENTO ASSOCIADA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE BEBIDAS
11676517-a96a-47b1-b9b7-11c48fb9927f	4635499	COMÉRCIO ATACADISTA DE BEBIDAS NÃO ESPECIFICADAS ANTERIORMENTE	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE BEBIDAS
de5370c3-2c01-43b4-9b9f-5b952e0ba634	4636201	COMÉRCIO ATACADISTA DE FUMO BENEFICIADO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE PRODUTOS DO FUMO
7fb274b6-d3ab-4a4d-8dff-f1e2217c147c	4636202	COMÉRCIO ATACADISTA DE CIGARROS, CIGARRILHAS E CHARUTOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE PRODUTOS DO FUMO
c888e6e0-c345-4fd1-bfb1-40bd2e3f32b5	4637101	COMÉRCIO ATACADISTA DE CAFÉ TORRADO, MOÍDO E SOLÚVEL	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
0f4a0b11-986f-4c9a-b2e3-118037badb52	4637102	COMÉRCIO ATACADISTA DE AÇÚCAR	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
cabd36fb-1951-49b5-b7f3-e26e30c3733b	4637103	COMÉRCIO ATACADISTA DE ÓLEOS E GORDURAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
81a8a24c-8e21-4131-a1c6-f257b1af5bad	4637104	COMÉRCIO ATACADISTA DE PÃES, BOLOS, BISCOITOS E SIMILARES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
43f99299-3ad3-4a4d-b137-8ff8f2b21be1	4637105	COMÉRCIO ATACADISTA DE MASSAS ALIMENTÍCIAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
075a6499-196b-49cf-b776-fd73a24cdfd9	4637106	COMÉRCIO ATACADISTA DE SORVETES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
9c845f7b-4c02-41e0-8443-71701edc92b3	4637107	COMÉRCIO ATACADISTA DE CHOCOLATES, CONFEITOS, BALAS, BOMBONS E SEMELHANTES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
82d82169-55de-4802-be57-9b95f60abe4a	4637199	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
c0d3f377-b32a-4180-8b68-216b6ff68069	4639701	COMÉRCIO ATACADISTA DE PRODUTOS ALIMENTÍCIOS EM GERAL	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE PRODUTOS ALIMENTÍCIOS EM GERAL
15d57545-8da0-4a56-ba4f-4af3d79fad99	4639702	COMÉRCIO ATACADISTA DE PRODUTOS ALIMENTÍCIOS EM GERAL, COM ATIVIDADE DE FRACIONAMENTO E ACONDICIONAMENTO ASSOCIADA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE PRODUTOS ALIMENTÍCIOS EM GERAL
7778a526-ad1c-4649-a5b8-4cf9c7510862	4641901	COMÉRCIO ATACADISTA DE TECIDOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE TECIDOS, ARTEFATOS DE TECIDOS E DE ARMARINHO
fc03ada9-67a1-4b79-8611-1afe0ea1c4f0	4641902	COMÉRCIO ATACADISTA DE ARTIGOS DE CAMA, MESA E BANHO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE TECIDOS, ARTEFATOS DE TECIDOS E DE ARMARINHO
fbca6e02-8cf8-4dd0-b826-b3d8944774bf	4641903	COMÉRCIO ATACADISTA DE ARTIGOS DE ARMARINHO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE TECIDOS, ARTEFATOS DE TECIDOS E DE ARMARINHO
10ef8d68-2ee7-4a7f-80a4-a7b8b270486c	4642701	COMÉRCIO ATACADISTA DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS, EXCETO PROFISSIONAIS E DE SEGURANÇA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS
cb3a3230-f6a6-470d-92c8-b3b9a8809755	4642702	COMÉRCIO ATACADISTA DE ROUPAS E ACESSÓRIOS PARA USO PROFISSIONAL E DE SEGURANÇA DO TRABALHO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS
bc40fe9e-e099-463a-9c8a-ae5069e87814	4643501	COMÉRCIO ATACADISTA DE CALÇADOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE CALÇADOS E ARTIGOS DE VIAGEM
c08cfaa8-5407-4381-8743-c801c539b4f1	4643502	COMÉRCIO ATACADISTA DE BOLSAS, MALAS E ARTIGOS DE VIAGEM	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE CALÇADOS E ARTIGOS DE VIAGEM
66066f36-fc93-4f3a-bdfc-149d4bf4c6e1	4644301	COMÉRCIO ATACADISTA DE MEDICAMENTOS E DROGAS DE USO HUMANO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE PRODUTOS FARMACÊUTICOS PARA USO HUMANO E VETERINÁRIO
3cba1577-8e78-4d8e-b5ec-2e840a9a2e1d	4644302	COMÉRCIO ATACADISTA DE MEDICAMENTOS E DROGAS DE USO VETERINÁRIO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE PRODUTOS FARMACÊUTICOS PARA USO HUMANO E VETERINÁRIO
b7a76722-82a8-4ccc-9afb-0b396df22510	4645101	COMÉRCIO ATACADISTA DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO, CIRÚRGICO, HOSPITALAR E DE LABORATÓRIOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO, CIRÚRGICO, ORTOPÉDICO E ODONTOLÓGICO
596adf1b-e706-4842-9b9d-b2829ea7e9e0	4645102	COMÉRCIO ATACADISTA DE PRÓTESES E ARTIGOS DE ORTOPEDIA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO, CIRÚRGICO, ORTOPÉDICO E ODONTOLÓGICO
3f07ebc5-7730-4d2d-aca6-a0a17c639e2d	4645103	COMÉRCIO ATACADISTA DE PRODUTOS ODONTOLÓGICOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO, CIRÚRGICO, ORTOPÉDICO E ODONTOLÓGICO
5dcc9429-478c-459f-94c3-e19fccfbc295	4646001	COMÉRCIO ATACADISTA DE COSMÉTICOS E PRODUTOS DE PERFUMARIA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL
d1d69b0b-d15e-4508-b5d5-3167ce6a2ff2	4646002	COMÉRCIO ATACADISTA DE PRODUTOS DE HIGIENE PESSOAL	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL
24176dc3-82fe-457c-9058-d607c8b93a36	4647801	COMÉRCIO ATACADISTA DE ARTIGOS DE ESCRITÓRIO E DE PAPELARIA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE ARTIGOS DE ESCRITÓRIO E DE PAPELARIA; LIVROS, JORNAIS E OUTRAS PUBLICAÇÕES
1dd6a8f7-e0d8-40c6-aa4f-2e33b71d27f8	4647802	COMÉRCIO ATACADISTA DE LIVROS, JORNAIS E OUTRAS PUBLICAÇÕES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE ARTIGOS DE ESCRITÓRIO E DE PAPELARIA; LIVROS, JORNAIS E OUTRAS PUBLICAÇÕES
2998163d-7a70-4031-abe2-b4cd4cadd04a	4649401	COMÉRCIO ATACADISTA DE EQUIPAMENTOS ELÉTRICOS DE USO PESSOAL E DOMÉSTICO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
9124d7f6-2352-4f87-9276-92cb3be45a6f	4649402	COMÉRCIO ATACADISTA DE APARELHOS ELETRÔNICOS DE USO PESSOAL E DOMÉSTICO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
3dfd74e3-f757-427f-8a08-0dd7ed42c7e3	4649403	COMÉRCIO ATACADISTA DE BICICLETAS, TRICICLOS E OUTROS VEÍCULOS RECREATIVOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
927b2bc8-4a20-45db-bcb9-8d9a8ed6b82c	4649404	COMÉRCIO ATACADISTA DE MÓVEIS E ARTIGOS DE COLCHOARIA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
ca90385f-5388-4f62-9879-c0f10829f2cb	4649405	COMÉRCIO ATACADISTA DE ARTIGOS DE TAPEÇARIA; PERSIANAS E CORTINAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
94a0eb2b-a7e0-4664-9718-aaea9ce0d596	4649406	COMÉRCIO ATACADISTA DE LUSTRES, LUMINÁRIAS E ABAJURES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
1e962b48-9ba4-4a66-afc2-aa963fb410f9	4649407	COMÉRCIO ATACADISTA DE FILMES, CDS, DVDS, FITAS E DISCOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
58526fd2-7e11-430c-a11b-791b17be923f	4649408	COMÉRCIO ATACADISTA DE PRODUTOS DE HIGIENE, LIMPEZA E CONSERVAÇÃO DOMICILIAR	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
de554954-f62a-46e7-9cd6-69932b28eda8	4649409	COMÉRCIO ATACADISTA DE PRODUTOS DE HIGIENE, LIMPEZA E CONSERVAÇÃO DOMICILIAR, COM ATIVIDADE DE FRACIONAMENTO E ACONDICIONAMENTO ASSOCIADA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
fdb72302-595c-4a29-8d66-81d833604d03	4649410	COMÉRCIO ATACADISTA DE JÓIAS, RELÓGIOS E BIJUTERIAS, INCLUSIVE PEDRAS PRECIOSAS E SEMIPRECIOSAS LAPIDADAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
0e428b03-b0b6-4bfd-8f8f-8d4796151028	4649499	COMÉRCIO ATACADISTA DE OUTROS EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
0c0d0d4d-8418-49ea-b3a5-006c38ffab8f	4651601	COMÉRCIO ATACADISTA DE EQUIPAMENTOS DE INFORMÁTICA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E PRODUTOS DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE COMPUTADORES, PERIFÉRICOS E SUPRIMENTOS DE INFORMÁTICA
125a7baf-98ca-408a-a72f-3cf82c011ad8	4651602	COMÉRCIO ATACADISTA DE SUPRIMENTOS PARA INFORMÁTICA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E PRODUTOS DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE COMPUTADORES, PERIFÉRICOS E SUPRIMENTOS DE INFORMÁTICA
72b0950e-ba7b-45e5-a0ad-7bc98fe63eda	4652400	COMÉRCIO ATACADISTA DE COMPONENTES ELETRÔNICOS E EQUIPAMENTOS DE TELEFONIA E COMUNICAÇÃO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E PRODUTOS DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE COMPONENTES ELETRÔNICOS E EQUIPAMENTOS DE TELEFONIA E COMUNICAÇÃO
7fdf8872-6d29-449a-bf96-72f3d188e63a	4661300	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS PARA USO AGROPECUÁRIO; PARTES E PEÇAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS, EXCETO DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS PARA USO AGROPECUÁRIO; PARTES E PEÇAS
ed5e4d4c-7592-49c3-ad7a-bf661514e9bc	4662100	COMÉRCIO ATACADISTA DE MÁQUINAS, EQUIPAMENTOS PARA TERRAPLENAGEM, MINERAÇÃO E CONSTRUÇÃO; PARTES E PEÇAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS, EXCETO DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE MÁQUINAS, EQUIPAMENTOS PARA TERRAPLENAGEM, MINERAÇÃO E CONSTRUÇÃO; PARTES E PEÇAS
2dba05b9-4e65-4571-9bd9-2049d4afa199	4663000	COMÉRCIO ATACADISTA DE MÁQUINAS E EQUIPAMENTOS PARA USO INDUSTRIAL; PARTES E PEÇAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS, EXCETO DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE MÁQUINAS E EQUIPAMENTOS PARA USO INDUSTRIAL; PARTES E PEÇAS
13046eab-e4c8-40b8-913a-bc0ed02994b4	4664800	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS PARA USO ODONTO MÉDICO HOSPITALAR; PARTES E PEÇAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS, EXCETO DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS PARA USO ODONTO-MÉDICO-HOSPITALAR; PARTES E PEÇAS
a65f6bc2-80a7-4364-b79e-0027a3dd7efa	4665600	COMÉRCIO ATACADISTA DE MÁQUINAS E EQUIPAMENTOS PARA USO COMERCIAL; PARTES E PEÇAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS, EXCETO DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE MÁQUINAS E EQUIPAMENTOS PARA USO COMERCIAL; PARTES E PEÇAS
70eb20ad-99aa-4e4e-8fa8-4a8e8f9035ba	4669901	COMÉRCIO ATACADISTA DE BOMBAS E COMPRESSORES; PARTES E PEÇAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS, EXCETO DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE; PARTES E PEÇAS
1f71bfa2-5fcf-4eac-9f3f-d5016688534b	4669999	COMÉRCIO ATACADISTA DE OUTRAS MÁQUINAS E EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE; PARTES E PEÇAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS, EXCETO DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE; PARTES E PEÇAS
2d6ce187-3fd2-4f80-903f-a8d330374441	4671100	COMÉRCIO ATACADISTA DE MADEIRA E PRODUTOS DERIVADOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO	COMÉRCIO ATACADISTA DE MADEIRA E PRODUTOS DERIVADOS
abdb58f3-f952-4c42-bb62-b3c2baaf0244	4672900	COMÉRCIO ATACADISTA DE FERRAGENS E FERRAMENTAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO	COMÉRCIO ATACADISTA DE FERRAGENS E FERRAMENTAS
7b52f615-80b8-460a-a8ab-ec49f3de8727	4673700	COMÉRCIO ATACADISTA DE MATERIAL ELÉTRICO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO	COMÉRCIO ATACADISTA DE MATERIAL ELÉTRICO
ab3f3917-f58e-4600-85e9-831968127afc	4674500	COMÉRCIO ATACADISTA DE CIMENTO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO	COMÉRCIO ATACADISTA DE CIMENTO
685316cf-c8fe-47d4-a620-4ba2e3015952	4679601	COMÉRCIO ATACADISTA DE TINTAS, VERNIZES E SIMILARES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO	COMÉRCIO ATACADISTA ESPECIALIZADO DE MATERIAIS DE CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE E DE MATERIAIS DE CONSTRUÇÃO EM GERAL
30e50039-fd8f-40ed-922e-c13473299bae	4679602	COMÉRCIO ATACADISTA DE MÁRMORES E GRANITOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO	COMÉRCIO ATACADISTA ESPECIALIZADO DE MATERIAIS DE CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE E DE MATERIAIS DE CONSTRUÇÃO EM GERAL
e7723bd1-eb53-4060-8a16-5e3684828bee	4679603	COMÉRCIO ATACADISTA DE VIDROS, ESPELHOS E VITRAIS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO	COMÉRCIO ATACADISTA ESPECIALIZADO DE MATERIAIS DE CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE E DE MATERIAIS DE CONSTRUÇÃO EM GERAL
e943d818-5dda-4dbc-a1c4-8e565d7890d5	4679604	COMÉRCIO ATACADISTA ESPECIALIZADO DE MATERIAIS DE CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO	COMÉRCIO ATACADISTA ESPECIALIZADO DE MATERIAIS DE CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE E DE MATERIAIS DE CONSTRUÇÃO EM GERAL
0710fd00-1cbc-455b-a38e-3032bb7b1662	4679699	COMÉRCIO ATACADISTA DE MATERIAIS DE CONSTRUÇÃO EM GERAL	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO	COMÉRCIO ATACADISTA ESPECIALIZADO DE MATERIAIS DE CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE E DE MATERIAIS DE CONSTRUÇÃO EM GERAL
fba9de88-483c-4bc6-a02d-9d7c04f685e8	4681801	COMÉRCIO ATACADISTA DE ÁLCOOL CARBURANTE, BIODIESEL, GASOLINA E DEMAIS DERIVADOS DE PETRÓLEO, EXCETO LUBRIFICANTES, NÃO REALIZADO POR TRANSPORTADOR RETALHISTA (T.R.R.)	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE COMBUSTÍVEIS SÓLIDOS, LÍQUIDOS E GASOSOS, EXCETO GÁS NATURAL E GLP
e47b913c-4700-4448-b446-190cfdbdbe4e	4681802	COMÉRCIO ATACADISTA DE COMBUSTÍVEIS REALIZADO POR TRANSPORTADOR RETALHISTA (T.R.R.)	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE COMBUSTÍVEIS SÓLIDOS, LÍQUIDOS E GASOSOS, EXCETO GÁS NATURAL E GLP
00076f6c-2c82-423a-9e80-e9dedee06a83	4681803	COMÉRCIO ATACADISTA DE COMBUSTÍVEIS DE ORIGEM VEGETAL, EXCETO ÁLCOOL CARBURANTE	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE COMBUSTÍVEIS SÓLIDOS, LÍQUIDOS E GASOSOS, EXCETO GÁS NATURAL E GLP
e4833659-e944-449b-bcb2-7bddeee90440	4681804	COMÉRCIO ATACADISTA DE COMBUSTÍVEIS DE ORIGEM MINERAL EM BRUTO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE COMBUSTÍVEIS SÓLIDOS, LÍQUIDOS E GASOSOS, EXCETO GÁS NATURAL E GLP
f791b2ec-2222-4e49-af7e-9eddd7805c8b	4681805	COMÉRCIO ATACADISTA DE LUBRIFICANTES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE COMBUSTÍVEIS SÓLIDOS, LÍQUIDOS E GASOSOS, EXCETO GÁS NATURAL E GLP
42e77a3d-e8a9-472a-85e7-0e797b3b7884	4682600	COMÉRCIO ATACADISTA DE GÁS LIQUEFEITO DE PETRÓLEO (GLP)	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE GÁS LIQUEFEITO DE PETRÓLEO (GLP)
5d5ac254-2050-4455-a92d-8e5673bffe80	4683400	COMÉRCIO ATACADISTA DE DEFENSIVOS AGRÍCOLAS, ADUBOS, FERTILIZANTES E CORRETIVOS DO SOLO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE DEFENSIVOS AGRÍCOLAS, ADUBOS, FERTILIZANTES E CORRETIVOS DO SOLO
5f578eda-8642-43b9-8c89-1d116a22846d	4684201	COMÉRCIO ATACADISTA DE RESINAS E ELASTÔMEROS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE PRODUTOS QUÍMICOS E PETROQUÍMICOS, EXCETO AGROQUÍMICOS
7da3c5bd-a493-4525-a8e3-9e13e488d4b2	4684202	COMÉRCIO ATACADISTA DE SOLVENTES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE PRODUTOS QUÍMICOS E PETROQUÍMICOS, EXCETO AGROQUÍMICOS
34fe5543-b8a9-4a7c-824b-0e90ba702747	4684299	COMÉRCIO ATACADISTA DE OUTROS PRODUTOS QUÍMICOS E PETROQUÍMICOS NÃO ESPECIFICADOS ANTERIORMENTE	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE PRODUTOS QUÍMICOS E PETROQUÍMICOS, EXCETO AGROQUÍMICOS
13673c00-8127-4cca-b578-4b13d767acfd	4685100	COMÉRCIO ATACADISTA DE PRODUTOS SIDERÚRGICOS E METALÚRGICOS, EXCETO PARA CONSTRUÇÃO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE PRODUTOS SIDERÚRGICOS E METALÚRGICOS, EXCETO PARA CONSTRUÇÃO
4e2ea894-2274-4766-a868-5e7f5b17ed8d	4686901	COMÉRCIO ATACADISTA DE PAPEL E PAPELÃO EM BRUTO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE PAPEL E PAPELÃO EM BRUTO E DE EMBALAGENS
e19a9ea9-b4c4-40b2-99ba-53d4b956d125	4686902	COMÉRCIO ATACADISTA DE EMBALAGENS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE PAPEL E PAPELÃO EM BRUTO E DE EMBALAGENS
c697a2f0-bf27-4e96-ad1e-48d832535b4e	4687701	COMÉRCIO ATACADISTA DE RESÍDUOS DE PAPEL E PAPELÃO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE RESÍDUOS E SUCATAS
89431dcd-1227-4580-9dc4-78323350f545	4687702	COMÉRCIO ATACADISTA DE RESÍDUOS E SUCATAS NÃO METÁLICOS, EXCETO DE PAPEL E PAPELÃO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE RESÍDUOS E SUCATAS
b4db8ae0-64df-4174-9d9e-a1369b7c7562	4687703	COMÉRCIO ATACADISTA DE RESÍDUOS E SUCATAS METÁLICOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE RESÍDUOS E SUCATAS
e04d2d35-91cd-4e0c-ba49-af610893244d	4689301	COMÉRCIO ATACADISTA DE PRODUTOS DA EXTRAÇÃO MINERAL, EXCETO COMBUSTÍVEIS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA ESPECIALIZADO DE OUTROS PRODUTOS INTERMEDIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
6cb8dec0-ce5a-4fee-b5d1-7f19f8257335	4689302	COMÉRCIO ATACADISTA DE FIOS E FIBRAS BENEFICIADOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA ESPECIALIZADO DE OUTROS PRODUTOS INTERMEDIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
b50a13ae-efc6-4718-a693-063db5826231	4689399	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS INTERMEDIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA ESPECIALIZADO DE OUTROS PRODUTOS INTERMEDIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
83e2aa2d-d273-454f-b117-fa702eec6f07	4691500	COMÉRCIO ATACADISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA NÃO-ESPECIALIZADO	COMÉRCIO ATACADISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS
aa39cc0f-033c-4063-bc68-334f4efda983	4692300	COMÉRCIO ATACADISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE INSUMOS AGROPECUÁRIOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA NÃO-ESPECIALIZADO	COMÉRCIO ATACADISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE INSUMOS AGROPECUÁRIOS
fbd824ed-da42-4648-92a8-02cb6d05730d	4693100	COMÉRCIO ATACADISTA DE MERCADORIAS EM GERAL, SEM PREDOMINÂNCIA DE ALIMENTOS OU DE INSUMOS AGROPECUÁRIOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA NÃO-ESPECIALIZADO	COMÉRCIO ATACADISTA DE MERCADORIAS EM GERAL, SEM PREDOMINÂNCIA DE ALIMENTOS OU DE INSUMOS AGROPECUÁRIOS
494fb340-6407-4842-b98d-bad2eab1c5d0	4711301	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS   HIPERMERCADOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA NÃO-ESPECIALIZADO	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS - HIPERMERCADOS E SUPERMERCADOS
432b5297-d885-4322-9df3-b80e65d07947	4711302	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS - SUPERMERCADOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA NÃO-ESPECIALIZADO	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS - HIPERMERCADOS E SUPERMERCADOS
453b1a05-dcfb-4b4a-ace4-32ff4d5407cb	4712100	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS - MINIMERCADOS, MERCEARIAS E ARMAZÉNS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA NÃO-ESPECIALIZADO	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS - MINIMERCADOS, MERCEARIAS E ARMAZÉNS
791bd048-7ff3-40e1-b00f-f5ae7609f48e	4713002	LOJAS DE VARIEDADES, EXCETO LOJAS DE DEPARTAMENTOS OU MAGAZINES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA NÃO-ESPECIALIZADO	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, SEM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS
58cc8e10-d0bc-4751-ae08-c294963d0fdd	4713004	LOJAS DE DEPARTAMENTOS OU MAGAZINES, EXCETO LOJAS FRANCAS (DUTY FREE)	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA NÃO-ESPECIALIZADO	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, SEM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS
cd6c4288-7455-470a-82a3-fdf7d275e9e8	4713005	LOJAS FRANCAS (DUTY FREE) DE AEROPORTOS, PORTOS E EM FRONTEIRAS TERRESTRES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA NÃO-ESPECIALIZADO	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, SEM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS
2ca1ef12-fe7f-41d6-82c7-a1de57747d55	4721102	PADARIA E CONFEITARIA COM PREDOMINÂNCIA DE REVENDA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE PRODUTOS DE PADARIA, LATICÍNIO, DOCES, BALAS E SEMELHANTES
55a17b4a-465f-4968-a769-0c121d44eb60	4721103	COMÉRCIO VAREJISTA DE LATICÍNIOS E FRIOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE PRODUTOS DE PADARIA, LATICÍNIO, DOCES, BALAS E SEMELHANTES
12a61698-6bfd-466e-a5f6-7f22c43ef9a8	4721104	COMÉRCIO VAREJISTA DE DOCES, BALAS, BOMBONS E SEMELHANTES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE PRODUTOS DE PADARIA, LATICÍNIO, DOCES, BALAS E SEMELHANTES
51a121d0-1da1-4ddc-b044-8a5bcef21fef	4722901	COMÉRCIO VAREJISTA DE CARNES - AÇOUGUES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE CARNES E PESCADOS - AÇOUGUES E PEIXARIAS
a4e97121-78c1-4a78-8c40-667cd0ce6a4f	4722902	PEIXARIA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE CARNES E PESCADOS - AÇOUGUES E PEIXARIAS
a2f77364-51c5-474c-b6cf-53ab5d33982b	4723700	COMÉRCIO VAREJISTA DE BEBIDAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE BEBIDAS
db8a75d3-0e16-49af-9943-3e249fd42caf	4724500	COMÉRCIO VAREJISTA DE HORTIFRUTIGRANJEIROS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE HORTIFRUTIGRANJEIROS
c6af59f0-8734-478f-948e-3edf727f6548	4729601	TABACARIA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS EM GERAL OU ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE; PRODUTOS DO FUMO
eeb7a432-e43f-41c8-b04d-e4717e4a4111	4729602	COMÉRCIO VAREJISTA DE MERCADORIAS EM LOJAS DE CONVENIÊNCIA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS EM GERAL OU ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE; PRODUTOS DO FUMO
81118d60-b199-4157-889d-677ef8e5758d	4729699	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS EM GERAL OU ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS EM GERAL OU ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE; PRODUTOS DO FUMO
d80d1296-030e-47bb-9152-ca7696950173	4731800	COMÉRCIO VAREJISTA DE COMBUSTÍVEIS PARA VEÍCULOS AUTOMOTORES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE COMBUSTÍVEIS PARA VEÍCULOS AUTOMOTORES	COMÉRCIO VAREJISTA DE COMBUSTÍVEIS PARA VEÍCULOS AUTOMOTORES
bdcc73fe-ac69-4553-ae1c-62ef78f56312	4732600	COMÉRCIO VAREJISTA DE LUBRIFICANTES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE COMBUSTÍVEIS PARA VEÍCULOS AUTOMOTORES	COMÉRCIO VAREJISTA DE LUBRIFICANTES
610f4c4d-9bc4-4223-a225-6ad28baa48d6	4741500	COMÉRCIO VAREJISTA DE TINTAS E MATERIAIS PARA PINTURA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE TINTAS E MATERIAIS PARA PINTURA
34e59e56-fa73-4709-97d8-d2797495e13e	4742300	COMÉRCIO VAREJISTA DE MATERIAL ELÉTRICO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE MATERIAL ELÉTRICO
582d6773-c9c2-4100-9602-f0f9ead14a09	4743100	COMÉRCIO VAREJISTA DE VIDROS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE VIDROS
70d17329-50e7-4556-93ae-0c375f7cdfc4	4744001	COMÉRCIO VAREJISTA DE FERRAGENS E FERRAMENTAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE FERRAGENS, MADEIRA E MATERIAIS DE CONSTRUÇÃO
dc92fa71-d7c4-48ab-aeae-d137f5946062	4744002	COMÉRCIO VAREJISTA DE MADEIRA E ARTEFATOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE FERRAGENS, MADEIRA E MATERIAIS DE CONSTRUÇÃO
7ed0482e-3c28-4fcf-a98c-7413135ee206	4744003	COMÉRCIO VAREJISTA DE MATERIAIS HIDRÁULICOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE FERRAGENS, MADEIRA E MATERIAIS DE CONSTRUÇÃO
1cae1baf-004b-4145-b64b-b18c1a5ebf5f	4744004	COMÉRCIO VAREJISTA DE CAL, AREIA, PEDRA BRITADA, TIJOLOS E TELHAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE FERRAGENS, MADEIRA E MATERIAIS DE CONSTRUÇÃO
cafa01be-bf9b-4c88-8749-14fb8dad7e86	4744005	COMÉRCIO VAREJISTA DE MATERIAIS DE CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE FERRAGENS, MADEIRA E MATERIAIS DE CONSTRUÇÃO
9e34ef16-8845-471d-aeea-38e9075e8541	4744006	COMÉRCIO VAREJISTA DE PEDRAS PARA REVESTIMENTO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE FERRAGENS, MADEIRA E MATERIAIS DE CONSTRUÇÃO
2ba3304e-787d-4e27-8f71-e949fd66eab2	4744099	COMÉRCIO VAREJISTA DE MATERIAIS DE CONSTRUÇÃO EM GERAL	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE FERRAGENS, MADEIRA E MATERIAIS DE CONSTRUÇÃO
07b2082e-4032-4532-aac5-514a57a1b5fb	4751201	COMÉRCIO VAREJISTA ESPECIALIZADO DE EQUIPAMENTOS E SUPRIMENTOS DE INFORMÁTICA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE EQUIPAMENTOS E SUPRIMENTOS DE INFORMÁTICA
bfbad65c-c96c-4686-908d-604306abc500	4751202	RECARGA DE CARTUCHOS PARA EQUIPAMENTOS DE INFORMÁTICA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE EQUIPAMENTOS E SUPRIMENTOS DE INFORMÁTICA
7a515029-4717-4179-9d60-365117cd2e77	4752100	COMÉRCIO VAREJISTA ESPECIALIZADO DE EQUIPAMENTOS DE TELEFONIA E COMUNICAÇÃO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE EQUIPAMENTOS DE TELEFONIA E COMUNICAÇÃO
617a4d82-00d6-4d48-85b6-2952fb958a37	4753900	COMÉRCIO VAREJISTA ESPECIALIZADO DE ELETRODOMÉSTICOS E EQUIPAMENTOS DE ÁUDIO E VÍDEO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE ELETRODOMÉSTICOS E EQUIPAMENTOS DE ÁUDIO E VÍDEO
6de18b18-8ce8-43fa-8762-c46b50daa05d	4754701	COMÉRCIO VAREJISTA DE MÓVEIS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE MÓVEIS, COLCHOARIA E ARTIGOS DE ILUMINAÇÃO
4ac29630-2b59-4b1b-bef2-f53b90e62cb5	4754702	COMÉRCIO VAREJISTA DE ARTIGOS DE COLCHOARIA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE MÓVEIS, COLCHOARIA E ARTIGOS DE ILUMINAÇÃO
40036e62-4359-4c0f-b6e4-54ba278dce1c	4754703	COMÉRCIO VAREJISTA DE ARTIGOS DE ILUMINAÇÃO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE MÓVEIS, COLCHOARIA E ARTIGOS DE ILUMINAÇÃO
6c8cf070-7dc9-452f-996f-2c94228898bc	4755501	COMÉRCIO VAREJISTA DE TECIDOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE TECIDOS E ARTIGOS DE CAMA, MESA E BANHO
2cfc9d7f-9284-4aa7-bdc2-cf81d4ce8391	4755502	COMERCIO VAREJISTA DE ARTIGOS DE ARMARINHO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE TECIDOS E ARTIGOS DE CAMA, MESA E BANHO
09f823b2-0062-42b4-a224-3bb4464e875b	4755503	COMERCIO VAREJISTA DE ARTIGOS DE CAMA, MESA E BANHO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE TECIDOS E ARTIGOS DE CAMA, MESA E BANHO
22233427-d0b7-4f33-b945-067c0786611a	4756300	COMÉRCIO VAREJISTA ESPECIALIZADO DE INSTRUMENTOS MUSICAIS E ACESSÓRIOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE INSTRUMENTOS MUSICAIS E ACESSÓRIOS
7f3ac8cb-1f2e-4280-81b2-cd37270985b4	4757100	COMÉRCIO VAREJISTA ESPECIALIZADO DE PEÇAS E ACESSÓRIOS PARA APARELHOS ELETROELETRÔNICOS PARA USO DOMÉSTICO, EXCETO INFORMÁTICA E COMUNICAÇÃO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE PEÇAS E ACESSÓRIOS PARA APARELHOS ELETROELETRÔNICOS PARA USO DOMÉSTICO, EXCETO INFORMÁTICA E COMUNICAÇÃO
442f6915-b3a4-4166-8735-5c7bd86b4092	4759801	COMÉRCIO VAREJISTA DE ARTIGOS DE TAPEÇARIA, CORTINAS E PERSIANAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA DE ARTIGOS DE USO DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
e60731f6-4547-41c4-a539-2830161bd1f7	4759899	COMÉRCIO VAREJISTA DE OUTROS ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA DE ARTIGOS DE USO DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
c7ab5b42-d45f-4784-abb7-2f7ecadd6028	4761001	COMÉRCIO VAREJISTA DE LIVROS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS	COMÉRCIO VAREJISTA DE LIVROS, JORNAIS, REVISTAS E PAPELARIA
6dc0ead4-6519-4552-85ce-b19c5531d4d4	4761002	COMÉRCIO VAREJISTA DE JORNAIS E REVISTAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS	COMÉRCIO VAREJISTA DE LIVROS, JORNAIS, REVISTAS E PAPELARIA
1826b66b-adc1-4c65-86ad-9b8b43a51767	4761003	COMÉRCIO VAREJISTA DE ARTIGOS DE PAPELARIA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS	COMÉRCIO VAREJISTA DE LIVROS, JORNAIS, REVISTAS E PAPELARIA
f31dd141-a14a-4744-abdc-9cc610af8de0	4762800	COMÉRCIO VAREJISTA DE DISCOS, CDS, DVDS E FITAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS	COMÉRCIO VAREJISTA DE DISCOS, CDS, DVDS E FITAS
d27aa7b3-5c7e-40af-9631-a196af615433	4763601	COMÉRCIO VAREJISTA DE BRINQUEDOS E ARTIGOS RECREATIVOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS	COMÉRCIO VAREJISTA DE ARTIGOS RECREATIVOS E ESPORTIVOS
a3e6f02a-90ca-4bb1-aac4-848ce6a676a0	4763602	COMÉRCIO VAREJISTA DE ARTIGOS ESPORTIVOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS	COMÉRCIO VAREJISTA DE ARTIGOS RECREATIVOS E ESPORTIVOS
4c696586-62e4-4685-8d89-5ad038319d07	4763603	COMÉRCIO VAREJISTA DE BICICLETAS E TRICICLOS; PEÇAS E ACESSÓRIOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS	COMÉRCIO VAREJISTA DE ARTIGOS RECREATIVOS E ESPORTIVOS
ce91870e-2c82-4430-8ad3-e3dae6dff941	4763604	COMÉRCIO VAREJISTA DE ARTIGOS DE CAÇA, PESCA E CAMPING	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS	COMÉRCIO VAREJISTA DE ARTIGOS RECREATIVOS E ESPORTIVOS
94a3f664-5bea-4a92-993e-3738dc3e18b7	4763605	COMÉRCIO VAREJISTA DE EMBARCAÇÕES E OUTROS VEÍCULOS RECREATIVOS; PEÇAS E ACESSÓRIOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS	COMÉRCIO VAREJISTA DE ARTIGOS RECREATIVOS E ESPORTIVOS
7b14c6a4-08c6-4581-a211-f51ed6baf090	4771701	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, SEM MANIPULAÇÃO DE FÓRMULAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, PERFUMARIA E COSMÉTICOS E ARTIGOS MÉDICOS, ÓPTICOS E ORTOPÉDICOS	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS PARA USO HUMANO E VETERINÁRIO
6c8b9152-828f-4548-beb4-92d196a14359	4771702	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, COM MANIPULAÇÃO DE FÓRMULAS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, PERFUMARIA E COSMÉTICOS E ARTIGOS MÉDICOS, ÓPTICOS E ORTOPÉDICOS	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS PARA USO HUMANO E VETERINÁRIO
382e96cd-d3e5-45d9-b493-0332a7a9d16e	4771703	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS HOMEOPÁTICOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, PERFUMARIA E COSMÉTICOS E ARTIGOS MÉDICOS, ÓPTICOS E ORTOPÉDICOS	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS PARA USO HUMANO E VETERINÁRIO
331beea4-dd0f-4a6a-9703-d4473b8d9da8	4771704	COMÉRCIO VAREJISTA DE MEDICAMENTOS VETERINÁRIOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, PERFUMARIA E COSMÉTICOS E ARTIGOS MÉDICOS, ÓPTICOS E ORTOPÉDICOS	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS PARA USO HUMANO E VETERINÁRIO
c77bf935-d0b0-4f17-b7fb-9dead2a0b331	4772500	COMÉRCIO VAREJISTA DE COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, PERFUMARIA E COSMÉTICOS E ARTIGOS MÉDICOS, ÓPTICOS E ORTOPÉDICOS	COMÉRCIO VAREJISTA DE COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL
1c3f7966-3803-4c6c-bb1d-3f378c143118	4773300	COMÉRCIO VAREJISTA DE ARTIGOS MÉDICOS E ORTOPÉDICOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, PERFUMARIA E COSMÉTICOS E ARTIGOS MÉDICOS, ÓPTICOS E ORTOPÉDICOS	COMÉRCIO VAREJISTA DE ARTIGOS MÉDICOS E ORTOPÉDICOS
e46e303d-5642-4f75-bec7-84071e66cc79	4774100	COMÉRCIO VAREJISTA DE ARTIGOS DE ÓPTICA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, PERFUMARIA E COSMÉTICOS E ARTIGOS MÉDICOS, ÓPTICOS E ORTOPÉDICOS	COMÉRCIO VAREJISTA DE ARTIGOS DE ÓPTICA
85983af2-36f7-4223-b3f9-16daf7bcd9ae	4781400	COMÉRCIO VAREJISTA DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS
7266bc8d-5cd5-4dd1-9860-839c8b3d93a3	4782201	COMÉRCIO VAREJISTA DE CALÇADOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE CALÇADOS E ARTIGOS DE VIAGEM
47e3b74e-5cc1-4471-94d5-66a814c27c1a	4782202	COMÉRCIO VAREJISTA DE ARTIGOS DE VIAGEM	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE CALÇADOS E ARTIGOS DE VIAGEM
2fcdcc98-6207-4e05-8fca-17b934706b14	4783101	COMÉRCIO VAREJISTA DE ARTIGOS DE JOALHERIA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE JÓIAS E RELÓGIOS
f2c1691f-df11-4565-8623-4843d124ead3	4783102	COMÉRCIO VAREJISTA DE ARTIGOS DE RELOJOARIA	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE JÓIAS E RELÓGIOS
60af9144-daf7-4a5b-8d99-1d247ba0655e	4784900	COMÉRCIO VAREJISTA DE GÁS LIQUEFEITO DE PETRÓLEO (GLP)	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE GÁS LIQUEFEITO DE PETRÓLEO (GLP)
84ede414-28eb-462e-a45b-13dedaa6bd40	4785701	COMÉRCIO VAREJISTA DE ANTIGUIDADES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE ARTIGOS USADOS
f9d9a61a-ee3f-4e98-bd91-72bdab194a66	4785799	COMÉRCIO VAREJISTA DE OUTROS ARTIGOS USADOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE ARTIGOS USADOS
48a0de8c-ccc4-4101-bcd3-3d3bce48d894	4789001	COMÉRCIO VAREJISTA DE SUVENIRES, BIJUTERIAS E ARTESANATOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
40734477-c65a-43ed-8872-7f76670a2ff7	4789002	COMÉRCIO VAREJISTA DE PLANTAS E FLORES NATURAIS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
e0af1889-ba69-4f83-a56b-1186a0affa42	4789003	COMÉRCIO VAREJISTA DE OBJETOS DE ARTE	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
168b17df-2c38-4f24-a8ed-d36360f60ef4	4789004	COMÉRCIO VAREJISTA DE ANIMAIS VIVOS E DE ARTIGOS E ALIMENTOS PARA ANIMAIS DE ESTIMAÇÃO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
18a6cf7a-dcf5-4935-8b17-fe9057e642dd	4789005	COMÉRCIO VAREJISTA DE PRODUTOS SANEANTES DOMISSANITÁRIOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
1bfae97a-bffc-49d2-94ab-cc5b87f563dd	4789006	COMÉRCIO VAREJISTA DE FOGOS DE ARTIFÍCIO E ARTIGOS PIROTÉCNICOS	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
0ebb3e40-9292-4c96-8272-e9677085ba00	4789007	COMÉRCIO VAREJISTA DE EQUIPAMENTOS PARA ESCRITÓRIO	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
f0d27839-7135-427f-a4a8-3658d1de1d39	4789008	COMÉRCIO VAREJISTA DE ARTIGOS FOTOGRÁFICOS E PARA FILMAGEM	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
90098de3-b57f-4260-a160-0ddcb8bcb694	4789009	COMÉRCIO VAREJISTA DE ARMAS E MUNIÇÕES	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
9a10cade-f0f2-4888-b8fa-3a960b178026	4789099	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NÃO ESPECIFICADOS ANTERIORMENTE	t	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
f3633e43-285d-4482-8a35-ba138090e20f	4911600	TRANSPORTE FERROVIÁRIO DE CARGA	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE FERROVIÁRIO E METROFERROVIÁRIO	TRANSPORTE FERROVIÁRIO DE CARGA
cf61364c-a91d-4d46-88a0-893f9221bcce	4912401	TRANSPORTE FERROVIÁRIO DE PASSAGEIROS INTERMUNICIPAL E INTERESTADUAL	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE FERROVIÁRIO E METROFERROVIÁRIO	TRANSPORTE METROFERROVIÁRIO DE PASSAGEIROS
b2e8b5a0-ab42-4aff-bfd1-e82bbec3b4ac	4912402	TRANSPORTE FERROVIÁRIO DE PASSAGEIROS MUNICIPAL E EM REGIÃO METROPOLITANA	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE FERROVIÁRIO E METROFERROVIÁRIO	TRANSPORTE METROFERROVIÁRIO DE PASSAGEIROS
a87d4e05-7914-42a3-b062-9180cf833fca	4912403	TRANSPORTE METROVIÁRIO	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE FERROVIÁRIO E METROFERROVIÁRIO	TRANSPORTE METROFERROVIÁRIO DE PASSAGEIROS
994211e4-4931-4bf4-bd9f-e008bd1b7558	4921301	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, MUNICIPAL	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, MUNICIPAL E EM REGIÃO METROPOLITANA
bc6177e7-15ca-4cf9-9368-b472fefcd7de	4921302	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, INTERMUNICIPAL EM REGIÃO METROPOLITANA	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, MUNICIPAL E EM REGIÃO METROPOLITANA
2e646a5f-2e17-43f0-b58b-43ad4f44b847	4922101	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, INTERMUNICIPAL, EXCETO EM REGIÃO METROPOLITANA	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL
c329c414-d26e-44c8-b3d9-8e6f52e2e54f	4922102	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, INTERESTADUAL	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL
37c73733-b3c3-41f6-afed-d40389bfe4a6	4922103	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, INTERNACIONAL	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL
afcf4680-ffa3-47f7-ab5d-638f905e6ed3	4923001	SERVIÇO DE TÁXI	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO DE TÁXI
9ad1cc2e-39a5-40d4-8d68-f1bc84544674	4923002	SERVIÇO DE TRANSPORTE DE PASSAGEIROS - LOCAÇÃO DE AUTOMÓVEIS COM MOTORISTA	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO DE TÁXI
5814447c-fab0-42a4-86c7-717765f85626	4924800	TRANSPORTE ESCOLAR	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE ESCOLAR
da00edbb-3e67-46fb-8abe-05b85e313caf	4929901	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, SOB REGIME DE FRETAMENTO, MUNICIPAL	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, SOB REGIME DE FRETAMENTO, E OUTROS TRANSPORTES RODOVIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
26c5fa63-be42-40e3-85e6-64e3d591a3ab	4929902	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, SOB REGIME DE FRETAMENTO, INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, SOB REGIME DE FRETAMENTO, E OUTROS TRANSPORTES RODOVIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
00ef3923-1b7a-466a-9b21-5ff2d391d2b2	4929903	ORGANIZAÇÃO DE EXCURSÕES EM VEÍCULOS RODOVIÁRIOS PRÓPRIOS, MUNICIPAL	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, SOB REGIME DE FRETAMENTO, E OUTROS TRANSPORTES RODOVIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
8da31fdb-3d4b-4e69-9a60-908d6b9b4180	4929904	ORGANIZAÇÃO DE EXCURSÕES EM VEÍCULOS RODOVIÁRIOS PRÓPRIOS, INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, SOB REGIME DE FRETAMENTO, E OUTROS TRANSPORTES RODOVIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
048a704b-c85f-4ef5-a207-281d3213721f	4929999	OUTROS TRANSPORTES RODOVIÁRIOS DE PASSAGEIROS NÃO ESPECIFICADOS ANTERIORMENTE	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, SOB REGIME DE FRETAMENTO, E OUTROS TRANSPORTES RODOVIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
0e600830-f443-438c-9c18-4fd4e969b0c0	4930201	TRANSPORTE RODOVIÁRIO DE CARGA, EXCETO PRODUTOS PERIGOSOS E MUDANÇAS, MUNICIPAL	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE CARGA	TRANSPORTE RODOVIÁRIO DE CARGA
80d202ba-850a-4c31-b834-6eed95616d44	4930202	TRANSPORTE RODOVIÁRIO DE CARGA, EXCETO PRODUTOS PERIGOSOS E MUDANÇAS, INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE CARGA	TRANSPORTE RODOVIÁRIO DE CARGA
a69ea554-09e6-4d2a-9d00-20beecd48204	4930203	TRANSPORTE RODOVIÁRIO DE PRODUTOS PERIGOSOS	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE CARGA	TRANSPORTE RODOVIÁRIO DE CARGA
735a83e0-fc49-41ef-9066-78ac72c2d935	4930204	TRANSPORTE RODOVIÁRIO DE MUDANÇAS	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE CARGA	TRANSPORTE RODOVIÁRIO DE CARGA
57493b8a-c4c0-4057-88ed-bb664430962a	4940000	TRANSPORTE DUTOVIÁRIO	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE DUTOVIÁRIO	TRANSPORTE DUTOVIÁRIO
b21d22ea-9ae8-4b68-ba52-9440caf8e85f	4950700	TRENS TURÍSTICOS, TELEFÉRICOS E SIMILARES	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRENS TURÍSTICOS, TELEFÉRICOS E SIMILARES	TRENS TURÍSTICOS, TELEFÉRICOS E SIMILARES
a2d9c80f-bcc4-499a-bcf9-2ee5a8f87d0f	5011401	TRANSPORTE MARÍTIMO DE CABOTAGEM - CARGA	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	TRANSPORTE MARÍTIMO DE CABOTAGEM E LONGO CURSO	TRANSPORTE MARÍTIMO DE CABOTAGEM
8b6df84e-53ae-41d8-a2b3-d650220b0e2c	5011402	TRANSPORTE MARÍTIMO DE CABOTAGEM - PASSAGEIROS	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	TRANSPORTE MARÍTIMO DE CABOTAGEM E LONGO CURSO	TRANSPORTE MARÍTIMO DE CABOTAGEM
b03ec486-eb95-4006-ad57-feb78bc345c9	5012201	TRANSPORTE MARÍTIMO DE LONGO CURSO - CARGA	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	TRANSPORTE MARÍTIMO DE CABOTAGEM E LONGO CURSO	TRANSPORTE MARÍTIMO DE LONGO CURSO
2c430ce2-c526-4bb2-a98f-bb3d9b9b7cab	5012202	TRANSPORTE MARÍTIMO DE LONGO CURSO - PASSAGEIROS	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	TRANSPORTE MARÍTIMO DE CABOTAGEM E LONGO CURSO	TRANSPORTE MARÍTIMO DE LONGO CURSO
9c8bd1c1-f2b7-4c70-9e1a-207510bbc546	5021101	TRANSPORTE POR NAVEGAÇÃO INTERIOR DE CARGA, MUNICIPAL, EXCETO TRAVESSIA	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	TRANSPORTE POR NAVEGAÇÃO INTERIOR	TRANSPORTE POR NAVEGAÇÃO INTERIOR DE CARGA
05e6cc48-c313-41da-a8b8-f93668dfbc24	5021102	TRANSPORTE POR NAVEGAÇÃO INTERIOR DE CARGA, INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL, EXCETO TRAVESSIA	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	TRANSPORTE POR NAVEGAÇÃO INTERIOR	TRANSPORTE POR NAVEGAÇÃO INTERIOR DE CARGA
d4c310c8-e7c1-4262-afa6-148acd7f59ba	5022001	TRANSPORTE POR NAVEGAÇÃO INTERIOR DE PASSAGEIROS EM LINHAS REGULARES, MUNICIPAL, EXCETO TRAVESSIA	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	TRANSPORTE POR NAVEGAÇÃO INTERIOR	TRANSPORTE POR NAVEGAÇÃO INTERIOR DE PASSAGEIROS EM LINHAS REGULARES
b3ae796a-3bec-4b3c-aaba-938164d04b95	5022002	TRANSPORTE POR NAVEGAÇÃO INTERIOR DE PASSAGEIROS EM LINHAS REGULARES, INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL, EXCETO TRAVESSIA	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	TRANSPORTE POR NAVEGAÇÃO INTERIOR	TRANSPORTE POR NAVEGAÇÃO INTERIOR DE PASSAGEIROS EM LINHAS REGULARES
3d610387-57c8-4f51-93e8-5c1cb07f7d73	5030101	NAVEGAÇÃO DE APOIO MARÍTIMO	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	NAVEGAÇÃO DE APOIO	NAVEGAÇÃO DE APOIO
74adfd7f-f111-4d25-aa9b-0d08d2e44b96	5030102	NAVEGAÇÃO DE APOIO PORTUÁRIO	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	NAVEGAÇÃO DE APOIO	NAVEGAÇÃO DE APOIO
b06173e5-8292-41ce-a6ec-7284c8ff3208	5030103	SERVIÇO DE REBOCADORES E EMPURRADORES	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	NAVEGAÇÃO DE APOIO	NAVEGAÇÃO DE APOIO
24247b69-2310-4f1b-8930-e99412ff58d9	5091201	TRANSPORTE POR NAVEGAÇÃO DE TRAVESSIA, MUNICIPAL	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	OUTROS TRANSPORTES AQUAVIÁRIOS	TRANSPORTE POR NAVEGAÇÃO DE TRAVESSIA
67ed1f81-37d5-4bb7-a844-e7ee6fbb7496	5091202	TRANSPORTE POR NAVEGAÇÃO DE TRAVESSIA INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	OUTROS TRANSPORTES AQUAVIÁRIOS	TRANSPORTE POR NAVEGAÇÃO DE TRAVESSIA
15edebf2-4ff7-41f7-b90c-ad32a1b15881	5099801	TRANSPORTE AQUAVIÁRIO PARA PASSEIOS TURÍSTICOS	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	OUTROS TRANSPORTES AQUAVIÁRIOS	TRANSPORTES AQUAVIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
15894023-a28a-4339-b760-a6cbc8fef246	5099899	OUTROS TRANSPORTES AQUAVIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	OUTROS TRANSPORTES AQUAVIÁRIOS	TRANSPORTES AQUAVIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
2110414e-307a-4d94-b906-61b456d0ec65	5111100	TRANSPORTE AÉREO DE PASSAGEIROS REGULAR	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AÉREO	TRANSPORTE AÉREO DE PASSAGEIROS	TRANSPORTE AÉREO DE PASSAGEIROS REGULAR
ea12a7d4-ef92-4ad9-9305-b83592ff613f	5112901	SERVIÇO DE TÁXI AÉREO E LOCAÇÃO DE AERONAVES COM TRIPULAÇÃO	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AÉREO	TRANSPORTE AÉREO DE PASSAGEIROS	TRANSPORTE AÉREO DE PASSAGEIROS NÃO-REGULAR
5db44ca1-ba11-406f-bfc8-56ffb7b74f92	5112999	OUTROS SERVIÇOS DE TRANSPORTE AÉREO DE PASSAGEIROS NÃO REGULAR	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AÉREO	TRANSPORTE AÉREO DE PASSAGEIROS	TRANSPORTE AÉREO DE PASSAGEIROS NÃO-REGULAR
04a23b4e-2d01-4b86-8c89-27f0168e0c1b	5120000	TRANSPORTE AÉREO DE CARGA	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AÉREO	TRANSPORTE AÉREO DE CARGA	TRANSPORTE AÉREO DE CARGA
e471ab3c-3149-46f4-a582-2fd90e36c530	5130700	TRANSPORTE ESPACIAL	t	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AÉREO	TRANSPORTE ESPACIAL	TRANSPORTE ESPACIAL
1215bc7b-a3ef-4f3c-805d-8cd49948ffc2	5211701	ARMAZÉNS GERAIS - EMISSÃO DE WARRANT	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ARMAZENAMENTO, CARGA E DESCARGA	ARMAZENAMENTO
83bcc2ae-4fc2-40d2-aa05-9ba1bff26f37	5211702	GUARDA MÓVEIS	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ARMAZENAMENTO, CARGA E DESCARGA	ARMAZENAMENTO
8f4fa4bf-48c5-498d-9c6c-972a1202a8a5	5211799	DEPÓSITOS DE MERCADORIAS PARA TERCEIROS, EXCETO ARMAZÉNS GERAIS E GUARDA MÓVEIS	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ARMAZENAMENTO, CARGA E DESCARGA	ARMAZENAMENTO
4e8a6d66-37c3-4754-b3e6-d08ba8e48e3a	5212500	CARGA E DESCARGA	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ARMAZENAMENTO, CARGA E DESCARGA	CARGA E DESCARGA
f60f7137-5588-461f-98fb-df6e277d90dd	5221400	CONCESSIONÁRIAS DE RODOVIAS, PONTES, TÚNEIS E SERVIÇOS RELACIONADOS	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES	CONCESSIONÁRIAS DE RODOVIAS, PONTES, TÚNEIS E SERVIÇOS RELACIONADOS
f49e64ed-92be-47a2-aa08-2809f26b575e	5222200	TERMINAIS RODOVIÁRIOS E FERROVIÁRIOS	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES	TERMINAIS RODOVIÁRIOS E FERROVIÁRIOS
0d1669dc-f52d-4d96-8117-872cead51b7a	5223100	ESTACIONAMENTO DE VEÍCULOS	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES	ESTACIONAMENTO DE VEÍCULOS
c81f9d47-f3c1-42b1-a1ef-3652ae6d3662	5229001	SERVIÇOS DE APOIO AO TRANSPORTE POR TÁXI, INCLUSIVE CENTRAIS DE CHAMADA	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES NÃO ESPECIFICADAS ANTERIORMENTE
8318337e-6e2b-417f-8470-a49e7237016b	5229002	SERVIÇOS DE REBOQUE DE VEÍCULOS	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES NÃO ESPECIFICADAS ANTERIORMENTE
6790a36b-3683-4089-a8e3-8b20b1e1b67b	5229099	OUTRAS ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES NÃO ESPECIFICADAS ANTERIORMENTE	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES NÃO ESPECIFICADAS ANTERIORMENTE
198a92ce-c79f-4989-8a15-84046e910186	5231101	ADMINISTRAÇÃO DA INFRAESTRUTURA PORTUÁRIA	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS	GESTÃO DE PORTOS E TERMINAIS
9bc89318-1c46-42e6-b941-be33f6759e4f	5231102	ATIVIDADES DO OPERADOR PORTUÁRIO	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS	GESTÃO DE PORTOS E TERMINAIS
996f9cfa-3cbd-43ed-969a-876123278436	5231103	GESTÃO DE TERMINAIS AQUAVIÁRIOS	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS	GESTÃO DE PORTOS E TERMINAIS
48ce2f63-cdd5-4ee4-a9e0-d8dac45a17d1	5232000	ATIVIDADES DE AGENCIAMENTO MARÍTIMO	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS	ATIVIDADES DE AGENCIAMENTO MARÍTIMO
6ce7c073-b020-4d6f-b297-e6d8d10e28d4	5239701	SERVIÇOS DE PRATICAGEM	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS NÃO ESPECIFICADAS ANTERIORMENTE
a4b15a1b-0a2a-49d8-a5a9-c3966c12a1ca	5239799	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS NÃO ESPECIFICADAS ANTERIORMENTE	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS NÃO ESPECIFICADAS ANTERIORMENTE
0da58838-0b65-4c64-bc88-6195e6eb9cc7	5240101	OPERAÇÃO DOS AEROPORTOS E CAMPOS DE ATERRISSAGEM	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES AÉREOS	ATIVIDADES AUXILIARES DOS TRANSPORTES AÉREOS
762883f1-76c4-4ecd-83a2-58af705384a3	5240199	ATIVIDADES AUXILIARES DOS TRANSPORTES AÉREOS, EXCETO OPERAÇÃO DOS AEROPORTOS E CAMPOS DE ATERRISSAGEM	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES AÉREOS	ATIVIDADES AUXILIARES DOS TRANSPORTES AÉREOS
93708e0d-1110-475b-888d-f5f3de08205d	5250801	COMISSARIA DE DESPACHOS	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA
24c23956-40ec-4887-bb0a-bde601015231	5250802	ATIVIDADES DE DESPACHANTES ADUANEIROS	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA
155df691-c9c5-4253-98b3-2bebbe93d570	5250803	AGENCIAMENTO DE CARGAS, EXCETO PARA O TRANSPORTE MARÍTIMO	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA
dc18d3b6-a324-4f98-8e9d-0dd88aafb37c	5250804	ORGANIZAÇÃO LOGÍSTICA DO TRANSPORTE DE CARGA	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA
e3257d9f-2cfd-4689-99b8-6e9ace21c8fa	5250805	OPERADOR DE TRANSPORTE MULTIMODAL - OTM	t	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA
110372b5-bae2-4504-9edf-2f769988c39b	5310501	ATIVIDADES DO CORREIO NACIONAL	t	TRANSPORTE, ARMAZENAGEM E CORREIO	CORREIO E OUTRAS ATIVIDADES DE ENTREGA	ATIVIDADES DE CORREIO	ATIVIDADES DE CORREIO
3be39f4b-24fb-4de5-a566-558b7a752617	5310502	ATIVIDADES DE FRANQUEADAS DO CORREIO NACIONAL	t	TRANSPORTE, ARMAZENAGEM E CORREIO	CORREIO E OUTRAS ATIVIDADES DE ENTREGA	ATIVIDADES DE CORREIO	ATIVIDADES DE CORREIO
3f5be675-2dc0-4c48-a38d-03d385f955bd	5320201	SERVIÇOS DE MALOTE NÃO REALIZADOS PELO CORREIO NACIONAL	t	TRANSPORTE, ARMAZENAGEM E CORREIO	CORREIO E OUTRAS ATIVIDADES DE ENTREGA	ATIVIDADES DE MALOTE E DE ENTREGA	ATIVIDADES DE MALOTE E DE ENTREGA
5567f11b-4a48-4a0f-978e-80e77a30f1a4	5320202	SERVIÇOS DE ENTREGA RÁPIDA	t	TRANSPORTE, ARMAZENAGEM E CORREIO	CORREIO E OUTRAS ATIVIDADES DE ENTREGA	ATIVIDADES DE MALOTE E DE ENTREGA	ATIVIDADES DE MALOTE E DE ENTREGA
9aed12ef-0904-4258-8874-0c1ac42ede2d	5510801	HOTÉIS	t	ALOJAMENTO E ALIMENTAÇÃO	ALOJAMENTO	HOTÉIS E SIMILARES	HOTÉIS E SIMILARES
8aaae8cc-124c-43ca-be9a-61dc6dfbb3d3	5510802	APART HOTÉIS	t	ALOJAMENTO E ALIMENTAÇÃO	ALOJAMENTO	HOTÉIS E SIMILARES	HOTÉIS E SIMILARES
06e56a89-8548-4401-9116-1af2ee4f0e32	5510803	MOTÉIS	t	ALOJAMENTO E ALIMENTAÇÃO	ALOJAMENTO	HOTÉIS E SIMILARES	HOTÉIS E SIMILARES
eddae1ec-339f-409f-99c5-f6c35a39d35c	5590601	ALBERGUES, EXCETO ASSISTENCIAIS	t	ALOJAMENTO E ALIMENTAÇÃO	ALOJAMENTO	OUTROS TIPOS DE ALOJAMENTO NÃO ESPECIFICADOS ANTERIORMENTE	OUTROS TIPOS DE ALOJAMENTO NÃO ESPECIFICADOS ANTERIORMENTE
68b38970-f160-4dc5-93d1-6916759f7dbe	5590602	CAMPINGS	t	ALOJAMENTO E ALIMENTAÇÃO	ALOJAMENTO	OUTROS TIPOS DE ALOJAMENTO NÃO ESPECIFICADOS ANTERIORMENTE	OUTROS TIPOS DE ALOJAMENTO NÃO ESPECIFICADOS ANTERIORMENTE
36110942-0b2c-4e97-bde1-49f70788bd87	5590603	PENSÕES(ALOJAMENTO)	t	ALOJAMENTO E ALIMENTAÇÃO	ALOJAMENTO	OUTROS TIPOS DE ALOJAMENTO NÃO ESPECIFICADOS ANTERIORMENTE	OUTROS TIPOS DE ALOJAMENTO NÃO ESPECIFICADOS ANTERIORMENTE
8f90881f-a089-4080-b5f0-d64fb7bc93c5	5590699	OUTROS ALOJAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE	t	ALOJAMENTO E ALIMENTAÇÃO	ALOJAMENTO	OUTROS TIPOS DE ALOJAMENTO NÃO ESPECIFICADOS ANTERIORMENTE	OUTROS TIPOS DE ALOJAMENTO NÃO ESPECIFICADOS ANTERIORMENTE
0ff6fa3a-a9ff-479f-a28d-74a0711f3c29	5611201	RESTAURANTES E SIMILARES	t	ALOJAMENTO E ALIMENTAÇÃO	ALIMENTAÇÃO	RESTAURANTES E OUTROS SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS	RESTAURANTES E OUTROS ESTABELECIMENTOS DE SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS
1ccc89dd-1eec-4cd1-a9a3-fc7018a112a4	5611203	LANCHONETES, CASAS DE CHÁ, DE SUCOS E SIMILARES	t	ALOJAMENTO E ALIMENTAÇÃO	ALIMENTAÇÃO	RESTAURANTES E OUTROS SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS	RESTAURANTES E OUTROS ESTABELECIMENTOS DE SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS
05af5151-2dc8-482b-bf15-5ba4805722e3	5611204	BARES E OUTROS ESTABELECIMENTOS ESPECIALIZADOS EM SERVIR BEBIDAS, SEM ENTRETENIMENTO	t	ALOJAMENTO E ALIMENTAÇÃO	ALIMENTAÇÃO	RESTAURANTES E OUTROS SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS	RESTAURANTES E OUTROS ESTABELECIMENTOS DE SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS
c3e4f012-5fe1-4ac2-8652-be5855b903d7	5611205	BARES E OUTROS ESTABELECIMENTOS ESPECIALIZADOS EM SERVIR BEBIDAS, COM ENTRETENIMENTO	t	ALOJAMENTO E ALIMENTAÇÃO	ALIMENTAÇÃO	RESTAURANTES E OUTROS SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS	RESTAURANTES E OUTROS ESTABELECIMENTOS DE SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS
132b41a6-9601-4f8a-afbb-ffa190897efa	5612100	SERVIÇOS AMBULANTES DE ALIMENTAÇÃO	t	ALOJAMENTO E ALIMENTAÇÃO	ALIMENTAÇÃO	RESTAURANTES E OUTROS SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS	SERVIÇOS AMBULANTES DE ALIMENTAÇÃO
078e4331-4079-465a-891b-6682caeb265a	5620101	FORNECIMENTO DE ALIMENTOS PREPARADOS PREPONDERANTEMENTE PARA EMPRESAS	t	ALOJAMENTO E ALIMENTAÇÃO	ALIMENTAÇÃO	SERVIÇOS DE CATERING, BUFÊ E OUTROS SERVIÇOS DE COMIDA PREPARADA	SERVIÇOS DE CATERING, BUFÊ E OUTROS SERVIÇOS DE COMIDA PREPARADA
720a3cb3-be5e-47c5-898a-563362ddbffa	5620102	SERVIÇOS DE ALIMENTAÇÃO PARA EVENTOS E RECEPÇÕES - BUFÊ	t	ALOJAMENTO E ALIMENTAÇÃO	ALIMENTAÇÃO	SERVIÇOS DE CATERING, BUFÊ E OUTROS SERVIÇOS DE COMIDA PREPARADA	SERVIÇOS DE CATERING, BUFÊ E OUTROS SERVIÇOS DE COMIDA PREPARADA
3462f6f3-5447-4a7b-b513-ef517c99794b	5620103	CANTINAS - SERVIÇOS DE ALIMENTAÇÃO PRIVATIVOS	t	ALOJAMENTO E ALIMENTAÇÃO	ALIMENTAÇÃO	SERVIÇOS DE CATERING, BUFÊ E OUTROS SERVIÇOS DE COMIDA PREPARADA	SERVIÇOS DE CATERING, BUFÊ E OUTROS SERVIÇOS DE COMIDA PREPARADA
1af64002-21b7-4744-85df-0b8752be19e0	5620104	FORNECIMENTO DE ALIMENTOS PREPARADOS PREPONDERANTEMENTE PARA CONSUMO DOMICILIAR	t	ALOJAMENTO E ALIMENTAÇÃO	ALIMENTAÇÃO	SERVIÇOS DE CATERING, BUFÊ E OUTROS SERVIÇOS DE COMIDA PREPARADA	SERVIÇOS DE CATERING, BUFÊ E OUTROS SERVIÇOS DE COMIDA PREPARADA
90798a6b-59eb-429d-b146-d341e15540d4	5811500	EDIÇÃO DE LIVROS	t	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS ATIVIDADES DE EDIÇÃO	EDIÇÃO DE LIVROS
96d7a543-e28c-4f2a-ae25-f8801bf8ac10	5812301	EDIÇÃO DE JORNAIS DIÁRIOS	t	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS ATIVIDADES DE EDIÇÃO	EDIÇÃO DE JORNAIS
fecd5240-41cb-4ff3-8982-a949c90f9954	5812302	EDIÇÃO DE JORNAIS NÃO DIÁRIOS	t	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS ATIVIDADES DE EDIÇÃO	EDIÇÃO DE JORNAIS
9521f0cc-fef4-4c4f-94d3-ef6728c22f5f	5813100	EDIÇÃO DE REVISTAS	t	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS ATIVIDADES DE EDIÇÃO	EDIÇÃO DE REVISTAS
0855cb96-3940-4ded-b8c8-54e61e8ee75c	5819100	EDIÇÃO DE CADASTROS, LISTAS E DE OUTROS PRODUTOS GRÁFICOS	t	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS ATIVIDADES DE EDIÇÃO	EDIÇÃO DE CADASTROS, LISTAS E DE OUTROS PRODUTOS GRÁFICOS
9f18dae0-0e60-4cd2-aab4-6940c25e3f1f	5821200	EDIÇÃO INTEGRADA À IMPRESSÃO DE LIVROS	t	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO INTEGRADA À IMPRESSÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS PUBLICAÇÕES	EDIÇÃO INTEGRADA À IMPRESSÃO DE LIVROS
7ae010b1-8c95-4dad-aaab-94467179423c	5822101	EDIÇÃO INTEGRADA À IMPRESSÃO DE JORNAIS DIÁRIOS	t	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO INTEGRADA À IMPRESSÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS PUBLICAÇÕES	EDIÇÃO INTEGRADA À IMPRESSÃO DE JORNAIS
e88e047d-d966-4074-8fab-4772cc4f4543	5822102	EDIÇÃO INTEGRADA À IMPRESSÃO DE JORNAIS NÃO DIÁRIOS	t	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO INTEGRADA À IMPRESSÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS PUBLICAÇÕES	EDIÇÃO INTEGRADA À IMPRESSÃO DE JORNAIS
34cad32b-24e2-49f7-817b-40933feedc8e	5823900	EDIÇÃO INTEGRADA À IMPRESSÃO DE REVISTAS	t	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO INTEGRADA À IMPRESSÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS PUBLICAÇÕES	EDIÇÃO INTEGRADA À IMPRESSÃO DE REVISTAS
5348608b-6c8b-4f48-81be-a500eb215551	5829800	EDIÇÃO INTEGRADA À IMPRESSÃO DE CADASTROS, LISTAS E DE OUTROS PRODUTOS GRÁFICOS	t	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO INTEGRADA À IMPRESSÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS PUBLICAÇÕES	EDIÇÃO INTEGRADA À IMPRESSÃO DE CADASTROS, LISTAS E DE OUTROS PRODUTOS GRÁFICOS
e5212016-4fc6-4943-b58c-153afaeb1669	5911101	ESTÚDIOS CINEMATOGRÁFICOS	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO	ATIVIDADES DE PRODUÇÃO CINEMATOGRÁFICA, DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO
74d72393-4053-44bd-8a11-5d8eb7491cd6	5911102	PRODUÇÃO DE FILMES PARA PUBLICIDADE	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO	ATIVIDADES DE PRODUÇÃO CINEMATOGRÁFICA, DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO
3c13ae71-64af-4064-86d5-e12732edd72b	5911199	ATIVIDADES DE PRODUÇÃO CINEMATOGRÁFICA, DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO NÃO ESPECIFICADAS ANTERIORMENTE	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO	ATIVIDADES DE PRODUÇÃO CINEMATOGRÁFICA, DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO
b8b13038-04e6-4dc9-8ee8-d20ae6f7ae21	5912001	SERVIÇOS DE DUBLAGEM	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO	ATIVIDADES DE PÓS-PRODUÇÃO CINEMATOGRÁFICA, DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO
a1005b78-ba29-4a62-a812-6d2ca151cc90	5912002	SERVIÇOS DE MIXAGEM SONORA EM PRODUÇÃO AUDIOVISUAL	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO	ATIVIDADES DE PÓS-PRODUÇÃO CINEMATOGRÁFICA, DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO
4b9e2057-ea0e-420f-892b-06278a4c5812	5912099	ATIVIDADES DE PÓS PRODUÇÃO CINEMATOGRÁFICA, DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO NÃO ESPECIFICADAS ANTERIORMENTE	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO	ATIVIDADES DE PÓS-PRODUÇÃO CINEMATOGRÁFICA, DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO
c40c53c7-6216-470b-8f2d-c743a06ac4ce	5913800	DISTRIBUIÇÃO CINEMATOGRÁFICA, DE VÍDEO E DE PROGRAMAS DE TELEVISÃO	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO	DISTRIBUIÇÃO CINEMATOGRÁFICA, DE VÍDEO E DE PROGRAMAS DE TELEVISÃO
f0cbf8d0-43e4-41bf-9647-90d103bf640b	5914600	ATIVIDADES DE EXIBIÇÃO CINEMATOGRÁFICA	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO	ATIVIDADES DE EXIBIÇÃO CINEMATOGRÁFICA
923193b3-9509-421b-a523-3ffcc1693a94	5920100	ATIVIDADES DE GRAVAÇÃO DE SOM E DE EDIÇÃO DE MÚSICA	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA	ATIVIDADES DE GRAVAÇÃO DE SOM E DE EDIÇÃO DE MÚSICA	ATIVIDADES DE GRAVAÇÃO DE SOM E DE EDIÇÃO DE MÚSICA
154cef66-7fd8-43e0-8104-d1ecb6367ca4	6010100	ATIVIDADES DE RÁDIO	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DE RÁDIO E DE TELEVISÃO	ATIVIDADES DE RÁDIO	ATIVIDADES DE RÁDIO
86b65c9d-f5e0-4110-b5ee-2fc05bf42952	6021700	ATIVIDADES DE TELEVISÃO ABERTA	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DE RÁDIO E DE TELEVISÃO	ATIVIDADES DE TELEVISÃO	ATIVIDADES DE TELEVISÃO ABERTA
c4fbdd98-0603-49de-a240-b9c434aab12e	6022501	PROGRAMADORAS	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DE RÁDIO E DE TELEVISÃO	ATIVIDADES DE TELEVISÃO	PROGRAMADORAS E ATIVIDADES RELACIONADAS À TELEVISÃO POR ASSINATURA
0785217e-5d2c-4aec-b8ca-13e0de4b9ce8	6022502	ATIVIDADES RELACIONADAS À TELEVISÃO POR ASSINATURA, EXCETO PROGRAMADORAS	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DE RÁDIO E DE TELEVISÃO	ATIVIDADES DE TELEVISÃO	PROGRAMADORAS E ATIVIDADES RELACIONADAS À TELEVISÃO POR ASSINATURA
261704d7-c366-4682-bf6e-62762f39fb4b	6110801	SERVIÇOS DE TELEFONIA FIXA COMUTADA - STFC	t	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	TELECOMUNICAÇÕES POR FIO	TELECOMUNICAÇÕES POR FIO
f743e31f-b095-41ce-a32b-e2ae21089ca1	6110802	SERVIÇOS DE REDES DE TRANSPORTES DE TELECOMUNICAÇÕES - SRTT	t	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	TELECOMUNICAÇÕES POR FIO	TELECOMUNICAÇÕES POR FIO
cd7590e4-05c0-42e2-be81-ca620c91650c	6110803	SERVIÇOS DE COMUNICAÇÃO MULTIMÍDIA - SCM	t	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	TELECOMUNICAÇÕES POR FIO	TELECOMUNICAÇÕES POR FIO
e54dd318-0db4-4faa-b160-14f8487fd812	6110899	SERVIÇOS DE TELECOMUNICAÇÕES POR FIO NÃO ESPECIFICADOS ANTERIORMENTE	t	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	TELECOMUNICAÇÕES POR FIO	TELECOMUNICAÇÕES POR FIO
e7b776e9-24ba-4352-947e-9803db6a7bba	6120501	TELEFONIA MÓVEL CELULAR	t	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	TELECOMUNICAÇÕES SEM FIO	TELECOMUNICAÇÕES SEM FIO
7af084c4-424e-4a04-985b-85433850971b	6120502	SERVIÇO MÓVEL ESPECIALIZADO - SME	t	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	TELECOMUNICAÇÕES SEM FIO	TELECOMUNICAÇÕES SEM FIO
f16c42e0-cad7-4d1b-80f0-553010c9235a	6120599	SERVIÇOS DE TELECOMUNICAÇÕES SEM FIO NÃO ESPECIFICADOS ANTERIORMENTE	t	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	TELECOMUNICAÇÕES SEM FIO	TELECOMUNICAÇÕES SEM FIO
df15c8f4-5059-4efa-88c9-f0b601b8fcd5	6130200	TELECOMUNICAÇÕES POR SATÉLITE	t	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	TELECOMUNICAÇÕES POR SATÉLITE	TELECOMUNICAÇÕES POR SATÉLITE
3dbdf8f2-7c56-4819-b6bd-2a9692e57bba	6141800	OPERADORAS DE TELEVISÃO POR ASSINATURA POR CABO	t	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	OPERADORAS DE TELEVISÃO POR ASSINATURA	OPERADORAS DE TELEVISÃO POR ASSINATURA POR CABO
9baa640c-3a28-4f98-86ce-7626f9f1edae	6142600	OPERADORAS DE TELEVISÃO POR ASSINATURA POR MICROONDAS	t	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	OPERADORAS DE TELEVISÃO POR ASSINATURA	OPERADORAS DE TELEVISÃO POR ASSINATURA POR MICROONDAS
d84ff83c-e096-45c0-971f-dd2e4cc7ce2d	6143400	OPERADORAS DE TELEVISÃO POR ASSINATURA POR SATÉLITE	t	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	OPERADORAS DE TELEVISÃO POR ASSINATURA	OPERADORAS DE TELEVISÃO POR ASSINATURA POR SATÉLITE
a74b7966-97e6-48b9-b9fa-f867ed60c04b	6190601	PROVEDORES DE ACESSO ÀS REDES DE COMUNICAÇÕES	t	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	OUTRAS ATIVIDADES DE TELECOMUNICAÇÕES	OUTRAS ATIVIDADES DE TELECOMUNICAÇÕES
7a851720-6eef-4b56-9f14-3ea2b8460c63	6190602	PROVEDORES DE VOZ SOBRE PROTOCOLO INTERNET - VOIP	t	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	OUTRAS ATIVIDADES DE TELECOMUNICAÇÕES	OUTRAS ATIVIDADES DE TELECOMUNICAÇÕES
9b91cf4e-017f-4565-a0bf-b5c1c6310218	6190699	OUTRAS ATIVIDADES DE TELECOMUNICAÇÕES NÃO ESPECIFICADAS ANTERIORMENTE	t	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	OUTRAS ATIVIDADES DE TELECOMUNICAÇÕES	OUTRAS ATIVIDADES DE TELECOMUNICAÇÕES
18998704-f694-4055-b505-a1778f39db08	6201501	DESENVOLVIMENTO DE PROGRAMAS DE COMPUTADOR SOB ENCOMENDA	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	DESENVOLVIMENTO DE PROGRAMAS DE COMPUTADOR SOB ENCOMENDA
60ff8c67-25ae-429c-a46a-9182d65c1d50	6201502	WEB DESIGN	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	DESENVOLVIMENTO DE PROGRAMAS DE COMPUTADOR SOB ENCOMENDA
94f20a5f-45f3-4af2-8b49-af13f1222b29	6202300	DESENVOLVIMENTO E LICENCIAMENTO DE PROGRAMAS DE COMPUTADOR CUSTOMIZÁVEIS	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	DESENVOLVIMENTO E LICENCIAMENTO DE PROGRAMAS DE COMPUTADOR CUSTOMIZÁVEIS
53f46418-4774-4bed-89e0-e92d01be3b08	6203100	DESENVOLVIMENTO E LICENCIAMENTO DE PROGRAMAS DE COMPUTADOR NÃO CUSTOMIZÁVEIS	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	DESENVOLVIMENTO E LICENCIAMENTO DE PROGRAMAS DE COMPUTADOR NÃO-CUSTOMIZÁVEIS
5d11c643-2f05-45c6-987a-06ecbbe2ef75	6204000	CONSULTORIA EM TECNOLOGIA DA INFORMAÇÃO	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	CONSULTORIA EM TECNOLOGIA DA INFORMAÇÃO
8700faa1-990b-4924-a59d-42c8ea8b8671	6209100	SUPORTE TÉCNICO, MANUTENÇÃO E OUTROS SERVIÇOS EM TECNOLOGIA DA INFORMAÇÃO	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	SUPORTE TÉCNICO, MANUTENÇÃO E OUTROS SERVIÇOS EM TECNOLOGIA DA INFORMAÇÃO
f68e6ac6-6606-4be7-9444-94c9c24da693	6311900	TRATAMENTO DE DADOS, PROVEDORES DE SERVIÇOS DE APLICAÇÃO E SERVIÇOS DE HOSPEDAGEM NA INTERNET	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO	TRATAMENTO DE DADOS, HOSPEDAGEM NA INTERNET E OUTRAS ATIVIDADES RELACIONADAS	TRATAMENTO DE DADOS, PROVEDORES DE SERVIÇOS DE APLICAÇÃO E SERVIÇOS DE HOSPEDAGEM NA INTERNET
bf4dd4c9-b802-4be2-8675-5753d56a446c	6319400	PORTAIS, PROVEDORES DE CONTEÚDO E OUTROS SERVIÇOS DE INFORMAÇÃO NA INTERNET	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO	TRATAMENTO DE DADOS, HOSPEDAGEM NA INTERNET E OUTRAS ATIVIDADES RELACIONADAS	PORTAIS, PROVEDORES DE CONTEÚDO E OUTROS SERVIÇOS DE INFORMAÇÃO NA INTERNET
813c6ee3-40f5-4ead-99b3-ec374e8a170d	6391700	AGÊNCIAS DE NOTÍCIAS	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO	OUTRAS ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO	AGÊNCIAS DE NOTÍCIAS
9cf913a1-1382-4208-b129-066dfecb2075	6399200	OUTRAS ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO NÃO ESPECIFICADAS ANTERIORMENTE	t	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO	OUTRAS ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO	OUTRAS ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO NÃO ESPECIFICADAS ANTERIORMENTE
29c95a32-12c3-4b60-a04a-a6578e2fea1c	6410700	BANCO CENTRAL	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	BANCO CENTRAL	BANCO CENTRAL
e2611570-9a5c-44f4-b260-6ad036bb0de7	6421200	BANCOS COMERCIAIS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO MONETÁRIA - DEPÓSITOS À VISTA	BANCOS COMERCIAIS
bb938a0b-552e-457a-8814-69db0f05e2c5	6422100	BANCOS MÚLTIPLOS, COM CARTEIRA COMERCIAL	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO MONETÁRIA - DEPÓSITOS À VISTA	BANCOS MÚLTIPLOS, COM CARTEIRA COMERCIAL
6191fbc2-63b6-46f0-a3e1-2b16fa043a8b	6423900	CAIXAS ECONÔMICAS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO MONETÁRIA - DEPÓSITOS À VISTA	CAIXAS ECONÔMICAS
3e4fb8c0-4ba9-4785-80b8-c7ff727146a4	6424701	BANCOS COOPERATIVOS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO MONETÁRIA - DEPÓSITOS À VISTA	CRÉDITO COOPERATIVO
d81b2703-dfe5-437e-93f8-172dee023fda	6424702	COOPERATIVAS CENTRAIS DE CRÉDITO	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO MONETÁRIA - DEPÓSITOS À VISTA	CRÉDITO COOPERATIVO
7c110930-59c3-4b03-b8bb-e68a1c9e2212	6424703	COOPERATIVAS DE CRÉDITO MÚTUO	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO MONETÁRIA - DEPÓSITOS À VISTA	CRÉDITO COOPERATIVO
d555e109-1f04-4a4a-8c18-11c8ede58569	6424704	COOPERATIVAS DE CRÉDITO RURAL	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO MONETÁRIA - DEPÓSITOS À VISTA	CRÉDITO COOPERATIVO
f47c5b0a-3e67-4e48-b286-5ec4ab222962	6431000	BANCOS MÚLTIPLOS, SEM CARTEIRA COMERCIAL	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	BANCOS MÚLTIPLOS, SEM CARTEIRA COMERCIAL
72a9b041-52b8-4ec9-a74f-913cbdf81eb8	6432800	BANCOS DE INVESTIMENTO	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	BANCOS DE INVESTIMENTO
66a151c1-194b-420e-9767-94c7bacaaa79	6433600	BANCOS DE DESENVOLVIMENTO	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	BANCOS DE DESENVOLVIMENTO
892dcdf4-d891-4da2-825f-40d71fe9bb65	6434400	AGÊNCIAS DE FOMENTO	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	AGÊNCIAS DE FOMENTO
5a978527-3fd0-4cea-87c8-e7b9cf8977a6	6435201	SOCIEDADES DE CRÉDITO IMOBILIÁRIO	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	CRÉDITO IMOBILIÁRIO
e275eef2-37ba-468e-97d7-0a5bad7694ed	6435202	ASSOCIAÇÕES DE POUPANÇA E EMPRÉSTIMO	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	CRÉDITO IMOBILIÁRIO
cbc3ecb1-1b89-4557-b4dd-ef7675887bd0	6435203	COMPANHIAS HIPOTECÁRIAS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	CRÉDITO IMOBILIÁRIO
f4665601-40a5-4fc9-9a26-3666fb1a0c3d	6436100	SOCIEDADES DE CRÉDITO, FINANCIAMENTO E INVESTIMENTO - FINANCEIRAS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	SOCIEDADES DE CRÉDITO, FINANCIAMENTO E INVESTIMENTO - FINANCEIRAS
31fa12c7-2e92-4c1b-8830-7d945622298d	6437900	SOCIEDADES DE CRÉDITO AO MICROEMPREENDEDOR	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	SOCIEDADES DE CRÉDITO AO MICROEMPREENDEDOR
05c0ebf0-6067-4978-b74f-971b6e92538b	6438701	BANCOS DE CÂMBIO	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	BANCOS DE CAMBIO E OUTRAS INSTITUIÇÕES DE INTERMEDIAÇÃO NÃO-MONETÁRIA
f1092f88-3f15-4633-9b3f-9f088ef1a3b6	6438799	OUTRAS INSTITUIÇÕES DE INTERMEDIAÇÃO NÃO MONETÁRIA	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	BANCOS DE CAMBIO E OUTRAS INSTITUIÇÕES DE INTERMEDIAÇÃO NÃO-MONETÁRIA
3d3bb0f3-0525-4fb5-b052-fa8f0e3d972e	6440900	ARRENDAMENTO MERCANTIL	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ARRENDAMENTO MERCANTIL	ARRENDAMENTO MERCANTIL
1ece21c4-58f0-4187-81dc-0b36c28a9381	6450600	SOCIEDADES DE CAPITALIZAÇÃO	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	SOCIEDADES DE CAPITALIZAÇÃO	SOCIEDADES DE CAPITALIZAÇÃO
7f71ba7e-e213-4b43-85f3-b3e2b702c745	6461100	HOLDINGS DE INSTITUIÇÕES FINANCEIRAS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SOCIEDADES DE PARTICIPAÇÃO	HOLDINGS DE INSTITUIÇÕES FINANCEIRAS
aded6ac5-5d42-4b76-86b7-378371425a11	6462000	HOLDINGS DE INSTITUIÇÕES NÃO FINANCEIRAS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SOCIEDADES DE PARTICIPAÇÃO	HOLDINGS DE INSTITUIÇÕES NÃO-FINANCEIRAS
4bd0f179-90d1-42f1-b400-5eaffc92dd3d	6463800	OUTRAS SOCIEDADES DE PARTICIPAÇÃO, EXCETO HOLDINGS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SOCIEDADES DE PARTICIPAÇÃO	OUTRAS SOCIEDADES DE PARTICIPAÇÃO, EXCETO HOLDINGS
d318b409-e749-4dc2-a61e-63332b3c3244	6470101	FUNDOS DE INVESTIMENTO, EXCETO PREVIDENCIÁRIOS E IMOBILIÁRIOS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	FUNDOS DE INVESTIMENTO	FUNDOS DE INVESTIMENTO
e037cffe-a4d0-492f-890d-483fe185b92f	6470102	FUNDOS DE INVESTIMENTO PREVIDENCIÁRIOS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	FUNDOS DE INVESTIMENTO	FUNDOS DE INVESTIMENTO
a38c743e-29d2-4eb5-8c7c-b60fe0712cad	6470103	FUNDOS DE INVESTIMENTO IMOBILIÁRIOS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	FUNDOS DE INVESTIMENTO	FUNDOS DE INVESTIMENTO
9fcbc04b-621f-418c-9ff1-49633caf740b	6491300	SOCIEDADES DE FOMENTO MERCANTIL - FACTORING	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	SOCIEDADES DE FOMENTO MERCANTIL - FACTORING
ef58fd20-b762-48b6-9d42-d39cbb83b291	6492100	SECURITIZAÇÃO DE CRÉDITOS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	SECURITIZAÇÃO DE CRÉDITOS
84f25a1b-3372-456d-aa04-f6fc70f393d5	6493000	ADMINISTRAÇÃO DE CONSÓRCIOS PARA AQUISIÇÃO DE BENS E DIREITOS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	ADMINISTRAÇÃO DE CONSÓRCIOS PARA AQUISIÇÃO DE BENS E DIREITOS
8b724338-e094-4df8-b72e-8268483d886f	6499901	CLUBES DE INVESTIMENTO	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	OUTRAS ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
7bd18452-c253-4e8a-92ae-62a2e1702026	6499902	SOCIEDADES DE INVESTIMENTO	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	OUTRAS ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
a17ded18-dce8-46d1-8980-b81400c7fc5d	6499903	FUNDO GARANTIDOR DE CRÉDITO	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	OUTRAS ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
8e176a7c-02a3-490e-8a61-a0a25eef3daf	6499904	CAIXAS DE FINANCIAMENTO DE CORPORAÇÕES	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	OUTRAS ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
5658e3d0-42e5-4347-9863-9889bcced2a1	6499905	CONCESSÃO DE CRÉDITO PELAS OSCIP	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	OUTRAS ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
bc6f7845-6859-4708-9e14-8def771e8746	6499999	OUTRAS ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	OUTRAS ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
fd88ae9b-b4ab-4364-b638-90ba8e49865d	6511101	SOCIEDADE SEGURADORA DE SEGUROS VIDA	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	SEGUROS, RESSEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	SEGUROS DE VIDA E NÃO-VIDA	SEGUROS DE VIDA
43a2c5c6-75e0-4801-a176-88cfb6ce3cd8	6511102	PLANOS DE AUXÍLIO FUNERAL	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	SEGUROS, RESSEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	SEGUROS DE VIDA E NÃO-VIDA	SEGUROS DE VIDA
71b83eec-d5bc-436b-8796-7f396bd2be7d	6512000	SOCIEDADE SEGURADORA DE SEGUROS NÃO VIDA	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	SEGUROS, RESSEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	SEGUROS DE VIDA E NÃO-VIDA	SEGUROS NÃO-VIDA
8164e8e9-396a-4e2d-a2fa-d6b15970b41e	6520100	SOCIEDADE SEGURADORA DE SEGUROS SAÚDE	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	SEGUROS, RESSEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	SEGUROS-SAÚDE	SEGUROS-SAÚDE
4ec8b162-64c0-479b-b77f-42c2eb928bb6	6530800	RESSEGUROS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	SEGUROS, RESSEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	RESSEGUROS	RESSEGUROS
f4299bff-c726-4e5d-a14c-664d28b784cc	6541300	PREVIDÊNCIA COMPLEMENTAR FECHADA	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	SEGUROS, RESSEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	PREVIDÊNCIA COMPLEMENTAR	PREVIDÊNCIA COMPLEMENTAR FECHADA
d29c11a5-bdeb-4a80-ab4b-4c5207808f9c	6542100	PREVIDÊNCIA COMPLEMENTAR ABERTA	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	SEGUROS, RESSEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	PREVIDÊNCIA COMPLEMENTAR	PREVIDÊNCIA COMPLEMENTAR ABERTA
e7ec4da6-33c2-4b46-bf97-884396d823a2	6550200	PLANOS DE SAÚDE	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	SEGUROS, RESSEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	PLANOS DE SAÚDE	PLANOS DE SAÚDE
ec721afd-71fb-40b5-966d-e70adbb895a9	6611801	BOLSA DE VALORES	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ADMINISTRAÇÃO DE BOLSAS E MERCADOS DE BALCÃO ORGANIZADOS
cd085c76-2be6-4b55-9294-8c27ff296cc4	6611802	BOLSA DE MERCADORIAS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ADMINISTRAÇÃO DE BOLSAS E MERCADOS DE BALCÃO ORGANIZADOS
4b3c8eb6-35a7-43ad-86dd-3f636d622f02	6611803	BOLSA DE MERCADORIAS E FUTUROS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ADMINISTRAÇÃO DE BOLSAS E MERCADOS DE BALCÃO ORGANIZADOS
86ac74fa-4eec-40c8-bdcf-fb54cdd5ff14	6611804	ADMINISTRAÇÃO DE MERCADOS DE BALCÃO ORGANIZADOS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ADMINISTRAÇÃO DE BOLSAS E MERCADOS DE BALCÃO ORGANIZADOS
c777e618-1e57-4e05-b0f2-13e290a5a790	6612601	CORRETORAS DE TÍTULOS E VALORES MOBILIÁRIOS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES DE INTERMEDIÁRIOS EM TRANSAÇÕES DE TÍTULOS, VALORES MOBILIÁRIOS E MERCADORIAS
10ba21a5-6933-4a81-86b3-ecde57b1ab42	6612602	DISTRIBUIDORAS DE TÍTULOS E VALORES MOBILIÁRIOS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES DE INTERMEDIÁRIOS EM TRANSAÇÕES DE TÍTULOS, VALORES MOBILIÁRIOS E MERCADORIAS
8cbf1d75-f4b3-4d99-99c9-f904b7dc55aa	6612603	CORRETORAS DE CÂMBIO	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES DE INTERMEDIÁRIOS EM TRANSAÇÕES DE TÍTULOS, VALORES MOBILIÁRIOS E MERCADORIAS
a85a77c7-b7b6-4f16-bd73-2a6af451d46a	6612604	CORRETORAS DE CONTRATOS DE MERCADORIAS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES DE INTERMEDIÁRIOS EM TRANSAÇÕES DE TÍTULOS, VALORES MOBILIÁRIOS E MERCADORIAS
10ce0f56-b9fc-4ec3-b196-566c381f6e69	6612605	AGENTES DE INVESTIMENTOS EM APLICAÇÕES FINANCEIRAS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES DE INTERMEDIÁRIOS EM TRANSAÇÕES DE TÍTULOS, VALORES MOBILIÁRIOS E MERCADORIAS
d44aef85-2654-4965-afc2-a6f64339dc57	6613400	ADMINISTRAÇÃO DE CARTÕES DE CRÉDITO	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ADMINISTRAÇÃO DE CARTÕES DE CRÉDITO
411122e8-cdf7-4627-bd81-9d50a326874e	6619301	SERVIÇOS DE LIQUIDAÇÃO E CUSTÓDIA	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
f5834286-94af-4e19-9c9f-a7409ce3222a	6619302	CORRESPONDENTES DE INSTITUIÇÕES FINANCEIRAS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
30f69039-4fb7-4a6a-b114-bd62e7af0cb0	6619303	REPRESENTAÇÕES DE BANCOS ESTRANGEIROS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
036e196a-2b9a-4245-835e-b05a2f4a34ae	6619304	CAIXAS ELETRÔNICOS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
c905cb62-94ee-4f5a-a7cd-4ec7df4890fb	6619305	OPERADORAS DE CARTÕES DE DÉBITO	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
36947f84-ceb4-400a-a227-78cd4f898770	6619399	OUTRAS ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
5a626e77-b58d-43f7-b573-55214c0ba0f9	6621501	PERITOS E AVALIADORES DE SEGUROS	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SEGUROS, DA PREVIDÊNCIA COMPLEMENTAR E DOS PLANOS DE SAÚDE	AVALIAÇÃO DE RISCOS E PERDAS
646ac256-59f5-4233-b8cf-63508c9aa0b8	6621502	AUDITORIA E CONSULTORIA ATUARIAL	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SEGUROS, DA PREVIDÊNCIA COMPLEMENTAR E DOS PLANOS DE SAÚDE	AVALIAÇÃO DE RISCOS E PERDAS
a6876b12-360f-4f2e-8cbf-c0c17f873d0a	6622300	CORRETORES E AGENTES DE SEGUROS, DE PLANOS DE PREVIDÊNCIA COMPLEMENTAR E DE SAÚDE	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SEGUROS, DA PREVIDÊNCIA COMPLEMENTAR E DOS PLANOS DE SAÚDE	CORRETORES E AGENTES DE SEGUROS, DE PLANOS DE PREVIDÊNCIA COMPLEMENTAR E DE SAÚDE
2f54974b-ef3b-4164-8f38-474a7087421c	6629100	ATIVIDADES AUXILIARES DOS SEGUROS, DA PREVIDÊNCIA COMPLEMENTAR E DOS PLANOS DE SAÚDE NÃO ESPECIFICADAS ANTERIORMENTE	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SEGUROS, DA PREVIDÊNCIA COMPLEMENTAR E DOS PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SEGUROS, DA PREVIDÊNCIA COMPLEMENTAR E DOS PLANOS DE SAÚDE NÃO ESPECIFICADAS ANTERIORMENTE
b1a227b6-6a94-41b9-a529-e2f7fac979f1	6630400	ATIVIDADES DE ADMINISTRAÇÃO DE FUNDOS POR CONTRATO OU COMISSÃO	t	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES DE ADMINISTRAÇÃO DE FUNDOS POR CONTRATO OU COMISSÃO	ATIVIDADES DE ADMINISTRAÇÃO DE FUNDOS POR CONTRATO OU COMISSÃO
dab81e8a-7401-4477-8330-333f04c09d96	6810201	COMPRA E VENDA DE IMÓVEIS PRÓPRIOS	t	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS DE IMÓVEIS PRÓPRIOS	ATIVIDADES IMOBILIÁRIAS DE IMÓVEIS PRÓPRIOS
852f49ea-16c3-44af-b8a5-b30babf9f86a	6810202	ALUGUEL DE IMÓVEIS PRÓPRIOS	t	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS DE IMÓVEIS PRÓPRIOS	ATIVIDADES IMOBILIÁRIAS DE IMÓVEIS PRÓPRIOS
60fddf2a-dfed-4bf1-9ba5-d0adde4cef22	6810203	LOTEAMENTO DE IMÓVEIS PRÓPRIOS	t	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS DE IMÓVEIS PRÓPRIOS	ATIVIDADES IMOBILIÁRIAS DE IMÓVEIS PRÓPRIOS
05f92566-2c30-452b-818b-4e75df4715b4	6821801	CORRETAGEM NA COMPRA E VENDA E AVALIAÇÃO DE IMÓVEIS	t	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS POR CONTRATO OU COMISSÃO	INTERMEDIAÇÃO NA COMPRA, VENDA E ALUGUEL DE IMÓVEIS
6efdb81d-1f6c-464d-8676-80a6a6330521	6821802	CORRETAGEM NO ALUGUEL DE IMÓVEIS	t	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS POR CONTRATO OU COMISSÃO	INTERMEDIAÇÃO NA COMPRA, VENDA E ALUGUEL DE IMÓVEIS
72454a41-8385-4120-ac31-87ae68fb6229	6822600	GESTÃO E ADMINISTRAÇÃO DA PROPRIEDADE IMOBILIARIA	t	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS POR CONTRATO OU COMISSÃO	GESTÃO E ADMINISTRAÇÃO DA PROPRIEDADE IMOBILIÁRIA
8d37ace1-8c47-4ad1-bd05-1a3811458b27	6911701	SERVIÇOS ADVOCATÍCIOS	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES JURÍDICAS, DE CONTABILIDADE E DE AUDITORIA	ATIVIDADES JURÍDICAS	ATIVIDADES JURÍDICAS, EXCETO CARTÓRIOS
8c99dd79-933f-4b8a-8a82-e271e9a3ccf0	6911702	ATIVIDADES AUXILIARES DA JUSTIÇA	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES JURÍDICAS, DE CONTABILIDADE E DE AUDITORIA	ATIVIDADES JURÍDICAS	ATIVIDADES JURÍDICAS, EXCETO CARTÓRIOS
8c2d5136-994d-42f6-a982-8cbf0d51081f	6911703	AGENTE DE PROPRIEDADE INDUSTRIAL	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES JURÍDICAS, DE CONTABILIDADE E DE AUDITORIA	ATIVIDADES JURÍDICAS	ATIVIDADES JURÍDICAS, EXCETO CARTÓRIOS
65d45a91-c7d1-4f23-82c6-9277c4bd24d2	6912500	CARTÓRIOS	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES JURÍDICAS, DE CONTABILIDADE E DE AUDITORIA	ATIVIDADES JURÍDICAS	CARTÓRIOS
d2491433-4553-4694-9d9d-35a818d85060	6920601	ATIVIDADES DE CONTABILIDADE	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES JURÍDICAS, DE CONTABILIDADE E DE AUDITORIA	ATIVIDADES DE CONTABILIDADE, CONSULTORIA E AUDITORIA CONTÁBIL E TRIBUTÁRIA	ATIVIDADES DE CONTABILIDADE, CONSULTORIA E AUDITORIA CONTÁBIL E TRIBUTÁRIA
183fc44d-8a0d-4acb-aaa0-78232edd19ce	6920602	ATIVIDADES DE CONSULTORIA E AUDITORIA CONTÁBIL E TRIBUTÁRIA	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES JURÍDICAS, DE CONTABILIDADE E DE AUDITORIA	ATIVIDADES DE CONTABILIDADE, CONSULTORIA E AUDITORIA CONTÁBIL E TRIBUTÁRIA	ATIVIDADES DE CONTABILIDADE, CONSULTORIA E AUDITORIA CONTÁBIL E TRIBUTÁRIA
39f0dbaf-ee30-422b-930b-6ee586ad8947	7020400	ATIVIDADES DE CONSULTORIA EM GESTÃO EMPRESARIAL, EXCETO CONSULTORIA TÉCNICA ESPECÍFICA	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES DE SEDES DE EMPRESAS E DE CONSULTORIA EM GESTÃO EMPRESARIAL	ATIVIDADES DE CONSULTORIA EM GESTÃO EMPRESARIAL	ATIVIDADES DE CONSULTORIA EM GESTÃO EMPRESARIAL
eb2fb5b2-62b5-491a-85c3-ec7114a6e251	7111100	SERVIÇOS DE ARQUITETURA	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA; TESTES E ANÁLISES TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA E ATIVIDADES TÉCNICAS RELACIONADAS	SERVIÇOS DE ARQUITETURA
8cac0695-8b83-4fc3-b53a-8de5754e358d	7112000	SERVIÇOS DE ENGENHARIA	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA; TESTES E ANÁLISES TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA E ATIVIDADES TÉCNICAS RELACIONADAS	SERVIÇOS DE ENGENHARIA
a29a8f4f-5f48-45d1-9cf6-7bf4f6d5fe79	7119701	SERVIÇOS DE CARTOGRAFIA, TOPOGRAFIA E GEODÉSIA	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA; TESTES E ANÁLISES TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA E ATIVIDADES TÉCNICAS RELACIONADAS	ATIVIDADES TÉCNICAS RELACIONADAS À ARQUITETURA E ENGENHARIA
57dca079-17dd-4a00-a561-4587de7d0eb4	7119702	ATIVIDADES DE ESTUDOS GEOLÓGICOS	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA; TESTES E ANÁLISES TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA E ATIVIDADES TÉCNICAS RELACIONADAS	ATIVIDADES TÉCNICAS RELACIONADAS À ARQUITETURA E ENGENHARIA
1df7e242-ff0d-4845-92f9-5b0ab8eb0e7f	7119703	SERVIÇOS DE DESENHO TÉCNICO RELACIONADOS À ARQUITETURA E ENGENHARIA	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA; TESTES E ANÁLISES TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA E ATIVIDADES TÉCNICAS RELACIONADAS	ATIVIDADES TÉCNICAS RELACIONADAS À ARQUITETURA E ENGENHARIA
634411bc-9d61-40df-8c0c-5e25e4d08a9f	7119704	SERVIÇOS DE PERÍCIA TÉCNICA RELACIONADOS À SEGURANÇA DO TRABALHO	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA; TESTES E ANÁLISES TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA E ATIVIDADES TÉCNICAS RELACIONADAS	ATIVIDADES TÉCNICAS RELACIONADAS À ARQUITETURA E ENGENHARIA
9fb3003f-ddb7-4dd4-8ed3-ef23a3936f77	7119799	ATIVIDADES TÉCNICAS RELACIONADAS À ENGENHARIA E ARQUITETURA NÃO ESPECIFICADAS ANTERIORMENTE	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA; TESTES E ANÁLISES TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA E ATIVIDADES TÉCNICAS RELACIONADAS	ATIVIDADES TÉCNICAS RELACIONADAS À ARQUITETURA E ENGENHARIA
a6da5ff4-4eff-4c25-a132-35285d5ccfcf	7120100	TESTES E ANÁLISES TÉCNICAS	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA; TESTES E ANÁLISES TÉCNICAS	TESTES E ANÁLISES TÉCNICAS	TESTES E ANÁLISES TÉCNICAS
6f83b01a-85ac-4c2b-94bf-4c471cd7c66d	7210000	PESQUISA E DESENVOLVIMENTO EXPERIMENTAL EM CIÊNCIAS FÍSICAS E NATURAIS	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PESQUISA E DESENVOLVIMENTO CIENTÍFICO	PESQUISA E DESENVOLVIMENTO EXPERIMENTAL EM CIÊNCIAS FÍSICAS E NATURAIS	PESQUISA E DESENVOLVIMENTO EXPERIMENTAL EM CIÊNCIAS FÍSICAS E NATURAIS
c6de5fbe-e537-4c3d-8de6-3cea1a3f151e	7220700	PESQUISA E DESENVOLVIMENTO EXPERIMENTAL EM CIÊNCIAS SOCIAIS E HUMANAS	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PESQUISA E DESENVOLVIMENTO CIENTÍFICO	PESQUISA E DESENVOLVIMENTO EXPERIMENTAL EM CIÊNCIAS SOCIAIS E HUMANAS	PESQUISA E DESENVOLVIMENTO EXPERIMENTAL EM CIÊNCIAS SOCIAIS E HUMANAS
6abc8f49-4fd6-4802-862a-bf6c1746d52b	7311400	AGÊNCIAS DE PUBLICIDADE	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PUBLICIDADE E PESQUISA DE MERCADO	PUBLICIDADE	AGÊNCIAS DE PUBLICIDADE
6d919521-1e46-47da-8d7a-a771784666de	7312200	AGENCIAMENTO DE ESPAÇOS PARA PUBLICIDADE, EXCETO EM VEÍCULOS DE COMUNICAÇÃO	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PUBLICIDADE E PESQUISA DE MERCADO	PUBLICIDADE	AGENCIAMENTO DE ESPAÇOS PARA PUBLICIDADE, EXCETO EM VEÍCULOS DE COMUNICAÇÃO
b3e6c226-4634-4145-9e8e-61cddad998e1	7319001	CRIAÇÃO ESTANDES PARA FEIRAS E EXPOSIÇÕES	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PUBLICIDADE E PESQUISA DE MERCADO	PUBLICIDADE	ATIVIDADES DE PUBLICIDADE NÃO ESPECIFICADAS ANTERIORMENTE
3ba286a2-29e3-4db2-8e19-4beec78e9d8c	7319002	PROMOÇÃO DE VENDAS	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PUBLICIDADE E PESQUISA DE MERCADO	PUBLICIDADE	ATIVIDADES DE PUBLICIDADE NÃO ESPECIFICADAS ANTERIORMENTE
f32d3f18-a6e8-4d0e-8759-e2775d0e7e64	7319003	MARKETING DIRETO	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PUBLICIDADE E PESQUISA DE MERCADO	PUBLICIDADE	ATIVIDADES DE PUBLICIDADE NÃO ESPECIFICADAS ANTERIORMENTE
47130b59-e34f-4fac-b783-5d260651a806	7319004	CONSULTORIA EM PUBLICIDADE	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PUBLICIDADE E PESQUISA DE MERCADO	PUBLICIDADE	ATIVIDADES DE PUBLICIDADE NÃO ESPECIFICADAS ANTERIORMENTE
7eadef77-fac5-474e-86d2-69c097ad537b	7319099	OUTRAS ATIVIDADES DE PUBLICIDADE NÃO ESPECIFICADAS ANTERIORMENTE	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PUBLICIDADE E PESQUISA DE MERCADO	PUBLICIDADE	ATIVIDADES DE PUBLICIDADE NÃO ESPECIFICADAS ANTERIORMENTE
fce14087-1f60-4b40-96b9-1d83e59adcf6	7320300	PESQUISAS DE MERCADO E DE OPINIÃO PÚBLICA	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PUBLICIDADE E PESQUISA DE MERCADO	PESQUISAS DE MERCADO E DE OPINIÃO PÚBLICA	PESQUISAS DE MERCADO E DE OPINIÃO PÚBLICA
b9259a23-04fc-4800-85ad-860e16205262	7410202	DESIGN DE INTERIORES	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	DESIGN E DECORAÇÃO DE INTERIORES	DESIGN E DECORAÇÃO DE INTERIORES
452976b3-f9c5-4123-8101-69b8e1539663	7410203	DESIGN DE PRODUTO	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	DESIGN E DECORAÇÃO DE INTERIORES	DESIGN E DECORAÇÃO DE INTERIORES
6b859582-a24d-4409-ac21-aa37b6742f14	7410299	ATIVIDADES DE DESIGN NÃO ESPECIFICADAS ANTERIORMENTE	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	DESIGN E DECORAÇÃO DE INTERIORES	DESIGN E DECORAÇÃO DE INTERIORES
c3f99b31-cfa8-4d9d-a508-6a2f0619581f	7420001	ATIVIDADES DE PRODUÇÃO DE FOTOGRAFIAS, EXCETO AÉREA E SUBMARINA	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES FOTOGRÁFICAS E SIMILARES	ATIVIDADES FOTOGRÁFICAS E SIMILARES
10ffd174-a47f-44fc-81a8-2ab028e0b3f0	7420002	ATIVIDADES DE PRODUÇÃO DE FOTOGRAFIAS AÉREAS E SUBMARINAS	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES FOTOGRÁFICAS E SIMILARES	ATIVIDADES FOTOGRÁFICAS E SIMILARES
27c879be-751f-4e95-abff-9fe8cf6ff06b	7420003	LABORATÓRIOS FOTOGRÁFICOS	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES FOTOGRÁFICAS E SIMILARES	ATIVIDADES FOTOGRÁFICAS E SIMILARES
0f394924-d88a-4d5b-89c7-226c0bcaabd6	7420004	FILMAGEM DE FESTAS E EVENTOS	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES FOTOGRÁFICAS E SIMILARES	ATIVIDADES FOTOGRÁFICAS E SIMILARES
3b0cbda1-564d-4285-9b44-623b62f8ac9e	7420005	SERVIÇOS DE MICROFILMAGEM	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES FOTOGRÁFICAS E SIMILARES	ATIVIDADES FOTOGRÁFICAS E SIMILARES
cda3bf53-9c86-4fbb-add6-2cc4437a6db0	7490101	SERVIÇOS DE TRADUÇÃO, INTERPRETAÇÃO E SIMILARES	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE
9dd8c764-babf-4fdc-bac1-08dfb50b2d9b	7490102	ESCAFANDRIA E MERGULHO	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE
0f32e071-2fa3-4cc5-9d4d-1019eb47fa42	7490103	SERVIÇOS DE AGRONOMIA E DE CONSULTORIA ÀS ATIVIDADES AGRÍCOLAS E PECUÁRIAS	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE
ca1a7ea4-db6a-4535-8964-742c9f1f6a4f	7490104	ATIVIDADES DE INTERMEDIAÇÃO E AGENCIAMENTO DE SERVIÇOS E NEGÓCIOS EM GERAL, EXCETO IMOBILIÁRIOS	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE
1b72d738-4d38-4911-9472-e5a4e2cf9ab0	7490105	AGENCIAMENTO DE PROFISSIONAIS PARA ATIVIDADES ESPORTIVAS, CULTURAIS E ARTÍSTICAS	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE
ef14bffc-ec88-4a7f-99a2-1f72e3f5b31f	7490199	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE
719491af-28f9-4ed6-b21a-bc17a1f97e1e	7500100	ATIVIDADES VETERINÁRIAS	t	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES VETERINÁRIAS	ATIVIDADES VETERINÁRIAS	ATIVIDADES VETERINÁRIAS
9a4d2a45-0d79-465b-8a54-be79d1ae1dfb	7711000	LOCAÇÃO DE AUTOMÓVEIS SEM CONDUTOR	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	LOCAÇÃO DE MEIOS DE TRANSPORTE SEM CONDUTOR	LOCAÇÃO DE AUTOMÓVEIS SEM CONDUTOR
71cb7882-0224-4386-bdf2-579e926822df	7719501	LOCAÇÃO DE EMBARCAÇÕES SEM TRIPULAÇÃO, EXCETO PARA FINS RECREATIVOS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	LOCAÇÃO DE MEIOS DE TRANSPORTE SEM CONDUTOR	LOCAÇÃO DE MEIOS DE TRANSPORTE, EXCETO AUTOMÓVEIS, SEM CONDUTOR
ba2f3f6c-6f16-433b-b354-76920e1a8311	7719502	LOCAÇÃO DE AERONAVES SEM TRIPULAÇÃO	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	LOCAÇÃO DE MEIOS DE TRANSPORTE SEM CONDUTOR	LOCAÇÃO DE MEIOS DE TRANSPORTE, EXCETO AUTOMÓVEIS, SEM CONDUTOR
efd57120-1995-4047-a97d-bbb270cd89a3	7719599	LOCAÇÃO DE OUTROS MEIOS DE TRANSPORTE NÃO ESPECIFICADOS ANTERIORMENTE, SEM CONDUTOR	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	LOCAÇÃO DE MEIOS DE TRANSPORTE SEM CONDUTOR	LOCAÇÃO DE MEIOS DE TRANSPORTE, EXCETO AUTOMÓVEIS, SEM CONDUTOR
252dd500-9ab2-488d-b21b-2c40475e620a	7721700	ALUGUEL DE EQUIPAMENTOS RECREATIVOS E ESPORTIVOS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS	ALUGUEL DE EQUIPAMENTOS RECREATIVOS E ESPORTIVOS
daab4ffa-b348-4eea-a7aa-16fe587155b4	7722500	ALUGUEL DE FITAS DE VÍDEO, DVDS E SIMILARES	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS	ALUGUEL DE FITAS DE VÍDEO, DVDS E SIMILARES
f766f727-c2ec-45da-a210-8410b73d519b	7723300	ALUGUEL DE OBJETOS DO VESTUÁRIO, JÓIAS E ACESSÓRIOS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS	ALUGUEL DE OBJETOS DO VESTUÁRIO, JÓIAS E ACESSÓRIOS
2ce3a706-906d-49be-94fc-179757fe849d	7729201	ALUGUEL DE APARELHOS DE JOGOS ELETRÔNICOS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
533f1345-2382-4654-b6c4-7a3d711c4d9c	7729202	ALUGUEL DE MÓVEIS, UTENSÍLIOS E APARELHOS DE USO DOMÉSTICO E PESSOAL; INSTRUMENTOS MUSICAIS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
e525681c-cf80-4b0d-88be-e3ea4e3108b0	7729203	ALUGUEL DE MATERIAL MÉDICO	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
8a606bca-3357-4771-a4fc-227ccc164d01	7729299	ALUGUEL DE OUTROS OBJETOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
c4fe2bee-0538-4f56-9537-43f5fab195f6	7731400	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS AGRÍCOLAS SEM OPERADOR	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS SEM OPERADOR	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS AGRÍCOLAS SEM OPERADOR
e26694c7-2b9f-4fbc-9496-e880bfe4e6c8	7732201	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS PARA CONSTRUÇÃO SEM OPERADOR, EXCETO ANDAIMES	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS SEM OPERADOR	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS PARA CONSTRUÇÃO SEM OPERADOR
b8a6d30d-abab-4f92-a27d-b8a188365244	7732202	ALUGUEL DE ANDAIMES	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS SEM OPERADOR	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS PARA CONSTRUÇÃO SEM OPERADOR
d74d44dd-1ecd-4d13-9c9e-5fb1af115950	7733100	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS PARA ESCRITÓRIOS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS SEM OPERADOR	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS PARA ESCRITÓRIOS
5d56d493-09fb-4c2f-a1b8-e715cc2f7f7c	7739001	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS PARA EXTRAÇÃO DE MINÉRIOS E PETRÓLEO, SEM OPERADOR	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS SEM OPERADOR	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE
52b332d9-0cad-43a1-b783-4d76d3ee999d	7739002	ALUGUEL DE EQUIPAMENTOS CIENTÍFICOS, MÉDICOS E HOSPITALARES, SEM OPERADOR	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS SEM OPERADOR	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE
01b56ce3-95f9-4627-b25e-8aef02fb11bd	7739003	ALUGUEL DE PALCOS, COBERTURAS E OUTRAS ESTRUTURAS DE USO TEMPORÁRIO, EXCETO ANDAIMES	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS SEM OPERADOR	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE
a8e27ea4-d6de-4540-a64d-74106ac5c504	7739099	ALUGUEL DE OUTRAS MÁQUINAS E EQUIPAMENTOS COMERCIAIS E INDUSTRIAIS NÃO ESPECIFICADOS ANTERIORMENTE, SEM OPERADOR	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS SEM OPERADOR	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE
5ba697ea-8a06-48e1-bef2-101053e8d943	7740300	GESTÃO DE ATIVOS INTANGÍVEIS NÃO FINANCEIROS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS
0ee07837-e622-4bd4-b591-a73eac41f88e	7810800	SELEÇÃO E AGENCIAMENTO DE MÃO DE OBRA	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SELEÇÃO, AGENCIAMENTO E LOCAÇÃO DE MÃO-DE-OBRA	SELEÇÃO E AGENCIAMENTO DE MÃO-DE-OBRA	SELEÇÃO E AGENCIAMENTO DE MÃO-DE-OBRA
1a6d64f4-9b38-4611-aa58-f8a1c9be4582	7820500	LOCAÇÃO DE MÃO DE OBRA TEMPORÁRIA	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SELEÇÃO, AGENCIAMENTO E LOCAÇÃO DE MÃO-DE-OBRA	LOCAÇÃO DE MÃO-DE-OBRA TEMPORÁRIA	LOCAÇÃO DE MÃO-DE-OBRA TEMPORÁRIA
0a7de335-97af-4d80-9111-73baa1a80b97	7830200	FORNECIMENTO E GESTÃO DE RECURSOS HUMANOS PARA TERCEIROS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SELEÇÃO, AGENCIAMENTO E LOCAÇÃO DE MÃO-DE-OBRA	FORNECIMENTO E GESTÃO DE RECURSOS HUMANOS PARA TERCEIROS	FORNECIMENTO E GESTÃO DE RECURSOS HUMANOS PARA TERCEIROS
bd0e0be6-fe03-4f5f-b49c-68042a34e0a4	7911200	AGÊNCIAS DE VIAGENS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	AGÊNCIAS DE VIAGENS, OPERADORES TURÍSTICOS E SERVIÇOS DE RESERVAS	AGÊNCIAS DE VIAGENS E OPERADORES TURÍSTICOS	AGÊNCIAS DE VIAGENS
6300f984-fc47-46e6-aeae-947476e57b2e	7912100	OPERADORES TURÍSTICOS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	AGÊNCIAS DE VIAGENS, OPERADORES TURÍSTICOS E SERVIÇOS DE RESERVAS	AGÊNCIAS DE VIAGENS E OPERADORES TURÍSTICOS	OPERADORES TURÍSTICOS
4bcf2df1-1675-4bd6-a36f-dd6d067411a3	7990200	SERVIÇOS DE RESERVAS E OUTROS SERVIÇOS DE TURISMO NÃO ESPECIFICADOS ANTERIORMENTE	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	AGÊNCIAS DE VIAGENS, OPERADORES TURÍSTICOS E SERVIÇOS DE RESERVAS	SERVIÇOS DE RESERVAS E OUTROS SERVIÇOS DE TURISMO NÃO ESPECIFICADOS ANTERIORMENTE	SERVIÇOS DE RESERVAS E OUTROS SERVIÇOS DE TURISMO NÃO ESPECIFICADOS ANTERIORMENTE
61b67098-f820-4657-bea0-dc2423b5b7f2	8011101	ATIVIDADES DE VIGILÂNCIA E SEGURANÇA PRIVADA	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA E INVESTIGAÇÃO	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA PRIVADA E TRANSPORTE DE VALORES	ATIVIDADES DE VIGILÂNCIA E SEGURANÇA PRIVADA
b8a357d8-cae2-4472-9623-6dd7ff922a10	8011102	SERVIÇOS DE ADESTRAMENTO DE CÃES DE GUARDA	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA E INVESTIGAÇÃO	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA PRIVADA E TRANSPORTE DE VALORES	ATIVIDADES DE VIGILÂNCIA E SEGURANÇA PRIVADA
70e9374b-0e4b-4cd2-91c8-a2399e552779	8012900	ATIVIDADES DE TRANSPORTE DE VALORES	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA E INVESTIGAÇÃO	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA PRIVADA E TRANSPORTE DE VALORES	ATIVIDADES DE TRANSPORTE DE VALORES
cbee04ba-8adb-44a7-a698-9d12b5d91066	8020001	ATIVIDADES DE MONITORAMENTO DE SISTEMAS DE SEGURANÇA ELETRÔNICO	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA E INVESTIGAÇÃO	ATIVIDADES DE MONITORAMENTO DE SISTEMAS DE SEGURANÇA	ATIVIDADES DE MONITORAMENTO DE SISTEMAS DE SEGURANÇA
326a5e50-b22a-4807-8e6f-e11cd624d692	8020002	OUTRAS ATIVIDADES DE SERVIÇOS DE SEGURANÇA	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA E INVESTIGAÇÃO	ATIVIDADES DE MONITORAMENTO DE SISTEMAS DE SEGURANÇA	ATIVIDADES DE MONITORAMENTO DE SISTEMAS DE SEGURANÇA
60360295-feb6-4542-98e8-14a8cdcd9014	8030700	ATIVIDADES DE INVESTIGAÇÃO PARTICULAR	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA E INVESTIGAÇÃO	ATIVIDADES DE INVESTIGAÇÃO PARTICULAR	ATIVIDADES DE INVESTIGAÇÃO PARTICULAR
a9782d06-1936-4e04-b00e-6985b2e798be	8111700	SERVIÇOS COMBINADOS PARA APOIO A EDIFÍCIOS, EXCETO CONDOMÍNIOS PREDIAIS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS PARA EDIFÍCIOS E ATIVIDADES PAISAGÍSTICAS	SERVIÇOS COMBINADOS PARA APOIO A EDIFÍCIOS	SERVIÇOS COMBINADOS PARA APOIO A EDIFÍCIOS, EXCETO CONDOMÍNIOS PREDIAIS
3068dfc6-1887-4157-83e2-585464fe92a7	8112500	CONDOMÍNIOS PREDIAIS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS PARA EDIFÍCIOS E ATIVIDADES PAISAGÍSTICAS	SERVIÇOS COMBINADOS PARA APOIO A EDIFÍCIOS	CONDOMÍNIOS PREDIAIS
1d8d8d7d-d3de-4e8d-8091-174a490a6933	8121400	LIMPEZA EM PRÉDIOS E EM DOMICÍLIOS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS PARA EDIFÍCIOS E ATIVIDADES PAISAGÍSTICAS	ATIVIDADES DE LIMPEZA	LIMPEZA EM PRÉDIOS E EM DOMICÍLIOS
0e0b2831-cfeb-477b-b43b-ade90a367ef9	8122200	IMUNIZAÇÃO E CONTROLE DE PRAGAS URBANAS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS PARA EDIFÍCIOS E ATIVIDADES PAISAGÍSTICAS	ATIVIDADES DE LIMPEZA	IMUNIZAÇÃO E CONTROLE DE PRAGAS URBANAS
7f967fe7-8ccb-4076-8b4d-9a7ca3d34daf	8129000	ATIVIDADES DE LIMPEZA NÃO ESPECIFICADAS ANTERIORMENTE	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS PARA EDIFÍCIOS E ATIVIDADES PAISAGÍSTICAS	ATIVIDADES DE LIMPEZA	ATIVIDADES DE LIMPEZA NÃO ESPECIFICADAS ANTERIORMENTE
50fb5c6b-6475-4215-a205-e0b6ee4a3dd9	8130300	ATIVIDADES PAISAGÍSTICAS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS PARA EDIFÍCIOS E ATIVIDADES PAISAGÍSTICAS	ATIVIDADES PAISAGÍSTICAS	ATIVIDADES PAISAGÍSTICAS
a8c82b1e-901b-4f78-9513-868fb71c0d6b	8211300	SERVIÇOS COMBINADOS DE ESCRITÓRIO E APOIO ADMINISTRATIVO	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	SERVIÇOS DE ESCRITÓRIO E APOIO ADMINISTRATIVO	SERVIÇOS COMBINADOS DE ESCRITÓRIO E APOIO ADMINISTRATIVO
1b04e0ad-af66-4ee2-8426-6b46d65040c3	8219901	FOTOCÓPIAS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	SERVIÇOS DE ESCRITÓRIO E APOIO ADMINISTRATIVO	FOTOCÓPIAS, PREPARAÇÃO DE DOCUMENTOS E OUTROS SERVIÇOS ESPECIALIZADOS DE APOIO ADMINISTRATIVO
ab3872b9-75f9-46d1-9175-fb377909d62b	8219999	PREPARAÇÃO DE DOCUMENTOS E SERVIÇOS ESPECIALIZADOS DE APOIO ADMINISTRATIVO NÃO ESPECIFICADOS ANTERIORMENTE	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	SERVIÇOS DE ESCRITÓRIO E APOIO ADMINISTRATIVO	FOTOCÓPIAS, PREPARAÇÃO DE DOCUMENTOS E OUTROS SERVIÇOS ESPECIALIZADOS DE APOIO ADMINISTRATIVO
2d9f70c7-e304-4383-a5ed-85d0a8a7f24e	8220200	ATIVIDADES DE TELEATENDIMENTO	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE TELEATENDIMENTO	ATIVIDADES DE TELEATENDIMENTO
05e12ffd-2c5c-4c3d-a717-80f378b777e6	8230001	SERVIÇOS DE ORGANIZAÇÃO DE FEIRAS, CONGRESSOS, EXPOSIÇÕES E FESTAS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE ORGANIZAÇÃO DE EVENTOS, EXCETO CULTURAIS E ESPORTIVOS	ATIVIDADES DE ORGANIZAÇÃO DE EVENTOS, EXCETO CULTURAIS E ESPORTIVOS
72fb996f-f2b9-4d51-a8f6-5a1ce6aa11a8	8230002	CASAS DE FESTAS E EVENTOS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE ORGANIZAÇÃO DE EVENTOS, EXCETO CULTURAIS E ESPORTIVOS	ATIVIDADES DE ORGANIZAÇÃO DE EVENTOS, EXCETO CULTURAIS E ESPORTIVOS
b31c1da8-6350-481d-922f-398504e981b3	8291100	ATIVIDADES DE COBRANÇAS E INFORMAÇÕES CADASTRAIS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE COBRANÇAS E INFORMAÇÕES CADASTRAIS
13d2e5f2-fbab-44c0-8660-5c0a7dcc248e	8292000	ENVASAMENTO E EMPACOTAMENTO SOB CONTRATO	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ENVASAMENTO E EMPACOTAMENTO SOB CONTRATO
db684de4-6499-4455-b60a-ed007f9d474d	8299701	MEDIÇÃO DE CONSUMO DE ENERGIA ELÉTRICA, GÁS E ÁGUA	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE
46bf54e5-9d4e-4249-9a3e-bc011930ac23	8299702	EMISSÃO DE VALES ALIMENTAÇÃO, VALES TRANSPORTE E SIMILARES	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE
b2ffac3e-199c-49e8-b0fa-5963a73a75cb	8299703	SERVIÇOS DE GRAVAÇÃO DE CARIMBOS, EXCETO CONFECÇÃO	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE
a96c4970-831b-49af-9b98-27d534a083ff	8299704	LEILOEIROS INDEPENDENTES	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE
f3f267b8-ccd2-4b19-99b1-73889589a000	8299705	SERVIÇOS DE LEVANTAMENTO DE FUNDOS SOB CONTRATO	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE
bfb96bef-6a70-427d-a67c-edd419d8fb05	8299706	CASAS LOTÉRICAS	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE
9b4473e6-7535-4d39-9adb-d5512a6c365a	8299707	SALAS DE ACESSO À INTERNET	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE
5c386f85-c3c2-4f08-b681-b62bf1ea4c44	8299799	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE	t	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE
31b4b4ca-fa31-4fe0-8eb7-328c68526d54	8411600	ADMINISTRAÇÃO PÚBLICA EM GERAL	t	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO DO ESTADO E DA POLÍTICA ECONÔMICA E SOCIAL	ADMINISTRAÇÃO PÚBLICA EM GERAL
56e72adb-d177-4989-8cd3-7a3be587b102	8412400	REGULAÇÃO DAS ATIVIDADES DE SAÚDE, EDUCAÇÃO, SERVIÇOS CULTURAIS E OUTROS SERVIÇOS SOCIAIS	t	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO DO ESTADO E DA POLÍTICA ECONÔMICA E SOCIAL	REGULAÇÃO DAS ATIVIDADES DE SAÚDE, EDUCAÇÃO, SERVIÇOS CULTURAIS E OUTROS SERVIÇOS SOCIAIS
be90cd4d-7bc3-4e01-867e-b8a54361ddea	8413200	REGULAÇÃO DAS ATIVIDADES ECONÔMICAS	t	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO DO ESTADO E DA POLÍTICA ECONÔMICA E SOCIAL	REGULAÇÃO DAS ATIVIDADES ECONÔMICAS
7b03ca55-a735-4176-9ba0-b6857574a4d8	8421300	RELAÇÕES EXTERIORES	t	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	SERVIÇOS COLETIVOS PRESTADOS PELA ADMINISTRAÇÃO PÚBLICA	RELAÇÕES EXTERIORES
06eedf80-8f2c-4cb5-8bc7-bd22816196a1	8422100	DEFESA	t	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	SERVIÇOS COLETIVOS PRESTADOS PELA ADMINISTRAÇÃO PÚBLICA	DEFESA
a45521cd-8649-4ef2-a31c-6c77a13359a1	8423000	JUSTIÇA	t	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	SERVIÇOS COLETIVOS PRESTADOS PELA ADMINISTRAÇÃO PÚBLICA	JUSTIÇA
2bf5fb6f-2b9c-4368-a4f5-cc43dff907e2	8424800	SEGURANÇA E ORDEM PÚBLICA	t	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	SERVIÇOS COLETIVOS PRESTADOS PELA ADMINISTRAÇÃO PÚBLICA	SEGURANÇA E ORDEM PÚBLICA
e8fc67a5-0dcd-4580-ae6a-85d2a3ba57f7	8425600	DEFESA CIVIL	t	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	SERVIÇOS COLETIVOS PRESTADOS PELA ADMINISTRAÇÃO PÚBLICA	DEFESA CIVIL
9092a3de-de27-4728-8c16-2b59498a0e06	8430200	SEGURIDADE SOCIAL OBRIGATÓRIA	t	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	SEGURIDADE SOCIAL OBRIGATÓRIA	SEGURIDADE SOCIAL OBRIGATÓRIA
3cbbf889-9331-480f-beaa-e0ff90c2ead6	8511200	EDUCAÇÃO INFANTIL - CRECHE	t	EDUCAÇÃO	EDUCAÇÃO	EDUCAÇÃO INFANTIL E ENSINO FUNDAMENTAL	EDUCAÇÃO INFANTIL - CRECHE
11fba177-5dca-4fc2-b2b8-0d98e29491e0	8512100	EDUCAÇÃO INFANTIL - PRÉESCOLA	t	EDUCAÇÃO	EDUCAÇÃO	EDUCAÇÃO INFANTIL E ENSINO FUNDAMENTAL	EDUCAÇÃO INFANTIL - PRÉ-ESCOLA
05b1f3d0-9ea8-4e0a-a831-22fd652462f0	8513900	ENSINO FUNDAMENTAL	t	EDUCAÇÃO	EDUCAÇÃO	EDUCAÇÃO INFANTIL E ENSINO FUNDAMENTAL	ENSINO FUNDAMENTAL
2ff236be-6ba5-4ae1-b521-2d2e60c65686	8520100	ENSINO MÉDIO	t	EDUCAÇÃO	EDUCAÇÃO	ENSINO MÉDIO	ENSINO MÉDIO
c7b6c41d-5e54-4c05-b18e-b408e0c725dc	8531700	EDUCAÇÃO SUPERIOR - GRADUAÇÃO	t	EDUCAÇÃO	EDUCAÇÃO	EDUCAÇÃO SUPERIOR	EDUCAÇÃO SUPERIOR - GRADUAÇÃO
495ff57f-65f5-4b9e-a684-21e38c72ca3e	8532500	EDUCAÇÃO SUPERIOR - GRADUAÇÃO E PÓS GRADUAÇÃO	t	EDUCAÇÃO	EDUCAÇÃO	EDUCAÇÃO SUPERIOR	EDUCAÇÃO SUPERIOR - GRADUAÇÃO E PÓS-GRADUAÇÃO
74c744d5-927c-406a-b385-29362257c612	8533300	EDUCAÇÃO SUPERIOR - PÓS GRADUAÇÃO E EXTENSÃO	t	EDUCAÇÃO	EDUCAÇÃO	EDUCAÇÃO SUPERIOR	EDUCAÇÃO SUPERIOR - PÓS-GRADUAÇÃO E EXTENSÃO
0394e1d9-b51f-4fcf-b2eb-98a956a4e7f6	8541400	EDUCAÇÃO PROFISSIONAL DE NÍVEL TÉCNICO	t	EDUCAÇÃO	EDUCAÇÃO	EDUCAÇÃO PROFISSIONAL DE NÍVEL TÉCNICO E TECNOLÓGICO	EDUCAÇÃO PROFISSIONAL DE NÍVEL TÉCNICO
a45a24e6-c86d-46ae-9689-7f60dde92e42	8542200	EDUCAÇÃO PROFISSIONAL DE NÍVEL TECNOLÓGICO	t	EDUCAÇÃO	EDUCAÇÃO	EDUCAÇÃO PROFISSIONAL DE NÍVEL TÉCNICO E TECNOLÓGICO	EDUCAÇÃO PROFISSIONAL DE NÍVEL TECNOLÓGICO
cabee3af-e66e-4674-b183-a4fa0fb89bb2	8550301	ADMINISTRAÇÃO DE CAIXAS ESCOLARES	t	EDUCAÇÃO	EDUCAÇÃO	ATIVIDADES DE APOIO À EDUCAÇÃO	ATIVIDADES DE APOIO À EDUCAÇÃO
3f22bc48-8408-4e13-b4de-d1a504a357b1	8550302	ATIVIDADES DE APOIO À EDUCAÇÃO, EXCETO CAIXAS ESCOLARES	t	EDUCAÇÃO	EDUCAÇÃO	ATIVIDADES DE APOIO À EDUCAÇÃO	ATIVIDADES DE APOIO À EDUCAÇÃO
479002ac-805a-497e-96d6-146e8a1d02f8	8591100	ENSINO DE ESPORTES	t	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ENSINO DE ESPORTES
6755b791-d00e-458e-aa6c-18f31cb3fdab	8592901	ENSINO DE DANÇA	t	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ENSINO DE ARTE E CULTURA
8a7c6257-24bb-4719-83a4-34bc25dab51b	8592902	ENSINO DE ARTES CÊNICAS, EXCETO DANÇA	t	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ENSINO DE ARTE E CULTURA
fd11977f-4322-4687-a76e-60a5deaeb188	8592903	ENSINO DE MÚSICA	t	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ENSINO DE ARTE E CULTURA
d785584c-0360-4cc2-80d8-0d9e5dfddf70	8592999	ENSINO DE ARTE E CULTURA NÃO ESPECIFICADO ANTERIORMENTE	t	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ENSINO DE ARTE E CULTURA
0962d708-9929-46ba-b3a6-7dce650562b4	8593700	ENSINO DE IDIOMAS	t	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ENSINO DE IDIOMAS
20366b03-cdbb-4b11-b703-d89436efec99	8599601	FORMAÇÃO DE CONDUTORES	t	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ATIVIDADES DE ENSINO NÃO ESPECIFICADAS ANTERIORMENTE
f1cad2a7-8a7a-4c08-9a5e-c5932f5542be	8599602	CURSOS DE PILOTAGEM	t	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ATIVIDADES DE ENSINO NÃO ESPECIFICADAS ANTERIORMENTE
bd36a4f6-2fe5-4596-8669-852ec5dcd15e	8599603	TREINAMENTO EM INFORMÁTICA	t	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ATIVIDADES DE ENSINO NÃO ESPECIFICADAS ANTERIORMENTE
84a5dcda-8e9f-4c81-b204-eb7fd8cf528e	8599604	TREINAMENTO EM DESENVOLVIMENTO PROFISSIONAL E GERENCIAL	t	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ATIVIDADES DE ENSINO NÃO ESPECIFICADAS ANTERIORMENTE
ac467fe7-f29f-4354-9bb9-a5073a23974c	8599605	CURSOS PREPARATÓRIOS PARA CONCURSOS	t	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ATIVIDADES DE ENSINO NÃO ESPECIFICADAS ANTERIORMENTE
64c0ee03-9870-4d7a-99ec-9146a313ec37	8599699	OUTRAS ATIVIDADES DE ENSINO NÃO ESPECIFICADAS ANTERIORMENTE	t	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ATIVIDADES DE ENSINO NÃO ESPECIFICADAS ANTERIORMENTE
f5c0e91b-4248-4fb1-a8d4-900f3cd334cd	8610101	ATIVIDADES DE ATENDIMENTO HOSPITALAR, EXCETO PRONTO SOCORRO E UNIDADES PARA ATENDIMENTO A URGÊNCIAS	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENDIMENTO HOSPITALAR	ATIVIDADES DE ATENDIMENTO HOSPITALAR
ff19f660-2c89-4581-bfb8-c69009558bde	8610102	ATIVIDADES DE ATENDIMENTO EM PRONTO SOCORRO E UNIDADES HOSPITALARES PARA ATENDIMENTO A URGÊNCIAS	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENDIMENTO HOSPITALAR	ATIVIDADES DE ATENDIMENTO HOSPITALAR
1c9ed198-c4bf-4dd6-94a2-aaae11de988f	8621601	UTI MÓVEL	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS E DE REMOÇÃO DE PACIENTES	SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS
df7098f2-41b4-4cc7-9ada-229b017c5f21	8621602	SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS, EXCETO POR UTI MÓVEL	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS E DE REMOÇÃO DE PACIENTES	SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS
53f7508d-5442-4690-baf0-35146095f8e4	8622400	SERVIÇOS DE REMOÇÃO DE PACIENTES, EXCETO OS SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS E DE REMOÇÃO DE PACIENTES	SERVIÇOS DE REMOÇÃO DE PACIENTES, EXCETO OS SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS
79c838d1-e81c-474d-a087-98cf425a580b	8630501	ATIVIDADE MÉDICA AMBULATORIAL COM RECURSOS PARA REALIZAÇÃO DE PROCEDIMENTOS CIRÚRGICOS	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS
fa54eb44-8f3c-4bcc-bba4-d6f38be681da	8630502	ATIVIDADE MÉDICA AMBULATORIAL COM RECURSOS PARA REALIZAÇÃO DE EXAMES COMPLEMENTARES	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS
b19113cf-7cec-4a23-9b5a-6ad23983a35e	8630503	ATIVIDADE MÉDICA AMBULATORIAL RESTRITA A CONSULTAS	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS
1c304ff5-fb89-40bb-9eb8-eb09bf700c30	8630504	ATIVIDADE ODONTOLÓGICA	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS
f62cf16d-5340-48ad-9ed0-4d6c62093d64	8630506	SERVIÇOS DE VACINAÇÃO E IMUNIZAÇÃO HUMANA	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS
db58881f-24da-4a48-8406-320a72dfa5e1	8630507	ATIVIDADES DE REPRODUÇÃO HUMANA ASSISTIDA	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS
493a0538-1fd9-4ea6-97eb-192fb86da98c	8630599	ATIVIDADES DE ATENÇÃO AMBULATORIAL NÃO ESPECIFICADAS ANTERIORMENTE	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS
d899a248-0498-4a94-8798-2562d0628998	8640201	LABORATÓRIOS DE ANATOMIA PATOLÓGICA E CITOLÓGICA	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
479f442d-5532-4e6c-89d9-eed871d968e7	8640202	LABORATÓRIOS CLÍNICOS	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
d6f8ff6b-e484-4f93-9dc2-ae379a9e99a0	8640203	SERVIÇOS DE DIÁLISE E NEFROLOGIA	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
07a51afb-d618-460c-b28b-438d049f2df0	8640204	SERVIÇOS DE TOMOGRAFIA	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
85885229-3e9d-4cae-b012-662e92b13c96	8640205	SERVIÇOS DE DIAGNÓSTICO POR IMAGEM COM USO DE RADIAÇÃO IONIZANTE, EXCETO TOMOGRAFIA	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
655c6ebb-dd25-4543-b066-9ed9262f3a67	8640206	SERVIÇOS DE RESSONÂNCIA MAGNÉTICA	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
b284befd-a008-4e88-a9af-f9e383d28a96	8640207	SERVIÇOS DE DIAGNÓSTICO POR IMAGEM SEM USO DE RADIAÇÃO IONIZANTE, EXCETO RESSONÂNCIA MAGNÉTICA	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
2bf90a18-8133-4546-936f-77f0cf062b71	8640208	SERVIÇOS DE DIAGNÓSTICO POR REGISTRO GRÁFICO - ECG, EEG E OUTROS EXAMES ANÁLOGOS	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
a52619e5-3138-43a6-b195-10e2a4bddc9f	8640209	SERVIÇOS DE DIAGNÓSTICO POR MÉTODOS ÓPTICOS - ENDOSCOPIA E OUTROS EXAMES ANÁLOGOS	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
b95ea6d4-c5ec-48eb-9c9f-466ecf488567	8640210	SERVIÇOS DE QUIMIOTERAPIA	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
de1c3c5d-a344-4dd8-8bce-ea9af3a610a4	8640211	SERVIÇOS DE RADIOTERAPIA	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
d3de9348-0e29-487f-bf06-e679f07c6a08	8640212	SERVIÇOS DE HEMOTERAPIA	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
e2cf8f50-01f5-4488-a7be-c96570ddd6d0	8640213	SERVIÇOS DE LITOTRIPCIA	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
09e92517-a07e-4a51-9d14-5d1779684138	8640214	SERVIÇOS DE BANCOS DE CÉLULAS E TECIDOS HUMANOS	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
2bab1896-43ed-43f1-818e-00e85baa9778	8640299	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA NÃO ESPECIFICADAS ANTERIORMENTE	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
7ed3c55a-3048-4bc8-99f2-2391055b2222	8650001	ATIVIDADES DE ENFERMAGEM	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS
77ccf8f2-36ad-42e7-a6ba-5be8ecd23734	8650002	ATIVIDADES DE PROFISSIONAIS DA NUTRIÇÃO	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS
f32d3b3e-d131-43ee-9c6f-0a7e1f4dfa37	8650003	ATIVIDADES DE PSICOLOGIA E PSICANÁLISE	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS
b1b3f4ee-e5f6-4386-b486-8563cab75232	8650004	ATIVIDADES DE FISIOTERAPIA	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS
f4437e7c-c006-4acd-9e45-4cb6c7f616c9	8650005	ATIVIDADES DE TERAPIA OCUPACIONAL	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS
95d122ed-d5ba-4065-90f8-ef590d45a4f1	8650006	ATIVIDADES DE FONOAUDIOLOGIA	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS
f5cf65b3-0339-4f71-867b-df351c22cca9	8650007	ATIVIDADES DE TERAPIA DE NUTRIÇÃO ENTERAL E PARENTERAL	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS
f2f33561-0f7a-465a-9009-85e28e9fa6f2	8650099	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE NÃO ESPECIFICADAS ANTERIORMENTE	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS
7a1ee522-2211-4738-8922-0d45d79aa2cd	8660700	ATIVIDADES DE APOIO À GESTÃO DE SAÚDE	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE APOIO À GESTÃO DE SAÚDE	ATIVIDADES DE APOIO À GESTÃO DE SAÚDE
c6d727b1-39db-4e94-9c90-18cf6c5da042	8690901	ATIVIDADES DE PRÁTICAS INTEGRATIVAS E COMPLEMENTARES EM SAÚDE HUMANA	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE
627efccf-a91c-4cf4-87a7-87996f4e9d7f	8690902	ATIVIDADES DE BANCO DE LEITE HUMANO	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE
47b3d0cc-9e28-499a-a083-ce87b0747d4d	8690903	ATIVIDADES DE ACUPUNTURA	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE
2727ceae-175b-4433-b86b-e953b2a242e2	8690904	ATIVIDADES DE PODOLOGIA	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE
1357b87e-4e30-4d88-b4e4-2eddf5f9f521	8690999	OUTRAS ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE
3a0cfc07-554f-45c3-84f2-ff14a076f23d	8711501	CLÍNICAS E RESIDÊNCIAS GERIÁTRICAS	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES, E DE INFRA-ESTRUTURA E APOIO A PACIENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
9702babe-a295-4b19-938c-133987b9619b	8711502	INSTITUIÇÕES DE LONGA PERMANÊNCIA PARA IDOSOS	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES, E DE INFRA-ESTRUTURA E APOIO A PACIENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
370447b0-b958-4803-9623-d304313a18fb	8711503	ATIVIDADES DE ASSISTÊNCIA A DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES, E DE INFRA-ESTRUTURA E APOIO A PACIENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
b5bd1835-4d95-4b75-a09f-62c69cac1a8f	8711504	CENTROS DE APOIO A PACIENTES COM CÂNCER E COM AIDS	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES, E DE INFRA-ESTRUTURA E APOIO A PACIENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
798b0c80-0657-4cc1-a9a5-1348c5fdf102	8711505	CONDOMÍNIOS RESIDENCIAIS PARA IDOSOS	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES, E DE INFRA-ESTRUTURA E APOIO A PACIENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
f7ebeb8f-6f76-4ddb-ae41-7e17c0e882dd	8712300	ATIVIDADES DE FORNECIMENTO DE INFRAESTRUTURA DE APOIO E ASSISTÊNCIA A PACIENTE NO DOMICÍLIO	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES, E DE INFRA-ESTRUTURA E APOIO A PACIENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE FORNECIMENTO DE INFRA-ESTRUTURA DE APOIO E ASSISTÊNCIA A PACIENTE NO DOMICÍLIO
bc4c8064-d025-4203-b960-fe71754a8e2d	8720401	ATIVIDADES DE CENTROS DE ASSISTÊNCIA PSICOSSOCIAL	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA PSICOSSOCIAL E À SAÚDE A PORTADORES DE DISTÚRBIOS PSÍQUICOS, DEFICIÊNCIA MENTAL E DEPENDÊNCIA QUÍMICA	ATIVIDADES DE ASSISTÊNCIA PSICOSSOCIAL E À SAÚDE A PORTADORES DE DISTÚRBIOS PSÍQUICOS, DEFICIÊNCIA MENTAL E DEPENDÊNCIA QUÍMICA
ab4beec6-3ea3-480b-a846-717e0167ddf5	8720499	ATIVIDADES DE ASSISTÊNCIA PSICOSSOCIAL E À SAÚDE A PORTADORES DE DISTÚRBIOS PSÍQUICOS, DEFICIÊNCIA MENTAL E DEPENDÊNCIA QUÍMICA E GRUPOS SIMILARES NÃO ESPECIFICADAS ANTERIORMENTE	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA PSICOSSOCIAL E À SAÚDE A PORTADORES DE DISTÚRBIOS PSÍQUICOS, DEFICIÊNCIA MENTAL E DEPENDÊNCIA QUÍMICA	ATIVIDADES DE ASSISTÊNCIA PSICOSSOCIAL E À SAÚDE A PORTADORES DE DISTÚRBIOS PSÍQUICOS, DEFICIÊNCIA MENTAL E DEPENDÊNCIA QUÍMICA
916032fe-69f4-4b5f-833f-34be436b62ba	8730101	ORFANATOS	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA SOCIAL PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA SOCIAL PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
f772fbf0-6ce0-4db7-80d7-80bd6e3b6ddf	8730102	ALBERGUES ASSISTENCIAIS	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA SOCIAL PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA SOCIAL PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
0db9ea7f-0213-4d21-801e-4d71b4c87b64	8730199	ATIVIDADES DE ASSISTÊNCIA SOCIAL PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES NÃO ESPECIFICADAS ANTERIORMENTE	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA SOCIAL PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA SOCIAL PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
560ee49f-d978-4525-be0f-a972f8023313	8800600	SERVIÇOS DE ASSISTÊNCIA SOCIAL SEM ALOJAMENTO	t	SAÚDE HUMANA E SERVIÇOS SOCIAIS	SERVIÇOS DE ASSISTÊNCIA SOCIAL SEM ALOJAMENTO	SERVIÇOS DE ASSISTÊNCIA SOCIAL SEM ALOJAMENTO	SERVIÇOS DE ASSISTÊNCIA SOCIAL SEM ALOJAMENTO
afc1e44c-0c2c-445c-a54f-1c38f27fe0de	9001901	PRODUÇÃO TEATRAL	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ARTES CÊNICAS, ESPETÁCULOS E ATIVIDADES COMPLEMENTARES
711f5ace-f8bb-421b-90b4-13b814f23ca2	9001902	PRODUÇÃO MUSICAL	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ARTES CÊNICAS, ESPETÁCULOS E ATIVIDADES COMPLEMENTARES
3711ed50-e40c-46b4-a573-83b8142d9315	9001903	PRODUÇÃO DE ESPETÁCULOS DE DANÇA	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ARTES CÊNICAS, ESPETÁCULOS E ATIVIDADES COMPLEMENTARES
46014ece-6f38-4e9a-87bd-f63b67dacaa1	9001904	PRODUÇÃO DE ESPETÁCULOS CIRCENSES, DE MARIONETES E SIMILARES	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ARTES CÊNICAS, ESPETÁCULOS E ATIVIDADES COMPLEMENTARES
d0a2b73a-7f15-4811-a73b-5ccaa76173e9	9001905	PRODUÇÃO DE ESPETÁCULOS DE RODEIOS, VAQUEJADAS E SIMILARES	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ARTES CÊNICAS, ESPETÁCULOS E ATIVIDADES COMPLEMENTARES
54ac2225-e907-432f-9d50-74a4e5f6dcd4	9001906	ATIVIDADES DE SONORIZAÇÃO E DE ILUMINAÇÃO	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ARTES CÊNICAS, ESPETÁCULOS E ATIVIDADES COMPLEMENTARES
e58430ed-b20f-4ad7-bae0-46dc883e164f	9001999	ARTES CÊNICAS, ESPETÁCULOS E ATIVIDADES COMPLEMENTARES NÃO ESPECIFICADAS ANTERIORMENTE	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ARTES CÊNICAS, ESPETÁCULOS E ATIVIDADES COMPLEMENTARES
f238b442-9f27-4eff-bd4b-5449db2490ce	9002701	ATIVIDADES DE ARTISTAS PLÁSTICOS, JORNALISTAS INDEPENDENTES E ESCRITORES	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	CRIAÇÃO ARTÍSTICA
cf8c127c-0a3a-4469-8c43-47e15345e7bb	9002702	RESTAURAÇÃO DE OBRAS DE ARTE	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	CRIAÇÃO ARTÍSTICA
dffff327-a759-488f-944e-a273d310afea	9003500	GESTÃO DE ESPAÇOS PARA ARTES CÊNICAS, ESPETÁCULOS E OUTRAS ATIVIDADES ARTÍSTICAS	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	GESTÃO DE ESPAÇOS PARA ARTES CÊNICAS, ESPETÁCULOS E OUTRAS ATIVIDADES ARTÍSTICAS
9d4f9bb9-cfce-40d6-b774-16032a656725	9101500	ATIVIDADES DE BIBLIOTECAS E ARQUIVOS	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES LIGADAS AO PATRIMÔNIO CULTURAL E AMBIENTAL	ATIVIDADES LIGADAS AO PATRIMÔNIO CULTURAL E AMBIENTAL	ATIVIDADES DE BIBLIOTECAS E ARQUIVOS
db99f073-0a73-4b61-b33e-eb508ea60f6b	9102301	ATIVIDADES DE MUSEUS E DE EXPLORAÇÃO DE LUGARES E PRÉDIOS HISTÓRICOS E ATRAÇÕES SIMILARES	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES LIGADAS AO PATRIMÔNIO CULTURAL E AMBIENTAL	ATIVIDADES LIGADAS AO PATRIMÔNIO CULTURAL E AMBIENTAL	ATIVIDADES DE MUSEUS E DE EXPLORAÇÃO, RESTAURAÇÃO ARTÍSTICA E CONSERVAÇÃO DE LUGARES E PRÉDIOS HISTÓRICOS E ATRAÇÕES SIMILARES
555b9f49-a3d5-414c-bd32-73c70956e125	9102302	RESTAURAÇÃO E CONSERVAÇÃO DE LUGARES E PRÉDIOS HISTÓRICOS	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES LIGADAS AO PATRIMÔNIO CULTURAL E AMBIENTAL	ATIVIDADES LIGADAS AO PATRIMÔNIO CULTURAL E AMBIENTAL	ATIVIDADES DE MUSEUS E DE EXPLORAÇÃO, RESTAURAÇÃO ARTÍSTICA E CONSERVAÇÃO DE LUGARES E PRÉDIOS HISTÓRICOS E ATRAÇÕES SIMILARES
d9daa8ed-8bd8-4dd7-b37a-70b8315e9777	9103100	ATIVIDADES DE JARDINS BOTÂNICOS, ZOOLÓGICOS, PARQUES NACIONAIS, RESERVAS ECOLÓGICAS E ÁREAS DE PROTEÇÃO AMBIENTAL	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES LIGADAS AO PATRIMÔNIO CULTURAL E AMBIENTAL	ATIVIDADES LIGADAS AO PATRIMÔNIO CULTURAL E AMBIENTAL	ATIVIDADES DE JARDINS BOTÂNICOS, ZOOLÓGICOS, PARQUES NACIONAIS, RESERVAS ECOLÓGICAS E ÁREAS DE PROTEÇÃO AMBIENTAL
8d971d66-29b0-4f25-a20b-5463fbd8ced5	9200301	CASAS DE BINGO	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS
1992682e-7626-4020-91cc-6cca018c03a9	9200302	EXPLORAÇÃO DE APOSTAS EM CORRIDAS DE CAVALOS	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS
2c55f8fb-a4b2-41e6-a8c2-8f2fd83cf179	9200399	EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS NÃO ESPECIFICADOS ANTERIORMENTE	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS
a1f9a9f7-4740-4759-afe1-e55a3d1d32cf	9311500	GESTÃO DE INSTALAÇÕES DE ESPORTES	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES ESPORTIVAS	GESTÃO DE INSTALAÇÕES DE ESPORTES
9b835a48-a026-4870-bb80-c3c4f1004325	9312300	CLUBES SOCIAIS, ESPORTIVOS E SIMILARES	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES ESPORTIVAS	CLUBES SOCIAIS, ESPORTIVOS E SIMILARES
962bc448-2b89-4815-b896-c156aa8d9c7c	9313100	ATIVIDADES DE CONDICIONAMENTO FÍSICO	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES ESPORTIVAS	ATIVIDADES DE CONDICIONAMENTO FÍSICO
a2fd19a1-aa00-4948-ba20-a2d24147e085	9319101	PRODUÇÃO E PROMOÇÃO DE EVENTOS ESPORTIVOS	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES ESPORTIVAS	ATIVIDADES ESPORTIVAS NÃO ESPECIFICADAS ANTERIORMENTE
a4b34ebc-d17e-4f2f-9adf-7fb50557f11e	9319199	OUTRAS ATIVIDADES ESPORTIVAS NÃO ESPECIFICADAS ANTERIORMENTE	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES ESPORTIVAS	ATIVIDADES ESPORTIVAS NÃO ESPECIFICADAS ANTERIORMENTE
90cf0226-9f69-4f4f-9066-2eb814b0cef6	9321200	PARQUES DE DIVERSÃO E PARQUES TEMÁTICOS	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER	PARQUES DE DIVERSÃO E PARQUES TEMÁTICOS
ae28bf8c-8419-40c9-81bc-03882678696b	9329801	DISCOTECAS, DANCETERIAS, SALÕES DE DANÇA E SIMILARES	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER NÃO ESPECIFICADAS ANTERIORMENTE
45bd89b7-bdc6-48a0-bdc4-6780cc73a766	9329802	EXPLORAÇÃO DE BOLICHES	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER NÃO ESPECIFICADAS ANTERIORMENTE
bc167750-4e38-44b0-8e7d-0b654ad6ca4f	9329803	EXPLORAÇÃO DE JOGOS DE SINUCA, BILHAR E SIMILARES	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER NÃO ESPECIFICADAS ANTERIORMENTE
daf8cd34-7848-4ea7-8789-bed970f928ff	9329804	EXPLORAÇÃO DE JOGOS ELETRÔNICOS RECREATIVOS	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER NÃO ESPECIFICADAS ANTERIORMENTE
76632b8d-9873-4687-8b06-f809ac25cdb4	9329899	OUTRAS ATIVIDADES DE RECREAÇÃO E LAZER NÃO ESPECIFICADAS ANTERIORMENTE	t	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER NÃO ESPECIFICADAS ANTERIORMENTE
50aa1cbd-f2ac-4a45-aa22-b60277e3cb99	9411100	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS PATRONAIS E EMPRESARIAIS	t	OUTRAS ATIVIDADES DE SERVIÇOS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS PATRONAIS, EMPRESARIAIS E PROFISSIONAIS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS PATRONAIS E EMPRESARIAIS
7017456d-8ace-4c57-be92-f3f7fc12a46d	9412001	ATIVIDADES DE FISCALIZAÇÃO PROFISSIONAL	t	OUTRAS ATIVIDADES DE SERVIÇOS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS PATRONAIS, EMPRESARIAIS E PROFISSIONAIS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS PROFISSIONAIS
8babeb9e-6e7f-4491-901c-d75545d7011c	9412099	OUTRAS ATIVIDADES ASSOCIATIVAS PROFISSIONAIS	t	OUTRAS ATIVIDADES DE SERVIÇOS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS PATRONAIS, EMPRESARIAIS E PROFISSIONAIS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS PROFISSIONAIS
2c1cdddf-ada1-4256-b0ce-e3704a151655	9420100	ATIVIDADES DE ORGANIZAÇÕES SINDICAIS	t	OUTRAS ATIVIDADES DE SERVIÇOS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS	ATIVIDADES DE ORGANIZAÇÕES SINDICAIS	ATIVIDADES DE ORGANIZAÇÕES SINDICAIS
8e428a30-bbb2-4940-906f-12a0edc9eefa	9430800	ATIVIDADES DE ASSOCIAÇÕES DE DEFESA DE DIREITOS SOCIAIS	t	OUTRAS ATIVIDADES DE SERVIÇOS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS	ATIVIDADES DE ASSOCIAÇÕES DE DEFESA DE DIREITOS SOCIAIS	ATIVIDADES DE ASSOCIAÇÕES DE DEFESA DE DIREITOS SOCIAIS
37da079f-2ab2-4579-b032-16c0f9c9af2e	9491000	ATIVIDADES DE ORGANIZAÇÕES RELIGIOSAS OU FILOSÓFICAS	t	OUTRAS ATIVIDADES DE SERVIÇOS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES DE ORGANIZAÇÕES RELIGIOSAS
265b1da6-36aa-45e8-8d16-5d5703d06317	9492800	ATIVIDADES DE ORGANIZAÇÕES POLÍTICAS	t	OUTRAS ATIVIDADES DE SERVIÇOS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES DE ORGANIZAÇÕES POLÍTICAS
5dfada45-21b9-4678-ade0-faea6d5fd774	9493600	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS LIGADAS À CULTURA E À ARTE	t	OUTRAS ATIVIDADES DE SERVIÇOS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS LIGADAS À CULTURA E À ARTE
dbfb8895-99d5-485b-8e69-48557bef5274	9499500	ATIVIDADES ASSOCIATIVAS NÃO ESPECIFICADAS ANTERIORMENTE	t	OUTRAS ATIVIDADES DE SERVIÇOS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES ASSOCIATIVAS NÃO ESPECIFICADAS ANTERIORMENTE
5931fc86-3249-4a2f-b049-27d123ddc629	9511800	REPARAÇÃO E MANUTENÇÃO DE COMPUTADORES E DE EQUIPAMENTOS PERIFÉRICOS	t	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO	REPARAÇÃO E MANUTENÇÃO DE COMPUTADORES E DE EQUIPAMENTOS PERIFÉRICOS
d3a88ef5-2333-42e4-bed0-9c033a473fe8	9512600	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE COMUNICAÇÃO	t	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE COMUNICAÇÃO
686e4569-b249-4a4a-ae15-5e6e78228ca3	9521500	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS ELETROELETRÔNICOS DE USO PESSOAL E DOMÉSTICO	t	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS ELETROELETRÔNICOS DE USO PESSOAL E DOMÉSTICO
c70ad94e-8700-4186-8d79-05127c37924a	9529101	REPARAÇÃO DE CALÇADOS, DE BOLSAS E ARTIGOS DE VIAGEM	t	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
9d469224-da46-4774-894c-dbc7bc1cd603	9529102	CHAVEIROS	t	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
b26982c5-ca6d-4a97-a08c-ed4430f55951	9529103	REPARAÇÃO DE RELÓGIOS	t	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
fc1b6025-d396-49d1-bd6e-8230f3b31eed	9529104	REPARAÇÃO DE BICICLETAS, TRICICLOS E OUTROS VEÍCULOS NÃO MOTORIZADOS	t	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
a879bbb2-01d4-4cf4-ba49-d9f0e2117ebf	9529105	REPARAÇÃO DE ARTIGOS DO MOBILIÁRIO	t	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
b867e333-e642-4435-a97e-638c07ee148f	9529106	REPARAÇÃO DE JÓIAS	t	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
8303badd-e27f-49fe-98d8-a18cec78e40b	9529199	REPARAÇÃO E MANUTENÇÃO DE OUTROS OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE	t	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
8188a063-9990-493a-a447-651f61496af3	9601701	LAVANDERIAS	t	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	LAVANDERIAS, TINTURARIAS E TOALHEIROS
609e26ae-0f2b-495d-af52-665ee87a2fde	9601702	TINTURARIAS	t	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	LAVANDERIAS, TINTURARIAS E TOALHEIROS
71788ab9-5794-4418-9ded-19cef9909104	9601703	TOALHEIROS	t	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	LAVANDERIAS, TINTURARIAS E TOALHEIROS
7c2b8694-bec8-42ec-ac69-88c1024abc57	9602501	CABELEIREIROS, MANICURE E PEDICURE	t	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	CABELEIREIROS E OUTRAS ATIVIDADES DE TRATAMENTO DE BELEZA
acbcfcce-eeba-4715-bc6e-59fcecacc305	9602502	ATIVIDADES DE ESTÉTICA E OUTROS SERVIÇOS DE CUIDADOS COM A BELEZA	t	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	CABELEIREIROS E OUTRAS ATIVIDADES DE TRATAMENTO DE BELEZA
dc5b931b-5dce-48b5-9e73-2ac0407b602f	9603301	GESTÃO E MANUTENÇÃO DE CEMITÉRIOS	t	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES FUNERÁRIAS E SERVIÇOS RELACIONADOS
daf2b7b4-937b-4498-92ef-00a9bd7faba5	9603302	SERVIÇOS DE CREMAÇÃO	t	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES FUNERÁRIAS E SERVIÇOS RELACIONADOS
1c94fec9-147e-4eb0-b834-fae0c089415a	9603303	SERVIÇOS DE SEPULTAMENTO	t	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES FUNERÁRIAS E SERVIÇOS RELACIONADOS
20f2efb9-27b8-4c69-8052-c2a778774936	9603304	SERVIÇOS DE FUNERÁRIAS	t	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES FUNERÁRIAS E SERVIÇOS RELACIONADOS
a9c142a1-65bc-4a3a-aa41-6ec1e1395d25	9603305	SERVIÇOS DE SOMATOCONSERVAÇÃO	t	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES FUNERÁRIAS E SERVIÇOS RELACIONADOS
d8820872-b4b2-4706-97e7-359921d38857	9603399	ATIVIDADES FUNERÁRIAS E SERVIÇOS RELACIONADOS NÃO ESPECIFICADOS ANTERIORMENTE	t	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES FUNERÁRIAS E SERVIÇOS RELACIONADOS
9c0e74e6-b809-4f3b-88db-6c0f8c20b63f	9609202	AGÊNCIAS MATRIMONIAIS	t	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES DE SERVIÇOS PESSOAIS NÃO ESPECIFICADAS ANTERIORMENTE
56ef903c-49b3-4806-92d9-fd00b581b3ae	9609204	EXPLORAÇÃO DE MÁQUINAS DE SERVIÇOS PESSOAIS ACIONADAS POR MOEDA	t	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES DE SERVIÇOS PESSOAIS NÃO ESPECIFICADAS ANTERIORMENTE
013a7d7c-65ec-4feb-bef8-731bb431bcde	9609205	ATIVIDADES DE SAUNA E BANHOS	t	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES DE SERVIÇOS PESSOAIS NÃO ESPECIFICADAS ANTERIORMENTE
f6790080-4657-48b8-ad22-ed4af6ea596d	9609206	SERVIÇOS DE TATUAGEM E COLOCAÇÃO DE PIERCING	t	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES DE SERVIÇOS PESSOAIS NÃO ESPECIFICADAS ANTERIORMENTE
545a1944-6175-434e-9d6b-2ef93d54b9eb	9609207	ALOJAMENTO DE ANIMAIS DOMÉSTICOS	t	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES DE SERVIÇOS PESSOAIS NÃO ESPECIFICADAS ANTERIORMENTE
0dc94906-0718-4959-8fcc-c75f67f5184a	9609208	HIGIENE E EMBELEZAMENTO DE ANIMAIS DOMÉSTICOS	t	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES DE SERVIÇOS PESSOAIS NÃO ESPECIFICADAS ANTERIORMENTE
57b08c07-8c6a-43f7-95b0-568c328a4893	9609299	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS NÃO ESPECIFICADAS ANTERIORMENTE	t	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES DE SERVIÇOS PESSOAIS NÃO ESPECIFICADAS ANTERIORMENTE
dcdce0ee-51f2-4399-87d9-043f62f31b35	9700500	SERVIÇOS DOMÉSTICOS	t	SERVIÇOS DOMÉSTICOS	SERVIÇOS DOMÉSTICOS	SERVIÇOS DOMÉSTICOS	SERVIÇOS DOMÉSTICOS
2c866dc0-1ab9-465a-b7ec-b11cce3f61a7	9900800	ORGANISMOS INTERNACIONAIS E OUTRAS INSTITUIÇÕES EXTRATERRITORIAIS	t	ORGANISMOS INTERNACIONAIS E OUTRAS INSTITUIÇÕES EXTRATERRITORIAIS	ORGANISMOS INTERNACIONAIS E OUTRAS INSTITUIÇÕES EXTRATERRITORIAIS	ORGANISMOS INTERNACIONAIS E OUTRAS INSTITUIÇÕES EXTRATERRITORIAIS	ORGANISMOS INTERNACIONAIS E OUTRAS INSTITUIÇÕES EXTRATERRITORIAIS
\.


--
-- TOC entry 4873 (class 0 OID 28941)
-- Dependencies: 249
-- Data for Name: cnae_ibge_hierarquia; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.cnae_ibge_hierarquia (subclasse, secao, divisao, grupo, classe) FROM stdin;
0111301	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE CEREAIS
0111302	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE CEREAIS
0111303	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE CEREAIS
0111399	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE CEREAIS
0112101	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE ALGODÃO HERBÁCEO E DE OUTRAS FIBRAS DE LAVOURA TEMPORÁRIA
0112102	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE ALGODÃO HERBÁCEO E DE OUTRAS FIBRAS DE LAVOURA TEMPORÁRIA
0112199	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE ALGODÃO HERBÁCEO E DE OUTRAS FIBRAS DE LAVOURA TEMPORÁRIA
0113000	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE CANA-DE-AÇÚCAR
0114800	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE FUMO
0115600	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE SOJA
0116401	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE OLEAGINOSAS DE LAVOURA TEMPORÁRIA, EXCETO SOJA
0116402	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE OLEAGINOSAS DE LAVOURA TEMPORÁRIA, EXCETO SOJA
0116403	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE OLEAGINOSAS DE LAVOURA TEMPORÁRIA, EXCETO SOJA
0116499	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE OLEAGINOSAS DE LAVOURA TEMPORÁRIA, EXCETO SOJA
0119901	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
0119902	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
0119903	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
0119904	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
0119905	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
0119906	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
0119907	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
0119908	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
0119909	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
0119999	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
0121101	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	HORTICULTURA E FLORICULTURA	HORTICULTURA
0121102	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	HORTICULTURA E FLORICULTURA	HORTICULTURA
0122900	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	HORTICULTURA E FLORICULTURA	CULTIVO DE FLORES E PLANTAS ORNAMENTAIS
0131800	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE LARANJA
0132600	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE UVA
0133401	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
0133402	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
0133403	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
0133404	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
0312404	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	PESCA	PESCA EM ÁGUA DOCE
0133405	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
0133406	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
0133407	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
0133408	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
0133409	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
0133410	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
0133411	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
0133499	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
0134200	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE CAFÉ
0135100	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE CACAU
0139301	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE PLANTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE
0139302	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE PLANTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE
0139303	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE PLANTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE
0139304	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE PLANTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE
0139305	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE PLANTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE
0139306	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE PLANTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE
0139399	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE LAVOURAS PERMANENTES	CULTIVO DE PLANTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE
0141501	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE SEMENTES E MUDAS CERTIFICADAS	PRODUÇÃO DE SEMENTES CERTIFICADAS
0141502	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE SEMENTES E MUDAS CERTIFICADAS	PRODUÇÃO DE SEMENTES CERTIFICADAS
0142300	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PRODUÇÃO DE SEMENTES E MUDAS CERTIFICADAS	PRODUÇÃO DE MUDAS E OUTRAS FORMAS DE PROPAGAÇÃO VEGETAL, CERTIFICADAS
0151201	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE BOVINOS
0151202	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE BOVINOS
0151203	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE BOVINOS
0152101	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE OUTROS ANIMAIS DE GRANDE PORTE
0152102	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE OUTROS ANIMAIS DE GRANDE PORTE
0152103	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE OUTROS ANIMAIS DE GRANDE PORTE
0153901	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE CAPRINOS E OVINOS
0153902	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE CAPRINOS E OVINOS
0154700	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE SUÍNOS
0155501	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE AVES
0155502	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE AVES
0155503	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE AVES
0155504	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE AVES
0155505	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE AVES
0159801	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE ANIMAIS NÃO ESPECIFICADOS ANTERIORMENTE
0159802	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE ANIMAIS NÃO ESPECIFICADOS ANTERIORMENTE
0159803	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE ANIMAIS NÃO ESPECIFICADOS ANTERIORMENTE
0159804	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE ANIMAIS NÃO ESPECIFICADOS ANTERIORMENTE
0159899	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	PECUÁRIA	CRIAÇÃO DE ANIMAIS NÃO ESPECIFICADOS ANTERIORMENTE
0161001	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA	ATIVIDADES DE APOIO À AGRICULTURA
0161002	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA	ATIVIDADES DE APOIO À AGRICULTURA
0161003	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA	ATIVIDADES DE APOIO À AGRICULTURA
0161099	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA	ATIVIDADES DE APOIO À AGRICULTURA
0162801	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA	ATIVIDADES DE APOIO À PECUÁRIA
0162802	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA	ATIVIDADES DE APOIO À PECUÁRIA
0162803	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA	ATIVIDADES DE APOIO À PECUÁRIA
0162899	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA	ATIVIDADES DE APOIO À PECUÁRIA
0163600	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA	ATIVIDADES DE PÓS-COLHEITA
0170900	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS	CAÇA E SERVIÇOS RELACIONADOS	CAÇA E SERVIÇOS RELACIONADOS
0210101	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
0210102	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
0210103	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
0210104	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
0210105	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
0210106	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
0210107	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
0210108	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
0210109	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
0210199	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
0220901	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS
0220902	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS
0220903	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS
0220904	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS
0220905	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS
0220906	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS
0220999	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS
0230600	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PRODUÇÃO FLORESTAL	ATIVIDADES DE APOIO À PRODUÇÃO FLORESTAL	ATIVIDADES DE APOIO À PRODUÇÃO FLORESTAL
0311601	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	PESCA	PESCA EM ÁGUA SALGADA
0311602	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	PESCA	PESCA EM ÁGUA SALGADA
0311603	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	PESCA	PESCA EM ÁGUA SALGADA
0311604	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	PESCA	PESCA EM ÁGUA SALGADA
0312401	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	PESCA	PESCA EM ÁGUA DOCE
0312402	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	PESCA	PESCA EM ÁGUA DOCE
0312403	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	PESCA	PESCA EM ÁGUA DOCE
0321301	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA SALGADA E SALOBRA
0321302	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA SALGADA E SALOBRA
0321303	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA SALGADA E SALOBRA
0321304	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA SALGADA E SALOBRA
0321305	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA SALGADA E SALOBRA
0321399	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA SALGADA E SALOBRA
0322101	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA DOCE
0322102	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA DOCE
0322103	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA DOCE
0322104	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA DOCE
0322105	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA DOCE
0322106	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA DOCE
0322107	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA DOCE
0322199	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA	PESCA E AQUICULTURA	AQUICULTURA	AQUICULTURA EM ÁGUA DOCE
0500301	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE CARVÃO MINERAL	EXTRAÇÃO DE CARVÃO MINERAL	EXTRAÇÃO DE CARVÃO MINERAL
0500302	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE CARVÃO MINERAL	EXTRAÇÃO DE CARVÃO MINERAL	EXTRAÇÃO DE CARVÃO MINERAL
0600001	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL
0600002	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL
0600003	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL
0710301	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINÉRIO DE FERRO	EXTRAÇÃO DE MINÉRIO DE FERRO
0710302	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINÉRIO DE FERRO	EXTRAÇÃO DE MINÉRIO DE FERRO
0721901	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINÉRIO DE ALUMÍNIO
0721902	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINÉRIO DE ALUMÍNIO
0722701	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINÉRIO DE ESTANHO
0722702	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINÉRIO DE ESTANHO
0723501	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINÉRIO DE MANGANÊS
0723502	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINÉRIO DE MANGANÊS
0724301	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINÉRIO DE METAIS PRECIOSOS
0724302	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINÉRIO DE METAIS PRECIOSOS
0725100	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINERAIS RADIOATIVOS
0729401	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS NÃO ESPECIFICADOS ANTERIORMENTE
0729402	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS NÃO ESPECIFICADOS ANTERIORMENTE
0729403	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS NÃO ESPECIFICADOS ANTERIORMENTE
0729404	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS NÃO ESPECIFICADOS ANTERIORMENTE
0729405	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS METÁLICOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS NÃO ESPECIFICADOS ANTERIORMENTE
0810001	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
0810002	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
0810003	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
0810004	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
0810005	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
0810006	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
0810007	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
0810008	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
0810009	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
0810010	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
0810099	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE PEDRA, AREIA E ARGILA	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
0891600	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE MINERAIS PARA FABRICAÇÃO DE ADUBOS, FERTILIZANTES E OUTROS PRODUTOS QUÍMICOS
0892401	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS	EXTRAÇÃO E REFINO DE SAL MARINHO E SAL-GEMA
0892402	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS	EXTRAÇÃO E REFINO DE SAL MARINHO E SAL-GEMA
0892403	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS	EXTRAÇÃO E REFINO DE SAL MARINHO E SAL-GEMA
0893200	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE GEMAS (PEDRAS PRECIOSAS E SEMIPRECIOSAS)
0899101	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE
0899102	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE
0899103	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE
0899199	INDÚSTRIAS EXTRATIVAS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE
0910600	INDÚSTRIAS EXTRATIVAS	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS	ATIVIDADES DE APOIO À EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL	ATIVIDADES DE APOIO À EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL
0990401	INDÚSTRIAS EXTRATIVAS	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS, EXCETO PETRÓLEO E GÁS NATURAL	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS, EXCETO PETRÓLEO E GÁS NATURAL
0990402	INDÚSTRIAS EXTRATIVAS	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS, EXCETO PETRÓLEO E GÁS NATURAL	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS, EXCETO PETRÓLEO E GÁS NATURAL
0990403	INDÚSTRIAS EXTRATIVAS	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS, EXCETO PETRÓLEO E GÁS NATURAL	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS, EXCETO PETRÓLEO E GÁS NATURAL
1011201	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	ABATE DE RESES, EXCETO SUÍNOS
1011202	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	ABATE DE RESES, EXCETO SUÍNOS
1011203	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	ABATE DE RESES, EXCETO SUÍNOS
1011204	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	ABATE DE RESES, EXCETO SUÍNOS
1011205	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	ABATE DE RESES, EXCETO SUÍNOS
1012101	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	ABATE DE SUÍNOS, AVES E OUTROS PEQUENOS ANIMAIS
1012102	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	ABATE DE SUÍNOS, AVES E OUTROS PEQUENOS ANIMAIS
1012103	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	ABATE DE SUÍNOS, AVES E OUTROS PEQUENOS ANIMAIS
1012104	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	ABATE DE SUÍNOS, AVES E OUTROS PEQUENOS ANIMAIS
1013901	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	FABRICAÇÃO DE PRODUTOS DE CARNE
1013902	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE	FABRICAÇÃO DE PRODUTOS DE CARNE
1020101	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	PRESERVAÇÃO DO PESCADO E FABRICAÇÃO DE PRODUTOS DO PESCADO	PRESERVAÇÃO DO PESCADO E FABRICAÇÃO DE PRODUTOS DO PESCADO
1020102	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	PRESERVAÇÃO DO PESCADO E FABRICAÇÃO DE PRODUTOS DO PESCADO	PRESERVAÇÃO DO PESCADO E FABRICAÇÃO DE PRODUTOS DO PESCADO
1031700	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE CONSERVAS DE FRUTAS, LEGUMES E OUTROS VEGETAIS	FABRICAÇÃO DE CONSERVAS DE FRUTAS
1032501	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE CONSERVAS DE FRUTAS, LEGUMES E OUTROS VEGETAIS	FABRICAÇÃO DE CONSERVAS DE LEGUMES E OUTROS VEGETAIS
1032599	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE CONSERVAS DE FRUTAS, LEGUMES E OUTROS VEGETAIS	FABRICAÇÃO DE CONSERVAS DE LEGUMES E OUTROS VEGETAIS
1033301	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE CONSERVAS DE FRUTAS, LEGUMES E OUTROS VEGETAIS	FABRICAÇÃO DE SUCOS DE FRUTAS, HORTALIÇAS E LEGUMES
1033302	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE CONSERVAS DE FRUTAS, LEGUMES E OUTROS VEGETAIS	FABRICAÇÃO DE SUCOS DE FRUTAS, HORTALIÇAS E LEGUMES
1041400	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE ÓLEOS E GORDURAS VEGETAIS E ANIMAIS	FABRICAÇÃO DE ÓLEOS VEGETAIS EM BRUTO, EXCETO ÓLEO DE MILHO
1042200	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE ÓLEOS E GORDURAS VEGETAIS E ANIMAIS	FABRICAÇÃO DE ÓLEOS VEGETAIS REFINADOS, EXCETO ÓLEO DE MILHO
1043100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE ÓLEOS E GORDURAS VEGETAIS E ANIMAIS	FABRICAÇÃO DE MARGARINA E OUTRAS GORDURAS VEGETAIS E DE ÓLEOS NÃO-COMESTÍVEIS DE ANIMAIS
1051100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	LATICÍNIOS	PREPARAÇÃO DO LEITE
1052000	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	LATICÍNIOS	FABRICAÇÃO DE LATICÍNIOS
1053800	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	LATICÍNIOS	FABRICAÇÃO DE SORVETES E OUTROS GELADOS COMESTÍVEIS
5120000	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AÉREO	TRANSPORTE AÉREO DE CARGA	TRANSPORTE AÉREO DE CARGA
1061901	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	BENEFICIAMENTO DE ARROZ E FABRICAÇÃO DE PRODUTOS DO ARROZ
1061902	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	BENEFICIAMENTO DE ARROZ E FABRICAÇÃO DE PRODUTOS DO ARROZ
1062700	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	MOAGEM DE TRIGO E FABRICAÇÃO DE DERIVADOS
1063500	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	FABRICAÇÃO DE FARINHA DE MANDIOCA E DERIVADOS
1064300	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	FABRICAÇÃO DE FARINHA DE MILHO E DERIVADOS, EXCETO ÓLEOS DE MILHO
1065101	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	FABRICAÇÃO DE AMIDOS E FÉCULAS DE VEGETAIS E DE ÓLEOS DE MILHO
1065102	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	FABRICAÇÃO DE AMIDOS E FÉCULAS DE VEGETAIS E DE ÓLEOS DE MILHO
1065103	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	FABRICAÇÃO DE AMIDOS E FÉCULAS DE VEGETAIS E DE ÓLEOS DE MILHO
1066000	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	FABRICAÇÃO DE ALIMENTOS PARA ANIMAIS
1069400	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS	MOAGEM E FABRICAÇÃO DE PRODUTOS DE ORIGEM VEGETAL NÃO ESPECIFICADOS ANTERIORMENTE
1071600	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO E REFINO DE AÇÚCAR	FABRICAÇÃO DE AÇÚCAR EM BRUTO
1072401	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO E REFINO DE AÇÚCAR	FABRICAÇÃO DE AÇÚCAR REFINADO
1072402	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO E REFINO DE AÇÚCAR	FABRICAÇÃO DE AÇÚCAR REFINADO
1081301	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	TORREFAÇÃO E MOAGEM DE CAFÉ	TORREFAÇÃO E MOAGEM DE CAFÉ
1081302	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	TORREFAÇÃO E MOAGEM DE CAFÉ	TORREFAÇÃO E MOAGEM DE CAFÉ
1082100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	TORREFAÇÃO E MOAGEM DE CAFÉ	FABRICAÇÃO DE PRODUTOS À BASE DE CAFÉ
1091101	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS DE PANIFICAÇÃO
1091102	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS DE PANIFICAÇÃO
1092900	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE BISCOITOS E BOLACHAS
1093701	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS DERIVADOS DO CACAU, DE CHOCOLATES E CONFEITOS
1093702	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS DERIVADOS DO CACAU, DE CHOCOLATES E CONFEITOS
1094500	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE MASSAS ALIMENTÍCIAS
1095300	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE ESPECIARIAS, MOLHOS, TEMPEROS E CONDIMENTOS
1096100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE ALIMENTOS E PRATOS PRONTOS
1099601	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
1099602	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
1099603	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
1099604	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
1099605	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
1099606	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
1099607	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
1099699	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
1111901	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS ALCOÓLICAS	FABRICAÇÃO DE AGUARDENTES E OUTRAS BEBIDAS DESTILADAS
1111902	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS ALCOÓLICAS	FABRICAÇÃO DE AGUARDENTES E OUTRAS BEBIDAS DESTILADAS
1112700	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS ALCOÓLICAS	FABRICAÇÃO DE VINHO
1113501	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS ALCOÓLICAS	FABRICAÇÃO DE MALTE, CERVEJAS E CHOPES
1113502	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS ALCOÓLICAS	FABRICAÇÃO DE MALTE, CERVEJAS E CHOPES
1121600	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS NÃO-ALCOÓLICAS	FABRICAÇÃO DE ÁGUAS ENVASADAS
5130700	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AÉREO	TRANSPORTE ESPACIAL	TRANSPORTE ESPACIAL
1122401	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS NÃO-ALCOÓLICAS	FABRICAÇÃO DE REFRIGERANTES E DE OUTRAS BEBIDAS NÃO-ALCOÓLICAS
1122402	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS NÃO-ALCOÓLICAS	FABRICAÇÃO DE REFRIGERANTES E DE OUTRAS BEBIDAS NÃO-ALCOÓLICAS
1122403	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS NÃO-ALCOÓLICAS	FABRICAÇÃO DE REFRIGERANTES E DE OUTRAS BEBIDAS NÃO-ALCOÓLICAS
1122404	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS NÃO-ALCOÓLICAS	FABRICAÇÃO DE REFRIGERANTES E DE OUTRAS BEBIDAS NÃO-ALCOÓLICAS
1122499	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE BEBIDAS	FABRICAÇÃO DE BEBIDAS NÃO-ALCOÓLICAS	FABRICAÇÃO DE REFRIGERANTES E DE OUTRAS BEBIDAS NÃO-ALCOÓLICAS
1210700	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DO FUMO	PROCESSAMENTO INDUSTRIAL DO FUMO	PROCESSAMENTO INDUSTRIAL DO FUMO
1220401	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DO FUMO	FABRICAÇÃO DE PRODUTOS DO FUMO	FABRICAÇÃO DE PRODUTOS DO FUMO
1220402	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DO FUMO	FABRICAÇÃO DE PRODUTOS DO FUMO	FABRICAÇÃO DE PRODUTOS DO FUMO
1220403	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DO FUMO	FABRICAÇÃO DE PRODUTOS DO FUMO	FABRICAÇÃO DE PRODUTOS DO FUMO
1220499	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DO FUMO	FABRICAÇÃO DE PRODUTOS DO FUMO	FABRICAÇÃO DE PRODUTOS DO FUMO
1311100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	PREPARAÇÃO E FIAÇÃO DE FIBRAS TÊXTEIS	PREPARAÇÃO E FIAÇÃO DE FIBRAS DE ALGODÃO
1312000	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	PREPARAÇÃO E FIAÇÃO DE FIBRAS TÊXTEIS	PREPARAÇÃO E FIAÇÃO DE FIBRAS TÊXTEIS NATURAIS, EXCETO ALGODÃO
1313800	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	PREPARAÇÃO E FIAÇÃO DE FIBRAS TÊXTEIS	FIAÇÃO DE FIBRAS ARTIFICIAIS E SINTÉTICAS
1314600	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	PREPARAÇÃO E FIAÇÃO DE FIBRAS TÊXTEIS	FABRICAÇÃO DE LINHAS PARA COSTURAR E BORDAR
1321900	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	TECELAGEM, EXCETO MALHA	TECELAGEM DE FIOS DE ALGODÃO
1322700	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	TECELAGEM, EXCETO MALHA	TECELAGEM DE FIOS DE FIBRAS TÊXTEIS NATURAIS, EXCETO ALGODÃO
1323500	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	TECELAGEM, EXCETO MALHA	TECELAGEM DE FIOS DE FIBRAS ARTIFICIAIS E SINTÉTICAS
1330800	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	FABRICAÇÃO DE TECIDOS DE MALHA	FABRICAÇÃO DE TECIDOS DE MALHA
1340501	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	ACABAMENTOS EM FIOS, TECIDOS E ARTEFATOS TÊXTEIS	ACABAMENTOS EM FIOS, TECIDOS E ARTEFATOS TÊXTEIS
1340502	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	ACABAMENTOS EM FIOS, TECIDOS E ARTEFATOS TÊXTEIS	ACABAMENTOS EM FIOS, TECIDOS E ARTEFATOS TÊXTEIS
1340599	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	ACABAMENTOS EM FIOS, TECIDOS E ARTEFATOS TÊXTEIS	ACABAMENTOS EM FIOS, TECIDOS E ARTEFATOS TÊXTEIS
1351100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	FABRICAÇÃO DE ARTEFATOS TÊXTEIS, EXCETO VESTUÁRIO	FABRICAÇÃO DE ARTEFATOS TÊXTEIS PARA USO DOMÉSTICO
1352900	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	FABRICAÇÃO DE ARTEFATOS TÊXTEIS, EXCETO VESTUÁRIO	FABRICAÇÃO DE ARTEFATOS DE TAPEÇARIA
1353700	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	FABRICAÇÃO DE ARTEFATOS TÊXTEIS, EXCETO VESTUÁRIO	FABRICAÇÃO DE ARTEFATOS DE CORDOARIA
1354500	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	FABRICAÇÃO DE ARTEFATOS TÊXTEIS, EXCETO VESTUÁRIO	FABRICAÇÃO DE TECIDOS ESPECIAIS, INCLUSIVE ARTEFATOS
1359600	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS TÊXTEIS	FABRICAÇÃO DE ARTEFATOS TÊXTEIS, EXCETO VESTUÁRIO	FABRICAÇÃO DE OUTROS PRODUTOS TÊXTEIS NÃO ESPECIFICADOS ANTERIORMENTE
1411801	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ROUPAS ÍNTIMAS
1411802	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ROUPAS ÍNTIMAS
1412601	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE PEÇAS DE VESTUÁRIO, EXCETO ROUPAS ÍNTIMAS
1412602	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE PEÇAS DE VESTUÁRIO, EXCETO ROUPAS ÍNTIMAS
1412603	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE PEÇAS DE VESTUÁRIO, EXCETO ROUPAS ÍNTIMAS
1413401	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ROUPAS PROFISSIONAIS
1413402	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ROUPAS PROFISSIONAIS
1413403	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ROUPAS PROFISSIONAIS
1414200	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	FABRICAÇÃO DE ACESSÓRIOS DO VESTUÁRIO, EXCETO PARA SEGURANÇA E PROTEÇÃO
1421500	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	FABRICAÇÃO DE ARTIGOS DE MALHARIA E TRICOTAGEM	FABRICAÇÃO DE MEIAS
1422300	INDÚSTRIAS DE TRANSFORMAÇÃO	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS	FABRICAÇÃO DE ARTIGOS DE MALHARIA E TRICOTAGEM	FABRICAÇÃO DE ARTIGOS DO VESTUÁRIO, PRODUZIDOS EM MALHARIAS E TRICOTAGENS, EXCETO MEIAS
1510600	INDÚSTRIAS DE TRANSFORMAÇÃO	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS	CURTIMENTO E OUTRAS PREPARAÇÕES DE COURO	CURTIMENTO E OUTRAS PREPARAÇÕES DE COURO
1521100	INDÚSTRIAS DE TRANSFORMAÇÃO	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS	FABRICAÇÃO DE ARTIGOS PARA VIAGEM E DE ARTEFATOS DIVERSOS DE COURO	FABRICAÇÃO DE ARTIGOS PARA VIAGEM, BOLSAS E SEMELHANTES DE QUALQUER MATERIAL
1529700	INDÚSTRIAS DE TRANSFORMAÇÃO	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS	FABRICAÇÃO DE ARTIGOS PARA VIAGEM E DE ARTEFATOS DIVERSOS DE COURO	FABRICAÇÃO DE ARTEFATOS DE COURO NÃO ESPECIFICADOS ANTERIORMENTE
1531901	INDÚSTRIAS DE TRANSFORMAÇÃO	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS	FABRICAÇÃO DE CALÇADOS	FABRICAÇÃO DE CALÇADOS DE COURO
1531902	INDÚSTRIAS DE TRANSFORMAÇÃO	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS	FABRICAÇÃO DE CALÇADOS	FABRICAÇÃO DE CALÇADOS DE COURO
1532700	INDÚSTRIAS DE TRANSFORMAÇÃO	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS	FABRICAÇÃO DE CALÇADOS	FABRICAÇÃO DE TÊNIS DE QUALQUER MATERIAL
1533500	INDÚSTRIAS DE TRANSFORMAÇÃO	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS	FABRICAÇÃO DE CALÇADOS	FABRICAÇÃO DE CALÇADOS DE MATERIAL SINTÉTICO
1539400	INDÚSTRIAS DE TRANSFORMAÇÃO	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS	FABRICAÇÃO DE CALÇADOS	FABRICAÇÃO DE CALÇADOS DE MATERIAIS NÃO ESPECIFICADOS ANTERIORMENTE
1540800	INDÚSTRIAS DE TRANSFORMAÇÃO	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS	FABRICAÇÃO DE PARTES PARA CALÇADOS, DE QUALQUER MATERIAL	FABRICAÇÃO DE PARTES PARA CALÇADOS, DE QUALQUER MATERIAL
1610203	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	DESDOBRAMENTO DE MADEIRA	DESDOBRAMENTO DE MADEIRA
1610204	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	DESDOBRAMENTO DE MADEIRA	DESDOBRAMENTO DE MADEIRA
1610205	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	DESDOBRAMENTO DE MADEIRA	DESDOBRAMENTO DE MADEIRA
1621800	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	FABRICAÇÃO DE PRODUTOS DE MADEIRA, CORTIÇA E MATERIAL TRANÇADO, EXCETO MÓVEIS	FABRICAÇÃO DE MADEIRA LAMINADA E DE CHAPAS DE MADEIRA COMPENSADA, PRENSADA E AGLOMERADA
1622601	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	FABRICAÇÃO DE PRODUTOS DE MADEIRA, CORTIÇA E MATERIAL TRANÇADO, EXCETO MÓVEIS	FABRICAÇÃO DE ESTRUTURAS DE MADEIRA E DE ARTIGOS DE CARPINTARIA PARA CONSTRUÇÃO
1622602	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	FABRICAÇÃO DE PRODUTOS DE MADEIRA, CORTIÇA E MATERIAL TRANÇADO, EXCETO MÓVEIS	FABRICAÇÃO DE ESTRUTURAS DE MADEIRA E DE ARTIGOS DE CARPINTARIA PARA CONSTRUÇÃO
1622699	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	FABRICAÇÃO DE PRODUTOS DE MADEIRA, CORTIÇA E MATERIAL TRANÇADO, EXCETO MÓVEIS	FABRICAÇÃO DE ESTRUTURAS DE MADEIRA E DE ARTIGOS DE CARPINTARIA PARA CONSTRUÇÃO
1623400	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	FABRICAÇÃO DE PRODUTOS DE MADEIRA, CORTIÇA E MATERIAL TRANÇADO, EXCETO MÓVEIS	FABRICAÇÃO DE ARTEFATOS DE TANOARIA E DE EMBALAGENS DE MADEIRA
1629301	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	FABRICAÇÃO DE PRODUTOS DE MADEIRA, CORTIÇA E MATERIAL TRANÇADO, EXCETO MÓVEIS	FABRICAÇÃO DE ARTEFATOS DE MADEIRA, PALHA, CORTIÇA, VIME E MATERIAL TRANÇADO NÃO ESPECIFICADOS ANTERIORMENTE, EXCETO MÓVEIS
1629302	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MADEIRA	FABRICAÇÃO DE PRODUTOS DE MADEIRA, CORTIÇA E MATERIAL TRANÇADO, EXCETO MÓVEIS	FABRICAÇÃO DE ARTEFATOS DE MADEIRA, PALHA, CORTIÇA, VIME E MATERIAL TRANÇADO NÃO ESPECIFICADOS ANTERIORMENTE, EXCETO MÓVEIS
1710900	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE CELULOSE E OUTRAS PASTAS PARA A FABRICAÇÃO DE PAPEL	FABRICAÇÃO DE CELULOSE E OUTRAS PASTAS PARA A FABRICAÇÃO DE PAPEL
1721400	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE PAPEL, CARTOLINA E PAPEL-CARTÃO	FABRICAÇÃO DE PAPEL
1722200	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE PAPEL, CARTOLINA E PAPEL-CARTÃO	FABRICAÇÃO DE CARTOLINA E PAPEL-CARTÃO
1731100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE EMBALAGENS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO	FABRICAÇÃO DE EMBALAGENS DE PAPEL
1732000	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE EMBALAGENS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO	FABRICAÇÃO DE EMBALAGENS DE CARTOLINA E PAPEL-CARTÃO
1733800	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE EMBALAGENS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO	FABRICAÇÃO DE CHAPAS E DE EMBALAGENS DE PAPELÃO ONDULADO
1741901	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE PRODUTOS DIVERSOS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO	FABRICAÇÃO DE PRODUTOS DE PAPEL, CARTOLINA, PAPEL CARTÃO E PAPELÃO ONDULADO PARA USO COMERCIAL E DE ESCRITÓRIO
1741902	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE PRODUTOS DIVERSOS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO	FABRICAÇÃO DE PRODUTOS DE PAPEL, CARTOLINA, PAPEL CARTÃO E PAPELÃO ONDULADO PARA USO COMERCIAL E DE ESCRITÓRIO
1742701	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE PRODUTOS DIVERSOS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO	FABRICAÇÃO DE PRODUTOS DE PAPEL PARA USOS DOMÉSTICO E HIGIÊNICO-SANITÁRIO
1742702	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE PRODUTOS DIVERSOS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO	FABRICAÇÃO DE PRODUTOS DE PAPEL PARA USOS DOMÉSTICO E HIGIÊNICO-SANITÁRIO
1742799	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE PRODUTOS DIVERSOS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO	FABRICAÇÃO DE PRODUTOS DE PAPEL PARA USOS DOMÉSTICO E HIGIÊNICO-SANITÁRIO
1749400	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL	FABRICAÇÃO DE PRODUTOS DIVERSOS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO	FABRICAÇÃO DE PRODUTOS DE PASTAS CELULÓSICAS, PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO NÃO ESPECIFICADOS ANTERIORMENTE
1811301	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	ATIVIDADE DE IMPRESSÃO	IMPRESSÃO DE JORNAIS, LIVROS, REVISTAS E OUTRAS PUBLICAÇÕES PERIÓDICAS
1811302	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	ATIVIDADE DE IMPRESSÃO	IMPRESSÃO DE JORNAIS, LIVROS, REVISTAS E OUTRAS PUBLICAÇÕES PERIÓDICAS
1812100	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	ATIVIDADE DE IMPRESSÃO	IMPRESSÃO DE MATERIAL DE SEGURANÇA
1813001	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	ATIVIDADE DE IMPRESSÃO	IMPRESSÃO DE MATERIAIS PARA OUTROS USOS
1813099	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	ATIVIDADE DE IMPRESSÃO	IMPRESSÃO DE MATERIAIS PARA OUTROS USOS
1821100	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	SERVIÇOS DE PRÉ-IMPRESSÃO E ACABAMENTOS GRÁFICOS	SERVIÇOS DE PRÉ-IMPRESSÃO
1822901	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	SERVIÇOS DE PRÉ-IMPRESSÃO E ACABAMENTOS GRÁFICOS	SERVIÇOS DE ACABAMENTOS GRÁFICOS
1822999	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	SERVIÇOS DE PRÉ-IMPRESSÃO E ACABAMENTOS GRÁFICOS	SERVIÇOS DE ACABAMENTOS GRÁFICOS
1830001	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	REPRODUÇÃO DE MATERIAIS GRAVADOS EM QUALQUER SUPORTE	REPRODUÇÃO DE MATERIAIS GRAVADOS EM QUALQUER SUPORTE
1830002	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	REPRODUÇÃO DE MATERIAIS GRAVADOS EM QUALQUER SUPORTE	REPRODUÇÃO DE MATERIAIS GRAVADOS EM QUALQUER SUPORTE
1830003	INDÚSTRIAS DE TRANSFORMAÇÃO	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES	REPRODUÇÃO DE MATERIAIS GRAVADOS EM QUALQUER SUPORTE	REPRODUÇÃO DE MATERIAIS GRAVADOS EM QUALQUER SUPORTE
1910100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE COQUE, DE PRODUTOS DERIVADOS DO PETRÓLEO E DE BIOCOMBUSTÍVEIS	COQUERIAS	COQUERIAS
1921700	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE COQUE, DE PRODUTOS DERIVADOS DO PETRÓLEO E DE BIOCOMBUSTÍVEIS	FABRICAÇÃO DE PRODUTOS DERIVADOS DO PETRÓLEO	FABRICAÇÃO DE PRODUTOS DO REFINO DE PETRÓLEO
1922501	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE COQUE, DE PRODUTOS DERIVADOS DO PETRÓLEO E DE BIOCOMBUSTÍVEIS	FABRICAÇÃO DE PRODUTOS DERIVADOS DO PETRÓLEO	FABRICAÇÃO DE PRODUTOS DERIVADOS DO PETRÓLEO, EXCETO PRODUTOS DO REFINO
1922502	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE COQUE, DE PRODUTOS DERIVADOS DO PETRÓLEO E DE BIOCOMBUSTÍVEIS	FABRICAÇÃO DE PRODUTOS DERIVADOS DO PETRÓLEO	FABRICAÇÃO DE PRODUTOS DERIVADOS DO PETRÓLEO, EXCETO PRODUTOS DO REFINO
1922599	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE COQUE, DE PRODUTOS DERIVADOS DO PETRÓLEO E DE BIOCOMBUSTÍVEIS	FABRICAÇÃO DE PRODUTOS DERIVADOS DO PETRÓLEO	FABRICAÇÃO DE PRODUTOS DERIVADOS DO PETRÓLEO, EXCETO PRODUTOS DO REFINO
1931400	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE COQUE, DE PRODUTOS DERIVADOS DO PETRÓLEO E DE BIOCOMBUSTÍVEIS	FABRICAÇÃO DE BIOCOMBUSTÍVEIS	FABRICAÇÃO DE ÁLCOOL
1932200	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE COQUE, DE PRODUTOS DERIVADOS DO PETRÓLEO E DE BIOCOMBUSTÍVEIS	FABRICAÇÃO DE BIOCOMBUSTÍVEIS	FABRICAÇÃO DE BIOCOMBUSTÍVEIS, EXCETO ÁLCOOL
2011800	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS	FABRICAÇÃO DE CLORO E ÁLCALIS
2012600	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS	FABRICAÇÃO DE INTERMEDIÁRIOS PARA FERTILIZANTES
2013401	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS	FABRICAÇÃO DE ADUBOS E FERTILIZANTES
2013402	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS	FABRICAÇÃO DE ADUBOS E FERTILIZANTES
2014200	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS	FABRICAÇÃO DE GASES INDUSTRIAIS
2019301	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS NÃO ESPECIFICADOS ANTERIORMENTE
2019399	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS NÃO ESPECIFICADOS ANTERIORMENTE
2021500	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS ORGÂNICOS	FABRICAÇÃO DE PRODUTOS PETROQUÍMICOS BÁSICOS
2022300	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS ORGÂNICOS	FABRICAÇÃO DE INTERMEDIÁRIOS PARA PLASTIFICANTES, RESINAS E FIBRAS
2029100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS ORGÂNICOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS ORGÂNICOS NÃO ESPECIFICADOS ANTERIORMENTE
2031200	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE RESINAS E ELASTÔMEROS	FABRICAÇÃO DE RESINAS TERMOPLÁSTICAS
2032100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE RESINAS E ELASTÔMEROS	FABRICAÇÃO DE RESINAS TERMOFIXAS
2033900	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE RESINAS E ELASTÔMEROS	FABRICAÇÃO DE ELASTÔMEROS
2040100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE FIBRAS ARTIFICIAIS E SINTÉTICAS	FABRICAÇÃO DE FIBRAS ARTIFICIAIS E SINTÉTICAS
2051700	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE DEFENSIVOS AGRÍCOLAS E DESINFESTANTES DOMISSANITÁRIOS	FABRICAÇÃO DE DEFENSIVOS AGRÍCOLAS
2052500	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE DEFENSIVOS AGRÍCOLAS E DESINFESTANTES DOMISSANITÁRIOS	FABRICAÇÃO DE DESINFESTANTES DOMISSANITÁRIOS
2061400	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE SABÕES, DETERGENTES, PRODUTOS DE LIMPEZA, COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL	FABRICAÇÃO DE SABÕES E DETERGENTES SINTÉTICOS
2062200	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE SABÕES, DETERGENTES, PRODUTOS DE LIMPEZA, COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL	FABRICAÇÃO DE PRODUTOS DE LIMPEZA E POLIMENTO
2063100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE SABÕES, DETERGENTES, PRODUTOS DE LIMPEZA, COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL	FABRICAÇÃO DE COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL
2071100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE TINTAS, VERNIZES, ESMALTES, LACAS E PRODUTOS AFINS	FABRICAÇÃO DE TINTAS, VERNIZES, ESMALTES E LACAS
2072000	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE TINTAS, VERNIZES, ESMALTES, LACAS E PRODUTOS AFINS	FABRICAÇÃO DE TINTAS DE IMPRESSÃO
2073800	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE TINTAS, VERNIZES, ESMALTES, LACAS E PRODUTOS AFINS	FABRICAÇÃO DE IMPERMEABILIZANTES, SOLVENTES E PRODUTOS AFINS
2091600	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS E PREPARADOS QUÍMICOS DIVERSOS	FABRICAÇÃO DE ADESIVOS E SELANTES
2092401	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS E PREPARADOS QUÍMICOS DIVERSOS	FABRICAÇÃO DE EXPLOSIVOS
2092402	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS E PREPARADOS QUÍMICOS DIVERSOS	FABRICAÇÃO DE EXPLOSIVOS
2092403	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS E PREPARADOS QUÍMICOS DIVERSOS	FABRICAÇÃO DE EXPLOSIVOS
2093200	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS E PREPARADOS QUÍMICOS DIVERSOS	FABRICAÇÃO DE ADITIVOS DE USO INDUSTRIAL
2094100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS E PREPARADOS QUÍMICOS DIVERSOS	FABRICAÇÃO DE CATALISADORES
2099101	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS E PREPARADOS QUÍMICOS DIVERSOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS NÃO ESPECIFICADOS ANTERIORMENTE
2099199	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS QUÍMICOS	FABRICAÇÃO DE PRODUTOS E PREPARADOS QUÍMICOS DIVERSOS	FABRICAÇÃO DE PRODUTOS QUÍMICOS NÃO ESPECIFICADOS ANTERIORMENTE
2110600	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS E FARMACÊUTICOS	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS
2121101	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS E FARMACÊUTICOS	FABRICAÇÃO DE PRODUTOS FARMACÊUTICOS	FABRICAÇÃO DE MEDICAMENTOS PARA USO HUMANO
2121102	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS E FARMACÊUTICOS	FABRICAÇÃO DE PRODUTOS FARMACÊUTICOS	FABRICAÇÃO DE MEDICAMENTOS PARA USO HUMANO
2121103	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS E FARMACÊUTICOS	FABRICAÇÃO DE PRODUTOS FARMACÊUTICOS	FABRICAÇÃO DE MEDICAMENTOS PARA USO HUMANO
2122000	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS E FARMACÊUTICOS	FABRICAÇÃO DE PRODUTOS FARMACÊUTICOS	FABRICAÇÃO DE MEDICAMENTOS PARA USO VETERINÁRIO
2123800	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS E FARMACÊUTICOS	FABRICAÇÃO DE PRODUTOS FARMACÊUTICOS	FABRICAÇÃO DE PREPARAÇÕES FARMACÊUTICAS
2211100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE BORRACHA	FABRICAÇÃO DE PNEUMÁTICOS E DE CÂMARAS-DE-AR
2212900	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE BORRACHA	REFORMA DE PNEUMÁTICOS USADOS
2219600	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE BORRACHA	FABRICAÇÃO DE ARTEFATOS DE BORRACHA NÃO ESPECIFICADOS ANTERIORMENTE
2221800	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE MATERIAL PLÁSTICO	FABRICAÇÃO DE LAMINADOS PLANOS E TUBULARES DE MATERIAL PLÁSTICO
2222600	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE MATERIAL PLÁSTICO	FABRICAÇÃO DE EMBALAGENS DE MATERIAL PLÁSTICO
2223400	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE MATERIAL PLÁSTICO	FABRICAÇÃO DE TUBOS E ACESSÓRIOS DE MATERIAL PLÁSTICO PARA USO NA CONSTRUÇÃO
2229301	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE MATERIAL PLÁSTICO	FABRICAÇÃO DE ARTEFATOS DE MATERIAL PLÁSTICO NÃO ESPECIFICADOS ANTERIORMENTE
2229302	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE MATERIAL PLÁSTICO	FABRICAÇÃO DE ARTEFATOS DE MATERIAL PLÁSTICO NÃO ESPECIFICADOS ANTERIORMENTE
2229303	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE MATERIAL PLÁSTICO	FABRICAÇÃO DE ARTEFATOS DE MATERIAL PLÁSTICO NÃO ESPECIFICADOS ANTERIORMENTE
2229399	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO	FABRICAÇÃO DE PRODUTOS DE MATERIAL PLÁSTICO	FABRICAÇÃO DE ARTEFATOS DE MATERIAL PLÁSTICO NÃO ESPECIFICADOS ANTERIORMENTE
2311700	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE VIDRO E DE PRODUTOS DO VIDRO	FABRICAÇÃO DE VIDRO PLANO E DE SEGURANÇA
2312500	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE VIDRO E DE PRODUTOS DO VIDRO	FABRICAÇÃO DE EMBALAGENS DE VIDRO
2319200	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE VIDRO E DE PRODUTOS DO VIDRO	FABRICAÇÃO DE ARTIGOS DE VIDRO
2320600	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE CIMENTO	FABRICAÇÃO DE CIMENTO
2330301	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES
2330302	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES
2330303	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES
2330304	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES
2330305	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES
2330399	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES
2341900	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS REFRATÁRIOS
2342701	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS NÃO-REFRATÁRIOS PARA USO ESTRUTURAL NA CONSTRUÇÃO
2342702	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS NÃO-REFRATÁRIOS PARA USO ESTRUTURAL NA CONSTRUÇÃO
2349401	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS NÃO-REFRATÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
2349499	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS	FABRICAÇÃO DE PRODUTOS CERÂMICOS NÃO-REFRATÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
2391501	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO DE PEDRAS E FABRICAÇÃO DE OUTROS PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO E OUTROS TRABALHOS EM PEDRAS
2391502	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO DE PEDRAS E FABRICAÇÃO DE OUTROS PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO E OUTROS TRABALHOS EM PEDRAS
2391503	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO DE PEDRAS E FABRICAÇÃO DE OUTROS PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO E OUTROS TRABALHOS EM PEDRAS
2392300	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO DE PEDRAS E FABRICAÇÃO DE OUTROS PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE CAL E GESSO
2399101	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO DE PEDRAS E FABRICAÇÃO DE OUTROS PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE
2399102	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO DE PEDRAS E FABRICAÇÃO DE OUTROS PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE
2399199	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS	APARELHAMENTO DE PEDRAS E FABRICAÇÃO DE OUTROS PRODUTOS DE MINERAIS NÃO-METÁLICOS	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE
2411300	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	PRODUÇÃO DE FERRO-GUSA E DE FERROLIGAS	PRODUÇÃO DE FERRO-GUSA
2412100	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	PRODUÇÃO DE FERRO-GUSA E DE FERROLIGAS	PRODUÇÃO DE FERROLIGAS
2421100	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	SIDERURGIA	PRODUÇÃO DE SEMI-ACABADOS DE AÇO
2422901	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	SIDERURGIA	PRODUÇÃO DE LAMINADOS PLANOS DE AÇO
2422902	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	SIDERURGIA	PRODUÇÃO DE LAMINADOS PLANOS DE AÇO
2423701	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	SIDERURGIA	PRODUÇÃO DE LAMINADOS LONGOS DE AÇO
2423702	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	SIDERURGIA	PRODUÇÃO DE LAMINADOS LONGOS DE AÇO
2424501	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	SIDERURGIA	PRODUÇÃO DE RELAMINADOS, TREFILADOS E PERFILADOS DE AÇO
2424502	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	SIDERURGIA	PRODUÇÃO DE RELAMINADOS, TREFILADOS E PERFILADOS DE AÇO
2431800	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	PRODUÇÃO DE TUBOS DE AÇO, EXCETO TUBOS SEM COSTURA	PRODUÇÃO DE CANOS E TUBOS COM COSTURA
2439300	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	PRODUÇÃO DE TUBOS DE AÇO, EXCETO TUBOS SEM COSTURA	PRODUÇÃO DE OUTROS TUBOS DE FERRO E AÇO
2441501	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	METALURGIA DOS METAIS NÃO-FERROSOS	METALURGIA DO ALUMÍNIO E SUAS LIGAS
2441502	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	METALURGIA DOS METAIS NÃO-FERROSOS	METALURGIA DO ALUMÍNIO E SUAS LIGAS
2442300	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	METALURGIA DOS METAIS NÃO-FERROSOS	METALURGIA DOS METAIS PRECIOSOS
2443100	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	METALURGIA DOS METAIS NÃO-FERROSOS	METALURGIA DO COBRE
2449101	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	METALURGIA DOS METAIS NÃO-FERROSOS	METALURGIA DOS METAIS NÃO-FERROSOS E SUAS LIGAS NÃO ESPECIFICADOS ANTERIORMENTE
2449102	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	METALURGIA DOS METAIS NÃO-FERROSOS	METALURGIA DOS METAIS NÃO-FERROSOS E SUAS LIGAS NÃO ESPECIFICADOS ANTERIORMENTE
2449103	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	METALURGIA DOS METAIS NÃO-FERROSOS	METALURGIA DOS METAIS NÃO-FERROSOS E SUAS LIGAS NÃO ESPECIFICADOS ANTERIORMENTE
2449199	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	METALURGIA DOS METAIS NÃO-FERROSOS	METALURGIA DOS METAIS NÃO-FERROSOS E SUAS LIGAS NÃO ESPECIFICADOS ANTERIORMENTE
2451200	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	FUNDIÇÃO	FUNDIÇÃO DE FERRO E AÇO
2452100	INDÚSTRIAS DE TRANSFORMAÇÃO	METALURGIA	FUNDIÇÃO	FUNDIÇÃO DE METAIS NÃO-FERROSOS E SUAS LIGAS
2511000	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE ESTRUTURAS METÁLICAS E OBRAS DE CALDEIRARIA PESADA	FABRICAÇÃO DE ESTRUTURAS METÁLICAS
2512800	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE ESTRUTURAS METÁLICAS E OBRAS DE CALDEIRARIA PESADA	FABRICAÇÃO DE ESQUADRIAS DE METAL
2513600	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE ESTRUTURAS METÁLICAS E OBRAS DE CALDEIRARIA PESADA	FABRICAÇÃO DE OBRAS DE CALDEIRARIA PESADA
2521700	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE TANQUES, RESERVATÓRIOS METÁLICOS E CALDEIRAS	FABRICAÇÃO DE TANQUES, RESERVATÓRIOS METÁLICOS E CALDEIRAS PARA AQUECIMENTO CENTRAL
2522500	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE TANQUES, RESERVATÓRIOS METÁLICOS E CALDEIRAS	FABRICAÇÃO DE CALDEIRAS GERADORAS DE VAPOR, EXCETO PARA AQUECIMENTO CENTRAL E PARA VEÍCULOS
2531401	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FORJARIA, ESTAMPARIA, METALURGIA DO PÓ E SERVIÇOS DE TRATAMENTO DE METAIS	PRODUÇÃO DE FORJADOS DE AÇO E DE METAIS NÃO-FERROSOS E SUAS LIGAS
2531402	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FORJARIA, ESTAMPARIA, METALURGIA DO PÓ E SERVIÇOS DE TRATAMENTO DE METAIS	PRODUÇÃO DE FORJADOS DE AÇO E DE METAIS NÃO-FERROSOS E SUAS LIGAS
2532201	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FORJARIA, ESTAMPARIA, METALURGIA DO PÓ E SERVIÇOS DE TRATAMENTO DE METAIS	PRODUÇÃO DE ARTEFATOS ESTAMPADOS DE METAL; METALURGIA DO PÓ
2532202	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FORJARIA, ESTAMPARIA, METALURGIA DO PÓ E SERVIÇOS DE TRATAMENTO DE METAIS	PRODUÇÃO DE ARTEFATOS ESTAMPADOS DE METAL; METALURGIA DO PÓ
2539001	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FORJARIA, ESTAMPARIA, METALURGIA DO PÓ E SERVIÇOS DE TRATAMENTO DE METAIS	SERVIÇOS DE USINAGEM, SOLDA, TRATAMENTO E REVESTIMENTO EM METAIS
2539002	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FORJARIA, ESTAMPARIA, METALURGIA DO PÓ E SERVIÇOS DE TRATAMENTO DE METAIS	SERVIÇOS DE USINAGEM, SOLDA, TRATAMENTO E REVESTIMENTO EM METAIS
2541100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE ARTIGOS DE CUTELARIA, DE SERRALHERIA E FERRAMENTAS	FABRICAÇÃO DE ARTIGOS DE CUTELARIA
2542000	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE ARTIGOS DE CUTELARIA, DE SERRALHERIA E FERRAMENTAS	FABRICAÇÃO DE ARTIGOS DE SERRALHERIA, EXCETO ESQUADRIAS
2543800	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE ARTIGOS DE CUTELARIA, DE SERRALHERIA E FERRAMENTAS	FABRICAÇÃO DE FERRAMENTAS
2550101	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE EQUIPAMENTO BÉLICO PESADO, ARMAS E MUNIÇÕES	FABRICAÇÃO DE EQUIPAMENTO BÉLICO PESADO, ARMAS E MUNIÇÕES
2550102	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE EQUIPAMENTO BÉLICO PESADO, ARMAS E MUNIÇÕES	FABRICAÇÃO DE EQUIPAMENTO BÉLICO PESADO, ARMAS E MUNIÇÕES
2591800	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE EMBALAGENS METÁLICAS
2592601	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE PRODUTOS DE TREFILADOS DE METAL
2592602	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE PRODUTOS DE TREFILADOS DE METAL
2593400	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE ARTIGOS DE METAL PARA USO DOMÉSTICO E PESSOAL
2599301	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE
2599302	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE
2599399	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE
2610800	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE COMPONENTES ELETRÔNICOS	FABRICAÇÃO DE COMPONENTES ELETRÔNICOS
2621300	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E PERIFÉRICOS	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA
2622100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E PERIFÉRICOS	FABRICAÇÃO DE PERIFÉRICOS PARA EQUIPAMENTOS DE INFORMÁTICA
2631100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE EQUIPAMENTOS DE COMUNICAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS TRANSMISSORES DE COMUNICAÇÃO
2632900	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE EQUIPAMENTOS DE COMUNICAÇÃO	FABRICAÇÃO DE APARELHOS TELEFÔNICOS E DE OUTROS EQUIPAMENTOS DE COMUNICAÇÃO
2640000	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE APARELHOS DE RECEPÇÃO, REPRODUÇÃO, GRAVAÇÃO E AMPLIFICAÇÃO DE ÁUDIO E VÍDEO	FABRICAÇÃO DE APARELHOS DE RECEPÇÃO, REPRODUÇÃO, GRAVAÇÃO E AMPLIFICAÇÃO DE ÁUDIO E VÍDEO
2651500	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE APARELHOS E INSTRUMENTOS DE MEDIDA, TESTE E CONTROLE; CRONÔMETROS E RELÓGIOS	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS DE MEDIDA, TESTE E CONTROLE
2652300	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE APARELHOS E INSTRUMENTOS DE MEDIDA, TESTE E CONTROLE; CRONÔMETROS E RELÓGIOS	FABRICAÇÃO DE CRONÔMETROS E RELÓGIOS
2660400	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE APARELHOS ELETROMÉDICOS E ELETROTERAPÊUTICOS E EQUIPAMENTOS DE IRRADIAÇÃO	FABRICAÇÃO DE APARELHOS ELETROMÉDICOS E ELETROTERAPÊUTICOS E EQUIPAMENTOS DE IRRADIAÇÃO
2670101	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE EQUIPAMENTOS E INSTRUMENTOS ÓPTICOS, FOTOGRÁFICOS E CINEMATOGRÁFICOS	FABRICAÇÃO DE EQUIPAMENTOS E INSTRUMENTOS ÓPTICOS, FOTOGRÁFICOS E CINEMATOGRÁFICOS
2670102	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE EQUIPAMENTOS E INSTRUMENTOS ÓPTICOS, FOTOGRÁFICOS E CINEMATOGRÁFICOS	FABRICAÇÃO DE EQUIPAMENTOS E INSTRUMENTOS ÓPTICOS, FOTOGRÁFICOS E CINEMATOGRÁFICOS
2680900	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS	FABRICAÇÃO DE MÍDIAS VIRGENS, MAGNÉTICAS E ÓPTICAS	FABRICAÇÃO DE MÍDIAS VIRGENS, MAGNÉTICAS E ÓPTICAS
2710401	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE GERADORES, TRANSFORMADORES E MOTORES ELÉTRICOS	FABRICAÇÃO DE GERADORES, TRANSFORMADORES E MOTORES ELÉTRICOS
2710402	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE GERADORES, TRANSFORMADORES E MOTORES ELÉTRICOS	FABRICAÇÃO DE GERADORES, TRANSFORMADORES E MOTORES ELÉTRICOS
2710403	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE GERADORES, TRANSFORMADORES E MOTORES ELÉTRICOS	FABRICAÇÃO DE GERADORES, TRANSFORMADORES E MOTORES ELÉTRICOS
2721000	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE PILHAS, BATERIAS E ACUMULADORES ELÉTRICOS	FABRICAÇÃO DE PILHAS, BATERIAS E ACUMULADORES ELÉTRICOS, EXCETO PARA VEÍCULOS AUTOMOTORES
2722801	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE PILHAS, BATERIAS E ACUMULADORES ELÉTRICOS	FABRICAÇÃO DE BATERIAS E ACUMULADORES PARA VEÍCULOS AUTOMOTORES
2722802	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE PILHAS, BATERIAS E ACUMULADORES ELÉTRICOS	FABRICAÇÃO DE BATERIAS E ACUMULADORES PARA VEÍCULOS AUTOMOTORES
2731700	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE EQUIPAMENTOS PARA DISTRIBUIÇÃO E CONTROLE DE ENERGIA ELÉTRICA	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS PARA DISTRIBUIÇÃO E CONTROLE DE ENERGIA ELÉTRICA
2732500	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE EQUIPAMENTOS PARA DISTRIBUIÇÃO E CONTROLE DE ENERGIA ELÉTRICA	FABRICAÇÃO DE MATERIAL ELÉTRICO PARA INSTALAÇÕES EM CIRCUITO DE CONSUMO
2733300	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE EQUIPAMENTOS PARA DISTRIBUIÇÃO E CONTROLE DE ENERGIA ELÉTRICA	FABRICAÇÃO DE FIOS, CABOS E CONDUTORES ELÉTRICOS ISOLADOS
2740601	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE LÂMPADAS E OUTROS EQUIPAMENTOS DE ILUMINAÇÃO	FABRICAÇÃO DE LÂMPADAS E OUTROS EQUIPAMENTOS DE ILUMINAÇÃO
2740602	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE LÂMPADAS E OUTROS EQUIPAMENTOS DE ILUMINAÇÃO	FABRICAÇÃO DE LÂMPADAS E OUTROS EQUIPAMENTOS DE ILUMINAÇÃO
2751100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE ELETRODOMÉSTICOS	FABRICAÇÃO DE FOGÕES, REFRIGERADORES E MÁQUINAS DE LAVAR E SECAR PARA USO DOMÉSTICO
2759701	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE ELETRODOMÉSTICOS	FABRICAÇÃO DE APARELHOS ELETRODOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
2759799	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE ELETRODOMÉSTICOS	FABRICAÇÃO DE APARELHOS ELETRODOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
2790201	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE EQUIPAMENTOS E APARELHOS ELÉTRICOS NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE EQUIPAMENTOS E APARELHOS ELÉTRICOS NÃO ESPECIFICADOS ANTERIORMENTE
2790202	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE EQUIPAMENTOS E APARELHOS ELÉTRICOS NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE EQUIPAMENTOS E APARELHOS ELÉTRICOS NÃO ESPECIFICADOS ANTERIORMENTE
2790299	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS	FABRICAÇÃO DE EQUIPAMENTOS E APARELHOS ELÉTRICOS NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE EQUIPAMENTOS E APARELHOS ELÉTRICOS NÃO ESPECIFICADOS ANTERIORMENTE
2811900	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MOTORES, BOMBAS, COMPRESSORES E EQUIPAMENTOS DE TRANSMISSÃO	FABRICAÇÃO DE MOTORES E TURBINAS, EXCETO PARA AVIÕES E VEÍCULOS RODOVIÁRIOS
2812700	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MOTORES, BOMBAS, COMPRESSORES E EQUIPAMENTOS DE TRANSMISSÃO	FABRICAÇÃO DE EQUIPAMENTOS HIDRÁULICOS E PNEUMÁTICOS, EXCETO VÁLVULAS
2813500	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MOTORES, BOMBAS, COMPRESSORES E EQUIPAMENTOS DE TRANSMISSÃO	FABRICAÇÃO DE VÁLVULAS, REGISTROS E DISPOSITIVOS SEMELHANTES
2814301	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MOTORES, BOMBAS, COMPRESSORES E EQUIPAMENTOS DE TRANSMISSÃO	FABRICAÇÃO DE COMPRESSORES
2814302	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MOTORES, BOMBAS, COMPRESSORES E EQUIPAMENTOS DE TRANSMISSÃO	FABRICAÇÃO DE COMPRESSORES
2815101	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MOTORES, BOMBAS, COMPRESSORES E EQUIPAMENTOS DE TRANSMISSÃO	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSMISSÃO PARA FINS INDUSTRIAIS
2815102	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MOTORES, BOMBAS, COMPRESSORES E EQUIPAMENTOS DE TRANSMISSÃO	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSMISSÃO PARA FINS INDUSTRIAIS
2821601	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS PARA INSTALAÇÕES TÉRMICAS
2821602	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS PARA INSTALAÇÕES TÉRMICAS
2822401	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE MÁQUINAS, EQUIPAMENTOS E APARELHOS PARA TRANSPORTE E ELEVAÇÃO DE CARGAS E PESSOAS
2822402	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE MÁQUINAS, EQUIPAMENTOS E APARELHOS PARA TRANSPORTE E ELEVAÇÃO DE CARGAS E PESSOAS
2823200	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE MÁQUINAS E APARELHOS DE REFRIGERAÇÃO E VENTILAÇÃO PARA USO INDUSTRIAL E COMERCIAL
2824101	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS DE AR CONDICIONADO
2824102	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS DE AR CONDICIONADO
2825900	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA SANEAMENTO BÁSICO E AMBIENTAL
2829101	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL NÃO ESPECIFICADOS ANTERIORMENTE
2829199	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL NÃO ESPECIFICADOS ANTERIORMENTE
2831300	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE TRATORES E DE MÁQUINAS E EQUIPAMENTOS PARA A AGRICULTURA E PECUÁRIA	FABRICAÇÃO DE TRATORES AGRÍCOLAS
2832100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE TRATORES E DE MÁQUINAS E EQUIPAMENTOS PARA A AGRICULTURA E PECUÁRIA	FABRICAÇÃO DE EQUIPAMENTOS PARA IRRIGAÇÃO AGRÍCOLA
2833000	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE TRATORES E DE MÁQUINAS E EQUIPAMENTOS PARA A AGRICULTURA E PECUÁRIA	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A AGRICULTURA E PECUÁRIA, EXCETO PARA IRRIGAÇÃO
2840200	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS-FERRAMENTA	FABRICAÇÃO DE MÁQUINAS-FERRAMENTA
2851800	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO NA EXTRAÇÃO MINERAL E NA CONSTRUÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A PROSPECÇÃO E EXTRAÇÃO DE PETRÓLEO
2852600	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO NA EXTRAÇÃO MINERAL E NA CONSTRUÇÃO	FABRICAÇÃO DE OUTRAS MÁQUINAS E EQUIPAMENTOS PARA USO NA EXTRAÇÃO MINERAL, EXCETO NA EXTRAÇÃO DE PETRÓLEO
2853400	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO NA EXTRAÇÃO MINERAL E NA CONSTRUÇÃO	FABRICAÇÃO DE TRATORES, EXCETO AGRÍCOLAS
2854200	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO NA EXTRAÇÃO MINERAL E NA CONSTRUÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA TERRAPLENAGEM, PAVIMENTAÇÃO E CONSTRUÇÃO, EXCETO TRATORES
2861500	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO INDUSTRIAL ESPECÍFICO	FABRICAÇÃO DE MÁQUINAS PARA A INDÚSTRIA METALÚRGICA, EXCETO MÁQUINAS-FERRAMENTA
2862300	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO INDUSTRIAL ESPECÍFICO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AS INDÚSTRIAS DE ALIMENTOS, BEBIDAS E FUMO
2863100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO INDUSTRIAL ESPECÍFICO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A INDÚSTRIA TÊXTIL
2864000	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO INDUSTRIAL ESPECÍFICO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AS INDÚSTRIAS DO VESTUÁRIO, DO COURO E DE CALÇADOS
2865800	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO INDUSTRIAL ESPECÍFICO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AS INDÚSTRIAS DE CELULOSE, PAPEL E PAPELÃO E ARTEFATOS
2866600	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO INDUSTRIAL ESPECÍFICO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A INDÚSTRIA DO PLÁSTICO
2869100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO INDUSTRIAL ESPECÍFICO	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA USO INDUSTRIAL ESPECÍFICO NÃO ESPECIFICADOS ANTERIORMENTE
2910701	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS	FABRICAÇÃO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS
2910702	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS	FABRICAÇÃO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS
2910703	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS	FABRICAÇÃO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS
2920401	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE CAMINHÕES E ÔNIBUS	FABRICAÇÃO DE CAMINHÕES E ÔNIBUS
2920402	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE CAMINHÕES E ÔNIBUS	FABRICAÇÃO DE CAMINHÕES E ÔNIBUS
2930101	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE CABINES, CARROCERIAS E REBOQUES PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE CABINES, CARROCERIAS E REBOQUES PARA VEÍCULOS AUTOMOTORES
2930102	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE CABINES, CARROCERIAS E REBOQUES PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE CABINES, CARROCERIAS E REBOQUES PARA VEÍCULOS AUTOMOTORES
2930103	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE CABINES, CARROCERIAS E REBOQUES PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE CABINES, CARROCERIAS E REBOQUES PARA VEÍCULOS AUTOMOTORES
2941700	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA O SISTEMA MOTOR DE VEÍCULOS AUTOMOTORES
2942500	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA OS SISTEMAS DE MARCHA E TRANSMISSÃO DE VEÍCULOS AUTOMOTORES
2943300	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA O SISTEMA DE FREIOS DE VEÍCULOS AUTOMOTORES
2944100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA O SISTEMA DE DIREÇÃO E SUSPENSÃO DE VEÍCULOS AUTOMOTORES
2945000	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE MATERIAL ELÉTRICO E ELETRÔNICO PARA VEÍCULOS AUTOMOTORES, EXCETO BATERIAS
2949201	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES NÃO ESPECIFICADOS ANTERIORMENTE
2949299	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES NÃO ESPECIFICADOS ANTERIORMENTE
2950600	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS	RECONDICIONAMENTO E RECUPERAÇÃO DE MOTORES PARA VEÍCULOS AUTOMOTORES	RECONDICIONAMENTO E RECUPERAÇÃO DE MOTORES PARA VEÍCULOS AUTOMOTORES
3011301	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	CONSTRUÇÃO DE EMBARCAÇÕES	CONSTRUÇÃO DE EMBARCAÇÕES E ESTRUTURAS FLUTUANTES
3011302	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	CONSTRUÇÃO DE EMBARCAÇÕES	CONSTRUÇÃO DE EMBARCAÇÕES E ESTRUTURAS FLUTUANTES
3012100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	CONSTRUÇÃO DE EMBARCAÇÕES	CONSTRUÇÃO DE EMBARCAÇÕES PARA ESPORTE E LAZER
3031800	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE VEÍCULOS FERROVIÁRIOS	FABRICAÇÃO DE LOCOMOTIVAS, VAGÕES E OUTROS MATERIAIS RODANTES
3032600	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE VEÍCULOS FERROVIÁRIOS	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS FERROVIÁRIOS
3041500	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE AERONAVES	FABRICAÇÃO DE AERONAVES
3042300	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE AERONAVES	FABRICAÇÃO DE TURBINAS, MOTORES E OUTROS COMPONENTES E PEÇAS PARA AERONAVES
3050400	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE VEÍCULOS MILITARES DE COMBATE	FABRICAÇÃO DE VEÍCULOS MILITARES DE COMBATE
3091101	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSPORTE NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE MOTOCICLETAS
3091102	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSPORTE NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE MOTOCICLETAS
3092000	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSPORTE NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE BICICLETAS E TRICICLOS NÃO-MOTORIZADOS
3099700	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSPORTE NÃO ESPECIFICADOS ANTERIORMENTE	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSPORTE NÃO ESPECIFICADOS ANTERIORMENTE
3101200	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÓVEIS	FABRICAÇÃO DE MÓVEIS	FABRICAÇÃO DE MÓVEIS COM PREDOMINÂNCIA DE MADEIRA
3102100	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÓVEIS	FABRICAÇÃO DE MÓVEIS	FABRICAÇÃO DE MÓVEIS COM PREDOMINÂNCIA DE METAL
3103900	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÓVEIS	FABRICAÇÃO DE MÓVEIS	FABRICAÇÃO DE MÓVEIS DE OUTROS MATERIAIS, EXCETO MADEIRA E METAL
3104700	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE MÓVEIS	FABRICAÇÃO DE MÓVEIS	FABRICAÇÃO DE COLCHÕES
3211601	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE ARTIGOS DE JOALHERIA, BIJUTERIA E SEMELHANTES	LAPIDAÇÃO DE GEMAS E FABRICAÇÃO DE ARTEFATOS DE OURIVESARIA E JOALHERIA
3211602	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE ARTIGOS DE JOALHERIA, BIJUTERIA E SEMELHANTES	LAPIDAÇÃO DE GEMAS E FABRICAÇÃO DE ARTEFATOS DE OURIVESARIA E JOALHERIA
3211603	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE ARTIGOS DE JOALHERIA, BIJUTERIA E SEMELHANTES	LAPIDAÇÃO DE GEMAS E FABRICAÇÃO DE ARTEFATOS DE OURIVESARIA E JOALHERIA
3212400	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE ARTIGOS DE JOALHERIA, BIJUTERIA E SEMELHANTES	FABRICAÇÃO DE BIJUTERIAS E ARTEFATOS SEMELHANTES
3220500	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE INSTRUMENTOS MUSICAIS	FABRICAÇÃO DE INSTRUMENTOS MUSICAIS
3230200	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE ARTEFATOS PARA PESCA E ESPORTE	FABRICAÇÃO DE ARTEFATOS PARA PESCA E ESPORTE
3240001	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE BRINQUEDOS E JOGOS RECREATIVOS	FABRICAÇÃO DE BRINQUEDOS E JOGOS RECREATIVOS
3240002	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE BRINQUEDOS E JOGOS RECREATIVOS	FABRICAÇÃO DE BRINQUEDOS E JOGOS RECREATIVOS
3240003	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE BRINQUEDOS E JOGOS RECREATIVOS	FABRICAÇÃO DE BRINQUEDOS E JOGOS RECREATIVOS
3240099	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE BRINQUEDOS E JOGOS RECREATIVOS	FABRICAÇÃO DE BRINQUEDOS E JOGOS RECREATIVOS
3250701	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS
3250702	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS
3250703	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS
3250704	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS
3250705	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS
3250706	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS
3250707	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS
3250709	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS
3291400	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE ESCOVAS, PINCÉIS E VASSOURAS
3292201	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE EQUIPAMENTOS E ACESSÓRIOS PARA SEGURANÇA E PROTEÇÃO PESSOAL E PROFISSIONAL
3292202	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE EQUIPAMENTOS E ACESSÓRIOS PARA SEGURANÇA E PROTEÇÃO PESSOAL E PROFISSIONAL
3299001	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS NÃO ESPECIFICADOS ANTERIORMENTE
3299002	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS NÃO ESPECIFICADOS ANTERIORMENTE
3299003	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS NÃO ESPECIFICADOS ANTERIORMENTE
3299004	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS NÃO ESPECIFICADOS ANTERIORMENTE
3299005	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS NÃO ESPECIFICADOS ANTERIORMENTE
3299006	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS NÃO ESPECIFICADOS ANTERIORMENTE
3299099	INDÚSTRIAS DE TRANSFORMAÇÃO	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS	FABRICAÇÃO DE PRODUTOS DIVERSOS NÃO ESPECIFICADOS ANTERIORMENTE
3311200	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE TANQUES, RESERVATÓRIOS METÁLICOS E CALDEIRAS, EXCETO PARA VEÍCULOS
3312102	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE EQUIPAMENTOS ELETRÔNICOS E ÓPTICOS
3312103	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE EQUIPAMENTOS ELETRÔNICOS E ÓPTICOS
3312104	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE EQUIPAMENTOS ELETRÔNICOS E ÓPTICOS
3313901	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS ELÉTRICOS
3313902	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS ELÉTRICOS
3313999	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS ELÉTRICOS
3314701	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314702	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314703	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314704	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314705	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314706	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314707	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314708	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314709	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314710	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314711	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314712	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314713	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314714	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314715	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314716	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314717	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314718	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314719	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314720	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314721	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314722	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3314799	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
3315500	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS FERROVIÁRIOS
3316301	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE AERONAVES
3316302	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE AERONAVES
3317101	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE EMBARCAÇÕES
3317102	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE EMBARCAÇÕES
3319800	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS	MANUTENÇÃO E REPARAÇÃO DE EQUIPAMENTOS E PRODUTOS NÃO ESPECIFICADOS ANTERIORMENTE
3321000	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS INDUSTRIAIS
3329501	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	INSTALAÇÃO DE EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE
3329599	INDÚSTRIAS DE TRANSFORMAÇÃO	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS	INSTALAÇÃO DE EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE
3511501	ELETRICIDADE E GÁS	ELETRICIDADE, GÁS E OUTRAS UTILIDADES	GERAÇÃO, TRANSMISSÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA	GERAÇÃO DE ENERGIA ELÉTRICA
3511502	ELETRICIDADE E GÁS	ELETRICIDADE, GÁS E OUTRAS UTILIDADES	GERAÇÃO, TRANSMISSÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA	GERAÇÃO DE ENERGIA ELÉTRICA
3512300	ELETRICIDADE E GÁS	ELETRICIDADE, GÁS E OUTRAS UTILIDADES	GERAÇÃO, TRANSMISSÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA	TRANSMISSÃO DE ENERGIA ELÉTRICA
3513100	ELETRICIDADE E GÁS	ELETRICIDADE, GÁS E OUTRAS UTILIDADES	GERAÇÃO, TRANSMISSÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA	COMÉRCIO ATACADISTA DE ENERGIA ELÉTRICA
3514000	ELETRICIDADE E GÁS	ELETRICIDADE, GÁS E OUTRAS UTILIDADES	GERAÇÃO, TRANSMISSÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA	DISTRIBUIÇÃO DE ENERGIA ELÉTRICA
3520401	ELETRICIDADE E GÁS	ELETRICIDADE, GÁS E OUTRAS UTILIDADES	PRODUÇÃO E DISTRIBUIÇÃO DE COMBUSTÍVEIS GASOSOS POR REDES URBANAS	PRODUÇÃO DE GÁS; PROCESSAMENTO DE GÁS NATURAL; DISTRIBUIÇÃO DE COMBUSTÍVEIS GASOSOS POR REDES URBANAS
3520402	ELETRICIDADE E GÁS	ELETRICIDADE, GÁS E OUTRAS UTILIDADES	PRODUÇÃO E DISTRIBUIÇÃO DE COMBUSTÍVEIS GASOSOS POR REDES URBANAS	PRODUÇÃO DE GÁS; PROCESSAMENTO DE GÁS NATURAL; DISTRIBUIÇÃO DE COMBUSTÍVEIS GASOSOS POR REDES URBANAS
3530100	ELETRICIDADE E GÁS	ELETRICIDADE, GÁS E OUTRAS UTILIDADES	PRODUÇÃO E DISTRIBUIÇÃO DE VAPOR, ÁGUA QUENTE E AR CONDICIONADO	PRODUÇÃO E DISTRIBUIÇÃO DE VAPOR, ÁGUA QUENTE E AR CONDICIONADO
3600601	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	CAPTAÇÃO, TRATAMENTO E DISTRIBUIÇÃO DE ÁGUA	CAPTAÇÃO, TRATAMENTO E DISTRIBUIÇÃO DE ÁGUA	CAPTAÇÃO, TRATAMENTO E DISTRIBUIÇÃO DE ÁGUA
3600602	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	CAPTAÇÃO, TRATAMENTO E DISTRIBUIÇÃO DE ÁGUA	CAPTAÇÃO, TRATAMENTO E DISTRIBUIÇÃO DE ÁGUA	CAPTAÇÃO, TRATAMENTO E DISTRIBUIÇÃO DE ÁGUA
3701100	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	ESGOTO E ATIVIDADES RELACIONADAS	ESGOTO E ATIVIDADES RELACIONADAS	GESTÃO DE REDES DE ESGOTO
3702900	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	ESGOTO E ATIVIDADES RELACIONADAS	ESGOTO E ATIVIDADES RELACIONADAS	ATIVIDADES RELACIONADAS A ESGOTO, EXCETO A GESTÃO DE REDES
5091201	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	OUTROS TRANSPORTES AQUAVIÁRIOS	TRANSPORTE POR NAVEGAÇÃO DE TRAVESSIA
3811400	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS	COLETA DE RESÍDUOS	COLETA DE RESÍDUOS NÃO-PERIGOSOS
3812200	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS	COLETA DE RESÍDUOS	COLETA DE RESÍDUOS PERIGOSOS
3821100	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS	TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS	TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS NÃO-PERIGOSOS
3822000	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS	TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS	TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS PERIGOSOS
3831901	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS METÁLICOS
3831999	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS METÁLICOS
3832700	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS PLÁSTICOS
3839401	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS NÃO ESPECIFICADOS ANTERIORMENTE
3839499	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS	RECUPERAÇÃO DE MATERIAIS NÃO ESPECIFICADOS ANTERIORMENTE
3900500	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO	DESCONTAMINAÇÃO E OUTROS SERVIÇOS DE GESTÃO DE RESÍDUOS	DESCONTAMINAÇÃO E OUTROS SERVIÇOS DE GESTÃO DE RESÍDUOS	DESCONTAMINAÇÃO E OUTROS SERVIÇOS DE GESTÃO DE RESÍDUOS
4110700	CONSTRUÇÃO	CONSTRUÇÃO DE EDIFÍCIOS	INCORPORAÇÃO DE EMPREENDIMENTOS IMOBILIÁRIOS	INCORPORAÇÃO DE EMPREENDIMENTOS IMOBILIÁRIOS
4120400	CONSTRUÇÃO	CONSTRUÇÃO DE EDIFÍCIOS	CONSTRUÇÃO DE EDIFÍCIOS	CONSTRUÇÃO DE EDIFÍCIOS
4211101	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	CONSTRUÇÃO DE RODOVIAS, FERROVIAS, OBRAS URBANAS E OBRAS-DE-ARTE ESPECIAIS	CONSTRUÇÃO DE RODOVIAS E FERROVIAS
4211102	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	CONSTRUÇÃO DE RODOVIAS, FERROVIAS, OBRAS URBANAS E OBRAS-DE-ARTE ESPECIAIS	CONSTRUÇÃO DE RODOVIAS E FERROVIAS
4212000	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	CONSTRUÇÃO DE RODOVIAS, FERROVIAS, OBRAS URBANAS E OBRAS-DE-ARTE ESPECIAIS	CONSTRUÇÃO DE OBRAS-DE-ARTE ESPECIAIS
4213800	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	CONSTRUÇÃO DE RODOVIAS, FERROVIAS, OBRAS URBANAS E OBRAS-DE-ARTE ESPECIAIS	OBRAS DE URBANIZAÇÃO - RUAS, PRAÇAS E CALÇADAS
4221901	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	OBRAS DE INFRA-ESTRUTURA PARA ENERGIA ELÉTRICA, TELECOMUNICAÇÕES, ÁGUA, ESGOTO E TRANSPORTE POR DUTOS	OBRAS PARA GERAÇÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA E PARA TELECOMUNICAÇÕES
4221902	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	OBRAS DE INFRA-ESTRUTURA PARA ENERGIA ELÉTRICA, TELECOMUNICAÇÕES, ÁGUA, ESGOTO E TRANSPORTE POR DUTOS	OBRAS PARA GERAÇÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA E PARA TELECOMUNICAÇÕES
4221903	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	OBRAS DE INFRA-ESTRUTURA PARA ENERGIA ELÉTRICA, TELECOMUNICAÇÕES, ÁGUA, ESGOTO E TRANSPORTE POR DUTOS	OBRAS PARA GERAÇÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA E PARA TELECOMUNICAÇÕES
4221904	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	OBRAS DE INFRA-ESTRUTURA PARA ENERGIA ELÉTRICA, TELECOMUNICAÇÕES, ÁGUA, ESGOTO E TRANSPORTE POR DUTOS	OBRAS PARA GERAÇÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA E PARA TELECOMUNICAÇÕES
4221905	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	OBRAS DE INFRA-ESTRUTURA PARA ENERGIA ELÉTRICA, TELECOMUNICAÇÕES, ÁGUA, ESGOTO E TRANSPORTE POR DUTOS	OBRAS PARA GERAÇÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA E PARA TELECOMUNICAÇÕES
4222701	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	OBRAS DE INFRA-ESTRUTURA PARA ENERGIA ELÉTRICA, TELECOMUNICAÇÕES, ÁGUA, ESGOTO E TRANSPORTE POR DUTOS	CONSTRUÇÃO DE REDES DE ABASTECIMENTO DE ÁGUA, COLETA DE ESGOTO E CONSTRUÇÕES CORRELATAS
4222702	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	OBRAS DE INFRA-ESTRUTURA PARA ENERGIA ELÉTRICA, TELECOMUNICAÇÕES, ÁGUA, ESGOTO E TRANSPORTE POR DUTOS	CONSTRUÇÃO DE REDES DE ABASTECIMENTO DE ÁGUA, COLETA DE ESGOTO E CONSTRUÇÕES CORRELATAS
4223500	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	OBRAS DE INFRA-ESTRUTURA PARA ENERGIA ELÉTRICA, TELECOMUNICAÇÕES, ÁGUA, ESGOTO E TRANSPORTE POR DUTOS	CONSTRUÇÃO DE REDES DE TRANSPORTES POR DUTOS, EXCETO PARA ÁGUA E ESGOTO
4291000	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	CONSTRUÇÃO DE OUTRAS OBRAS DE INFRA-ESTRUTURA	OBRAS PORTUÁRIAS, MARÍTIMAS E FLUVIAIS
4292801	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	CONSTRUÇÃO DE OUTRAS OBRAS DE INFRA-ESTRUTURA	MONTAGEM DE INSTALAÇÕES INDUSTRIAIS E DE ESTRUTURAS METÁLICAS
4292802	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	CONSTRUÇÃO DE OUTRAS OBRAS DE INFRA-ESTRUTURA	MONTAGEM DE INSTALAÇÕES INDUSTRIAIS E DE ESTRUTURAS METÁLICAS
4299501	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	CONSTRUÇÃO DE OUTRAS OBRAS DE INFRA-ESTRUTURA	OBRAS DE ENGENHARIA CIVIL NÃO ESPECIFICADAS ANTERIORMENTE
4299599	CONSTRUÇÃO	OBRAS DE INFRA-ESTRUTURA	CONSTRUÇÃO DE OUTRAS OBRAS DE INFRA-ESTRUTURA	OBRAS DE ENGENHARIA CIVIL NÃO ESPECIFICADAS ANTERIORMENTE
4311801	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	DEMOLIÇÃO E PREPARAÇÃO DO TERRENO	DEMOLIÇÃO E PREPARAÇÃO DE CANTEIROS DE OBRAS
4311802	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	DEMOLIÇÃO E PREPARAÇÃO DO TERRENO	DEMOLIÇÃO E PREPARAÇÃO DE CANTEIROS DE OBRAS
4312600	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	DEMOLIÇÃO E PREPARAÇÃO DO TERRENO	PERFURAÇÕES E SONDAGENS
4313400	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	DEMOLIÇÃO E PREPARAÇÃO DO TERRENO	OBRAS DE TERRAPLENAGEM
4319300	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	DEMOLIÇÃO E PREPARAÇÃO DO TERRENO	SERVIÇOS DE PREPARAÇÃO DO TERRENO NÃO ESPECIFICADOS ANTERIORMENTE
4321500	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	INSTALAÇÕES ELÉTRICAS
4322301	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	INSTALAÇÕES HIDRÁULICAS, DE SISTEMAS DE VENTILAÇÃO E REFRIGERAÇÃO
4322302	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	INSTALAÇÕES HIDRÁULICAS, DE SISTEMAS DE VENTILAÇÃO E REFRIGERAÇÃO
4322303	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	INSTALAÇÕES HIDRÁULICAS, DE SISTEMAS DE VENTILAÇÃO E REFRIGERAÇÃO
4329101	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	OBRAS DE INSTALAÇÕES EM CONSTRUÇÕES NÃO ESPECIFICADAS ANTERIORMENTE
4329102	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	OBRAS DE INSTALAÇÕES EM CONSTRUÇÕES NÃO ESPECIFICADAS ANTERIORMENTE
4329103	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	OBRAS DE INSTALAÇÕES EM CONSTRUÇÕES NÃO ESPECIFICADAS ANTERIORMENTE
4329104	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	OBRAS DE INSTALAÇÕES EM CONSTRUÇÕES NÃO ESPECIFICADAS ANTERIORMENTE
4329105	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	OBRAS DE INSTALAÇÕES EM CONSTRUÇÕES NÃO ESPECIFICADAS ANTERIORMENTE
4329199	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES	OBRAS DE INSTALAÇÕES EM CONSTRUÇÕES NÃO ESPECIFICADAS ANTERIORMENTE
4330401	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OBRAS DE ACABAMENTO	OBRAS DE ACABAMENTO
4330402	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OBRAS DE ACABAMENTO	OBRAS DE ACABAMENTO
4330403	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OBRAS DE ACABAMENTO	OBRAS DE ACABAMENTO
4330404	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OBRAS DE ACABAMENTO	OBRAS DE ACABAMENTO
4330405	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OBRAS DE ACABAMENTO	OBRAS DE ACABAMENTO
4330499	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OBRAS DE ACABAMENTO	OBRAS DE ACABAMENTO
4391600	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OUTROS SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OBRAS DE FUNDAÇÕES
4399101	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OUTROS SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE
4399102	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OUTROS SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE
4399103	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OUTROS SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE
4399104	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OUTROS SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE
4399105	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OUTROS SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE
4399199	CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	OUTROS SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE
4511101	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE VEÍCULOS AUTOMOTORES	COMÉRCIO A VAREJO E POR ATACADO DE VEÍCULOS AUTOMOTORES
4511102	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE VEÍCULOS AUTOMOTORES	COMÉRCIO A VAREJO E POR ATACADO DE VEÍCULOS AUTOMOTORES
4511103	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE VEÍCULOS AUTOMOTORES	COMÉRCIO A VAREJO E POR ATACADO DE VEÍCULOS AUTOMOTORES
4511104	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE VEÍCULOS AUTOMOTORES	COMÉRCIO A VAREJO E POR ATACADO DE VEÍCULOS AUTOMOTORES
4511105	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE VEÍCULOS AUTOMOTORES	COMÉRCIO A VAREJO E POR ATACADO DE VEÍCULOS AUTOMOTORES
4511106	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE VEÍCULOS AUTOMOTORES	COMÉRCIO A VAREJO E POR ATACADO DE VEÍCULOS AUTOMOTORES
4512901	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE VEÍCULOS AUTOMOTORES	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE VEÍCULOS AUTOMOTORES
4512902	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE VEÍCULOS AUTOMOTORES	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE VEÍCULOS AUTOMOTORES
4520001	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES
4520002	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES
4520003	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES
4520004	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES
4520005	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES
4520006	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES
5091202	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	OUTROS TRANSPORTES AQUAVIÁRIOS	TRANSPORTE POR NAVEGAÇÃO DE TRAVESSIA
4520007	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES
4520008	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES
4530701	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES
4530702	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES
4530703	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES
4530704	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES
4530705	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES
4530706	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES
4541201	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS	COMÉRCIO POR ATACADO E A VAREJO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
4541202	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS	COMÉRCIO POR ATACADO E A VAREJO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
4541203	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS	COMÉRCIO POR ATACADO E A VAREJO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
4541204	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS	COMÉRCIO POR ATACADO E A VAREJO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
4541206	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS	COMÉRCIO POR ATACADO E A VAREJO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
4541207	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS	COMÉRCIO POR ATACADO E A VAREJO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
4542101	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
4542102	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
4543900	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS	MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS
4611700	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS
4612500	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE COMBUSTÍVEIS, MINERAIS, PRODUTOS SIDERÚRGICOS E QUÍMICOS
4613300	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MADEIRA, MATERIAL DE CONSTRUÇÃO E FERRAGENS
4614100	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MÁQUINAS, EQUIPAMENTOS, EMBARCAÇÕES E AERONAVES
4615000	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE ELETRODOMÉSTICOS, MÓVEIS E ARTIGOS DE USO DOMÉSTICO
4616800	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE TÊXTEIS, VESTUÁRIO, CALÇADOS E ARTIGOS DE VIAGEM
4617600	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO
4618401	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO ESPECIALIZADO EM PRODUTOS NÃO ESPECIFICADOS ANTERIORMENTE
4618402	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO ESPECIALIZADO EM PRODUTOS NÃO ESPECIFICADOS ANTERIORMENTE
4618403	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO ESPECIALIZADO EM PRODUTOS NÃO ESPECIFICADOS ANTERIORMENTE
4618499	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO ESPECIALIZADO EM PRODUTOS NÃO ESPECIFICADOS ANTERIORMENTE
4619200	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MERCADORIAS EM GERAL NÃO ESPECIALIZADO
4621400	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE CAFÉ EM GRÃO
4622200	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE SOJA
4623101	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
4623102	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
4623103	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
4623104	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
4623105	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
4623106	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
4623107	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
4623108	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
4623109	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
4623199	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
4631100	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE LEITE E LATICÍNIOS
4632001	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE CEREAIS E LEGUMINOSAS BENEFICIADOS, FARINHAS, AMIDOS E FÉCULAS
4632002	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE CEREAIS E LEGUMINOSAS BENEFICIADOS, FARINHAS, AMIDOS E FÉCULAS
4632003	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE CEREAIS E LEGUMINOSAS BENEFICIADOS, FARINHAS, AMIDOS E FÉCULAS
4633801	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE HORTIFRUTIGRANJEIROS
4633802	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE HORTIFRUTIGRANJEIROS
4633803	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE HORTIFRUTIGRANJEIROS
4634601	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE CARNES, PRODUTOS DA CARNE E PESCADO
5099801	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	OUTROS TRANSPORTES AQUAVIÁRIOS	TRANSPORTES AQUAVIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
4634602	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE CARNES, PRODUTOS DA CARNE E PESCADO
4634603	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE CARNES, PRODUTOS DA CARNE E PESCADO
4634699	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE CARNES, PRODUTOS DA CARNE E PESCADO
4635401	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE BEBIDAS
4635402	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE BEBIDAS
4635403	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE BEBIDAS
4635499	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE BEBIDAS
4636201	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE PRODUTOS DO FUMO
4636202	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE PRODUTOS DO FUMO
4637101	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
4637102	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
4637103	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
4637104	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
4637105	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
4637106	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
4637107	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
4637199	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
4639701	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE PRODUTOS ALIMENTÍCIOS EM GERAL
4639702	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO ATACADISTA DE PRODUTOS ALIMENTÍCIOS EM GERAL
4641901	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE TECIDOS, ARTEFATOS DE TECIDOS E DE ARMARINHO
4641902	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE TECIDOS, ARTEFATOS DE TECIDOS E DE ARMARINHO
4641903	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE TECIDOS, ARTEFATOS DE TECIDOS E DE ARMARINHO
4642701	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS
4642702	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS
4643501	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE CALÇADOS E ARTIGOS DE VIAGEM
4643502	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE CALÇADOS E ARTIGOS DE VIAGEM
5099899	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	OUTROS TRANSPORTES AQUAVIÁRIOS	TRANSPORTES AQUAVIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
4644301	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE PRODUTOS FARMACÊUTICOS PARA USO HUMANO E VETERINÁRIO
4644302	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE PRODUTOS FARMACÊUTICOS PARA USO HUMANO E VETERINÁRIO
4645101	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO, CIRÚRGICO, ORTOPÉDICO E ODONTOLÓGICO
4645102	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO, CIRÚRGICO, ORTOPÉDICO E ODONTOLÓGICO
4645103	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO, CIRÚRGICO, ORTOPÉDICO E ODONTOLÓGICO
4646001	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL
4646002	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL
4647801	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE ARTIGOS DE ESCRITÓRIO E DE PAPELARIA; LIVROS, JORNAIS E OUTRAS PUBLICAÇÕES
4647802	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE ARTIGOS DE ESCRITÓRIO E DE PAPELARIA; LIVROS, JORNAIS E OUTRAS PUBLICAÇÕES
4649401	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
4649402	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
4649403	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
4649404	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
4649405	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
4649406	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
4649407	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
4649408	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
4649409	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
4649410	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
4649499	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
4651601	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E PRODUTOS DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE COMPUTADORES, PERIFÉRICOS E SUPRIMENTOS DE INFORMÁTICA
4651602	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E PRODUTOS DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE COMPUTADORES, PERIFÉRICOS E SUPRIMENTOS DE INFORMÁTICA
4652400	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E PRODUTOS DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE COMPONENTES ELETRÔNICOS E EQUIPAMENTOS DE TELEFONIA E COMUNICAÇÃO
4661300	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS, EXCETO DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS PARA USO AGROPECUÁRIO; PARTES E PEÇAS
4662100	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS, EXCETO DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE MÁQUINAS, EQUIPAMENTOS PARA TERRAPLENAGEM, MINERAÇÃO E CONSTRUÇÃO; PARTES E PEÇAS
4663000	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS, EXCETO DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE MÁQUINAS E EQUIPAMENTOS PARA USO INDUSTRIAL; PARTES E PEÇAS
4664800	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS, EXCETO DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS PARA USO ODONTO-MÉDICO-HOSPITALAR; PARTES E PEÇAS
4665600	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS, EXCETO DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE MÁQUINAS E EQUIPAMENTOS PARA USO COMERCIAL; PARTES E PEÇAS
4669901	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS, EXCETO DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE; PARTES E PEÇAS
4669999	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS, EXCETO DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE; PARTES E PEÇAS
4671100	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO	COMÉRCIO ATACADISTA DE MADEIRA E PRODUTOS DERIVADOS
4672900	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO	COMÉRCIO ATACADISTA DE FERRAGENS E FERRAMENTAS
4673700	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO	COMÉRCIO ATACADISTA DE MATERIAL ELÉTRICO
4674500	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO	COMÉRCIO ATACADISTA DE CIMENTO
4679601	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO	COMÉRCIO ATACADISTA ESPECIALIZADO DE MATERIAIS DE CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE E DE MATERIAIS DE CONSTRUÇÃO EM GERAL
4679602	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO	COMÉRCIO ATACADISTA ESPECIALIZADO DE MATERIAIS DE CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE E DE MATERIAIS DE CONSTRUÇÃO EM GERAL
4679603	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO	COMÉRCIO ATACADISTA ESPECIALIZADO DE MATERIAIS DE CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE E DE MATERIAIS DE CONSTRUÇÃO EM GERAL
4679604	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO	COMÉRCIO ATACADISTA ESPECIALIZADO DE MATERIAIS DE CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE E DE MATERIAIS DE CONSTRUÇÃO EM GERAL
4679699	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO	COMÉRCIO ATACADISTA ESPECIALIZADO DE MATERIAIS DE CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE E DE MATERIAIS DE CONSTRUÇÃO EM GERAL
4681801	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE COMBUSTÍVEIS SÓLIDOS, LÍQUIDOS E GASOSOS, EXCETO GÁS NATURAL E GLP
4681802	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE COMBUSTÍVEIS SÓLIDOS, LÍQUIDOS E GASOSOS, EXCETO GÁS NATURAL E GLP
4681803	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE COMBUSTÍVEIS SÓLIDOS, LÍQUIDOS E GASOSOS, EXCETO GÁS NATURAL E GLP
4681804	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE COMBUSTÍVEIS SÓLIDOS, LÍQUIDOS E GASOSOS, EXCETO GÁS NATURAL E GLP
4681805	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE COMBUSTÍVEIS SÓLIDOS, LÍQUIDOS E GASOSOS, EXCETO GÁS NATURAL E GLP
4682600	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE GÁS LIQUEFEITO DE PETRÓLEO (GLP)
4683400	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE DEFENSIVOS AGRÍCOLAS, ADUBOS, FERTILIZANTES E CORRETIVOS DO SOLO
4684201	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE PRODUTOS QUÍMICOS E PETROQUÍMICOS, EXCETO AGROQUÍMICOS
4684202	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE PRODUTOS QUÍMICOS E PETROQUÍMICOS, EXCETO AGROQUÍMICOS
4684299	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE PRODUTOS QUÍMICOS E PETROQUÍMICOS, EXCETO AGROQUÍMICOS
4685100	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE PRODUTOS SIDERÚRGICOS E METALÚRGICOS, EXCETO PARA CONSTRUÇÃO
4686901	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE PAPEL E PAPELÃO EM BRUTO E DE EMBALAGENS
4686902	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE PAPEL E PAPELÃO EM BRUTO E DE EMBALAGENS
4687701	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE RESÍDUOS E SUCATAS
4687702	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE RESÍDUOS E SUCATAS
4687703	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA DE RESÍDUOS E SUCATAS
4689301	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA ESPECIALIZADO DE OUTROS PRODUTOS INTERMEDIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
4689302	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA ESPECIALIZADO DE OUTROS PRODUTOS INTERMEDIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
4689399	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS	COMÉRCIO ATACADISTA ESPECIALIZADO DE OUTROS PRODUTOS INTERMEDIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
4691500	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA NÃO-ESPECIALIZADO	COMÉRCIO ATACADISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS
4692300	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA NÃO-ESPECIALIZADO	COMÉRCIO ATACADISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE INSUMOS AGROPECUÁRIOS
4693100	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO ATACADISTA NÃO-ESPECIALIZADO	COMÉRCIO ATACADISTA DE MERCADORIAS EM GERAL, SEM PREDOMINÂNCIA DE ALIMENTOS OU DE INSUMOS AGROPECUÁRIOS
4711301	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA NÃO-ESPECIALIZADO	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS - HIPERMERCADOS E SUPERMERCADOS
4711302	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA NÃO-ESPECIALIZADO	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS - HIPERMERCADOS E SUPERMERCADOS
4712100	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA NÃO-ESPECIALIZADO	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS - MINIMERCADOS, MERCEARIAS E ARMAZÉNS
4713002	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA NÃO-ESPECIALIZADO	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, SEM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS
4713004	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA NÃO-ESPECIALIZADO	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, SEM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS
4713005	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA NÃO-ESPECIALIZADO	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, SEM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS
4721102	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE PRODUTOS DE PADARIA, LATICÍNIO, DOCES, BALAS E SEMELHANTES
4721103	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE PRODUTOS DE PADARIA, LATICÍNIO, DOCES, BALAS E SEMELHANTES
4721104	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE PRODUTOS DE PADARIA, LATICÍNIO, DOCES, BALAS E SEMELHANTES
4722901	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE CARNES E PESCADOS - AÇOUGUES E PEIXARIAS
4722902	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE CARNES E PESCADOS - AÇOUGUES E PEIXARIAS
4723700	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE BEBIDAS
4724500	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE HORTIFRUTIGRANJEIROS
4729601	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS EM GERAL OU ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE; PRODUTOS DO FUMO
5111100	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AÉREO	TRANSPORTE AÉREO DE PASSAGEIROS	TRANSPORTE AÉREO DE PASSAGEIROS REGULAR
4729602	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS EM GERAL OU ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE; PRODUTOS DO FUMO
4729699	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS EM GERAL OU ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE; PRODUTOS DO FUMO
4731800	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE COMBUSTÍVEIS PARA VEÍCULOS AUTOMOTORES	COMÉRCIO VAREJISTA DE COMBUSTÍVEIS PARA VEÍCULOS AUTOMOTORES
4732600	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE COMBUSTÍVEIS PARA VEÍCULOS AUTOMOTORES	COMÉRCIO VAREJISTA DE LUBRIFICANTES
4741500	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE TINTAS E MATERIAIS PARA PINTURA
4742300	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE MATERIAL ELÉTRICO
4743100	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE VIDROS
4744001	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE FERRAGENS, MADEIRA E MATERIAIS DE CONSTRUÇÃO
4744002	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE FERRAGENS, MADEIRA E MATERIAIS DE CONSTRUÇÃO
4744003	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE FERRAGENS, MADEIRA E MATERIAIS DE CONSTRUÇÃO
4744004	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE FERRAGENS, MADEIRA E MATERIAIS DE CONSTRUÇÃO
4744005	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE FERRAGENS, MADEIRA E MATERIAIS DE CONSTRUÇÃO
4744006	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE FERRAGENS, MADEIRA E MATERIAIS DE CONSTRUÇÃO
4744099	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO	COMÉRCIO VAREJISTA DE FERRAGENS, MADEIRA E MATERIAIS DE CONSTRUÇÃO
4751201	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE EQUIPAMENTOS E SUPRIMENTOS DE INFORMÁTICA
4751202	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE EQUIPAMENTOS E SUPRIMENTOS DE INFORMÁTICA
4752100	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE EQUIPAMENTOS DE TELEFONIA E COMUNICAÇÃO
4753900	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE ELETRODOMÉSTICOS E EQUIPAMENTOS DE ÁUDIO E VÍDEO
4754701	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE MÓVEIS, COLCHOARIA E ARTIGOS DE ILUMINAÇÃO
4754702	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE MÓVEIS, COLCHOARIA E ARTIGOS DE ILUMINAÇÃO
4754703	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE MÓVEIS, COLCHOARIA E ARTIGOS DE ILUMINAÇÃO
4755501	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE TECIDOS E ARTIGOS DE CAMA, MESA E BANHO
4755502	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE TECIDOS E ARTIGOS DE CAMA, MESA E BANHO
4755503	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE TECIDOS E ARTIGOS DE CAMA, MESA E BANHO
4756300	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE INSTRUMENTOS MUSICAIS E ACESSÓRIOS
4757100	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA ESPECIALIZADO DE PEÇAS E ACESSÓRIOS PARA APARELHOS ELETROELETRÔNICOS PARA USO DOMÉSTICO, EXCETO INFORMÁTICA E COMUNICAÇÃO
4759801	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA DE ARTIGOS DE USO DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
4759899	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO	COMÉRCIO VAREJISTA DE ARTIGOS DE USO DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
5112901	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AÉREO	TRANSPORTE AÉREO DE PASSAGEIROS	TRANSPORTE AÉREO DE PASSAGEIROS NÃO-REGULAR
4761001	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS	COMÉRCIO VAREJISTA DE LIVROS, JORNAIS, REVISTAS E PAPELARIA
4761002	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS	COMÉRCIO VAREJISTA DE LIVROS, JORNAIS, REVISTAS E PAPELARIA
4761003	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS	COMÉRCIO VAREJISTA DE LIVROS, JORNAIS, REVISTAS E PAPELARIA
4762800	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS	COMÉRCIO VAREJISTA DE DISCOS, CDS, DVDS E FITAS
4763601	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS	COMÉRCIO VAREJISTA DE ARTIGOS RECREATIVOS E ESPORTIVOS
4763602	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS	COMÉRCIO VAREJISTA DE ARTIGOS RECREATIVOS E ESPORTIVOS
4763603	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS	COMÉRCIO VAREJISTA DE ARTIGOS RECREATIVOS E ESPORTIVOS
4763604	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS	COMÉRCIO VAREJISTA DE ARTIGOS RECREATIVOS E ESPORTIVOS
4763605	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS	COMÉRCIO VAREJISTA DE ARTIGOS RECREATIVOS E ESPORTIVOS
4771701	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, PERFUMARIA E COSMÉTICOS E ARTIGOS MÉDICOS, ÓPTICOS E ORTOPÉDICOS	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS PARA USO HUMANO E VETERINÁRIO
4771702	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, PERFUMARIA E COSMÉTICOS E ARTIGOS MÉDICOS, ÓPTICOS E ORTOPÉDICOS	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS PARA USO HUMANO E VETERINÁRIO
4771703	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, PERFUMARIA E COSMÉTICOS E ARTIGOS MÉDICOS, ÓPTICOS E ORTOPÉDICOS	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS PARA USO HUMANO E VETERINÁRIO
4771704	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, PERFUMARIA E COSMÉTICOS E ARTIGOS MÉDICOS, ÓPTICOS E ORTOPÉDICOS	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS PARA USO HUMANO E VETERINÁRIO
4772500	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, PERFUMARIA E COSMÉTICOS E ARTIGOS MÉDICOS, ÓPTICOS E ORTOPÉDICOS	COMÉRCIO VAREJISTA DE COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL
4773300	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, PERFUMARIA E COSMÉTICOS E ARTIGOS MÉDICOS, ÓPTICOS E ORTOPÉDICOS	COMÉRCIO VAREJISTA DE ARTIGOS MÉDICOS E ORTOPÉDICOS
4774100	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, PERFUMARIA E COSMÉTICOS E ARTIGOS MÉDICOS, ÓPTICOS E ORTOPÉDICOS	COMÉRCIO VAREJISTA DE ARTIGOS DE ÓPTICA
4781400	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS
4782201	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE CALÇADOS E ARTIGOS DE VIAGEM
4782202	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE CALÇADOS E ARTIGOS DE VIAGEM
4783101	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE JÓIAS E RELÓGIOS
4783102	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE JÓIAS E RELÓGIOS
4784900	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE GÁS LIQUEFEITO DE PETRÓLEO (GLP)
4785701	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE ARTIGOS USADOS
4785799	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE ARTIGOS USADOS
4789001	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
4789002	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
4789003	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
4789004	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
4789005	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
5112999	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AÉREO	TRANSPORTE AÉREO DE PASSAGEIROS	TRANSPORTE AÉREO DE PASSAGEIROS NÃO-REGULAR
4789006	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
4789007	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
4789008	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
4789009	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
4789099	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS	COMÉRCIO VAREJISTA	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
4911600	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE FERROVIÁRIO E METROFERROVIÁRIO	TRANSPORTE FERROVIÁRIO DE CARGA
4912401	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE FERROVIÁRIO E METROFERROVIÁRIO	TRANSPORTE METROFERROVIÁRIO DE PASSAGEIROS
4912402	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE FERROVIÁRIO E METROFERROVIÁRIO	TRANSPORTE METROFERROVIÁRIO DE PASSAGEIROS
4912403	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE FERROVIÁRIO E METROFERROVIÁRIO	TRANSPORTE METROFERROVIÁRIO DE PASSAGEIROS
4921301	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, MUNICIPAL E EM REGIÃO METROPOLITANA
4921302	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, MUNICIPAL E EM REGIÃO METROPOLITANA
4922101	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL
4922102	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL
4922103	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL
4923001	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO DE TÁXI
4923002	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO DE TÁXI
4924800	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE ESCOLAR
4929901	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, SOB REGIME DE FRETAMENTO, E OUTROS TRANSPORTES RODOVIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
4929902	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, SOB REGIME DE FRETAMENTO, E OUTROS TRANSPORTES RODOVIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
4929903	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, SOB REGIME DE FRETAMENTO, E OUTROS TRANSPORTES RODOVIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
4929904	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, SOB REGIME DE FRETAMENTO, E OUTROS TRANSPORTES RODOVIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
4929999	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, SOB REGIME DE FRETAMENTO, E OUTROS TRANSPORTES RODOVIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
4930201	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE CARGA	TRANSPORTE RODOVIÁRIO DE CARGA
4930202	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE CARGA	TRANSPORTE RODOVIÁRIO DE CARGA
4930203	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE CARGA	TRANSPORTE RODOVIÁRIO DE CARGA
4930204	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE RODOVIÁRIO DE CARGA	TRANSPORTE RODOVIÁRIO DE CARGA
4940000	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRANSPORTE DUTOVIÁRIO	TRANSPORTE DUTOVIÁRIO
4950700	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE TERRESTRE	TRENS TURÍSTICOS, TELEFÉRICOS E SIMILARES	TRENS TURÍSTICOS, TELEFÉRICOS E SIMILARES
5011401	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	TRANSPORTE MARÍTIMO DE CABOTAGEM E LONGO CURSO	TRANSPORTE MARÍTIMO DE CABOTAGEM
5011402	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	TRANSPORTE MARÍTIMO DE CABOTAGEM E LONGO CURSO	TRANSPORTE MARÍTIMO DE CABOTAGEM
5012201	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	TRANSPORTE MARÍTIMO DE CABOTAGEM E LONGO CURSO	TRANSPORTE MARÍTIMO DE LONGO CURSO
5012202	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	TRANSPORTE MARÍTIMO DE CABOTAGEM E LONGO CURSO	TRANSPORTE MARÍTIMO DE LONGO CURSO
5021101	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	TRANSPORTE POR NAVEGAÇÃO INTERIOR	TRANSPORTE POR NAVEGAÇÃO INTERIOR DE CARGA
5021102	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	TRANSPORTE POR NAVEGAÇÃO INTERIOR	TRANSPORTE POR NAVEGAÇÃO INTERIOR DE CARGA
5022001	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	TRANSPORTE POR NAVEGAÇÃO INTERIOR	TRANSPORTE POR NAVEGAÇÃO INTERIOR DE PASSAGEIROS EM LINHAS REGULARES
5022002	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	TRANSPORTE POR NAVEGAÇÃO INTERIOR	TRANSPORTE POR NAVEGAÇÃO INTERIOR DE PASSAGEIROS EM LINHAS REGULARES
5030101	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	NAVEGAÇÃO DE APOIO	NAVEGAÇÃO DE APOIO
5030102	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	NAVEGAÇÃO DE APOIO	NAVEGAÇÃO DE APOIO
5030103	TRANSPORTE, ARMAZENAGEM E CORREIO	TRANSPORTE AQUAVIÁRIO	NAVEGAÇÃO DE APOIO	NAVEGAÇÃO DE APOIO
5211701	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ARMAZENAMENTO, CARGA E DESCARGA	ARMAZENAMENTO
5211702	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ARMAZENAMENTO, CARGA E DESCARGA	ARMAZENAMENTO
5211799	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ARMAZENAMENTO, CARGA E DESCARGA	ARMAZENAMENTO
5212500	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ARMAZENAMENTO, CARGA E DESCARGA	CARGA E DESCARGA
5221400	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES	CONCESSIONÁRIAS DE RODOVIAS, PONTES, TÚNEIS E SERVIÇOS RELACIONADOS
5222200	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES	TERMINAIS RODOVIÁRIOS E FERROVIÁRIOS
5223100	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES	ESTACIONAMENTO DE VEÍCULOS
5229001	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES NÃO ESPECIFICADAS ANTERIORMENTE
5229002	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES NÃO ESPECIFICADAS ANTERIORMENTE
5229099	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES NÃO ESPECIFICADAS ANTERIORMENTE
5231101	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS	GESTÃO DE PORTOS E TERMINAIS
5231102	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS	GESTÃO DE PORTOS E TERMINAIS
5231103	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS	GESTÃO DE PORTOS E TERMINAIS
5232000	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS	ATIVIDADES DE AGENCIAMENTO MARÍTIMO
5239701	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS NÃO ESPECIFICADAS ANTERIORMENTE
5239799	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS NÃO ESPECIFICADAS ANTERIORMENTE
5240101	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES AÉREOS	ATIVIDADES AUXILIARES DOS TRANSPORTES AÉREOS
5240199	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES AUXILIARES DOS TRANSPORTES AÉREOS	ATIVIDADES AUXILIARES DOS TRANSPORTES AÉREOS
5250801	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA
5250802	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA
5250803	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA
5250804	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA
5250805	TRANSPORTE, ARMAZENAGEM E CORREIO	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA
5310501	TRANSPORTE, ARMAZENAGEM E CORREIO	CORREIO E OUTRAS ATIVIDADES DE ENTREGA	ATIVIDADES DE CORREIO	ATIVIDADES DE CORREIO
5310502	TRANSPORTE, ARMAZENAGEM E CORREIO	CORREIO E OUTRAS ATIVIDADES DE ENTREGA	ATIVIDADES DE CORREIO	ATIVIDADES DE CORREIO
5320201	TRANSPORTE, ARMAZENAGEM E CORREIO	CORREIO E OUTRAS ATIVIDADES DE ENTREGA	ATIVIDADES DE MALOTE E DE ENTREGA	ATIVIDADES DE MALOTE E DE ENTREGA
5320202	TRANSPORTE, ARMAZENAGEM E CORREIO	CORREIO E OUTRAS ATIVIDADES DE ENTREGA	ATIVIDADES DE MALOTE E DE ENTREGA	ATIVIDADES DE MALOTE E DE ENTREGA
5510801	ALOJAMENTO E ALIMENTAÇÃO	ALOJAMENTO	HOTÉIS E SIMILARES	HOTÉIS E SIMILARES
5510802	ALOJAMENTO E ALIMENTAÇÃO	ALOJAMENTO	HOTÉIS E SIMILARES	HOTÉIS E SIMILARES
5510803	ALOJAMENTO E ALIMENTAÇÃO	ALOJAMENTO	HOTÉIS E SIMILARES	HOTÉIS E SIMILARES
5590601	ALOJAMENTO E ALIMENTAÇÃO	ALOJAMENTO	OUTROS TIPOS DE ALOJAMENTO NÃO ESPECIFICADOS ANTERIORMENTE	OUTROS TIPOS DE ALOJAMENTO NÃO ESPECIFICADOS ANTERIORMENTE
5590602	ALOJAMENTO E ALIMENTAÇÃO	ALOJAMENTO	OUTROS TIPOS DE ALOJAMENTO NÃO ESPECIFICADOS ANTERIORMENTE	OUTROS TIPOS DE ALOJAMENTO NÃO ESPECIFICADOS ANTERIORMENTE
5590603	ALOJAMENTO E ALIMENTAÇÃO	ALOJAMENTO	OUTROS TIPOS DE ALOJAMENTO NÃO ESPECIFICADOS ANTERIORMENTE	OUTROS TIPOS DE ALOJAMENTO NÃO ESPECIFICADOS ANTERIORMENTE
5590699	ALOJAMENTO E ALIMENTAÇÃO	ALOJAMENTO	OUTROS TIPOS DE ALOJAMENTO NÃO ESPECIFICADOS ANTERIORMENTE	OUTROS TIPOS DE ALOJAMENTO NÃO ESPECIFICADOS ANTERIORMENTE
5611201	ALOJAMENTO E ALIMENTAÇÃO	ALIMENTAÇÃO	RESTAURANTES E OUTROS SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS	RESTAURANTES E OUTROS ESTABELECIMENTOS DE SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS
5611203	ALOJAMENTO E ALIMENTAÇÃO	ALIMENTAÇÃO	RESTAURANTES E OUTROS SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS	RESTAURANTES E OUTROS ESTABELECIMENTOS DE SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS
5611204	ALOJAMENTO E ALIMENTAÇÃO	ALIMENTAÇÃO	RESTAURANTES E OUTROS SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS	RESTAURANTES E OUTROS ESTABELECIMENTOS DE SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS
5611205	ALOJAMENTO E ALIMENTAÇÃO	ALIMENTAÇÃO	RESTAURANTES E OUTROS SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS	RESTAURANTES E OUTROS ESTABELECIMENTOS DE SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS
5612100	ALOJAMENTO E ALIMENTAÇÃO	ALIMENTAÇÃO	RESTAURANTES E OUTROS SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS	SERVIÇOS AMBULANTES DE ALIMENTAÇÃO
5620101	ALOJAMENTO E ALIMENTAÇÃO	ALIMENTAÇÃO	SERVIÇOS DE CATERING, BUFÊ E OUTROS SERVIÇOS DE COMIDA PREPARADA	SERVIÇOS DE CATERING, BUFÊ E OUTROS SERVIÇOS DE COMIDA PREPARADA
5620102	ALOJAMENTO E ALIMENTAÇÃO	ALIMENTAÇÃO	SERVIÇOS DE CATERING, BUFÊ E OUTROS SERVIÇOS DE COMIDA PREPARADA	SERVIÇOS DE CATERING, BUFÊ E OUTROS SERVIÇOS DE COMIDA PREPARADA
5620103	ALOJAMENTO E ALIMENTAÇÃO	ALIMENTAÇÃO	SERVIÇOS DE CATERING, BUFÊ E OUTROS SERVIÇOS DE COMIDA PREPARADA	SERVIÇOS DE CATERING, BUFÊ E OUTROS SERVIÇOS DE COMIDA PREPARADA
5620104	ALOJAMENTO E ALIMENTAÇÃO	ALIMENTAÇÃO	SERVIÇOS DE CATERING, BUFÊ E OUTROS SERVIÇOS DE COMIDA PREPARADA	SERVIÇOS DE CATERING, BUFÊ E OUTROS SERVIÇOS DE COMIDA PREPARADA
5811500	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS ATIVIDADES DE EDIÇÃO	EDIÇÃO DE LIVROS
5812301	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS ATIVIDADES DE EDIÇÃO	EDIÇÃO DE JORNAIS
5812302	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS ATIVIDADES DE EDIÇÃO	EDIÇÃO DE JORNAIS
5813100	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS ATIVIDADES DE EDIÇÃO	EDIÇÃO DE REVISTAS
5819100	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS ATIVIDADES DE EDIÇÃO	EDIÇÃO DE CADASTROS, LISTAS E DE OUTROS PRODUTOS GRÁFICOS
5821200	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO INTEGRADA À IMPRESSÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS PUBLICAÇÕES	EDIÇÃO INTEGRADA À IMPRESSÃO DE LIVROS
5822101	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO INTEGRADA À IMPRESSÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS PUBLICAÇÕES	EDIÇÃO INTEGRADA À IMPRESSÃO DE JORNAIS
5822102	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO INTEGRADA À IMPRESSÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS PUBLICAÇÕES	EDIÇÃO INTEGRADA À IMPRESSÃO DE JORNAIS
5823900	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO INTEGRADA À IMPRESSÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS PUBLICAÇÕES	EDIÇÃO INTEGRADA À IMPRESSÃO DE REVISTAS
5829800	INFORMAÇÃO E COMUNICAÇÃO	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO	EDIÇÃO INTEGRADA À IMPRESSÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS PUBLICAÇÕES	EDIÇÃO INTEGRADA À IMPRESSÃO DE CADASTROS, LISTAS E DE OUTROS PRODUTOS GRÁFICOS
5911101	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO	ATIVIDADES DE PRODUÇÃO CINEMATOGRÁFICA, DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO
5911102	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO	ATIVIDADES DE PRODUÇÃO CINEMATOGRÁFICA, DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO
5911199	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO	ATIVIDADES DE PRODUÇÃO CINEMATOGRÁFICA, DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO
5912001	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO	ATIVIDADES DE PÓS-PRODUÇÃO CINEMATOGRÁFICA, DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO
5912002	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO	ATIVIDADES DE PÓS-PRODUÇÃO CINEMATOGRÁFICA, DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO
5912099	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO	ATIVIDADES DE PÓS-PRODUÇÃO CINEMATOGRÁFICA, DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO
5913800	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO	DISTRIBUIÇÃO CINEMATOGRÁFICA, DE VÍDEO E DE PROGRAMAS DE TELEVISÃO
5914600	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO	ATIVIDADES DE EXIBIÇÃO CINEMATOGRÁFICA
5920100	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA	ATIVIDADES DE GRAVAÇÃO DE SOM E DE EDIÇÃO DE MÚSICA	ATIVIDADES DE GRAVAÇÃO DE SOM E DE EDIÇÃO DE MÚSICA
6010100	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DE RÁDIO E DE TELEVISÃO	ATIVIDADES DE RÁDIO	ATIVIDADES DE RÁDIO
6021700	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DE RÁDIO E DE TELEVISÃO	ATIVIDADES DE TELEVISÃO	ATIVIDADES DE TELEVISÃO ABERTA
6022501	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DE RÁDIO E DE TELEVISÃO	ATIVIDADES DE TELEVISÃO	PROGRAMADORAS E ATIVIDADES RELACIONADAS À TELEVISÃO POR ASSINATURA
6022502	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DE RÁDIO E DE TELEVISÃO	ATIVIDADES DE TELEVISÃO	PROGRAMADORAS E ATIVIDADES RELACIONADAS À TELEVISÃO POR ASSINATURA
6110801	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	TELECOMUNICAÇÕES POR FIO	TELECOMUNICAÇÕES POR FIO
6110802	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	TELECOMUNICAÇÕES POR FIO	TELECOMUNICAÇÕES POR FIO
6110803	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	TELECOMUNICAÇÕES POR FIO	TELECOMUNICAÇÕES POR FIO
6110899	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	TELECOMUNICAÇÕES POR FIO	TELECOMUNICAÇÕES POR FIO
6120501	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	TELECOMUNICAÇÕES SEM FIO	TELECOMUNICAÇÕES SEM FIO
6120502	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	TELECOMUNICAÇÕES SEM FIO	TELECOMUNICAÇÕES SEM FIO
6120599	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	TELECOMUNICAÇÕES SEM FIO	TELECOMUNICAÇÕES SEM FIO
6130200	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	TELECOMUNICAÇÕES POR SATÉLITE	TELECOMUNICAÇÕES POR SATÉLITE
6141800	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	OPERADORAS DE TELEVISÃO POR ASSINATURA	OPERADORAS DE TELEVISÃO POR ASSINATURA POR CABO
6142600	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	OPERADORAS DE TELEVISÃO POR ASSINATURA	OPERADORAS DE TELEVISÃO POR ASSINATURA POR MICROONDAS
6143400	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	OPERADORAS DE TELEVISÃO POR ASSINATURA	OPERADORAS DE TELEVISÃO POR ASSINATURA POR SATÉLITE
6190601	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	OUTRAS ATIVIDADES DE TELECOMUNICAÇÕES	OUTRAS ATIVIDADES DE TELECOMUNICAÇÕES
6190602	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	OUTRAS ATIVIDADES DE TELECOMUNICAÇÕES	OUTRAS ATIVIDADES DE TELECOMUNICAÇÕES
6190699	INFORMAÇÃO E COMUNICAÇÃO	TELECOMUNICAÇÕES	OUTRAS ATIVIDADES DE TELECOMUNICAÇÕES	OUTRAS ATIVIDADES DE TELECOMUNICAÇÕES
6201501	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	DESENVOLVIMENTO DE PROGRAMAS DE COMPUTADOR SOB ENCOMENDA
6201502	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	DESENVOLVIMENTO DE PROGRAMAS DE COMPUTADOR SOB ENCOMENDA
6202300	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	DESENVOLVIMENTO E LICENCIAMENTO DE PROGRAMAS DE COMPUTADOR CUSTOMIZÁVEIS
6203100	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	DESENVOLVIMENTO E LICENCIAMENTO DE PROGRAMAS DE COMPUTADOR NÃO-CUSTOMIZÁVEIS
6204000	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	CONSULTORIA EM TECNOLOGIA DA INFORMAÇÃO
6209100	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO	SUPORTE TÉCNICO, MANUTENÇÃO E OUTROS SERVIÇOS EM TECNOLOGIA DA INFORMAÇÃO
6311900	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO	TRATAMENTO DE DADOS, HOSPEDAGEM NA INTERNET E OUTRAS ATIVIDADES RELACIONADAS	TRATAMENTO DE DADOS, PROVEDORES DE SERVIÇOS DE APLICAÇÃO E SERVIÇOS DE HOSPEDAGEM NA INTERNET
6319400	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO	TRATAMENTO DE DADOS, HOSPEDAGEM NA INTERNET E OUTRAS ATIVIDADES RELACIONADAS	PORTAIS, PROVEDORES DE CONTEÚDO E OUTROS SERVIÇOS DE INFORMAÇÃO NA INTERNET
6391700	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO	OUTRAS ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO	AGÊNCIAS DE NOTÍCIAS
6399200	INFORMAÇÃO E COMUNICAÇÃO	ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO	OUTRAS ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO	OUTRAS ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO NÃO ESPECIFICADAS ANTERIORMENTE
6410700	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	BANCO CENTRAL	BANCO CENTRAL
6421200	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO MONETÁRIA - DEPÓSITOS À VISTA	BANCOS COMERCIAIS
6422100	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO MONETÁRIA - DEPÓSITOS À VISTA	BANCOS MÚLTIPLOS, COM CARTEIRA COMERCIAL
6423900	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO MONETÁRIA - DEPÓSITOS À VISTA	CAIXAS ECONÔMICAS
6424701	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO MONETÁRIA - DEPÓSITOS À VISTA	CRÉDITO COOPERATIVO
6424702	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO MONETÁRIA - DEPÓSITOS À VISTA	CRÉDITO COOPERATIVO
6424703	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO MONETÁRIA - DEPÓSITOS À VISTA	CRÉDITO COOPERATIVO
6424704	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO MONETÁRIA - DEPÓSITOS À VISTA	CRÉDITO COOPERATIVO
6431000	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	BANCOS MÚLTIPLOS, SEM CARTEIRA COMERCIAL
6432800	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	BANCOS DE INVESTIMENTO
6433600	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	BANCOS DE DESENVOLVIMENTO
6434400	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	AGÊNCIAS DE FOMENTO
6435201	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	CRÉDITO IMOBILIÁRIO
6435202	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	CRÉDITO IMOBILIÁRIO
6435203	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	CRÉDITO IMOBILIÁRIO
6436100	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	SOCIEDADES DE CRÉDITO, FINANCIAMENTO E INVESTIMENTO - FINANCEIRAS
6437900	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	SOCIEDADES DE CRÉDITO AO MICROEMPREENDEDOR
6438701	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	BANCOS DE CAMBIO E OUTRAS INSTITUIÇÕES DE INTERMEDIAÇÃO NÃO-MONETÁRIA
6438799	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO	BANCOS DE CAMBIO E OUTRAS INSTITUIÇÕES DE INTERMEDIAÇÃO NÃO-MONETÁRIA
6440900	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ARRENDAMENTO MERCANTIL	ARRENDAMENTO MERCANTIL
6450600	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	SOCIEDADES DE CAPITALIZAÇÃO	SOCIEDADES DE CAPITALIZAÇÃO
6461100	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SOCIEDADES DE PARTICIPAÇÃO	HOLDINGS DE INSTITUIÇÕES FINANCEIRAS
6462000	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SOCIEDADES DE PARTICIPAÇÃO	HOLDINGS DE INSTITUIÇÕES NÃO-FINANCEIRAS
6463800	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SOCIEDADES DE PARTICIPAÇÃO	OUTRAS SOCIEDADES DE PARTICIPAÇÃO, EXCETO HOLDINGS
6470101	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	FUNDOS DE INVESTIMENTO	FUNDOS DE INVESTIMENTO
6470102	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	FUNDOS DE INVESTIMENTO	FUNDOS DE INVESTIMENTO
6470103	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	FUNDOS DE INVESTIMENTO	FUNDOS DE INVESTIMENTO
6491300	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	SOCIEDADES DE FOMENTO MERCANTIL - FACTORING
6492100	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	SECURITIZAÇÃO DE CRÉDITOS
6493000	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	ADMINISTRAÇÃO DE CONSÓRCIOS PARA AQUISIÇÃO DE BENS E DIREITOS
6499901	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	OUTRAS ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
6499902	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	OUTRAS ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
6499903	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	OUTRAS ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
6499904	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	OUTRAS ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
6499905	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	OUTRAS ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
6499999	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES DE SERVIÇOS FINANCEIROS	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE	OUTRAS ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
6511101	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	SEGUROS, RESSEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	SEGUROS DE VIDA E NÃO-VIDA	SEGUROS DE VIDA
6511102	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	SEGUROS, RESSEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	SEGUROS DE VIDA E NÃO-VIDA	SEGUROS DE VIDA
6512000	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	SEGUROS, RESSEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	SEGUROS DE VIDA E NÃO-VIDA	SEGUROS NÃO-VIDA
6520100	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	SEGUROS, RESSEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	SEGUROS-SAÚDE	SEGUROS-SAÚDE
6530800	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	SEGUROS, RESSEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	RESSEGUROS	RESSEGUROS
6541300	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	SEGUROS, RESSEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	PREVIDÊNCIA COMPLEMENTAR	PREVIDÊNCIA COMPLEMENTAR FECHADA
6542100	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	SEGUROS, RESSEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	PREVIDÊNCIA COMPLEMENTAR	PREVIDÊNCIA COMPLEMENTAR ABERTA
6550200	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	SEGUROS, RESSEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	PLANOS DE SAÚDE	PLANOS DE SAÚDE
6611801	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ADMINISTRAÇÃO DE BOLSAS E MERCADOS DE BALCÃO ORGANIZADOS
6611802	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ADMINISTRAÇÃO DE BOLSAS E MERCADOS DE BALCÃO ORGANIZADOS
6611803	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ADMINISTRAÇÃO DE BOLSAS E MERCADOS DE BALCÃO ORGANIZADOS
6611804	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ADMINISTRAÇÃO DE BOLSAS E MERCADOS DE BALCÃO ORGANIZADOS
6612601	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES DE INTERMEDIÁRIOS EM TRANSAÇÕES DE TÍTULOS, VALORES MOBILIÁRIOS E MERCADORIAS
6612602	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES DE INTERMEDIÁRIOS EM TRANSAÇÕES DE TÍTULOS, VALORES MOBILIÁRIOS E MERCADORIAS
6612603	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES DE INTERMEDIÁRIOS EM TRANSAÇÕES DE TÍTULOS, VALORES MOBILIÁRIOS E MERCADORIAS
6612604	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES DE INTERMEDIÁRIOS EM TRANSAÇÕES DE TÍTULOS, VALORES MOBILIÁRIOS E MERCADORIAS
6612605	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES DE INTERMEDIÁRIOS EM TRANSAÇÕES DE TÍTULOS, VALORES MOBILIÁRIOS E MERCADORIAS
6613400	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ADMINISTRAÇÃO DE CARTÕES DE CRÉDITO
6619301	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
6619302	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
6619303	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
6619304	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
6619305	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
6619399	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
6621501	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SEGUROS, DA PREVIDÊNCIA COMPLEMENTAR E DOS PLANOS DE SAÚDE	AVALIAÇÃO DE RISCOS E PERDAS
6621502	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SEGUROS, DA PREVIDÊNCIA COMPLEMENTAR E DOS PLANOS DE SAÚDE	AVALIAÇÃO DE RISCOS E PERDAS
6622300	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SEGUROS, DA PREVIDÊNCIA COMPLEMENTAR E DOS PLANOS DE SAÚDE	CORRETORES E AGENTES DE SEGUROS, DE PLANOS DE PREVIDÊNCIA COMPLEMENTAR E DE SAÚDE
6629100	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SEGUROS, DA PREVIDÊNCIA COMPLEMENTAR E DOS PLANOS DE SAÚDE	ATIVIDADES AUXILIARES DOS SEGUROS, DA PREVIDÊNCIA COMPLEMENTAR E DOS PLANOS DE SAÚDE NÃO ESPECIFICADAS ANTERIORMENTE
6630400	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE	ATIVIDADES DE ADMINISTRAÇÃO DE FUNDOS POR CONTRATO OU COMISSÃO	ATIVIDADES DE ADMINISTRAÇÃO DE FUNDOS POR CONTRATO OU COMISSÃO
6810201	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS DE IMÓVEIS PRÓPRIOS	ATIVIDADES IMOBILIÁRIAS DE IMÓVEIS PRÓPRIOS
6810202	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS DE IMÓVEIS PRÓPRIOS	ATIVIDADES IMOBILIÁRIAS DE IMÓVEIS PRÓPRIOS
6810203	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS DE IMÓVEIS PRÓPRIOS	ATIVIDADES IMOBILIÁRIAS DE IMÓVEIS PRÓPRIOS
6821801	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS POR CONTRATO OU COMISSÃO	INTERMEDIAÇÃO NA COMPRA, VENDA E ALUGUEL DE IMÓVEIS
6821802	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS POR CONTRATO OU COMISSÃO	INTERMEDIAÇÃO NA COMPRA, VENDA E ALUGUEL DE IMÓVEIS
6822600	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS	ATIVIDADES IMOBILIÁRIAS POR CONTRATO OU COMISSÃO	GESTÃO E ADMINISTRAÇÃO DA PROPRIEDADE IMOBILIÁRIA
6911701	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES JURÍDICAS, DE CONTABILIDADE E DE AUDITORIA	ATIVIDADES JURÍDICAS	ATIVIDADES JURÍDICAS, EXCETO CARTÓRIOS
6911702	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES JURÍDICAS, DE CONTABILIDADE E DE AUDITORIA	ATIVIDADES JURÍDICAS	ATIVIDADES JURÍDICAS, EXCETO CARTÓRIOS
6911703	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES JURÍDICAS, DE CONTABILIDADE E DE AUDITORIA	ATIVIDADES JURÍDICAS	ATIVIDADES JURÍDICAS, EXCETO CARTÓRIOS
6912500	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES JURÍDICAS, DE CONTABILIDADE E DE AUDITORIA	ATIVIDADES JURÍDICAS	CARTÓRIOS
6920601	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES JURÍDICAS, DE CONTABILIDADE E DE AUDITORIA	ATIVIDADES DE CONTABILIDADE, CONSULTORIA E AUDITORIA CONTÁBIL E TRIBUTÁRIA	ATIVIDADES DE CONTABILIDADE, CONSULTORIA E AUDITORIA CONTÁBIL E TRIBUTÁRIA
6920602	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES JURÍDICAS, DE CONTABILIDADE E DE AUDITORIA	ATIVIDADES DE CONTABILIDADE, CONSULTORIA E AUDITORIA CONTÁBIL E TRIBUTÁRIA	ATIVIDADES DE CONTABILIDADE, CONSULTORIA E AUDITORIA CONTÁBIL E TRIBUTÁRIA
7020400	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES DE SEDES DE EMPRESAS E DE CONSULTORIA EM GESTÃO EMPRESARIAL	ATIVIDADES DE CONSULTORIA EM GESTÃO EMPRESARIAL	ATIVIDADES DE CONSULTORIA EM GESTÃO EMPRESARIAL
7111100	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA; TESTES E ANÁLISES TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA E ATIVIDADES TÉCNICAS RELACIONADAS	SERVIÇOS DE ARQUITETURA
7112000	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA; TESTES E ANÁLISES TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA E ATIVIDADES TÉCNICAS RELACIONADAS	SERVIÇOS DE ENGENHARIA
7119701	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA; TESTES E ANÁLISES TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA E ATIVIDADES TÉCNICAS RELACIONADAS	ATIVIDADES TÉCNICAS RELACIONADAS À ARQUITETURA E ENGENHARIA
7119702	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA; TESTES E ANÁLISES TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA E ATIVIDADES TÉCNICAS RELACIONADAS	ATIVIDADES TÉCNICAS RELACIONADAS À ARQUITETURA E ENGENHARIA
7119703	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA; TESTES E ANÁLISES TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA E ATIVIDADES TÉCNICAS RELACIONADAS	ATIVIDADES TÉCNICAS RELACIONADAS À ARQUITETURA E ENGENHARIA
7119704	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA; TESTES E ANÁLISES TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA E ATIVIDADES TÉCNICAS RELACIONADAS	ATIVIDADES TÉCNICAS RELACIONADAS À ARQUITETURA E ENGENHARIA
7119799	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA; TESTES E ANÁLISES TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA E ATIVIDADES TÉCNICAS RELACIONADAS	ATIVIDADES TÉCNICAS RELACIONADAS À ARQUITETURA E ENGENHARIA
7120100	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	SERVIÇOS DE ARQUITETURA E ENGENHARIA; TESTES E ANÁLISES TÉCNICAS	TESTES E ANÁLISES TÉCNICAS	TESTES E ANÁLISES TÉCNICAS
7210000	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PESQUISA E DESENVOLVIMENTO CIENTÍFICO	PESQUISA E DESENVOLVIMENTO EXPERIMENTAL EM CIÊNCIAS FÍSICAS E NATURAIS	PESQUISA E DESENVOLVIMENTO EXPERIMENTAL EM CIÊNCIAS FÍSICAS E NATURAIS
7220700	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PESQUISA E DESENVOLVIMENTO CIENTÍFICO	PESQUISA E DESENVOLVIMENTO EXPERIMENTAL EM CIÊNCIAS SOCIAIS E HUMANAS	PESQUISA E DESENVOLVIMENTO EXPERIMENTAL EM CIÊNCIAS SOCIAIS E HUMANAS
7311400	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PUBLICIDADE E PESQUISA DE MERCADO	PUBLICIDADE	AGÊNCIAS DE PUBLICIDADE
7312200	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PUBLICIDADE E PESQUISA DE MERCADO	PUBLICIDADE	AGENCIAMENTO DE ESPAÇOS PARA PUBLICIDADE, EXCETO EM VEÍCULOS DE COMUNICAÇÃO
7319001	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PUBLICIDADE E PESQUISA DE MERCADO	PUBLICIDADE	ATIVIDADES DE PUBLICIDADE NÃO ESPECIFICADAS ANTERIORMENTE
7319002	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PUBLICIDADE E PESQUISA DE MERCADO	PUBLICIDADE	ATIVIDADES DE PUBLICIDADE NÃO ESPECIFICADAS ANTERIORMENTE
7319003	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PUBLICIDADE E PESQUISA DE MERCADO	PUBLICIDADE	ATIVIDADES DE PUBLICIDADE NÃO ESPECIFICADAS ANTERIORMENTE
7319004	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PUBLICIDADE E PESQUISA DE MERCADO	PUBLICIDADE	ATIVIDADES DE PUBLICIDADE NÃO ESPECIFICADAS ANTERIORMENTE
7319099	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PUBLICIDADE E PESQUISA DE MERCADO	PUBLICIDADE	ATIVIDADES DE PUBLICIDADE NÃO ESPECIFICADAS ANTERIORMENTE
7320300	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	PUBLICIDADE E PESQUISA DE MERCADO	PESQUISAS DE MERCADO E DE OPINIÃO PÚBLICA	PESQUISAS DE MERCADO E DE OPINIÃO PÚBLICA
7410202	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	DESIGN E DECORAÇÃO DE INTERIORES	DESIGN E DECORAÇÃO DE INTERIORES
7410203	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	DESIGN E DECORAÇÃO DE INTERIORES	DESIGN E DECORAÇÃO DE INTERIORES
7410299	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	DESIGN E DECORAÇÃO DE INTERIORES	DESIGN E DECORAÇÃO DE INTERIORES
7420001	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES FOTOGRÁFICAS E SIMILARES	ATIVIDADES FOTOGRÁFICAS E SIMILARES
7420002	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES FOTOGRÁFICAS E SIMILARES	ATIVIDADES FOTOGRÁFICAS E SIMILARES
7420003	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES FOTOGRÁFICAS E SIMILARES	ATIVIDADES FOTOGRÁFICAS E SIMILARES
7420004	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES FOTOGRÁFICAS E SIMILARES	ATIVIDADES FOTOGRÁFICAS E SIMILARES
7420005	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES FOTOGRÁFICAS E SIMILARES	ATIVIDADES FOTOGRÁFICAS E SIMILARES
7490101	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE
7490102	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE
7490103	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE
7490104	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE
7490105	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE
7490199	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE
7500100	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS	ATIVIDADES VETERINÁRIAS	ATIVIDADES VETERINÁRIAS	ATIVIDADES VETERINÁRIAS
7711000	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	LOCAÇÃO DE MEIOS DE TRANSPORTE SEM CONDUTOR	LOCAÇÃO DE AUTOMÓVEIS SEM CONDUTOR
7719501	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	LOCAÇÃO DE MEIOS DE TRANSPORTE SEM CONDUTOR	LOCAÇÃO DE MEIOS DE TRANSPORTE, EXCETO AUTOMÓVEIS, SEM CONDUTOR
7719502	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	LOCAÇÃO DE MEIOS DE TRANSPORTE SEM CONDUTOR	LOCAÇÃO DE MEIOS DE TRANSPORTE, EXCETO AUTOMÓVEIS, SEM CONDUTOR
7719599	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	LOCAÇÃO DE MEIOS DE TRANSPORTE SEM CONDUTOR	LOCAÇÃO DE MEIOS DE TRANSPORTE, EXCETO AUTOMÓVEIS, SEM CONDUTOR
7721700	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS	ALUGUEL DE EQUIPAMENTOS RECREATIVOS E ESPORTIVOS
7722500	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS	ALUGUEL DE FITAS DE VÍDEO, DVDS E SIMILARES
7723300	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS	ALUGUEL DE OBJETOS DO VESTUÁRIO, JÓIAS E ACESSÓRIOS
7729201	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
7729202	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
7729203	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
7729299	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
7731400	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS SEM OPERADOR	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS AGRÍCOLAS SEM OPERADOR
7732201	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS SEM OPERADOR	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS PARA CONSTRUÇÃO SEM OPERADOR
7732202	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS SEM OPERADOR	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS PARA CONSTRUÇÃO SEM OPERADOR
7733100	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS SEM OPERADOR	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS PARA ESCRITÓRIOS
7739001	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS SEM OPERADOR	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE
7739002	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS SEM OPERADOR	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE
7739003	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS SEM OPERADOR	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE
7739099	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS SEM OPERADOR	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE
7740300	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS	GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS
7810800	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SELEÇÃO, AGENCIAMENTO E LOCAÇÃO DE MÃO-DE-OBRA	SELEÇÃO E AGENCIAMENTO DE MÃO-DE-OBRA	SELEÇÃO E AGENCIAMENTO DE MÃO-DE-OBRA
7820500	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SELEÇÃO, AGENCIAMENTO E LOCAÇÃO DE MÃO-DE-OBRA	LOCAÇÃO DE MÃO-DE-OBRA TEMPORÁRIA	LOCAÇÃO DE MÃO-DE-OBRA TEMPORÁRIA
7830200	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SELEÇÃO, AGENCIAMENTO E LOCAÇÃO DE MÃO-DE-OBRA	FORNECIMENTO E GESTÃO DE RECURSOS HUMANOS PARA TERCEIROS	FORNECIMENTO E GESTÃO DE RECURSOS HUMANOS PARA TERCEIROS
7911200	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	AGÊNCIAS DE VIAGENS, OPERADORES TURÍSTICOS E SERVIÇOS DE RESERVAS	AGÊNCIAS DE VIAGENS E OPERADORES TURÍSTICOS	AGÊNCIAS DE VIAGENS
7912100	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	AGÊNCIAS DE VIAGENS, OPERADORES TURÍSTICOS E SERVIÇOS DE RESERVAS	AGÊNCIAS DE VIAGENS E OPERADORES TURÍSTICOS	OPERADORES TURÍSTICOS
7990200	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	AGÊNCIAS DE VIAGENS, OPERADORES TURÍSTICOS E SERVIÇOS DE RESERVAS	SERVIÇOS DE RESERVAS E OUTROS SERVIÇOS DE TURISMO NÃO ESPECIFICADOS ANTERIORMENTE	SERVIÇOS DE RESERVAS E OUTROS SERVIÇOS DE TURISMO NÃO ESPECIFICADOS ANTERIORMENTE
8011101	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA E INVESTIGAÇÃO	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA PRIVADA E TRANSPORTE DE VALORES	ATIVIDADES DE VIGILÂNCIA E SEGURANÇA PRIVADA
8011102	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA E INVESTIGAÇÃO	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA PRIVADA E TRANSPORTE DE VALORES	ATIVIDADES DE VIGILÂNCIA E SEGURANÇA PRIVADA
8012900	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA E INVESTIGAÇÃO	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA PRIVADA E TRANSPORTE DE VALORES	ATIVIDADES DE TRANSPORTE DE VALORES
8020001	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA E INVESTIGAÇÃO	ATIVIDADES DE MONITORAMENTO DE SISTEMAS DE SEGURANÇA	ATIVIDADES DE MONITORAMENTO DE SISTEMAS DE SEGURANÇA
8020002	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA E INVESTIGAÇÃO	ATIVIDADES DE MONITORAMENTO DE SISTEMAS DE SEGURANÇA	ATIVIDADES DE MONITORAMENTO DE SISTEMAS DE SEGURANÇA
8030700	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA E INVESTIGAÇÃO	ATIVIDADES DE INVESTIGAÇÃO PARTICULAR	ATIVIDADES DE INVESTIGAÇÃO PARTICULAR
8111700	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS PARA EDIFÍCIOS E ATIVIDADES PAISAGÍSTICAS	SERVIÇOS COMBINADOS PARA APOIO A EDIFÍCIOS	SERVIÇOS COMBINADOS PARA APOIO A EDIFÍCIOS, EXCETO CONDOMÍNIOS PREDIAIS
8112500	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS PARA EDIFÍCIOS E ATIVIDADES PAISAGÍSTICAS	SERVIÇOS COMBINADOS PARA APOIO A EDIFÍCIOS	CONDOMÍNIOS PREDIAIS
8121400	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS PARA EDIFÍCIOS E ATIVIDADES PAISAGÍSTICAS	ATIVIDADES DE LIMPEZA	LIMPEZA EM PRÉDIOS E EM DOMICÍLIOS
8122200	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS PARA EDIFÍCIOS E ATIVIDADES PAISAGÍSTICAS	ATIVIDADES DE LIMPEZA	IMUNIZAÇÃO E CONTROLE DE PRAGAS URBANAS
8129000	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS PARA EDIFÍCIOS E ATIVIDADES PAISAGÍSTICAS	ATIVIDADES DE LIMPEZA	ATIVIDADES DE LIMPEZA NÃO ESPECIFICADAS ANTERIORMENTE
8130300	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS PARA EDIFÍCIOS E ATIVIDADES PAISAGÍSTICAS	ATIVIDADES PAISAGÍSTICAS	ATIVIDADES PAISAGÍSTICAS
8211300	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	SERVIÇOS DE ESCRITÓRIO E APOIO ADMINISTRATIVO	SERVIÇOS COMBINADOS DE ESCRITÓRIO E APOIO ADMINISTRATIVO
8219901	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	SERVIÇOS DE ESCRITÓRIO E APOIO ADMINISTRATIVO	FOTOCÓPIAS, PREPARAÇÃO DE DOCUMENTOS E OUTROS SERVIÇOS ESPECIALIZADOS DE APOIO ADMINISTRATIVO
8219999	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	SERVIÇOS DE ESCRITÓRIO E APOIO ADMINISTRATIVO	FOTOCÓPIAS, PREPARAÇÃO DE DOCUMENTOS E OUTROS SERVIÇOS ESPECIALIZADOS DE APOIO ADMINISTRATIVO
8220200	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE TELEATENDIMENTO	ATIVIDADES DE TELEATENDIMENTO
8230001	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE ORGANIZAÇÃO DE EVENTOS, EXCETO CULTURAIS E ESPORTIVOS	ATIVIDADES DE ORGANIZAÇÃO DE EVENTOS, EXCETO CULTURAIS E ESPORTIVOS
8230002	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE ORGANIZAÇÃO DE EVENTOS, EXCETO CULTURAIS E ESPORTIVOS	ATIVIDADES DE ORGANIZAÇÃO DE EVENTOS, EXCETO CULTURAIS E ESPORTIVOS
8291100	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE COBRANÇAS E INFORMAÇÕES CADASTRAIS
8292000	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ENVASAMENTO E EMPACOTAMENTO SOB CONTRATO
8299701	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE
8299702	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE
8299703	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE
8299704	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE
8299705	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE
8299706	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE
8299707	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE
8299799	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS	ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE
8411600	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO DO ESTADO E DA POLÍTICA ECONÔMICA E SOCIAL	ADMINISTRAÇÃO PÚBLICA EM GERAL
8412400	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO DO ESTADO E DA POLÍTICA ECONÔMICA E SOCIAL	REGULAÇÃO DAS ATIVIDADES DE SAÚDE, EDUCAÇÃO, SERVIÇOS CULTURAIS E OUTROS SERVIÇOS SOCIAIS
8413200	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO DO ESTADO E DA POLÍTICA ECONÔMICA E SOCIAL	REGULAÇÃO DAS ATIVIDADES ECONÔMICAS
8421300	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	SERVIÇOS COLETIVOS PRESTADOS PELA ADMINISTRAÇÃO PÚBLICA	RELAÇÕES EXTERIORES
8422100	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	SERVIÇOS COLETIVOS PRESTADOS PELA ADMINISTRAÇÃO PÚBLICA	DEFESA
8423000	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	SERVIÇOS COLETIVOS PRESTADOS PELA ADMINISTRAÇÃO PÚBLICA	JUSTIÇA
8424800	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	SERVIÇOS COLETIVOS PRESTADOS PELA ADMINISTRAÇÃO PÚBLICA	SEGURANÇA E ORDEM PÚBLICA
8425600	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	SERVIÇOS COLETIVOS PRESTADOS PELA ADMINISTRAÇÃO PÚBLICA	DEFESA CIVIL
8430200	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL	SEGURIDADE SOCIAL OBRIGATÓRIA	SEGURIDADE SOCIAL OBRIGATÓRIA
8511200	EDUCAÇÃO	EDUCAÇÃO	EDUCAÇÃO INFANTIL E ENSINO FUNDAMENTAL	EDUCAÇÃO INFANTIL - CRECHE
8512100	EDUCAÇÃO	EDUCAÇÃO	EDUCAÇÃO INFANTIL E ENSINO FUNDAMENTAL	EDUCAÇÃO INFANTIL - PRÉ-ESCOLA
8513900	EDUCAÇÃO	EDUCAÇÃO	EDUCAÇÃO INFANTIL E ENSINO FUNDAMENTAL	ENSINO FUNDAMENTAL
8520100	EDUCAÇÃO	EDUCAÇÃO	ENSINO MÉDIO	ENSINO MÉDIO
8531700	EDUCAÇÃO	EDUCAÇÃO	EDUCAÇÃO SUPERIOR	EDUCAÇÃO SUPERIOR - GRADUAÇÃO
8532500	EDUCAÇÃO	EDUCAÇÃO	EDUCAÇÃO SUPERIOR	EDUCAÇÃO SUPERIOR - GRADUAÇÃO E PÓS-GRADUAÇÃO
8533300	EDUCAÇÃO	EDUCAÇÃO	EDUCAÇÃO SUPERIOR	EDUCAÇÃO SUPERIOR - PÓS-GRADUAÇÃO E EXTENSÃO
8541400	EDUCAÇÃO	EDUCAÇÃO	EDUCAÇÃO PROFISSIONAL DE NÍVEL TÉCNICO E TECNOLÓGICO	EDUCAÇÃO PROFISSIONAL DE NÍVEL TÉCNICO
8542200	EDUCAÇÃO	EDUCAÇÃO	EDUCAÇÃO PROFISSIONAL DE NÍVEL TÉCNICO E TECNOLÓGICO	EDUCAÇÃO PROFISSIONAL DE NÍVEL TECNOLÓGICO
8550301	EDUCAÇÃO	EDUCAÇÃO	ATIVIDADES DE APOIO À EDUCAÇÃO	ATIVIDADES DE APOIO À EDUCAÇÃO
8550302	EDUCAÇÃO	EDUCAÇÃO	ATIVIDADES DE APOIO À EDUCAÇÃO	ATIVIDADES DE APOIO À EDUCAÇÃO
8591100	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ENSINO DE ESPORTES
8592901	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ENSINO DE ARTE E CULTURA
8592902	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ENSINO DE ARTE E CULTURA
8592903	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ENSINO DE ARTE E CULTURA
8592999	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ENSINO DE ARTE E CULTURA
8593700	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ENSINO DE IDIOMAS
8599601	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ATIVIDADES DE ENSINO NÃO ESPECIFICADAS ANTERIORMENTE
8599602	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ATIVIDADES DE ENSINO NÃO ESPECIFICADAS ANTERIORMENTE
8599603	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ATIVIDADES DE ENSINO NÃO ESPECIFICADAS ANTERIORMENTE
8599604	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ATIVIDADES DE ENSINO NÃO ESPECIFICADAS ANTERIORMENTE
8599605	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ATIVIDADES DE ENSINO NÃO ESPECIFICADAS ANTERIORMENTE
8599699	EDUCAÇÃO	EDUCAÇÃO	OUTRAS ATIVIDADES DE ENSINO	ATIVIDADES DE ENSINO NÃO ESPECIFICADAS ANTERIORMENTE
8610101	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENDIMENTO HOSPITALAR	ATIVIDADES DE ATENDIMENTO HOSPITALAR
8610102	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENDIMENTO HOSPITALAR	ATIVIDADES DE ATENDIMENTO HOSPITALAR
8621601	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS E DE REMOÇÃO DE PACIENTES	SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS
8621602	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS E DE REMOÇÃO DE PACIENTES	SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS
8622400	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS E DE REMOÇÃO DE PACIENTES	SERVIÇOS DE REMOÇÃO DE PACIENTES, EXCETO OS SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS
8630501	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS
8630502	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS
8630503	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS
8630504	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS
8630506	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS
8630507	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS
8630599	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS
8640201	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
8640202	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
8640203	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
8640204	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
8640205	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
9311500	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES ESPORTIVAS	GESTÃO DE INSTALAÇÕES DE ESPORTES
8640206	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
8640207	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
8640208	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
8640209	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
8640210	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
8640211	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
8640212	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
8640213	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
8640214	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
8640299	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
8650001	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS
8650002	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS
8650003	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS
8650004	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS
8650005	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS
8650006	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS
8650007	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS
8650099	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS
8660700	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE APOIO À GESTÃO DE SAÚDE	ATIVIDADES DE APOIO À GESTÃO DE SAÚDE
8690901	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE
8690902	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE
8690903	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE
8690904	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE
8690999	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE
8711501	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES, E DE INFRA-ESTRUTURA E APOIO A PACIENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
8711502	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES, E DE INFRA-ESTRUTURA E APOIO A PACIENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
8711503	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES, E DE INFRA-ESTRUTURA E APOIO A PACIENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
9312300	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES ESPORTIVAS	CLUBES SOCIAIS, ESPORTIVOS E SIMILARES
8711504	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES, E DE INFRA-ESTRUTURA E APOIO A PACIENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
8711505	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES, E DE INFRA-ESTRUTURA E APOIO A PACIENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
8712300	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES, E DE INFRA-ESTRUTURA E APOIO A PACIENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE FORNECIMENTO DE INFRA-ESTRUTURA DE APOIO E ASSISTÊNCIA A PACIENTE NO DOMICÍLIO
8720401	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA PSICOSSOCIAL E À SAÚDE A PORTADORES DE DISTÚRBIOS PSÍQUICOS, DEFICIÊNCIA MENTAL E DEPENDÊNCIA QUÍMICA	ATIVIDADES DE ASSISTÊNCIA PSICOSSOCIAL E À SAÚDE A PORTADORES DE DISTÚRBIOS PSÍQUICOS, DEFICIÊNCIA MENTAL E DEPENDÊNCIA QUÍMICA
8720499	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA PSICOSSOCIAL E À SAÚDE A PORTADORES DE DISTÚRBIOS PSÍQUICOS, DEFICIÊNCIA MENTAL E DEPENDÊNCIA QUÍMICA	ATIVIDADES DE ASSISTÊNCIA PSICOSSOCIAL E À SAÚDE A PORTADORES DE DISTÚRBIOS PSÍQUICOS, DEFICIÊNCIA MENTAL E DEPENDÊNCIA QUÍMICA
8730101	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA SOCIAL PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA SOCIAL PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
8730102	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA SOCIAL PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA SOCIAL PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
8730199	SAÚDE HUMANA E SERVIÇOS SOCIAIS	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA SOCIAL PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES	ATIVIDADES DE ASSISTÊNCIA SOCIAL PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
8800600	SAÚDE HUMANA E SERVIÇOS SOCIAIS	SERVIÇOS DE ASSISTÊNCIA SOCIAL SEM ALOJAMENTO	SERVIÇOS DE ASSISTÊNCIA SOCIAL SEM ALOJAMENTO	SERVIÇOS DE ASSISTÊNCIA SOCIAL SEM ALOJAMENTO
9001901	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ARTES CÊNICAS, ESPETÁCULOS E ATIVIDADES COMPLEMENTARES
9001902	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ARTES CÊNICAS, ESPETÁCULOS E ATIVIDADES COMPLEMENTARES
9001903	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ARTES CÊNICAS, ESPETÁCULOS E ATIVIDADES COMPLEMENTARES
9001904	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ARTES CÊNICAS, ESPETÁCULOS E ATIVIDADES COMPLEMENTARES
9001905	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ARTES CÊNICAS, ESPETÁCULOS E ATIVIDADES COMPLEMENTARES
9001906	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ARTES CÊNICAS, ESPETÁCULOS E ATIVIDADES COMPLEMENTARES
9001999	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ARTES CÊNICAS, ESPETÁCULOS E ATIVIDADES COMPLEMENTARES
9002701	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	CRIAÇÃO ARTÍSTICA
9002702	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	CRIAÇÃO ARTÍSTICA
9003500	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS	GESTÃO DE ESPAÇOS PARA ARTES CÊNICAS, ESPETÁCULOS E OUTRAS ATIVIDADES ARTÍSTICAS
9101500	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES LIGADAS AO PATRIMÔNIO CULTURAL E AMBIENTAL	ATIVIDADES LIGADAS AO PATRIMÔNIO CULTURAL E AMBIENTAL	ATIVIDADES DE BIBLIOTECAS E ARQUIVOS
9102301	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES LIGADAS AO PATRIMÔNIO CULTURAL E AMBIENTAL	ATIVIDADES LIGADAS AO PATRIMÔNIO CULTURAL E AMBIENTAL	ATIVIDADES DE MUSEUS E DE EXPLORAÇÃO, RESTAURAÇÃO ARTÍSTICA E CONSERVAÇÃO DE LUGARES E PRÉDIOS HISTÓRICOS E ATRAÇÕES SIMILARES
9102302	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES LIGADAS AO PATRIMÔNIO CULTURAL E AMBIENTAL	ATIVIDADES LIGADAS AO PATRIMÔNIO CULTURAL E AMBIENTAL	ATIVIDADES DE MUSEUS E DE EXPLORAÇÃO, RESTAURAÇÃO ARTÍSTICA E CONSERVAÇÃO DE LUGARES E PRÉDIOS HISTÓRICOS E ATRAÇÕES SIMILARES
9103100	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES LIGADAS AO PATRIMÔNIO CULTURAL E AMBIENTAL	ATIVIDADES LIGADAS AO PATRIMÔNIO CULTURAL E AMBIENTAL	ATIVIDADES DE JARDINS BOTÂNICOS, ZOOLÓGICOS, PARQUES NACIONAIS, RESERVAS ECOLÓGICAS E ÁREAS DE PROTEÇÃO AMBIENTAL
9200301	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS
9200302	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS
9200399	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS
9313100	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES ESPORTIVAS	ATIVIDADES DE CONDICIONAMENTO FÍSICO
9319101	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES ESPORTIVAS	ATIVIDADES ESPORTIVAS NÃO ESPECIFICADAS ANTERIORMENTE
9319199	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES ESPORTIVAS	ATIVIDADES ESPORTIVAS NÃO ESPECIFICADAS ANTERIORMENTE
9321200	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER	PARQUES DE DIVERSÃO E PARQUES TEMÁTICOS
9329801	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER NÃO ESPECIFICADAS ANTERIORMENTE
9329802	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER NÃO ESPECIFICADAS ANTERIORMENTE
9329803	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER NÃO ESPECIFICADAS ANTERIORMENTE
9329804	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER NÃO ESPECIFICADAS ANTERIORMENTE
9329899	ARTES, CULTURA, ESPORTE E RECREAÇÃO	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER	ATIVIDADES DE RECREAÇÃO E LAZER NÃO ESPECIFICADAS ANTERIORMENTE
9411100	OUTRAS ATIVIDADES DE SERVIÇOS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS PATRONAIS, EMPRESARIAIS E PROFISSIONAIS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS PATRONAIS E EMPRESARIAIS
9412001	OUTRAS ATIVIDADES DE SERVIÇOS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS PATRONAIS, EMPRESARIAIS E PROFISSIONAIS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS PROFISSIONAIS
9412099	OUTRAS ATIVIDADES DE SERVIÇOS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS PATRONAIS, EMPRESARIAIS E PROFISSIONAIS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS PROFISSIONAIS
9420100	OUTRAS ATIVIDADES DE SERVIÇOS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS	ATIVIDADES DE ORGANIZAÇÕES SINDICAIS	ATIVIDADES DE ORGANIZAÇÕES SINDICAIS
9430800	OUTRAS ATIVIDADES DE SERVIÇOS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS	ATIVIDADES DE ASSOCIAÇÕES DE DEFESA DE DIREITOS SOCIAIS	ATIVIDADES DE ASSOCIAÇÕES DE DEFESA DE DIREITOS SOCIAIS
9491000	OUTRAS ATIVIDADES DE SERVIÇOS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES DE ORGANIZAÇÕES RELIGIOSAS
9492800	OUTRAS ATIVIDADES DE SERVIÇOS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES DE ORGANIZAÇÕES POLÍTICAS
9493600	OUTRAS ATIVIDADES DE SERVIÇOS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS LIGADAS À CULTURA E À ARTE
9499500	OUTRAS ATIVIDADES DE SERVIÇOS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS NÃO ESPECIFICADAS ANTERIORMENTE	ATIVIDADES ASSOCIATIVAS NÃO ESPECIFICADAS ANTERIORMENTE
9511800	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO	REPARAÇÃO E MANUTENÇÃO DE COMPUTADORES E DE EQUIPAMENTOS PERIFÉRICOS
9512600	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE COMUNICAÇÃO
9521500	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS ELETROELETRÔNICOS DE USO PESSOAL E DOMÉSTICO
9529101	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
9529102	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
9529103	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
9529104	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
9529105	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
9529106	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
9529199	OUTRAS ATIVIDADES DE SERVIÇOS	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
9601701	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	LAVANDERIAS, TINTURARIAS E TOALHEIROS
9601702	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	LAVANDERIAS, TINTURARIAS E TOALHEIROS
9601703	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	LAVANDERIAS, TINTURARIAS E TOALHEIROS
9602501	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	CABELEIREIROS E OUTRAS ATIVIDADES DE TRATAMENTO DE BELEZA
9602502	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	CABELEIREIROS E OUTRAS ATIVIDADES DE TRATAMENTO DE BELEZA
9603301	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES FUNERÁRIAS E SERVIÇOS RELACIONADOS
9603302	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES FUNERÁRIAS E SERVIÇOS RELACIONADOS
9603303	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES FUNERÁRIAS E SERVIÇOS RELACIONADOS
9603304	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES FUNERÁRIAS E SERVIÇOS RELACIONADOS
9603305	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES FUNERÁRIAS E SERVIÇOS RELACIONADOS
9603399	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES FUNERÁRIAS E SERVIÇOS RELACIONADOS
9609202	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES DE SERVIÇOS PESSOAIS NÃO ESPECIFICADAS ANTERIORMENTE
9609204	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES DE SERVIÇOS PESSOAIS NÃO ESPECIFICADAS ANTERIORMENTE
9609205	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES DE SERVIÇOS PESSOAIS NÃO ESPECIFICADAS ANTERIORMENTE
9609206	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES DE SERVIÇOS PESSOAIS NÃO ESPECIFICADAS ANTERIORMENTE
9609207	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES DE SERVIÇOS PESSOAIS NÃO ESPECIFICADAS ANTERIORMENTE
9609208	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES DE SERVIÇOS PESSOAIS NÃO ESPECIFICADAS ANTERIORMENTE
9609299	OUTRAS ATIVIDADES DE SERVIÇOS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS	ATIVIDADES DE SERVIÇOS PESSOAIS NÃO ESPECIFICADAS ANTERIORMENTE
9700500	SERVIÇOS DOMÉSTICOS	SERVIÇOS DOMÉSTICOS	SERVIÇOS DOMÉSTICOS	SERVIÇOS DOMÉSTICOS
9900800	ORGANISMOS INTERNACIONAIS E OUTRAS INSTITUIÇÕES EXTRATERRITORIAIS	ORGANISMOS INTERNACIONAIS E OUTRAS INSTITUIÇÕES EXTRATERRITORIAIS	ORGANISMOS INTERNACIONAIS E OUTRAS INSTITUIÇÕES EXTRATERRITORIAIS	ORGANISMOS INTERNACIONAIS E OUTRAS INSTITUIÇÕES EXTRATERRITORIAIS
\.


--
-- TOC entry 4847 (class 0 OID 17718)
-- Dependencies: 223
-- Data for Name: dadoscomplementares; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.dadoscomplementares (endereco, bairro, cidade, estado, cep, telefone, email, cnpj, ie, im, tenantid, createdat, updatedat, fantasia, razaosocial, observacoes) FROM stdin;
\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	c0b38958-8832-465d-9efa-812185c2fb1a	2023-07-04 14:06:37.932	2023-07-04 14:06:37.932	\N	\N	\N
\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	89e5d80e-5745-4235-84e1-ae590de026ea	2023-07-04 14:08:14.279	2023-07-04 14:08:14.279	\N	\N	\N
\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	4d95e964-6d08-4316-8a63-3e994c93f622	2023-07-04 15:26:43.812	2023-07-04 15:26:43.812	\N	\N	\N
\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	02ca80b9-7a5b-4715-a9ee-9226f89087a5	2023-07-05 18:57:33.628	2023-07-05 18:57:33.628	\N	\N	\N
\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	7a0eb58a-aaea-4782-8724-06144fceff00	2023-07-06 08:51:29.979	2023-07-06 08:51:29.979	\N	\N	\N
Rua Corruíras, 175	Campeche	Florianópolis	Santa Catarina	88063091	+55 48 988151381	contato@bla.com				b9fb9d4b-e9a4-45ed-86f0-b9262922437d	2026-03-31 09:56:12.258	2026-03-31 09:56:12.258	Bla	Grupo Bla	
Rua das Curruiras, 175	Campeche	Florianópolis	SC	88063091	48 988151381	chayimamaral@gmail.com				5bf1a2bc-b39e-4af6-97df-bb70326373ab	2023-07-06 16:25:28.288	2023-07-06 16:25:28.288	Carlos Amaral	VEC	Novo teste testando o teste de observações.
\.


--
-- TOC entry 4848 (class 0 OID 17728)
-- Dependencies: 224
-- Data for Name: empresa; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.empresa (id, nome, municipio_id, dataabertura, datafechamento, ativo, tenant_id, rotina_id, cnaes, iniciado, bairro) FROM stdin;
32c99043-ae5e-47a6-b3db-e02f13b5aff9	Ploc Industria de goma de mascar	4a8647d1-06c8-4616-85be-3f6399949ed3	\N	\N	t	5bf1a2bc-b39e-4af6-97df-bb70326373ab	ed925e14-d150-434f-b287-7154d67c1d0a	{}	t	\N
3bd699c9-15dc-4a79-8ee8-0a098073203b	Empresa Exemplo	4a8647d1-06c8-4616-85be-3f6399949ed3	\N	\N	t	5bf1a2bc-b39e-4af6-97df-bb70326373ab	ed925e14-d150-434f-b287-7154d67c1d0a	{1234567,2345678}	t	\N
67207fad-07aa-4daf-b667-f3b926a120ad	Vec Sistemas	abfd20e5-d561-4c44-ba42-ae194ebb2c18	\N	\N	t	5bf1a2bc-b39e-4af6-97df-bb70326373ab	005a21fd-3aaa-43ee-a2e8-647a4d8845ab	{1234567,2345678,6225315,5648978,6354987,5264897}	t	\N
56fab307-b775-40f6-87ef-51daa7509698	Anadja Serviços Contábeis	6a69c90c-8475-4d97-9e9a-8647305346f1	\N	\N	t	5bf1a2bc-b39e-4af6-97df-bb70326373ab	595ac1c0-fe5e-4a87-8871-9d9cce8fce04	{1234567,5234465,1234869,1236587}	t	\N
030adbb7-7d9d-408f-bf90-786f0dca48d2	T2R Play Book - alteraçao	abfd20e5-d561-4c44-ba42-ae194ebb2c18	\N	\N	f	5bf1a2bc-b39e-4af6-97df-bb70326373ab	49241e34-99f6-4af3-98a2-cb39f251818a	{1234567,2356789,5231513}	f	\N
65ea4cdb-3bd1-48a3-8534-fd78190710ce	Nova Empresa TExte	abfd20e5-d561-4c44-ba42-ae194ebb2c18	\N	\N	t	5bf1a2bc-b39e-4af6-97df-bb70326373ab	005a21fd-3aaa-43ee-a2e8-647a4d8845ab	{}	f	\N
5b2eacf9-5289-402d-85be-52f7233d20d2	Carlos Amaral Consultoria	abfd20e5-d561-4c44-ba42-ae194ebb2c18	\N	\N	t	5bf1a2bc-b39e-4af6-97df-bb70326373ab	1cd6c238-d805-4c94-829e-bad7a9b62cfb	{}	t	\N
a0ef2dad-5f65-4821-bbf2-034477183f44	Empresa Teste	abfd20e5-d561-4c44-ba42-ae194ebb2c18	\N	\N	t	5bf1a2bc-b39e-4af6-97df-bb70326373ab	1cd6c238-d805-4c94-829e-bad7a9b62cfb	{}	f	\N
2d969b03-f302-437a-8cfe-7b85da6e28fb	Nova empresa teste de tags	6a69c90c-8475-4d97-9e9a-8647305346f1	\N	\N	t	5bf1a2bc-b39e-4af6-97df-bb70326373ab	595ac1c0-fe5e-4a87-8871-9d9cce8fce04	{}	t	\N
\.


--
-- TOC entry 4870 (class 0 OID 28766)
-- Dependencies: 246
-- Data for Name: empresa_agenda; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.empresa_agenda (id, empresa_id, template_id, descricao, data_vencimento, status, valor_estimado, criado_em, atualizado_em) FROM stdin;
\.


--
-- TOC entry 4871 (class 0 OID 28851)
-- Dependencies: 247
-- Data for Name: empresa_compromissos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.empresa_compromissos (id, descricao, valor, vencimento, observacao, status, empresa_id, tipoempresa_obrigacao_id, criado_em, atualizado_em, competencia) FROM stdin;
e02cd007-30e7-4337-ad20-71062fa55cb2	Compromisso bairro mensal nao financeiro	\N	2026-04-20 00:00:00-03	Seed automatico MEI - abrangencia local.	pendente	5b2eacf9-5289-402d-85be-52f7233d20d2	93c6a4dc-ae55-431a-b0d8-b69bc237875f	2026-03-31 15:26:11.410707-03	2026-03-31 15:26:11.410707-03	2026-04-01
6b8ed10c-8eda-4161-aa52-8c62509d3cd4	Compromisso municipal mensal financeiro	120.000	2026-04-20 00:00:00-03	Seed automatico MEI - abrangencia local.	pendente	5b2eacf9-5289-402d-85be-52f7233d20d2	cf548021-bc2d-4091-8f1a-087918e5f577	2026-03-31 15:26:11.410707-03	2026-03-31 15:26:11.410707-03	2026-04-01
85d5745d-6bdd-4bb5-8652-e3331306f4af	Compromisso estadual mensal nao financeiro	\N	2026-04-20 00:00:00-03	Seed automatico MEI - abrangencia local.	pendente	5b2eacf9-5289-402d-85be-52f7233d20d2	5d3189ad-0395-490f-a929-b4f8675bad4e	2026-03-31 15:26:11.410707-03	2026-03-31 15:26:11.410707-03	2026-04-01
600bf149-b675-4563-9205-1f52a753dce8	Compromisso municipal mensal nao financeiro	\N	2026-04-20 00:00:00-03	Seed automatico MEI - abrangencia local.	pendente	5b2eacf9-5289-402d-85be-52f7233d20d2	9a9af32b-a611-46ea-9acc-abce4ab662ec	2026-03-31 15:26:11.410707-03	2026-03-31 15:26:11.410707-03	2026-04-01
9b071171-9054-4ba6-8302-8a74a8235472	Compromisso estadual anual nao financeiro	\N	2026-04-20 00:00:00-03	Seed automatico MEI - abrangencia local.	pendente	5b2eacf9-5289-402d-85be-52f7233d20d2	f3d85f25-31d0-4cdc-93f9-c9a9818e65c7	2026-03-31 15:26:11.410707-03	2026-03-31 15:26:11.410707-03	2026-04-01
fb9e4c4c-ebd2-4ddd-a6d5-ed0e4a2a7664	Compromisso municipal anual nao financeiro	\N	2026-03-30 00:00:00-03	Seed automatico MEI - abrangencia local.	pendente	5b2eacf9-5289-402d-85be-52f7233d20d2	4acf5849-2a62-4390-b7b8-b0a2920113f0	2026-03-31 15:26:11.410707-03	2026-03-31 20:16:33.063276-03	2026-04-01
beb2fae6-cdba-4b15-be1d-d70dee664f6d	Compromisso municipal anual financeiro	130.000	2026-04-06 00:00:00-03	Seed automatico MEI - abrangencia local.	pendente	5b2eacf9-5289-402d-85be-52f7233d20d2	e7873d49-a38d-48bd-aa59-268d943625e3	2026-03-31 15:26:11.410707-03	2026-03-31 20:16:34.462852-03	2026-04-01
47e8b8f6-7697-45af-86ab-66dc9f19ff1b	Compromisso estadual mensal financeiro	100.000	2026-04-07 00:00:00-03	Seed automatico MEI - abrangencia local.	pendente	5b2eacf9-5289-402d-85be-52f7233d20d2	7a6e69c2-57e6-4beb-9ec1-e3424a7a2d8d	2026-03-31 15:26:11.410707-03	2026-03-31 20:16:44.354348-03	2026-04-01
791407c9-e43b-4b65-a1cb-054e3bac3c5f	Teste de avulsos	220.000	2026-04-29 21:00:00-03		pendente	5b2eacf9-5289-402d-85be-52f7233d20d2	52f9e9ad-2e2c-4a64-b779-8867db21479d	2026-04-01 08:28:06.164157-03	2026-04-01 08:28:06.164157-03	2026-04-01
88a5f0fa-3103-4347-b3ee-07ec9b5175eb	Compromisso bairro anual financeiro	200.500	2026-03-31 00:00:00-03	Seed automatico MEI - abrangencia local.	concluido	5b2eacf9-5289-402d-85be-52f7233d20d2	bce1f085-fdc7-4054-a20f-09ad6f22e2a6	2026-03-31 15:26:11.410707-03	2026-04-01 11:09:04.808209-03	2026-04-01
4968ce2f-479a-4dfa-acaf-b5df0ea08c22	Compromisso bairro mensal financeiro	200.000	2026-04-20 00:00:00-03	Seed automatico MEI - abrangencia local.	pendente	5b2eacf9-5289-402d-85be-52f7233d20d2	e85d3da6-fac6-4f01-95af-0cbe67576089	2026-03-31 15:26:11.410707-03	2026-03-31 15:43:46.537795-03	2026-04-01
3172ed58-cf9d-4e43-a735-6784cc636de6	Compromisso estadual anual financeiro	110.000	2026-04-20 00:00:00-03	Seed automatico MEI - abrangencia local.	concluido	5b2eacf9-5289-402d-85be-52f7233d20d2	c603a3c5-10ee-4b14-a122-b7473ece1fa5	2026-03-31 15:26:11.410707-03	2026-03-31 20:15:45.427246-03	2026-04-01
\.


--
-- TOC entry 4872 (class 0 OID 28908)
-- Dependencies: 248
-- Data for Name: empresa_dados; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.empresa_dados (empresa_id, cnpj, endereco, email_contato, telefone, telefone2, data_abertura, data_encerramento, observacao, criado_em, atualizado_em) FROM stdin;
\.


--
-- TOC entry 4849 (class 0 OID 17742)
-- Dependencies: 225
-- Data for Name: empresacnae; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.empresacnae (empresa, cnae) FROM stdin;
\.


--
-- TOC entry 4850 (class 0 OID 17749)
-- Dependencies: 226
-- Data for Name: empresadados; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.empresadados (id, razaosocial, fantasia, cnpj, ie, im, empresaid) FROM stdin;
\.


--
-- TOC entry 4843 (class 0 OID 17665)
-- Dependencies: 219
-- Data for Name: estado; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.estado (id, nome, sigla, ativo) FROM stdin;
0874a7f6-4aac-4764-819f-402a9ac83631	Rondônia	RO	t
97981a5d-8395-4c6f-bdec-30804f7910a0	Roraima	RR	t
b3b8bf17-9063-495a-ad37-fc64e3784321	Rio Grande do Sul	RS	t
502caf63-be95-472f-9922-e8ba268fefa8	Santa Catarina	SC	t
34120e89-4e9b-4282-b2ed-611764f37d18	Sergipe	SE	t
59e0036a-4269-4297-a30a-d86a54dc4b7c	São Paulo	SP	t
79205e41-9aab-4b65-8b91-ae7d92074f03	Tocantins	TO	t
cdd36e9f-ac1b-4954-96ce-76f4780206cc	Amazonas	AM	t
1f106b25-26a5-42d9-8944-6f07915095d5	Amapá	AP	t
b779fcd6-f89b-4777-872f-a5d10b56fc91	Bahia	BA	t
a6c43bac-7a92-4cef-a4ea-2c0e8c3ba71e	Ceará	CE	t
96e1005c-4051-4754-a865-b8692257ff8a	Distrito Federal	DF	t
65cf8cc3-94b3-4888-97a9-80ce81c1d4ce	Espirito Santo	ES	t
810a5e93-2426-4521-b059-d64d3a83a19f	Goiás	GO	t
03c0a6a3-09e5-4f69-a99c-df90f255cbfc\n	Maranhão	MA	t
071b9f94-298a-42c3-a042-0a15476f5b8b\n	Minas Gerais	MG	t
0eacb915-f4a3-41dc-982e-e8c281a2a33c\n	Mato Grosso do Sul	MS	t
1342eb48-4d7e-48ab-b66e-557cd3a8a24a	Mato Grosso	MT	t
1457525d-4387-4502-9d23-2fc31db8c808	Pará	PA	t
1ab075d3-8d38-4d26-b1eb-ddd65eeb6c35\n	Paraíba	PB	t
48f43519-b4ab-45f7-b43b-faab68187288\n	Pernambuco	PE	t
756f8e9c-31ce-4afe-a749-8902928d0083\n	Piauí	PI	t
ad44e0c8-2fa2-41cb-bf50-2b30b79d57e6\n	Paraná	PR	t
d233f91d-bb00-4cde-a5dc-4f7a0d9af4b2\n	Rio de Janeiro	RJ	t
e3eaa7a4-511d-4eff-8f44-7df2e5c82907\n	Alagoas	AL	t
ec415c5e-b2e3-43eb-885f-f9987fcc543d\n	Rio Grande do Norte	RN	t
31e25438-c641-424a-858d-da4557a67b4f	testes	Te	f
7e7a4de6-9e0b-42be-a236-18cd4dc15e77	teste	TEs	f
43f5f9b0-4204-4ffe-a6d0-3a09e1fef1b5	teste	Te	f
16175392-1d15-4f35-bf47-9e0b9eed0ee3	teste	Te	f
8e220cb0-9820-431e-91be-87eeb74453eb	asdfs	ASDf	f
219e2ef7-37f1-4489-ae53-b5f4b9ab1c68	asdfasdfa	ADSf	f
c79b80a5-7877-40ba-9b01-408f411ac5bf	Rio Grande do Centro	RC	f
0197cdfe-5c41-40a6-ae77-56da02d68b5e	Acre	AC	t
21ff67f7-283a-46eb-96ea-7198a2bc2761	Exterior	EX	t
\.


--
-- TOC entry 4851 (class 0 OID 17757)
-- Dependencies: 227
-- Data for Name: feriado_estadual; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.feriado_estadual (feriado_id, uf_id) FROM stdin;
6ae652e1-aacc-4d44-8f43-f06c9247dbda	59e0036a-4269-4297-a30a-d86a54dc4b7c
d9002885-b6e2-423d-a524-90be59cf1c94	0eacb915-f4a3-41dc-982e-e8c281a2a33c\n
\.


--
-- TOC entry 4852 (class 0 OID 17764)
-- Dependencies: 228
-- Data for Name: feriado_municipal; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.feriado_municipal (feriado_id, municipio_id) FROM stdin;
dbd41f59-fcc6-412a-bd21-20f0d533b5bf	abfd20e5-d561-4c44-ba42-ae194ebb2c18
8e7b05f5-3fb9-4f40-a8b9-2b2814461448	f4ac2cb0-44a7-4d41-ad60-30818a39c37b
1bc4a8dd-333d-45f8-b0d6-7704964c47ee	{"id":"5e6b9b79-66ce-4119-af61-1fdf141c085b","nome":"Curitiba / PR"}
7b9cf456-2488-4c40-999c-a3f76fe4868a	4a8647d1-06c8-4616-85be-3f6399949ed3
a0825ec4-330e-447f-9ad8-323906c08f24	4c754d16-7a29-4682-80c6-a193dbe902f8
bd16b37b-4236-4c04-a679-0df6f34d41c3	4c754d16-7a29-4682-80c6-a193dbe902f8
c587121e-8c81-4a33-8d11-ea586c11d33e	5e6b9b79-66ce-4119-af61-1fdf141c085b
\.


--
-- TOC entry 4853 (class 0 OID 17771)
-- Dependencies: 229
-- Data for Name: feriados; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.feriados (id, descricao, data, ativo, feriado) FROM stdin;
6ae652e1-aacc-4d44-8f43-f06c9247dbda	Feriado Estadual Sâo Paulo	09/07	t	ESTADUAL
8e2d7b89-7b4d-4277-9eea-c926e3664f42	Confraternização Universal	01/01	t	FIXO
dbd41f59-fcc6-412a-bd21-20f0d533b5bf	Aniversário Cidade Florianópolis	23/03	t	MUNICIPAL
8e7b05f5-3fb9-4f40-a8b9-2b2814461448	Aniversário Cidade de São Paulo	25/01	t	MUNICIPAL
351ef755-5f5e-496e-8455-ef15dfedcce1	Natal	25/12	t	FIXO
ae000276-7b31-4ae9-92a6-2952960c0c53	Independência do Brasil	07/09	t	FIXO
b6ee7de6-e076-4bc3-b2cc-f486dfb53389	Proclamação da República	15/11	t	FIXO
fe5a177b-d661-47aa-9152-36aa9b2bd65d	Dia de Finados	02/11	t	FIXO
8b10fc7c-6eb0-4447-a2fe-1eb281857b12	Páscoa	31/03	t	VARIAVEL
7b9cf456-2488-4c40-999c-a3f76fe4868a	Feriado Guaruja	15/12	t	MUNICIPAL
a0825ec4-330e-447f-9ad8-323906c08f24	Aniversário de Santos	14/04	t	MUNICIPAL
d9002885-b6e2-423d-a524-90be59cf1c94	Aniversário Mato Grosso do Sul	11/10	t	ESTADUAL
bd16b37b-4236-4c04-a679-0df6f34d41c3	Feriado de Santos	15/08	f	MUNICIPAL
c587121e-8c81-4a33-8d11-ea586c11d33e	Aiversário Curitiba	29/03	t	MUNICIPAL
\.


--
-- TOC entry 4854 (class 0 OID 17783)
-- Dependencies: 230
-- Data for Name: grupopassos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.grupopassos (id, descricao, municipio_id, createdat, updatedat, tipoempresa_id, ativo) FROM stdin;
8de1301f-ba9d-41d8-b391-db9e0b56ab9c	EIRELI FLORIPA	abfd20e5-d561-4c44-ba42-ae194ebb2c18	2023-07-18 14:15:01.571	2023-07-18 14:15:01.571	13d8bac6-5226-4af7-8e90-a44880dcbe27	t
e0bb5bfc-21c2-4a97-875d-54fa5ddbc364	Biguaçu LTDA	6a69c90c-8475-4d97-9e9a-8647305346f1	2023-07-24 17:09:39.585	2023-07-24 17:09:39.585	190016eb-d7df-419c-a203-fbdec2e6f379	t
a9e87eb2-9625-4cd5-a141-6bc1c00e3d86	Guarujá LTDA	4a8647d1-06c8-4616-85be-3f6399949ed3	2023-07-24 17:11:13.453	2023-07-24 17:11:13.453	190016eb-d7df-419c-a203-fbdec2e6f379	t
00ad6a11-1ed1-4676-9c5f-43b088530cab	Florianópolis LTDA	abfd20e5-d561-4c44-ba42-ae194ebb2c18	2023-07-24 17:10:25.794	2023-07-24 17:10:25.794	190016eb-d7df-419c-a203-fbdec2e6f379	t
f18a4388-252e-41a7-a0da-14e4061539d9	Guarujá MEI	4a8647d1-06c8-4616-85be-3f6399949ed3	2023-07-24 19:39:57.698	2023-07-24 19:39:57.698	21a4bf05-3100-41e2-a3b2-e59ff67fc897	t
\.


--
-- TOC entry 4881 (class 0 OID 29005)
-- Dependencies: 257
-- Data for Name: ibge_cnae_classe; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ibge_cnae_classe (id, grupo_id, nome) FROM stdin;
1	1	CULTIVO DE CEREAIS
2	1	CULTIVO DE ALGODÃO HERBÁCEO E DE OUTRAS FIBRAS DE LAVOURA TEMPORÁRIA
3	1	CULTIVO DE CANA-DE-AÇÚCAR
4	1	CULTIVO DE FUMO
5	1	CULTIVO DE SOJA
6	1	CULTIVO DE OLEAGINOSAS DE LAVOURA TEMPORÁRIA, EXCETO SOJA
7	1	CULTIVO DE PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
8	2	HORTICULTURA
9	2	CULTIVO DE FLORES E PLANTAS ORNAMENTAIS
10	3	CULTIVO DE LARANJA
11	3	CULTIVO DE UVA
12	3	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE, EXCETO LARANJA E UVA
13	3	CULTIVO DE CAFÉ
14	3	CULTIVO DE CACAU
15	3	CULTIVO DE PLANTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE
16	4	PRODUÇÃO DE SEMENTES CERTIFICADAS
17	4	PRODUÇÃO DE MUDAS E OUTRAS FORMAS DE PROPAGAÇÃO VEGETAL, CERTIFICADAS
18	5	CRIAÇÃO DE BOVINOS
19	5	CRIAÇÃO DE OUTROS ANIMAIS DE GRANDE PORTE
20	5	CRIAÇÃO DE CAPRINOS E OVINOS
21	5	CRIAÇÃO DE SUÍNOS
22	5	CRIAÇÃO DE AVES
23	5	CRIAÇÃO DE ANIMAIS NÃO ESPECIFICADOS ANTERIORMENTE
24	6	ATIVIDADES DE APOIO À AGRICULTURA
25	6	ATIVIDADES DE APOIO À PECUÁRIA
26	6	ATIVIDADES DE PÓS-COLHEITA
27	7	CAÇA E SERVIÇOS RELACIONADOS
28	8	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
29	9	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS
30	10	ATIVIDADES DE APOIO À PRODUÇÃO FLORESTAL
31	11	PESCA EM ÁGUA SALGADA
32	11	PESCA EM ÁGUA DOCE
33	12	AQUICULTURA EM ÁGUA SALGADA E SALOBRA
34	12	AQUICULTURA EM ÁGUA DOCE
35	13	EXTRAÇÃO DE CARVÃO MINERAL
36	14	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL
37	15	EXTRAÇÃO DE MINÉRIO DE FERRO
38	16	EXTRAÇÃO DE MINÉRIO DE METAIS PRECIOSOS
39	16	EXTRAÇÃO DE MINÉRIO DE ALUMÍNIO
40	16	EXTRAÇÃO DE MINÉRIO DE ESTANHO
41	16	EXTRAÇÃO DE MINÉRIO DE MANGANÊS
42	16	EXTRAÇÃO DE MINERAIS RADIOATIVOS
43	16	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS NÃO ESPECIFICADOS ANTERIORMENTE
44	17	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
45	18	EXTRAÇÃO DE MINERAIS PARA FABRICAÇÃO DE ADUBOS, FERTILIZANTES E OUTROS PRODUTOS QUÍMICOS
46	18	EXTRAÇÃO E REFINO DE SAL MARINHO E SAL-GEMA
47	18	EXTRAÇÃO DE GEMAS (PEDRAS PRECIOSAS E SEMIPRECIOSAS)
48	18	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE
49	19	ATIVIDADES DE APOIO À EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL
50	20	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS, EXCETO PETRÓLEO E GÁS NATURAL
51	21	ABATE DE RESES, EXCETO SUÍNOS
52	21	ABATE DE SUÍNOS, AVES E OUTROS PEQUENOS ANIMAIS
53	21	FABRICAÇÃO DE PRODUTOS DE CARNE
54	22	PRESERVAÇÃO DO PESCADO E FABRICAÇÃO DE PRODUTOS DO PESCADO
55	23	FABRICAÇÃO DE CONSERVAS DE FRUTAS
56	23	FABRICAÇÃO DE CONSERVAS DE LEGUMES E OUTROS VEGETAIS
57	23	FABRICAÇÃO DE SUCOS DE FRUTAS, HORTALIÇAS E LEGUMES
58	24	FABRICAÇÃO DE ÓLEOS VEGETAIS EM BRUTO, EXCETO ÓLEO DE MILHO
59	24	FABRICAÇÃO DE ÓLEOS VEGETAIS REFINADOS, EXCETO ÓLEO DE MILHO
60	24	FABRICAÇÃO DE MARGARINA E OUTRAS GORDURAS VEGETAIS E DE ÓLEOS NÃO-COMESTÍVEIS DE ANIMAIS
61	25	FABRICAÇÃO DE SORVETES E OUTROS GELADOS COMESTÍVEIS
62	25	PREPARAÇÃO DO LEITE
63	25	FABRICAÇÃO DE LATICÍNIOS
64	26	BENEFICIAMENTO DE ARROZ E FABRICAÇÃO DE PRODUTOS DO ARROZ
65	26	MOAGEM DE TRIGO E FABRICAÇÃO DE DERIVADOS
66	26	FABRICAÇÃO DE FARINHA DE MANDIOCA E DERIVADOS
67	26	FABRICAÇÃO DE FARINHA DE MILHO E DERIVADOS, EXCETO ÓLEOS DE MILHO
68	26	FABRICAÇÃO DE AMIDOS E FÉCULAS DE VEGETAIS E DE ÓLEOS DE MILHO
69	26	FABRICAÇÃO DE ALIMENTOS PARA ANIMAIS
70	26	MOAGEM E FABRICAÇÃO DE PRODUTOS DE ORIGEM VEGETAL NÃO ESPECIFICADOS ANTERIORMENTE
71	27	FABRICAÇÃO DE AÇÚCAR EM BRUTO
72	27	FABRICAÇÃO DE AÇÚCAR REFINADO
73	28	TORREFAÇÃO E MOAGEM DE CAFÉ
74	28	FABRICAÇÃO DE PRODUTOS À BASE DE CAFÉ
75	29	FABRICAÇÃO DE PRODUTOS DE PANIFICAÇÃO
76	29	FABRICAÇÃO DE BISCOITOS E BOLACHAS
77	29	FABRICAÇÃO DE PRODUTOS DERIVADOS DO CACAU, DE CHOCOLATES E CONFEITOS
78	29	FABRICAÇÃO DE MASSAS ALIMENTÍCIAS
79	29	FABRICAÇÃO DE ESPECIARIAS, MOLHOS, TEMPEROS E CONDIMENTOS
80	29	FABRICAÇÃO DE ALIMENTOS E PRATOS PRONTOS
81	29	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
82	30	FABRICAÇÃO DE AGUARDENTES E OUTRAS BEBIDAS DESTILADAS
83	30	FABRICAÇÃO DE VINHO
84	30	FABRICAÇÃO DE MALTE, CERVEJAS E CHOPES
85	31	FABRICAÇÃO DE ÁGUAS ENVASADAS
86	31	FABRICAÇÃO DE REFRIGERANTES E DE OUTRAS BEBIDAS NÃO-ALCOÓLICAS
87	32	PROCESSAMENTO INDUSTRIAL DO FUMO
88	33	FABRICAÇÃO DE PRODUTOS DO FUMO
89	34	PREPARAÇÃO E FIAÇÃO DE FIBRAS DE ALGODÃO
90	34	PREPARAÇÃO E FIAÇÃO DE FIBRAS TÊXTEIS NATURAIS, EXCETO ALGODÃO
91	34	FIAÇÃO DE FIBRAS ARTIFICIAIS E SINTÉTICAS
92	34	FABRICAÇÃO DE LINHAS PARA COSTURAR E BORDAR
93	35	TECELAGEM DE FIOS DE ALGODÃO
94	35	TECELAGEM DE FIOS DE FIBRAS TÊXTEIS NATURAIS, EXCETO ALGODÃO
95	35	TECELAGEM DE FIOS DE FIBRAS ARTIFICIAIS E SINTÉTICAS
96	36	FABRICAÇÃO DE TECIDOS DE MALHA
97	37	ACABAMENTOS EM FIOS, TECIDOS E ARTEFATOS TÊXTEIS
98	38	FABRICAÇÃO DE ARTEFATOS TÊXTEIS PARA USO DOMÉSTICO
99	38	FABRICAÇÃO DE ARTEFATOS DE TAPEÇARIA
100	38	FABRICAÇÃO DE ARTEFATOS DE CORDOARIA
101	38	FABRICAÇÃO DE TECIDOS ESPECIAIS, INCLUSIVE ARTEFATOS
102	38	FABRICAÇÃO DE OUTROS PRODUTOS TÊXTEIS NÃO ESPECIFICADOS ANTERIORMENTE
103	39	CONFECÇÃO DE ROUPAS ÍNTIMAS
104	39	CONFECÇÃO DE PEÇAS DE VESTUÁRIO, EXCETO ROUPAS ÍNTIMAS
105	39	CONFECÇÃO DE ROUPAS PROFISSIONAIS
106	39	FABRICAÇÃO DE ACESSÓRIOS DO VESTUÁRIO, EXCETO PARA SEGURANÇA E PROTEÇÃO
107	40	FABRICAÇÃO DE MEIAS
108	40	FABRICAÇÃO DE ARTIGOS DO VESTUÁRIO, PRODUZIDOS EM MALHARIAS E TRICOTAGENS, EXCETO MEIAS
109	41	CURTIMENTO E OUTRAS PREPARAÇÕES DE COURO
110	42	FABRICAÇÃO DE ARTIGOS PARA VIAGEM, BOLSAS E SEMELHANTES DE QUALQUER MATERIAL
111	42	FABRICAÇÃO DE ARTEFATOS DE COURO NÃO ESPECIFICADOS ANTERIORMENTE
112	43	FABRICAÇÃO DE CALÇADOS DE MATERIAL SINTÉTICO
113	43	FABRICAÇÃO DE CALÇADOS DE COURO
114	43	FABRICAÇÃO DE TÊNIS DE QUALQUER MATERIAL
115	43	FABRICAÇÃO DE CALÇADOS DE MATERIAIS NÃO ESPECIFICADOS ANTERIORMENTE
116	44	FABRICAÇÃO DE PARTES PARA CALÇADOS, DE QUALQUER MATERIAL
117	45	DESDOBRAMENTO DE MADEIRA
118	46	FABRICAÇÃO DE MADEIRA LAMINADA E DE CHAPAS DE MADEIRA COMPENSADA, PRENSADA E AGLOMERADA
119	46	FABRICAÇÃO DE ESTRUTURAS DE MADEIRA E DE ARTIGOS DE CARPINTARIA PARA CONSTRUÇÃO
120	46	FABRICAÇÃO DE ARTEFATOS DE TANOARIA E DE EMBALAGENS DE MADEIRA
121	46	FABRICAÇÃO DE ARTEFATOS DE MADEIRA, PALHA, CORTIÇA, VIME E MATERIAL TRANÇADO NÃO ESPECIFICADOS ANTERIORMENTE, EXCETO MÓVEIS
122	47	FABRICAÇÃO DE CELULOSE E OUTRAS PASTAS PARA A FABRICAÇÃO DE PAPEL
123	48	FABRICAÇÃO DE PAPEL
124	48	FABRICAÇÃO DE CARTOLINA E PAPEL-CARTÃO
125	49	FABRICAÇÃO DE EMBALAGENS DE PAPEL
126	49	FABRICAÇÃO DE EMBALAGENS DE CARTOLINA E PAPEL-CARTÃO
127	49	FABRICAÇÃO DE CHAPAS E DE EMBALAGENS DE PAPELÃO ONDULADO
128	50	FABRICAÇÃO DE PRODUTOS DE PAPEL, CARTOLINA, PAPEL CARTÃO E PAPELÃO ONDULADO PARA USO COMERCIAL E DE ESCRITÓRIO
129	50	FABRICAÇÃO DE PRODUTOS DE PAPEL PARA USOS DOMÉSTICO E HIGIÊNICO-SANITÁRIO
130	50	FABRICAÇÃO DE PRODUTOS DE PASTAS CELULÓSICAS, PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO NÃO ESPECIFICADOS ANTERIORMENTE
131	51	IMPRESSÃO DE JORNAIS, LIVROS, REVISTAS E OUTRAS PUBLICAÇÕES PERIÓDICAS
132	51	IMPRESSÃO DE MATERIAL DE SEGURANÇA
133	51	IMPRESSÃO DE MATERIAIS PARA OUTROS USOS
134	52	SERVIÇOS DE PRÉ-IMPRESSÃO
135	52	SERVIÇOS DE ACABAMENTOS GRÁFICOS
136	53	REPRODUÇÃO DE MATERIAIS GRAVADOS EM QUALQUER SUPORTE
137	54	COQUERIAS
138	55	FABRICAÇÃO DE PRODUTOS DO REFINO DE PETRÓLEO
139	55	FABRICAÇÃO DE PRODUTOS DERIVADOS DO PETRÓLEO, EXCETO PRODUTOS DO REFINO
140	56	FABRICAÇÃO DE ÁLCOOL
141	56	FABRICAÇÃO DE BIOCOMBUSTÍVEIS, EXCETO ÁLCOOL
142	57	FABRICAÇÃO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS
143	58	FABRICAÇÃO DE CAMINHÕES E ÔNIBUS
144	59	FABRICAÇÃO DE CABINES, CARROCERIAS E REBOQUES PARA VEÍCULOS AUTOMOTORES
145	60	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA O SISTEMA MOTOR DE VEÍCULOS AUTOMOTORES
146	60	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA OS SISTEMAS DE MARCHA E TRANSMISSÃO DE VEÍCULOS AUTOMOTORES
147	60	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA O SISTEMA DE FREIOS DE VEÍCULOS AUTOMOTORES
148	60	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA O SISTEMA DE DIREÇÃO E SUSPENSÃO DE VEÍCULOS AUTOMOTORES
149	60	FABRICAÇÃO DE MATERIAL ELÉTRICO E ELETRÔNICO PARA VEÍCULOS AUTOMOTORES, EXCETO BATERIAS
150	60	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES NÃO ESPECIFICADOS ANTERIORMENTE
151	61	RECONDICIONAMENTO E RECUPERAÇÃO DE MOTORES PARA VEÍCULOS AUTOMOTORES
152	62	FABRICAÇÃO DE CLORO E ÁLCALIS
153	62	FABRICAÇÃO DE INTERMEDIÁRIOS PARA FERTILIZANTES
154	62	FABRICAÇÃO DE ADUBOS E FERTILIZANTES
155	62	FABRICAÇÃO DE GASES INDUSTRIAIS
156	62	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS NÃO ESPECIFICADOS ANTERIORMENTE
157	63	FABRICAÇÃO DE PRODUTOS PETROQUÍMICOS BÁSICOS
158	63	FABRICAÇÃO DE INTERMEDIÁRIOS PARA PLASTIFICANTES, RESINAS E FIBRAS
159	63	FABRICAÇÃO DE PRODUTOS QUÍMICOS ORGÂNICOS NÃO ESPECIFICADOS ANTERIORMENTE
160	64	FABRICAÇÃO DE ELASTÔMEROS
161	64	FABRICAÇÃO DE RESINAS TERMOPLÁSTICAS
162	64	FABRICAÇÃO DE RESINAS TERMOFIXAS
163	65	FABRICAÇÃO DE FIBRAS ARTIFICIAIS E SINTÉTICAS
164	66	FABRICAÇÃO DE DEFENSIVOS AGRÍCOLAS
165	66	FABRICAÇÃO DE DESINFESTANTES DOMISSANITÁRIOS
166	67	FABRICAÇÃO DE SABÕES E DETERGENTES SINTÉTICOS
167	67	FABRICAÇÃO DE PRODUTOS DE LIMPEZA E POLIMENTO
168	67	FABRICAÇÃO DE COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL
169	68	FABRICAÇÃO DE TINTAS, VERNIZES, ESMALTES E LACAS
170	68	FABRICAÇÃO DE TINTAS DE IMPRESSÃO
171	68	FABRICAÇÃO DE IMPERMEABILIZANTES, SOLVENTES E PRODUTOS AFINS
172	69	FABRICAÇÃO DE ADESIVOS E SELANTES
173	69	FABRICAÇÃO DE EXPLOSIVOS
174	69	FABRICAÇÃO DE ADITIVOS DE USO INDUSTRIAL
175	69	FABRICAÇÃO DE CATALISADORES
176	69	FABRICAÇÃO DE PRODUTOS QUÍMICOS NÃO ESPECIFICADOS ANTERIORMENTE
177	70	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS
178	71	FABRICAÇÃO DE MEDICAMENTOS PARA USO HUMANO
179	71	FABRICAÇÃO DE MEDICAMENTOS PARA USO VETERINÁRIO
180	71	FABRICAÇÃO DE PREPARAÇÕES FARMACÊUTICAS
181	72	FABRICAÇÃO DE PNEUMÁTICOS E DE CÂMARAS-DE-AR
182	72	REFORMA DE PNEUMÁTICOS USADOS
183	72	FABRICAÇÃO DE ARTEFATOS DE BORRACHA NÃO ESPECIFICADOS ANTERIORMENTE
184	73	FABRICAÇÃO DE LAMINADOS PLANOS E TUBULARES DE MATERIAL PLÁSTICO
185	73	FABRICAÇÃO DE EMBALAGENS DE MATERIAL PLÁSTICO
186	73	FABRICAÇÃO DE TUBOS E ACESSÓRIOS DE MATERIAL PLÁSTICO PARA USO NA CONSTRUÇÃO
187	73	FABRICAÇÃO DE ARTEFATOS DE MATERIAL PLÁSTICO NÃO ESPECIFICADOS ANTERIORMENTE
188	74	FABRICAÇÃO DE EMBALAGENS DE VIDRO
189	74	FABRICAÇÃO DE VIDRO PLANO E DE SEGURANÇA
190	74	FABRICAÇÃO DE ARTIGOS DE VIDRO
191	75	FABRICAÇÃO DE CIMENTO
192	76	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES
193	77	FABRICAÇÃO DE PRODUTOS CERÂMICOS REFRATÁRIOS
194	77	FABRICAÇÃO DE PRODUTOS CERÂMICOS NÃO-REFRATÁRIOS PARA USO ESTRUTURAL NA CONSTRUÇÃO
195	77	FABRICAÇÃO DE PRODUTOS CERÂMICOS NÃO-REFRATÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
196	78	APARELHAMENTO E OUTROS TRABALHOS EM PEDRAS
197	78	FABRICAÇÃO DE CAL E GESSO
198	78	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE
199	79	PRODUÇÃO DE FERRO-GUSA
200	79	PRODUÇÃO DE FERROLIGAS
201	80	PRODUÇÃO DE SEMI-ACABADOS DE AÇO
202	80	PRODUÇÃO DE LAMINADOS PLANOS DE AÇO
203	80	PRODUÇÃO DE LAMINADOS LONGOS DE AÇO
204	80	PRODUÇÃO DE RELAMINADOS, TREFILADOS E PERFILADOS DE AÇO
205	81	PRODUÇÃO DE CANOS E TUBOS COM COSTURA
206	81	PRODUÇÃO DE OUTROS TUBOS DE FERRO E AÇO
207	82	METALURGIA DO ALUMÍNIO E SUAS LIGAS
208	82	METALURGIA DOS METAIS PRECIOSOS
209	82	METALURGIA DO COBRE
210	82	METALURGIA DOS METAIS NÃO-FERROSOS E SUAS LIGAS NÃO ESPECIFICADOS ANTERIORMENTE
211	83	FUNDIÇÃO DE FERRO E AÇO
212	83	FUNDIÇÃO DE METAIS NÃO-FERROSOS E SUAS LIGAS
213	84	FABRICAÇÃO DE ESTRUTURAS METÁLICAS
214	84	FABRICAÇÃO DE ESQUADRIAS DE METAL
215	84	FABRICAÇÃO DE OBRAS DE CALDEIRARIA PESADA
216	85	FABRICAÇÃO DE TANQUES, RESERVATÓRIOS METÁLICOS E CALDEIRAS PARA AQUECIMENTO CENTRAL
217	85	FABRICAÇÃO DE CALDEIRAS GERADORAS DE VAPOR, EXCETO PARA AQUECIMENTO CENTRAL E PARA VEÍCULOS
218	86	PRODUÇÃO DE FORJADOS DE AÇO E DE METAIS NÃO-FERROSOS E SUAS LIGAS
219	86	PRODUÇÃO DE ARTEFATOS ESTAMPADOS DE METAL; METALURGIA DO PÓ
220	86	SERVIÇOS DE USINAGEM, SOLDA, TRATAMENTO E REVESTIMENTO EM METAIS
221	87	FABRICAÇÃO DE ARTIGOS DE CUTELARIA
222	87	FABRICAÇÃO DE ARTIGOS DE SERRALHERIA, EXCETO ESQUADRIAS
223	87	FABRICAÇÃO DE FERRAMENTAS
224	88	FABRICAÇÃO DE EQUIPAMENTO BÉLICO PESADO, ARMAS E MUNIÇÕES
225	89	FABRICAÇÃO DE EMBALAGENS METÁLICAS
226	89	FABRICAÇÃO DE PRODUTOS DE TREFILADOS DE METAL
227	89	FABRICAÇÃO DE ARTIGOS DE METAL PARA USO DOMÉSTICO E PESSOAL
228	89	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE
229	90	FABRICAÇÃO DE COMPONENTES ELETRÔNICOS
230	91	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA
231	91	FABRICAÇÃO DE PERIFÉRICOS PARA EQUIPAMENTOS DE INFORMÁTICA
232	92	FABRICAÇÃO DE EQUIPAMENTOS TRANSMISSORES DE COMUNICAÇÃO
233	92	FABRICAÇÃO DE APARELHOS TELEFÔNICOS E DE OUTROS EQUIPAMENTOS DE COMUNICAÇÃO
234	93	FABRICAÇÃO DE APARELHOS DE RECEPÇÃO, REPRODUÇÃO, GRAVAÇÃO E AMPLIFICAÇÃO DE ÁUDIO E VÍDEO
235	94	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS DE MEDIDA, TESTE E CONTROLE
236	94	FABRICAÇÃO DE CRONÔMETROS E RELÓGIOS
237	95	FABRICAÇÃO DE APARELHOS ELETROMÉDICOS E ELETROTERAPÊUTICOS E EQUIPAMENTOS DE IRRADIAÇÃO
238	96	FABRICAÇÃO DE EQUIPAMENTOS E INSTRUMENTOS ÓPTICOS, FOTOGRÁFICOS E CINEMATOGRÁFICOS
239	97	FABRICAÇÃO DE MÍDIAS VIRGENS, MAGNÉTICAS E ÓPTICAS
240	98	FABRICAÇÃO DE GERADORES, TRANSFORMADORES E MOTORES ELÉTRICOS
241	99	FABRICAÇÃO DE PILHAS, BATERIAS E ACUMULADORES ELÉTRICOS, EXCETO PARA VEÍCULOS AUTOMOTORES
242	99	FABRICAÇÃO DE BATERIAS E ACUMULADORES PARA VEÍCULOS AUTOMOTORES
243	100	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS PARA DISTRIBUIÇÃO E CONTROLE DE ENERGIA ELÉTRICA
244	100	FABRICAÇÃO DE MATERIAL ELÉTRICO PARA INSTALAÇÕES EM CIRCUITO DE CONSUMO
245	100	FABRICAÇÃO DE FIOS, CABOS E CONDUTORES ELÉTRICOS ISOLADOS
246	101	FABRICAÇÃO DE LÂMPADAS E OUTROS EQUIPAMENTOS DE ILUMINAÇÃO
247	102	FABRICAÇÃO DE FOGÕES, REFRIGERADORES E MÁQUINAS DE LAVAR E SECAR PARA USO DOMÉSTICO
248	102	FABRICAÇÃO DE APARELHOS ELETRODOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
249	103	FABRICAÇÃO DE EQUIPAMENTOS E APARELHOS ELÉTRICOS NÃO ESPECIFICADOS ANTERIORMENTE
250	104	FABRICAÇÃO DE MOTORES E TURBINAS, EXCETO PARA AVIÕES E VEÍCULOS RODOVIÁRIOS
251	104	FABRICAÇÃO DE EQUIPAMENTOS HIDRÁULICOS E PNEUMÁTICOS, EXCETO VÁLVULAS
252	104	FABRICAÇÃO DE VÁLVULAS, REGISTROS E DISPOSITIVOS SEMELHANTES
253	104	FABRICAÇÃO DE COMPRESSORES
254	104	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSMISSÃO PARA FINS INDUSTRIAIS
255	105	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS PARA INSTALAÇÕES TÉRMICAS
256	105	FABRICAÇÃO DE MÁQUINAS, EQUIPAMENTOS E APARELHOS PARA TRANSPORTE E ELEVAÇÃO DE CARGAS E PESSOAS
257	105	FABRICAÇÃO DE MÁQUINAS E APARELHOS DE REFRIGERAÇÃO E VENTILAÇÃO PARA USO INDUSTRIAL E COMERCIAL
258	105	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS DE AR CONDICIONADO
259	105	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA SANEAMENTO BÁSICO E AMBIENTAL
260	105	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL NÃO ESPECIFICADOS ANTERIORMENTE
261	106	FABRICAÇÃO DE EQUIPAMENTOS PARA IRRIGAÇÃO AGRÍCOLA
262	106	FABRICAÇÃO DE TRATORES AGRÍCOLAS
263	106	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A AGRICULTURA E PECUÁRIA, EXCETO PARA IRRIGAÇÃO
264	107	FABRICAÇÃO DE MÁQUINAS-FERRAMENTA
265	108	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A PROSPECÇÃO E EXTRAÇÃO DE PETRÓLEO
266	108	FABRICAÇÃO DE OUTRAS MÁQUINAS E EQUIPAMENTOS PARA USO NA EXTRAÇÃO MINERAL, EXCETO NA EXTRAÇÃO DE PETRÓLEO
267	108	FABRICAÇÃO DE TRATORES, EXCETO AGRÍCOLAS
268	108	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA TERRAPLENAGEM, PAVIMENTAÇÃO E CONSTRUÇÃO, EXCETO TRATORES
269	109	FABRICAÇÃO DE MÁQUINAS PARA A INDÚSTRIA METALÚRGICA, EXCETO MÁQUINAS-FERRAMENTA
270	109	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AS INDÚSTRIAS DE ALIMENTOS, BEBIDAS E FUMO
271	109	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A INDÚSTRIA TÊXTIL
272	109	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AS INDÚSTRIAS DO VESTUÁRIO, DO COURO E DE CALÇADOS
273	109	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AS INDÚSTRIAS DE CELULOSE, PAPEL E PAPELÃO E ARTEFATOS
274	109	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A INDÚSTRIA DO PLÁSTICO
275	109	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA USO INDUSTRIAL ESPECÍFICO NÃO ESPECIFICADOS ANTERIORMENTE
276	110	CONSTRUÇÃO DE EMBARCAÇÕES E ESTRUTURAS FLUTUANTES
277	110	CONSTRUÇÃO DE EMBARCAÇÕES PARA ESPORTE E LAZER
278	111	FABRICAÇÃO DE LOCOMOTIVAS, VAGÕES E OUTROS MATERIAIS RODANTES
279	111	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS FERROVIÁRIOS
280	112	FABRICAÇÃO DE AERONAVES
281	112	FABRICAÇÃO DE TURBINAS, MOTORES E OUTROS COMPONENTES E PEÇAS PARA AERONAVES
282	113	FABRICAÇÃO DE VEÍCULOS MILITARES DE COMBATE
283	114	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSPORTE NÃO ESPECIFICADOS ANTERIORMENTE
284	114	FABRICAÇÃO DE MOTOCICLETAS
285	114	FABRICAÇÃO DE BICICLETAS E TRICICLOS NÃO-MOTORIZADOS
286	115	FABRICAÇÃO DE MÓVEIS COM PREDOMINÂNCIA DE MADEIRA
287	115	FABRICAÇÃO DE MÓVEIS COM PREDOMINÂNCIA DE METAL
288	115	FABRICAÇÃO DE MÓVEIS DE OUTROS MATERIAIS, EXCETO MADEIRA E METAL
289	115	FABRICAÇÃO DE COLCHÕES
290	116	LAPIDAÇÃO DE GEMAS E FABRICAÇÃO DE ARTEFATOS DE OURIVESARIA E JOALHERIA
291	116	FABRICAÇÃO DE BIJUTERIAS E ARTEFATOS SEMELHANTES
292	117	FABRICAÇÃO DE INSTRUMENTOS MUSICAIS
293	118	FABRICAÇÃO DE ARTEFATOS PARA PESCA E ESPORTE
294	119	FABRICAÇÃO DE BRINQUEDOS E JOGOS RECREATIVOS
295	120	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS
296	121	FABRICAÇÃO DE ESCOVAS, PINCÉIS E VASSOURAS
297	121	FABRICAÇÃO DE EQUIPAMENTOS E ACESSÓRIOS PARA SEGURANÇA E PROTEÇÃO PESSOAL E PROFISSIONAL
298	121	FABRICAÇÃO DE PRODUTOS DIVERSOS NÃO ESPECIFICADOS ANTERIORMENTE
299	122	MANUTENÇÃO E REPARAÇÃO DE TANQUES, RESERVATÓRIOS METÁLICOS E CALDEIRAS, EXCETO PARA VEÍCULOS
300	122	MANUTENÇÃO E REPARAÇÃO DE EQUIPAMENTOS ELETRÔNICOS E ÓPTICOS
301	122	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS ELÉTRICOS
302	122	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DA INDÚSTRIA MECÂNICA
303	122	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS FERROVIÁRIOS
304	122	MANUTENÇÃO E REPARAÇÃO DE AERONAVES
305	122	MANUTENÇÃO E REPARAÇÃO DE EMBARCAÇÕES
306	122	MANUTENÇÃO E REPARAÇÃO DE EQUIPAMENTOS E PRODUTOS NÃO ESPECIFICADOS ANTERIORMENTE
307	123	INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS INDUSTRIAIS
308	123	INSTALAÇÃO DE EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE
309	124	GERAÇÃO DE ENERGIA ELÉTRICA
310	124	TRANSMISSÃO DE ENERGIA ELÉTRICA
311	124	COMÉRCIO ATACADISTA DE ENERGIA ELÉTRICA
312	124	DISTRIBUIÇÃO DE ENERGIA ELÉTRICA
313	125	PRODUÇÃO DE GÁS; PROCESSAMENTO DE GÁS NATURAL; DISTRIBUIÇÃO DE COMBUSTÍVEIS GASOSOS POR REDES URBANAS
314	126	PRODUÇÃO E DISTRIBUIÇÃO DE VAPOR, ÁGUA QUENTE E AR CONDICIONADO
315	127	CAPTAÇÃO, TRATAMENTO E DISTRIBUIÇÃO DE ÁGUA
316	128	GESTÃO DE REDES DE ESGOTO
317	128	ATIVIDADES RELACIONADAS A ESGOTO, EXCETO A GESTÃO DE REDES
318	129	COLETA DE RESÍDUOS NÃO-PERIGOSOS
319	129	COLETA DE RESÍDUOS PERIGOSOS
320	130	TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS NÃO-PERIGOSOS
321	130	TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS PERIGOSOS
322	131	RECUPERAÇÃO DE MATERIAIS METÁLICOS
323	131	RECUPERAÇÃO DE MATERIAIS PLÁSTICOS
324	131	RECUPERAÇÃO DE MATERIAIS NÃO ESPECIFICADOS ANTERIORMENTE
325	132	DESCONTAMINAÇÃO E OUTROS SERVIÇOS DE GESTÃO DE RESÍDUOS
326	133	INCORPORAÇÃO DE EMPREENDIMENTOS IMOBILIÁRIOS
327	134	CONSTRUÇÃO DE EDIFÍCIOS
328	135	CONSTRUÇÃO DE RODOVIAS E FERROVIAS
329	135	CONSTRUÇÃO DE OBRAS-DE-ARTE ESPECIAIS
330	135	OBRAS DE URBANIZAÇÃO - RUAS, PRAÇAS E CALÇADAS
331	136	CONSTRUÇÃO DE REDES DE TRANSPORTES POR DUTOS, EXCETO PARA ÁGUA E ESGOTO
332	136	OBRAS PARA GERAÇÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA E PARA TELECOMUNICAÇÕES
333	136	CONSTRUÇÃO DE REDES DE ABASTECIMENTO DE ÁGUA, COLETA DE ESGOTO E CONSTRUÇÕES CORRELATAS
334	137	OBRAS PORTUÁRIAS, MARÍTIMAS E FLUVIAIS
335	137	MONTAGEM DE INSTALAÇÕES INDUSTRIAIS E DE ESTRUTURAS METÁLICAS
336	137	OBRAS DE ENGENHARIA CIVIL NÃO ESPECIFICADAS ANTERIORMENTE
337	138	ARMAZENAMENTO
338	138	CARGA E DESCARGA
339	139	CONCESSIONÁRIAS DE RODOVIAS, PONTES, TÚNEIS E SERVIÇOS RELACIONADOS
340	139	TERMINAIS RODOVIÁRIOS E FERROVIÁRIOS
341	139	ESTACIONAMENTO DE VEÍCULOS
342	139	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES NÃO ESPECIFICADAS ANTERIORMENTE
343	140	GESTÃO DE PORTOS E TERMINAIS
344	140	ATIVIDADES DE AGENCIAMENTO MARÍTIMO
345	140	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS NÃO ESPECIFICADAS ANTERIORMENTE
346	141	ATIVIDADES AUXILIARES DOS TRANSPORTES AÉREOS
347	142	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA
348	143	ATIVIDADES DE CORREIO
349	144	ATIVIDADES DE MALOTE E DE ENTREGA
350	145	HOTÉIS E SIMILARES
351	146	OUTROS TIPOS DE ALOJAMENTO NÃO ESPECIFICADOS ANTERIORMENTE
352	147	RESTAURANTES E OUTROS ESTABELECIMENTOS DE SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS
353	147	SERVIÇOS AMBULANTES DE ALIMENTAÇÃO
354	148	SERVIÇOS DE CATERING, BUFÊ E OUTROS SERVIÇOS DE COMIDA PREPARADA
355	149	DEMOLIÇÃO E PREPARAÇÃO DE CANTEIROS DE OBRAS
356	149	PERFURAÇÕES E SONDAGENS
357	149	OBRAS DE TERRAPLENAGEM
358	149	SERVIÇOS DE PREPARAÇÃO DO TERRENO NÃO ESPECIFICADOS ANTERIORMENTE
359	150	INSTALAÇÕES ELÉTRICAS
360	150	INSTALAÇÕES HIDRÁULICAS, DE SISTEMAS DE VENTILAÇÃO E REFRIGERAÇÃO
361	150	OBRAS DE INSTALAÇÕES EM CONSTRUÇÕES NÃO ESPECIFICADAS ANTERIORMENTE
362	151	OBRAS DE ACABAMENTO
363	152	OBRAS DE FUNDAÇÕES
364	152	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE
365	153	COMÉRCIO A VAREJO E POR ATACADO DE VEÍCULOS AUTOMOTORES
366	153	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE VEÍCULOS AUTOMOTORES
367	154	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES
368	155	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES
369	156	COMÉRCIO POR ATACADO E A VAREJO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
370	156	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
371	156	MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS
372	157	ATIVIDADES DE RÁDIO
373	158	ATIVIDADES DE TELEVISÃO ABERTA
374	158	PROGRAMADORAS E ATIVIDADES RELACIONADAS À TELEVISÃO POR ASSINATURA
375	159	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS
376	159	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE COMBUSTÍVEIS, MINERAIS, PRODUTOS SIDERÚRGICOS E QUÍMICOS
377	159	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MADEIRA, MATERIAL DE CONSTRUÇÃO E FERRAGENS
378	159	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MÁQUINAS, EQUIPAMENTOS, EMBARCAÇÕES E AERONAVES
379	159	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE ELETRODOMÉSTICOS, MÓVEIS E ARTIGOS DE USO DOMÉSTICO
380	159	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE TÊXTEIS, VESTUÁRIO, CALÇADOS E ARTIGOS DE VIAGEM
381	159	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO
382	159	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO ESPECIALIZADO EM PRODUTOS NÃO ESPECIFICADOS ANTERIORMENTE
383	159	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MERCADORIAS EM GERAL NÃO ESPECIALIZADO
384	160	COMÉRCIO ATACADISTA DE CAFÉ EM GRÃO
385	160	COMÉRCIO ATACADISTA DE SOJA
386	160	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS, ALIMENTOS PARA ANIMAIS E MATÉRIAS-PRIMAS AGRÍCOLAS, EXCETO CAFÉ E SOJA
387	161	COMÉRCIO ATACADISTA DE LEITE E LATICÍNIOS
388	161	COMÉRCIO ATACADISTA DE CEREAIS E LEGUMINOSAS BENEFICIADOS, FARINHAS, AMIDOS E FÉCULAS
389	161	COMÉRCIO ATACADISTA DE HORTIFRUTIGRANJEIROS
390	161	COMÉRCIO ATACADISTA DE CARNES, PRODUTOS DA CARNE E PESCADO
391	161	COMÉRCIO ATACADISTA DE BEBIDAS
392	161	COMÉRCIO ATACADISTA DE PRODUTOS DO FUMO
393	161	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
394	161	COMÉRCIO ATACADISTA DE PRODUTOS ALIMENTÍCIOS EM GERAL
395	162	COMÉRCIO ATACADISTA DE COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL
396	162	COMÉRCIO ATACADISTA DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO, CIRÚRGICO, ORTOPÉDICO E ODONTOLÓGICO
397	162	COMÉRCIO ATACADISTA DE TECIDOS, ARTEFATOS DE TECIDOS E DE ARMARINHO
398	162	COMÉRCIO ATACADISTA DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS
399	162	COMÉRCIO ATACADISTA DE CALÇADOS E ARTIGOS DE VIAGEM
400	162	COMÉRCIO ATACADISTA DE PRODUTOS FARMACÊUTICOS PARA USO HUMANO E VETERINÁRIO
401	162	COMÉRCIO ATACADISTA DE ARTIGOS DE ESCRITÓRIO E DE PAPELARIA; LIVROS, JORNAIS E OUTRAS PUBLICAÇÕES
402	162	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
403	163	COMÉRCIO ATACADISTA DE COMPUTADORES, PERIFÉRICOS E SUPRIMENTOS DE INFORMÁTICA
404	163	COMÉRCIO ATACADISTA DE COMPONENTES ELETRÔNICOS E EQUIPAMENTOS DE TELEFONIA E COMUNICAÇÃO
405	164	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS PARA USO AGROPECUÁRIO; PARTES E PEÇAS
406	164	COMÉRCIO ATACADISTA DE MÁQUINAS, EQUIPAMENTOS PARA TERRAPLENAGEM, MINERAÇÃO E CONSTRUÇÃO; PARTES E PEÇAS
407	164	COMÉRCIO ATACADISTA DE MÁQUINAS E EQUIPAMENTOS PARA USO INDUSTRIAL; PARTES E PEÇAS
408	164	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS PARA USO ODONTO-MÉDICO-HOSPITALAR; PARTES E PEÇAS
409	164	COMÉRCIO ATACADISTA DE MÁQUINAS E EQUIPAMENTOS PARA USO COMERCIAL; PARTES E PEÇAS
410	164	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE; PARTES E PEÇAS
411	165	COMÉRCIO ATACADISTA DE MADEIRA E PRODUTOS DERIVADOS
412	165	COMÉRCIO ATACADISTA DE FERRAGENS E FERRAMENTAS
413	165	COMÉRCIO ATACADISTA DE MATERIAL ELÉTRICO
414	165	COMÉRCIO ATACADISTA DE CIMENTO
415	165	COMÉRCIO ATACADISTA ESPECIALIZADO DE MATERIAIS DE CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE E DE MATERIAIS DE CONSTRUÇÃO EM GERAL
416	166	COMÉRCIO ATACADISTA DE COMBUSTÍVEIS SÓLIDOS, LÍQUIDOS E GASOSOS, EXCETO GÁS NATURAL E GLP
417	166	COMÉRCIO ATACADISTA DE GÁS LIQUEFEITO DE PETRÓLEO (GLP)
418	166	COMÉRCIO ATACADISTA DE DEFENSIVOS AGRÍCOLAS, ADUBOS, FERTILIZANTES E CORRETIVOS DO SOLO
419	166	COMÉRCIO ATACADISTA DE PRODUTOS QUÍMICOS E PETROQUÍMICOS, EXCETO AGROQUÍMICOS
420	166	COMÉRCIO ATACADISTA DE PRODUTOS SIDERÚRGICOS E METALÚRGICOS, EXCETO PARA CONSTRUÇÃO
421	166	COMÉRCIO ATACADISTA DE PAPEL E PAPELÃO EM BRUTO E DE EMBALAGENS
422	166	COMÉRCIO ATACADISTA DE RESÍDUOS E SUCATAS
423	166	COMÉRCIO ATACADISTA ESPECIALIZADO DE OUTROS PRODUTOS INTERMEDIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
424	167	COMÉRCIO ATACADISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS
425	167	COMÉRCIO ATACADISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE INSUMOS AGROPECUÁRIOS
426	167	COMÉRCIO ATACADISTA DE MERCADORIAS EM GERAL, SEM PREDOMINÂNCIA DE ALIMENTOS OU DE INSUMOS AGROPECUÁRIOS
427	168	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS - HIPERMERCADOS E SUPERMERCADOS
428	168	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS - MINIMERCADOS, MERCEARIAS E ARMAZÉNS
429	168	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, SEM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS
430	169	COMÉRCIO VAREJISTA DE CARNES E PESCADOS - AÇOUGUES E PEIXARIAS
431	169	COMÉRCIO VAREJISTA DE BEBIDAS
432	169	COMÉRCIO VAREJISTA DE HORTIFRUTIGRANJEIROS
433	169	COMÉRCIO VAREJISTA DE PRODUTOS DE PADARIA, LATICÍNIO, DOCES, BALAS E SEMELHANTES
434	169	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS EM GERAL OU ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE; PRODUTOS DO FUMO
435	170	COMÉRCIO VAREJISTA DE COMBUSTÍVEIS PARA VEÍCULOS AUTOMOTORES
436	170	COMÉRCIO VAREJISTA DE LUBRIFICANTES
437	171	COMÉRCIO VAREJISTA DE TINTAS E MATERIAIS PARA PINTURA
438	171	COMÉRCIO VAREJISTA DE MATERIAL ELÉTRICO
439	171	COMÉRCIO VAREJISTA DE VIDROS
440	171	COMÉRCIO VAREJISTA DE FERRAGENS, MADEIRA E MATERIAIS DE CONSTRUÇÃO
441	172	COMÉRCIO VAREJISTA ESPECIALIZADO DE PEÇAS E ACESSÓRIOS PARA APARELHOS ELETROELETRÔNICOS PARA USO DOMÉSTICO, EXCETO INFORMÁTICA E COMUNICAÇÃO
442	172	COMÉRCIO VAREJISTA ESPECIALIZADO DE TECIDOS E ARTIGOS DE CAMA, MESA E BANHO
443	172	COMÉRCIO VAREJISTA ESPECIALIZADO DE INSTRUMENTOS MUSICAIS E ACESSÓRIOS
444	172	COMÉRCIO VAREJISTA ESPECIALIZADO DE EQUIPAMENTOS E SUPRIMENTOS DE INFORMÁTICA
445	172	COMÉRCIO VAREJISTA ESPECIALIZADO DE EQUIPAMENTOS DE TELEFONIA E COMUNICAÇÃO
446	172	COMÉRCIO VAREJISTA ESPECIALIZADO DE ELETRODOMÉSTICOS E EQUIPAMENTOS DE ÁUDIO E VÍDEO
447	172	COMÉRCIO VAREJISTA ESPECIALIZADO DE MÓVEIS, COLCHOARIA E ARTIGOS DE ILUMINAÇÃO
448	172	COMÉRCIO VAREJISTA DE ARTIGOS DE USO DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
449	173	COMÉRCIO VAREJISTA DE LIVROS, JORNAIS, REVISTAS E PAPELARIA
450	173	COMÉRCIO VAREJISTA DE DISCOS, CDS, DVDS E FITAS
451	173	COMÉRCIO VAREJISTA DE ARTIGOS RECREATIVOS E ESPORTIVOS
452	174	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS PARA USO HUMANO E VETERINÁRIO
453	174	COMÉRCIO VAREJISTA DE COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL
454	174	COMÉRCIO VAREJISTA DE ARTIGOS MÉDICOS E ORTOPÉDICOS
455	174	COMÉRCIO VAREJISTA DE ARTIGOS DE ÓPTICA
456	175	COMÉRCIO VAREJISTA DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS
457	175	COMÉRCIO VAREJISTA DE CALÇADOS E ARTIGOS DE VIAGEM
458	175	COMÉRCIO VAREJISTA DE JÓIAS E RELÓGIOS
459	175	COMÉRCIO VAREJISTA DE GÁS LIQUEFEITO DE PETRÓLEO (GLP)
460	175	COMÉRCIO VAREJISTA DE ARTIGOS USADOS
461	175	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE
462	176	TRANSPORTE FERROVIÁRIO DE CARGA
463	176	TRANSPORTE METROFERROVIÁRIO DE PASSAGEIROS
464	177	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, MUNICIPAL E EM REGIÃO METROPOLITANA
465	177	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL
466	177	TRANSPORTE RODOVIÁRIO DE TÁXI
467	177	TRANSPORTE ESCOLAR
468	177	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, SOB REGIME DE FRETAMENTO, E OUTROS TRANSPORTES RODOVIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
469	178	TRANSPORTE RODOVIÁRIO DE CARGA
470	179	TRANSPORTE DUTOVIÁRIO
471	180	TRENS TURÍSTICOS, TELEFÉRICOS E SIMILARES
472	181	TRANSPORTE MARÍTIMO DE CABOTAGEM
473	181	TRANSPORTE MARÍTIMO DE LONGO CURSO
474	182	TRANSPORTE POR NAVEGAÇÃO INTERIOR DE PASSAGEIROS EM LINHAS REGULARES
475	182	TRANSPORTE POR NAVEGAÇÃO INTERIOR DE CARGA
476	183	NAVEGAÇÃO DE APOIO
477	184	TRANSPORTE POR NAVEGAÇÃO DE TRAVESSIA
478	184	TRANSPORTES AQUAVIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
479	185	TRANSPORTE AÉREO DE PASSAGEIROS REGULAR
480	185	TRANSPORTE AÉREO DE PASSAGEIROS NÃO-REGULAR
481	186	TRANSPORTE AÉREO DE CARGA
482	187	TRANSPORTE ESPACIAL
483	188	SERVIÇOS DE ARQUITETURA
484	188	SERVIÇOS DE ENGENHARIA
485	188	ATIVIDADES TÉCNICAS RELACIONADAS À ARQUITETURA E ENGENHARIA
486	189	TESTES E ANÁLISES TÉCNICAS
487	190	EDIÇÃO DE LIVROS
488	190	EDIÇÃO DE JORNAIS
489	190	EDIÇÃO DE REVISTAS
490	190	EDIÇÃO DE CADASTROS, LISTAS E DE OUTROS PRODUTOS GRÁFICOS
491	191	EDIÇÃO INTEGRADA À IMPRESSÃO DE LIVROS
492	191	EDIÇÃO INTEGRADA À IMPRESSÃO DE JORNAIS
493	191	EDIÇÃO INTEGRADA À IMPRESSÃO DE REVISTAS
494	191	EDIÇÃO INTEGRADA À IMPRESSÃO DE CADASTROS, LISTAS E DE OUTROS PRODUTOS GRÁFICOS
495	192	ATIVIDADES DE PRODUÇÃO CINEMATOGRÁFICA, DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO
496	192	ATIVIDADES DE PÓS-PRODUÇÃO CINEMATOGRÁFICA, DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO
497	192	DISTRIBUIÇÃO CINEMATOGRÁFICA, DE VÍDEO E DE PROGRAMAS DE TELEVISÃO
498	192	ATIVIDADES DE EXIBIÇÃO CINEMATOGRÁFICA
499	193	ATIVIDADES DE GRAVAÇÃO DE SOM E DE EDIÇÃO DE MÚSICA
500	194	TELECOMUNICAÇÕES POR FIO
501	195	TELECOMUNICAÇÕES SEM FIO
502	196	TELECOMUNICAÇÕES POR SATÉLITE
503	197	OPERADORAS DE TELEVISÃO POR ASSINATURA POR CABO
504	197	OPERADORAS DE TELEVISÃO POR ASSINATURA POR MICROONDAS
505	197	OPERADORAS DE TELEVISÃO POR ASSINATURA POR SATÉLITE
506	198	OUTRAS ATIVIDADES DE TELECOMUNICAÇÕES
507	199	DESENVOLVIMENTO DE PROGRAMAS DE COMPUTADOR SOB ENCOMENDA
508	199	DESENVOLVIMENTO E LICENCIAMENTO DE PROGRAMAS DE COMPUTADOR CUSTOMIZÁVEIS
509	199	DESENVOLVIMENTO E LICENCIAMENTO DE PROGRAMAS DE COMPUTADOR NÃO-CUSTOMIZÁVEIS
510	199	CONSULTORIA EM TECNOLOGIA DA INFORMAÇÃO
511	199	SUPORTE TÉCNICO, MANUTENÇÃO E OUTROS SERVIÇOS EM TECNOLOGIA DA INFORMAÇÃO
512	200	TRATAMENTO DE DADOS, PROVEDORES DE SERVIÇOS DE APLICAÇÃO E SERVIÇOS DE HOSPEDAGEM NA INTERNET
513	200	PORTAIS, PROVEDORES DE CONTEÚDO E OUTROS SERVIÇOS DE INFORMAÇÃO NA INTERNET
514	201	AGÊNCIAS DE NOTÍCIAS
515	201	OUTRAS ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO NÃO ESPECIFICADAS ANTERIORMENTE
516	202	BANCO CENTRAL
517	203	CAIXAS ECONÔMICAS
518	203	BANCOS MÚLTIPLOS, COM CARTEIRA COMERCIAL
519	203	BANCOS COMERCIAIS
520	203	CRÉDITO COOPERATIVO
521	204	BANCOS MÚLTIPLOS, SEM CARTEIRA COMERCIAL
522	204	BANCOS DE INVESTIMENTO
523	204	BANCOS DE DESENVOLVIMENTO
524	204	AGÊNCIAS DE FOMENTO
525	204	CRÉDITO IMOBILIÁRIO
526	204	SOCIEDADES DE CRÉDITO, FINANCIAMENTO E INVESTIMENTO - FINANCEIRAS
527	204	SOCIEDADES DE CRÉDITO AO MICROEMPREENDEDOR
528	204	BANCOS DE CAMBIO E OUTRAS INSTITUIÇÕES DE INTERMEDIAÇÃO NÃO-MONETÁRIA
529	205	ARRENDAMENTO MERCANTIL
530	206	SOCIEDADES DE CAPITALIZAÇÃO
531	207	HOLDINGS DE INSTITUIÇÕES FINANCEIRAS
532	207	HOLDINGS DE INSTITUIÇÕES NÃO-FINANCEIRAS
533	207	OUTRAS SOCIEDADES DE PARTICIPAÇÃO, EXCETO HOLDINGS
534	208	FUNDOS DE INVESTIMENTO
535	209	SOCIEDADES DE FOMENTO MERCANTIL - FACTORING
536	209	SECURITIZAÇÃO DE CRÉDITOS
537	209	ADMINISTRAÇÃO DE CONSÓRCIOS PARA AQUISIÇÃO DE BENS E DIREITOS
538	209	OUTRAS ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
539	210	SEGUROS DE VIDA
540	210	SEGUROS NÃO-VIDA
541	211	SEGUROS-SAÚDE
542	212	RESSEGUROS
543	213	PREVIDÊNCIA COMPLEMENTAR FECHADA
544	213	PREVIDÊNCIA COMPLEMENTAR ABERTA
545	214	PLANOS DE SAÚDE
546	215	ADMINISTRAÇÃO DE BOLSAS E MERCADOS DE BALCÃO ORGANIZADOS
547	215	ATIVIDADES DE INTERMEDIÁRIOS EM TRANSAÇÕES DE TÍTULOS, VALORES MOBILIÁRIOS E MERCADORIAS
548	215	ADMINISTRAÇÃO DE CARTÕES DE CRÉDITO
549	215	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
550	216	AVALIAÇÃO DE RISCOS E PERDAS
551	216	CORRETORES E AGENTES DE SEGUROS, DE PLANOS DE PREVIDÊNCIA COMPLEMENTAR E DE SAÚDE
552	216	ATIVIDADES AUXILIARES DOS SEGUROS, DA PREVIDÊNCIA COMPLEMENTAR E DOS PLANOS DE SAÚDE NÃO ESPECIFICADAS ANTERIORMENTE
553	217	ATIVIDADES DE ADMINISTRAÇÃO DE FUNDOS POR CONTRATO OU COMISSÃO
554	218	ATIVIDADES IMOBILIÁRIAS DE IMÓVEIS PRÓPRIOS
555	219	INTERMEDIAÇÃO NA COMPRA, VENDA E ALUGUEL DE IMÓVEIS
556	219	GESTÃO E ADMINISTRAÇÃO DA PROPRIEDADE IMOBILIÁRIA
557	220	ATIVIDADES JURÍDICAS, EXCETO CARTÓRIOS
558	220	CARTÓRIOS
559	221	ATIVIDADES DE CONTABILIDADE, CONSULTORIA E AUDITORIA CONTÁBIL E TRIBUTÁRIA
560	222	ATIVIDADES DE CONSULTORIA EM GESTÃO EMPRESARIAL
561	223	PESQUISA E DESENVOLVIMENTO EXPERIMENTAL EM CIÊNCIAS FÍSICAS E NATURAIS
562	224	PESQUISA E DESENVOLVIMENTO EXPERIMENTAL EM CIÊNCIAS SOCIAIS E HUMANAS
563	225	AGÊNCIAS DE PUBLICIDADE
564	225	AGENCIAMENTO DE ESPAÇOS PARA PUBLICIDADE, EXCETO EM VEÍCULOS DE COMUNICAÇÃO
565	225	ATIVIDADES DE PUBLICIDADE NÃO ESPECIFICADAS ANTERIORMENTE
566	226	PESQUISAS DE MERCADO E DE OPINIÃO PÚBLICA
567	227	DESIGN E DECORAÇÃO DE INTERIORES
568	228	ATIVIDADES FOTOGRÁFICAS E SIMILARES
569	229	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE
570	230	ATIVIDADES VETERINÁRIAS
571	231	ATIVIDADES DE BIBLIOTECAS E ARQUIVOS
572	231	ATIVIDADES DE MUSEUS E DE EXPLORAÇÃO, RESTAURAÇÃO ARTÍSTICA E CONSERVAÇÃO DE LUGARES E PRÉDIOS HISTÓRICOS E ATRAÇÕES SIMILARES
573	231	ATIVIDADES DE JARDINS BOTÂNICOS, ZOOLÓGICOS, PARQUES NACIONAIS, RESERVAS ECOLÓGICAS E ÁREAS DE PROTEÇÃO AMBIENTAL
574	232	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS
575	233	LOCAÇÃO DE AUTOMÓVEIS SEM CONDUTOR
576	233	LOCAÇÃO DE MEIOS DE TRANSPORTE, EXCETO AUTOMÓVEIS, SEM CONDUTOR
577	234	ALUGUEL DE EQUIPAMENTOS RECREATIVOS E ESPORTIVOS
578	234	ALUGUEL DE FITAS DE VÍDEO, DVDS E SIMILARES
579	234	ALUGUEL DE OBJETOS DO VESTUÁRIO, JÓIAS E ACESSÓRIOS
580	234	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
581	235	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS AGRÍCOLAS SEM OPERADOR
582	235	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS PARA CONSTRUÇÃO SEM OPERADOR
583	235	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS PARA ESCRITÓRIOS
584	235	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE
585	236	GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS
586	237	SELEÇÃO E AGENCIAMENTO DE MÃO-DE-OBRA
587	238	LOCAÇÃO DE MÃO-DE-OBRA TEMPORÁRIA
588	239	FORNECIMENTO E GESTÃO DE RECURSOS HUMANOS PARA TERCEIROS
589	240	AGÊNCIAS DE VIAGENS
590	240	OPERADORES TURÍSTICOS
591	241	SERVIÇOS DE RESERVAS E OUTROS SERVIÇOS DE TURISMO NÃO ESPECIFICADOS ANTERIORMENTE
592	242	ATIVIDADES DE VIGILÂNCIA E SEGURANÇA PRIVADA
593	242	ATIVIDADES DE TRANSPORTE DE VALORES
594	243	ATIVIDADES DE MONITORAMENTO DE SISTEMAS DE SEGURANÇA
595	244	ATIVIDADES DE INVESTIGAÇÃO PARTICULAR
596	245	SERVIÇOS COMBINADOS PARA APOIO A EDIFÍCIOS, EXCETO CONDOMÍNIOS PREDIAIS
597	245	CONDOMÍNIOS PREDIAIS
598	246	LIMPEZA EM PRÉDIOS E EM DOMICÍLIOS
599	246	IMUNIZAÇÃO E CONTROLE DE PRAGAS URBANAS
600	246	ATIVIDADES DE LIMPEZA NÃO ESPECIFICADAS ANTERIORMENTE
601	247	ATIVIDADES PAISAGÍSTICAS
602	248	SERVIÇOS COMBINADOS DE ESCRITÓRIO E APOIO ADMINISTRATIVO
603	248	FOTOCÓPIAS, PREPARAÇÃO DE DOCUMENTOS E OUTROS SERVIÇOS ESPECIALIZADOS DE APOIO ADMINISTRATIVO
604	249	ATIVIDADES DE TELEATENDIMENTO
605	250	ATIVIDADES DE ORGANIZAÇÃO DE EVENTOS, EXCETO CULTURAIS E ESPORTIVOS
606	251	ATIVIDADES DE COBRANÇAS E INFORMAÇÕES CADASTRAIS
607	251	ENVASAMENTO E EMPACOTAMENTO SOB CONTRATO
608	251	ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE
609	252	ADMINISTRAÇÃO PÚBLICA EM GERAL
610	252	REGULAÇÃO DAS ATIVIDADES DE SAÚDE, EDUCAÇÃO, SERVIÇOS CULTURAIS E OUTROS SERVIÇOS SOCIAIS
611	252	REGULAÇÃO DAS ATIVIDADES ECONÔMICAS
612	253	RELAÇÕES EXTERIORES
613	253	DEFESA
614	253	JUSTIÇA
615	253	SEGURANÇA E ORDEM PÚBLICA
616	253	DEFESA CIVIL
617	254	SEGURIDADE SOCIAL OBRIGATÓRIA
618	255	EDUCAÇÃO INFANTIL - CRECHE
619	255	EDUCAÇÃO INFANTIL - PRÉ-ESCOLA
620	255	ENSINO FUNDAMENTAL
621	256	ENSINO MÉDIO
622	257	EDUCAÇÃO SUPERIOR - PÓS-GRADUAÇÃO E EXTENSÃO
623	257	EDUCAÇÃO SUPERIOR - GRADUAÇÃO
624	257	EDUCAÇÃO SUPERIOR - GRADUAÇÃO E PÓS-GRADUAÇÃO
625	258	EDUCAÇÃO PROFISSIONAL DE NÍVEL TÉCNICO
626	258	EDUCAÇÃO PROFISSIONAL DE NÍVEL TECNOLÓGICO
627	259	ATIVIDADES DE APOIO À EDUCAÇÃO
628	260	ENSINO DE ESPORTES
629	260	ENSINO DE ARTE E CULTURA
630	260	ENSINO DE IDIOMAS
631	260	ATIVIDADES DE ENSINO NÃO ESPECIFICADAS ANTERIORMENTE
632	261	ATIVIDADES DE ATENDIMENTO HOSPITALAR
633	262	SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS
634	262	SERVIÇOS DE REMOÇÃO DE PACIENTES, EXCETO OS SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS
635	263	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS
636	264	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
637	265	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS
638	266	ATIVIDADES DE APOIO À GESTÃO DE SAÚDE
639	267	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE
640	268	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
641	268	ATIVIDADES DE FORNECIMENTO DE INFRA-ESTRUTURA DE APOIO E ASSISTÊNCIA A PACIENTE NO DOMICÍLIO
642	269	ATIVIDADES DE ASSISTÊNCIA PSICOSSOCIAL E À SAÚDE A PORTADORES DE DISTÚRBIOS PSÍQUICOS, DEFICIÊNCIA MENTAL E DEPENDÊNCIA QUÍMICA
643	270	ATIVIDADES DE ASSISTÊNCIA SOCIAL PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
644	271	SERVIÇOS DE ASSISTÊNCIA SOCIAL SEM ALOJAMENTO
645	272	ARTES CÊNICAS, ESPETÁCULOS E ATIVIDADES COMPLEMENTARES
646	272	CRIAÇÃO ARTÍSTICA
647	272	GESTÃO DE ESPAÇOS PARA ARTES CÊNICAS, ESPETÁCULOS E OUTRAS ATIVIDADES ARTÍSTICAS
648	273	GESTÃO DE INSTALAÇÕES DE ESPORTES
649	273	CLUBES SOCIAIS, ESPORTIVOS E SIMILARES
650	273	ATIVIDADES DE CONDICIONAMENTO FÍSICO
651	273	ATIVIDADES ESPORTIVAS NÃO ESPECIFICADAS ANTERIORMENTE
652	274	PARQUES DE DIVERSÃO E PARQUES TEMÁTICOS
653	274	ATIVIDADES DE RECREAÇÃO E LAZER NÃO ESPECIFICADAS ANTERIORMENTE
654	275	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS PATRONAIS E EMPRESARIAIS
655	275	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS PROFISSIONAIS
656	276	ATIVIDADES DE ORGANIZAÇÕES SINDICAIS
657	277	ATIVIDADES DE ASSOCIAÇÕES DE DEFESA DE DIREITOS SOCIAIS
658	278	ATIVIDADES DE ORGANIZAÇÕES RELIGIOSAS
659	278	ATIVIDADES DE ORGANIZAÇÕES POLÍTICAS
660	278	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS LIGADAS À CULTURA E À ARTE
661	278	ATIVIDADES ASSOCIATIVAS NÃO ESPECIFICADAS ANTERIORMENTE
662	279	REPARAÇÃO E MANUTENÇÃO DE COMPUTADORES E DE EQUIPAMENTOS PERIFÉRICOS
663	279	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE COMUNICAÇÃO
664	280	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS ELETROELETRÔNICOS DE USO PESSOAL E DOMÉSTICO
665	280	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
666	281	LAVANDERIAS, TINTURARIAS E TOALHEIROS
667	281	CABELEIREIROS E OUTRAS ATIVIDADES DE TRATAMENTO DE BELEZA
668	281	ATIVIDADES FUNERÁRIAS E SERVIÇOS RELACIONADOS
669	281	ATIVIDADES DE SERVIÇOS PESSOAIS NÃO ESPECIFICADAS ANTERIORMENTE
670	282	SERVIÇOS DOMÉSTICOS
671	283	ORGANISMOS INTERNACIONAIS E OUTRAS INSTITUIÇÕES EXTRATERRITORIAIS
\.


--
-- TOC entry 4877 (class 0 OID 28967)
-- Dependencies: 253
-- Data for Name: ibge_cnae_divisao; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ibge_cnae_divisao (id, secao_id, nome) FROM stdin;
1	1	AGRICULTURA, PECUÁRIA E SERVIÇOS RELACIONADOS
2	1	PRODUÇÃO FLORESTAL
3	1	PESCA E AQUICULTURA
4	2	EXTRAÇÃO DE CARVÃO MINERAL
5	2	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL
6	2	EXTRAÇÃO DE MINERAIS METÁLICOS
7	2	EXTRAÇÃO DE MINERAIS NÃO-METÁLICOS
8	2	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS
9	3	FABRICAÇÃO DE PRODUTOS ALIMENTÍCIOS
10	3	FABRICAÇÃO DE BEBIDAS
11	3	FABRICAÇÃO DE PRODUTOS DO FUMO
12	3	FABRICAÇÃO DE PRODUTOS TÊXTEIS
13	3	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS
14	3	PREPARAÇÃO DE COUROS E FABRICAÇÃO DE ARTEFATOS DE COURO, ARTIGOS PARA VIAGEM E CALÇADOS
15	3	FABRICAÇÃO DE PRODUTOS DE MADEIRA
16	3	FABRICAÇÃO DE CELULOSE, PAPEL E PRODUTOS DE PAPEL
17	3	IMPRESSÃO E REPRODUÇÃO DE GRAVAÇÕES
18	3	FABRICAÇÃO DE COQUE, DE PRODUTOS DERIVADOS DO PETRÓLEO E DE BIOCOMBUSTÍVEIS
19	3	FABRICAÇÃO DE VEÍCULOS AUTOMOTORES, REBOQUES E CARROCERIAS
20	3	FABRICAÇÃO DE PRODUTOS QUÍMICOS
21	3	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS E FARMACÊUTICOS
22	3	FABRICAÇÃO DE PRODUTOS DE BORRACHA E DE MATERIAL PLÁSTICO
23	3	FABRICAÇÃO DE PRODUTOS DE MINERAIS NÃO-METÁLICOS
24	3	METALURGIA
25	3	FABRICAÇÃO DE PRODUTOS DE METAL, EXCETO MÁQUINAS  E EQUIPAMENTOS
26	3	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA, PRODUTOS ELETRÔNICOS E ÓPTICOS
27	3	FABRICAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS
28	3	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS
29	3	FABRICAÇÃO DE OUTROS EQUIPAMENTOS DE TRANSPORTE, EXCETO VEÍCULOS AUTOMOTORES
30	3	FABRICAÇÃO DE MÓVEIS
31	3	FABRICAÇÃO DE PRODUTOS DIVERSOS
32	3	MANUTENÇÃO, REPARAÇÃO E INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS
33	4	ELETRICIDADE, GÁS E OUTRAS UTILIDADES
34	5	CAPTAÇÃO, TRATAMENTO E DISTRIBUIÇÃO DE ÁGUA
35	5	ESGOTO E ATIVIDADES RELACIONADAS
36	5	COLETA, TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS; RECUPERAÇÃO DE MATERIAIS
37	5	DESCONTAMINAÇÃO E OUTROS SERVIÇOS DE GESTÃO DE RESÍDUOS
38	6	CONSTRUÇÃO DE EDIFÍCIOS
39	6	OBRAS DE INFRA-ESTRUTURA
40	7	ARMAZENAMENTO E ATIVIDADES AUXILIARES DOS TRANSPORTES
41	7	CORREIO E OUTRAS ATIVIDADES DE ENTREGA
42	8	ALOJAMENTO
43	8	ALIMENTAÇÃO
44	6	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO
45	9	COMÉRCIO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS
46	10	ATIVIDADES DE RÁDIO E DE TELEVISÃO
47	9	COMÉRCIO POR ATACADO, EXCETO VEÍCULOS AUTOMOTORES E MOTOCICLETAS
48	9	COMÉRCIO VAREJISTA
49	7	TRANSPORTE TERRESTRE
50	7	TRANSPORTE AQUAVIÁRIO
51	7	TRANSPORTE AÉREO
52	11	SERVIÇOS DE ARQUITETURA E ENGENHARIA; TESTES E ANÁLISES TÉCNICAS
53	10	EDIÇÃO E EDIÇÃO INTEGRADA À IMPRESSÃO
54	10	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO; GRAVAÇÃO DE SOM E EDIÇÃO DE MÚSICA
55	10	TELECOMUNICAÇÕES
56	10	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO
57	10	ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO
58	12	ATIVIDADES DE SERVIÇOS FINANCEIROS
59	12	SEGUROS, RESSEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE
60	12	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS, SEGUROS, PREVIDÊNCIA COMPLEMENTAR E PLANOS DE SAÚDE
61	13	ATIVIDADES IMOBILIÁRIAS
62	11	ATIVIDADES JURÍDICAS, DE CONTABILIDADE E DE AUDITORIA
63	11	ATIVIDADES DE SEDES DE EMPRESAS E DE CONSULTORIA EM GESTÃO EMPRESARIAL
64	11	PESQUISA E DESENVOLVIMENTO CIENTÍFICO
65	11	PUBLICIDADE E PESQUISA DE MERCADO
66	11	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS
67	11	ATIVIDADES VETERINÁRIAS
68	14	ATIVIDADES LIGADAS AO PATRIMÔNIO CULTURAL E AMBIENTAL
69	14	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS
70	15	ALUGUÉIS NÃO-IMOBILIÁRIOS E GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS
71	15	SELEÇÃO, AGENCIAMENTO E LOCAÇÃO DE MÃO-DE-OBRA
72	15	AGÊNCIAS DE VIAGENS, OPERADORES TURÍSTICOS E SERVIÇOS DE RESERVAS
73	15	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA E INVESTIGAÇÃO
74	15	SERVIÇOS PARA EDIFÍCIOS E ATIVIDADES PAISAGÍSTICAS
75	15	SERVIÇOS DE ESCRITÓRIO, DE APOIO ADMINISTRATIVO E OUTROS SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS
76	16	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL
77	17	EDUCAÇÃO
78	18	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA
79	18	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA INTEGRADAS COM ASSISTÊNCIA SOCIAL, PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
80	18	SERVIÇOS DE ASSISTÊNCIA SOCIAL SEM ALOJAMENTO
81	14	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS
82	14	ATIVIDADES ESPORTIVAS E DE RECREAÇÃO E LAZER
83	19	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS
84	19	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO E DE OBJETOS PESSOAIS E DOMÉSTICOS
85	19	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS
86	20	SERVIÇOS DOMÉSTICOS
87	21	ORGANISMOS INTERNACIONAIS E OUTRAS INSTITUIÇÕES EXTRATERRITORIAIS
\.


--
-- TOC entry 4879 (class 0 OID 28986)
-- Dependencies: 255
-- Data for Name: ibge_cnae_grupo; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ibge_cnae_grupo (id, divisao_id, nome) FROM stdin;
1	1	PRODUÇÃO DE LAVOURAS TEMPORÁRIAS
2	1	HORTICULTURA E FLORICULTURA
3	1	PRODUÇÃO DE LAVOURAS PERMANENTES
4	1	PRODUÇÃO DE SEMENTES E MUDAS CERTIFICADAS
5	1	PECUÁRIA
6	1	ATIVIDADES DE APOIO À AGRICULTURA E À PECUÁRIA; ATIVIDADES DE PÓS-COLHEITA
7	1	CAÇA E SERVIÇOS RELACIONADOS
8	2	PRODUÇÃO FLORESTAL - FLORESTAS PLANTADAS
9	2	PRODUÇÃO FLORESTAL - FLORESTAS NATIVAS
10	2	ATIVIDADES DE APOIO À PRODUÇÃO FLORESTAL
11	3	PESCA
12	3	AQUICULTURA
13	4	EXTRAÇÃO DE CARVÃO MINERAL
14	5	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL
15	6	EXTRAÇÃO DE MINÉRIO DE FERRO
16	6	EXTRAÇÃO DE MINERAIS METÁLICOS NÃO-FERROSOS
17	7	EXTRAÇÃO DE PEDRA, AREIA E ARGILA
18	7	EXTRAÇÃO DE OUTROS MINERAIS NÃO-METÁLICOS
19	8	ATIVIDADES DE APOIO À EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL
20	8	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS, EXCETO PETRÓLEO E GÁS NATURAL
21	9	ABATE E FABRICAÇÃO DE PRODUTOS DE CARNE
22	9	PRESERVAÇÃO DO PESCADO E FABRICAÇÃO DE PRODUTOS DO PESCADO
23	9	FABRICAÇÃO DE CONSERVAS DE FRUTAS, LEGUMES E OUTROS VEGETAIS
24	9	FABRICAÇÃO DE ÓLEOS E GORDURAS VEGETAIS E ANIMAIS
25	9	LATICÍNIOS
26	9	MOAGEM, FABRICAÇÃO DE PRODUTOS AMILÁCEOS E DE ALIMENTOS PARA ANIMAIS
27	9	FABRICAÇÃO E REFINO DE AÇÚCAR
28	9	TORREFAÇÃO E MOAGEM DE CAFÉ
29	9	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS
30	10	FABRICAÇÃO DE BEBIDAS ALCOÓLICAS
31	10	FABRICAÇÃO DE BEBIDAS NÃO-ALCOÓLICAS
32	11	PROCESSAMENTO INDUSTRIAL DO FUMO
33	11	FABRICAÇÃO DE PRODUTOS DO FUMO
34	12	PREPARAÇÃO E FIAÇÃO DE FIBRAS TÊXTEIS
35	12	TECELAGEM, EXCETO MALHA
36	12	FABRICAÇÃO DE TECIDOS DE MALHA
37	12	ACABAMENTOS EM FIOS, TECIDOS E ARTEFATOS TÊXTEIS
38	12	FABRICAÇÃO DE ARTEFATOS TÊXTEIS, EXCETO VESTUÁRIO
39	13	CONFECÇÃO DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS
40	13	FABRICAÇÃO DE ARTIGOS DE MALHARIA E TRICOTAGEM
41	14	CURTIMENTO E OUTRAS PREPARAÇÕES DE COURO
42	14	FABRICAÇÃO DE ARTIGOS PARA VIAGEM E DE ARTEFATOS DIVERSOS DE COURO
43	14	FABRICAÇÃO DE CALÇADOS
44	14	FABRICAÇÃO DE PARTES PARA CALÇADOS, DE QUALQUER MATERIAL
45	15	DESDOBRAMENTO DE MADEIRA
46	15	FABRICAÇÃO DE PRODUTOS DE MADEIRA, CORTIÇA E MATERIAL TRANÇADO, EXCETO MÓVEIS
47	16	FABRICAÇÃO DE CELULOSE E OUTRAS PASTAS PARA A FABRICAÇÃO DE PAPEL
48	16	FABRICAÇÃO DE PAPEL, CARTOLINA E PAPEL-CARTÃO
49	16	FABRICAÇÃO DE EMBALAGENS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO
50	16	FABRICAÇÃO DE PRODUTOS DIVERSOS DE PAPEL, CARTOLINA, PAPEL-CARTÃO E PAPELÃO ONDULADO
51	17	ATIVIDADE DE IMPRESSÃO
52	17	SERVIÇOS DE PRÉ-IMPRESSÃO E ACABAMENTOS GRÁFICOS
53	17	REPRODUÇÃO DE MATERIAIS GRAVADOS EM QUALQUER SUPORTE
54	18	COQUERIAS
55	18	FABRICAÇÃO DE PRODUTOS DERIVADOS DO PETRÓLEO
56	18	FABRICAÇÃO DE BIOCOMBUSTÍVEIS
57	19	FABRICAÇÃO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS
58	19	FABRICAÇÃO DE CAMINHÕES E ÔNIBUS
59	19	FABRICAÇÃO DE CABINES, CARROCERIAS E REBOQUES PARA VEÍCULOS AUTOMOTORES
60	19	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES
61	19	RECONDICIONAMENTO E RECUPERAÇÃO DE MOTORES PARA VEÍCULOS AUTOMOTORES
62	20	FABRICAÇÃO DE PRODUTOS QUÍMICOS INORGÂNICOS
63	20	FABRICAÇÃO DE PRODUTOS QUÍMICOS ORGÂNICOS
64	20	FABRICAÇÃO DE RESINAS E ELASTÔMEROS
65	20	FABRICAÇÃO DE FIBRAS ARTIFICIAIS E SINTÉTICAS
66	20	FABRICAÇÃO DE DEFENSIVOS AGRÍCOLAS E DESINFESTANTES DOMISSANITÁRIOS
67	20	FABRICAÇÃO DE SABÕES, DETERGENTES, PRODUTOS DE LIMPEZA, COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL
68	20	FABRICAÇÃO DE TINTAS, VERNIZES, ESMALTES, LACAS E PRODUTOS AFINS
69	20	FABRICAÇÃO DE PRODUTOS E PREPARADOS QUÍMICOS DIVERSOS
70	21	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS
71	21	FABRICAÇÃO DE PRODUTOS FARMACÊUTICOS
72	22	FABRICAÇÃO DE PRODUTOS DE BORRACHA
73	22	FABRICAÇÃO DE PRODUTOS DE MATERIAL PLÁSTICO
74	23	FABRICAÇÃO DE VIDRO E DE PRODUTOS DO VIDRO
75	23	FABRICAÇÃO DE CIMENTO
76	23	FABRICAÇÃO DE ARTEFATOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES
77	23	FABRICAÇÃO DE PRODUTOS CERÂMICOS
78	23	APARELHAMENTO DE PEDRAS E FABRICAÇÃO DE OUTROS PRODUTOS DE MINERAIS NÃO-METÁLICOS
79	24	PRODUÇÃO DE FERRO-GUSA E DE FERROLIGAS
80	24	SIDERURGIA
81	24	PRODUÇÃO DE TUBOS DE AÇO, EXCETO TUBOS SEM COSTURA
82	24	METALURGIA DOS METAIS NÃO-FERROSOS
83	24	FUNDIÇÃO
84	25	FABRICAÇÃO DE ESTRUTURAS METÁLICAS E OBRAS DE CALDEIRARIA PESADA
85	25	FABRICAÇÃO DE TANQUES, RESERVATÓRIOS METÁLICOS E CALDEIRAS
86	25	FORJARIA, ESTAMPARIA, METALURGIA DO PÓ E SERVIÇOS DE TRATAMENTO DE METAIS
87	25	FABRICAÇÃO DE ARTIGOS DE CUTELARIA, DE SERRALHERIA E FERRAMENTAS
88	25	FABRICAÇÃO DE EQUIPAMENTO BÉLICO PESADO, ARMAS E MUNIÇÕES
89	25	FABRICAÇÃO DE PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE
90	26	FABRICAÇÃO DE COMPONENTES ELETRÔNICOS
91	26	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E PERIFÉRICOS
92	26	FABRICAÇÃO DE EQUIPAMENTOS DE COMUNICAÇÃO
176	49	TRANSPORTE FERROVIÁRIO E METROFERROVIÁRIO
93	26	FABRICAÇÃO DE APARELHOS DE RECEPÇÃO, REPRODUÇÃO, GRAVAÇÃO E AMPLIFICAÇÃO DE ÁUDIO E VÍDEO
94	26	FABRICAÇÃO DE APARELHOS E INSTRUMENTOS DE MEDIDA, TESTE E CONTROLE; CRONÔMETROS E RELÓGIOS
95	26	FABRICAÇÃO DE APARELHOS ELETROMÉDICOS E ELETROTERAPÊUTICOS E EQUIPAMENTOS DE IRRADIAÇÃO
96	26	FABRICAÇÃO DE EQUIPAMENTOS E INSTRUMENTOS ÓPTICOS, FOTOGRÁFICOS E CINEMATOGRÁFICOS
97	26	FABRICAÇÃO DE MÍDIAS VIRGENS, MAGNÉTICAS E ÓPTICAS
98	27	FABRICAÇÃO DE GERADORES, TRANSFORMADORES E MOTORES ELÉTRICOS
99	27	FABRICAÇÃO DE PILHAS, BATERIAS E ACUMULADORES ELÉTRICOS
100	27	FABRICAÇÃO DE EQUIPAMENTOS PARA DISTRIBUIÇÃO E CONTROLE DE ENERGIA ELÉTRICA
101	27	FABRICAÇÃO DE LÂMPADAS E OUTROS EQUIPAMENTOS DE ILUMINAÇÃO
102	27	FABRICAÇÃO DE ELETRODOMÉSTICOS
103	27	FABRICAÇÃO DE EQUIPAMENTOS E APARELHOS ELÉTRICOS NÃO ESPECIFICADOS ANTERIORMENTE
104	28	FABRICAÇÃO DE MOTORES, BOMBAS, COMPRESSORES E EQUIPAMENTOS DE TRANSMISSÃO
105	28	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO GERAL
106	28	FABRICAÇÃO DE TRATORES E DE MÁQUINAS E EQUIPAMENTOS PARA A AGRICULTURA E PECUÁRIA
107	28	FABRICAÇÃO DE MÁQUINAS-FERRAMENTA
108	28	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO NA EXTRAÇÃO MINERAL E NA CONSTRUÇÃO
109	28	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE USO INDUSTRIAL ESPECÍFICO
110	29	CONSTRUÇÃO DE EMBARCAÇÕES
111	29	FABRICAÇÃO DE VEÍCULOS FERROVIÁRIOS
112	29	FABRICAÇÃO DE AERONAVES
113	29	FABRICAÇÃO DE VEÍCULOS MILITARES DE COMBATE
114	29	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSPORTE NÃO ESPECIFICADOS ANTERIORMENTE
115	30	FABRICAÇÃO DE MÓVEIS
116	31	FABRICAÇÃO DE ARTIGOS DE JOALHERIA, BIJUTERIA E SEMELHANTES
117	31	FABRICAÇÃO DE INSTRUMENTOS MUSICAIS
118	31	FABRICAÇÃO DE ARTEFATOS PARA PESCA E ESPORTE
119	31	FABRICAÇÃO DE BRINQUEDOS E JOGOS RECREATIVOS
120	31	FABRICAÇÃO DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO E ODONTOLÓGICO E DE ARTIGOS ÓPTICOS
121	31	FABRICAÇÃO DE PRODUTOS DIVERSOS
122	32	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS
123	32	INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS
124	33	GERAÇÃO, TRANSMISSÃO E DISTRIBUIÇÃO DE ENERGIA ELÉTRICA
125	33	PRODUÇÃO E DISTRIBUIÇÃO DE COMBUSTÍVEIS GASOSOS POR REDES URBANAS
126	33	PRODUÇÃO E DISTRIBUIÇÃO DE VAPOR, ÁGUA QUENTE E AR CONDICIONADO
127	34	CAPTAÇÃO, TRATAMENTO E DISTRIBUIÇÃO DE ÁGUA
128	35	ESGOTO E ATIVIDADES RELACIONADAS
129	36	COLETA DE RESÍDUOS
130	36	TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS
131	36	RECUPERAÇÃO DE MATERIAIS
132	37	DESCONTAMINAÇÃO E OUTROS SERVIÇOS DE GESTÃO DE RESÍDUOS
133	38	INCORPORAÇÃO DE EMPREENDIMENTOS IMOBILIÁRIOS
134	38	CONSTRUÇÃO DE EDIFÍCIOS
135	39	CONSTRUÇÃO DE RODOVIAS, FERROVIAS, OBRAS URBANAS E OBRAS-DE-ARTE ESPECIAIS
136	39	OBRAS DE INFRA-ESTRUTURA PARA ENERGIA ELÉTRICA, TELECOMUNICAÇÕES, ÁGUA, ESGOTO E TRANSPORTE POR DUTOS
137	39	CONSTRUÇÃO DE OUTRAS OBRAS DE INFRA-ESTRUTURA
138	40	ARMAZENAMENTO, CARGA E DESCARGA
139	40	ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES
140	40	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS
141	40	ATIVIDADES AUXILIARES DOS TRANSPORTES AÉREOS
142	40	ATIVIDADES RELACIONADAS À ORGANIZAÇÃO DO TRANSPORTE DE CARGA
143	41	ATIVIDADES DE CORREIO
144	41	ATIVIDADES DE MALOTE E DE ENTREGA
145	42	HOTÉIS E SIMILARES
146	42	OUTROS TIPOS DE ALOJAMENTO NÃO ESPECIFICADOS ANTERIORMENTE
147	43	RESTAURANTES E OUTROS SERVIÇOS DE ALIMENTAÇÃO E BEBIDAS
148	43	SERVIÇOS DE CATERING, BUFÊ E OUTROS SERVIÇOS DE COMIDA PREPARADA
149	44	DEMOLIÇÃO E PREPARAÇÃO DO TERRENO
150	44	INSTALAÇÕES ELÉTRICAS, HIDRÁULICAS E OUTRAS INSTALAÇÕES EM CONSTRUÇÕES
151	44	OBRAS DE ACABAMENTO
152	44	OUTROS SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO
153	45	COMÉRCIO DE VEÍCULOS AUTOMOTORES
154	45	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS AUTOMOTORES
155	45	COMÉRCIO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES
156	45	COMÉRCIO, MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS, PEÇAS E ACESSÓRIOS
157	46	ATIVIDADES DE RÁDIO
158	46	ATIVIDADES DE TELEVISÃO
159	47	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO, EXCETO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS
160	47	COMÉRCIO ATACADISTA DE MATÉRIAS-PRIMAS AGRÍCOLAS E ANIMAIS VIVOS
161	47	COMÉRCIO ATACADISTA ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO
162	47	COMÉRCIO ATACADISTA DE PRODUTOS DE CONSUMO NÃO-ALIMENTAR
163	47	COMÉRCIO ATACADISTA DE EQUIPAMENTOS E PRODUTOS DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO
164	47	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS, EXCETO DE TECNOLOGIAS DE INFORMAÇÃO E COMUNICAÇÃO
165	47	COMÉRCIO ATACADISTA DE MADEIRA, FERRAGENS, FERRAMENTAS, MATERIAL ELÉTRICO E MATERIAL DE CONSTRUÇÃO
166	47	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS
167	47	COMÉRCIO ATACADISTA NÃO-ESPECIALIZADO
168	48	COMÉRCIO VAREJISTA NÃO-ESPECIALIZADO
169	48	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO
170	48	COMÉRCIO VAREJISTA DE COMBUSTÍVEIS PARA VEÍCULOS AUTOMOTORES
171	48	COMÉRCIO VAREJISTA DE MATERIAL DE CONSTRUÇÃO
172	48	COMÉRCIO VAREJISTA DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO; EQUIPAMENTOS E ARTIGOS DE USO DOMÉSTICO
173	48	COMÉRCIO VAREJISTA DE ARTIGOS CULTURAIS, RECREATIVOS E ESPORTIVOS
174	48	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, PERFUMARIA E COSMÉTICOS E ARTIGOS MÉDICOS, ÓPTICOS E ORTOPÉDICOS
175	48	COMÉRCIO VAREJISTA DE PRODUTOS NOVOS NÃO ESPECIFICADOS ANTERIORMENTE E DE PRODUTOS USADOS
177	49	TRANSPORTE RODOVIÁRIO DE PASSAGEIROS
178	49	TRANSPORTE RODOVIÁRIO DE CARGA
179	49	TRANSPORTE DUTOVIÁRIO
180	49	TRENS TURÍSTICOS, TELEFÉRICOS E SIMILARES
181	50	TRANSPORTE MARÍTIMO DE CABOTAGEM E LONGO CURSO
182	50	TRANSPORTE POR NAVEGAÇÃO INTERIOR
183	50	NAVEGAÇÃO DE APOIO
184	50	OUTROS TRANSPORTES AQUAVIÁRIOS
185	51	TRANSPORTE AÉREO DE PASSAGEIROS
186	51	TRANSPORTE AÉREO DE CARGA
187	51	TRANSPORTE ESPACIAL
188	52	SERVIÇOS DE ARQUITETURA E ENGENHARIA E ATIVIDADES TÉCNICAS RELACIONADAS
189	52	TESTES E ANÁLISES TÉCNICAS
190	53	EDIÇÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS ATIVIDADES DE EDIÇÃO
191	53	EDIÇÃO INTEGRADA À IMPRESSÃO DE LIVROS, JORNAIS, REVISTAS E OUTRAS PUBLICAÇÕES
192	54	ATIVIDADES CINEMATOGRÁFICAS, PRODUÇÃO DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO
193	54	ATIVIDADES DE GRAVAÇÃO DE SOM E DE EDIÇÃO DE MÚSICA
194	55	TELECOMUNICAÇÕES POR FIO
195	55	TELECOMUNICAÇÕES SEM FIO
196	55	TELECOMUNICAÇÕES POR SATÉLITE
197	55	OPERADORAS DE TELEVISÃO POR ASSINATURA
198	55	OUTRAS ATIVIDADES DE TELECOMUNICAÇÕES
199	56	ATIVIDADES DOS SERVIÇOS DE TECNOLOGIA DA INFORMAÇÃO
200	57	TRATAMENTO DE DADOS, HOSPEDAGEM NA INTERNET E OUTRAS ATIVIDADES RELACIONADAS
201	57	OUTRAS ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO
202	58	BANCO CENTRAL
203	58	INTERMEDIAÇÃO MONETÁRIA - DEPÓSITOS À VISTA
204	58	INTERMEDIAÇÃO NÃO-MONETÁRIA - OUTROS INSTRUMENTOS DE CAPTAÇÃO
205	58	ARRENDAMENTO MERCANTIL
206	58	SOCIEDADES DE CAPITALIZAÇÃO
207	58	ATIVIDADES DE SOCIEDADES DE PARTICIPAÇÃO
208	58	FUNDOS DE INVESTIMENTO
209	58	ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
210	59	SEGUROS DE VIDA E NÃO-VIDA
211	59	SEGUROS-SAÚDE
212	59	RESSEGUROS
213	59	PREVIDÊNCIA COMPLEMENTAR
214	59	PLANOS DE SAÚDE
215	60	ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS
216	60	ATIVIDADES AUXILIARES DOS SEGUROS, DA PREVIDÊNCIA COMPLEMENTAR E DOS PLANOS DE SAÚDE
217	60	ATIVIDADES DE ADMINISTRAÇÃO DE FUNDOS POR CONTRATO OU COMISSÃO
218	61	ATIVIDADES IMOBILIÁRIAS DE IMÓVEIS PRÓPRIOS
219	61	ATIVIDADES IMOBILIÁRIAS POR CONTRATO OU COMISSÃO
220	62	ATIVIDADES JURÍDICAS
221	62	ATIVIDADES DE CONTABILIDADE, CONSULTORIA E AUDITORIA CONTÁBIL E TRIBUTÁRIA
222	63	ATIVIDADES DE CONSULTORIA EM GESTÃO EMPRESARIAL
223	64	PESQUISA E DESENVOLVIMENTO EXPERIMENTAL EM CIÊNCIAS FÍSICAS E NATURAIS
224	64	PESQUISA E DESENVOLVIMENTO EXPERIMENTAL EM CIÊNCIAS SOCIAIS E HUMANAS
225	65	PUBLICIDADE
226	65	PESQUISAS DE MERCADO E DE OPINIÃO PÚBLICA
227	66	DESIGN E DECORAÇÃO DE INTERIORES
228	66	ATIVIDADES FOTOGRÁFICAS E SIMILARES
229	66	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE
230	67	ATIVIDADES VETERINÁRIAS
231	68	ATIVIDADES LIGADAS AO PATRIMÔNIO CULTURAL E AMBIENTAL
232	69	ATIVIDADES DE EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS
233	70	LOCAÇÃO DE MEIOS DE TRANSPORTE SEM CONDUTOR
234	70	ALUGUEL DE OBJETOS PESSOAIS E DOMÉSTICOS
235	70	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS SEM OPERADOR
236	70	GESTÃO DE ATIVOS INTANGÍVEIS NÃO-FINANCEIROS
237	71	SELEÇÃO E AGENCIAMENTO DE MÃO-DE-OBRA
238	71	LOCAÇÃO DE MÃO-DE-OBRA TEMPORÁRIA
239	71	FORNECIMENTO E GESTÃO DE RECURSOS HUMANOS PARA TERCEIROS
240	72	AGÊNCIAS DE VIAGENS E OPERADORES TURÍSTICOS
241	72	SERVIÇOS DE RESERVAS E OUTROS SERVIÇOS DE TURISMO NÃO ESPECIFICADOS ANTERIORMENTE
242	73	ATIVIDADES DE VIGILÂNCIA, SEGURANÇA PRIVADA E TRANSPORTE DE VALORES
243	73	ATIVIDADES DE MONITORAMENTO DE SISTEMAS DE SEGURANÇA
244	73	ATIVIDADES DE INVESTIGAÇÃO PARTICULAR
245	74	SERVIÇOS COMBINADOS PARA APOIO A EDIFÍCIOS
246	74	ATIVIDADES DE LIMPEZA
247	74	ATIVIDADES PAISAGÍSTICAS
248	75	SERVIÇOS DE ESCRITÓRIO E APOIO ADMINISTRATIVO
249	75	ATIVIDADES DE TELEATENDIMENTO
250	75	ATIVIDADES DE ORGANIZAÇÃO DE EVENTOS, EXCETO CULTURAIS E ESPORTIVOS
251	75	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS
252	76	ADMINISTRAÇÃO DO ESTADO E DA POLÍTICA ECONÔMICA E SOCIAL
253	76	SERVIÇOS COLETIVOS PRESTADOS PELA ADMINISTRAÇÃO PÚBLICA
254	76	SEGURIDADE SOCIAL OBRIGATÓRIA
255	77	EDUCAÇÃO INFANTIL E ENSINO FUNDAMENTAL
256	77	ENSINO MÉDIO
257	77	EDUCAÇÃO SUPERIOR
258	77	EDUCAÇÃO PROFISSIONAL DE NÍVEL TÉCNICO E TECNOLÓGICO
259	77	ATIVIDADES DE APOIO À EDUCAÇÃO
260	77	OUTRAS ATIVIDADES DE ENSINO
261	78	ATIVIDADES DE ATENDIMENTO HOSPITALAR
262	78	SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS E DE REMOÇÃO DE PACIENTES
263	78	ATIVIDADES DE ATENÇÃO AMBULATORIAL EXECUTADAS POR MÉDICOS E ODONTÓLOGOS
264	78	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA
265	78	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE, EXCETO MÉDICOS E ODONTÓLOGOS
266	78	ATIVIDADES DE APOIO À GESTÃO DE SAÚDE
267	78	ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE
268	79	ATIVIDADES DE ASSISTÊNCIA A IDOSOS, DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES, E DE INFRA-ESTRUTURA E APOIO A PACIENTES PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
269	79	ATIVIDADES DE ASSISTÊNCIA PSICOSSOCIAL E À SAÚDE A PORTADORES DE DISTÚRBIOS PSÍQUICOS, DEFICIÊNCIA MENTAL E DEPENDÊNCIA QUÍMICA
270	79	ATIVIDADES DE ASSISTÊNCIA SOCIAL PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES
271	80	SERVIÇOS DE ASSISTÊNCIA SOCIAL SEM ALOJAMENTO
272	81	ATIVIDADES ARTÍSTICAS, CRIATIVAS E DE ESPETÁCULOS
273	82	ATIVIDADES ESPORTIVAS
274	82	ATIVIDADES DE RECREAÇÃO E LAZER
275	83	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS PATRONAIS, EMPRESARIAIS E PROFISSIONAIS
276	83	ATIVIDADES DE ORGANIZAÇÕES SINDICAIS
277	83	ATIVIDADES DE ASSOCIAÇÕES DE DEFESA DE DIREITOS SOCIAIS
278	83	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS NÃO ESPECIFICADAS ANTERIORMENTE
279	84	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE INFORMÁTICA E COMUNICAÇÃO
280	84	REPARAÇÃO E MANUTENÇÃO DE OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS
281	85	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS
282	86	SERVIÇOS DOMÉSTICOS
283	87	ORGANISMOS INTERNACIONAIS E OUTRAS INSTITUIÇÕES EXTRATERRITORIAIS
\.


--
-- TOC entry 4875 (class 0 OID 28954)
-- Dependencies: 251
-- Data for Name: ibge_cnae_secao; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ibge_cnae_secao (id, nome) FROM stdin;
1	AGRICULTURA, PECUÁRIA, PRODUÇÃO FLORESTAL, PESCA E AQUICULTURA
2	INDÚSTRIAS EXTRATIVAS
3	INDÚSTRIAS DE TRANSFORMAÇÃO
4	ELETRICIDADE E GÁS
5	ÁGUA, ESGOTO, ATIVIDADES DE GESTÃO DE RESÍDUOS E DESCONTAMINAÇÃO
6	CONSTRUÇÃO
7	TRANSPORTE, ARMAZENAGEM E CORREIO
8	ALOJAMENTO E ALIMENTAÇÃO
9	COMÉRCIO; REPARAÇÃO DE VEÍCULOS AUTOMOTORES E MOTOCICLETAS
10	INFORMAÇÃO E COMUNICAÇÃO
11	ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS
12	ATIVIDADES FINANCEIRAS, DE SEGUROS E SERVIÇOS RELACIONADOS
13	ATIVIDADES IMOBILIÁRIAS
14	ARTES, CULTURA, ESPORTE E RECREAÇÃO
15	ATIVIDADES ADMINISTRATIVAS E SERVIÇOS COMPLEMENTARES
16	ADMINISTRAÇÃO PÚBLICA, DEFESA E SEGURIDADE SOCIAL
17	EDUCAÇÃO
18	SAÚDE HUMANA E SERVIÇOS SOCIAIS
19	OUTRAS ATIVIDADES DE SERVIÇOS
20	SERVIÇOS DOMÉSTICOS
21	ORGANISMOS INTERNACIONAIS E OUTRAS INSTITUIÇÕES EXTRATERRITORIAIS
\.


--
-- TOC entry 4883 (class 0 OID 29024)
-- Dependencies: 259
-- Data for Name: ibge_cnae_subclasse; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ibge_cnae_subclasse (id, classe_id, codigo, nome) FROM stdin;
1	1	0111301	CULTIVO DE ARROZ
2	1	0111302	CULTIVO DE MILHO
3	1	0111303	CULTIVO DE TRIGO
4	1	0111399	CULTIVO DE OUTROS CEREAIS NÃO ESPECIFICADOS ANTERIORMENTE
5	2	0112101	CULTIVO DE ALGODÃO HERBÁCEO
6	2	0112102	CULTIVO DE JUTA
7	2	0112199	CULTIVO DE OUTRAS FIBRAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
8	3	0113000	CULTIVO DE CANA DE AÇÚCAR
9	4	0114800	CULTIVO DE FUMO
10	5	0115600	CULTIVO DE SOJA
11	6	0116401	CULTIVO DE AMENDOIM
12	6	0116402	CULTIVO DE GIRASSOL
13	6	0116403	CULTIVO DE MAMONA
14	6	0116499	CULTIVO DE OUTRAS OLEAGINOSAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
15	7	0119901	CULTIVO DE ABACAXI
16	7	0119902	CULTIVO DE ALHO
17	7	0119903	CULTIVO DE BATATA INGLESA
18	7	0119904	CULTIVO DE CEBOLA
19	7	0119905	CULTIVO DE FEIJÃO
20	7	0119906	CULTIVO DE MANDIOCA
21	7	0119907	CULTIVO DE MELÃO
22	7	0119908	CULTIVO DE MELANCIA
23	7	0119909	CULTIVO DE TOMATE RASTEIRO
24	7	0119999	CULTIVO DE OUTRAS PLANTAS DE LAVOURA TEMPORÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
25	8	0121101	HORTICULTURA, EXCETO MORANGO
26	8	0121102	CULTIVO DE MORANGO
27	9	0122900	CULTIVO DE FLORES E PLANTAS ORNAMENTAIS
28	10	0131800	CULTIVO DE LARANJA
29	11	0132600	CULTIVO DE UVA
30	12	0133406	CULTIVO DE GUARANÁ
31	12	0133403	CULTIVO DE CAJU
32	12	0133404	CULTIVO DE CÍTRICOS, EXCETO LARANJA
33	12	0133405	CULTIVO DE COCO DA BAÍA
34	12	0133401	CULTIVO DE AÇAÍ
35	12	0133402	CULTIVO DE BANANA
36	12	0133407	CULTIVO DE MAÇÃ
37	12	0133408	CULTIVO DE MAMÃO
38	12	0133409	CULTIVO DE MARACUJÁ
39	12	0133410	CULTIVO DE MANGA
40	12	0133411	CULTIVO DE PÊSSEGO
41	12	0133499	CULTIVO DE FRUTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE
42	13	0134200	CULTIVO DE CAFÉ
43	14	0135100	CULTIVO DE CACAU
44	15	0139301	CULTIVO DE CHÁ DA ÍNDIA
45	15	0139302	CULTIVO DE ERVA MATE
46	15	0139303	CULTIVO DE PIMENTA DO REINO
47	15	0139304	CULTIVO DE PLANTAS PARA CONDIMENTO, EXCETO PIMENTA DO REINO
48	15	0139305	CULTIVO DE DENDÊ
49	15	0139306	CULTIVO DE SERINGUEIRA
50	15	0139399	CULTIVO DE OUTRAS PLANTAS DE LAVOURA PERMANENTE NÃO ESPECIFICADAS ANTERIORMENTE
51	16	0141501	PRODUÇÃO DE SEMENTES CERTIFICADAS, EXCETO DE FORRAGEIRAS PARA PASTO
52	16	0141502	PRODUÇÃO DE SEMENTES CERTIFICADAS DE FORRAGEIRAS PARA FORMAÇÃO DE PASTO
53	17	0142300	PRODUÇÃO DE MUDAS E OUTRAS FORMAS DE PROPAGAÇÃO VEGETAL, CERTIFICADAS
54	18	0151203	CRIAÇÃO DE BOVINOS, EXCETO PARA CORTE E LEITE
55	18	0151201	CRIAÇÃO DE BOVINOS PARA CORTE
56	18	0151202	CRIAÇÃO DE BOVINOS PARA LEITE
57	19	0152103	CRIAÇÃO DE ASININOS E MUARES
58	19	0152101	CRIAÇÃO DE BUFALINOS
59	19	0152102	CRIAÇÃO DE EQUINOS
60	20	0153901	CRIAÇÃO DE CAPRINOS
61	20	0153902	CRIAÇÃO DE OVINOS, INCLUSIVE PARA PRODUÇÃO DE LÃ
62	21	0154700	CRIAÇÃO DE SUÍNOS
63	22	0155501	CRIAÇÃO DE FRANGOS PARA CORTE
64	22	0155502	PRODUÇÃO DE PINTOS DE UM DIA
65	22	0155503	CRIAÇÃO DE OUTROS GALINÁCEOS, EXCETO PARA CORTE
66	22	0155504	CRIAÇÃO DE AVES, EXCETO GALINÁCEOS
67	22	0155505	PRODUÇÃO DE OVOS
68	23	0159801	APICULTURA
69	23	0159802	CRIAÇÃO DE ANIMAIS DE ESTIMAÇÃO
70	23	0159803	CRIAÇÃO DE ESCARGÔ
71	23	0159804	CRIAÇÃO DE BICHO DA SEDA
72	23	0159899	CRIAÇÃO DE OUTROS ANIMAIS NÃO ESPECIFICADOS ANTERIORMENTE
73	24	0161002	SERVIÇO DE PODA DE ÁRVORES PARA LAVOURAS
74	24	0161001	SERVIÇO DE PULVERIZAÇÃO E CONTROLE DE PRAGAS AGRÍCOLAS
75	24	0161003	SERVIÇO DE PREPARAÇÃO DE TERRENO, CULTIVO E COLHEITA
76	24	0161099	ATIVIDADES DE APOIO À AGRICULTURA NÃO ESPECIFICADAS ANTERIORMENTE
77	25	0162801	SERVIÇO DE INSEMINAÇÃO ARTIFICIAL DE ANIMAIS
78	25	0162802	SERVIÇO DE TOSQUIAMENTO DE OVINOS
79	25	0162803	SERVIÇO DE MANEJO DE ANIMAIS
80	25	0162899	ATIVIDADES DE APOIO À PECUÁRIA NÃO ESPECIFICADAS ANTERIORMENTE
81	26	0163600	ATIVIDADES DE PÓS COLHEITA
82	27	0170900	CAÇA E SERVIÇOS RELACIONADOS
83	28	0210106	CULTIVO DE MUDAS EM VIVEIROS FLORESTAIS
84	28	0210107	EXTRAÇÃO DE MADEIRA EM FLORESTAS PLANTADAS
85	28	0210109	PRODUÇÃO DE CASCA DE ACÁCIA NEGRA - FLORESTAS PLANTADAS
86	28	0210101	CULTIVO DE EUCALIPTO
87	28	0210102	CULTIVO DE ACÁCIA NEGRA
88	28	0210103	CULTIVO DE PINUS
89	28	0210104	CULTIVO DE TECA
90	28	0210105	CULTIVO DE ESPÉCIES MADEIREIRAS, EXCETO EUCALIPTO, ACÁCIA NEGRA, PINUS E TECA
91	28	0210108	PRODUÇÃO DE CARVÃO VEGETAL - FLORESTAS PLANTADAS
92	28	0210199	PRODUÇÃO DE PRODUTOS NÃO MADEIREIROS NÃO ESPECIFICADOS ANTERIORMENTE EM FLORESTAS PLANTADAS
93	29	0220901	EXTRAÇÃO DE MADEIRA EM FLORESTAS NATIVAS
94	29	0220902	PRODUÇÃO DE CARVÃO VEGETAL - FLORESTAS NATIVAS
95	29	0220903	COLETA DE CASTANHA DO PARÁ EM FLORESTAS NATIVAS
96	29	0220904	COLETA DE LÁTEX EM FLORESTAS NATIVAS
97	29	0220905	COLETA DE PALMITO EM FLORESTAS NATIVAS
98	29	0220906	CONSERVAÇÃO DE FLORESTAS NATIVAS
99	29	0220999	COLETA DE PRODUTOS NÃO MADEIREIROS NÃO ESPECIFICADOS ANTERIORMENTE EM FLORESTAS NATIVAS
100	30	0230600	ATIVIDADES DE APOIO À PRODUÇÃO FLORESTAL
101	31	0311601	PESCA DE PEIXES EM ÁGUA SALGADA
102	31	0311602	PESCA DE CRUSTÁCEOS E MOLUSCOS EM ÁGUA SALGADA
103	31	0311603	COLETA DE OUTROS PRODUTOS MARINHOS
104	31	0311604	ATIVIDADES DE APOIO À PESCA EM ÁGUA SALGADA
105	32	0312401	PESCA DE PEIXES EM ÁGUA DOCE
106	32	0312402	PESCA DE CRUSTÁCEOS E MOLUSCOS EM ÁGUA DOCE
107	32	0312403	COLETA DE OUTROS PRODUTOS AQUÁTICOS DE ÁGUA DOCE
108	32	0312404	ATIVIDADES DE APOIO À PESCA EM ÁGUA DOCE
109	33	0321301	CRIAÇÃO DE PEIXES EM ÁGUA SALGADA E SALOBRA
110	33	0321302	CRIAÇÃO DE CAMARÕES EM ÁGUA SALGADA E SALOBRA
111	33	0321303	CRIAÇÃO DE OSTRAS E MEXILHÕES EM ÁGUA SALGADA E SALOBRA
112	33	0321304	CRIAÇÃO DE PEIXES ORNAMENTAIS EM ÁGUA SALGADA E SALOBRA
113	33	0321305	ATIVIDADES DE APOIO À AQUICULTURA EM ÁGUA SALGADA E SALOBRA
114	33	0321399	CULTIVOS E SEMICULTIVOS DA AQUICULTURA EM ÁGUA SALGADA E SALOBRA NÃO ESPECIFICADOS ANTERIORMENTE
115	34	0322101	CRIAÇÃO DE PEIXES EM ÁGUA DOCE
116	34	0322102	CRIAÇÃO DE CAMARÕES EM ÁGUA DOCE
117	34	0322103	CRIAÇÃO DE OSTRAS E MEXILHÕES EM ÁGUA DOCE
118	34	0322104	CRIAÇÃO DE PEIXES ORNAMENTAIS EM ÁGUA DOCE
119	34	0322105	RANICULTURA
120	34	0322106	CRIAÇÃO DE JACARÉ
121	34	0322107	ATIVIDADES DE APOIO À AQUICULTURA EM ÁGUA DOCE
122	34	0322199	CULTIVOS E SEMICULTIVOS DA AQUICULTURA EM ÁGUA DOCE NÃO ESPECIFICADOS ANTERIORMENTE
123	35	0500301	EXTRAÇÃO DE CARVÃO MINERAL
124	35	0500302	BENEFICIAMENTO DE CARVÃO MINERAL
125	36	0600001	EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL
126	36	0600002	EXTRAÇÃO E BENEFICIAMENTO DE XISTO
127	36	0600003	EXTRAÇÃO E BENEFICIAMENTO DE AREIAS BETUMINOSAS
128	37	0710301	EXTRAÇÃO DE MINÉRIO DE FERRO
129	37	0710302	PELOTIZAÇÃO, SINTERIZAÇÃO E OUTROS BENEFICIAMENTOS DE MINÉRIO DE FERRO
130	38	0724301	EXTRAÇÃO DE MINÉRIO DE METAIS PRECIOSOS
131	38	0724302	BENEFICIAMENTO DE MINÉRIO DE METAIS PRECIOSOS
132	39	0721901	EXTRAÇÃO DE MINÉRIO DE ALUMÍNIO
133	39	0721902	BENEFICIAMENTO DE MINÉRIO DE ALUMÍNIO
134	40	0722701	EXTRAÇÃO DE MINÉRIO DE ESTANHO
135	40	0722702	BENEFICIAMENTO DE MINÉRIO DE ESTANHO
136	41	0723501	EXTRAÇÃO DE MINÉRIO DE MANGANÊS
137	41	0723502	BENEFICIAMENTO DE MINÉRIO DE MANGANÊS
138	42	0725100	EXTRAÇÃO DE MINERAIS RADIOATIVOS
139	43	0729401	EXTRAÇÃO DE MINÉRIOS DE NIÓBIO E TITÂNIO
140	43	0729402	EXTRAÇÃO DE MINÉRIO DE TUNGSTÊNIO
141	43	0729403	EXTRAÇÃO DE MINÉRIO DE NÍQUEL
142	43	0729404	EXTRAÇÃO DE MINÉRIOS DE COBRE, CHUMBO, ZINCO E OUTROS MINERAIS METÁLICOS NÃO FERROSOS NÃO ESPECIFICADOS ANTERIORMENTE
143	43	0729405	BENEFICIAMENTO DE MINÉRIOS DE COBRE, CHUMBO, ZINCO E OUTROS MINERAIS METÁLICOS NÃO FERROSOS NÃO ESPECIFICADOS ANTERIORMENTE
144	44	0810001	EXTRAÇÃO DE ARDÓSIA E BENEFICIAMENTO ASSOCIADO
145	44	0810002	EXTRAÇÃO DE GRANITO E BENEFICIAMENTO ASSOCIADO
146	44	0810003	EXTRAÇÃO DE MÁRMORE E BENEFICIAMENTO ASSOCIADO
147	44	0810004	EXTRAÇÃO DE CALCÁRIO E DOLOMITA E BENEFICIAMENTO ASSOCIADO
148	44	0810005	EXTRAÇÃO DE GESSO E CAULIM
149	44	0810006	EXTRAÇÃO DE AREIA, CASCALHO OU PEDREGULHO E BENEFICIAMENTO ASSOCIADO
150	44	0810007	EXTRAÇÃO DE ARGILA E BENEFICIAMENTO ASSOCIADO
151	44	0810008	EXTRAÇÃO DE SAIBRO E BENEFICIAMENTO ASSOCIADO
152	44	0810009	EXTRAÇÃO DE BASALTO E BENEFICIAMENTO ASSOCIADO
153	44	0810010	BENEFICIAMENTO DE GESSO E CAULIM ASSOCIADO À EXTRAÇÃO
154	44	0810099	EXTRAÇÃO E BRITAMENTO DE PEDRAS E OUTROS MATERIAIS PARA CONSTRUÇÃO E BENEFICIAMENTO ASSOCIADO
155	45	0891600	EXTRAÇÃO DE MINERAIS PARA FABRICAÇÃO DE ADUBOS, FERTILIZANTES E OUTROS PRODUTOS QUÍMICOS
156	46	0892401	EXTRAÇÃO DE SAL MARINHO
157	46	0892402	EXTRAÇÃO DE SAL GEMA
158	46	0892403	REFINO E OUTROS TRATAMENTOS DO SAL
159	47	0893200	EXTRAÇÃO DE GEMAS (PEDRAS PRECIOSAS E SEMIPRECIOSAS)
160	48	0899101	EXTRAÇÃO DE GRAFITA
161	48	0899102	EXTRAÇÃO DE QUARTZO
162	48	0899103	EXTRAÇÃO DE AMIANTO
163	48	0899199	EXTRAÇÃO DE OUTROS MINERAIS NÃO METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE
164	49	0910600	ATIVIDADES DE APOIO À EXTRAÇÃO DE PETRÓLEO E GÁS NATURAL
165	50	0990401	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINÉRIO DE FERRO
166	50	0990402	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS METÁLICOS NÃO FERROSOS
167	50	0990403	ATIVIDADES DE APOIO À EXTRAÇÃO DE MINERAIS NÃO METÁLICOS
168	51	1011201	FRIGORÍFICO - ABATE DE BOVINOS
169	51	1011202	FRIGORÍFICO - ABATE DE EQUINOS
170	51	1011203	FRIGORÍFICO - ABATE DE OVINOS E CAPRINOS
171	51	1011204	FRIGORÍFICO - ABATE DE BUFALINOS
172	51	1011205	MATADOURO - ABATE DE RESES SOB CONTRATO - EXCETO ABATE DE SUÍNOS
173	52	1012102	ABATE DE PEQUENOS ANIMAIS
174	52	1012101	ABATE DE AVES
175	52	1012103	FRIGORÍFICO - ABATE DE SUÍNOS
176	52	1012104	MATADOURO - ABATE DE SUÍNOS SOB CONTRATO
177	53	1013901	FABRICAÇÃO DE PRODUTOS DE CARNE
178	53	1013902	PREPARAÇÃO DE SUBPRODUTOS DO ABATE
179	54	1020101	PRESERVAÇÃO DE PEIXES, CRUSTÁCEOS E MOLUSCOS
180	54	1020102	FABRICAÇÃO DE CONSERVAS DE PEIXES, CRUSTÁCEOS E MOLUSCOS
181	55	1031700	FABRICAÇÃO DE CONSERVAS DE FRUTAS
182	56	1032501	FABRICAÇÃO DE CONSERVAS DE PALMITO
183	56	1032599	FABRICAÇÃO DE CONSERVAS DE LEGUMES E OUTROS VEGETAIS, EXCETO PALMITO
184	57	1033301	FABRICAÇÃO DE SUCOS CONCENTRADOS DE FRUTAS, HORTALIÇAS E LEGUMES
185	57	1033302	FABRICAÇÃO DE SUCOS DE FRUTAS, HORTALIÇAS E LEGUMES, EXCETO CONCENTRADOS
186	58	1041400	FABRICAÇÃO DE ÓLEOS VEGETAIS EM BRUTO, EXCETO ÓLEO DE MILHO
187	59	1042200	FABRICAÇÃO DE ÓLEOS VEGETAIS REFINADOS, EXCETO ÓLEO DE MILHO
188	60	1043100	FABRICAÇÃO DE MARGARINA E OUTRAS GORDURAS VEGETAIS E DE ÓLEOS NÃO COMESTÍVEIS DE ANIMAIS
189	61	1053800	FABRICAÇÃO DE SORVETES E OUTROS GELADOS COMESTÍVEIS
190	62	1051100	PREPARAÇÃO DO LEITE
191	63	1052000	FABRICAÇÃO DE LATICÍNIOS
192	64	1061901	BENEFICIAMENTO DE ARROZ
193	64	1061902	FABRICAÇÃO DE PRODUTOS DO ARROZ
194	65	1062700	MOAGEM DE TRIGO E FABRICAÇÃO DE DERIVADOS
195	66	1063500	FABRICAÇÃO DE FARINHA DE MANDIOCA E DERIVADOS
196	67	1064300	FABRICAÇÃO DE FARINHA DE MILHO E DERIVADOS, EXCETO ÓLEOS DE MILHO
197	68	1065101	FABRICAÇÃO DE AMIDOS E FÉCULAS DE VEGETAIS
198	68	1065102	FABRICAÇÃO DE ÓLEO DE MILHO EM BRUTO
199	68	1065103	FABRICAÇÃO DE ÓLEO DE MILHO REFINADO
200	69	1066000	FABRICAÇÃO DE ALIMENTOS PARA ANIMAIS
201	70	1069400	MOAGEM E FABRICAÇÃO DE PRODUTOS DE ORIGEM VEGETAL NÃO ESPECIFICADOS ANTERIORMENTE
202	71	1071600	FABRICAÇÃO DE AÇÚCAR EM BRUTO
203	72	1072401	FABRICAÇÃO DE AÇÚCAR DE CANA REFINADO
204	72	1072402	FABRICAÇÃO DE AÇÚCAR DE CEREAIS (DEXTROSE) E DE BETERRABA
205	73	1081301	BENEFICIAMENTO DE CAFÉ
206	73	1081302	TORREFAÇÃO E MOAGEM DE CAFÉ
207	74	1082100	FABRICAÇÃO DE PRODUTOS À BASE DE CAFÉ
208	75	1091101	FABRICAÇÃO DE PRODUTOS DE PANIFICAÇÃO INDUSTRIAL
209	75	1091102	FABRICAÇÃO DE PRODUTOS DE PADARIA E CONFEITARIA COM PREDOMINÂNCIA  DE PRODUÇÃO PRÓPRIA
210	76	1092900	FABRICAÇÃO DE BISCOITOS E BOLACHAS
211	77	1093701	FABRICAÇÃO DE PRODUTOS DERIVADOS DO CACAU E DE CHOCOLATES
212	77	1093702	FABRICAÇÃO DE FRUTAS CRISTALIZADAS, BALAS E SEMELHANTES
213	78	1094500	FABRICAÇÃO DE MASSAS ALIMENTÍCIAS
214	79	1095300	FABRICAÇÃO DE ESPECIARIAS, MOLHOS, TEMPEROS E CONDIMENTOS
215	80	1096100	FABRICAÇÃO DE ALIMENTOS E PRATOS PRONTOS
216	81	1099601	FABRICAÇÃO DE VINAGRES
217	81	1099602	FABRICAÇÃO DE PÓS ALIMENTÍCIOS
218	81	1099603	FABRICAÇÃO DE FERMENTOS E LEVEDURAS
219	81	1099604	FABRICAÇÃO DE GELO COMUM
220	81	1099605	FABRICAÇÃO DE PRODUTOS PARA INFUSÃO (CHÁ, MATE, ETC.)
221	81	1099606	FABRICAÇÃO DE ADOÇANTES NATURAIS E ARTIFICIAIS
222	81	1099607	FABRICAÇÃO DE ALIMENTOS DIETÉTICOS E COMPLEMENTOS ALIMENTARES
223	81	1099699	FABRICAÇÃO DE OUTROS PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
224	82	1111901	FABRICAÇÃO DE AGUARDENTE DE CANA DE AÇÚCAR
225	82	1111902	FABRICAÇÃO DE OUTRAS AGUARDENTES E BEBIDAS DESTILADAS
226	83	1112700	FABRICAÇÃO DE VINHO
227	84	1113501	FABRICAÇÃO DE MALTE, INCLUSIVE MALTE UÍSQUE
228	84	1113502	FABRICAÇÃO DE CERVEJAS E CHOPES
229	85	1121600	FABRICAÇÃO DE ÁGUAS ENVASADAS
230	86	1122401	FABRICAÇÃO DE REFRIGERANTES
231	86	1122402	FABRICAÇÃO DE CHÁ MATE E OUTROS CHÁS PRONTOS PARA CONSUMO
232	86	1122403	FABRICAÇÃO DE REFRESCOS, XAROPES E PÓS PARA REFRESCOS, EXCETO REFRESCOS DE FRUTAS
233	86	1122404	FABRICAÇÃO DE BEBIDAS ISOTÔNICAS
234	86	1122499	FABRICAÇÃO DE OUTRAS BEBIDAS NÃO ALCOÓLICAS NÃO ESPECIFICADAS ANTERIORMENTE
235	87	1210700	PROCESSAMENTO INDUSTRIAL DO FUMO
236	88	1220401	FABRICAÇÃO DE CIGARROS
237	88	1220402	FABRICAÇÃO DE CIGARRILHAS E CHARUTOS
238	88	1220403	FABRICAÇÃO DE FILTROS PARA CIGARROS
239	88	1220499	FABRICAÇÃO DE OUTROS PRODUTOS DO FUMO, EXCETO CIGARROS, CIGARRILHAS E CHARUTOS
240	89	1311100	PREPARAÇÃO E FIAÇÃO DE FIBRAS DE ALGODÃO
241	90	1312000	PREPARAÇÃO E FIAÇÃO DE FIBRAS TÊXTEIS NATURAIS, EXCETO ALGODÃO
242	91	1313800	FIAÇÃO DE FIBRAS ARTIFICIAIS E SINTÉTICAS
243	92	1314600	FABRICAÇÃO DE LINHAS PARA COSTURAR E BORDAR
244	93	1321900	TECELAGEM DE FIOS DE ALGODÃO
245	94	1322700	TECELAGEM DE FIOS DE FIBRAS TÊXTEIS NATURAIS, EXCETO ALGODÃO
246	95	1323500	TECELAGEM DE FIOS DE FIBRAS ARTIFICIAIS E SINTÉTICAS
247	96	1330800	FABRICAÇÃO DE TECIDOS DE MALHA
248	97	1340501	ESTAMPARIA E TEXTURIZAÇÃO EM FIOS, TECIDOS, ARTEFATOS TÊXTEIS E PEÇAS DO VESTUÁRIO
249	97	1340502	ALVEJAMENTO, TINGIMENTO E TORÇÃO EM FIOS, TECIDOS, ARTEFATOS TÊXTEIS E PEÇAS DO VESTUÁRIO
250	97	1340599	OUTROS SERVIÇOS DE ACABAMENTO EM FIOS, TECIDOS, ARTEFATOS TÊXTEIS E PEÇAS DO VESTUÁRIO
251	98	1351100	FABRICAÇÃO DE ARTEFATOS TÊXTEIS PARA USO DOMÉSTICO
252	99	1352900	FABRICAÇÃO DE ARTEFATOS DE TAPEÇARIA
253	100	1353700	FABRICAÇÃO DE ARTEFATOS DE CORDOARIA
254	101	1354500	FABRICAÇÃO DE TECIDOS ESPECIAIS, INCLUSIVE ARTEFATOS
255	102	1359600	FABRICAÇÃO DE OUTROS PRODUTOS TÊXTEIS NÃO ESPECIFICADOS ANTERIORMENTE
256	103	1411801	CONFECÇÃO DE ROUPAS ÍNTIMAS
257	103	1411802	FACÇÃO DE ROUPAS ÍNTIMAS
258	104	1412601	CONFECÇÃO DE PEÇAS DE VESTUÁRIO, EXCETO ROUPAS ÍNTIMAS E AS CONFECCIONADAS SOB MEDIDA
259	104	1412602	CONFECÇÃO, SOB MEDIDA, DE PEÇAS DO VESTUÁRIO, EXCETO ROUPAS ÍNTIMAS
260	104	1412603	FACÇÃO DE PEÇAS DO VESTUÁRIO, EXCETO ROUPAS ÍNTIMAS
261	105	1413401	CONFECÇÃO DE ROUPAS PROFISSIONAIS, EXCETO SOB MEDIDA
262	105	1413402	CONFECÇÃO, SOB MEDIDA, DE ROUPAS PROFISSIONAIS
263	105	1413403	FACÇÃO DE ROUPAS PROFISSIONAIS
264	106	1414200	FABRICAÇÃO DE ACESSÓRIOS DO VESTUÁRIO, EXCETO PARA SEGURANÇA E PROTEÇÃO
265	107	1421500	FABRICAÇÃO DE MEIAS
421	213	2511000	FABRICAÇÃO DE ESTRUTURAS METÁLICAS
266	108	1422300	FABRICAÇÃO DE ARTIGOS DO VESTUÁRIO, PRODUZIDOS EM MALHARIAS E TRICOTAGENS, EXCETO MEIAS
267	109	1510600	CURTIMENTO E OUTRAS PREPARAÇÕES DE COURO
268	110	1521100	FABRICAÇÃO DE ARTIGOS PARA VIAGEM, BOLSAS E SEMELHANTES DE QUALQUER MATERIAL
269	111	1529700	FABRICAÇÃO DE ARTEFATOS DE COURO NÃO ESPECIFICADOS ANTERIORMENTE
270	112	1533500	FABRICAÇÃO DE CALÇADOS DE MATERIAL SINTÉTICO
271	113	1531901	FABRICAÇÃO DE CALÇADOS DE COURO
272	113	1531902	ACABAMENTO DE CALÇADOS DE COURO SOB CONTRATO
273	114	1532700	FABRICAÇÃO DE TÊNIS DE QUALQUER MATERIAL
274	115	1539400	FABRICAÇÃO DE CALÇADOS DE MATERIAIS NÃO ESPECIFICADOS ANTERIORMENTE
275	116	1540800	FABRICAÇÃO DE PARTES PARA CALÇADOS, DE QUALQUER MATERIAL
276	117	1610204	SERRARIAS SEM DESDOBRAMENTO DE MADEIRA EM BRUTO - RESSERRAGEM
277	117	1610203	SERRARIAS COM DESDOBRAMENTO DE MADEIRA EM BRUTO
278	117	1610205	SERVIÇO DE TRATAMENTO DE MADEIRA REALIZADO SOB CONTRATO
279	118	1621800	FABRICAÇÃO DE MADEIRA LAMINADA E DE CHAPAS DE MADEIRA COMPENSADA, PRENSADA E AGLOMERADA
280	119	1622699	FABRICAÇÃO DE OUTROS ARTIGOS DE CARPINTARIA PARA CONSTRUÇÃO
281	119	1622601	FABRICAÇÃO DE CASAS DE MADEIRA PRÉ FABRICADAS
282	119	1622602	FABRICAÇÃO DE ESQUADRIAS DE MADEIRA E DE PEÇAS DE MADEIRA PARA INSTALAÇÕES INDUSTRIAIS E COMERCIAIS
283	120	1623400	FABRICAÇÃO DE ARTEFATOS DE TANOARIA E DE EMBALAGENS DE MADEIRA
284	121	1629301	FABRICAÇÃO DE ARTEFATOS DIVERSOS DE MADEIRA, EXCETO MÓVEIS
285	121	1629302	FABRICAÇÃO DE ARTEFATOS DIVERSOS DE CORTIÇA, BAMBU, PALHA, VIME E OUTROS MATERIAIS TRANÇADOS, EXCETO MÓVEIS
286	122	1710900	FABRICAÇÃO DE CELULOSE E OUTRAS PASTAS PARA A FABRICAÇÃO DE PAPEL
287	123	1721400	FABRICAÇÃO DE PAPEL
288	124	1722200	FABRICAÇÃO DE CARTOLINA E PAPEL CARTÃO
289	125	1731100	FABRICAÇÃO DE EMBALAGENS DE PAPEL
290	126	1732000	FABRICAÇÃO DE EMBALAGENS DE CARTOLINA E PAPEL CARTÃO
291	127	1733800	FABRICAÇÃO DE CHAPAS E DE EMBALAGENS DE PAPELÃO ONDULADO
292	128	1741901	FABRICAÇÃO DE FORMULÁRIOS CONTÍNUOS
293	128	1741902	FABRICAÇÃO DE PRODUTOS DE PAPEL, CARTOLINA, PAPEL CARTÃO E PAPELÃO ONDULADO PARA USO INDUSTRIAL, COMERCIAL E DE ESCRITÓRIO
294	129	1742701	FABRICAÇÃO DE FRALDAS DESCARTÁVEIS
295	129	1742702	FABRICAÇÃO DE ABSORVENTES HIGIÊNICOS
296	129	1742799	FABRICAÇÃO DE PRODUTOS DE PAPEL PARA USO DOMÉSTICO E HIGIÊNICO SANITÁRIO NÃO ESPECIFICADOS ANTERIORMENTE
297	130	1749400	FABRICAÇÃO DE PRODUTOS DE PASTAS CELULÓSICAS, PAPEL, CARTOLINA, PAPEL CARTÃO E PAPELÃO ONDULADO NÃO ESPECIFICADOS ANTERIORMENTE
298	131	1811301	IMPRESSÃO DE JORNAIS
299	131	1811302	IMPRESSÃO DE LIVROS, REVISTAS E OUTRAS PUBLICAÇÕES PERIÓDICAS
300	132	1812100	IMPRESSÃO DE MATERIAL DE SEGURANÇA
301	133	1813001	IMPRESSÃO DE MATERIAL PARA USO PUBLICITÁRIO
302	133	1813099	IMPRESSÃO DE MATERIAL PARA OUTROS USOS
303	134	1821100	SERVIÇOS DE PRÉ IMPRESSÃO
304	135	1822901	SERVIÇOS DE ENCADERNAÇÃO E PLASTIFICAÇÃO
305	135	1822999	SERVIÇOS DE ACABAMENTOS GRÁFICOS, EXCETO ENCADERNAÇÃO E PLASTIFICAÇÃO
306	136	1830001	REPRODUÇÃO DE SOM EM QUALQUER SUPORTE
307	136	1830002	REPRODUÇÃO DE VÍDEO EM QUALQUER SUPORTE
308	136	1830003	REPRODUÇÃO DE SOFTWARE EM QUALQUER SUPORTE
309	137	1910100	COQUERIAS
310	138	1921700	FABRICAÇÃO DE PRODUTOS DO REFINO DE PETRÓLEO
311	139	1922599	FABRICAÇÃO DE OUTROS PRODUTOS DERIVADOS DO PETRÓLEO, EXCETO PRODUTOS DO REFINO
312	139	1922501	FORMULAÇÃO DE COMBUSTÍVEIS
313	139	1922502	RERREFINO DE ÓLEOS LUBRIFICANTES
314	140	1931400	FABRICAÇÃO DE ÁLCOOL
315	141	1932200	FABRICAÇÃO DE BIOCOMBUSTÍVEIS, EXCETO ÁLCOOL
316	142	2910701	FABRICAÇÃO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS
317	142	2910702	FABRICAÇÃO DE CHASSIS COM MOTOR PARA AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS
318	142	2910703	FABRICAÇÃO DE MOTORES PARA AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS
319	143	2920401	FABRICAÇÃO DE CAMINHÕES E ÔNIBUS
320	143	2920402	FABRICAÇÃO DE MOTORES PARA CAMINHÕES E ÔNIBUS
321	144	2930101	FABRICAÇÃO DE CABINES, CARROCERIAS E REBOQUES PARA CAMINHÕES
322	144	2930102	FABRICAÇÃO DE CARROCERIAS PARA ÔNIBUS
323	144	2930103	FABRICAÇÃO DE CABINES, CARROCERIAS E REBOQUES PARA OUTROS VEÍCULOS AUTOMOTORES, EXCETO CAMINHÕES E ÔNIBUS
324	145	2941700	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA O SISTEMA MOTOR DE VEÍCULOS AUTOMOTORES
325	146	2942500	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA OS SISTEMAS DE MARCHA E TRANSMISSÃO DE VEÍCULOS AUTOMOTORES
326	147	2943300	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA O SISTEMA DE FREIOS DE VEÍCULOS AUTOMOTORES
327	148	2944100	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA O SISTEMA DE DIREÇÃO E SUSPENSÃO DE VEÍCULOS AUTOMOTORES
328	149	2945000	FABRICAÇÃO DE MATERIAL ELÉTRICO E ELETRÔNICO PARA VEÍCULOS AUTOMOTORES, EXCETO BATERIAS
329	150	2949201	FABRICAÇÃO DE BANCOS E ESTOFADOS PARA VEÍCULOS AUTOMOTORES
330	150	2949299	FABRICAÇÃO DE OUTRAS PEÇAS E ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES NÃO ESPECIFICADAS ANTERIORMENTE
331	151	2950600	RECONDICIONAMENTO E RECUPERAÇÃO DE MOTORES PARA VEÍCULOS AUTOMOTORES
332	152	2011800	FABRICAÇÃO DE CLORO E ÁLCALIS
333	153	2012600	FABRICAÇÃO DE INTERMEDIÁRIOS PARA FERTILIZANTES
334	154	2013401	FABRICAÇÃO DE ADUBOS E FERTILIZANTES ORGANOMINERAIS
335	154	2013402	FABRICAÇÃO DE ADUBOS E FERTILIZANTES, EXCETO ORGANOMINERAIS
336	155	2014200	FABRICAÇÃO DE GASES INDUSTRIAIS
337	156	2019301	ELABORAÇÃO DE COMBUSTÍVEIS NUCLEARES
338	156	2019399	FABRICAÇÃO DE OUTROS PRODUTOS QUÍMICOS INORGÂNICOS NÃO ESPECIFICADOS ANTERIORMENTE
339	157	2021500	FABRICAÇÃO DE PRODUTOS PETROQUÍMICOS BÁSICOS
340	158	2022300	FABRICAÇÃO DE INTERMEDIÁRIOS PARA PLASTIFICANTES, RESINAS E FIBRAS
341	159	2029100	FABRICAÇÃO DE PRODUTOS QUÍMICOS ORGÂNICOS NÃO ESPECIFICADOS ANTERIORMENTE
342	160	2033900	FABRICAÇÃO DE ELASTÔMEROS
343	161	2031200	FABRICAÇÃO DE RESINAS TERMOPLÁSTICAS
344	162	2032100	FABRICAÇÃO DE RESINAS TERMOFIXAS
345	163	2040100	FABRICAÇÃO DE FIBRAS ARTIFICIAIS E SINTÉTICAS
346	164	2051700	FABRICAÇÃO DE DEFENSIVOS AGRÍCOLAS
347	165	2052500	FABRICAÇÃO DE DESINFESTANTES DOMISSANITÁRIOS
348	166	2061400	FABRICAÇÃO DE SABÕES E DETERGENTES SINTÉTICOS
349	167	2062200	FABRICAÇÃO DE PRODUTOS DE LIMPEZA E POLIMENTO
350	168	2063100	FABRICAÇÃO DE COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL
351	169	2071100	FABRICAÇÃO DE TINTAS, VERNIZES, ESMALTES E LACAS
352	170	2072000	FABRICAÇÃO DE TINTAS DE IMPRESSÃO
353	171	2073800	FABRICAÇÃO DE IMPERMEABILIZANTES, SOLVENTES E PRODUTOS AFINS
354	172	2091600	FABRICAÇÃO DE ADESIVOS E SELANTES
355	173	2092401	FABRICAÇÃO DE PÓLVORAS, EXPLOSIVOS E DETONANTES
356	173	2092402	FABRICAÇÃO DE ARTIGOS PIROTÉCNICOS
357	173	2092403	FABRICAÇÃO DE FÓSFOROS DE SEGURANÇA
358	174	2093200	FABRICAÇÃO DE ADITIVOS DE USO INDUSTRIAL
359	175	2094100	FABRICAÇÃO DE CATALISADORES
360	176	2099101	FABRICAÇÃO DE CHAPAS, FILMES, PAPÉIS E OUTROS MATERIAIS E PRODUTOS QUÍMICOS PARA FOTOGRAFIA
361	176	2099199	FABRICAÇÃO DE OUTROS PRODUTOS QUÍMICOS NÃO ESPECIFICADOS ANTERIORMENTE
362	177	2110600	FABRICAÇÃO DE PRODUTOS FARMOQUÍMICOS
363	178	2121101	FABRICAÇÃO DE MEDICAMENTOS ALOPÁTICOS PARA USO HUMANO
364	178	2121102	FABRICAÇÃO DE MEDICAMENTOS HOMEOPÁTICOS PARA USO HUMANO
365	178	2121103	FABRICAÇÃO DE MEDICAMENTOS FITOTERÁPICOS PARA USO HUMANO
366	179	2122000	FABRICAÇÃO DE MEDICAMENTOS PARA USO VETERINÁRIO
367	180	2123800	FABRICAÇÃO DE PREPARAÇÕES FARMACÊUTICAS
368	181	2211100	FABRICAÇÃO DE PNEUMÁTICOS E DE CÂMARAS DE AR
369	182	2212900	REFORMA DE PNEUMÁTICOS USADOS
370	183	2219600	FABRICAÇÃO DE ARTEFATOS DE BORRACHA NÃO ESPECIFICADOS ANTERIORMENTE
371	184	2221800	FABRICAÇÃO DE LAMINADOS PLANOS E TUBULARES DE MATERIAL PLÁSTICO
372	185	2222600	FABRICAÇÃO DE EMBALAGENS DE MATERIAL PLÁSTICO
373	186	2223400	FABRICAÇÃO DE TUBOS E ACESSÓRIOS DE MATERIAL PLÁSTICO PARA USO NA CONSTRUÇÃO
374	187	2229301	FABRICAÇÃO DE ARTEFATOS DE MATERIAL PLÁSTICO PARA USO PESSOAL E DOMÉSTICO
375	187	2229302	FABRICAÇÃO DE ARTEFATOS DE MATERIAL PLÁSTICO PARA USOS INDUSTRIAIS
376	187	2229303	FABRICAÇÃO DE ARTEFATOS DE MATERIAL PLÁSTICO PARA USO NA CONSTRUÇÃO, EXCETO TUBOS E ACESSÓRIOS
377	187	2229399	FABRICAÇÃO DE ARTEFATOS DE MATERIAL PLÁSTICO PARA OUTROS USOS NÃO ESPECIFICADOS ANTERIORMENTE
378	188	2312500	FABRICAÇÃO DE EMBALAGENS DE VIDRO
379	189	2311700	FABRICAÇÃO DE VIDRO PLANO E DE SEGURANÇA
380	190	2319200	FABRICAÇÃO DE ARTIGOS DE VIDRO
381	191	2320600	FABRICAÇÃO DE CIMENTO
382	192	2330301	FABRICAÇÃO DE ESTRUTURAS PRÉ MOLDADAS DE CONCRETO ARMADO, EM SÉRIE E SOB ENCOMENDA
383	192	2330302	FABRICAÇÃO DE ARTEFATOS DE CIMENTO PARA USO NA CONSTRUÇÃO
384	192	2330303	FABRICAÇÃO DE ARTEFATOS DE FIBROCIMENTO PARA USO NA CONSTRUÇÃO
385	192	2330304	FABRICAÇÃO DE CASAS PRÉ MOLDADAS DE CONCRETO
386	192	2330305	PREPARAÇÃO DE MASSA DE CONCRETO E ARGAMASSA PARA CONSTRUÇÃO
387	192	2330399	FABRICAÇÃO DE OUTROS ARTEFATOS E PRODUTOS DE CONCRETO, CIMENTO, FIBROCIMENTO, GESSO E MATERIAIS SEMELHANTES
388	193	2341900	FABRICAÇÃO DE PRODUTOS CERÂMICOS REFRATÁRIOS
389	194	2342701	FABRICAÇÃO DE AZULEJOS E PISOS
390	194	2342702	FABRICAÇÃO DE ARTEFATOS DE CERÂMICA E BARRO COZIDO PARA USO NA CONSTRUÇÃO, EXCETO AZULEJOS E PISOS
391	195	2349401	FABRICAÇÃO DE MATERIAL SANITÁRIO DE CERÂMICA
392	195	2349499	FABRICAÇÃO DE PRODUTOS CERÂMICOS NÃO REFRATÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
393	196	2391501	BRITAMENTO DE PEDRAS, EXCETO ASSOCIADO À EXTRAÇÃO
394	196	2391502	APARELHAMENTO DE PEDRAS PARA CONSTRUÇÃO, EXCETO ASSOCIADO À EXTRAÇÃO
395	196	2391503	APARELHAMENTO DE PLACAS E EXECUÇÃO DE TRABALHOS EM MÁRMORE, GRANITO, ARDÓSIA E OUTRAS PEDRAS
396	197	2392300	FABRICAÇÃO DE CAL E GESSO
397	198	2399101	DECORAÇÃO, LAPIDAÇÃO, GRAVAÇÃO, VITRIFICAÇÃO E OUTROS TRABALHOS EM CERÂMICA, LOUÇA, VIDRO E CRISTAL
398	198	2399102	FABRICAÇÃO DE ABRASIVOS
399	198	2399199	FABRICAÇÃO DE OUTROS PRODUTOS DE MINERAIS NÃO METÁLICOS NÃO ESPECIFICADOS ANTERIORMENTE
400	199	2411300	PRODUÇÃO DE FERRO GUSA
401	200	2412100	PRODUÇÃO DE FERROLIGAS
402	201	2421100	PRODUÇÃO DE SEMI ACABADOS DE AÇO
403	202	2422901	PRODUÇÃO DE LAMINADOS PLANOS DE AÇO AO CARBONO, REVESTIDOS OU NÃO
404	202	2422902	PRODUÇÃO DE LAMINADOS PLANOS DE AÇOS ESPECIAIS
405	203	2423701	PRODUÇÃO DE TUBOS DE AÇO SEM COSTURA
406	203	2423702	PRODUÇÃO DE LAMINADOS LONGOS DE AÇO, EXCETO TUBOS
407	204	2424502	PRODUÇÃO DE RELAMINADOS, TREFILADOS E PERFILADOS DE AÇO, EXCETO ARAMES
408	204	2424501	PRODUÇÃO DE ARAMES DE AÇO
409	205	2431800	PRODUÇÃO DE TUBOS DE AÇO COM COSTURA
410	206	2439300	PRODUÇÃO DE OUTROS TUBOS DE FERRO E AÇO
411	207	2441501	PRODUÇÃO DE ALUMÍNIO E SUAS LIGAS EM FORMAS PRIMÁRIAS
412	207	2441502	PRODUÇÃO DE LAMINADOS DE ALUMÍNIO
413	208	2442300	METALURGIA DOS METAIS PRECIOSOS
414	209	2443100	METALURGIA DO COBRE
415	210	2449101	PRODUÇÃO DE ZINCO EM FORMAS PRIMÁRIAS
416	210	2449102	PRODUÇÃO DE LAMINADOS DE ZINCO
417	210	2449103	FABRICAÇÃO DE ÂNODOS PARA GALVANOPLASTIA
418	210	2449199	METALURGIA DE OUTROS METAIS NÃO FERROSOS E SUAS LIGAS NÃO ESPECIFICADOS ANTERIORMENTE
419	211	2451200	FUNDIÇÃO DE FERRO E AÇO
420	212	2452100	FUNDIÇÃO DE METAIS NÃO FERROSOS E SUAS LIGAS
422	214	2512800	FABRICAÇÃO DE ESQUADRIAS DE METAL
423	215	2513600	FABRICAÇÃO DE OBRAS DE CALDEIRARIA PESADA
424	216	2521700	FABRICAÇÃO DE TANQUES, RESERVATÓRIOS METÁLICOS E CALDEIRAS PARA AQUECIMENTO CENTRAL
425	217	2522500	FABRICAÇÃO DE CALDEIRAS GERADORAS DE VAPOR, EXCETO PARA AQUECIMENTO CENTRAL E PARA VEÍCULOS
426	218	2531401	PRODUÇÃO DE FORJADOS DE AÇO
427	218	2531402	PRODUÇÃO DE FORJADOS DE METAIS NÃO FERROSOS E SUAS LIGAS
428	219	2532201	PRODUÇÃO DE ARTEFATOS ESTAMPADOS DE METAL
429	219	2532202	METALURGIA DO PÓ
430	220	2539001	SERVIÇOS DE USINAGEM, TORNEARIA E SOLDA
431	220	2539002	SERVIÇOS DE TRATAMENTO E REVESTIMENTO EM METAIS
432	221	2541100	FABRICAÇÃO DE ARTIGOS DE CUTELARIA
433	222	2542000	FABRICAÇÃO DE ARTIGOS DE SERRALHERIA, EXCETO ESQUADRIAS
434	223	2543800	FABRICAÇÃO DE FERRAMENTAS
435	224	2550101	FABRICAÇÃO DE EQUIPAMENTO BÉLICO PESADO, EXCETO VEÍCULOS MILITARES DE COMBATE
436	224	2550102	FABRICAÇÃO DE ARMAS DE FOGO, OUTRAS ARMAS  E MUNIÇÕES
437	225	2591800	FABRICAÇÃO DE EMBALAGENS METÁLICAS
438	226	2592601	FABRICAÇÃO DE PRODUTOS DE TREFILADOS DE METAL PADRONIZADOS
439	226	2592602	FABRICAÇÃO DE PRODUTOS DE TREFILADOS DE METAL, EXCETO PADRONIZADOS
440	227	2593400	FABRICAÇÃO DE ARTIGOS DE METAL PARA USO DOMÉSTICO E PESSOAL
441	228	2599301	SERVIÇOS DE CONFECÇÃO DE ARMAÇÕES METÁLICAS PARA A CONSTRUÇÃO
442	228	2599302	SERVIÇO DE CORTE E DOBRA DE METAIS
443	228	2599399	FABRICAÇÃO DE OUTROS PRODUTOS DE METAL NÃO ESPECIFICADOS ANTERIORMENTE
444	229	2610800	FABRICAÇÃO DE COMPONENTES ELETRÔNICOS
445	230	2621300	FABRICAÇÃO DE EQUIPAMENTOS DE INFORMÁTICA
446	231	2622100	FABRICAÇÃO DE PERIFÉRICOS PARA EQUIPAMENTOS DE INFORMÁTICA
447	232	2631100	FABRICAÇÃO DE EQUIPAMENTOS TRANSMISSORES DE COMUNICAÇÃO, PEÇAS E ACESSÓRIOS
448	233	2632900	FABRICAÇÃO DE APARELHOS TELEFÔNICOS E DE OUTROS EQUIPAMENTOS DE COMUNICAÇÃO, PEÇAS E ACESSÓRIOS
449	234	2640000	FABRICAÇÃO DE APARELHOS DE RECEPÇÃO, REPRODUÇÃO, GRAVAÇÃO E AMPLIFICAÇÃO DE ÁUDIO E VÍDEO
450	235	2651500	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS DE MEDIDA, TESTE E CONTROLE
451	236	2652300	FABRICAÇÃO DE CRONÔMETROS E RELÓGIOS
452	237	2660400	FABRICAÇÃO DE APARELHOS ELETROMÉDICOS E ELETROTERAPÊUTICOS E EQUIPAMENTOS DE IRRADIAÇÃO
453	238	2670102	FABRICAÇÃO DE APARELHOS FOTOGRÁFICOS E CINEMATOGRÁFICOS, PEÇAS E ACESSÓRIOS
454	238	2670101	FABRICAÇÃO DE EQUIPAMENTOS E INSTRUMENTOS ÓPTICOS, PEÇAS E ACESSÓRIOS
455	239	2680900	FABRICAÇÃO DE MÍDIAS VIRGENS, MAGNÉTICAS E ÓPTICAS
456	240	2710401	FABRICAÇÃO DE GERADORES DE CORRENTE CONTÍNUA E ALTERNADA, PEÇAS E ACESSÓRIOS
457	240	2710402	FABRICAÇÃO DE TRANSFORMADORES, INDUTORES, CONVERSORES, SINCRONIZADORES E SEMELHANTES, PEÇAS E ACESSÓRIOS
458	240	2710403	FABRICAÇÃO DE MOTORES ELÉTRICOS, PEÇAS E ACESSÓRIOS
459	241	2721000	FABRICAÇÃO DE PILHAS, BATERIAS E ACUMULADORES ELÉTRICOS, EXCETO PARA VEÍCULOS AUTOMOTORES
460	242	2722802	RECONDICIONAMENTO DE BATERIAS E ACUMULADORES PARA VEÍCULOS AUTOMOTORES
461	242	2722801	FABRICAÇÃO DE BATERIAS E ACUMULADORES PARA VEÍCULOS AUTOMOTORES
462	243	2731700	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS PARA DISTRIBUIÇÃO E CONTROLE DE ENERGIA ELÉTRICA
463	244	2732500	FABRICAÇÃO DE MATERIAL ELÉTRICO PARA INSTALAÇÕES EM CIRCUITO DE CONSUMO
464	245	2733300	FABRICAÇÃO DE FIOS, CABOS E CONDUTORES ELÉTRICOS ISOLADOS
465	246	2740601	FABRICAÇÃO DE LÂMPADAS
466	246	2740602	FABRICAÇÃO DE LUMINÁRIAS E OUTROS EQUIPAMENTOS DE ILUMINAÇÃO
467	247	2751100	FABRICAÇÃO DE FOGÕES, REFRIGERADORES E MÁQUINAS DE LAVAR E SECAR PARA USO DOMÉSTICO, PEÇAS E ACESSÓRIOS
468	248	2759701	FABRICAÇÃO DE APARELHOS ELÉTRICOS DE USO PESSOAL, PEÇAS E ACESSÓRIOS
469	248	2759799	FABRICAÇÃO DE OUTROS APARELHOS ELETRODOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE, PEÇAS E ACESSÓRIOS
470	249	2790201	FABRICAÇÃO DE ELETRODOS, CONTATOS E OUTROS ARTIGOS DE CARVÃO E GRAFITA PARA USO ELÉTRICO, ELETROÍMÃS E ISOLADORES
471	249	2790202	FABRICAÇÃO DE EQUIPAMENTOS PARA SINALIZAÇÃO E ALARME
472	249	2790299	FABRICAÇÃO DE OUTROS EQUIPAMENTOS E APARELHOS ELÉTRICOS NÃO ESPECIFICADOS ANTERIORMENTE
473	250	2811900	FABRICAÇÃO DE MOTORES E TURBINAS, PEÇAS E ACESSÓRIOS, EXCETO PARA AVIÕES E VEÍCULOS RODOVIÁRIOS
474	251	2812700	FABRICAÇÃO DE EQUIPAMENTOS HIDRÁULICOS E PNEUMÁTICOS, PEÇAS E ACESSÓRIOS, EXCETO VÁLVULAS
475	252	2813500	FABRICAÇÃO DE VÁLVULAS, REGISTROS E DISPOSITIVOS SEMELHANTES, PEÇAS E ACESSÓRIOS
476	253	2814301	FABRICAÇÃO DE COMPRESSORES PARA USO INDUSTRIAL, PEÇAS E ACESSÓRIOS
477	253	2814302	FABRICAÇÃO DE COMPRESSORES PARA USO NÃO INDUSTRIAL, PEÇAS E ACESSÓRIOS
478	254	2815101	FABRICAÇÃO DE ROLAMENTOS PARA FINS INDUSTRIAIS
479	254	2815102	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSMISSÃO PARA FINS INDUSTRIAIS, EXCETO ROLAMENTOS
480	255	2821601	FABRICAÇÃO DE FORNOS INDUSTRIAIS, APARELHOS E EQUIPAMENTOS NÃO ELÉTRICOS PARA INSTALAÇÕES TÉRMICAS, PEÇAS E ACESSÓRIOS
481	255	2821602	FABRICAÇÃO DE ESTUFAS E FORNOS ELÉTRICOS PARA FINS INDUSTRIAIS, PEÇAS E ACESSÓRIOS
482	256	2822401	FABRICAÇÃO DE MÁQUINAS, EQUIPAMENTOS E APARELHOS PARA TRANSPORTE E ELEVAÇÃO DE PESSOAS, PEÇAS E ACESSÓRIOS
483	256	2822402	FABRICAÇÃO DE MÁQUINAS, EQUIPAMENTOS E APARELHOS PARA TRANSPORTE E ELEVAÇÃO DE CARGAS, PEÇAS E ACESSÓRIOS
484	257	2823200	FABRICAÇÃO DE MÁQUINAS E APARELHOS DE REFRIGERAÇÃO E VENTILAÇÃO PARA USO INDUSTRIAL E COMERCIAL, PEÇAS E ACESSÓRIOS
485	258	2824102	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS DE AR CONDICIONADO PARA USO NÃO INDUSTRIAL
486	258	2824101	FABRICAÇÃO DE APARELHOS E EQUIPAMENTOS DE AR CONDICIONADO PARA USO INDUSTRIAL
487	259	2825900	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA SANEAMENTO BÁSICO E AMBIENTAL, PEÇAS E ACESSÓRIOS
488	260	2829101	FABRICAÇÃO DE MÁQUINAS DE ESCREVER, CALCULAR E OUTROS EQUIPAMENTOS NÃO ELETRÔNICOS PARA ESCRITÓRIO, PEÇAS E ACESSÓRIOS
489	260	2829199	FABRICAÇÃO DE OUTRAS MÁQUINAS E EQUIPAMENTOS DE USO GERAL NÃO ESPECIFICADOS ANTERIORMENTE, PEÇAS E ACESSÓRIOS
490	261	2832100	FABRICAÇÃO DE EQUIPAMENTOS PARA IRRIGAÇÃO AGRÍCOLA, PEÇAS E ACESSÓRIOS
491	262	2831300	FABRICAÇÃO DE TRATORES AGRÍCOLAS, PEÇAS E ACESSÓRIOS
492	263	2833000	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A AGRICULTURA E PECUÁRIA, PEÇAS E ACESSÓRIOS, EXCETO PARA IRRIGAÇÃO
493	264	2840200	FABRICAÇÃO DE MÁQUINAS FERRAMENTA, PEÇAS E ACESSÓRIOS
494	265	2851800	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A PROSPECÇÃO E EXTRAÇÃO DE PETRÓLEO, PEÇAS E ACESSÓRIOS
495	266	2852600	FABRICAÇÃO DE OUTRAS MÁQUINAS E EQUIPAMENTOS PARA USO NA EXTRAÇÃO MINERAL, PEÇAS E ACESSÓRIOS, EXCETO NA EXTRAÇÃO DE PETRÓLEO
496	267	2853400	FABRICAÇÃO DE TRATORES, PEÇAS E ACESSÓRIOS, EXCETO AGRÍCOLAS
497	268	2854200	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA TERRAPLENAGEM, PAVIMENTAÇÃO E CONSTRUÇÃO, PEÇAS E ACESSÓRIOS, EXCETO TRATORES
498	269	2861500	FABRICAÇÃO DE MÁQUINAS PARA A INDÚSTRIA METALÚRGICA, PEÇAS E ACESSÓRIOS, EXCETO MÁQUINAS FERRAMENTA
499	270	2862300	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AS INDÚSTRIAS DE ALIMENTOS, BEBIDAS E FUMO, PEÇAS E ACESSÓRIOS
500	271	2863100	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A INDÚSTRIA TÊXTIL, PEÇAS E ACESSÓRIOS
501	272	2864000	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AS INDÚSTRIAS DO VESTUÁRIO, DO COURO E DE CALÇADOS, PEÇAS E ACESSÓRIOS
502	273	2865800	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AS INDÚSTRIAS DE CELULOSE, PAPEL E PAPELÃO E ARTEFATOS, PEÇAS E ACESSÓRIOS
503	274	2866600	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A INDÚSTRIA DO PLÁSTICO, PEÇAS E ACESSÓRIOS
504	275	2869100	FABRICAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA USO INDUSTRIAL ESPECÍFICO NÃO ESPECIFICADOS ANTERIORMENTE, PEÇAS E ACESSÓRIOS
505	276	3011301	CONSTRUÇÃO DE EMBARCAÇÕES DE GRANDE PORTE
506	276	3011302	CONSTRUÇÃO DE EMBARCAÇÕES PARA USO COMERCIAL E PARA USOS ESPECIAIS, EXCETO DE GRANDE PORTE
507	277	3012100	CONSTRUÇÃO DE EMBARCAÇÕES PARA ESPORTE E LAZER
508	278	3031800	FABRICAÇÃO DE LOCOMOTIVAS, VAGÕES E OUTROS MATERIAIS RODANTES
509	279	3032600	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA VEÍCULOS FERROVIÁRIOS
510	280	3041500	FABRICAÇÃO DE AERONAVES
511	281	3042300	FABRICAÇÃO DE TURBINAS, MOTORES E OUTROS COMPONENTES E PEÇAS PARA AERONAVES
512	282	3050400	FABRICAÇÃO DE VEÍCULOS MILITARES DE COMBATE
513	283	3099700	FABRICAÇÃO DE EQUIPAMENTOS DE TRANSPORTE NÃO ESPECIFICADOS ANTERIORMENTE
514	284	3091101	FABRICAÇÃO DE MOTOCICLETAS
515	284	3091102	FABRICAÇÃO DE PEÇAS E ACESSÓRIOS PARA MOTOCICLETAS
516	285	3092000	FABRICAÇÃO DE BICICLETAS E TRICICLOS NÃO MOTORIZADOS, PEÇAS E ACESSÓRIOS
517	286	3101200	FABRICAÇÃO DE MÓVEIS COM PREDOMINÂNCIA DE MADEIRA
518	287	3102100	FABRICAÇÃO DE MÓVEIS COM PREDOMINÂNCIA DE METAL
519	288	3103900	FABRICAÇÃO DE MÓVEIS DE OUTROS MATERIAIS, EXCETO MADEIRA E METAL
520	289	3104700	FABRICAÇÃO DE COLCHÕES
521	290	3211601	LAPIDAÇÃO DE GEMAS
522	290	3211602	FABRICAÇÃO DE ARTEFATOS DE JOALHERIA E OURIVESARIA
523	290	3211603	CUNHAGEM DE MOEDAS E MEDALHAS
524	291	3212400	FABRICAÇÃO DE BIJUTERIAS E ARTEFATOS SEMELHANTES
525	292	3220500	FABRICAÇÃO DE INSTRUMENTOS MUSICAIS, PEÇAS E ACESSÓRIOS
526	293	3230200	FABRICAÇÃO DE ARTEFATOS PARA PESCA E ESPORTE
527	294	3240001	FABRICAÇÃO DE JOGOS ELETRÔNICOS
528	294	3240002	FABRICAÇÃO DE MESAS DE BILHAR, DE SINUCA E ACESSÓRIOS NÃO ASSOCIADA À LOCAÇÃO
529	294	3240003	FABRICAÇÃO DE MESAS DE BILHAR, DE SINUCA E ACESSÓRIOS ASSOCIADA À LOCAÇÃO
530	294	3240099	FABRICAÇÃO DE OUTROS BRINQUEDOS E JOGOS RECREATIVOS NÃO ESPECIFICADOS ANTERIORMENTE
531	295	3250704	FABRICAÇÃO DE APARELHOS E UTENSÍLIOS PARA CORREÇÃO DE DEFEITOS FÍSICOS E APARELHOS ORTOPÉDICOS EM GERAL, EXCETO SOB ENCOMENDA
532	295	3250702	FABRICAÇÃO DE MOBILIÁRIO PARA USO MÉDICO, CIRÚRGICO, ODONTOLÓGICO E DE LABORATÓRIO
533	295	3250703	FABRICAÇÃO DE APARELHOS E UTENSÍLIOS PARA CORREÇÃO DE DEFEITOS FÍSICOS E APARELHOS ORTOPÉDICOS EM GERAL SOB ENCOMENDA
534	295	3250701	FABRICAÇÃO DE INSTRUMENTOS NÃO ELETRÔNICOS E UTENSÍLIOS PARA USO MÉDICO, CIRÚRGICO, ODONTOLÓGICO E DE LABORATÓRIO
535	295	3250705	FABRICAÇÃO DE MATERIAIS PARA MEDICINA E ODONTOLOGIA
536	295	3250706	SERVIÇOS DE PRÓTESE DENTÁRIA
537	295	3250707	FABRICAÇÃO DE ARTIGOS ÓPTICOS
538	295	3250709	SERVIÇO DE LABORATÓRIO ÓPTICO
539	296	3291400	FABRICAÇÃO DE ESCOVAS, PINCÉIS E VASSOURAS
540	297	3292201	FABRICAÇÃO DE ROUPAS DE PROTEÇÃO E SEGURANÇA E RESISTENTES A FOGO
541	297	3292202	FABRICAÇÃO DE EQUIPAMENTOS E ACESSÓRIOS PARA SEGURANÇA PESSOAL E PROFISSIONAL
542	298	3299004	FABRICAÇÃO DE PAINÉIS E LETREIROS LUMINOSOS
543	298	3299005	FABRICAÇÃO DE AVIAMENTOS PARA COSTURA
544	298	3299006	FABRICAÇÃO DE VELAS, INCLUSIVE DECORATIVAS
545	298	3299001	FABRICAÇÃO DE GUARDA CHUVAS E SIMILARES
546	298	3299002	FABRICAÇÃO DE CANETAS, LÁPIS E OUTROS ARTIGOS PARA ESCRITÓRIO
547	298	3299003	FABRICAÇÃO DE LETRAS, LETREIROS E PLACAS DE QUALQUER MATERIAL, EXCETO LUMINOSOS
548	298	3299099	FABRICAÇÃO DE PRODUTOS DIVERSOS NÃO ESPECIFICADOS ANTERIORMENTE
549	299	3311200	MANUTENÇÃO E REPARAÇÃO DE TANQUES, RESERVATÓRIOS METÁLICOS E CALDEIRAS, EXCETO PARA VEÍCULOS
550	300	3312102	MANUTENÇÃO E REPARAÇÃO DE APARELHOS E INSTRUMENTOS DE MEDIDA, TESTE E CONTROLE
551	300	3312103	MANUTENÇÃO E REPARAÇÃO DE APARELHOS ELETROMÉDICOS E ELETROTERAPÊUTICOS E EQUIPAMENTOS DE IRRADIAÇÃO
552	300	3312104	MANUTENÇÃO E REPARAÇÃO DE EQUIPAMENTOS E INSTRUMENTOS ÓPTICOS
553	301	3313901	MANUTENÇÃO E REPARAÇÃO DE GERADORES, TRANSFORMADORES E MOTORES ELÉTRICOS
554	301	3313902	MANUTENÇÃO E REPARAÇÃO DE BATERIAS E ACUMULADORES ELÉTRICOS, EXCETO PARA VEÍCULOS
555	301	3313999	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS, APARELHOS E MATERIAIS ELÉTRICOS NÃO ESPECIFICADOS ANTERIORMENTE
556	302	3314705	MANUTENÇÃO E REPARAÇÃO DE EQUIPAMENTOS DE TRANSMISSÃO PARA FINS INDUSTRIAIS
557	302	3314706	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS, APARELHOS E EQUIPAMENTOS PARA INSTALAÇÕES TÉRMICAS
558	302	3314703	MANUTENÇÃO E REPARAÇÃO DE VÁLVULAS INDUSTRIAIS
559	302	3314704	MANUTENÇÃO E REPARAÇÃO DE COMPRESSORES
560	302	3314715	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA USO NA EXTRAÇÃO MINERAL, EXCETO NA EXTRAÇÃO DE PETRÓLEO
561	302	3314716	MANUTENÇÃO E REPARAÇÃO DE TRATORES, EXCETO AGRÍCOLAS
562	302	3314701	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS MOTRIZES NÃO ELÉTRICAS
563	302	3314702	MANUTENÇÃO E REPARAÇÃO DE EQUIPAMENTOS HIDRÁULICOS E PNEUMÁTICOS, EXCETO VÁLVULAS
564	302	3314707	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E APARELHOS DE REFRIGERAÇÃO E VENTILAÇÃO PARA USO INDUSTRIAL E COMERCIAL
565	302	3314708	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS, EQUIPAMENTOS E APARELHOS PARA TRANSPORTE E ELEVAÇÃO DE CARGAS
566	302	3314709	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS DE ESCREVER, CALCULAR E DE OUTROS EQUIPAMENTOS NÃO ELETRÔNICOS PARA ESCRITÓRIO
567	302	3314710	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA USO GERAL NÃO ESPECIFICADOS ANTERIORMENTE
568	302	3314711	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AGRICULTURA E PECUÁRIA
569	302	3314712	MANUTENÇÃO E REPARAÇÃO DE TRATORES AGRÍCOLAS
570	302	3314713	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS FERRAMENTA
571	302	3314714	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A PROSPECÇÃO E EXTRAÇÃO DE PETRÓLEO
572	302	3314717	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS DE TERRAPLENAGEM, PAVIMENTAÇÃO E CONSTRUÇÃO, EXCETO TRATORES
573	302	3314718	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS PARA A INDÚSTRIA METALÚRGICA, EXCETO MÁQUINAS FERRAMENTA
574	302	3314719	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA AS INDÚSTRIAS DE ALIMENTOS, BEBIDAS E FUMO
575	302	3314720	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E EQUIPAMENTOS PARA A INDÚSTRIA TÊXTIL, DO VESTUÁRIO, DO COURO E CALÇADOS
576	302	3314721	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E APARELHOS PARA A INDÚSTRIA DE CELULOSE, PAPEL E PAPELÃO E ARTEFATOS
577	302	3314722	MANUTENÇÃO E REPARAÇÃO DE MÁQUINAS E APARELHOS PARA A INDÚSTRIA DO PLÁSTICO
578	302	3314799	MANUTENÇÃO E REPARAÇÃO DE OUTRAS MÁQUINAS E EQUIPAMENTOS PARA USOS INDUSTRIAIS NÃO ESPECIFICADOS ANTERIORMENTE
579	303	3315500	MANUTENÇÃO E REPARAÇÃO DE VEÍCULOS FERROVIÁRIOS
580	304	3316301	MANUTENÇÃO E REPARAÇÃO DE AERONAVES, EXCETO A MANUTENÇÃO NA PISTA
581	304	3316302	MANUTENÇÃO DE AERONAVES NA PISTA
582	305	3317102	MANUTENÇÃO E REPARAÇÃO DE EMBARCAÇÕES PARA ESPORTE E LAZER
583	305	3317101	MANUTENÇÃO E REPARAÇÃO DE EMBARCAÇÕES E ESTRUTURAS FLUTUANTES
584	306	3319800	MANUTENÇÃO E REPARAÇÃO DE EQUIPAMENTOS E PRODUTOS NÃO ESPECIFICADOS ANTERIORMENTE
585	307	3321000	INSTALAÇÃO DE MÁQUINAS E EQUIPAMENTOS INDUSTRIAIS
586	308	3329501	SERVIÇOS DE MONTAGEM DE MÓVEIS DE QUALQUER MATERIAL
587	308	3329599	INSTALAÇÃO DE OUTROS EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE
588	309	3511501	GERAÇÃO DE ENERGIA ELÉTRICA
589	309	3511502	ATIVIDADES DE COORDENAÇÃO E CONTROLE DA OPERAÇÃO DA GERAÇÃO E TRANSMISSÃO DE ENERGIA ELÉTRICA
590	310	3512300	TRANSMISSÃO DE ENERGIA ELÉTRICA
591	311	3513100	COMÉRCIO ATACADISTA DE ENERGIA ELÉTRICA
592	312	3514000	DISTRIBUIÇÃO DE ENERGIA ELÉTRICA
593	313	3520401	PRODUÇÃO DE GÁS; PROCESSAMENTO DE GÁS NATURAL
594	313	3520402	DISTRIBUIÇÃO DE COMBUSTÍVEIS GASOSOS POR REDES URBANAS
595	314	3530100	PRODUÇÃO E DISTRIBUIÇÃO DE VAPOR, ÁGUA QUENTE E AR CONDICIONADO
596	315	3600602	DISTRIBUIÇÃO DE ÁGUA POR CAMINHÕES
597	315	3600601	CAPTAÇÃO, TRATAMENTO E DISTRIBUIÇÃO DE ÁGUA
598	316	3701100	GESTÃO DE REDES DE ESGOTO
599	317	3702900	ATIVIDADES RELACIONADAS A ESGOTO, EXCETO A GESTÃO DE REDES
600	318	3811400	COLETA DE RESÍDUOS NÃO PERIGOSOS
601	319	3812200	COLETA DE RESÍDUOS PERIGOSOS
602	320	3821100	TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS NÃO PERIGOSOS
603	321	3822000	TRATAMENTO E DISPOSIÇÃO DE RESÍDUOS PERIGOSOS
604	322	3831901	RECUPERAÇÃO DE SUCATAS DE ALUMÍNIO
605	322	3831999	RECUPERAÇÃO DE MATERIAIS METÁLICOS, EXCETO ALUMÍNIO
606	323	3832700	RECUPERAÇÃO DE MATERIAIS PLÁSTICOS
607	324	3839401	USINAS DE COMPOSTAGEM
608	324	3839499	RECUPERAÇÃO DE MATERIAIS NÃO ESPECIFICADOS ANTERIORMENTE
609	325	3900500	DESCONTAMINAÇÃO E OUTROS SERVIÇOS DE GESTÃO DE RESÍDUOS
610	326	4110700	INCORPORAÇÃO DE EMPREENDIMENTOS IMOBILIÁRIOS
611	327	4120400	CONSTRUÇÃO DE EDIFÍCIOS
612	328	4211101	CONSTRUÇÃO DE RODOVIAS E FERROVIAS
613	328	4211102	PINTURA PARA SINALIZAÇÃO EM PISTAS RODOVIÁRIAS E AEROPORTOS
614	329	4212000	CONSTRUÇÃO DE OBRAS DE ARTE ESPECIAIS
615	330	4213800	OBRAS DE URBANIZAÇÃO - RUAS, PRAÇAS E CALÇADAS
616	331	4223500	CONSTRUÇÃO DE REDES DE TRANSPORTES POR DUTOS, EXCETO PARA ÁGUA E ESGOTO
617	332	4221905	MANUTENÇÃO DE ESTAÇÕES E REDES DE TELECOMUNICAÇÕES
618	332	4221901	CONSTRUÇÃO DE BARRAGENS E REPRESAS PARA GERAÇÃO DE ENERGIA ELÉTRICA
619	332	4221902	CONSTRUÇÃO DE ESTAÇÕES E REDES DE DISTRIBUIÇÃO DE ENERGIA ELÉTRICA
620	332	4221903	MANUTENÇÃO DE REDES DE DISTRIBUIÇÃO DE ENERGIA ELÉTRICA
621	332	4221904	CONSTRUÇÃO DE ESTAÇÕES E REDES DE TELECOMUNICAÇÕES
622	333	4222701	CONSTRUÇÃO DE REDES DE ABASTECIMENTO DE ÁGUA, COLETA DE ESGOTO E CONSTRUÇÕES CORRELATAS, EXCETO OBRAS DE IRRIGAÇÃO
623	333	4222702	OBRAS DE IRRIGAÇÃO
624	334	4291000	OBRAS PORTUÁRIAS, MARÍTIMAS E FLUVIAIS
625	335	4292801	MONTAGEM DE ESTRUTURAS METÁLICAS
626	335	4292802	OBRAS DE MONTAGEM INDUSTRIAL
627	336	4299501	CONSTRUÇÃO DE INSTALAÇÕES ESPORTIVAS E RECREATIVAS
628	336	4299599	OUTRAS OBRAS DE ENGENHARIA CIVIL NÃO ESPECIFICADAS ANTERIORMENTE
629	337	5211701	ARMAZÉNS GERAIS - EMISSÃO DE WARRANT
630	337	5211702	GUARDA MÓVEIS
631	337	5211799	DEPÓSITOS DE MERCADORIAS PARA TERCEIROS, EXCETO ARMAZÉNS GERAIS E GUARDA MÓVEIS
632	338	5212500	CARGA E DESCARGA
633	339	5221400	CONCESSIONÁRIAS DE RODOVIAS, PONTES, TÚNEIS E SERVIÇOS RELACIONADOS
634	340	5222200	TERMINAIS RODOVIÁRIOS E FERROVIÁRIOS
635	341	5223100	ESTACIONAMENTO DE VEÍCULOS
636	342	5229001	SERVIÇOS DE APOIO AO TRANSPORTE POR TÁXI, INCLUSIVE CENTRAIS DE CHAMADA
637	342	5229002	SERVIÇOS DE REBOQUE DE VEÍCULOS
638	342	5229099	OUTRAS ATIVIDADES AUXILIARES DOS TRANSPORTES TERRESTRES NÃO ESPECIFICADAS ANTERIORMENTE
639	343	5231101	ADMINISTRAÇÃO DA INFRAESTRUTURA PORTUÁRIA
640	343	5231102	ATIVIDADES DO OPERADOR PORTUÁRIO
641	343	5231103	GESTÃO DE TERMINAIS AQUAVIÁRIOS
642	344	5232000	ATIVIDADES DE AGENCIAMENTO MARÍTIMO
643	345	5239701	SERVIÇOS DE PRATICAGEM
644	345	5239799	ATIVIDADES AUXILIARES DOS TRANSPORTES AQUAVIÁRIOS NÃO ESPECIFICADAS ANTERIORMENTE
645	346	5240101	OPERAÇÃO DOS AEROPORTOS E CAMPOS DE ATERRISSAGEM
646	346	5240199	ATIVIDADES AUXILIARES DOS TRANSPORTES AÉREOS, EXCETO OPERAÇÃO DOS AEROPORTOS E CAMPOS DE ATERRISSAGEM
647	347	5250801	COMISSARIA DE DESPACHOS
648	347	5250802	ATIVIDADES DE DESPACHANTES ADUANEIROS
649	347	5250803	AGENCIAMENTO DE CARGAS, EXCETO PARA O TRANSPORTE MARÍTIMO
650	347	5250804	ORGANIZAÇÃO LOGÍSTICA DO TRANSPORTE DE CARGA
651	347	5250805	OPERADOR DE TRANSPORTE MULTIMODAL - OTM
652	348	5310501	ATIVIDADES DO CORREIO NACIONAL
653	348	5310502	ATIVIDADES DE FRANQUEADAS DO CORREIO NACIONAL
654	349	5320201	SERVIÇOS DE MALOTE NÃO REALIZADOS PELO CORREIO NACIONAL
655	349	5320202	SERVIÇOS DE ENTREGA RÁPIDA
656	350	5510801	HOTÉIS
657	350	5510802	APART HOTÉIS
658	350	5510803	MOTÉIS
659	351	5590601	ALBERGUES, EXCETO ASSISTENCIAIS
660	351	5590602	CAMPINGS
661	351	5590603	PENSÕES(ALOJAMENTO)
662	351	5590699	OUTROS ALOJAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE
663	352	5611204	BARES E OUTROS ESTABELECIMENTOS ESPECIALIZADOS EM SERVIR BEBIDAS, SEM ENTRETENIMENTO
664	352	5611201	RESTAURANTES E SIMILARES
665	352	5611203	LANCHONETES, CASAS DE CHÁ, DE SUCOS E SIMILARES
666	352	5611205	BARES E OUTROS ESTABELECIMENTOS ESPECIALIZADOS EM SERVIR BEBIDAS, COM ENTRETENIMENTO
667	353	5612100	SERVIÇOS AMBULANTES DE ALIMENTAÇÃO
668	354	5620102	SERVIÇOS DE ALIMENTAÇÃO PARA EVENTOS E RECEPÇÕES - BUFÊ
669	354	5620101	FORNECIMENTO DE ALIMENTOS PREPARADOS PREPONDERANTEMENTE PARA EMPRESAS
670	354	5620103	CANTINAS - SERVIÇOS DE ALIMENTAÇÃO PRIVATIVOS
671	354	5620104	FORNECIMENTO DE ALIMENTOS PREPARADOS PREPONDERANTEMENTE PARA CONSUMO DOMICILIAR
672	355	4311801	DEMOLIÇÃO DE EDIFÍCIOS E OUTRAS ESTRUTURAS
673	355	4311802	PREPARAÇÃO DE CANTEIRO E LIMPEZA DE TERRENO
674	356	4312600	PERFURAÇÕES E SONDAGENS
675	357	4313400	OBRAS DE TERRAPLENAGEM
676	358	4319300	SERVIÇOS DE PREPARAÇÃO DO TERRENO NÃO ESPECIFICADOS ANTERIORMENTE
677	359	4321500	INSTALAÇÃO E MANUTENÇÃO ELÉTRICA
678	360	4322301	INSTALAÇÕES HIDRÁULICAS, SANITÁRIAS E DE GÁS
679	360	4322302	INSTALAÇÃO E MANUTENÇÃO DE SISTEMAS CENTRAIS DE AR CONDICIONADO, DE VENTILAÇÃO E REFRIGERAÇÃO
680	360	4322303	INSTALAÇÕES DE SISTEMA DE PREVENÇÃO CONTRA INCÊNDIO
681	361	4329101	INSTALAÇÃO DE PAINÉIS PUBLICITÁRIOS
682	361	4329102	INSTALAÇÃO DE EQUIPAMENTOS PARA ORIENTAÇÃO À NAVEGAÇÃO MARÍTIMA FLUVIAL E LACUSTRE
683	361	4329103	INSTALAÇÃO, MANUTENÇÃO E REPARAÇÃO DE ELEVADORES, ESCADAS E ESTEIRAS ROLANTES
684	361	4329104	MONTAGEM E INSTALAÇÃO DE SISTEMAS E EQUIPAMENTOS DE ILUMINAÇÃO E SINALIZAÇÃO EM VIAS PÚBLICAS, PORTOS E AEROPORTOS
685	361	4329105	TRATAMENTOS TÉRMICOS, ACÚSTICOS OU DE VIBRAÇÃO
686	361	4329199	OUTRAS OBRAS DE INSTALAÇÕES EM CONSTRUÇÕES NÃO ESPECIFICADAS ANTERIORMENTE
687	362	4330403	OBRAS DE ACABAMENTO EM GESSO E ESTUQUE
688	362	4330404	SERVIÇOS DE PINTURA DE EDIFÍCIOS EM GERAL
689	362	4330405	APLICAÇÃO DE REVESTIMENTOS E DE RESINAS EM INTERIORES E EXTERIORES
690	362	4330401	IMPERMEABILIZAÇÃO EM OBRAS DE ENGENHARIA CIVIL
691	362	4330402	INSTALAÇÃO DE PORTAS, JANELAS, TETOS, DIVISÓRIAS E ARMÁRIOS EMBUTIDOS DE QUALQUER MATERIAL
692	362	4330499	OUTRAS OBRAS DE ACABAMENTO DA CONSTRUÇÃO
693	363	4391600	OBRAS DE FUNDAÇÕES
694	364	4399101	ADMINISTRAÇÃO DE OBRAS
695	364	4399102	MONTAGEM E DESMONTAGEM DE ANDAIMES E OUTRAS ESTRUTURAS TEMPORÁRIAS
696	364	4399103	OBRAS DE ALVENARIA
697	364	4399104	SERVIÇOS DE OPERAÇÃO E FORNECIMENTO DE EQUIPAMENTOS PARA TRANSPORTE E ELEVAÇÃO DE CARGAS E PESSOAS PARA USO EM OBRAS
698	364	4399105	PERFURAÇÃO E CONSTRUÇÃO DE POÇOS DE ÁGUA
699	364	4399199	SERVIÇOS ESPECIALIZADOS PARA CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE
700	365	4511101	COMÉRCIO A VAREJO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS NOVOS
701	365	4511102	COMÉRCIO A VAREJO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS USADOS
702	365	4511103	COMÉRCIO POR ATACADO DE AUTOMÓVEIS, CAMIONETAS E UTILITÁRIOS NOVOS E USADOS
703	365	4511104	COMÉRCIO POR ATACADO DE CAMINHÕES NOVOS E USADOS
704	365	4511105	COMÉRCIO POR ATACADO DE REBOQUES E SEMI REBOQUES NOVOS E USADOS
705	365	4511106	COMÉRCIO POR ATACADO DE ÔNIBUS E MICROÔNIBUS NOVOS E USADOS
706	366	4512901	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE VEÍCULOS AUTOMOTORES
707	366	4512902	COMÉRCIO SOB CONSIGNAÇÃO DE VEÍCULOS AUTOMOTORES
708	367	4520006	SERVIÇOS DE BORRACHARIA PARA VEÍCULOS AUTOMOTORES
709	367	4520001	SERVIÇOS DE MANUTENÇÃO E REPARAÇÃO MECÂNICA DE VEÍCULOS AUTOMOTORES
710	367	4520002	SERVIÇOS DE LANTERNAGEM OU FUNILARIA E PINTURA DE VEÍCULOS AUTOMOTORES
711	367	4520003	SERVIÇOS DE MANUTENÇÃO E REPARAÇÃO ELÉTRICA DE VEÍCULOS AUTOMOTORES
712	367	4520004	SERVIÇOS DE ALINHAMENTO E BALANCEAMENTO DE VEÍCULOS AUTOMOTORES
713	367	4520005	SERVIÇOS DE LAVAGEM, LUBRIFICAÇÃO E POLIMENTO DE VEÍCULOS AUTOMOTORES
714	367	4520007	SERVIÇOS DE INSTALAÇÃO, MANUTENÇÃO E REPARAÇÃO DE ACESSÓRIOS PARA VEÍCULOS AUTOMOTORES
715	367	4520008	SERVIÇOS DE CAPOTARIA
716	368	4530701	COMÉRCIO POR ATACADO DE PEÇAS E ACESSÓRIOS NOVOS PARA VEÍCULOS AUTOMOTORES
717	368	4530702	COMÉRCIO POR ATACADO DE PNEUMÁTICOS E CÂMARAS DE AR
718	368	4530703	COMÉRCIO A VAREJO DE PEÇAS E ACESSÓRIOS NOVOS PARA VEÍCULOS AUTOMOTORES
719	368	4530704	COMÉRCIO A VAREJO DE PEÇAS E ACESSÓRIOS USADOS PARA VEÍCULOS AUTOMOTORES
720	368	4530705	COMÉRCIO A VAREJO DE PNEUMÁTICOS E CÂMARAS DE AR
721	368	4530706	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE PEÇAS E ACESSÓRIOS NOVOS E USADOS PARA VEÍCULOS AUTOMOTORES
722	369	4541201	COMÉRCIO POR ATACADO DE MOTOCICLETAS E MOTONETAS
723	369	4541202	COMÉRCIO POR ATACADO DE PEÇAS E ACESSÓRIOS PARA MOTOCICLETAS E MOTONETAS
724	369	4541203	COMÉRCIO A VAREJO DE MOTOCICLETAS E MOTONETAS NOVAS
725	369	4541204	COMÉRCIO A VAREJO DE MOTOCICLETAS E MOTONETAS USADAS
726	369	4541206	COMÉRCIO A VAREJO DE PEÇAS E ACESSÓRIOS NOVOS PARA MOTOCICLETAS E MOTONETAS
727	369	4541207	COMÉRCIO A VAREJO DE PEÇAS E ACESSÓRIOS USADOS PARA MOTOCICLETAS E MOTONETAS
728	370	4542101	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MOTOCICLETAS E MOTONETAS, PEÇAS E ACESSÓRIOS
729	370	4542102	COMÉRCIO SOB CONSIGNAÇÃO DE MOTOCICLETAS E MOTONETAS
730	371	4543900	MANUTENÇÃO E REPARAÇÃO DE MOTOCICLETAS E MOTONETAS
731	372	6010100	ATIVIDADES DE RÁDIO
732	373	6021700	ATIVIDADES DE TELEVISÃO ABERTA
733	374	6022501	PROGRAMADORAS
734	374	6022502	ATIVIDADES RELACIONADAS À TELEVISÃO POR ASSINATURA, EXCETO PROGRAMADORAS
735	375	4611700	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MATÉRIAS PRIMAS AGRÍCOLAS E ANIMAIS VIVOS
736	376	4612500	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE COMBUSTÍVEIS, MINERAIS, PRODUTOS SIDERÚRGICOS E QUÍMICOS
737	377	4613300	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MADEIRA, MATERIAL DE CONSTRUÇÃO E FERRAGENS
738	378	4614100	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MÁQUINAS, EQUIPAMENTOS, EMBARCAÇÕES E AERONAVES
739	379	4615000	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE ELETRODOMÉSTICOS, MÓVEIS E ARTIGOS DE USO DOMÉSTICO
740	380	4616800	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE TÊXTEIS, VESTUÁRIO, CALÇADOS E ARTIGOS DE VIAGEM
741	381	4617600	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE PRODUTOS ALIMENTÍCIOS, BEBIDAS E FUMO
742	382	4618401	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MEDICAMENTOS, COSMÉTICOS E PRODUTOS DE PERFUMARIA
743	382	4618402	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE INSTRUMENTOS E MATERIAIS ODONTO MÉDICO HOSPITALARES
744	382	4618403	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE JORNAIS, REVISTAS E OUTRAS PUBLICAÇÕES
745	382	4618499	OUTROS REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO ESPECIALIZADO EM PRODUTOS NÃO ESPECIFICADOS ANTERIORMENTE
746	383	4619200	REPRESENTANTES COMERCIAIS E AGENTES DO COMÉRCIO DE MERCADORIAS EM GERAL NÃO ESPECIALIZADO
747	384	4621400	COMÉRCIO ATACADISTA DE CAFÉ EM GRÃO
748	385	4622200	COMÉRCIO ATACADISTA DE SOJA
749	386	4623105	COMÉRCIO ATACADISTA DE CACAU
750	386	4623106	COMÉRCIO ATACADISTA DE SEMENTES, FLORES, PLANTAS E GRAMAS
751	386	4623107	COMÉRCIO ATACADISTA DE SISAL
752	386	4623102	COMÉRCIO ATACADISTA DE COUROS, LÃS, PELES E OUTROS SUBPRODUTOS NÃO COMESTÍVEIS DE ORIGEM ANIMAL
753	386	4623103	COMÉRCIO ATACADISTA DE ALGODÃO
754	386	4623101	COMÉRCIO ATACADISTA DE ANIMAIS VIVOS
755	386	4623104	COMÉRCIO ATACADISTA DE FUMO EM FOLHA NÃO BENEFICIADO
756	386	4623108	COMÉRCIO ATACADISTA DE MATÉRIAS PRIMAS AGRÍCOLAS COM ATIVIDADE DE FRACIONAMENTO E ACONDICIONAMENTO ASSOCIADA
757	386	4623109	COMÉRCIO ATACADISTA DE ALIMENTOS PARA ANIMAIS
758	386	4623199	COMÉRCIO ATACADISTA DE MATÉRIAS PRIMAS AGRÍCOLAS NÃO ESPECIFICADAS ANTERIORMENTE
759	387	4631100	COMÉRCIO ATACADISTA DE LEITE E LATICÍNIOS
760	388	4632001	COMÉRCIO ATACADISTA DE CEREAIS E LEGUMINOSAS BENEFICIADOS
761	388	4632002	COMÉRCIO ATACADISTA DE FARINHAS, AMIDOS E FÉCULAS
762	388	4632003	COMÉRCIO ATACADISTA DE CEREAIS E LEGUMINOSAS BENEFICIADOS, FARINHAS, AMIDOS E FÉCULAS, COM ATIVIDADE DE FRACIONAMENTO E ACONDICIONAMENTO ASSOCIADA
763	389	4633803	COMÉRCIO ATACADISTA DE COELHOS E OUTROS PEQUENOS ANIMAIS VIVOS PARA ALIMENTAÇÃO
764	389	4633801	COMÉRCIO ATACADISTA DE FRUTAS, VERDURAS, RAÍZES, TUBÉRCULOS, HORTALIÇAS E LEGUMES FRESCOS
765	389	4633802	COMÉRCIO ATACADISTA DE AVES VIVAS E OVOS
766	390	4634601	COMÉRCIO ATACADISTA DE CARNES BOVINAS E SUÍNAS E DERIVADOS
767	390	4634602	COMÉRCIO ATACADISTA DE AVES ABATIDAS E DERIVADOS
768	390	4634603	COMÉRCIO ATACADISTA DE PESCADOS E FRUTOS DO MAR
769	390	4634699	COMÉRCIO ATACADISTA DE CARNES E DERIVADOS DE OUTROS ANIMAIS
770	391	4635401	COMÉRCIO ATACADISTA DE ÁGUA MINERAL
771	391	4635402	COMÉRCIO ATACADISTA DE CERVEJA, CHOPE E REFRIGERANTE
772	391	4635403	COMÉRCIO ATACADISTA DE BEBIDAS COM ATIVIDADE DE FRACIONAMENTO E ACONDICIONAMENTO ASSOCIADA
773	391	4635499	COMÉRCIO ATACADISTA DE BEBIDAS NÃO ESPECIFICADAS ANTERIORMENTE
774	392	4636201	COMÉRCIO ATACADISTA DE FUMO BENEFICIADO
775	392	4636202	COMÉRCIO ATACADISTA DE CIGARROS, CIGARRILHAS E CHARUTOS
776	393	4637101	COMÉRCIO ATACADISTA DE CAFÉ TORRADO, MOÍDO E SOLÚVEL
777	393	4637102	COMÉRCIO ATACADISTA DE AÇÚCAR
778	393	4637103	COMÉRCIO ATACADISTA DE ÓLEOS E GORDURAS
779	393	4637104	COMÉRCIO ATACADISTA DE PÃES, BOLOS, BISCOITOS E SIMILARES
780	393	4637105	COMÉRCIO ATACADISTA DE MASSAS ALIMENTÍCIAS
781	393	4637106	COMÉRCIO ATACADISTA DE SORVETES
782	393	4637107	COMÉRCIO ATACADISTA DE CHOCOLATES, CONFEITOS, BALAS, BOMBONS E SEMELHANTES
783	393	4637199	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
784	394	4639701	COMÉRCIO ATACADISTA DE PRODUTOS ALIMENTÍCIOS EM GERAL
785	394	4639702	COMÉRCIO ATACADISTA DE PRODUTOS ALIMENTÍCIOS EM GERAL, COM ATIVIDADE DE FRACIONAMENTO E ACONDICIONAMENTO ASSOCIADA
786	395	4646001	COMÉRCIO ATACADISTA DE COSMÉTICOS E PRODUTOS DE PERFUMARIA
787	395	4646002	COMÉRCIO ATACADISTA DE PRODUTOS DE HIGIENE PESSOAL
788	396	4645101	COMÉRCIO ATACADISTA DE INSTRUMENTOS E MATERIAIS PARA USO MÉDICO, CIRÚRGICO, HOSPITALAR E DE LABORATÓRIOS
789	396	4645102	COMÉRCIO ATACADISTA DE PRÓTESES E ARTIGOS DE ORTOPEDIA
790	396	4645103	COMÉRCIO ATACADISTA DE PRODUTOS ODONTOLÓGICOS
791	397	4641902	COMÉRCIO ATACADISTA DE ARTIGOS DE CAMA, MESA E BANHO
792	397	4641903	COMÉRCIO ATACADISTA DE ARTIGOS DE ARMARINHO
793	397	4641901	COMÉRCIO ATACADISTA DE TECIDOS
794	398	4642701	COMÉRCIO ATACADISTA DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS, EXCETO PROFISSIONAIS E DE SEGURANÇA
795	398	4642702	COMÉRCIO ATACADISTA DE ROUPAS E ACESSÓRIOS PARA USO PROFISSIONAL E DE SEGURANÇA DO TRABALHO
796	399	4643501	COMÉRCIO ATACADISTA DE CALÇADOS
797	399	4643502	COMÉRCIO ATACADISTA DE BOLSAS, MALAS E ARTIGOS DE VIAGEM
798	400	4644301	COMÉRCIO ATACADISTA DE MEDICAMENTOS E DROGAS DE USO HUMANO
799	400	4644302	COMÉRCIO ATACADISTA DE MEDICAMENTOS E DROGAS DE USO VETERINÁRIO
800	401	4647801	COMÉRCIO ATACADISTA DE ARTIGOS DE ESCRITÓRIO E DE PAPELARIA
801	401	4647802	COMÉRCIO ATACADISTA DE LIVROS, JORNAIS E OUTRAS PUBLICAÇÕES
802	402	4649401	COMÉRCIO ATACADISTA DE EQUIPAMENTOS ELÉTRICOS DE USO PESSOAL E DOMÉSTICO
803	402	4649402	COMÉRCIO ATACADISTA DE APARELHOS ELETRÔNICOS DE USO PESSOAL E DOMÉSTICO
804	402	4649403	COMÉRCIO ATACADISTA DE BICICLETAS, TRICICLOS E OUTROS VEÍCULOS RECREATIVOS
805	402	4649404	COMÉRCIO ATACADISTA DE MÓVEIS E ARTIGOS DE COLCHOARIA
806	402	4649405	COMÉRCIO ATACADISTA DE ARTIGOS DE TAPEÇARIA; PERSIANAS E CORTINAS
807	402	4649406	COMÉRCIO ATACADISTA DE LUSTRES, LUMINÁRIAS E ABAJURES
808	402	4649407	COMÉRCIO ATACADISTA DE FILMES, CDS, DVDS, FITAS E DISCOS
809	402	4649408	COMÉRCIO ATACADISTA DE PRODUTOS DE HIGIENE, LIMPEZA E CONSERVAÇÃO DOMICILIAR
810	402	4649409	COMÉRCIO ATACADISTA DE PRODUTOS DE HIGIENE, LIMPEZA E CONSERVAÇÃO DOMICILIAR, COM ATIVIDADE DE FRACIONAMENTO E ACONDICIONAMENTO ASSOCIADA
811	402	4649410	COMÉRCIO ATACADISTA DE JÓIAS, RELÓGIOS E BIJUTERIAS, INCLUSIVE PEDRAS PRECIOSAS E SEMIPRECIOSAS LAPIDADAS
812	402	4649499	COMÉRCIO ATACADISTA DE OUTROS EQUIPAMENTOS E ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
813	403	4651601	COMÉRCIO ATACADISTA DE EQUIPAMENTOS DE INFORMÁTICA
814	403	4651602	COMÉRCIO ATACADISTA DE SUPRIMENTOS PARA INFORMÁTICA
815	404	4652400	COMÉRCIO ATACADISTA DE COMPONENTES ELETRÔNICOS E EQUIPAMENTOS DE TELEFONIA E COMUNICAÇÃO
816	405	4661300	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS PARA USO AGROPECUÁRIO; PARTES E PEÇAS
817	406	4662100	COMÉRCIO ATACADISTA DE MÁQUINAS, EQUIPAMENTOS PARA TERRAPLENAGEM, MINERAÇÃO E CONSTRUÇÃO; PARTES E PEÇAS
818	407	4663000	COMÉRCIO ATACADISTA DE MÁQUINAS E EQUIPAMENTOS PARA USO INDUSTRIAL; PARTES E PEÇAS
819	408	4664800	COMÉRCIO ATACADISTA DE MÁQUINAS, APARELHOS E EQUIPAMENTOS PARA USO ODONTO MÉDICO HOSPITALAR; PARTES E PEÇAS
820	409	4665600	COMÉRCIO ATACADISTA DE MÁQUINAS E EQUIPAMENTOS PARA USO COMERCIAL; PARTES E PEÇAS
821	410	4669901	COMÉRCIO ATACADISTA DE BOMBAS E COMPRESSORES; PARTES E PEÇAS
822	410	4669999	COMÉRCIO ATACADISTA DE OUTRAS MÁQUINAS E EQUIPAMENTOS NÃO ESPECIFICADOS ANTERIORMENTE; PARTES E PEÇAS
823	411	4671100	COMÉRCIO ATACADISTA DE MADEIRA E PRODUTOS DERIVADOS
824	412	4672900	COMÉRCIO ATACADISTA DE FERRAGENS E FERRAMENTAS
825	413	4673700	COMÉRCIO ATACADISTA DE MATERIAL ELÉTRICO
826	414	4674500	COMÉRCIO ATACADISTA DE CIMENTO
827	415	4679699	COMÉRCIO ATACADISTA DE MATERIAIS DE CONSTRUÇÃO EM GERAL
828	415	4679601	COMÉRCIO ATACADISTA DE TINTAS, VERNIZES E SIMILARES
829	415	4679602	COMÉRCIO ATACADISTA DE MÁRMORES E GRANITOS
830	415	4679603	COMÉRCIO ATACADISTA DE VIDROS, ESPELHOS E VITRAIS
831	415	4679604	COMÉRCIO ATACADISTA ESPECIALIZADO DE MATERIAIS DE CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE
832	416	4681801	COMÉRCIO ATACADISTA DE ÁLCOOL CARBURANTE, BIODIESEL, GASOLINA E DEMAIS DERIVADOS DE PETRÓLEO, EXCETO LUBRIFICANTES, NÃO REALIZADO POR TRANSPORTADOR RETALHISTA (T.R.R.)
833	416	4681802	COMÉRCIO ATACADISTA DE COMBUSTÍVEIS REALIZADO POR TRANSPORTADOR RETALHISTA (T.R.R.)
834	416	4681803	COMÉRCIO ATACADISTA DE COMBUSTÍVEIS DE ORIGEM VEGETAL, EXCETO ÁLCOOL CARBURANTE
835	416	4681804	COMÉRCIO ATACADISTA DE COMBUSTÍVEIS DE ORIGEM MINERAL EM BRUTO
836	416	4681805	COMÉRCIO ATACADISTA DE LUBRIFICANTES
837	417	4682600	COMÉRCIO ATACADISTA DE GÁS LIQUEFEITO DE PETRÓLEO (GLP)
838	418	4683400	COMÉRCIO ATACADISTA DE DEFENSIVOS AGRÍCOLAS, ADUBOS, FERTILIZANTES E CORRETIVOS DO SOLO
839	419	4684201	COMÉRCIO ATACADISTA DE RESINAS E ELASTÔMEROS
840	419	4684202	COMÉRCIO ATACADISTA DE SOLVENTES
841	419	4684299	COMÉRCIO ATACADISTA DE OUTROS PRODUTOS QUÍMICOS E PETROQUÍMICOS NÃO ESPECIFICADOS ANTERIORMENTE
842	420	4685100	COMÉRCIO ATACADISTA DE PRODUTOS SIDERÚRGICOS E METALÚRGICOS, EXCETO PARA CONSTRUÇÃO
843	421	4686901	COMÉRCIO ATACADISTA DE PAPEL E PAPELÃO EM BRUTO
844	421	4686902	COMÉRCIO ATACADISTA DE EMBALAGENS
845	422	4687701	COMÉRCIO ATACADISTA DE RESÍDUOS DE PAPEL E PAPELÃO
846	422	4687702	COMÉRCIO ATACADISTA DE RESÍDUOS E SUCATAS NÃO METÁLICOS, EXCETO DE PAPEL E PAPELÃO
847	422	4687703	COMÉRCIO ATACADISTA DE RESÍDUOS E SUCATAS METÁLICOS
848	423	4689301	COMÉRCIO ATACADISTA DE PRODUTOS DA EXTRAÇÃO MINERAL, EXCETO COMBUSTÍVEIS
849	423	4689302	COMÉRCIO ATACADISTA DE FIOS E FIBRAS BENEFICIADOS
850	423	4689399	COMÉRCIO ATACADISTA ESPECIALIZADO EM OUTROS PRODUTOS INTERMEDIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
851	424	4691500	COMÉRCIO ATACADISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS
852	425	4692300	COMÉRCIO ATACADISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE INSUMOS AGROPECUÁRIOS
853	426	4693100	COMÉRCIO ATACADISTA DE MERCADORIAS EM GERAL, SEM PREDOMINÂNCIA DE ALIMENTOS OU DE INSUMOS AGROPECUÁRIOS
854	427	4711301	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS   HIPERMERCADOS
855	427	4711302	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS - SUPERMERCADOS
856	428	4712100	COMÉRCIO VAREJISTA DE MERCADORIAS EM GERAL, COM PREDOMINÂNCIA DE PRODUTOS ALIMENTÍCIOS - MINIMERCADOS, MERCEARIAS E ARMAZÉNS
857	429	4713002	LOJAS DE VARIEDADES, EXCETO LOJAS DE DEPARTAMENTOS OU MAGAZINES
858	429	4713005	LOJAS FRANCAS (DUTY FREE) DE AEROPORTOS, PORTOS E EM FRONTEIRAS TERRESTRES
859	429	4713004	LOJAS DE DEPARTAMENTOS OU MAGAZINES, EXCETO LOJAS FRANCAS (DUTY FREE)
860	430	4722901	COMÉRCIO VAREJISTA DE CARNES - AÇOUGUES
861	430	4722902	PEIXARIA
862	431	4723700	COMÉRCIO VAREJISTA DE BEBIDAS
863	432	4724500	COMÉRCIO VAREJISTA DE HORTIFRUTIGRANJEIROS
864	433	4721103	COMÉRCIO VAREJISTA DE LATICÍNIOS E FRIOS
865	433	4721102	PADARIA E CONFEITARIA COM PREDOMINÂNCIA DE REVENDA
866	433	4721104	COMÉRCIO VAREJISTA DE DOCES, BALAS, BOMBONS E SEMELHANTES
867	434	4729601	TABACARIA
868	434	4729602	COMÉRCIO VAREJISTA DE MERCADORIAS EM LOJAS DE CONVENIÊNCIA
869	434	4729699	COMÉRCIO VAREJISTA DE PRODUTOS ALIMENTÍCIOS EM GERAL OU ESPECIALIZADO EM PRODUTOS ALIMENTÍCIOS NÃO ESPECIFICADOS ANTERIORMENTE
870	435	4731800	COMÉRCIO VAREJISTA DE COMBUSTÍVEIS PARA VEÍCULOS AUTOMOTORES
871	436	4732600	COMÉRCIO VAREJISTA DE LUBRIFICANTES
872	437	4741500	COMÉRCIO VAREJISTA DE TINTAS E MATERIAIS PARA PINTURA
873	438	4742300	COMÉRCIO VAREJISTA DE MATERIAL ELÉTRICO
874	439	4743100	COMÉRCIO VAREJISTA DE VIDROS
875	440	4744001	COMÉRCIO VAREJISTA DE FERRAGENS E FERRAMENTAS
876	440	4744002	COMÉRCIO VAREJISTA DE MADEIRA E ARTEFATOS
877	440	4744003	COMÉRCIO VAREJISTA DE MATERIAIS HIDRÁULICOS
878	440	4744004	COMÉRCIO VAREJISTA DE CAL, AREIA, PEDRA BRITADA, TIJOLOS E TELHAS
879	440	4744005	COMÉRCIO VAREJISTA DE MATERIAIS DE CONSTRUÇÃO NÃO ESPECIFICADOS ANTERIORMENTE
880	440	4744006	COMÉRCIO VAREJISTA DE PEDRAS PARA REVESTIMENTO
881	440	4744099	COMÉRCIO VAREJISTA DE MATERIAIS DE CONSTRUÇÃO EM GERAL
882	441	4757100	COMÉRCIO VAREJISTA ESPECIALIZADO DE PEÇAS E ACESSÓRIOS PARA APARELHOS ELETROELETRÔNICOS PARA USO DOMÉSTICO, EXCETO INFORMÁTICA E COMUNICAÇÃO
883	442	4755501	COMÉRCIO VAREJISTA DE TECIDOS
884	442	4755502	COMERCIO VAREJISTA DE ARTIGOS DE ARMARINHO
885	442	4755503	COMERCIO VAREJISTA DE ARTIGOS DE CAMA, MESA E BANHO
886	443	4756300	COMÉRCIO VAREJISTA ESPECIALIZADO DE INSTRUMENTOS MUSICAIS E ACESSÓRIOS
887	444	4751201	COMÉRCIO VAREJISTA ESPECIALIZADO DE EQUIPAMENTOS E SUPRIMENTOS DE INFORMÁTICA
888	444	4751202	RECARGA DE CARTUCHOS PARA EQUIPAMENTOS DE INFORMÁTICA
889	445	4752100	COMÉRCIO VAREJISTA ESPECIALIZADO DE EQUIPAMENTOS DE TELEFONIA E COMUNICAÇÃO
890	446	4753900	COMÉRCIO VAREJISTA ESPECIALIZADO DE ELETRODOMÉSTICOS E EQUIPAMENTOS DE ÁUDIO E VÍDEO
891	447	4754701	COMÉRCIO VAREJISTA DE MÓVEIS
892	447	4754702	COMÉRCIO VAREJISTA DE ARTIGOS DE COLCHOARIA
893	447	4754703	COMÉRCIO VAREJISTA DE ARTIGOS DE ILUMINAÇÃO
894	448	4759801	COMÉRCIO VAREJISTA DE ARTIGOS DE TAPEÇARIA, CORTINAS E PERSIANAS
895	448	4759899	COMÉRCIO VAREJISTA DE OUTROS ARTIGOS DE USO PESSOAL E DOMÉSTICO NÃO ESPECIFICADOS ANTERIORMENTE
896	449	4761001	COMÉRCIO VAREJISTA DE LIVROS
897	449	4761002	COMÉRCIO VAREJISTA DE JORNAIS E REVISTAS
898	449	4761003	COMÉRCIO VAREJISTA DE ARTIGOS DE PAPELARIA
899	450	4762800	COMÉRCIO VAREJISTA DE DISCOS, CDS, DVDS E FITAS
900	451	4763603	COMÉRCIO VAREJISTA DE BICICLETAS E TRICICLOS; PEÇAS E ACESSÓRIOS
901	451	4763604	COMÉRCIO VAREJISTA DE ARTIGOS DE CAÇA, PESCA E CAMPING
902	451	4763601	COMÉRCIO VAREJISTA DE BRINQUEDOS E ARTIGOS RECREATIVOS
903	451	4763602	COMÉRCIO VAREJISTA DE ARTIGOS ESPORTIVOS
904	451	4763605	COMÉRCIO VAREJISTA DE EMBARCAÇÕES E OUTROS VEÍCULOS RECREATIVOS; PEÇAS E ACESSÓRIOS
905	452	4771701	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, SEM MANIPULAÇÃO DE FÓRMULAS
906	452	4771702	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS, COM MANIPULAÇÃO DE FÓRMULAS
907	452	4771703	COMÉRCIO VAREJISTA DE PRODUTOS FARMACÊUTICOS HOMEOPÁTICOS
908	452	4771704	COMÉRCIO VAREJISTA DE MEDICAMENTOS VETERINÁRIOS
909	453	4772500	COMÉRCIO VAREJISTA DE COSMÉTICOS, PRODUTOS DE PERFUMARIA E DE HIGIENE PESSOAL
910	454	4773300	COMÉRCIO VAREJISTA DE ARTIGOS MÉDICOS E ORTOPÉDICOS
911	455	4774100	COMÉRCIO VAREJISTA DE ARTIGOS DE ÓPTICA
912	456	4781400	COMÉRCIO VAREJISTA DE ARTIGOS DO VESTUÁRIO E ACESSÓRIOS
913	457	4782201	COMÉRCIO VAREJISTA DE CALÇADOS
914	457	4782202	COMÉRCIO VAREJISTA DE ARTIGOS DE VIAGEM
915	458	4783101	COMÉRCIO VAREJISTA DE ARTIGOS DE JOALHERIA
916	458	4783102	COMÉRCIO VAREJISTA DE ARTIGOS DE RELOJOARIA
917	459	4784900	COMÉRCIO VAREJISTA DE GÁS LIQUEFEITO DE PETRÓLEO (GLP)
918	460	4785701	COMÉRCIO VAREJISTA DE ANTIGUIDADES
919	460	4785799	COMÉRCIO VAREJISTA DE OUTROS ARTIGOS USADOS
920	461	4789001	COMÉRCIO VAREJISTA DE SUVENIRES, BIJUTERIAS E ARTESANATOS
921	461	4789002	COMÉRCIO VAREJISTA DE PLANTAS E FLORES NATURAIS
922	461	4789003	COMÉRCIO VAREJISTA DE OBJETOS DE ARTE
923	461	4789004	COMÉRCIO VAREJISTA DE ANIMAIS VIVOS E DE ARTIGOS E ALIMENTOS PARA ANIMAIS DE ESTIMAÇÃO
924	461	4789005	COMÉRCIO VAREJISTA DE PRODUTOS SANEANTES DOMISSANITÁRIOS
925	461	4789006	COMÉRCIO VAREJISTA DE FOGOS DE ARTIFÍCIO E ARTIGOS PIROTÉCNICOS
926	461	4789007	COMÉRCIO VAREJISTA DE EQUIPAMENTOS PARA ESCRITÓRIO
927	461	4789008	COMÉRCIO VAREJISTA DE ARTIGOS FOTOGRÁFICOS E PARA FILMAGEM
928	461	4789009	COMÉRCIO VAREJISTA DE ARMAS E MUNIÇÕES
929	461	4789099	COMÉRCIO VAREJISTA DE OUTROS PRODUTOS NÃO ESPECIFICADOS ANTERIORMENTE
930	462	4911600	TRANSPORTE FERROVIÁRIO DE CARGA
931	463	4912401	TRANSPORTE FERROVIÁRIO DE PASSAGEIROS INTERMUNICIPAL E INTERESTADUAL
932	463	4912402	TRANSPORTE FERROVIÁRIO DE PASSAGEIROS MUNICIPAL E EM REGIÃO METROPOLITANA
933	463	4912403	TRANSPORTE METROVIÁRIO
934	464	4921301	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, MUNICIPAL
935	464	4921302	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, INTERMUNICIPAL EM REGIÃO METROPOLITANA
936	465	4922101	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, INTERMUNICIPAL, EXCETO EM REGIÃO METROPOLITANA
937	465	4922102	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, INTERESTADUAL
938	465	4922103	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, COM ITINERÁRIO FIXO, INTERNACIONAL
939	466	4923001	SERVIÇO DE TÁXI
940	466	4923002	SERVIÇO DE TRANSPORTE DE PASSAGEIROS - LOCAÇÃO DE AUTOMÓVEIS COM MOTORISTA
941	467	4924800	TRANSPORTE ESCOLAR
942	468	4929902	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, SOB REGIME DE FRETAMENTO, INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL
943	468	4929901	TRANSPORTE RODOVIÁRIO COLETIVO DE PASSAGEIROS, SOB REGIME DE FRETAMENTO, MUNICIPAL
944	468	4929903	ORGANIZAÇÃO DE EXCURSÕES EM VEÍCULOS RODOVIÁRIOS PRÓPRIOS, MUNICIPAL
945	468	4929904	ORGANIZAÇÃO DE EXCURSÕES EM VEÍCULOS RODOVIÁRIOS PRÓPRIOS, INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL
946	468	4929999	OUTROS TRANSPORTES RODOVIÁRIOS DE PASSAGEIROS NÃO ESPECIFICADOS ANTERIORMENTE
947	469	4930201	TRANSPORTE RODOVIÁRIO DE CARGA, EXCETO PRODUTOS PERIGOSOS E MUDANÇAS, MUNICIPAL
948	469	4930202	TRANSPORTE RODOVIÁRIO DE CARGA, EXCETO PRODUTOS PERIGOSOS E MUDANÇAS, INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL
949	469	4930203	TRANSPORTE RODOVIÁRIO DE PRODUTOS PERIGOSOS
950	469	4930204	TRANSPORTE RODOVIÁRIO DE MUDANÇAS
951	470	4940000	TRANSPORTE DUTOVIÁRIO
952	471	4950700	TRENS TURÍSTICOS, TELEFÉRICOS E SIMILARES
953	472	5011401	TRANSPORTE MARÍTIMO DE CABOTAGEM - CARGA
954	472	5011402	TRANSPORTE MARÍTIMO DE CABOTAGEM - PASSAGEIROS
955	473	5012201	TRANSPORTE MARÍTIMO DE LONGO CURSO - CARGA
956	473	5012202	TRANSPORTE MARÍTIMO DE LONGO CURSO - PASSAGEIROS
957	474	5022001	TRANSPORTE POR NAVEGAÇÃO INTERIOR DE PASSAGEIROS EM LINHAS REGULARES, MUNICIPAL, EXCETO TRAVESSIA
958	474	5022002	TRANSPORTE POR NAVEGAÇÃO INTERIOR DE PASSAGEIROS EM LINHAS REGULARES, INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL, EXCETO TRAVESSIA
959	475	5021101	TRANSPORTE POR NAVEGAÇÃO INTERIOR DE CARGA, MUNICIPAL, EXCETO TRAVESSIA
960	475	5021102	TRANSPORTE POR NAVEGAÇÃO INTERIOR DE CARGA, INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL, EXCETO TRAVESSIA
961	476	5030101	NAVEGAÇÃO DE APOIO MARÍTIMO
962	476	5030102	NAVEGAÇÃO DE APOIO PORTUÁRIO
963	476	5030103	SERVIÇO DE REBOCADORES E EMPURRADORES
964	477	5091201	TRANSPORTE POR NAVEGAÇÃO DE TRAVESSIA, MUNICIPAL
965	477	5091202	TRANSPORTE POR NAVEGAÇÃO DE TRAVESSIA INTERMUNICIPAL, INTERESTADUAL E INTERNACIONAL
966	478	5099801	TRANSPORTE AQUAVIÁRIO PARA PASSEIOS TURÍSTICOS
967	478	5099899	OUTROS TRANSPORTES AQUAVIÁRIOS NÃO ESPECIFICADOS ANTERIORMENTE
968	479	5111100	TRANSPORTE AÉREO DE PASSAGEIROS REGULAR
969	480	5112901	SERVIÇO DE TÁXI AÉREO E LOCAÇÃO DE AERONAVES COM TRIPULAÇÃO
970	480	5112999	OUTROS SERVIÇOS DE TRANSPORTE AÉREO DE PASSAGEIROS NÃO REGULAR
971	481	5120000	TRANSPORTE AÉREO DE CARGA
972	482	5130700	TRANSPORTE ESPACIAL
973	483	7111100	SERVIÇOS DE ARQUITETURA
974	484	7112000	SERVIÇOS DE ENGENHARIA
975	485	7119701	SERVIÇOS DE CARTOGRAFIA, TOPOGRAFIA E GEODÉSIA
976	485	7119702	ATIVIDADES DE ESTUDOS GEOLÓGICOS
977	485	7119703	SERVIÇOS DE DESENHO TÉCNICO RELACIONADOS À ARQUITETURA E ENGENHARIA
978	485	7119704	SERVIÇOS DE PERÍCIA TÉCNICA RELACIONADOS À SEGURANÇA DO TRABALHO
979	485	7119799	ATIVIDADES TÉCNICAS RELACIONADAS À ENGENHARIA E ARQUITETURA NÃO ESPECIFICADAS ANTERIORMENTE
980	486	7120100	TESTES E ANÁLISES TÉCNICAS
981	487	5811500	EDIÇÃO DE LIVROS
982	488	5812301	EDIÇÃO DE JORNAIS DIÁRIOS
983	488	5812302	EDIÇÃO DE JORNAIS NÃO DIÁRIOS
984	489	5813100	EDIÇÃO DE REVISTAS
985	490	5819100	EDIÇÃO DE CADASTROS, LISTAS E DE OUTROS PRODUTOS GRÁFICOS
986	491	5821200	EDIÇÃO INTEGRADA À IMPRESSÃO DE LIVROS
987	492	5822101	EDIÇÃO INTEGRADA À IMPRESSÃO DE JORNAIS DIÁRIOS
988	492	5822102	EDIÇÃO INTEGRADA À IMPRESSÃO DE JORNAIS NÃO DIÁRIOS
989	493	5823900	EDIÇÃO INTEGRADA À IMPRESSÃO DE REVISTAS
990	494	5829800	EDIÇÃO INTEGRADA À IMPRESSÃO DE CADASTROS, LISTAS E DE OUTROS PRODUTOS GRÁFICOS
991	495	5911101	ESTÚDIOS CINEMATOGRÁFICOS
992	495	5911102	PRODUÇÃO DE FILMES PARA PUBLICIDADE
993	495	5911199	ATIVIDADES DE PRODUÇÃO CINEMATOGRÁFICA, DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO NÃO ESPECIFICADAS ANTERIORMENTE
994	496	5912001	SERVIÇOS DE DUBLAGEM
995	496	5912002	SERVIÇOS DE MIXAGEM SONORA EM PRODUÇÃO AUDIOVISUAL
996	496	5912099	ATIVIDADES DE PÓS PRODUÇÃO CINEMATOGRÁFICA, DE VÍDEOS E DE PROGRAMAS DE TELEVISÃO NÃO ESPECIFICADAS ANTERIORMENTE
997	497	5913800	DISTRIBUIÇÃO CINEMATOGRÁFICA, DE VÍDEO E DE PROGRAMAS DE TELEVISÃO
998	498	5914600	ATIVIDADES DE EXIBIÇÃO CINEMATOGRÁFICA
999	499	5920100	ATIVIDADES DE GRAVAÇÃO DE SOM E DE EDIÇÃO DE MÚSICA
1000	500	6110803	SERVIÇOS DE COMUNICAÇÃO MULTIMÍDIA - SCM
1001	500	6110899	SERVIÇOS DE TELECOMUNICAÇÕES POR FIO NÃO ESPECIFICADOS ANTERIORMENTE
1002	500	6110801	SERVIÇOS DE TELEFONIA FIXA COMUTADA - STFC
1003	500	6110802	SERVIÇOS DE REDES DE TRANSPORTES DE TELECOMUNICAÇÕES - SRTT
1004	501	6120501	TELEFONIA MÓVEL CELULAR
1005	501	6120502	SERVIÇO MÓVEL ESPECIALIZADO - SME
1006	501	6120599	SERVIÇOS DE TELECOMUNICAÇÕES SEM FIO NÃO ESPECIFICADOS ANTERIORMENTE
1007	502	6130200	TELECOMUNICAÇÕES POR SATÉLITE
1008	503	6141800	OPERADORAS DE TELEVISÃO POR ASSINATURA POR CABO
1009	504	6142600	OPERADORAS DE TELEVISÃO POR ASSINATURA POR MICROONDAS
1010	505	6143400	OPERADORAS DE TELEVISÃO POR ASSINATURA POR SATÉLITE
1011	506	6190601	PROVEDORES DE ACESSO ÀS REDES DE COMUNICAÇÕES
1012	506	6190602	PROVEDORES DE VOZ SOBRE PROTOCOLO INTERNET - VOIP
1013	506	6190699	OUTRAS ATIVIDADES DE TELECOMUNICAÇÕES NÃO ESPECIFICADAS ANTERIORMENTE
1014	507	6201502	WEB DESIGN
1015	507	6201501	DESENVOLVIMENTO DE PROGRAMAS DE COMPUTADOR SOB ENCOMENDA
1016	508	6202300	DESENVOLVIMENTO E LICENCIAMENTO DE PROGRAMAS DE COMPUTADOR CUSTOMIZÁVEIS
1017	509	6203100	DESENVOLVIMENTO E LICENCIAMENTO DE PROGRAMAS DE COMPUTADOR NÃO CUSTOMIZÁVEIS
1018	510	6204000	CONSULTORIA EM TECNOLOGIA DA INFORMAÇÃO
1019	511	6209100	SUPORTE TÉCNICO, MANUTENÇÃO E OUTROS SERVIÇOS EM TECNOLOGIA DA INFORMAÇÃO
1020	512	6311900	TRATAMENTO DE DADOS, PROVEDORES DE SERVIÇOS DE APLICAÇÃO E SERVIÇOS DE HOSPEDAGEM NA INTERNET
1021	513	6319400	PORTAIS, PROVEDORES DE CONTEÚDO E OUTROS SERVIÇOS DE INFORMAÇÃO NA INTERNET
1022	514	6391700	AGÊNCIAS DE NOTÍCIAS
1023	515	6399200	OUTRAS ATIVIDADES DE PRESTAÇÃO DE SERVIÇOS DE INFORMAÇÃO NÃO ESPECIFICADAS ANTERIORMENTE
1024	516	6410700	BANCO CENTRAL
1025	517	6423900	CAIXAS ECONÔMICAS
1026	518	6422100	BANCOS MÚLTIPLOS, COM CARTEIRA COMERCIAL
1027	519	6421200	BANCOS COMERCIAIS
1028	520	6424701	BANCOS COOPERATIVOS
1029	520	6424702	COOPERATIVAS CENTRAIS DE CRÉDITO
1030	520	6424703	COOPERATIVAS DE CRÉDITO MÚTUO
1031	520	6424704	COOPERATIVAS DE CRÉDITO RURAL
1032	521	6431000	BANCOS MÚLTIPLOS, SEM CARTEIRA COMERCIAL
1033	522	6432800	BANCOS DE INVESTIMENTO
1034	523	6433600	BANCOS DE DESENVOLVIMENTO
1035	524	6434400	AGÊNCIAS DE FOMENTO
1036	525	6435201	SOCIEDADES DE CRÉDITO IMOBILIÁRIO
1037	525	6435202	ASSOCIAÇÕES DE POUPANÇA E EMPRÉSTIMO
1038	525	6435203	COMPANHIAS HIPOTECÁRIAS
1039	526	6436100	SOCIEDADES DE CRÉDITO, FINANCIAMENTO E INVESTIMENTO - FINANCEIRAS
1040	527	6437900	SOCIEDADES DE CRÉDITO AO MICROEMPREENDEDOR
1041	528	6438701	BANCOS DE CÂMBIO
1042	528	6438799	OUTRAS INSTITUIÇÕES DE INTERMEDIAÇÃO NÃO MONETÁRIA
1043	529	6440900	ARRENDAMENTO MERCANTIL
1044	530	6450600	SOCIEDADES DE CAPITALIZAÇÃO
1045	531	6461100	HOLDINGS DE INSTITUIÇÕES FINANCEIRAS
1046	532	6462000	HOLDINGS DE INSTITUIÇÕES NÃO FINANCEIRAS
1047	533	6463800	OUTRAS SOCIEDADES DE PARTICIPAÇÃO, EXCETO HOLDINGS
1048	534	6470102	FUNDOS DE INVESTIMENTO PREVIDENCIÁRIOS
1049	534	6470103	FUNDOS DE INVESTIMENTO IMOBILIÁRIOS
1050	534	6470101	FUNDOS DE INVESTIMENTO, EXCETO PREVIDENCIÁRIOS E IMOBILIÁRIOS
1051	535	6491300	SOCIEDADES DE FOMENTO MERCANTIL - FACTORING
1052	536	6492100	SECURITIZAÇÃO DE CRÉDITOS
1053	537	6493000	ADMINISTRAÇÃO DE CONSÓRCIOS PARA AQUISIÇÃO DE BENS E DIREITOS
1054	538	6499901	CLUBES DE INVESTIMENTO
1055	538	6499902	SOCIEDADES DE INVESTIMENTO
1056	538	6499903	FUNDO GARANTIDOR DE CRÉDITO
1057	538	6499904	CAIXAS DE FINANCIAMENTO DE CORPORAÇÕES
1058	538	6499905	CONCESSÃO DE CRÉDITO PELAS OSCIP
1059	538	6499999	OUTRAS ATIVIDADES DE SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
1060	539	6511101	SOCIEDADE SEGURADORA DE SEGUROS VIDA
1061	539	6511102	PLANOS DE AUXÍLIO FUNERAL
1062	540	6512000	SOCIEDADE SEGURADORA DE SEGUROS NÃO VIDA
1063	541	6520100	SOCIEDADE SEGURADORA DE SEGUROS SAÚDE
1064	542	6530800	RESSEGUROS
1065	543	6541300	PREVIDÊNCIA COMPLEMENTAR FECHADA
1066	544	6542100	PREVIDÊNCIA COMPLEMENTAR ABERTA
1067	545	6550200	PLANOS DE SAÚDE
1068	546	6611802	BOLSA DE MERCADORIAS
1069	546	6611803	BOLSA DE MERCADORIAS E FUTUROS
1070	546	6611804	ADMINISTRAÇÃO DE MERCADOS DE BALCÃO ORGANIZADOS
1071	546	6611801	BOLSA DE VALORES
1072	547	6612602	DISTRIBUIDORAS DE TÍTULOS E VALORES MOBILIÁRIOS
1073	547	6612603	CORRETORAS DE CÂMBIO
1074	547	6612604	CORRETORAS DE CONTRATOS DE MERCADORIAS
1075	547	6612601	CORRETORAS DE TÍTULOS E VALORES MOBILIÁRIOS
1076	547	6612605	AGENTES DE INVESTIMENTOS EM APLICAÇÕES FINANCEIRAS
1077	548	6613400	ADMINISTRAÇÃO DE CARTÕES DE CRÉDITO
1078	549	6619304	CAIXAS ELETRÔNICOS
1079	549	6619305	OPERADORAS DE CARTÕES DE DÉBITO
1080	549	6619399	OUTRAS ATIVIDADES AUXILIARES DOS SERVIÇOS FINANCEIROS NÃO ESPECIFICADAS ANTERIORMENTE
1081	549	6619301	SERVIÇOS DE LIQUIDAÇÃO E CUSTÓDIA
1082	549	6619302	CORRESPONDENTES DE INSTITUIÇÕES FINANCEIRAS
1083	549	6619303	REPRESENTAÇÕES DE BANCOS ESTRANGEIROS
1084	550	6621502	AUDITORIA E CONSULTORIA ATUARIAL
1085	550	6621501	PERITOS E AVALIADORES DE SEGUROS
1086	551	6622300	CORRETORES E AGENTES DE SEGUROS, DE PLANOS DE PREVIDÊNCIA COMPLEMENTAR E DE SAÚDE
1168	598	8121400	LIMPEZA EM PRÉDIOS E EM DOMICÍLIOS
1087	552	6629100	ATIVIDADES AUXILIARES DOS SEGUROS, DA PREVIDÊNCIA COMPLEMENTAR E DOS PLANOS DE SAÚDE NÃO ESPECIFICADAS ANTERIORMENTE
1088	553	6630400	ATIVIDADES DE ADMINISTRAÇÃO DE FUNDOS POR CONTRATO OU COMISSÃO
1089	554	6810201	COMPRA E VENDA DE IMÓVEIS PRÓPRIOS
1090	554	6810202	ALUGUEL DE IMÓVEIS PRÓPRIOS
1091	554	6810203	LOTEAMENTO DE IMÓVEIS PRÓPRIOS
1092	555	6821801	CORRETAGEM NA COMPRA E VENDA E AVALIAÇÃO DE IMÓVEIS
1093	555	6821802	CORRETAGEM NO ALUGUEL DE IMÓVEIS
1094	556	6822600	GESTÃO E ADMINISTRAÇÃO DA PROPRIEDADE IMOBILIARIA
1095	557	6911701	SERVIÇOS ADVOCATÍCIOS
1096	557	6911703	AGENTE DE PROPRIEDADE INDUSTRIAL
1097	557	6911702	ATIVIDADES AUXILIARES DA JUSTIÇA
1098	558	6912500	CARTÓRIOS
1099	559	6920601	ATIVIDADES DE CONTABILIDADE
1100	559	6920602	ATIVIDADES DE CONSULTORIA E AUDITORIA CONTÁBIL E TRIBUTÁRIA
1101	560	7020400	ATIVIDADES DE CONSULTORIA EM GESTÃO EMPRESARIAL, EXCETO CONSULTORIA TÉCNICA ESPECÍFICA
1102	561	7210000	PESQUISA E DESENVOLVIMENTO EXPERIMENTAL EM CIÊNCIAS FÍSICAS E NATURAIS
1103	562	7220700	PESQUISA E DESENVOLVIMENTO EXPERIMENTAL EM CIÊNCIAS SOCIAIS E HUMANAS
1104	563	7311400	AGÊNCIAS DE PUBLICIDADE
1105	564	7312200	AGENCIAMENTO DE ESPAÇOS PARA PUBLICIDADE, EXCETO EM VEÍCULOS DE COMUNICAÇÃO
1106	565	7319001	CRIAÇÃO ESTANDES PARA FEIRAS E EXPOSIÇÕES
1107	565	7319002	PROMOÇÃO DE VENDAS
1108	565	7319003	MARKETING DIRETO
1109	565	7319004	CONSULTORIA EM PUBLICIDADE
1110	565	7319099	OUTRAS ATIVIDADES DE PUBLICIDADE NÃO ESPECIFICADAS ANTERIORMENTE
1111	566	7320300	PESQUISAS DE MERCADO E DE OPINIÃO PÚBLICA
1112	567	7410202	DESIGN DE INTERIORES
1113	567	7410203	DESIGN DE PRODUTO
1114	567	7410299	ATIVIDADES DE DESIGN NÃO ESPECIFICADAS ANTERIORMENTE
1115	568	7420001	ATIVIDADES DE PRODUÇÃO DE FOTOGRAFIAS, EXCETO AÉREA E SUBMARINA
1116	568	7420002	ATIVIDADES DE PRODUÇÃO DE FOTOGRAFIAS AÉREAS E SUBMARINAS
1117	568	7420003	LABORATÓRIOS FOTOGRÁFICOS
1118	568	7420004	FILMAGEM DE FESTAS E EVENTOS
1119	568	7420005	SERVIÇOS DE MICROFILMAGEM
1120	569	7490102	ESCAFANDRIA E MERGULHO
1121	569	7490101	SERVIÇOS DE TRADUÇÃO, INTERPRETAÇÃO E SIMILARES
1122	569	7490104	ATIVIDADES DE INTERMEDIAÇÃO E AGENCIAMENTO DE SERVIÇOS E NEGÓCIOS EM GERAL, EXCETO IMOBILIÁRIOS
1123	569	7490105	AGENCIAMENTO DE PROFISSIONAIS PARA ATIVIDADES ESPORTIVAS, CULTURAIS E ARTÍSTICAS
1124	569	7490199	OUTRAS ATIVIDADES PROFISSIONAIS, CIENTÍFICAS E TÉCNICAS NÃO ESPECIFICADAS ANTERIORMENTE
1125	569	7490103	SERVIÇOS DE AGRONOMIA E DE CONSULTORIA ÀS ATIVIDADES AGRÍCOLAS E PECUÁRIAS
1126	570	7500100	ATIVIDADES VETERINÁRIAS
1127	571	9101500	ATIVIDADES DE BIBLIOTECAS E ARQUIVOS
1128	572	9102301	ATIVIDADES DE MUSEUS E DE EXPLORAÇÃO DE LUGARES E PRÉDIOS HISTÓRICOS E ATRAÇÕES SIMILARES
1129	572	9102302	RESTAURAÇÃO E CONSERVAÇÃO DE LUGARES E PRÉDIOS HISTÓRICOS
1130	573	9103100	ATIVIDADES DE JARDINS BOTÂNICOS, ZOOLÓGICOS, PARQUES NACIONAIS, RESERVAS ECOLÓGICAS E ÁREAS DE PROTEÇÃO AMBIENTAL
1131	574	9200301	CASAS DE BINGO
1132	574	9200302	EXPLORAÇÃO DE APOSTAS EM CORRIDAS DE CAVALOS
1133	574	9200399	EXPLORAÇÃO DE JOGOS DE AZAR E APOSTAS NÃO ESPECIFICADOS ANTERIORMENTE
1134	575	7711000	LOCAÇÃO DE AUTOMÓVEIS SEM CONDUTOR
1135	576	7719501	LOCAÇÃO DE EMBARCAÇÕES SEM TRIPULAÇÃO, EXCETO PARA FINS RECREATIVOS
1136	576	7719502	LOCAÇÃO DE AERONAVES SEM TRIPULAÇÃO
1137	576	7719599	LOCAÇÃO DE OUTROS MEIOS DE TRANSPORTE NÃO ESPECIFICADOS ANTERIORMENTE, SEM CONDUTOR
1138	577	7721700	ALUGUEL DE EQUIPAMENTOS RECREATIVOS E ESPORTIVOS
1139	578	7722500	ALUGUEL DE FITAS DE VÍDEO, DVDS E SIMILARES
1140	579	7723300	ALUGUEL DE OBJETOS DO VESTUÁRIO, JÓIAS E ACESSÓRIOS
1141	580	7729201	ALUGUEL DE APARELHOS DE JOGOS ELETRÔNICOS
1142	580	7729202	ALUGUEL DE MÓVEIS, UTENSÍLIOS E APARELHOS DE USO DOMÉSTICO E PESSOAL; INSTRUMENTOS MUSICAIS
1143	580	7729203	ALUGUEL DE MATERIAL MÉDICO
1144	580	7729299	ALUGUEL DE OUTROS OBJETOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
1145	581	7731400	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS AGRÍCOLAS SEM OPERADOR
1146	582	7732201	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS PARA CONSTRUÇÃO SEM OPERADOR, EXCETO ANDAIMES
1147	582	7732202	ALUGUEL DE ANDAIMES
1148	583	7733100	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS PARA ESCRITÓRIOS
1149	584	7739001	ALUGUEL DE MÁQUINAS E EQUIPAMENTOS PARA EXTRAÇÃO DE MINÉRIOS E PETRÓLEO, SEM OPERADOR
1150	584	7739002	ALUGUEL DE EQUIPAMENTOS CIENTÍFICOS, MÉDICOS E HOSPITALARES, SEM OPERADOR
1151	584	7739003	ALUGUEL DE PALCOS, COBERTURAS E OUTRAS ESTRUTURAS DE USO TEMPORÁRIO, EXCETO ANDAIMES
1152	584	7739099	ALUGUEL DE OUTRAS MÁQUINAS E EQUIPAMENTOS COMERCIAIS E INDUSTRIAIS NÃO ESPECIFICADOS ANTERIORMENTE, SEM OPERADOR
1153	585	7740300	GESTÃO DE ATIVOS INTANGÍVEIS NÃO FINANCEIROS
1154	586	7810800	SELEÇÃO E AGENCIAMENTO DE MÃO DE OBRA
1155	587	7820500	LOCAÇÃO DE MÃO DE OBRA TEMPORÁRIA
1156	588	7830200	FORNECIMENTO E GESTÃO DE RECURSOS HUMANOS PARA TERCEIROS
1157	589	7911200	AGÊNCIAS DE VIAGENS
1158	590	7912100	OPERADORES TURÍSTICOS
1159	591	7990200	SERVIÇOS DE RESERVAS E OUTROS SERVIÇOS DE TURISMO NÃO ESPECIFICADOS ANTERIORMENTE
1160	592	8011101	ATIVIDADES DE VIGILÂNCIA E SEGURANÇA PRIVADA
1161	592	8011102	SERVIÇOS DE ADESTRAMENTO DE CÃES DE GUARDA
1162	593	8012900	ATIVIDADES DE TRANSPORTE DE VALORES
1163	594	8020001	ATIVIDADES DE MONITORAMENTO DE SISTEMAS DE SEGURANÇA ELETRÔNICO
1164	594	8020002	OUTRAS ATIVIDADES DE SERVIÇOS DE SEGURANÇA
1165	595	8030700	ATIVIDADES DE INVESTIGAÇÃO PARTICULAR
1166	596	8111700	SERVIÇOS COMBINADOS PARA APOIO A EDIFÍCIOS, EXCETO CONDOMÍNIOS PREDIAIS
1167	597	8112500	CONDOMÍNIOS PREDIAIS
1169	599	8122200	IMUNIZAÇÃO E CONTROLE DE PRAGAS URBANAS
1170	600	8129000	ATIVIDADES DE LIMPEZA NÃO ESPECIFICADAS ANTERIORMENTE
1171	601	8130300	ATIVIDADES PAISAGÍSTICAS
1172	602	8211300	SERVIÇOS COMBINADOS DE ESCRITÓRIO E APOIO ADMINISTRATIVO
1173	603	8219901	FOTOCÓPIAS
1174	603	8219999	PREPARAÇÃO DE DOCUMENTOS E SERVIÇOS ESPECIALIZADOS DE APOIO ADMINISTRATIVO NÃO ESPECIFICADOS ANTERIORMENTE
1175	604	8220200	ATIVIDADES DE TELEATENDIMENTO
1176	605	8230002	CASAS DE FESTAS E EVENTOS
1177	605	8230001	SERVIÇOS DE ORGANIZAÇÃO DE FEIRAS, CONGRESSOS, EXPOSIÇÕES E FESTAS
1178	606	8291100	ATIVIDADES DE COBRANÇAS E INFORMAÇÕES CADASTRAIS
1179	607	8292000	ENVASAMENTO E EMPACOTAMENTO SOB CONTRATO
1180	608	8299701	MEDIÇÃO DE CONSUMO DE ENERGIA ELÉTRICA, GÁS E ÁGUA
1181	608	8299702	EMISSÃO DE VALES ALIMENTAÇÃO, VALES TRANSPORTE E SIMILARES
1182	608	8299703	SERVIÇOS DE GRAVAÇÃO DE CARIMBOS, EXCETO CONFECÇÃO
1183	608	8299704	LEILOEIROS INDEPENDENTES
1184	608	8299705	SERVIÇOS DE LEVANTAMENTO DE FUNDOS SOB CONTRATO
1185	608	8299706	CASAS LOTÉRICAS
1186	608	8299707	SALAS DE ACESSO À INTERNET
1187	608	8299799	OUTRAS ATIVIDADES DE SERVIÇOS PRESTADOS PRINCIPALMENTE ÀS EMPRESAS NÃO ESPECIFICADAS ANTERIORMENTE
1188	609	8411600	ADMINISTRAÇÃO PÚBLICA EM GERAL
1189	610	8412400	REGULAÇÃO DAS ATIVIDADES DE SAÚDE, EDUCAÇÃO, SERVIÇOS CULTURAIS E OUTROS SERVIÇOS SOCIAIS
1190	611	8413200	REGULAÇÃO DAS ATIVIDADES ECONÔMICAS
1191	612	8421300	RELAÇÕES EXTERIORES
1192	613	8422100	DEFESA
1193	614	8423000	JUSTIÇA
1194	615	8424800	SEGURANÇA E ORDEM PÚBLICA
1195	616	8425600	DEFESA CIVIL
1196	617	8430200	SEGURIDADE SOCIAL OBRIGATÓRIA
1197	618	8511200	EDUCAÇÃO INFANTIL - CRECHE
1198	619	8512100	EDUCAÇÃO INFANTIL - PRÉESCOLA
1199	620	8513900	ENSINO FUNDAMENTAL
1200	621	8520100	ENSINO MÉDIO
1201	622	8533300	EDUCAÇÃO SUPERIOR - PÓS GRADUAÇÃO E EXTENSÃO
1202	623	8531700	EDUCAÇÃO SUPERIOR - GRADUAÇÃO
1203	624	8532500	EDUCAÇÃO SUPERIOR - GRADUAÇÃO E PÓS GRADUAÇÃO
1204	625	8541400	EDUCAÇÃO PROFISSIONAL DE NÍVEL TÉCNICO
1205	626	8542200	EDUCAÇÃO PROFISSIONAL DE NÍVEL TECNOLÓGICO
1206	627	8550301	ADMINISTRAÇÃO DE CAIXAS ESCOLARES
1207	627	8550302	ATIVIDADES DE APOIO À EDUCAÇÃO, EXCETO CAIXAS ESCOLARES
1208	628	8591100	ENSINO DE ESPORTES
1209	629	8592901	ENSINO DE DANÇA
1210	629	8592902	ENSINO DE ARTES CÊNICAS, EXCETO DANÇA
1211	629	8592903	ENSINO DE MÚSICA
1212	629	8592999	ENSINO DE ARTE E CULTURA NÃO ESPECIFICADO ANTERIORMENTE
1213	630	8593700	ENSINO DE IDIOMAS
1214	631	8599601	FORMAÇÃO DE CONDUTORES
1215	631	8599602	CURSOS DE PILOTAGEM
1216	631	8599603	TREINAMENTO EM INFORMÁTICA
1217	631	8599604	TREINAMENTO EM DESENVOLVIMENTO PROFISSIONAL E GERENCIAL
1218	631	8599605	CURSOS PREPARATÓRIOS PARA CONCURSOS
1219	631	8599699	OUTRAS ATIVIDADES DE ENSINO NÃO ESPECIFICADAS ANTERIORMENTE
1220	632	8610101	ATIVIDADES DE ATENDIMENTO HOSPITALAR, EXCETO PRONTO SOCORRO E UNIDADES PARA ATENDIMENTO A URGÊNCIAS
1221	632	8610102	ATIVIDADES DE ATENDIMENTO EM PRONTO SOCORRO E UNIDADES HOSPITALARES PARA ATENDIMENTO A URGÊNCIAS
1222	633	8621601	UTI MÓVEL
1223	633	8621602	SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS, EXCETO POR UTI MÓVEL
1224	634	8622400	SERVIÇOS DE REMOÇÃO DE PACIENTES, EXCETO OS SERVIÇOS MÓVEIS DE ATENDIMENTO A URGÊNCIAS
1225	635	8630599	ATIVIDADES DE ATENÇÃO AMBULATORIAL NÃO ESPECIFICADAS ANTERIORMENTE
1226	635	8630501	ATIVIDADE MÉDICA AMBULATORIAL COM RECURSOS PARA REALIZAÇÃO DE PROCEDIMENTOS CIRÚRGICOS
1227	635	8630502	ATIVIDADE MÉDICA AMBULATORIAL COM RECURSOS PARA REALIZAÇÃO DE EXAMES COMPLEMENTARES
1228	635	8630503	ATIVIDADE MÉDICA AMBULATORIAL RESTRITA A CONSULTAS
1229	635	8630504	ATIVIDADE ODONTOLÓGICA
1230	635	8630506	SERVIÇOS DE VACINAÇÃO E IMUNIZAÇÃO HUMANA
1231	635	8630507	ATIVIDADES DE REPRODUÇÃO HUMANA ASSISTIDA
1232	636	8640201	LABORATÓRIOS DE ANATOMIA PATOLÓGICA E CITOLÓGICA
1233	636	8640202	LABORATÓRIOS CLÍNICOS
1234	636	8640203	SERVIÇOS DE DIÁLISE E NEFROLOGIA
1235	636	8640204	SERVIÇOS DE TOMOGRAFIA
1236	636	8640205	SERVIÇOS DE DIAGNÓSTICO POR IMAGEM COM USO DE RADIAÇÃO IONIZANTE, EXCETO TOMOGRAFIA
1237	636	8640206	SERVIÇOS DE RESSONÂNCIA MAGNÉTICA
1238	636	8640207	SERVIÇOS DE DIAGNÓSTICO POR IMAGEM SEM USO DE RADIAÇÃO IONIZANTE, EXCETO RESSONÂNCIA MAGNÉTICA
1239	636	8640208	SERVIÇOS DE DIAGNÓSTICO POR REGISTRO GRÁFICO - ECG, EEG E OUTROS EXAMES ANÁLOGOS
1240	636	8640209	SERVIÇOS DE DIAGNÓSTICO POR MÉTODOS ÓPTICOS - ENDOSCOPIA E OUTROS EXAMES ANÁLOGOS
1241	636	8640210	SERVIÇOS DE QUIMIOTERAPIA
1242	636	8640211	SERVIÇOS DE RADIOTERAPIA
1243	636	8640212	SERVIÇOS DE HEMOTERAPIA
1244	636	8640213	SERVIÇOS DE LITOTRIPCIA
1245	636	8640214	SERVIÇOS DE BANCOS DE CÉLULAS E TECIDOS HUMANOS
1246	636	8640299	ATIVIDADES DE SERVIÇOS DE COMPLEMENTAÇÃO DIAGNÓSTICA E TERAPÊUTICA NÃO ESPECIFICADAS ANTERIORMENTE
1247	637	8650006	ATIVIDADES DE FONOAUDIOLOGIA
1248	637	8650004	ATIVIDADES DE FISIOTERAPIA
1249	637	8650001	ATIVIDADES DE ENFERMAGEM
1250	637	8650002	ATIVIDADES DE PROFISSIONAIS DA NUTRIÇÃO
1251	637	8650003	ATIVIDADES DE PSICOLOGIA E PSICANÁLISE
1252	637	8650007	ATIVIDADES DE TERAPIA DE NUTRIÇÃO ENTERAL E PARENTERAL
1253	637	8650099	ATIVIDADES DE PROFISSIONAIS DA ÁREA DE SAÚDE NÃO ESPECIFICADAS ANTERIORMENTE
1254	637	8650005	ATIVIDADES DE TERAPIA OCUPACIONAL
1255	638	8660700	ATIVIDADES DE APOIO À GESTÃO DE SAÚDE
1256	639	8690901	ATIVIDADES DE PRÁTICAS INTEGRATIVAS E COMPLEMENTARES EM SAÚDE HUMANA
1257	639	8690902	ATIVIDADES DE BANCO DE LEITE HUMANO
1258	639	8690903	ATIVIDADES DE ACUPUNTURA
1259	639	8690904	ATIVIDADES DE PODOLOGIA
1260	639	8690999	OUTRAS ATIVIDADES DE ATENÇÃO À SAÚDE HUMANA NÃO ESPECIFICADAS ANTERIORMENTE
1261	640	8711501	CLÍNICAS E RESIDÊNCIAS GERIÁTRICAS
1262	640	8711502	INSTITUIÇÕES DE LONGA PERMANÊNCIA PARA IDOSOS
1263	640	8711503	ATIVIDADES DE ASSISTÊNCIA A DEFICIENTES FÍSICOS, IMUNODEPRIMIDOS E CONVALESCENTES
1264	640	8711504	CENTROS DE APOIO A PACIENTES COM CÂNCER E COM AIDS
1265	640	8711505	CONDOMÍNIOS RESIDENCIAIS PARA IDOSOS
1266	641	8712300	ATIVIDADES DE FORNECIMENTO DE INFRAESTRUTURA DE APOIO E ASSISTÊNCIA A PACIENTE NO DOMICÍLIO
1267	642	8720401	ATIVIDADES DE CENTROS DE ASSISTÊNCIA PSICOSSOCIAL
1268	642	8720499	ATIVIDADES DE ASSISTÊNCIA PSICOSSOCIAL E À SAÚDE A PORTADORES DE DISTÚRBIOS PSÍQUICOS, DEFICIÊNCIA MENTAL E DEPENDÊNCIA QUÍMICA E GRUPOS SIMILARES NÃO ESPECIFICADAS ANTERIORMENTE
1269	643	8730101	ORFANATOS
1270	643	8730102	ALBERGUES ASSISTENCIAIS
1271	643	8730199	ATIVIDADES DE ASSISTÊNCIA SOCIAL PRESTADAS EM RESIDÊNCIAS COLETIVAS E PARTICULARES NÃO ESPECIFICADAS ANTERIORMENTE
1272	644	8800600	SERVIÇOS DE ASSISTÊNCIA SOCIAL SEM ALOJAMENTO
1273	645	9001901	PRODUÇÃO TEATRAL
1274	645	9001902	PRODUÇÃO MUSICAL
1275	645	9001903	PRODUÇÃO DE ESPETÁCULOS DE DANÇA
1276	645	9001904	PRODUÇÃO DE ESPETÁCULOS CIRCENSES, DE MARIONETES E SIMILARES
1277	645	9001905	PRODUÇÃO DE ESPETÁCULOS DE RODEIOS, VAQUEJADAS E SIMILARES
1278	645	9001906	ATIVIDADES DE SONORIZAÇÃO E DE ILUMINAÇÃO
1279	645	9001999	ARTES CÊNICAS, ESPETÁCULOS E ATIVIDADES COMPLEMENTARES NÃO ESPECIFICADAS ANTERIORMENTE
1280	646	9002702	RESTAURAÇÃO DE OBRAS DE ARTE
1281	646	9002701	ATIVIDADES DE ARTISTAS PLÁSTICOS, JORNALISTAS INDEPENDENTES E ESCRITORES
1282	647	9003500	GESTÃO DE ESPAÇOS PARA ARTES CÊNICAS, ESPETÁCULOS E OUTRAS ATIVIDADES ARTÍSTICAS
1283	648	9311500	GESTÃO DE INSTALAÇÕES DE ESPORTES
1284	649	9312300	CLUBES SOCIAIS, ESPORTIVOS E SIMILARES
1285	650	9313100	ATIVIDADES DE CONDICIONAMENTO FÍSICO
1286	651	9319101	PRODUÇÃO E PROMOÇÃO DE EVENTOS ESPORTIVOS
1287	651	9319199	OUTRAS ATIVIDADES ESPORTIVAS NÃO ESPECIFICADAS ANTERIORMENTE
1288	652	9321200	PARQUES DE DIVERSÃO E PARQUES TEMÁTICOS
1289	653	9329801	DISCOTECAS, DANCETERIAS, SALÕES DE DANÇA E SIMILARES
1290	653	9329802	EXPLORAÇÃO DE BOLICHES
1291	653	9329803	EXPLORAÇÃO DE JOGOS DE SINUCA, BILHAR E SIMILARES
1292	653	9329804	EXPLORAÇÃO DE JOGOS ELETRÔNICOS RECREATIVOS
1293	653	9329899	OUTRAS ATIVIDADES DE RECREAÇÃO E LAZER NÃO ESPECIFICADAS ANTERIORMENTE
1294	654	9411100	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS PATRONAIS E EMPRESARIAIS
1295	655	9412001	ATIVIDADES DE FISCALIZAÇÃO PROFISSIONAL
1296	655	9412099	OUTRAS ATIVIDADES ASSOCIATIVAS PROFISSIONAIS
1297	656	9420100	ATIVIDADES DE ORGANIZAÇÕES SINDICAIS
1298	657	9430800	ATIVIDADES DE ASSOCIAÇÕES DE DEFESA DE DIREITOS SOCIAIS
1299	658	9491000	ATIVIDADES DE ORGANIZAÇÕES RELIGIOSAS OU FILOSÓFICAS
1300	659	9492800	ATIVIDADES DE ORGANIZAÇÕES POLÍTICAS
1301	660	9493600	ATIVIDADES DE ORGANIZAÇÕES ASSOCIATIVAS LIGADAS À CULTURA E À ARTE
1302	661	9499500	ATIVIDADES ASSOCIATIVAS NÃO ESPECIFICADAS ANTERIORMENTE
1303	662	9511800	REPARAÇÃO E MANUTENÇÃO DE COMPUTADORES E DE EQUIPAMENTOS PERIFÉRICOS
1304	663	9512600	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS DE COMUNICAÇÃO
1305	664	9521500	REPARAÇÃO E MANUTENÇÃO DE EQUIPAMENTOS ELETROELETRÔNICOS DE USO PESSOAL E DOMÉSTICO
1306	665	9529103	REPARAÇÃO DE RELÓGIOS
1307	665	9529101	REPARAÇÃO DE CALÇADOS, DE BOLSAS E ARTIGOS DE VIAGEM
1308	665	9529102	CHAVEIROS
1309	665	9529104	REPARAÇÃO DE BICICLETAS, TRICICLOS E OUTROS VEÍCULOS NÃO MOTORIZADOS
1310	665	9529105	REPARAÇÃO DE ARTIGOS DO MOBILIÁRIO
1311	665	9529106	REPARAÇÃO DE JÓIAS
1312	665	9529199	REPARAÇÃO E MANUTENÇÃO DE OUTROS OBJETOS E EQUIPAMENTOS PESSOAIS E DOMÉSTICOS NÃO ESPECIFICADOS ANTERIORMENTE
1313	666	9601701	LAVANDERIAS
1314	666	9601702	TINTURARIAS
1315	666	9601703	TOALHEIROS
1316	667	9602502	ATIVIDADES DE ESTÉTICA E OUTROS SERVIÇOS DE CUIDADOS COM A BELEZA
1317	667	9602501	CABELEIREIROS, MANICURE E PEDICURE
1318	668	9603302	SERVIÇOS DE CREMAÇÃO
1319	668	9603303	SERVIÇOS DE SEPULTAMENTO
1320	668	9603304	SERVIÇOS DE FUNERÁRIAS
1321	668	9603305	SERVIÇOS DE SOMATOCONSERVAÇÃO
1322	668	9603399	ATIVIDADES FUNERÁRIAS E SERVIÇOS RELACIONADOS NÃO ESPECIFICADOS ANTERIORMENTE
1323	668	9603301	GESTÃO E MANUTENÇÃO DE CEMITÉRIOS
1324	669	9609202	AGÊNCIAS MATRIMONIAIS
1325	669	9609204	EXPLORAÇÃO DE MÁQUINAS DE SERVIÇOS PESSOAIS ACIONADAS POR MOEDA
1326	669	9609205	ATIVIDADES DE SAUNA E BANHOS
1327	669	9609206	SERVIÇOS DE TATUAGEM E COLOCAÇÃO DE PIERCING
1328	669	9609207	ALOJAMENTO DE ANIMAIS DOMÉSTICOS
1329	669	9609208	HIGIENE E EMBELEZAMENTO DE ANIMAIS DOMÉSTICOS
1330	669	9609299	OUTRAS ATIVIDADES DE SERVIÇOS PESSOAIS NÃO ESPECIFICADAS ANTERIORMENTE
1331	670	9700500	SERVIÇOS DOMÉSTICOS
1332	671	9900800	ORGANISMOS INTERNACIONAIS E OUTRAS INSTITUIÇÕES EXTRATERRITORIAIS
\.


--
-- TOC entry 4855 (class 0 OID 17799)
-- Dependencies: 231
-- Data for Name: itenspassos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.itenspassos (id, grupopassos_id, passos_id) FROM stdin;
53306540-e85d-4804-b679-ea518f286b4a	8de1301f-ba9d-41d8-b391-db9e0b56ab9c	023b4bb7-6054-4e14-b93b-7354d5e95eb8
e592d7a5-7c8f-4115-828c-78aba53f8d20	8de1301f-ba9d-41d8-b391-db9e0b56ab9c	7b35949c-3740-4da9-99c0-a15bdf3ff6d5
\.


--
-- TOC entry 4856 (class 0 OID 17808)
-- Dependencies: 232
-- Data for Name: linkpassos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.linkpassos (passo_id, link) FROM stdin;
31445cac-91dc-4c21-bec2-adc240905b2e	www.jucesc.sc. gov.br
f45dc0a4-0a3e-4984-9a9d-a3ff706b3402	www.estado.sc.gov.br
b9206898-3ecd-4bd5-b83a-9249d5dd1bc2	www.prefeitura.sc.gov.br
5047a655-d6b3-431f-96fd-c7e4cbcb7ee0	www.dbe.sc.gov.br
d4ededcb-b5a2-402a-90e6-f4db735beb29	www.biguacu.sc.gov.br
1d64ff79-3192-4b28-a4b8-7654daea77f4	google.com
\.


--
-- TOC entry 4857 (class 0 OID 17815)
-- Dependencies: 233
-- Data for Name: municipio; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.municipio (id, nome, codigo, ufid, ativo) FROM stdin;
abfd20e5-d561-4c44-ba42-ae194ebb2c18	Florianópolis	2250	502caf63-be95-472f-9922-e8ba268fefa8	t
4a8647d1-06c8-4616-85be-3f6399949ed3	Guarujá	123123	59e0036a-4269-4297-a30a-d86a54dc4b7c	t
6a69c90c-8475-4d97-9e9a-8647305346f1	Biguaçu	2211	502caf63-be95-472f-9922-e8ba268fefa8	t
4c754d16-7a29-4682-80c6-a193dbe902f8	Santos	123123	59e0036a-4269-4297-a30a-d86a54dc4b7c	t
5e6b9b79-66ce-4119-af61-1fdf141c085b	Curitiba	123123	ad44e0c8-2fa2-41cb-bf50-2b30b79d57e6\n	t
f4ac2cb0-44a7-4d41-ad60-30818a39c37b	São Paulo	211221	59e0036a-4269-4297-a30a-d86a54dc4b7c	t
f5531987-ec10-4099-b940-b9bde36c0b16	Antonio Carlos	654321456	502caf63-be95-472f-9922-e8ba268fefa8	t
6ac92e36-0526-4a84-9364-c3a1d317b2f3	Palhoça	456456	502caf63-be95-472f-9922-e8ba268fefa8	t
371b1906-9454-4421-a6cf-a09e9909bf5a	Barueri	343412	59e0036a-4269-4297-a30a-d86a54dc4b7c	t
90b1ed2c-6a45-4977-9948-239a7335deac	São José	342423421	502caf63-be95-472f-9922-e8ba268fefa8	t
\.


--
-- TOC entry 4858 (class 0 OID 17826)
-- Dependencies: 234
-- Data for Name: passos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.passos (id, descricao, tempoestimado, createdat, updatedat, tipopasso, ativo, municipio_id) FROM stdin;
023b4bb7-6054-4e14-b93b-7354d5e95eb8	Checklist de Documentos e Informações Necessárias	4	2023-06-26 07:38:44.012	2023-06-26 07:38:44.012	M	t	abfd20e5-d561-4c44-ba42-ae194ebb2c18
31445cac-91dc-4c21-bec2-adc240905b2e	Viabilidade JUCESC	2	2023-06-26 07:38:44.012	2023-06-26 07:38:44.012	E	t	abfd20e5-d561-4c44-ba42-ae194ebb2c18
3fe622f0-96c4-4457-8c90-ae6ebcaf19b3	Viabilidade Instalação Prefeitura (caso aplicável)	3	2023-06-26 07:38:44.012	2023-06-26 07:38:44.012	M	t	abfd20e5-d561-4c44-ba42-ae194ebb2c18
91168e21-df97-4ab2-b1f5-ec35e9103efc	Implantar Processo na Junta	10	2023-06-26 07:38:44.012	2023-06-26 07:38:44.012	F	t	abfd20e5-d561-4c44-ba42-ae194ebb2c18
1236690c-828f-4459-895b-cc53a27ba9f4	Enviar Contrato Cliente e DARE	2	2023-07-18 15:08:23.606	2023-07-18 15:08:23.606	P	t	abfd20e5-d561-4c44-ba42-ae194ebb2c18
136e1f3e-1705-485f-9927-3074cc416e43	Assinar Contrato	3	2023-07-18 15:10:47.179	2023-07-18 15:10:47.179	P	t	abfd20e5-d561-4c44-ba42-ae194ebb2c18
e62ddd44-7581-4a91-8e9a-9200b92aba45	Enviar email interno	1	2023-07-18 15:10:47.179	2023-07-18 15:10:47.179	P	t	abfd20e5-d561-4c44-ba42-ae194ebb2c18
7b35949c-3740-4da9-99c0-a15bdf3ff6d5	Enviar email para Cliente	1	2023-07-18 15:16:39.945	2023-07-18 15:16:39.945	P	t	abfd20e5-d561-4c44-ba42-ae194ebb2c18
1d64ff79-3192-4b28-a4b8-7654daea77f4	Solicitar acesso Sistema Prefeitura 	10	2023-07-18 15:16:39.945	2023-07-18 15:16:39.945	M	t	abfd20e5-d561-4c44-ba42-ae194ebb2c18
9e705234-9d64-4b41-bca3-d71d94d2c323	Sistema Único  Cadastro	4	2023-07-18 15:10:47.179	2023-07-18 15:10:47.179	P	t	abfd20e5-d561-4c44-ba42-ae194ebb2c18
5047a655-d6b3-431f-96fd-c7e4cbcb7ee0	DBE	1	2023-06-26 07:38:44.012	2023-06-26 07:38:44.012	E	t	abfd20e5-d561-4c44-ba42-ae194ebb2c18
78417170-c0d7-4ca6-bbf4-4c69d994ccd8	Vínculo  Contador Prefeitura	5	2023-07-18 15:16:39.945	2023-07-18 15:16:39.945	M	t	6a69c90c-8475-4d97-9e9a-8647305346f1
b9206898-3ecd-4bd5-b83a-9249d5dd1bc2	Abrir processo na Prefeitura	3	2023-07-18 15:16:39.945	2023-07-18 15:16:39.945	M	t	6a69c90c-8475-4d97-9e9a-8647305346f1
f45dc0a4-0a3e-4984-9a9d-a3ff706b3402	Abrir Processo na Secretaria do Estado	3	2023-07-18 15:16:39.945	2023-07-18 15:16:39.945	P	t	6a69c90c-8475-4d97-9e9a-8647305346f1
d4ededcb-b5a2-402a-90e6-f4db735beb29	Abrir Processo na Prefeitura  de Biguaçu	3	2023-07-29 16:42:44.271	2023-07-29 16:42:44.271	M	t	6a69c90c-8475-4d97-9e9a-8647305346f1
e58d4218-1fa0-4a8a-a80f-fdb5ef245bef	Abrir Processo na Prefeitura de Guarujá	5	2023-08-23 07:43:19.504	2023-08-23 07:43:19.504	M	t	4a8647d1-06c8-4616-85be-3f6399949ed3
539fc0cb-a658-4d58-a6ee-5458593c772f	Passo X para abertura de Filial em Floripa	5	2023-09-22 16:41:48.102	2023-09-22 16:41:48.102	M	t	abfd20e5-d561-4c44-ba42-ae194ebb2c18
264e9bfa-aac4-4524-be04-9e569feb1d30	Passo demonstrativo para abertura de empresa no Guarujá	5	2023-09-26 09:26:36.034	2023-09-26 09:26:36.034	M	t	4a8647d1-06c8-4616-85be-3f6399949ed3
a13f2be9-4098-4a46-991e-2979f6dfc280	Enviar email (a quem de direito)	1	2023-09-26 09:27:00.747	2023-09-26 09:27:00.747	P	t	4a8647d1-06c8-4616-85be-3f6399949ed3
\.


--
-- TOC entry 4859 (class 0 OID 17842)
-- Dependencies: 235
-- Data for Name: rotinaitemlink; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.rotinaitemlink (rotinaitem_id, link) FROM stdin;
a5ee4f4e-9a78-4e4b-a02c-b379734699c3	www.jucesc.sc.gov.br
1d64ff79-3192-4b28-a4b8-7654daea77f4	www.pmbiguacu.gov.br
\.


--
-- TOC entry 4860 (class 0 OID 17848)
-- Dependencies: 236
-- Data for Name: rotinaitens; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.rotinaitens (rotina_id, passo_id, ordem) FROM stdin;
005a21fd-3aaa-43ee-a2e8-647a4d8845ab	023b4bb7-6054-4e14-b93b-7354d5e95eb8	0
005a21fd-3aaa-43ee-a2e8-647a4d8845ab	136e1f3e-1705-485f-9927-3074cc416e43	1
005a21fd-3aaa-43ee-a2e8-647a4d8845ab	7b35949c-3740-4da9-99c0-a15bdf3ff6d5	2
005a21fd-3aaa-43ee-a2e8-647a4d8845ab	31445cac-91dc-4c21-bec2-adc240905b2e	3
595ac1c0-fe5e-4a87-8871-9d9cce8fce04	78417170-c0d7-4ca6-bbf4-4c69d994ccd8	0
595ac1c0-fe5e-4a87-8871-9d9cce8fce04	b9206898-3ecd-4bd5-b83a-9249d5dd1bc2	1
595ac1c0-fe5e-4a87-8871-9d9cce8fce04	d4ededcb-b5a2-402a-90e6-f4db735beb29	2
595ac1c0-fe5e-4a87-8871-9d9cce8fce04	f45dc0a4-0a3e-4984-9a9d-a3ff706b3402	3
ee39ab7c-aa90-44ab-b6fe-9cc94a6b3225	5047a655-d6b3-431f-96fd-c7e4cbcb7ee0	0
ee39ab7c-aa90-44ab-b6fe-9cc94a6b3225	9e705234-9d64-4b41-bca3-d71d94d2c323	1
ee39ab7c-aa90-44ab-b6fe-9cc94a6b3225	1d64ff79-3192-4b28-a4b8-7654daea77f4	2
ee39ab7c-aa90-44ab-b6fe-9cc94a6b3225	1236690c-828f-4459-895b-cc53a27ba9f4	3
ee39ab7c-aa90-44ab-b6fe-9cc94a6b3225	7b35949c-3740-4da9-99c0-a15bdf3ff6d5	4
ee39ab7c-aa90-44ab-b6fe-9cc94a6b3225	91168e21-df97-4ab2-b1f5-ec35e9103efc	5
ee39ab7c-aa90-44ab-b6fe-9cc94a6b3225	3fe622f0-96c4-4457-8c90-ae6ebcaf19b3	6
ee39ab7c-aa90-44ab-b6fe-9cc94a6b3225	31445cac-91dc-4c21-bec2-adc240905b2e	7
005a21fd-3aaa-43ee-a2e8-647a4d8845ab	91168e21-df97-4ab2-b1f5-ec35e9103efc	4
005a21fd-3aaa-43ee-a2e8-647a4d8845ab	1236690c-828f-4459-895b-cc53a27ba9f4	5
005a21fd-3aaa-43ee-a2e8-647a4d8845ab	e62ddd44-7581-4a91-8e9a-9200b92aba45	6
005a21fd-3aaa-43ee-a2e8-647a4d8845ab	9e705234-9d64-4b41-bca3-d71d94d2c323	7
005a21fd-3aaa-43ee-a2e8-647a4d8845ab	5047a655-d6b3-431f-96fd-c7e4cbcb7ee0	8
005a21fd-3aaa-43ee-a2e8-647a4d8845ab	3fe622f0-96c4-4457-8c90-ae6ebcaf19b3	9
005a21fd-3aaa-43ee-a2e8-647a4d8845ab	1d64ff79-3192-4b28-a4b8-7654daea77f4	10
cbfc8f55-d3d0-42fb-a5d5-dd31f0dc643b	d4ededcb-b5a2-402a-90e6-f4db735beb29	0
cbfc8f55-d3d0-42fb-a5d5-dd31f0dc643b	78417170-c0d7-4ca6-bbf4-4c69d994ccd8	1
cbfc8f55-d3d0-42fb-a5d5-dd31f0dc643b	f45dc0a4-0a3e-4984-9a9d-a3ff706b3402	2
49241e34-99f6-4af3-98a2-cb39f251818a	136e1f3e-1705-485f-9927-3074cc416e43	0
49241e34-99f6-4af3-98a2-cb39f251818a	1236690c-828f-4459-895b-cc53a27ba9f4	1
49241e34-99f6-4af3-98a2-cb39f251818a	3fe622f0-96c4-4457-8c90-ae6ebcaf19b3	2
49241e34-99f6-4af3-98a2-cb39f251818a	7b35949c-3740-4da9-99c0-a15bdf3ff6d5	3
49241e34-99f6-4af3-98a2-cb39f251818a	5047a655-d6b3-431f-96fd-c7e4cbcb7ee0	4
49241e34-99f6-4af3-98a2-cb39f251818a	31445cac-91dc-4c21-bec2-adc240905b2e	5
ed925e14-d150-434f-b287-7154d67c1d0a	264e9bfa-aac4-4524-be04-9e569feb1d30	0
ed925e14-d150-434f-b287-7154d67c1d0a	e58d4218-1fa0-4a8a-a80f-fdb5ef245bef	1
6be4d4eb-d094-453d-bd52-579408300b45	3fe622f0-96c4-4457-8c90-ae6ebcaf19b3	0
6be4d4eb-d094-453d-bd52-579408300b45	539fc0cb-a658-4d58-a6ee-5458593c772f	1
6be4d4eb-d094-453d-bd52-579408300b45	136e1f3e-1705-485f-9927-3074cc416e43	2
6be4d4eb-d094-453d-bd52-579408300b45	5047a655-d6b3-431f-96fd-c7e4cbcb7ee0	3
6be4d4eb-d094-453d-bd52-579408300b45	7b35949c-3740-4da9-99c0-a15bdf3ff6d5	4
6be4d4eb-d094-453d-bd52-579408300b45	e62ddd44-7581-4a91-8e9a-9200b92aba45	5
8f07dcb1-7526-48d3-9d20-0816dd2baf5b	136e1f3e-1705-485f-9927-3074cc416e43	0
8f07dcb1-7526-48d3-9d20-0816dd2baf5b	1236690c-828f-4459-895b-cc53a27ba9f4	1
8f07dcb1-7526-48d3-9d20-0816dd2baf5b	3fe622f0-96c4-4457-8c90-ae6ebcaf19b3	2
8f07dcb1-7526-48d3-9d20-0816dd2baf5b	5047a655-d6b3-431f-96fd-c7e4cbcb7ee0	3
1cd6c238-d805-4c94-829e-bad7a9b62cfb	31445cac-91dc-4c21-bec2-adc240905b2e	0
1cd6c238-d805-4c94-829e-bad7a9b62cfb	5047a655-d6b3-431f-96fd-c7e4cbcb7ee0	1
1cd6c238-d805-4c94-829e-bad7a9b62cfb	7b35949c-3740-4da9-99c0-a15bdf3ff6d5	2
\.


--
-- TOC entry 4861 (class 0 OID 17855)
-- Dependencies: 237
-- Data for Name: rotinas; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.rotinas (id, descricao, municipio_id, ativo, tipo_empresa_id) FROM stdin;
5ac68905-e3cb-4acc-903e-2fbb2fe46b4b	Abertura MEI Campeche	abfd20e5-d561-4c44-ba42-ae194ebb2c18	f	\N
1cd6c238-d805-4c94-829e-bad7a9b62cfb	Abertura MEI Campeche	abfd20e5-d561-4c44-ba42-ae194ebb2c18	t	21a4bf05-3100-41e2-a3b2-e59ff67fc897
595ac1c0-fe5e-4a87-8871-9d9cce8fce04	Abertura LTDA Biguaçu	6a69c90c-8475-4d97-9e9a-8647305346f1	t	190016eb-d7df-419c-a203-fbdec2e6f379
6be4d4eb-d094-453d-bd52-579408300b45	Abertura de Filial Florianópolis	abfd20e5-d561-4c44-ba42-ae194ebb2c18	t	190016eb-d7df-419c-a203-fbdec2e6f379
005a21fd-3aaa-43ee-a2e8-647a4d8845ab	Abertura EIRELI Florianópolis	abfd20e5-d561-4c44-ba42-ae194ebb2c18	t	826e668b-9df0-44a8-9ae1-baa25e383aaa
ed925e14-d150-434f-b287-7154d67c1d0a	Abertura Ltda Guarujá	4a8647d1-06c8-4616-85be-3f6399949ed3	t	190016eb-d7df-419c-a203-fbdec2e6f379
8f07dcb1-7526-48d3-9d20-0816dd2baf5b	Abertura MEI Guarujá	4a8647d1-06c8-4616-85be-3f6399949ed3	t	21a4bf05-3100-41e2-a3b2-e59ff67fc897
49241e34-99f6-4af3-98a2-cb39f251818a	Alteração Contratual LTDA Florianópolis	abfd20e5-d561-4c44-ba42-ae194ebb2c18	t	190016eb-d7df-419c-a203-fbdec2e6f379
ee39ab7c-aa90-44ab-b6fe-9cc94a6b3225	Encerramento de Empresa Floripa	abfd20e5-d561-4c44-ba42-ae194ebb2c18	t	190016eb-d7df-419c-a203-fbdec2e6f379
cbfc8f55-d3d0-42fb-a5d5-dd31f0dc643b	Encerramento Empresa Biguaçu	6a69c90c-8475-4d97-9e9a-8647305346f1	t	190016eb-d7df-419c-a203-fbdec2e6f379
e4fa2d00-bea7-4718-be6b-0c7608de7bb6	Teste pós Refactoring	f5531987-ec10-4099-b940-b9bde36c0b16	t	21a4bf05-3100-41e2-a3b2-e59ff67fc897
\.


--
-- TOC entry 4862 (class 0 OID 17866)
-- Dependencies: 238
-- Data for Name: tenant; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tenant (id, nome, contato, active, createdat, updatedat, plano) FROM stdin;
d1e9e353-9d14-4f94-a426-6af374a6a7e0	Betel Contabilidade	Valéria Amaral	t	2023-06-07 23:03:56.979	2023-06-07 23:03:56.979	DEMO
0d1a7bfb-c81e-4f5b-a59b-3820e935dbc1	JNP Contabilidade	Patrícia Nicco	t	2023-06-07 23:08:46.02	2023-06-07 23:08:46.02	DEMO
fe4e79c6-de00-47d4-9b28-8913aecd9a25	Betel Serviços Contábeis	Lucimara	t	2023-06-07 23:09:47.248	2023-06-07 23:09:47.248	DEMO
8b0dabfe-d217-4759-9184-91eb73d31cc9	Global Business	Thiago	t	2023-06-07 23:28:06.705	2023-06-07 23:28:06.705	DEMO
24909044-39f5-4892-a636-1cc4d6b9440f	Neto Serviços Contábeis	Abilio Neto	t	2023-06-07 23:30:53.326	2023-06-07 23:30:53.326	DEMO
5bf1a2bc-b39e-4af6-97df-bb70326373ab	VEC Serviços Contábeis	Carlos Amaral	t	2023-06-07 23:35:54.834	2023-06-07 23:35:54.834	DEMO
a95ecd56-c1af-44c6-91f6-05a859030ed8	abc	abcd	t	2023-06-08 12:30:35.251	2023-06-08 12:30:35.251	DEMO
293bf206-5dec-452d-a8f1-1655fa86c1b3	\N	Naide	t	2023-06-13 18:10:12.876	2023-06-13 18:10:12.876	DEMO
a83d705d-c693-4a51-933f-8a1549ac9e31	\N	Dirlei	t	2023-06-14 23:08:38.498	2023-06-14 23:08:38.498	DEMO
76e5ab47-87a5-4558-bfcd-0c69bad2a05e	\N	bla	t	2023-06-14 23:09:06.528	2023-06-14 23:09:06.528	DEMO
2fadab18-413e-4b9c-947f-796e10a00d30	\N	rege	t	2023-06-14 23:10:40.562	2023-06-14 23:10:40.562	DEMO
311951aa-ace3-489a-9d50-325e632959ca	\N	miki@vec.com	t	2023-07-03 14:22:47.745	2023-07-03 14:22:47.745	DEMO
4faea3cf-48ae-4fcf-bad7-e4d03a5c3117	\N	Abilio Neto	t	2023-07-04 13:35:29.161	2023-07-04 13:35:29.161	DEMO
0a550cc7-e4f6-4866-83b0-c6828fa59729	\N	Abilio Neto	t	2023-07-04 13:36:17.402	2023-07-04 13:36:17.402	DEMO
60d38516-a0ed-4960-80f3-2f782c8eba09	\N	Abilio Neto	t	2023-07-04 13:36:29.013	2023-07-04 13:36:29.013	DEMO
5947a370-dee3-4a72-b55d-88cee53cac38	\N	Abilio Neto	t	2023-07-04 13:38:35.458	2023-07-04 13:38:35.458	DEMO
7ca1a4fb-12c5-4e3d-a449-7d9b7c912b3f	\N	Abilio Neto	t	2023-07-04 13:39:03.486	2023-07-04 13:39:03.486	DEMO
9b500017-5853-4b5a-8f3d-c2c10f83e01d	\N	Abilio Neto	t	2023-07-04 13:39:55.923	2023-07-04 13:39:55.923	DEMO
c0b38958-8832-465d-9efa-812185c2fb1a	\N	Eduardo Amaral	t	2023-07-04 14:06:37.913	2023-07-04 14:06:37.913	DEMO
89e5d80e-5745-4235-84e1-ae590de026ea	\N	Eduardo Amaral	t	2023-07-04 14:08:14.261	2023-07-04 14:08:14.261	DEMO
4d95e964-6d08-4316-8a63-3e994c93f622	\N	Bela	t	2023-07-04 15:26:43.792	2023-07-04 15:26:43.792	DEMO
02ca80b9-7a5b-4715-a9ee-9226f89087a5	\N	Cris	t	2023-07-05 18:57:33.608	2023-07-05 18:57:33.608	DEMO
7a0eb58a-aaea-4782-8724-06144fceff00	\N	Dionéia	t	2023-07-06 08:51:29.956	2023-07-06 08:51:29.956	DEMO
78866ba4-9b12-4db0-aad5-bdbe79cb63b9	MARE	contato@mare.com	t	2026-03-24 08:09:30.891	2026-03-24 08:09:30.891	DEMO
b9fb9d4b-e9a4-45ed-86f0-b9262922437d	meire@bla.com	meire@bla.com	t	2026-03-31 09:56:12.258	2026-03-31 09:56:12.258	DEMO
\.


--
-- TOC entry 4863 (class 0 OID 17882)
-- Dependencies: 239
-- Data for Name: tipoempresa; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tipoempresa (descricao, capital, anual, ativo, id) FROM stdin;
SS - Sociedade Simples	2500.00	100000.00	t	22c59c69-621b-437c-98c3-025aa852efb1
SA - Sociedade Anônima	\N	\N	t	c2a04ff5-4e7e-4d96-9ae9-b2c6356c608b
SLU - Sociedade Limitada Unipessoal	\N	\N	t	13d8bac6-5226-4af7-8e90-a44880dcbe27
MEI - Micro Empreendedor Individual	\N	\N	t	21a4bf05-3100-41e2-a3b2-e59ff67fc897
EI - Empresa Individual	\N	\N	t	826e668b-9df0-44a8-9ae1-baa25e383aaa
LTDA - Sociedade Empresária Limitada	\N	\N	t	190016eb-d7df-419c-a203-fbdec2e6f379
\.


--
-- TOC entry 4868 (class 0 OID 27527)
-- Dependencies: 244
-- Data for Name: tipoempresa_obriga_bairro; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tipoempresa_obriga_bairro (tipoempresa_obrigacao_id, municipio_id, bairro) FROM stdin;
67698eea-67e1-44d5-8344-c872f6569668	abfd20e5-d561-4c44-ba42-ae194ebb2c18	Campeche
\.


--
-- TOC entry 4866 (class 0 OID 27489)
-- Dependencies: 242
-- Data for Name: tipoempresa_obriga_estado; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tipoempresa_obriga_estado (obrigacao_id, estado_id) FROM stdin;
7a6e69c2-57e6-4beb-9ec1-e3424a7a2d8d	502caf63-be95-472f-9922-e8ba268fefa8
5d3189ad-0395-490f-a929-b4f8675bad4e	502caf63-be95-472f-9922-e8ba268fefa8
f3d85f25-31d0-4cdc-93f9-c9a9818e65c7	502caf63-be95-472f-9922-e8ba268fefa8
c603a3c5-10ee-4b14-a122-b7473ece1fa5	502caf63-be95-472f-9922-e8ba268fefa8
\.


--
-- TOC entry 4867 (class 0 OID 27508)
-- Dependencies: 243
-- Data for Name: tipoempresa_obriga_municipio; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tipoempresa_obriga_municipio (obrigacao_id, municipio_id) FROM stdin;
cf548021-bc2d-4091-8f1a-087918e5f577	abfd20e5-d561-4c44-ba42-ae194ebb2c18
9a9af32b-a611-46ea-9acc-abce4ab662ec	abfd20e5-d561-4c44-ba42-ae194ebb2c18
4acf5849-2a62-4390-b7b8-b0a2920113f0	abfd20e5-d561-4c44-ba42-ae194ebb2c18
e7873d49-a38d-48bd-aa59-268d943625e3	abfd20e5-d561-4c44-ba42-ae194ebb2c18
93c6a4dc-ae55-431a-b0d8-b69bc237875f	abfd20e5-d561-4c44-ba42-ae194ebb2c18
e85d3da6-fac6-4f01-95af-0cbe67576089	abfd20e5-d561-4c44-ba42-ae194ebb2c18
bce1f085-fdc7-4054-a20f-09ad6f22e2a6	abfd20e5-d561-4c44-ba42-ae194ebb2c18
\.


--
-- TOC entry 4865 (class 0 OID 27358)
-- Dependencies: 241
-- Data for Name: tipoempresa_obrigacao; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tipoempresa_obrigacao (id, descricao, periodicidade, abrangencia, valor, observacao, ativo, criado_em, atualizado_em, tipo_empresa_id, dia_base, mes_base, tipo_classificacao) FROM stdin;
93c6a4dc-ae55-431a-b0d8-b69bc237875f	Compromisso bairro mensal nao financeiro	MENSAL	MUNICIPAL	\N	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-30 18:25:14.268504-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	INFORMATIVA
cf548021-bc2d-4091-8f1a-087918e5f577	Compromisso municipal mensal financeiro	MENSAL	MUNICIPAL	120.00	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-27 10:43:14.959813-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	TRIBUTARIA
e7873d49-a38d-48bd-aa59-268d943625e3	Compromisso municipal anual financeiro	ANUAL	MUNICIPAL	130.00	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-30 14:10:36.379865-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	TRIBUTARIA
e85d3da6-fac6-4f01-95af-0cbe67576089	Compromisso bairro mensal financeiro	MENSAL	MUNICIPAL	200.00	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-30 18:39:14.692931-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	TRIBUTO
c603a3c5-10ee-4b14-a122-b7473ece1fa5	Compromisso estadual anual financeiro	ANUAL	ESTADUAL	110.00	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-30 19:20:19.374854-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	TRIBUTARIA
67698eea-67e1-44d5-8344-c872f6569668	Laudêmio	ANUAL	BAIRRO	150.00	O Laudêmio e o Foro, decorrentes de a região estar em cima de Terras da União (Geridas pela SPU - Secretaria do Patrimônio da União).	t	2026-03-31 09:36:38.160785-03	2026-03-31 09:36:38.160785-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	1	TRIBUTARIA
bce1f085-fdc7-4054-a20f-09ad6f22e2a6	Compromisso bairro anual financeiro	ANUAL	MUNICIPAL	200.50	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-31 09:36:51.584632-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	TRIBUTARIA
52f9e9ad-2e2c-4a64-b779-8867db21479d	Documentação para IRPF	ANUAL	FEDERAL	\N	\N	t	2026-04-01 08:27:29.398222-03	2026-04-01 08:27:29.398222-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	INFORMATIVA
4acf5849-2a62-4390-b7b8-b0a2920113f0	Compromisso municipal anual nao financeiro	ANUAL	MUNICIPAL	\N	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-27 10:43:14.959813-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	INFORMATIVA
5d3189ad-0395-490f-a929-b4f8675bad4e	Compromisso estadual mensal nao financeiro	MENSAL	ESTADUAL	\N	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-27 10:43:14.959813-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	INFORMATIVA
9a9af32b-a611-46ea-9acc-abce4ab662ec	Compromisso municipal mensal nao financeiro	MENSAL	MUNICIPAL	\N	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-27 10:43:14.959813-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	INFORMATIVA
f3d85f25-31d0-4cdc-93f9-c9a9818e65c7	Compromisso estadual anual nao financeiro	ANUAL	ESTADUAL	\N	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-27 10:43:14.959813-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	INFORMATIVA
87a3300d-60a2-4d87-9e48-702ab9ad1ced	Compromisso bairro anual nao financeiro	ANUAL	MUNICIPAL	\N	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-30 18:28:23.579697-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	INFORMATIVA
7a6e69c2-57e6-4beb-9ec1-e3424a7a2d8d	Compromisso estadual mensal financeiro	MENSAL	ESTADUAL	100.00	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-27 10:43:14.959813-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	TRIBUTARIA
\.


--
-- TOC entry 4869 (class 0 OID 28738)
-- Dependencies: 245
-- Data for Name: tipoempresa_obrigacao_old; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tipoempresa_obrigacao_old (id, tipo_empresa_id, descricao, dia_base, mes_base, frequencia, tipo, ativo, criado_em, atualizado_em) FROM stdin;
d64a947a-46e4-4a66-b40c-3da0670c34d6	21a4bf05-3100-41e2-a3b2-e59ff67fc897	Compromisso Mensal	5	4	MENSAL	TRIBUTO	t	2026-03-28 16:10:34.188739-03	2026-03-28 16:10:34.188739-03
86adf4d1-d6d2-409d-a55d-34f26b51aafb	21a4bf05-3100-41e2-a3b2-e59ff67fc897	Comrpomisso teste Anual	20	4	ANUAL	TRIBUTO	t	2026-03-28 16:11:05.825873-03	2026-03-28 16:11:05.825873-03
db735fe7-72ca-47b9-a034-15acc166ec92	21a4bf05-3100-41e2-a3b2-e59ff67fc897	Compromisso Mensal apenas informativo 	5	4	MENSAL	INFORMATIVA	t	2026-03-28 16:11:57.545202-03	2026-03-28 16:11:57.545202-03
ccabfb5d-6921-440f-826c-359943414fbd	21a4bf05-3100-41e2-a3b2-e59ff67fc897	Novo teste de compromisso informativo anual	5	4	ANUAL	INFORMATIVA	t	2026-03-28 16:12:21.599454-03	2026-03-28 16:12:21.599454-03
b9daccb1-f634-45df-8f4c-b14218512452	21a4bf05-3100-41e2-a3b2-e59ff67fc897	Nova Obrigação	1	5	MENSAL	INFORMATIVA	t	2026-03-30 14:07:00.66542-03	2026-03-30 14:07:00.66542-03
\.


--
-- TOC entry 4864 (class 0 OID 17890)
-- Dependencies: 240
-- Data for Name: usuario; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.usuario (id, password, email, tenantid, active, createdat, role, updatedat, nome) FROM stdin;
f3ecfb51-0b41-454d-ac53-55af67e4695c	$2b$08$r8UJ3tAfwWAqIHB31SMCj.ZfF.1Ooax5X5mtlukzDaNTNXMbgm.qG	carlos@vec.com	5bf1a2bc-b39e-4af6-97df-bb70326373ab	t	2023-06-07 23:35:54.942	ADMIN	2023-06-07 23:35:54.942	Carlos Amaral
2591afa6-9914-4b5f-9c97-653ac1cd382b	$2b$08$r8UJ3tAfwWAqIHB31SMCj.ZfF.1Ooax5X5mtlukzDaNTNXMbgm.qG	neto@neto.com	24909044-39f5-4892-a636-1cc4d6b9440f	t	2023-06-07 23:30:53.434	ADMIN	2023-06-07 23:30:53.434	Abilio Neto
532f36f6-e768-47e3-906f-55aab44c7950	$2b$08$r8UJ3tAfwWAqIHB31SMCj.ZfF.1Ooax5X5mtlukzDaNTNXMbgm.qG	dioneia@vec.com	7a0eb58a-aaea-4782-8724-06144fceff00	t	2023-07-06 08:51:30.018	ADMIN	2023-07-06 08:51:30.018	Dionéia
56bc8d60-a196-428c-a5fd-d3031ceb0d11	$2b$08$r8UJ3tAfwWAqIHB31SMCj.ZfF.1Ooax5X5mtlukzDaNTNXMbgm.qG	val@vec.com	d1e9e353-9d14-4f94-a426-6af374a6a7e0	t	2023-06-07 23:03:57.185	ADMIN	2023-06-07 23:03:57.185	Valéria Amaral
6b919c58-ebe8-426c-82aa-35bc6a08e4d1	$2b$08$r8UJ3tAfwWAqIHB31SMCj.ZfF.1Ooax5X5mtlukzDaNTNXMbgm.qG	cris@vec.com	02ca80b9-7a5b-4715-a9ee-9226f89087a5	t	2023-07-05 18:57:33.665	ADMIN	2023-07-05 18:57:33.665	Cris
97d5dd34-3bd8-4479-a20e-82d7a7b44df2	$2b$08$r8UJ3tAfwWAqIHB31SMCj.ZfF.1Ooax5X5mtlukzDaNTNXMbgm.qG	abc@abc.com	a95ecd56-c1af-44c6-91f6-05a859030ed8	t	2023-06-08 12:30:35.458	ADMIN	2023-06-08 12:30:35.458	abcd
9e857324-da7d-44ea-b982-39156aff80c6	$2b$08$r8UJ3tAfwWAqIHB31SMCj.ZfF.1Ooax5X5mtlukzDaNTNXMbgm.qG	abilio@vec.com	9b500017-5853-4b5a-8f3d-c2c10f83e01d	t	2023-07-04 13:39:56.137	ADMIN	2023-07-04 13:39:56.137	Abilio Neto
bcc3aaaa-f273-4acd-bb9e-c8e677203b8c	$2b$08$r8UJ3tAfwWAqIHB31SMCj.ZfF.1Ooax5X5mtlukzDaNTNXMbgm.qG	fofo@vec.com	5bf1a2bc-b39e-4af6-97df-bb70326373ab	t	2026-03-23 17:24:06.911	USER	2026-03-23 17:24:06.911	Fox Fofó
c261b585-7be0-4017-948e-7747affd8e34	$2b$08$r8UJ3tAfwWAqIHB31SMCj.ZfF.1Ooax5X5mtlukzDaNTNXMbgm.qG	vela@vec.com	4d95e964-6d08-4316-8a63-3e994c93f622	t	2023-07-04 15:26:43.859	ADMIN	2023-07-04 15:26:43.859	Bela
8a8549f0-6248-450d-835b-9121ef341f0c	$2a$08$y/dZE9zjM3h9Q7Ka0tJEBOqwGzFMMyPIaepRJpDCvcait65bvZPfG	didi@vec.com	d1e9e353-9d14-4f94-a426-6af374a6a7e0	t	2026-03-23 19:33:58.321	USER	2026-03-23 19:33:58.321	didi@vec.com
0806c4fd-2011-4aa8-8b7a-34e6a6cb3679	$2a$08$TMOfeZjyNLljxMV.p66CR.cAeRgudYYi8NaoOgAR/I6Lxm1KDBTH6	super@mare.com	78866ba4-9b12-4db0-aad5-bdbe79cb63b9	t	2026-03-24 08:10:07.274	SUPER	2026-03-24 08:10:07.274	Admin MARE
85e53bc8-73a1-4ab7-9764-eadb733fcf31	$2a$08$TObLNqrqPhvFPZsYX1.jou7yKBtTy.O1CX7Eq5OKZev.MeDclLkHu	meire@bla.com	b9fb9d4b-e9a4-45ed-86f0-b9262922437d	t	2026-03-31 09:56:12.258	ADMIN	2026-03-31 09:56:12.258	meire@bla.com
c3de8d80-0eb8-4d73-9e7b-79e5e28130e5	$2a$08$ybusijgpXC8A9vNQXEFB7OtNu8Eng/Ef.Elw5xk/TbfCHx3kOF8eW	ble@bla.com	b9fb9d4b-e9a4-45ed-86f0-b9262922437d	t	2026-03-31 10:05:15.145	USER	2026-03-31 10:05:15.145	ble@bla.com
\.


--
-- TOC entry 4899 (class 0 OID 0)
-- Dependencies: 256
-- Name: ibge_cnae_classe_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.ibge_cnae_classe_id_seq', 671, true);


--
-- TOC entry 4900 (class 0 OID 0)
-- Dependencies: 252
-- Name: ibge_cnae_divisao_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.ibge_cnae_divisao_id_seq', 87, true);


--
-- TOC entry 4901 (class 0 OID 0)
-- Dependencies: 254
-- Name: ibge_cnae_grupo_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.ibge_cnae_grupo_id_seq', 283, true);


--
-- TOC entry 4902 (class 0 OID 0)
-- Dependencies: 250
-- Name: ibge_cnae_secao_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.ibge_cnae_secao_id_seq', 21, true);


--
-- TOC entry 4903 (class 0 OID 0)
-- Dependencies: 258
-- Name: ibge_cnae_subclasse_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.ibge_cnae_subclasse_id_seq', 1332, true);


--
-- TOC entry 4570 (class 2606 OID 17910)
-- Name: estado Estado_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estado
    ADD CONSTRAINT "Estado_pkey" PRIMARY KEY (id);


--
-- TOC entry 4599 (class 2606 OID 17912)
-- Name: municipio Municipio_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.municipio
    ADD CONSTRAINT "Municipio_pkey" PRIMARY KEY (id);


--
-- TOC entry 4572 (class 2606 OID 17914)
-- Name: agenda agenda_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda
    ADD CONSTRAINT agenda_pkey PRIMARY KEY (id);


--
-- TOC entry 4574 (class 2606 OID 17916)
-- Name: agendaitens agendaitens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agendaitens
    ADD CONSTRAINT agendaitens_pkey PRIMARY KEY (id);


--
-- TOC entry 4645 (class 2606 OID 28952)
-- Name: cnae_ibge_hierarquia cnae_ibge_hierarquia_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cnae_ibge_hierarquia
    ADD CONSTRAINT cnae_ibge_hierarquia_pkey PRIMARY KEY (subclasse);


--
-- TOC entry 4576 (class 2606 OID 17918)
-- Name: cnae cnae_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cnae
    ADD CONSTRAINT cnae_pkey PRIMARY KEY (id);


--
-- TOC entry 4622 (class 2606 OID 27497)
-- Name: tipoempresa_obriga_estado compromisso_estado_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obriga_estado
    ADD CONSTRAINT compromisso_estado_pkey PRIMARY KEY (obrigacao_id);


--
-- TOC entry 4619 (class 2606 OID 27377)
-- Name: tipoempresa_obrigacao compromisso_financeiro_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obrigacao
    ADD CONSTRAINT compromisso_financeiro_pkey PRIMARY KEY (id);


--
-- TOC entry 4624 (class 2606 OID 27516)
-- Name: tipoempresa_obriga_municipio compromisso_municipio_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obriga_municipio
    ADD CONSTRAINT compromisso_municipio_pkey PRIMARY KEY (obrigacao_id);


--
-- TOC entry 4631 (class 2606 OID 28784)
-- Name: empresa_agenda empresa_agenda_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_agenda
    ADD CONSTRAINT empresa_agenda_pkey PRIMARY KEY (id);


--
-- TOC entry 4636 (class 2606 OID 28870)
-- Name: empresa_compromissos empresa_compromissos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_compromissos
    ADD CONSTRAINT empresa_compromissos_pkey PRIMARY KEY (id);


--
-- TOC entry 4643 (class 2606 OID 28919)
-- Name: empresa_dados empresa_dados_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_dados
    ADD CONSTRAINT empresa_dados_pkey PRIMARY KEY (empresa_id);


--
-- TOC entry 4579 (class 2606 OID 17920)
-- Name: empresa empresa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa
    ADD CONSTRAINT empresa_pkey PRIMARY KEY (id);


--
-- TOC entry 4581 (class 2606 OID 17922)
-- Name: empresadados empresas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresadados
    ADD CONSTRAINT empresas_pkey PRIMARY KEY (id);


--
-- TOC entry 4583 (class 2606 OID 17924)
-- Name: feriado_estadual feriado_estadual_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feriado_estadual
    ADD CONSTRAINT feriado_estadual_pkey PRIMARY KEY (feriado_id, uf_id);


--
-- TOC entry 4585 (class 2606 OID 17926)
-- Name: feriado_municipal feriado_municipal_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feriado_municipal
    ADD CONSTRAINT feriado_municipal_pkey PRIMARY KEY (feriado_id, municipio_id);


--
-- TOC entry 4587 (class 2606 OID 17928)
-- Name: feriados feriados_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feriados
    ADD CONSTRAINT feriados_pkey PRIMARY KEY (id);


--
-- TOC entry 4589 (class 2606 OID 17930)
-- Name: grupopassos grupopasso_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupopassos
    ADD CONSTRAINT grupopasso_pkey PRIMARY KEY (id);


--
-- TOC entry 4659 (class 2606 OID 29017)
-- Name: ibge_cnae_classe ibge_cnae_classe_grupo_id_nome_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_classe
    ADD CONSTRAINT ibge_cnae_classe_grupo_id_nome_key UNIQUE (grupo_id, nome);


--
-- TOC entry 4661 (class 2606 OID 29015)
-- Name: ibge_cnae_classe ibge_cnae_classe_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_classe
    ADD CONSTRAINT ibge_cnae_classe_pkey PRIMARY KEY (id);


--
-- TOC entry 4651 (class 2606 OID 28977)
-- Name: ibge_cnae_divisao ibge_cnae_divisao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_divisao
    ADD CONSTRAINT ibge_cnae_divisao_pkey PRIMARY KEY (id);


--
-- TOC entry 4653 (class 2606 OID 28979)
-- Name: ibge_cnae_divisao ibge_cnae_divisao_secao_id_nome_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_divisao
    ADD CONSTRAINT ibge_cnae_divisao_secao_id_nome_key UNIQUE (secao_id, nome);


--
-- TOC entry 4655 (class 2606 OID 28998)
-- Name: ibge_cnae_grupo ibge_cnae_grupo_divisao_id_nome_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_grupo
    ADD CONSTRAINT ibge_cnae_grupo_divisao_id_nome_key UNIQUE (divisao_id, nome);


--
-- TOC entry 4657 (class 2606 OID 28996)
-- Name: ibge_cnae_grupo ibge_cnae_grupo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_grupo
    ADD CONSTRAINT ibge_cnae_grupo_pkey PRIMARY KEY (id);


--
-- TOC entry 4647 (class 2606 OID 28965)
-- Name: ibge_cnae_secao ibge_cnae_secao_nome_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_secao
    ADD CONSTRAINT ibge_cnae_secao_nome_key UNIQUE (nome);


--
-- TOC entry 4649 (class 2606 OID 28963)
-- Name: ibge_cnae_secao ibge_cnae_secao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_secao
    ADD CONSTRAINT ibge_cnae_secao_pkey PRIMARY KEY (id);


--
-- TOC entry 4663 (class 2606 OID 29037)
-- Name: ibge_cnae_subclasse ibge_cnae_subclasse_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_subclasse
    ADD CONSTRAINT ibge_cnae_subclasse_codigo_key UNIQUE (codigo);


--
-- TOC entry 4665 (class 2606 OID 29035)
-- Name: ibge_cnae_subclasse ibge_cnae_subclasse_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_subclasse
    ADD CONSTRAINT ibge_cnae_subclasse_pkey PRIMARY KEY (id);


--
-- TOC entry 4591 (class 2606 OID 17932)
-- Name: itenspassos itenspassos_id_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.itenspassos
    ADD CONSTRAINT itenspassos_id_pkey PRIMARY KEY (id);


--
-- TOC entry 4595 (class 2606 OID 17934)
-- Name: linkpassos linkpassos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.linkpassos
    ADD CONSTRAINT linkpassos_pkey PRIMARY KEY (passo_id);


--
-- TOC entry 4601 (class 2606 OID 17936)
-- Name: passos passo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.passos
    ADD CONSTRAINT passo_pkey PRIMARY KEY (id);


--
-- TOC entry 4597 (class 2606 OID 17938)
-- Name: linkpassos passos_id_unq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.linkpassos
    ADD CONSTRAINT passos_id_unq UNIQUE (passo_id);


--
-- TOC entry 4593 (class 2606 OID 17940)
-- Name: itenspassos passos_itens_unq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.itenspassos
    ADD CONSTRAINT passos_itens_unq UNIQUE (grupopassos_id, passos_id);


--
-- TOC entry 4603 (class 2606 OID 17942)
-- Name: rotinaitemlink rotinaitemlink_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rotinaitemlink
    ADD CONSTRAINT rotinaitemlink_pkey PRIMARY KEY (rotinaitem_id);


--
-- TOC entry 4609 (class 2606 OID 17944)
-- Name: rotinas rotinas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rotinas
    ADD CONSTRAINT rotinas_pkey PRIMARY KEY (id);


--
-- TOC entry 4606 (class 2606 OID 17946)
-- Name: rotinaitens rotinasitens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rotinaitens
    ADD CONSTRAINT rotinasitens_pkey PRIMARY KEY (rotina_id, passo_id);


--
-- TOC entry 4612 (class 2606 OID 17948)
-- Name: tenant tenant_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant
    ADD CONSTRAINT tenant_pkey PRIMARY KEY (id);


--
-- TOC entry 4614 (class 2606 OID 17950)
-- Name: tipoempresa tipoempresa_id_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa
    ADD CONSTRAINT tipoempresa_id_pkey PRIMARY KEY (id);


--
-- TOC entry 4626 (class 2606 OID 27536)
-- Name: tipoempresa_obriga_bairro tipoempresa_obriga_bairro_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obriga_bairro
    ADD CONSTRAINT tipoempresa_obriga_bairro_pkey PRIMARY KEY (tipoempresa_obrigacao_id);


--
-- TOC entry 4629 (class 2606 OID 28760)
-- Name: tipoempresa_obrigacao_old tipoempresa_obrigacao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obrigacao_old
    ADD CONSTRAINT tipoempresa_obrigacao_pkey PRIMARY KEY (id);


--
-- TOC entry 4617 (class 2606 OID 17952)
-- Name: usuario usuario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_pkey PRIMARY KEY (id);


--
-- TOC entry 4620 (class 1259 OID 28806)
-- Name: idx_compromisso_financeiro_tipoempresa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_compromisso_financeiro_tipoempresa ON public.tipoempresa_obrigacao USING btree (tipo_empresa_id);


--
-- TOC entry 4632 (class 1259 OID 28796)
-- Name: idx_empresa_agenda_empresa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_empresa_agenda_empresa ON public.empresa_agenda USING btree (empresa_id);


--
-- TOC entry 4633 (class 1259 OID 28797)
-- Name: idx_empresa_agenda_template; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_empresa_agenda_template ON public.empresa_agenda USING btree (template_id);


--
-- TOC entry 4634 (class 1259 OID 28798)
-- Name: idx_empresa_agenda_vencimento; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_empresa_agenda_vencimento ON public.empresa_agenda USING btree (data_vencimento);


--
-- TOC entry 4637 (class 1259 OID 28883)
-- Name: idx_empresa_compromissos_compromisso_fin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_empresa_compromissos_compromisso_fin ON public.empresa_compromissos USING btree (tipoempresa_obrigacao_id);


--
-- TOC entry 4638 (class 1259 OID 28881)
-- Name: idx_empresa_compromissos_empresa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_empresa_compromissos_empresa ON public.empresa_compromissos USING btree (empresa_id);


--
-- TOC entry 4639 (class 1259 OID 28898)
-- Name: idx_empresa_compromissos_tipo_obrigacao; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_empresa_compromissos_tipo_obrigacao ON public.empresa_compromissos USING btree (tipoempresa_obrigacao_id);


--
-- TOC entry 4640 (class 1259 OID 28882)
-- Name: idx_empresa_compromissos_vencimento; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_empresa_compromissos_vencimento ON public.empresa_compromissos USING btree (vencimento);


--
-- TOC entry 4604 (class 1259 OID 17953)
-- Name: idx_rotinaitens_ordem; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rotinaitens_ordem ON public.rotinaitens USING btree (ordem);


--
-- TOC entry 4607 (class 1259 OID 28850)
-- Name: idx_rotinas_tipo_empresa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rotinas_tipo_empresa ON public.rotinas USING btree (tipo_empresa_id);


--
-- TOC entry 4627 (class 1259 OID 28795)
-- Name: idx_tipoempresa_obrigacao_tipo_empresa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tipoempresa_obrigacao_tipo_empresa ON public.tipoempresa_obrigacao_old USING btree (tipo_empresa_id);


--
-- TOC entry 4610 (class 1259 OID 17954)
-- Name: tenant_nome_unico; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX tenant_nome_unico ON public.tenant USING btree (nome);


--
-- TOC entry 4577 (class 1259 OID 28933)
-- Name: uq_cnae_subclasse; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_cnae_subclasse ON public.cnae USING btree (subclasse);


--
-- TOC entry 4641 (class 1259 OID 28900)
-- Name: uq_empresa_compromissos_empresa_obrigacao_competencia; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_empresa_compromissos_empresa_obrigacao_competencia ON public.empresa_compromissos USING btree (empresa_id, tipoempresa_obrigacao_id, competencia);


--
-- TOC entry 4615 (class 1259 OID 17955)
-- Name: usuario_email_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX usuario_email_key ON public.usuario USING btree (email);


--
-- TOC entry 4695 (class 2620 OID 17956)
-- Name: empresa gerar_agenda; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER gerar_agenda AFTER UPDATE ON public.empresa FOR EACH ROW EXECUTE FUNCTION public.gerar_agenda_trigger();


--
-- TOC entry 4672 (class 2606 OID 17957)
-- Name: municipio Municipio_ufId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.municipio
    ADD CONSTRAINT "Municipio_ufId_fkey" FOREIGN KEY (ufid) REFERENCES public.estado(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4679 (class 2606 OID 27498)
-- Name: tipoempresa_obriga_estado compromisso_estado_compromisso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obriga_estado
    ADD CONSTRAINT compromisso_estado_compromisso_id_fkey FOREIGN KEY (obrigacao_id) REFERENCES public.tipoempresa_obrigacao(id) ON DELETE CASCADE;


--
-- TOC entry 4680 (class 2606 OID 27503)
-- Name: tipoempresa_obriga_estado compromisso_estado_estado_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obriga_estado
    ADD CONSTRAINT compromisso_estado_estado_id_fkey FOREIGN KEY (estado_id) REFERENCES public.estado(id);


--
-- TOC entry 4681 (class 2606 OID 27517)
-- Name: tipoempresa_obriga_municipio compromisso_municipio_compromisso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obriga_municipio
    ADD CONSTRAINT compromisso_municipio_compromisso_id_fkey FOREIGN KEY (obrigacao_id) REFERENCES public.tipoempresa_obrigacao(id) ON DELETE CASCADE;


--
-- TOC entry 4682 (class 2606 OID 27522)
-- Name: tipoempresa_obriga_municipio compromisso_municipio_municipio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obriga_municipio
    ADD CONSTRAINT compromisso_municipio_municipio_id_fkey FOREIGN KEY (municipio_id) REFERENCES public.municipio(id);


--
-- TOC entry 4666 (class 2606 OID 17962)
-- Name: dadoscomplementares dadoscomplementares_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dadoscomplementares
    ADD CONSTRAINT dadoscomplementares_fkey FOREIGN KEY (tenantid) REFERENCES public.tenant(id);


--
-- TOC entry 4686 (class 2606 OID 28785)
-- Name: empresa_agenda empresa_agenda_empresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_agenda
    ADD CONSTRAINT empresa_agenda_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresa(id) ON DELETE CASCADE;


--
-- TOC entry 4687 (class 2606 OID 28888)
-- Name: empresa_agenda empresa_agenda_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_agenda
    ADD CONSTRAINT empresa_agenda_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.tipoempresa_obrigacao(id) ON DELETE CASCADE;


--
-- TOC entry 4688 (class 2606 OID 28871)
-- Name: empresa_compromissos empresa_compromissos_empresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_compromissos
    ADD CONSTRAINT empresa_compromissos_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresa(id) ON DELETE CASCADE;


--
-- TOC entry 4689 (class 2606 OID 28893)
-- Name: empresa_compromissos empresa_compromissos_tipoempresa_obrigacao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_compromissos
    ADD CONSTRAINT empresa_compromissos_tipoempresa_obrigacao_id_fkey FOREIGN KEY (tipoempresa_obrigacao_id) REFERENCES public.tipoempresa_obrigacao(id) ON DELETE RESTRICT;


--
-- TOC entry 4690 (class 2606 OID 28920)
-- Name: empresa_dados empresa_dados_empresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_dados
    ADD CONSTRAINT empresa_dados_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresa(id) ON DELETE CASCADE;


--
-- TOC entry 4678 (class 2606 OID 28801)
-- Name: tipoempresa_obrigacao fk_compromisso_tipoempresa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obrigacao
    ADD CONSTRAINT fk_compromisso_tipoempresa FOREIGN KEY (tipo_empresa_id) REFERENCES public.tipoempresa(id);


--
-- TOC entry 4683 (class 2606 OID 27542)
-- Name: tipoempresa_obriga_bairro fk_obriga_bairro_municipio; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obriga_bairro
    ADD CONSTRAINT fk_obriga_bairro_municipio FOREIGN KEY (municipio_id) REFERENCES public.municipio(id);


--
-- TOC entry 4684 (class 2606 OID 27537)
-- Name: tipoempresa_obriga_bairro fk_obriga_bairro_obrigacao; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obriga_bairro
    ADD CONSTRAINT fk_obriga_bairro_obrigacao FOREIGN KEY (tipoempresa_obrigacao_id) REFERENCES public.tipoempresa_obrigacao(id) ON DELETE CASCADE;


--
-- TOC entry 4667 (class 2606 OID 17967)
-- Name: grupopassos grupo_municipio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupopassos
    ADD CONSTRAINT grupo_municipio_id_fkey FOREIGN KEY (municipio_id) REFERENCES public.municipio(id) NOT VALID;


--
-- TOC entry 4668 (class 2606 OID 17972)
-- Name: grupopassos grupo_tipoempresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupopassos
    ADD CONSTRAINT grupo_tipoempresa_id_fkey FOREIGN KEY (tipoempresa_id) REFERENCES public.tipoempresa(id) NOT VALID;


--
-- TOC entry 4669 (class 2606 OID 17977)
-- Name: itenspassos grupopassos_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.itenspassos
    ADD CONSTRAINT grupopassos_id_fkey FOREIGN KEY (grupopassos_id) REFERENCES public.grupopassos(id);


--
-- TOC entry 4693 (class 2606 OID 29018)
-- Name: ibge_cnae_classe ibge_cnae_classe_grupo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_classe
    ADD CONSTRAINT ibge_cnae_classe_grupo_id_fkey FOREIGN KEY (grupo_id) REFERENCES public.ibge_cnae_grupo(id) ON DELETE CASCADE;


--
-- TOC entry 4691 (class 2606 OID 28980)
-- Name: ibge_cnae_divisao ibge_cnae_divisao_secao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_divisao
    ADD CONSTRAINT ibge_cnae_divisao_secao_id_fkey FOREIGN KEY (secao_id) REFERENCES public.ibge_cnae_secao(id) ON DELETE CASCADE;


--
-- TOC entry 4692 (class 2606 OID 28999)
-- Name: ibge_cnae_grupo ibge_cnae_grupo_divisao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_grupo
    ADD CONSTRAINT ibge_cnae_grupo_divisao_id_fkey FOREIGN KEY (divisao_id) REFERENCES public.ibge_cnae_divisao(id) ON DELETE CASCADE;


--
-- TOC entry 4694 (class 2606 OID 29038)
-- Name: ibge_cnae_subclasse ibge_cnae_subclasse_classe_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ibge_cnae_subclasse
    ADD CONSTRAINT ibge_cnae_subclasse_classe_id_fkey FOREIGN KEY (classe_id) REFERENCES public.ibge_cnae_classe(id) ON DELETE CASCADE;


--
-- TOC entry 4671 (class 2606 OID 17982)
-- Name: linkpassos linkpassos_passos_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.linkpassos
    ADD CONSTRAINT linkpassos_passos_id_fkey FOREIGN KEY (passo_id) REFERENCES public.passos(id) NOT VALID;


--
-- TOC entry 4675 (class 2606 OID 17987)
-- Name: rotinas municipio_cidade_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rotinas
    ADD CONSTRAINT municipio_cidade_id_fkey FOREIGN KEY (municipio_id) REFERENCES public.municipio(id) NOT VALID;


--
-- TOC entry 4670 (class 2606 OID 17992)
-- Name: itenspassos passos_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.itenspassos
    ADD CONSTRAINT passos_id_fkey FOREIGN KEY (passos_id) REFERENCES public.passos(id) NOT VALID;


--
-- TOC entry 4673 (class 2606 OID 17997)
-- Name: rotinaitens rotinas_passo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rotinaitens
    ADD CONSTRAINT rotinas_passo_id_fkey FOREIGN KEY (passo_id) REFERENCES public.passos(id) NOT VALID;


--
-- TOC entry 4674 (class 2606 OID 18002)
-- Name: rotinaitens rotinas_rotina_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rotinaitens
    ADD CONSTRAINT rotinas_rotina_id_fkey FOREIGN KEY (rotina_id) REFERENCES public.rotinas(id) NOT VALID;


--
-- TOC entry 4676 (class 2606 OID 28845)
-- Name: rotinas rotinas_tipo_empresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rotinas
    ADD CONSTRAINT rotinas_tipo_empresa_id_fkey FOREIGN KEY (tipo_empresa_id) REFERENCES public.tipoempresa(id);


--
-- TOC entry 4685 (class 2606 OID 28761)
-- Name: tipoempresa_obrigacao_old tipoempresa_obrigacao_tipo_empresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obrigacao_old
    ADD CONSTRAINT tipoempresa_obrigacao_tipo_empresa_id_fkey FOREIGN KEY (tipo_empresa_id) REFERENCES public.tipoempresa(id) ON DELETE CASCADE;


--
-- TOC entry 4677 (class 2606 OID 18007)
-- Name: usuario usuario_tenantid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_tenantid_fkey FOREIGN KEY (tenantid) REFERENCES public.tenant(id) ON UPDATE CASCADE ON DELETE RESTRICT;


-- Completed on 2026-04-02 10:20:59 -03

--
-- PostgreSQL database dump complete
--

\unrestrict lXlIztUtigNpfTzEKI4XEKsJU89980CClofONytDviwldNFGecgF8KYB5ivB4jG

