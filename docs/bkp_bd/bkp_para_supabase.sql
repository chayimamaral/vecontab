--
-- PostgreSQL database dump
--

\restrict djJ3u7fqK190Fba53Y9po3GoUrL1flb0tM5AqG8GGrjKMN9hmbHbusCr5VP4XiX

-- Dumped from database version 18.3
-- Dumped by pg_dump version 18.3

-- Started on 2026-03-31 07:39:18 -03

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

DROP DATABASE vecontab;
--
-- TOC entry 4797 (class 1262 OID 17603)
-- Name: vecontab; Type: DATABASE; Schema: -; Owner: -
--

CREATE DATABASE vecontab WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE_PROVIDER = libc LOCALE = 'pt_BR.UTF-8';


\unrestrict djJ3u7fqK190Fba53Y9po3GoUrL1flb0tM5AqG8GGrjKMN9hmbHbusCr5VP4XiX
\connect vecontab
\restrict djJ3u7fqK190Fba53Y9po3GoUrL1flb0tM5AqG8GGrjKMN9hmbHbusCr5VP4XiX

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

CREATE SCHEMA public;


--
-- TOC entry 4798 (class 0 OID 0)
-- Dependencies: 5
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


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
-- TOC entry 244 (class 1259 OID 27527)
-- Name: compromisso_bairro; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.compromisso_bairro (
    compromisso_id uuid NOT NULL,
    municipio_id text NOT NULL,
    bairro character varying(255)
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
-- TOC entry 4764 (class 0 OID 17681)
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
-- TOC entry 4765 (class 0 OID 17696)
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
-- TOC entry 4766 (class 0 OID 17707)
-- Dependencies: 222
-- Data for Name: cnae; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.cnae (id, subclasse, denominacao, ativo) FROM stdin;
1137c51a-f601-43ff-b7e9-55d6baedac31	62.02-3/00	Desenvolvimento e licenciamento de Programas de Computador não customizáveis	t
35fe9134-1db2-4a23-817b-99fb5e61f8a1	62.04-0/00	Consultoria em Tecnologia da Informação	t
\.


--
-- TOC entry 4788 (class 0 OID 27527)
-- Dependencies: 244
-- Data for Name: compromisso_bairro; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.compromisso_bairro (compromisso_id, municipio_id, bairro) FROM stdin;
\.


--
-- TOC entry 4767 (class 0 OID 17718)
-- Dependencies: 223
-- Data for Name: dadoscomplementares; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.dadoscomplementares (endereco, bairro, cidade, estado, cep, telefone, email, cnpj, ie, im, tenantid, createdat, updatedat, fantasia, razaosocial, observacoes) FROM stdin;
\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	c0b38958-8832-465d-9efa-812185c2fb1a	2023-07-04 14:06:37.932	2023-07-04 14:06:37.932	\N	\N	\N
\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	89e5d80e-5745-4235-84e1-ae590de026ea	2023-07-04 14:08:14.279	2023-07-04 14:08:14.279	\N	\N	\N
\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	4d95e964-6d08-4316-8a63-3e994c93f622	2023-07-04 15:26:43.812	2023-07-04 15:26:43.812	\N	\N	\N
\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	02ca80b9-7a5b-4715-a9ee-9226f89087a5	2023-07-05 18:57:33.628	2023-07-05 18:57:33.628	\N	\N	\N
\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	7a0eb58a-aaea-4782-8724-06144fceff00	2023-07-06 08:51:29.979	2023-07-06 08:51:29.979	\N	\N	\N
Rua das Curruiras, 175	Campeche	Florianópolis	SC	88063091	48 988151381	chayimamaral@gmail.com	\N	\N	\N	5bf1a2bc-b39e-4af6-97df-bb70326373ab	2023-07-06 16:25:28.288	2023-07-06 16:25:28.288	Carlos Amaral	VEC	Novo teste testando o teste de observações.
\.


--
-- TOC entry 4768 (class 0 OID 17728)
-- Dependencies: 224
-- Data for Name: empresa; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.empresa (id, nome, municipio_id, dataabertura, datafechamento, ativo, tenant_id, rotina_id, cnaes, iniciado, bairro) FROM stdin;
32c99043-ae5e-47a6-b3db-e02f13b5aff9	Ploc Industria de goma de mascar	4a8647d1-06c8-4616-85be-3f6399949ed3	\N	\N	t	5bf1a2bc-b39e-4af6-97df-bb70326373ab	ed925e14-d150-434f-b287-7154d67c1d0a	{}	t	\N
3bd699c9-15dc-4a79-8ee8-0a098073203b	Empresa Exemplo	4a8647d1-06c8-4616-85be-3f6399949ed3	\N	\N	t	5bf1a2bc-b39e-4af6-97df-bb70326373ab	ed925e14-d150-434f-b287-7154d67c1d0a	{1234567,2345678}	t	\N
67207fad-07aa-4daf-b667-f3b926a120ad	Vec Sistemas	abfd20e5-d561-4c44-ba42-ae194ebb2c18	\N	\N	t	5bf1a2bc-b39e-4af6-97df-bb70326373ab	005a21fd-3aaa-43ee-a2e8-647a4d8845ab	{1234567,2345678,6225315,5648978,6354987,5264897}	t	\N
2d969b03-f302-437a-8cfe-7b85da6e28fb	Nova empresa teste de tags	6a69c90c-8475-4d97-9e9a-8647305346f1	\N	\N	t	5bf1a2bc-b39e-4af6-97df-bb70326373ab	595ac1c0-fe5e-4a87-8871-9d9cce8fce04	\N	t	\N
56fab307-b775-40f6-87ef-51daa7509698	Anadja Serviços Contábeis	6a69c90c-8475-4d97-9e9a-8647305346f1	\N	\N	t	5bf1a2bc-b39e-4af6-97df-bb70326373ab	595ac1c0-fe5e-4a87-8871-9d9cce8fce04	{1234567,5234465,1234869,1236587}	t	\N
030adbb7-7d9d-408f-bf90-786f0dca48d2	T2R Play Book - alteraçao	abfd20e5-d561-4c44-ba42-ae194ebb2c18	\N	\N	f	5bf1a2bc-b39e-4af6-97df-bb70326373ab	49241e34-99f6-4af3-98a2-cb39f251818a	{1234567,2356789,5231513}	f	\N
65ea4cdb-3bd1-48a3-8534-fd78190710ce	Nova Empresa TExte	abfd20e5-d561-4c44-ba42-ae194ebb2c18	\N	\N	t	5bf1a2bc-b39e-4af6-97df-bb70326373ab	005a21fd-3aaa-43ee-a2e8-647a4d8845ab	{}	f	\N
5b2eacf9-5289-402d-85be-52f7233d20d2	Carlos Amaral Consultoria	abfd20e5-d561-4c44-ba42-ae194ebb2c18	\N	\N	t	5bf1a2bc-b39e-4af6-97df-bb70326373ab	1cd6c238-d805-4c94-829e-bad7a9b62cfb	{}	t	\N
a0ef2dad-5f65-4821-bbf2-034477183f44	Empresa Teste	abfd20e5-d561-4c44-ba42-ae194ebb2c18	\N	\N	t	5bf1a2bc-b39e-4af6-97df-bb70326373ab	1cd6c238-d805-4c94-829e-bad7a9b62cfb	{}	f	\N
\.


--
-- TOC entry 4790 (class 0 OID 28766)
-- Dependencies: 246
-- Data for Name: empresa_agenda; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.empresa_agenda (id, empresa_id, template_id, descricao, data_vencimento, status, valor_estimado, criado_em, atualizado_em) FROM stdin;
\.


--
-- TOC entry 4791 (class 0 OID 28851)
-- Dependencies: 247
-- Data for Name: empresa_compromissos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.empresa_compromissos (id, descricao, valor, vencimento, observacao, status, empresa_id, tipoempresa_obrigacao_id, criado_em, atualizado_em) FROM stdin;
\.


--
-- TOC entry 4769 (class 0 OID 17742)
-- Dependencies: 225
-- Data for Name: empresacnae; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.empresacnae (empresa, cnae) FROM stdin;
\.


--
-- TOC entry 4770 (class 0 OID 17749)
-- Dependencies: 226
-- Data for Name: empresadados; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.empresadados (id, razaosocial, fantasia, cnpj, ie, im, empresaid) FROM stdin;
\.


--
-- TOC entry 4763 (class 0 OID 17665)
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
\.


--
-- TOC entry 4771 (class 0 OID 17757)
-- Dependencies: 227
-- Data for Name: feriado_estadual; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.feriado_estadual (feriado_id, uf_id) FROM stdin;
6ae652e1-aacc-4d44-8f43-f06c9247dbda	59e0036a-4269-4297-a30a-d86a54dc4b7c
d9002885-b6e2-423d-a524-90be59cf1c94	0eacb915-f4a3-41dc-982e-e8c281a2a33c\n
\.


--
-- TOC entry 4772 (class 0 OID 17764)
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
-- TOC entry 4773 (class 0 OID 17771)
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
-- TOC entry 4774 (class 0 OID 17783)
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
-- TOC entry 4775 (class 0 OID 17799)
-- Dependencies: 231
-- Data for Name: itenspassos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.itenspassos (id, grupopassos_id, passos_id) FROM stdin;
53306540-e85d-4804-b679-ea518f286b4a	8de1301f-ba9d-41d8-b391-db9e0b56ab9c	023b4bb7-6054-4e14-b93b-7354d5e95eb8
e592d7a5-7c8f-4115-828c-78aba53f8d20	8de1301f-ba9d-41d8-b391-db9e0b56ab9c	7b35949c-3740-4da9-99c0-a15bdf3ff6d5
\.


--
-- TOC entry 4776 (class 0 OID 17808)
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
-- TOC entry 4777 (class 0 OID 17815)
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
\.


--
-- TOC entry 4778 (class 0 OID 17826)
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
-- TOC entry 4779 (class 0 OID 17842)
-- Dependencies: 235
-- Data for Name: rotinaitemlink; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.rotinaitemlink (rotinaitem_id, link) FROM stdin;
a5ee4f4e-9a78-4e4b-a02c-b379734699c3	www.jucesc.sc.gov.br
1d64ff79-3192-4b28-a4b8-7654daea77f4	www.pmbiguacu.gov.br
\.


--
-- TOC entry 4780 (class 0 OID 17848)
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
-- TOC entry 4781 (class 0 OID 17855)
-- Dependencies: 237
-- Data for Name: rotinas; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.rotinas (id, descricao, municipio_id, ativo, tipo_empresa_id) FROM stdin;
595ac1c0-fe5e-4a87-8871-9d9cce8fce04	Abertura LTDA Biguaçu	6a69c90c-8475-4d97-9e9a-8647305346f1	t	\N
ee39ab7c-aa90-44ab-b6fe-9cc94a6b3225	Encerramento de Empresa Floripa	abfd20e5-d561-4c44-ba42-ae194ebb2c18	t	\N
cbfc8f55-d3d0-42fb-a5d5-dd31f0dc643b	Encerramento Empresa Biguaçu	6a69c90c-8475-4d97-9e9a-8647305346f1	t	\N
ed925e14-d150-434f-b287-7154d67c1d0a	Abertura Ltda Guarujá	4a8647d1-06c8-4616-85be-3f6399949ed3	t	\N
005a21fd-3aaa-43ee-a2e8-647a4d8845ab	Abertura EIRELI Florianópolis	abfd20e5-d561-4c44-ba42-ae194ebb2c18	t	\N
8f07dcb1-7526-48d3-9d20-0816dd2baf5b	Abertura MEI Guarujá	4a8647d1-06c8-4616-85be-3f6399949ed3	t	\N
49241e34-99f6-4af3-98a2-cb39f251818a	Alteração Contratual LTDA Florianópolis	abfd20e5-d561-4c44-ba42-ae194ebb2c18	t	\N
6be4d4eb-d094-453d-bd52-579408300b45	Abertura de Filial Florianópolis	abfd20e5-d561-4c44-ba42-ae194ebb2c18	t	\N
e4fa2d00-bea7-4718-be6b-0c7608de7bb6	Teste pós Refactoring	f5531987-ec10-4099-b940-b9bde36c0b16	t	\N
5ac68905-e3cb-4acc-903e-2fbb2fe46b4b	Abertura MEI Campeche	abfd20e5-d561-4c44-ba42-ae194ebb2c18	f	\N
1cd6c238-d805-4c94-829e-bad7a9b62cfb	Abertura MEI Campeche	abfd20e5-d561-4c44-ba42-ae194ebb2c18	t	21a4bf05-3100-41e2-a3b2-e59ff67fc897
\.


--
-- TOC entry 4782 (class 0 OID 17866)
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
\.


--
-- TOC entry 4783 (class 0 OID 17882)
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
-- TOC entry 4786 (class 0 OID 27489)
-- Dependencies: 242
-- Data for Name: tipoempresa_obriga_estado; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tipoempresa_obriga_estado (obrigacao_id, estado_id) FROM stdin;
7a6e69c2-57e6-4beb-9ec1-e3424a7a2d8d	59e0036a-4269-4297-a30a-d86a54dc4b7c
5d3189ad-0395-490f-a929-b4f8675bad4e	59e0036a-4269-4297-a30a-d86a54dc4b7c
f3d85f25-31d0-4cdc-93f9-c9a9818e65c7	59e0036a-4269-4297-a30a-d86a54dc4b7c
c603a3c5-10ee-4b14-a122-b7473ece1fa5	59e0036a-4269-4297-a30a-d86a54dc4b7c
\.


--
-- TOC entry 4787 (class 0 OID 27508)
-- Dependencies: 243
-- Data for Name: tipoempresa_obriga_municipio; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tipoempresa_obriga_municipio (obrigacao_id, municipio_id) FROM stdin;
cf548021-bc2d-4091-8f1a-087918e5f577	4a8647d1-06c8-4616-85be-3f6399949ed3
9a9af32b-a611-46ea-9acc-abce4ab662ec	4a8647d1-06c8-4616-85be-3f6399949ed3
4acf5849-2a62-4390-b7b8-b0a2920113f0	4a8647d1-06c8-4616-85be-3f6399949ed3
e7873d49-a38d-48bd-aa59-268d943625e3	4a8647d1-06c8-4616-85be-3f6399949ed3
93c6a4dc-ae55-431a-b0d8-b69bc237875f	4a8647d1-06c8-4616-85be-3f6399949ed3
bce1f085-fdc7-4054-a20f-09ad6f22e2a6	4a8647d1-06c8-4616-85be-3f6399949ed3
e85d3da6-fac6-4f01-95af-0cbe67576089	4a8647d1-06c8-4616-85be-3f6399949ed3
\.


--
-- TOC entry 4785 (class 0 OID 27358)
-- Dependencies: 241
-- Data for Name: tipoempresa_obrigacao; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tipoempresa_obrigacao (id, descricao, periodicidade, abrangencia, valor, observacao, ativo, criado_em, atualizado_em, tipo_empresa_id, dia_base, mes_base, tipo_classificacao) FROM stdin;
93c6a4dc-ae55-431a-b0d8-b69bc237875f	Compromisso bairro mensal nao financeiro	MENSAL	MUNICIPAL	\N	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-30 18:25:14.268504-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	INFORMATIVA
bce1f085-fdc7-4054-a20f-09ad6f22e2a6	Compromisso bairro anual financeiro	ANUAL	MUNICIPAL	200.00	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-30 18:27:34.765519-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	TRIBUTARIA
cf548021-bc2d-4091-8f1a-087918e5f577	Compromisso municipal mensal financeiro	MENSAL	MUNICIPAL	120.00	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-27 10:43:14.959813-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	TRIBUTARIA
e7873d49-a38d-48bd-aa59-268d943625e3	Compromisso municipal anual financeiro	ANUAL	MUNICIPAL	130.00	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-30 14:10:36.379865-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	TRIBUTARIA
e85d3da6-fac6-4f01-95af-0cbe67576089	Compromisso bairro mensal financeiro	MENSAL	MUNICIPAL	200.00	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-30 18:39:14.692931-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	TRIBUTO
c603a3c5-10ee-4b14-a122-b7473ece1fa5	Compromisso estadual anual financeiro	ANUAL	ESTADUAL	110.00	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-30 19:20:19.374854-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	TRIBUTARIA
4acf5849-2a62-4390-b7b8-b0a2920113f0	Compromisso municipal anual nao financeiro	ANUAL	MUNICIPAL	\N	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-27 10:43:14.959813-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	INFORMATIVA
5d3189ad-0395-490f-a929-b4f8675bad4e	Compromisso estadual mensal nao financeiro	MENSAL	ESTADUAL	\N	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-27 10:43:14.959813-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	INFORMATIVA
9a9af32b-a611-46ea-9acc-abce4ab662ec	Compromisso municipal mensal nao financeiro	MENSAL	MUNICIPAL	\N	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-27 10:43:14.959813-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	INFORMATIVA
f3d85f25-31d0-4cdc-93f9-c9a9818e65c7	Compromisso estadual anual nao financeiro	ANUAL	ESTADUAL	\N	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-27 10:43:14.959813-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	INFORMATIVA
87a3300d-60a2-4d87-9e48-702ab9ad1ced	Compromisso bairro anual nao financeiro	ANUAL	MUNICIPAL	\N	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-30 18:28:23.579697-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	INFORMATIVA
7a6e69c2-57e6-4beb-9ec1-e3424a7a2d8d	Compromisso estadual mensal financeiro	MENSAL	ESTADUAL	100.00	Seed automatico MEI - abrangencia local.	t	2026-03-27 10:43:14.959813-03	2026-03-27 10:43:14.959813-03	21a4bf05-3100-41e2-a3b2-e59ff67fc897	20	4	TRIBUTARIA
\.


--
-- TOC entry 4789 (class 0 OID 28738)
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
-- TOC entry 4784 (class 0 OID 17890)
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
\.


--
-- TOC entry 4799 (class 0 OID 0)
-- Dependencies: 5
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO PUBLIC;


-- Completed on 2026-03-31 07:39:18 -03

--
-- PostgreSQL database dump complete
--

\unrestrict djJ3u7fqK190Fba53Y9po3GoUrL1flb0tM5AqG8GGrjKMN9hmbHbusCr5VP4XiX

