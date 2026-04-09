import setupAPIClient from '../../components/api/api';

export default function EmpresaDadosService() {
  const getByEmpresa = async (empresaId: string) => {
    const apiClient = setupAPIClient(undefined);
    const response = await apiClient.get('/api/empresadados', {
      params: { empresa_id: empresaId },
    });
    return { data: response.data };
  };

  const save = async (params: {
    id: string;
    municipio_id?: string;
    bairro?: string;
    cnpj?: string;
    capital_social?: number | null;
    endereco?: string;
    numero?: string;
    cep?: string;
    email_contato?: string;
    telefone?: string;
    telefone2?: string;
    data_abertura?: string;
    data_encerramento?: string;
    observacao?: string;
  }) => {
    const apiClient = setupAPIClient(undefined);
    const response = await apiClient.put('/api/empresadados', {
      params: {
        ...params,
      },
    });
    return { data: response.data };
  };

  return { getByEmpresa, save };
}
