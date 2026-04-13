/* FullCalendar Types */
import { EventApi, EventInput } from '@fullcalendar/core';

/* Chart.js Types */
import { ChartData, ChartOptions } from 'chart.js';

type InventoryStatus = 'INSTOCK' | 'LOWSTOCK' | 'OUTOFSTOCK';

type Status = 'DELIVERED' | 'PENDING' | 'RETURNED' | 'CANCELLED';

export type LayoutType = 'list' | 'grid';
export type SortOrderType = 1 | 0 | -1;

declare namespace Vec {

    type TipoEmpresa = {
        id?: string;
        descricao?: string;
        anual?: number;
    }

    type TipoEmpresaLite = {
        id?: string;
        descricao?: string;
    }

    type Estado = {
        id?: string;
        nome?: string;
        sigla?: string;
    };

    type Cidade = {
        id?: string;
        nome?: string;
        codigo?: string;
        ufid?: string;
        uf?: Estado;
    };

    type Municipio = {
        id?: string;
        nome?: string;
        codigo?: string;
        ufId?: string;
        uf?: Estado;
    };

    type MunicipioLite = {
        id?: string;
        nome?: string;
    }

    type Passo = {
        id?: string;
        descricao?: string;
        tempoestimado?: number;
        tipopasso?: string;
        link?: string;
        municipio_id?: string;
        municipio?: MunicipioLite;
    }

    type EmpresaDados = {
        empresa_id?: string;
        municipio_id?: string;
        municipio?: MunicipioLite;
        cnpj?: string;
        /** Capital social (PJ); coluna public.clientes_dados.capital_social */
        capital_social?: number | null;
        endereco?: string;
        numero?: string;
        cep?: string;
        email_contato?: string;
        telefone?: string;
        telefone2?: string;
        data_abertura?: string;
        data_encerramento?: string;
        observacao?: string;
    };

    type Empresa = {
        id?: string;
        nome?: string;
        /** PF | PJ — coluna public.empresa.tipo_pessoa */
        tipo_pessoa?: string;
        /** CPF (PF) ou CNPJ opcional (PJ); coluna public.empresa.documento */
        documento?: string;
        cnpj?: string;
        ie?: string;
        im?: string;
        razaosocial?: string;
        fantasia?: string;
        endereco?: string;
        numero?: string;
        complemento?: string;
        bairro?: string;
        municipio: MunicipioLite;
        rotina: RotinaLite;
        /** Template PF (IRPF / Carnê-Leão etc.); alinhado ao JSON da API */
        rotina_pf?: RotinaPFLite;
        tipo_empresa?: TipoEmpresaLite;
        uf?: string;
        cep?: string;
        tenantid?: string;
        cnaes: string[];
        iniciado: boolean;
        passos_concluidos?: boolean;
        compromissos_gerados?: boolean;
    }

    type GrupoPasso = {
        id?: string;
        descricao?: string;
        municipio_id?: string;
        tipoempresa_id?: string;
        municipio?: MunicipioLite;
        tipoempresa?: TipoEmpresaLite;
    }

    type Rotina = {
        id?: string;
        descricao?: string;
        cidade_id?: string;
        municipio?: MunicipioLite;
    }

    type Rotinas = {
        id?: string;
        descricao?: string;
        cidade_id?: string;
        municipio?: MunicipioLite;
        rotinaitens?: RotinaItem;
    }

    type RotinaLite = {
        id?: string;
        descricao?: string;
        tipo_empresa_id?: string;
        tipo_empresa?: TipoEmpresaLite;
        municipio?: MunicipioLite;
        /** Rótulo para dropdown quando a lista reúne rotinas de vários municípios */
        lista_label?: string;
    }

    /** Template de rotina para cliente PF (federal / sazonal); tenant. */
    type RotinaPFLite = {
        id?: string;
        nome?: string;
        categoria?: string;
    }

    type RotinaPFListRow = {
        id?: string;
        nome?: string;
        categoria?: string;
        descricao?: string;
        ativo?: boolean;
        criado_em?: string;
        item_count?: number;
    }

    type RotinaPFItemRow = {
        id?: string;
        rotina_pf_id?: string;
        ordem?: number;
        passo_id?: string;
        passo_descricao?: string;
        descricao?: string;
        tempo_estimado?: number;
    }

    type RotinaItem = {
        id?: string;
        descricao?: string;
        tempoestimado?: number;
        tipopasso?: string;
        rotina_id?: string;
        ordem?: number;
        link?: RotinaLink;
    }

    type RotinaLink = {
        rotina_id?: string;
        descricao?: string;
    }

    type Usuarios = {
        id?: string;
        nome?: string;
        email?: string;
        password?: string;
        role?: string;
        tenantid?: string;
        tenantnome?: string;
        active?: boolean;
    }

    type CNAE = {
        id?: string;
        secao?: string;
        divisao?: string;
        grupo?: string;
        classe?: string;
        subclasse?: string;
        denominacao?: string;
    }

    /** CRT federal (SPED) + metadados de obrigacoes em configuracao_json */
    type RegimeTributario = {
        id?: string;
        nome?: string;
        codigo_crt?: number;
        tipo_apuracao?: string;
        ativo?: boolean;
        configuracao_json?: Record<string, unknown>;
    }

    type CompromissoRef = {
        id?: string;
        nome?: string;
    }

    type Compromisso = {
        id?: string;
        tipo_empresa_id?: string;
        tipoempresa?: TipoEmpresaLite;
        natureza?: string;      // FINANCEIRO | NAO_FINANCEIRO
        descricao?: string;
        periodicidade?: string;  // MENSAL | ANUAL
        abrangencia?: string;    // FEDERAL | ESTADUAL | MUNICIPAL | BAIRRO
        valor?: number;
        observacao?: string;
        estado?: CompromissoRef;
        municipio?: CompromissoRef;
        bairro?: string;
    }

    type Obrigacao = {
        id?: string;
        tipo_empresa_id?: string;
        descricao?: string;
        dia_base?: number;
        mes_base?: number | null;
        frequencia?: string;  // MENSAL | ANUAL
        tipo?: string;        // TRIBUTO | INFORMATIVA
    }

    type EmpresaAgendaItem = {
        id?: string;
        empresa_id?: string;
        template_id?: string;
        descricao?: string;
        data_vencimento?: string;
        status?: string;       // PENDENTE | PAGO | ATRASADO
        valor_estimado?: number | null;
    }

    type EmpresaAgendaAcompanhamentoItem = {
        empresa_id?: string;
        empresa_nome?: string;
        compromisso_id?: string;
        descricao?: string;
        data_vencimento?: string;
        status?: string;
        tipo?: string;         // TRIBUTO | INFORMATIVA (template)
        classificacao?: string; // FINANCEIRO | NAO_FINANCEIRO (derivado do template)
        agenda_item_id?: string;
        valor_estimado?: number | null;
    }

    type MonitorOperacaoItem = {
        id?: string;
        tenant_id?: string;
        tenant_nome?: string;
        user_id?: string;
        origem?: string;
        tipo?: string;
        status?: string;
        mensagem?: string;
        detalhe?: Record<string, unknown>;
        criado_em?: string;
    }
}
