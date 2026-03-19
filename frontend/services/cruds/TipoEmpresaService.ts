import setupAPIClient from '../../components/api/api';

export default function TipoEmpresaService() {

  const getTiposEmpresa = async (params) => {
    // do jeito que receber o params, ele vem como string, entao tem que converter para objeto
    //console.log('params.lazyEvent', params.lazyEvent.toString())
    const apiClient = setupAPIClient(undefined);
    // ao passar o params, ele vem como string, entao tem que converter para objeto com JSON.parse

    try {
      const response = await apiClient.get('/api/tiposempresa', {
        params: JSON.parse(params.lazyEvent),
      })
      // não precisa converter para objeto, pois o axios já faz isso
      const { tiposEmpresa, totalRecords } = response.data
      return {
        data: {
          tiposEmpresa,
          totalRecords
        }
      }
    } catch (err) {
      throw new Error('Erro ao buscar Tipos de Empresa')
    }
  }

  const createTipoEmpresa = async (params) => {
    const apiClient = setupAPIClient(undefined);
    try {
      const response = await apiClient.post('/api/tipoempresa', {
        params: {
          ...params
        }
      })
      const { tiposEmpresa, totalRecords } = response.data
      return {
        data: {
          tiposEmpresa,
          totalRecords
        }
      }
    } catch (err) {
      throw new Error('Erro ao criar Tipo de Empresa')
    }
  }


  const deleteTipoEmpresa = async (params) => {
    const apiClient = setupAPIClient(undefined);
    try {
      const response = await apiClient.put('/api/deletetipoempresa', {
        params: {
          ...params
        }
      })

      const { tiposEmpresa, totalRecords } = response.data
      return {
        data: {
          tiposEmpresa,
          totalRecords,
        }
      }
    } catch (err) {
      throw new Error('Erro ao deletar Tipo de Empresa', err)
    }
  }

  const updateTipoEmpresa = async (params) => {
    const apiClient = setupAPIClient(undefined);
    try {
      const response = await apiClient.put('/api/tipoempresa', {
        params: {
          ...params
        }
      })
      const { tiposEmpresa, totalRecords } = response.data
      return {
        data: {
          tiposEmpresa,
          totalRecords,
        }
      }
    } catch (err) {
      throw new Error('Erro ao atualizar Tipo de Empresa')
    }
  }

  const getTiposEmpresaLite = async () => {
    const apiClient = setupAPIClient(undefined);
    try {
      const response = await apiClient.get('/api/tiposempresalite')
      const { tiposEmpresa } = response.data
      return {
        data: {
          tiposEmpresa
        }
      }
    } catch (err) {
      throw new Error('Erro ao buscar Tipos de Empresa')
    }
  }

  return {
    getTiposEmpresa,
    createTipoEmpresa,
    deleteTipoEmpresa,
    updateTipoEmpresa,
    getTiposEmpresaLite
  }

}