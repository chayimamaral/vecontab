import setupAPIClient from '../../components/api/api';

export type TabelaConsumoFaixa = {
    id: string;
    tipo: string;
    faixa: number;
    quantidade_de: number;
    quantidade_ate?: number | null;
    preco: number;
    ativo: boolean;
};

export type IntegraGasto = {
    id: string;
    tenant_id: string;
    empresa_documento: string;
    tipo: string;
    id_sistema: string;
    id_servico: string;
    quantidade: number;
    consumo_mes: number;
    faixa_aplicada: number;
    preco_unitario: number;
    valor_total: number;
    processado_em: string;
};

export default function IntegraTabelaConsumoService() {
    const listFaixas = async (tipo?: string) => {
        const api = setupAPIClient(undefined);
        const { data } = await api.get('/api/integra-contador/tabela-consumo', {
            params: { tipo: tipo ?? '' },
        });
        return data?.faixas ?? [];
    };

    const createFaixa = async (params: Omit<TabelaConsumoFaixa, 'id' | 'ativo'>) => {
        const api = setupAPIClient(undefined);
        return api.post('/api/integra-contador/tabela-consumo', { params });
    };

    const updateFaixa = async (params: Omit<TabelaConsumoFaixa, 'ativo'>) => {
        const api = setupAPIClient(undefined);
        return api.put('/api/integra-contador/tabela-consumo', { params });
    };

    const deleteFaixa = async (id: string) => {
        const api = setupAPIClient(undefined);
        return api.put('/api/integra-contador/tabela-consumo/delete', { params: { id } });
    };

    const listGastos = async (opts?: { empresaDocumento?: string; tipo?: string }) => {
        const api = setupAPIClient(undefined);
        const { data } = await api.get('/api/integra-contador/gastos', {
            params: {
                empresa_documento: opts?.empresaDocumento ?? '',
                tipo: opts?.tipo ?? '',
            },
        });
        return {
            gastos: (data?.gastos ?? []) as IntegraGasto[],
            totalValor: Number(data?.total_valor ?? 0),
            totalQuantidade: Number(data?.total_quantidade ?? 0),
        };
    };

    return { listFaixas, createFaixa, updateFaixa, deleteFaixa, listGastos };
}
