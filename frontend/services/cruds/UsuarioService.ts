import setupAPIClient from '../../components/api/api';

export default function UsuarioService() {

  return {

    getUsuarios: async (params) => {
      // do jeito que receber o params, ele vem como string, entao tem que converter para objeto
      const apiClient = setupAPIClient(undefined);
      // ao passar o params, ele vem como string, entao tem que converter para objeto com JSON.parse

      try {
        const response = await apiClient.get('/api/usuarios', {
          params: JSON.parse(params.lazyEvent),
        })
        // não precisa converter para objeto, pois o axios já faz isso
        const { usuarios, totalRecords } = response.data
        return {
          data: {
            usuarios,
            totalRecords
          }
        }
      } catch (err) {
        throw new Error('Erro ao buscar Usuarios')
      }
    },

    getUserRole: async (params) => {
      const apiClient = setupAPIClient(undefined);
      try {
        const response = await apiClient.get('/api/usuariorole', {
          params: {
            ...params
          }
        })
        const { logado } = response.data
        return {
          data: { logado }


        }
      } catch (err) {
        throw new Error('Erro ao buscar Usuarios')
      }
    },

    getTenantId: async (params) => {
      const apiClient = setupAPIClient(undefined);
      try {
        const response = await apiClient.get('/api/usuariotenant', {
          params: {
            ...params
          }
        })
        const { tenantid } = response.data
        return {
          data: tenantid
        }
      } catch (err) {
        throw new Error('Erro ao buscar Tenant')
      }
    },


    createUsuario: async (params) => {
      const apiClient = setupAPIClient(undefined);
      try {
        const response = await apiClient.post('/api/usuario', {
          params: {
            ...params
          }
        })
        const { usuarios, totalRecords } = response.data
        return {
          data: {
            usuarios,
            totalRecords
          }
        }
      } catch (err) {
        throw new Error('Erro ao criar Usuário')
      }
    },

    updateUsuario: async (params) => {
      const apiClient = setupAPIClient(undefined);
      try {
        const response = await apiClient.put('/api/usuario', {
          params: {
            ...params
          }
        })
        const { usuarios, totalRecords } = response.data
        return {
          data: {
            usuarios,
            totalRecords,
          }
        }
      } catch (err) {
        throw new Error('Erro ao atualizar Tipo de Empresa')
      }
    },

    deleteUsuario: async (params) => {
      const apiClient = setupAPIClient(undefined);
      try {
        const response = await apiClient.put('/api/usuario', {
          params: {
            ...params
          }
        })

        const { usuarios, totalRecords } = response.data
        return {
          data: {
            usuarios,
            totalRecords,
          }
        }
      } catch (err) {
        throw new Error('Erro ao deletar Tipo de Empresa', err)
      }
    }
  }
}