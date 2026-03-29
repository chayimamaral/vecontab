import setupAPIClient from '../../components/api/api';

export default function RotinaService() {

    const getRotina = async (params) => {

        // do jeito que receber o params, ele vem como string, entao tem que converter para objeto

        const apiClient = setupAPIClient(undefined);

        // ao passar o params, ele vem como string, entao tem que converter para objeto com JSON.parse
        const response = await apiClient.get('/api/rotina', {
            params: JSON.parse(params.lazyEvent),
        });

        // não precisa converter para objeto, pois o axios já faz isso
        const { rotinas, totalRecords } = response.data

        return {
            data: {
                rotinas,
                totalRecords
            }
        }
    }

    const getRotinas = async (params) => {

        // do jeito que receber o params, ele vem como string, entao tem que converter para objeto

        const apiClient = setupAPIClient(undefined);

        // ao passar o params, ele vem como string, entao tem que converter para objeto com JSON.parse
        const response = await apiClient.get('/api/listrotinas', {
            params: JSON.parse(params.lazyEvent),
        });

        // não precisa converter para objeto, pois o axios já faz isso
        const { rotinas, totalRecords } = response.data

        return {
            data: {
                rotinas,
                totalRecords
            }
        }
    }

    /** Backend: GET /api/listrotinaslite? id = UUID do município. */
    const getRotinasLite = async (municipioRef?: { id?: string } | null) => {
        const apiClient = setupAPIClient(undefined);
        const id = municipioRef && typeof municipioRef === 'object' ? String(municipioRef.id ?? '').trim() : '';
        const response = await apiClient.get('/api/listrotinaslite', {
            params: { id },
        });

        const { rotinas, totalRecords } = response.data;

        return {
            data: {
                rotinas: Array.isArray(rotinas) ? rotinas : [],
                totalRecords,
            },
        };
    };

    const deleteRotina = async (params) => {
        try {
            const apiClient = setupAPIClient(undefined);
            const response = await apiClient.put('/api/deleterotina', {
                params: {
                    ...params
                }

            })

            const { rotinas, totalRecords } = response.data

            return {
                props: {
                    rotinas,
                    totalRecords,
                }
            }
        } catch (err) {
            return {
                redirect: {
                    destination: '/rotinas',
                    permanent: false

                }
            }
        }
    }


    const updateRotina = async (params) => {
        try {
            const apiClient = setupAPIClient(undefined);

            const response = await apiClient.put('/api/rotina', {
                params: {
                    ...params
                }

            })

            const { rotinas, totalRecords } = response.data

            return {
                data: {
                    rotinas,
                    totalRecords,
                }
            }
        } catch (err) {
            return {
                redirect: {
                    destination: '/rotinas',
                    permanent: false

                }
            }
        }
    }

    const createRotina = async (params) => {
        try {
            const apiClient = setupAPIClient(undefined);

            const response = await apiClient.post('/api/rotina', {
                params: {
                    ...params
                }
            })

            const { rotinas, totalRecords } = response.data

            return {
                data: {
                    rotinas,
                    totalRecords
                }
            }

        } catch (err) {
            return {
                redirect: {
                    destination: '/rotinas',
                    permanent: false

                }
            }
        }
    }

    const getRotinaPassosSelecionados = async (params) => {

        // do jeito que receber o params, ele vem como string, entao tem que converter para objeto

        const apiClient = setupAPIClient(undefined);

        // ao passar o params, ele vem como string, entao tem que converter para objeto com JSON.parse
        const response = await apiClient.get('/api/listrotinaitensselected', {
            params: {
                ...params
            },
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

    const salvarPassosSelecionados = async (params) => {

        try {
            const apiClient = setupAPIClient(undefined);

            const response = await apiClient.put('/api/salvarselecao', {
                params: {
                    ...params
                }
            })

            //const { rotinas, totalRecords } = response.data

            // return {
            //     data: {
            //         rotinas,
            //         totalRecords
            //     }
            // }
            return
        } catch (err) {
            return {
                redirect: {
                    destination: '/salvarpassosselecionados',
                    permanent: false

                }
            }
        }
    }

    const removerPassoSelecionado = async (params) => {
        try {
            const apiClient = setupAPIClient(undefined);

            const response = await apiClient.put('/api/removepassoselecionado', {
                params: {
                    ...params
                }
            })

            return
        } catch (err) {
            return {
                redirect: {
                    destination: '/salvarpassosselecionados',
                    permanent: false

                }
            }
        }
    }

    return {
        getRotina,
        getRotinas,
        deleteRotina,
        updateRotina,
        createRotina,
        getRotinaPassosSelecionados,
        salvarPassosSelecionados,
        removerPassoSelecionado,
        getRotinasLite
    }
}



