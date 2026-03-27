import setupAPIClient from '../../components/api/api';

type GerarAgendaParams = {
  empresa_id: string;
  tipo_empresa_id: string;
  data_inicio: string;
};

type UpdateStatusParams = {
  id: string;
  status: string;
};

export default function EmpresaAgendaService() {
  return {

    getAgenda: async (empresaId: string) => {
      try {
        const apiClient = setupAPIClient(undefined);
        const response = await apiClient.get('/api/empresaagenda', {
          params: { empresa_id: empresaId },
        });
        const { itens } = response.data;
        return { data: { itens } };
      } catch (err) {
        throw new Error('Erro ao buscar agenda da empresa');
      }
    },

    getAcompanhamento: async () => {
      try {
        const apiClient = setupAPIClient(undefined);
        const response = await apiClient.get('/api/empresaagenda/acompanhamento');
        const { itens } = response.data;
        return { data: { itens } };
      } catch (err) {
        throw new Error('Erro ao buscar acompanhamento de compromissos');
      }
    },

    gerarAgenda: async (params: GerarAgendaParams) => {
      try {
        const apiClient = setupAPIClient(undefined);
        const response = await apiClient.post('/api/empresaagenda/gerar', { params });
        return { data: response.data };
      } catch (err) {
        throw new Error('Erro ao gerar agenda da empresa');
      }
    },

    updateStatus: async (params: UpdateStatusParams) => {
      try {
        const apiClient = setupAPIClient(undefined);
        const response = await apiClient.put('/api/empresaagenda/status', { params });
        return { data: response.data };
      } catch (err) {
        throw new Error('Erro ao atualizar status da agenda');
      }
    },
  };
}
