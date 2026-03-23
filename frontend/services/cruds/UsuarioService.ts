import setupAPIClient from '../../components/api/api';
import { AxiosError } from 'axios';
import { AxiosError } from 'axios';

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
          nome: params.nome,
          email: params.email,
          password: params.password,
          role: params.role,
          tenantId: params.tenantId || params.tenantid,
        })
        const { usuarios, totalRecords } = response.data
        return {
          data: {
            usuarios,
            totalRecords
          }
        }
      } catch (err) {
        const axiosErr = err as AxiosError<{ error?: string; message?: string }>;
        const message =
          axiosErr.response?.data?.error ||
          axiosErr.response?.data?.message ||
          axiosErr.message ||
          'Erro ao criar Usuário';
        throw new Error(message)
      }
    },

    updateUsuario: async (params) => {
      const apiClient = setupAPIClient(undefined);
      try {
        const response = await apiClient.put('/api/usuario', {
          id: params.id,
          nome: params.nome,
          email: params.email,
          role: params.role,
          tenantId: params.tenantId || params.tenantid,
        })
        const { usuarios, totalRecords } = response.data
        return {
          data: {
            usuarios,
            totalRecords,
          }
        }
      } catch (err) {
        const axiosErr = err as AxiosError<{ error?: string; message?: string }>;
        const message =
          axiosErr.response?.data?.error ||
          axiosErr.response?.data?.message ||
          axiosErr.message ||
          'Erro ao atualizar Usuário';
        throw new Error(message)
      }
    },

    deleteUsuario: async (params) => {
      const apiClient = setupAPIClient(undefined);
      try {
        const response = await apiClient.delete('/api/usuario', { params: { id: params.id } })

        const { usuarios, totalRecords } = response.data
        return {
          data: {
            usuarios,
            totalRecords,
          }
        }
      } catch (err) {
        const axiosErr = err as AxiosError<{ error?: string; message?: string }>;
        const message =
          axiosErr.response?.data?.error ||
          axiosErr.response?.data?.message ||
          axiosErr.message ||
          'Erro ao deletar Usuário';
        throw new Error(message)
      }
    }
  }
}