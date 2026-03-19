import setupAPIClient from '../../components/api/api';

export default function EmpresaService() {

  const getEmpresa = async (params) => {

    // do jeito que receber o params, ele vem como string, entao tem que converter para objeto

    const apiClient = setupAPIClient(undefined);

    // ao passar o params, ele vem como string, entao tem que converter para objeto com JSON.parse
    const response = await apiClient.get('/api/empresas', {
      params: JSON.parse(params.lazyEvent),
    });

    // não precisa converter para objeto, pois o axios já faz isso
    const { empresas, totalRecords } = response.data

    return {
      data: {
        empresas,
        totalRecords
      }
    }
  }

  const getEmpresas = async (params) => {

    // do jeito que receber o params, ele vem como string, entao tem que converter para objeto
    const apiClient = setupAPIClient(undefined);

    // ao passar o params, ele vem como string, entao tem que converter para objeto com JSON.parse
    const response = await apiClient.get('/api/empresas', {
      params: JSON.parse(params.lazyEvent),
    });

    // não precisa converter para objeto, pois o axios já faz isso
    const { empresas, totalRecords } = response.data

    return {
      data: {
        empresas,
        totalRecords
      }
    }
  }

  const deleteEmpresa = async (params) => {
    try {
      const apiClient = setupAPIClient(undefined);
      const response = await apiClient.put('/api/deleteempresa', {
        params: {
          ...params
        }

      })

      const { empresas, totalRecords } = response.data

      return {
        props: {
          empresas,
          totalRecords,
        }
      }
    } catch (err) {
      return {
        redirect: {
          destination: '/empresas',
          permanent: false

        }
      }
    }
  }

  const updateEmpresa = async (params) => {

    try {
      const apiClient = setupAPIClient(undefined);

      const response = await apiClient.put('/api/updateempresa', {
        params:
        {
          ...params
        }
      })

      const { empresas, totalRecords } = response.data

      return {
        data: {
          empresas,
          totalRecords,
        }
      }
    } catch (err) {
      return {
        redirect: {
          destination: '/empresas',
          permanent: false

        }
      }
    }
  }

  const iniciarProcesso = async (params) => {

    //esta função tornará 'iniciado = true' e, neste momento, internamente no BD
    //será disparado um trigger que acionará uma função para geração da agenda
    //de obrigações da empresa, incluindo os passos e calculando a data para
    //cada passo, de acordo com a data de início do processo, a saber, hoje (ou data atual).
    //após o início do processo, a única operação permitida será cancelar a
    //abertura da empresa e não será mais permitido alterar os dados da empresa.

    try {
      const apiClient = setupAPIClient(undefined);

      const response = await apiClient.put('/api/iniciarprocesso', {
        params:
        {
          ...params
        }
      })

      const { empresas, totalRecords } = response.data

      return {
        data: {
          empresas,
          totalRecords,
        }
      }
    } catch (err) {
      return {
        redirect: {
          destination: '/empresas',
          permanent: false

        }
      }
    }
  }

  const createEmpresa = async (params) => {
    try {
      const apiClient = setupAPIClient(undefined);

      const response = await apiClient.post('/api/empresa', {
        params: {
          ...params
        }
      })

      const { empresas, totalRecords } = response.data

      return {
        data: {
          empresas,
          totalRecords
        }
      }

    } catch (err) {
      return {
        redirect: {
          destination: '/empresas',
          permanent: false

        }
      }
    }
  }

  const validaCnae = async (params) => {
    const cnae = `${params.slice(0, 2)}.${params.slice(2, 4)}-${params.slice(4, 5)}/${params.slice(5)}`;
    try {
      const apiClient = setupAPIClient(undefined);

      const response = await apiClient.post('/api/validacnae', {
        cnae: cnae
      })


      const cnaeValido = response.data.valid

      return {
        data: {
          cnaeValido
        }
      }

    } catch (err) {

      throw new Error("Erro ao validar CNAE")

    }
  }


  return {
    getEmpresa,
    getEmpresas,
    deleteEmpresa,
    updateEmpresa,
    createEmpresa,
    iniciarProcesso,
    validaCnae
  }
}



