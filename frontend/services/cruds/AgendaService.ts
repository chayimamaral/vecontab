import setupAPIClient from '../../components/api/api';
import { AxiosError } from 'axios';

export default function AgendaService() {

  const normalizeEvents = (payload: any) => {
    if (Array.isArray(payload)) {
      return payload;
    }
    if (Array.isArray(payload?.events)) {
      return payload.events;
    }
    return [];
  };

  return {

    getAgendaList: async (params): Promise<any[]> => {
      try {
        const apiClient = setupAPIClient(undefined);
        const response = await apiClient.get('/api/agendalist', {
          params: params,
        });
        return normalizeEvents(response.data);
      } catch (err) {
        const axiosErr = err as AxiosError<{ error?: string; message?: string }>;
        const message =
          axiosErr.response?.data?.error ||
          axiosErr.response?.data?.message ||
          axiosErr.message ||
          'Erro ao buscar agendaList';
        throw new Error(message);

      }
    },

    getDetalhes: async (params): Promise<any[]> => {
      try {
        const apiClient = setupAPIClient(undefined);
        const resposta = await apiClient.get('/api/agendadetalhes', {
          params: params,
        });
        return normalizeEvents(resposta.data);
      } catch (err) {
        const axiosErr = err as AxiosError<{ error?: string; message?: string }>;
        const message =
          axiosErr.response?.data?.error ||
          axiosErr.response?.data?.message ||
          axiosErr.message ||
          'Erro ao buscar detalhes da agenda';
        throw new Error(message);

      }
    },

    concluirPasso: async (payload: { agenda_id: string; agenda_item_id: string }) => {
      try {
        const apiClient = setupAPIClient(undefined);
        const response = await apiClient.post('/api/agenda/concluir-passo', payload);

        return {
          data: response.data
        };
      } catch (err) {
        const axiosErr = err as AxiosError<{ error?: string; message?: string }>;
        const message =
          axiosErr.response?.data?.error ||
          axiosErr.response?.data?.message ||
          axiosErr.message ||
          'Erro ao concluir passo da agenda';
        throw new Error(message);
      }
    },

    reabrirPasso: async (payload: { agenda_id: string; agenda_item_id: string }) => {
      try {
        const apiClient = setupAPIClient(undefined);
        const response = await apiClient.post('/api/agendareabrirpasso', payload);

        return {
          data: response.data
        };
      } catch (err) {
        const axiosErr = err as AxiosError<{ error?: string; message?: string }>;
        const message =
          axiosErr.response?.data?.error ||
          axiosErr.response?.data?.message ||
          axiosErr.message ||
          'Erro ao reabrir passo da agenda';
        throw new Error(message);
      }
    },

    createAgendaItem: async (payload: {
      agenda_id: string;
      descricao: string;
      inicio: string;
      termino?: string;
    }) => {
      const apiClient = setupAPIClient(undefined);
      const response = await apiClient.post('/api/agenda/item', payload);
      return response.data as { agenda_id: string; agenda_item_id: string };
    },

    updateAgendaItem: async (payload: {
      agenda_id: string;
      agenda_item_id: string;
      descricao?: string;
      inicio?: string;
      termino?: string;
    }) => {
      const apiClient = setupAPIClient(undefined);
      await apiClient.put('/api/agenda/item', payload);
    },

    deleteAgendaItem: async (agenda_id: string, agenda_item_id: string) => {
      const apiClient = setupAPIClient(undefined);
      await apiClient.delete('/api/agenda/item', {
        params: { agenda_id, agenda_item_id },
      });
    },

  }
  // return {
  //   getAgendaList,
  //   getAgendaDetalhesBug,
  //   getDetalhes,
  // }

}