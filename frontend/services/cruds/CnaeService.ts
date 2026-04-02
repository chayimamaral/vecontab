import setupAPIClient from '../../components/api/api';

export default function CnaeService() {

  const getCnaes = async (params) => {
    const apiClient = setupAPIClient(undefined);
    const lazy = typeof params.lazyEvent === 'string' ? JSON.parse(params.lazyEvent) : params.lazyEvent;

    try {
      const response = await apiClient.get('/api/cnaes', {
        params: {
          first: lazy.first ?? 0,
          rows: lazy.rows ?? 25,
          sortField: lazy.sortField ?? '',
          sortOrder: lazy.sortOrder ?? 1,
          filters: typeof lazy.filters === 'string' ? lazy.filters : JSON.stringify(lazy.filters ?? {}),
        },
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

  /** Resolve hierarquia + denominação pelo catálogo IBGE (tabelas ibge_cnae_* no backend). */
  const resolveCnae = async (subclasse7: string) => {
    const apiClient = setupAPIClient(undefined);
    const response = await apiClient.get('/api/cnaeresolve', {
      params: { subclasse: subclasse7.replace(/\D/g, '') },
    });
    return { data: response.data };
  };

  return {
    getCnaes,
    createCnae,
    deleteCnae,
    updateCnae,
    getCnaeLite,
    resolveCnae,
  }

}