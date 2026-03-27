import setupAPIClient from '../../components/api/api';

type GetCompromissosParams = {
  lazyEvent: string;
};

type MutateCompromissoParams = {
  id?: string;
  tipoempresa?: { id?: string; nome?: string };
  natureza?: string;
  descricao?: string;
  periodicidade?: string;
  abrangencia?: string;
  valor?: number;
  observacao?: string;
  estado?: { id?: string; nome?: string };
  municipio?: { id?: string; nome?: string };
  bairro?: string;
};

export default function CompromissoService() {
  return {

    getCompromissos: async (params: GetCompromissosParams) => {
      try {
        const apiClient = setupAPIClient(undefined);
        const response = await apiClient.get('/api/compromissos', {
          params: JSON.parse(params.lazyEvent),
        });
        const { compromissos, totalRecords } = response.data;
        return { data: { compromissos, totalRecords } };
      } catch (err) {
        throw new Error('Erro ao buscar compromissos');
      }
    },

    createCompromisso: async (params: MutateCompromissoParams) => {
      try {
        const apiClient = setupAPIClient(undefined);
        await apiClient.post('/api/compromisso', { params });
        return { success: true };
      } catch (err) {
        throw new Error('Erro ao criar compromisso');
      }
    },

    updateCompromisso: async (params: MutateCompromissoParams) => {
      try {
        const apiClient = setupAPIClient(undefined);
        await apiClient.put('/api/compromisso', { params });
        return { success: true };
      } catch (err) {
        throw new Error('Erro ao atualizar compromisso');
      }
    },

    deleteCompromisso: async (params: MutateCompromissoParams) => {
      try {
        const apiClient = setupAPIClient(undefined);
        await apiClient.put('/api/deletecompromisso', { params });
        return { success: true };
      } catch (err) {
        throw new Error('Erro ao excluir compromisso');
      }
    },
  };
}
