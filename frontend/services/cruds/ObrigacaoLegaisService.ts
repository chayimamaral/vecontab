import { AxiosError } from 'axios';
import setupAPIClient from '../../components/api/api';

function msgFromAxios(err: unknown, fallback: string): string {
  const ax = err as AxiosError<{ error?: string }>;
  const server = ax.response?.data?.error;
  if (typeof server === 'string' && server.trim() !== '') {
    return server.trim();
  }
  if (ax.response?.status === 401) {
    return 'Sessão expirada ou não autorizado. Faça login novamente.';
  }
  if (ax.code === 'ERR_NETWORK' || ax.message === 'Network Error') {
    return 'Não foi possível conectar à API. Verifique se o backend está em execução e NEXT_PUBLIC_API_URL.';
  }
  return fallback;
}

type GetParams = {
  lazyEvent: string;
};

type MutateParams = {
  id?: string;
  dia_base?: number;
  mes_base?: string | number | null;
  tipo_classificacao?: string;
  tipoempresa?: { id?: string; nome?: string; descricao?: string };
  descricao?: string;
  periodicidade?: string;
  abrangencia?: string;
  valor?: number;
  observacao?: string;
  estado?: { id?: string; nome?: string };
  municipio?: { id?: string; nome?: string };
  bairro?: string;
  catalogo_servico_ids?: string[];
};

export default function ObrigacaoLegaisService() {
  return {
    getObrigacoes: async (params: GetParams) => {
      try {
        const apiClient = setupAPIClient(undefined);
        const response = await apiClient.get('/api/obrigacoes', {
          params: JSON.parse(params.lazyEvent),
        });
        const { obrigacoes, totalRecords } = response.data;
        return { data: { obrigacoes, totalRecords } };
      } catch (err) {
        throw new Error(msgFromAxios(err, 'Erro ao buscar obrigações legais'));
      }
    },

    createObrigacao: async (params: MutateParams) => {
      try {
        const apiClient = setupAPIClient(undefined);
        await apiClient.post('/api/obrigacao', { params });
        return { success: true };
      } catch (err) {
        throw new Error(msgFromAxios(err, 'Erro ao criar obrigação legal'));
      }
    },

    updateObrigacao: async (params: MutateParams) => {
      try {
        const apiClient = setupAPIClient(undefined);
        await apiClient.put('/api/obrigacao', { params });
        return { success: true };
      } catch (err) {
        throw new Error(msgFromAxios(err, 'Erro ao atualizar obrigação legal'));
      }
    },

    deleteObrigacao: async (params: MutateParams) => {
      try {
        const apiClient = setupAPIClient(undefined);
        await apiClient.put('/api/deleteobrigacao', { params });
        return { success: true };
      } catch (err) {
        throw new Error(msgFromAxios(err, 'Erro ao excluir obrigação legal'));
      }
    },
  };
}
