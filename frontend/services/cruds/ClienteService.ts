import setupAPIClient from '../../components/api/api';

export interface ClienteRow {
  id: string;
  tenant_id: string;
  tipoPessoa: string;
  nome: string;
  documento: string;
  municipioId?: string;
  rotinaId?: string;
  cnaes?: unknown;
  bairro?: string;
  iniciado: boolean;
  ativo: boolean;
}

export default function ClienteService() {
  const list = async (limit = 500, offset = 0) => {
    const api = setupAPIClient(undefined);
    const response = await api.get<{ clientes: ClienteRow[] }>('/api/clientes', {
      params: { limit, offset },
    });
    return response.data?.clientes ?? [];
  };

  return { list };
}
