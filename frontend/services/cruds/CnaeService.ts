import setupAPIClient from '../../components/api/api';

export default function CnaeService() {

  const getCnaes = async (params) => {
    // do jeito que receber o params, ele vem como string, entao tem que converter para objeto
    //console.log('params.lazyEvent', params.lazyEvent.toString())
    const apiClient = setupAPIClient(undefined);
    // ao passar o params, ele vem como string, entao tem que converter para objeto com JSON.parse

    try {
      const response = await apiClient.get('/api/cnaes', {
        params: JSON.parse(params.lazyEvent),
      })
      // não precisa converter para objeto, pois o axios já faz isso
      const { cnaes, totalRecords } = response.data
      return {
        data: {
          cnaes,
          totalRecords
        }
      }
    } catch (err) {
      throw new Error('Erro ao buscar CNAEs')
    }
  }

  const createCnae = async (params) => {
    const apiClient = setupAPIClient(undefined);
    try {
      const response = await apiClient.post('/api/cnae', {
        params: {
          ...params
        }
      })
      const { cnaes, totalRecords } = response.data
      return {
        data: {
          cnaes,
          totalRecords
        }
      }
    } catch (err) {
      throw new Error('Erro ao incluir CNAE')
    }
  }


  const deleteCnae = async (params) => {
    const apiClient = setupAPIClient(undefined);
    try {
      const response = await apiClient.put('/api/deletecnae', {
        params: {
          ...params
        }
      })

      const { cnaes, totalRecords } = response.data
      return {
        data: {
          cnaes,
          totalRecords,
        }
      }
    } catch (err) {
      throw new Error('Erro ao deletar CNAE', err)
    }
  }

  const updateCnae = async (params) => {
    const apiClient = setupAPIClient(undefined);
    try {
      const response = await apiClient.put('/api/cnae', {
        params: {
          ...params
        }
      })
      const { cnaes, totalRecords } = response.data
      return {
        data: {
          cnaes,
          totalRecords,
        }
      }
    } catch (err) {
      throw new Error('Erro ao atualizar CNAE')
    }
  }

  const getCnaeLite = async () => {
    const apiClient = setupAPIClient(undefined);
    try {
      const response = await apiClient.get('/api/cnaelite')
      const { cnaes } = response.data
      return {
        data: {
          cnaes
        }
      }
    } catch (err) {
      throw new Error('Erro ao buscar CNAE')
    }
  }

  return {
    getCnaes,
    createCnae,
    deleteCnae,
    updateCnae,
    getCnaeLite
  }

}