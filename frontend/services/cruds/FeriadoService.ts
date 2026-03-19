import setupAPIClient from '../../components/api/api';

export default function FeriadoService() {

  return {


    getFeriados: async (params) => {

      // do jeito que receber o params, ele vem como string, entao tem que converter para objeto
      try {
        const apiClient = setupAPIClient(undefined);
        // ao passar o params, ele vem como string, entao tem que converter para objeto com JSON.parse
        const response = await apiClient.get('/api/feriados', {
          params: JSON.parse(params.lazyEvent),
        });
        // não precisa converter para objeto, pois o axios já faz isso
        const { feriados, totalRecords } = response.data

        return {
          data: {
            feriados,
            totalRecords
          }
        }
      } catch (err) {
        throw new Error('Erro ao buscar feriados')

      }
    },

    createFeriado: async (params) => {
      try {
        const apiClient = setupAPIClient(undefined);
        const create = await apiClient.post('/api/feriado', {
          params: {
            ...params
          }
        })

        const response = await this.getFeriadosFixos(params)

        const { feriados, totalRecords } = response.data

        return {
          data: {
            feriados,
            totalRecords
          }
        }

      } catch (err) {
        return {
          redirect: {
            destination: '/feriados',
            permanent: false

          }
        }
      }
    },

    updateFeriado: async (params) => {
      try {
        const apiClient = setupAPIClient(undefined);

        const update = await apiClient.put('/api/feriado', {
          params: {
            ...params
          }

        })

        const response = await this.getFeriadosFixos(params)
        const { feriados, totalRecords } = response.data

        return {
          data: {
            feriados,
            totalRecords,
          }
        }
      } catch (err) {
        return {
          redirect: {
            destination: '/feriados',
            permanent: false

          }
        }
      }
    },

    deleteFeriado: async (params) => {
      try {
        const apiClient = setupAPIClient(undefined);
        const response = await apiClient.put('/api/deleteferiado', {
          params: {
            ...params
          }
        })

        const { feriados, totalRecords } = response.data

        return {
          data: {
            feriados,
            totalRecords,
          }
        }
      } catch (err) {
        throw new Error('Erro ao deletar feriado')
      }
    },


    //     return {
    //         getEstados,
    //         createEstado,
    //         updateEstado,
    //         deleteEstado,
    //         getUFCidade
    //     }
  }
}


