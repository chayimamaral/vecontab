import setupAPIClient from '../../components/api/api';

export default function EstadoService() {

    return {

        getEstados: async (params) => {
            // do jeito que receber o params, ele vem como string, entao tem que converter para objeto
            try {
                const apiClient = setupAPIClient(undefined);
                // ao passar o params, ele vem como string, entao tem que converter para objeto com JSON.parse
                const response = await apiClient.get('/api/estados', {
                    params: JSON.parse(params.lazyEvent),
                });
                // não precisa converter para objeto, pois o axios já faz isso
                const { estados, totalRecords } = response.data

                return {
                    data: {
                        estados,
                        totalRecords
                    }
                }
            } catch (err) {
                throw new Error('Erro ao buscar estados')

            }
        },

        createEstado: async (params) => {
            try {
                const apiClient = setupAPIClient(undefined);

                const create = await apiClient.post('/api/estado', {
                    params: {
                        ...params
                    }
                })

                const response = await this.getEstados(params)

                const { estados, totalRecords } = response.data

                return {
                    data: {
                        estados,
                        totalRecords
                    }
                }

            } catch (err) {
                return {
                    redirect: {
                        destination: '/estados',
                        permanent: false

                    }
                }
            }
        },

        updateEstado: async (params) => {
            try {
                const apiClient = setupAPIClient(undefined);

                const update = await apiClient.put('/api/estado', {
                    params: {
                        ...params
                    }

                })

                const response = await this.getEstados(params)
                const { estados, totalRecords } = response.data

                return {
                    data: {
                        estados,
                        totalRecords,
                    }
                }
            } catch (err) {
                return {
                    redirect: {
                        destination: '/estados',
                        permanent: false

                    }
                }
            }
        },

        deleteEstado: async (params) => {
            try {
                const apiClient = setupAPIClient(undefined);
                const response = await apiClient.put('/api/deleteestado', {
                    params: {
                        ...params
                    }
                })

                const { estados, totalRecords } = response.data

                return {
                    data: {
                        estados,
                        totalRecords,
                    }
                }
            } catch (err) {
                throw new Error('Erro ao deletar estado')
            }
        },

        getUFCidade: async () => {
            try {
                const apiClient = setupAPIClient(undefined);
                const response = await apiClient.get('/api/ufscidade')

                const { estados, totalRecords } = response.data

                return {
                    data: {
                        estados
                    }
                }
            } catch (err) {
                return {
                    redirect: {
                        destination: '/municipios',
                        permanent: false

                    }
                }
            }
        }

        //     return {
        //         getEstados,
        //         createEstado,
        //         updateEstado,
        //         deleteEstado,
        //         getUFCidade
        //     }
    }
}


