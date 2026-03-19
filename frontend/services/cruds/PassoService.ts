import setupAPIClient from '../../components/api/api';

export default function PassoService() {

    const getPasso = async (params) => {

        // do jeito que receber o params, ele vem como string, entao tem que converter para objeto

        const apiClient = setupAPIClient(undefined);

        // ao passar o params, ele vem como string, entao tem que converter para objeto com JSON.parse
        const response = await apiClient.get('/api/passo', {
            params: JSON.parse(params.lazyEvent),
        });

        // não precisa converter para objeto, pois o axios já faz isso
        const { passos, totalRecords } = response.data

        return {
            data: {
                passos,
                totalRecords
            }
        }
    }


    const getPassos = async (params) => {

        // do jeito que receber o params, ele vem como string, entao tem que converter para objeto

        const apiClient = setupAPIClient(undefined);

        // ao passar o params, ele vem como string, entao tem que converter para objeto com JSON.parse
        const response = await apiClient.get('/api/passos', {
            params: JSON.parse(params.lazyEvent),
        });

        // não precisa converter para objeto, pois o axios já faz isso
        const { passos, totalRecords } = response.data

        return {
            data: {
                passos,
                totalRecords
            }
        }
    }

    const deletePasso = async (params) => {
        try {
            const apiClient = setupAPIClient(undefined);
            const response = await apiClient.put('/api/deletepasso', {
                params: {
                    ...params
                }

            })

            const { passos, totalRecords } = response.data

            return {
                props: {
                    passos,
                    totalRecords,
                }
            }
        } catch (err) {
            return {
                redirect: {
                    destination: '/passos',
                    permanent: false

                }
            }
        }
    }


    const updatePasso = async (deletarItem) => {
        try {
            const apiClient = setupAPIClient(undefined);

            const response = await apiClient.put('/api/passo', {
                params: {
                    deletarItem
                }

            })

            const { passos, totalRecords } = response.data

            return {
                data: {
                    passos,
                    totalRecords,
                }
            }
        } catch (err) {
            return {
                redirect: {
                    destination: '/passos',
                    permanent: false

                }
            }
        }
    }

    const createPasso = async (params) => {
        try {
            const apiClient = setupAPIClient(undefined);

            const response = await apiClient.post('/api/passo', {
                params: {
                    ...params
                }
            })

            //console.log(response.data)

            const { passos, totalRecords } = response.data

            //console.log(passos)

            return {
                data: {
                    passos,
                    totalRecords
                }
            }

        } catch (err) {
            return {
                redirect: {
                    destination: '/passos',
                    permanent: false

                }
            }
        }
    }

    const getPassosPorCidade = async (params) => {

        // do jeito que receber o params, ele vem como string, entao tem que converter para objeto

        const apiClient = setupAPIClient(undefined);

        // ao passar o params, ele vem como string, entao tem que converter para objeto com JSON.parse
        const response = await apiClient.get('/api/passosporcidade', {
            params: {
                ...params
            }
        });

        // não precisa converter para objeto, pois o axios já faz isso
        const { passos, totalRecords } = response.data

        return {
            data: {
                passos,
                totalRecords
            }
        }
    }

    return {
        getPasso,
        getPassos,
        deletePasso,
        updatePasso,
        createPasso,
        getPassosPorCidade
    }
}



