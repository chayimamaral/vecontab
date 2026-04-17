import setupAPIClient from '../../components/api/api';
import { Vec } from '../../types/types';

export interface MonitorOperacaoListResponse {
  itens: Vec.MonitorOperacaoItem[];
  total: number;
}

export interface MonitorOperacaoListFilters {
  clienteNome?: string;
  status?: string;
  dataDe?: string;
  dataAte?: string;
}

export default function MonitorOperacaoService() {
  const list = async (limit = 50, offset = 0, filters: MonitorOperacaoListFilters = {}) => {
    const api = setupAPIClient(undefined);
    const response = await api.get<MonitorOperacaoListResponse>('/api/monitor/operacoes', {
      params: {
        limit,
        offset,
        cliente_nome: filters.clienteNome?.trim() || undefined,
        status: filters.status?.trim() || undefined,
        data_de: filters.dataDe?.trim() || undefined,
        data_ate: filters.dataAte?.trim() || undefined,
      },
    });
    return response.data ?? { itens: [], total: 0 };
  };

  return { list };
}
