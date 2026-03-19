import setupAPIClient from '../../components/api/api';

export default function AgendaService() {

  return {

    getAgendaList: async (params) => {
      // do jeito que receber o params, ele vem como string, entao tem que converter para objeto
      try {
        const apiClient = setupAPIClient(undefined);
        // ao passar o params, ele vem como string, entao tem que converter para objeto com JSON.parse
        const response = await apiClient.get('/api/agendalist', {
          params: params,
        });
        // não precisa converter para objeto, pois o axios já faz isso
        const events = response.data;

        return {
          data: {
            events
          }
        }
      } catch (err) {
        throw new Error('Erro ao buscar agendaList', err)

      }
    },

    getDetalhes: async (params) => {
      // do jeito que receber o params, ele vem como string, entao tem que converter para objeto
      try {
        const apiClient = setupAPIClient(undefined);
        // ao passar o params, ele vem como string, entao tem que converter para objeto com JSON.parse
        const resposta = await apiClient.get('/api/agendadetalhes', {
          params: params,
        });
        // não precisa converter para objeto, pois o axios já faz isso
        const events = resposta.data

        console.log('events', events)

        return {
          data: {
            events
          }
        }
      } catch (err) {
        throw new Error('Erro ao buscar estados')

      }
    },

  }
  // return {
  //   getAgendaList,
  //   getAgendaDetalhesBug,
  //   getDetalhes,
  // }

}