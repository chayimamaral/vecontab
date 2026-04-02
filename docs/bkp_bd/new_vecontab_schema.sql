--
-- PostgreSQL database dump
--

\restrict jCfDQHbffxC2f8xdQ3w3yHUearAh1C95mS81KNOD0Eh0n2odIcS3ALAZbPTvWps

-- Dumped from database version 18.3
-- Dumped by pg_dump version 18.3

-- Started on 2026-03-31 10:35:59 -03

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
-- TOC entry 894 (class 1247 OID 17605)
-- Name: feriado; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.feriado AS ENUM (
    'MUNICIPAL',
    'ESTADUAL',
    'FIXO',
    'VARIAVEL'
);


--
-- TOC entry 897 (class 1247 OID 17614)
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
-- TOC entry 900 (class 1247 OID 17626)
-- Name: plano; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.plano AS ENUM (
    'DEMO',
    'BASICO',
    'INTERMEDIARIO',
    'PRO'
);


--
-- TOC entry 903 (class 1247 OID 17636)
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
-- TOC entry 906 (class 1247 OID 17652)
-- Name: status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.status AS ENUM (
    'Pendente',
    'Concluída'
);


--
-- TOC entry 248 (class 1255 OID 17657)
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
-- TOC entry 265 (class 1255 OID 17658)
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
-- TOC entry 266 (class 1255 OID 17659)
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
-- TOC entry 267 (class 1255 OID 17660)
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
-- TOC entry 268 (class 1255 OID 17661)
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
-- TOC entry 269 (class 1255 OID 17662)
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
-- TOC entry 270 (class 1255 OID 17663)
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
-- TOC entry 271 (class 1255 OID 17664)
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
-- TOC entry 272 (class 1255 OID 17675)
-- Name: getfoo(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.getfoo(character varying) RETURNS SETOF public.estado
    LANGUAGE sql
    AS $_$
    SELECT * FROM public.estado WHERE id = $1;
$_$;


--
-- TOC entry 249 (class 1255 OID 17676)
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
-- TOC entry 250 (class 1255 OID 17677)
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
-- TOC entry 251 (class 1255 OID 17678)
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
-- TOC entry 252 (class 1255 OID 17679)
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
-- TOC entry 253 (class 1255 OID 17680)
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
    ativo boolean DEFAULT true NOT NULL
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
    CONSTRAINT chk_empresa_compromissos_status CHECK (((status)::text = ANY ((ARRAY['pendente'::character varying, 'concluido'::character varying])::text[])))
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
-- TOC entry 4521 (class 2606 OID 17910)
-- Name: estado Estado_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estado
    ADD CONSTRAINT "Estado_pkey" PRIMARY KEY (id);


--
-- TOC entry 4549 (class 2606 OID 17912)
-- Name: municipio Municipio_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.municipio
    ADD CONSTRAINT "Municipio_pkey" PRIMARY KEY (id);


--
-- TOC entry 4523 (class 2606 OID 17914)
-- Name: agenda agenda_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agenda
    ADD CONSTRAINT agenda_pkey PRIMARY KEY (id);


--
-- TOC entry 4525 (class 2606 OID 17916)
-- Name: agendaitens agendaitens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agendaitens
    ADD CONSTRAINT agendaitens_pkey PRIMARY KEY (id);


--
-- TOC entry 4527 (class 2606 OID 17918)
-- Name: cnae cnae_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cnae
    ADD CONSTRAINT cnae_pkey PRIMARY KEY (id);


--
-- TOC entry 4572 (class 2606 OID 27497)
-- Name: tipoempresa_obriga_estado compromisso_estado_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obriga_estado
    ADD CONSTRAINT compromisso_estado_pkey PRIMARY KEY (obrigacao_id);


--
-- TOC entry 4569 (class 2606 OID 27377)
-- Name: tipoempresa_obrigacao compromisso_financeiro_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obrigacao
    ADD CONSTRAINT compromisso_financeiro_pkey PRIMARY KEY (id);


--
-- TOC entry 4574 (class 2606 OID 27516)
-- Name: tipoempresa_obriga_municipio compromisso_municipio_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obriga_municipio
    ADD CONSTRAINT compromisso_municipio_pkey PRIMARY KEY (obrigacao_id);


--
-- TOC entry 4581 (class 2606 OID 28784)
-- Name: empresa_agenda empresa_agenda_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_agenda
    ADD CONSTRAINT empresa_agenda_pkey PRIMARY KEY (id);


--
-- TOC entry 4586 (class 2606 OID 28870)
-- Name: empresa_compromissos empresa_compromissos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_compromissos
    ADD CONSTRAINT empresa_compromissos_pkey PRIMARY KEY (id);


--
-- TOC entry 4529 (class 2606 OID 17920)
-- Name: empresa empresa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa
    ADD CONSTRAINT empresa_pkey PRIMARY KEY (id);


--
-- TOC entry 4531 (class 2606 OID 17922)
-- Name: empresadados empresas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresadados
    ADD CONSTRAINT empresas_pkey PRIMARY KEY (id);


--
-- TOC entry 4533 (class 2606 OID 17924)
-- Name: feriado_estadual feriado_estadual_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feriado_estadual
    ADD CONSTRAINT feriado_estadual_pkey PRIMARY KEY (feriado_id, uf_id);


--
-- TOC entry 4535 (class 2606 OID 17926)
-- Name: feriado_municipal feriado_municipal_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feriado_municipal
    ADD CONSTRAINT feriado_municipal_pkey PRIMARY KEY (feriado_id, municipio_id);


--
-- TOC entry 4537 (class 2606 OID 17928)
-- Name: feriados feriados_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feriados
    ADD CONSTRAINT feriados_pkey PRIMARY KEY (id);


--
-- TOC entry 4539 (class 2606 OID 17930)
-- Name: grupopassos grupopasso_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupopassos
    ADD CONSTRAINT grupopasso_pkey PRIMARY KEY (id);


--
-- TOC entry 4541 (class 2606 OID 17932)
-- Name: itenspassos itenspassos_id_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.itenspassos
    ADD CONSTRAINT itenspassos_id_pkey PRIMARY KEY (id);


--
-- TOC entry 4545 (class 2606 OID 17934)
-- Name: linkpassos linkpassos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.linkpassos
    ADD CONSTRAINT linkpassos_pkey PRIMARY KEY (passo_id);


--
-- TOC entry 4551 (class 2606 OID 17936)
-- Name: passos passo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.passos
    ADD CONSTRAINT passo_pkey PRIMARY KEY (id);


--
-- TOC entry 4547 (class 2606 OID 17938)
-- Name: linkpassos passos_id_unq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.linkpassos
    ADD CONSTRAINT passos_id_unq UNIQUE (passo_id);


--
-- TOC entry 4543 (class 2606 OID 17940)
-- Name: itenspassos passos_itens_unq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.itenspassos
    ADD CONSTRAINT passos_itens_unq UNIQUE (grupopassos_id, passos_id);


--
-- TOC entry 4553 (class 2606 OID 17942)
-- Name: rotinaitemlink rotinaitemlink_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rotinaitemlink
    ADD CONSTRAINT rotinaitemlink_pkey PRIMARY KEY (rotinaitem_id);


--
-- TOC entry 4559 (class 2606 OID 17944)
-- Name: rotinas rotinas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rotinas
    ADD CONSTRAINT rotinas_pkey PRIMARY KEY (id);


--
-- TOC entry 4556 (class 2606 OID 17946)
-- Name: rotinaitens rotinasitens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rotinaitens
    ADD CONSTRAINT rotinasitens_pkey PRIMARY KEY (rotina_id, passo_id);


--
-- TOC entry 4562 (class 2606 OID 17948)
-- Name: tenant tenant_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant
    ADD CONSTRAINT tenant_pkey PRIMARY KEY (id);


--
-- TOC entry 4564 (class 2606 OID 17950)
-- Name: tipoempresa tipoempresa_id_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa
    ADD CONSTRAINT tipoempresa_id_pkey PRIMARY KEY (id);


--
-- TOC entry 4576 (class 2606 OID 27536)
-- Name: tipoempresa_obriga_bairro tipoempresa_obriga_bairro_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obriga_bairro
    ADD CONSTRAINT tipoempresa_obriga_bairro_pkey PRIMARY KEY (tipoempresa_obrigacao_id);


--
-- TOC entry 4579 (class 2606 OID 28760)
-- Name: tipoempresa_obrigacao_old tipoempresa_obrigacao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obrigacao_old
    ADD CONSTRAINT tipoempresa_obrigacao_pkey PRIMARY KEY (id);


--
-- TOC entry 4567 (class 2606 OID 17952)
-- Name: usuario usuario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_pkey PRIMARY KEY (id);


--
-- TOC entry 4570 (class 1259 OID 28806)
-- Name: idx_compromisso_financeiro_tipoempresa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_compromisso_financeiro_tipoempresa ON public.tipoempresa_obrigacao USING btree (tipo_empresa_id);


--
-- TOC entry 4582 (class 1259 OID 28796)
-- Name: idx_empresa_agenda_empresa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_empresa_agenda_empresa ON public.empresa_agenda USING btree (empresa_id);


--
-- TOC entry 4583 (class 1259 OID 28797)
-- Name: idx_empresa_agenda_template; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_empresa_agenda_template ON public.empresa_agenda USING btree (template_id);


--
-- TOC entry 4584 (class 1259 OID 28798)
-- Name: idx_empresa_agenda_vencimento; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_empresa_agenda_vencimento ON public.empresa_agenda USING btree (data_vencimento);


--
-- TOC entry 4587 (class 1259 OID 28883)
-- Name: idx_empresa_compromissos_compromisso_fin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_empresa_compromissos_compromisso_fin ON public.empresa_compromissos USING btree (tipoempresa_obrigacao_id);


--
-- TOC entry 4588 (class 1259 OID 28881)
-- Name: idx_empresa_compromissos_empresa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_empresa_compromissos_empresa ON public.empresa_compromissos USING btree (empresa_id);


--
-- TOC entry 4589 (class 1259 OID 28898)
-- Name: idx_empresa_compromissos_tipo_obrigacao; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_empresa_compromissos_tipo_obrigacao ON public.empresa_compromissos USING btree (tipoempresa_obrigacao_id);


--
-- TOC entry 4590 (class 1259 OID 28882)
-- Name: idx_empresa_compromissos_vencimento; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_empresa_compromissos_vencimento ON public.empresa_compromissos USING btree (vencimento);


--
-- TOC entry 4554 (class 1259 OID 17953)
-- Name: idx_rotinaitens_ordem; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rotinaitens_ordem ON public.rotinaitens USING btree (ordem);


--
-- TOC entry 4557 (class 1259 OID 28850)
-- Name: idx_rotinas_tipo_empresa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rotinas_tipo_empresa ON public.rotinas USING btree (tipo_empresa_id);


--
-- TOC entry 4577 (class 1259 OID 28795)
-- Name: idx_tipoempresa_obrigacao_tipo_empresa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tipoempresa_obrigacao_tipo_empresa ON public.tipoempresa_obrigacao_old USING btree (tipo_empresa_id);


--
-- TOC entry 4560 (class 1259 OID 17954)
-- Name: tenant_nome_unico; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX tenant_nome_unico ON public.tenant USING btree (nome);


--
-- TOC entry 4565 (class 1259 OID 17955)
-- Name: usuario_email_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX usuario_email_key ON public.usuario USING btree (email);


--
-- TOC entry 4615 (class 2620 OID 17956)
-- Name: empresa gerar_agenda; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER gerar_agenda AFTER UPDATE ON public.empresa FOR EACH ROW EXECUTE FUNCTION public.gerar_agenda_trigger();


--
-- TOC entry 4597 (class 2606 OID 17957)
-- Name: municipio Municipio_ufId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.municipio
    ADD CONSTRAINT "Municipio_ufId_fkey" FOREIGN KEY (ufid) REFERENCES public.estado(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4604 (class 2606 OID 27498)
-- Name: tipoempresa_obriga_estado compromisso_estado_compromisso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obriga_estado
    ADD CONSTRAINT compromisso_estado_compromisso_id_fkey FOREIGN KEY (obrigacao_id) REFERENCES public.tipoempresa_obrigacao(id) ON DELETE CASCADE;


--
-- TOC entry 4605 (class 2606 OID 27503)
-- Name: tipoempresa_obriga_estado compromisso_estado_estado_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obriga_estado
    ADD CONSTRAINT compromisso_estado_estado_id_fkey FOREIGN KEY (estado_id) REFERENCES public.estado(id);


--
-- TOC entry 4606 (class 2606 OID 27517)
-- Name: tipoempresa_obriga_municipio compromisso_municipio_compromisso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obriga_municipio
    ADD CONSTRAINT compromisso_municipio_compromisso_id_fkey FOREIGN KEY (obrigacao_id) REFERENCES public.tipoempresa_obrigacao(id) ON DELETE CASCADE;


--
-- TOC entry 4607 (class 2606 OID 27522)
-- Name: tipoempresa_obriga_municipio compromisso_municipio_municipio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obriga_municipio
    ADD CONSTRAINT compromisso_municipio_municipio_id_fkey FOREIGN KEY (municipio_id) REFERENCES public.municipio(id);


--
-- TOC entry 4591 (class 2606 OID 17962)
-- Name: dadoscomplementares dadoscomplementares_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dadoscomplementares
    ADD CONSTRAINT dadoscomplementares_fkey FOREIGN KEY (tenantid) REFERENCES public.tenant(id);


--
-- TOC entry 4611 (class 2606 OID 28785)
-- Name: empresa_agenda empresa_agenda_empresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_agenda
    ADD CONSTRAINT empresa_agenda_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresa(id) ON DELETE CASCADE;


--
-- TOC entry 4612 (class 2606 OID 28888)
-- Name: empresa_agenda empresa_agenda_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_agenda
    ADD CONSTRAINT empresa_agenda_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.tipoempresa_obrigacao(id) ON DELETE CASCADE;


--
-- TOC entry 4613 (class 2606 OID 28871)
-- Name: empresa_compromissos empresa_compromissos_empresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_compromissos
    ADD CONSTRAINT empresa_compromissos_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresa(id) ON DELETE CASCADE;


--
-- TOC entry 4614 (class 2606 OID 28893)
-- Name: empresa_compromissos empresa_compromissos_tipoempresa_obrigacao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empresa_compromissos
    ADD CONSTRAINT empresa_compromissos_tipoempresa_obrigacao_id_fkey FOREIGN KEY (tipoempresa_obrigacao_id) REFERENCES public.tipoempresa_obrigacao(id) ON DELETE RESTRICT;


--
-- TOC entry 4603 (class 2606 OID 28801)
-- Name: tipoempresa_obrigacao fk_compromisso_tipoempresa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obrigacao
    ADD CONSTRAINT fk_compromisso_tipoempresa FOREIGN KEY (tipo_empresa_id) REFERENCES public.tipoempresa(id);


--
-- TOC entry 4608 (class 2606 OID 27542)
-- Name: tipoempresa_obriga_bairro fk_obriga_bairro_municipio; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obriga_bairro
    ADD CONSTRAINT fk_obriga_bairro_municipio FOREIGN KEY (municipio_id) REFERENCES public.municipio(id);


--
-- TOC entry 4609 (class 2606 OID 27537)
-- Name: tipoempresa_obriga_bairro fk_obriga_bairro_obrigacao; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obriga_bairro
    ADD CONSTRAINT fk_obriga_bairro_obrigacao FOREIGN KEY (tipoempresa_obrigacao_id) REFERENCES public.tipoempresa_obrigacao(id) ON DELETE CASCADE;


--
-- TOC entry 4592 (class 2606 OID 17967)
-- Name: grupopassos grupo_municipio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupopassos
    ADD CONSTRAINT grupo_municipio_id_fkey FOREIGN KEY (municipio_id) REFERENCES public.municipio(id) NOT VALID;


--
-- TOC entry 4593 (class 2606 OID 17972)
-- Name: grupopassos grupo_tipoempresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grupopassos
    ADD CONSTRAINT grupo_tipoempresa_id_fkey FOREIGN KEY (tipoempresa_id) REFERENCES public.tipoempresa(id) NOT VALID;


--
-- TOC entry 4594 (class 2606 OID 17977)
-- Name: itenspassos grupopassos_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.itenspassos
    ADD CONSTRAINT grupopassos_id_fkey FOREIGN KEY (grupopassos_id) REFERENCES public.grupopassos(id);


--
-- TOC entry 4596 (class 2606 OID 17982)
-- Name: linkpassos linkpassos_passos_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.linkpassos
    ADD CONSTRAINT linkpassos_passos_id_fkey FOREIGN KEY (passo_id) REFERENCES public.passos(id) NOT VALID;


--
-- TOC entry 4600 (class 2606 OID 17987)
-- Name: rotinas municipio_cidade_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rotinas
    ADD CONSTRAINT municipio_cidade_id_fkey FOREIGN KEY (municipio_id) REFERENCES public.municipio(id) NOT VALID;


--
-- TOC entry 4595 (class 2606 OID 17992)
-- Name: itenspassos passos_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.itenspassos
    ADD CONSTRAINT passos_id_fkey FOREIGN KEY (passos_id) REFERENCES public.passos(id) NOT VALID;


--
-- TOC entry 4598 (class 2606 OID 17997)
-- Name: rotinaitens rotinas_passo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rotinaitens
    ADD CONSTRAINT rotinas_passo_id_fkey FOREIGN KEY (passo_id) REFERENCES public.passos(id) NOT VALID;


--
-- TOC entry 4599 (class 2606 OID 18002)
-- Name: rotinaitens rotinas_rotina_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rotinaitens
    ADD CONSTRAINT rotinas_rotina_id_fkey FOREIGN KEY (rotina_id) REFERENCES public.rotinas(id) NOT VALID;


--
-- TOC entry 4601 (class 2606 OID 28845)
-- Name: rotinas rotinas_tipo_empresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rotinas
    ADD CONSTRAINT rotinas_tipo_empresa_id_fkey FOREIGN KEY (tipo_empresa_id) REFERENCES public.tipoempresa(id);


--
-- TOC entry 4610 (class 2606 OID 28761)
-- Name: tipoempresa_obrigacao_old tipoempresa_obrigacao_tipo_empresa_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipoempresa_obrigacao_old
    ADD CONSTRAINT tipoempresa_obrigacao_tipo_empresa_id_fkey FOREIGN KEY (tipo_empresa_id) REFERENCES public.tipoempresa(id) ON DELETE CASCADE;


--
-- TOC entry 4602 (class 2606 OID 18007)
-- Name: usuario usuario_tenantid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_tenantid_fkey FOREIGN KEY (tenantid) REFERENCES public.tenant(id) ON UPDATE CASCADE ON DELETE RESTRICT;


-- Completed on 2026-03-31 10:35:59 -03

--
-- PostgreSQL database dump complete
--

\unrestrict jCfDQHbffxC2f8xdQ3w3yHUearAh1C95mS81KNOD0Eh0n2odIcS3ALAZbPTvWps

