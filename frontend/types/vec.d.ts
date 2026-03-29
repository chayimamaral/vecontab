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
        capital?: number;
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

    type Empresa = {
        id?: string;
        nome?: string;
        cnpj?: string;
        ie?: string;
        im?: string;
        razaosocial?: string;
        fantasia?: string;
        endereco: '';
        numero: '';
        complemento: '';
        bairro?: string;
        municipio: MunicipioLite;
        rotina: RotinaLite;
        tipo_empresa?: TipoEmpresaLite;
        uf: '';
        cep: '';
        tenantid: '';
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
        subclasse?: string;
        denominacao?: string;
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
}
