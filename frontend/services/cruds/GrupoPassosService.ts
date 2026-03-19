import setupAPIClient from '../../components/api/api';

export default function GrupoPassosService() {

  const getGrupoPassos = async (params) => {
    // do jeito que receber o params, ele vem como string, entao tem que converter para objeto
    //console.log('params.lazyEvent', params.lazyEvent.toString())
    const apiClient = setupAPIClient(undefined);
    // ao passar o params, ele vem como string, entao tem que converter para objeto com JSON.parse
    try {
      const response = await apiClient.get('/api/grupopassos', {
        params: JSON.parse(params.lazyEvent),
      })

      // não precisa converter para objeto, pois o axios já faz isso
      const { grupopassos, totalRecords } = response.data

      return {
        data: {
          grupopassos,
          totalRecords
        }
      }
    } catch (err) {
      throw new Error('Erro ao buscar Grupo de Passos')
    }
  }

  const createGrupoPassos = async (params) => {
    const apiClient = setupAPIClient(undefined);
    try {
      const response = await apiClient.post('/api/grupopassos', {
        params: {
          ...params
        }
      })
      const { grupopassos, totalRecords } = response.data
      return {
        data: {
          grupopassos,
          totalRecords
        }
      }
    } catch (err) {
      throw new Error('Erro ao criar Grupo de Passos')
    }
  }


  const deleteGrupoPassos = async (params) => {
    const apiClient = setupAPIClient(undefined);
    try {
      const response = await apiClient.put('/api/deletegrupopasso', {
        params: {
          ...params
        }
      })

      const { grupopassos, totalRecords } = response.data
      return {
        data: {
          grupopassos,
          totalRecords,
        }
      }
    } catch (err) {
      throw new Error('Erro ao deletar Grupo de Passos', err)
    }
  }

  const updateGrupoPassos = async (params) => {
    const apiClient = setupAPIClient(undefined);
    try {
      const response = await apiClient.put('/api/grupopasso', {
        params: {
          ...params
        }
      })
      const { grupopassos, totalRecords } = response.data
      return {
        data: {
          grupopassos,
          totalRecords,
        }
      }
    } catch (err) {
      throw new Error('Erro ao atualizar Grupo de Passos')
    }
  }

  return {
    getGrupoPassos,
    createGrupoPassos,
    deleteGrupoPassos,
    updateGrupoPassos
  }

}