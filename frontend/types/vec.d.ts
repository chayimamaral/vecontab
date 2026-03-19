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
        bairro: '';
        municipio: MunicipioLite;
        rotina: RotinaLite;
        uf: '';
        cep: '';
        tenantid: '';
        cnaes: string[];
        iniciado: boolean;
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
        active?: boolean;
    }

    type CNAE = {
        id?: string;
        subclasse?: string;
        denominacao?: string;
    }
}
