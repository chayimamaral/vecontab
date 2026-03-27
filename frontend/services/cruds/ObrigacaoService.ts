import setupAPIClient from '../../components/api/api';

type MutateObrigacaoParams = {
  id?: string;
  tipo_empresa_id?: string;
  descricao?: string;
  dia_base?: number;
  mes_base?: number | null;
  frequencia?: string;
  tipo?: string;
};

export default function ObrigacaoService() {
  return {

    getObrigacoes: async (tipoEmpresaId: string) => {
      try {
        const apiClient = setupAPIClient(undefined);
        const response = await apiClient.get('/api/obrigacoes', {
          params: { tipo_empresa_id: tipoEmpresaId },
        });
        const { obrigacoes } = response.data;
        return { data: { obrigacoes } };
      } catch (err) {
        throw new Error('Erro ao buscar obrigações');
      }
    },

    createObrigacao: async (params: MutateObrigacaoParams) => {
      try {
        const apiClient = setupAPIClient(undefined);
        const response = await apiClient.post('/api/obrigacao', { params });
        return { data: response.data };
      } catch (err) {
        throw new Error('Erro ao criar obrigação');
      }
    },

    updateObrigacao: async (params: MutateObrigacaoParams) => {
      try {
        const apiClient = setupAPIClient(undefined);
        const response = await apiClient.put('/api/obrigacao', { params });
        return { data: response.data };
      } catch (err) {
        throw new Error('Erro ao atualizar obrigação');
      }
    },

    deleteObrigacao: async (params: MutateObrigacaoParams) => {
      try {
        const apiClient = setupAPIClient(undefined);
        await apiClient.put('/api/deleteobrigacao', { params });
        return { success: true };
      } catch (err) {
        throw new Error('Erro ao excluir obrigação');
      }
    },
  };
}
