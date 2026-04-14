import setupAPIClient from '../../components/api/api';

export default function EmpresaService() {

  const getEmpresa = async (params: { lazyEvent: string }) => {

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

  const getEmpresas = async (params: { lazyEvent: string }) => {

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

  const deleteEmpresa = async (params: Record<string, unknown>) => {
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

  const updateEmpresa = async (params: Record<string, any>) => {
    const apiClient = setupAPIClient(undefined);
    const tipo =
      String(params?.tipo_pessoa ?? 'PJ')
        .trim()
        .toUpperCase() === 'PF'
        ? 'PF'
        : 'PJ';

    const response = await apiClient.put('/api/updateempresa', {
      params: {
        ...params,
        tipo_pessoa: tipo,
        documento: params?.documento ?? '',
        ie: params?.ie ?? '',
        im: params?.im ?? '',
        regime_tributario: params?.regime_tributario ?? { id: '' },
        tipo_empresa: params?.tipo_empresa ?? { id: '' },
        rotina: params?.rotina ?? { id: '' },
        rotina_pf: params?.rotina_pf ?? { id: '' },
        municipio: { id: params?.municipio?.id ?? '' },
      },
    });

    const { empresas, totalRecords } = response.data;

    return {
      data: {
        empresas,
        totalRecords,
      },
    };
  };

  const iniciarProcesso = async (params: Record<string, unknown>) => {

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

  const createEmpresa = async (params: Record<string, any>) => {
    const apiClient = setupAPIClient(undefined);
    const tipo =
      String(params?.tipo_pessoa ?? 'PJ')
        .trim()
        .toUpperCase() === 'PF'
        ? 'PF'
        : 'PJ';

    const response = await apiClient.post('/api/empresa', {
      params: {
        ...params,
        tipo_pessoa: tipo,
        documento: params?.documento ?? '',
        ie: params?.ie ?? '',
        im: params?.im ?? '',
        regime_tributario: params?.regime_tributario ?? { id: '' },
        tipo_empresa: params?.tipo_empresa ?? { id: '' },
        rotina: params?.rotina ?? { id: '' },
        rotina_pf: params?.rotina_pf ?? { id: '' },
        municipio: { id: params?.municipio?.id ?? '' },
      },
    });

    const { empresas, totalRecords } = response.data;

    return {
      data: {
        empresas,
        totalRecords,
      },
    };
  };

  const validaCnae = async (params: string) => {
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

  const getEmpresaProcessos = async (params?: { empresa_id?: string }) => {
    const apiClient = setupAPIClient(undefined);
    const response = await apiClient.get('/api/empresa-processos', {
      params: {
        empresa_id: params?.empresa_id ?? '',
      },
    });
    const { processos, totalRecords } = response.data;
    return { data: { processos, totalRecords } };
  };

  const createEmpresaProcesso = async (params: {
    empresa_id: string;
    rotina?: { id?: string };
    descricao: string;
  }) => {
    const apiClient = setupAPIClient(undefined);
    const response = await apiClient.post('/api/empresa-processo', {
      params: {
        empresa_id: params.empresa_id,
        rotina: params.rotina ?? { id: '' },
        descricao: params.descricao,
      },
    });
    const { processos, totalRecords } = response.data;
    return { data: { processos, totalRecords } };
  };

  const iniciarEmpresaProcesso = async (params: { processo_id: string; empresa_id: string }) => {
    const apiClient = setupAPIClient(undefined);
    const response = await apiClient.put('/api/empresa-processo/iniciar', {
      params,
    });
    const { processos, totalRecords } = response.data;
    return { data: { processos, totalRecords } };
  };

  const marcarCompromissosEmpresaProcesso = async (params: { processo_id: string }) => {
    const apiClient = setupAPIClient(undefined);
    const response = await apiClient.put('/api/empresa-processo/compromissos', {
      params,
    });
    const { processos, totalRecords } = response.data;
    return { data: { processos, totalRecords } };
  };


  return {
    getEmpresa,
    getEmpresas,
    deleteEmpresa,
    updateEmpresa,
    createEmpresa,
    iniciarProcesso,
    validaCnae,
    getEmpresaProcessos,
    createEmpresaProcesso,
    iniciarEmpresaProcesso,
    marcarCompromissosEmpresaProcesso,
  }
}



