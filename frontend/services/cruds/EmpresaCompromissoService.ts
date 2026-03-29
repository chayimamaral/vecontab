import setupAPIClient from '../../components/api/api';

function normalizeAcompanhamentoItem(raw: Record<string, unknown>) {
  const s = (k: string, ...alts: string[]) => {
    const v = raw[k] ?? alts.map((a) => raw[a]).find((x) => x != null);
    return v == null ? '' : String(v);
  };
  const n = (k: string, ...alts: string[]) => {
    const v = raw[k] ?? alts.map((a) => raw[a]).find((x) => x != null);
    if (v == null || v === '') {
      return null;
    }
    const num = Number(v);
    return Number.isFinite(num) ? num : null;
  };
  return {
    empresa_id: s('empresa_id', 'empresaId'),
    empresa_nome: s('empresa_nome', 'empresaNome'),
    compromisso_id: s('compromisso_id', 'compromissoId'),
    descricao: s('descricao'),
    data_vencimento: s('data_vencimento', 'dataVencimento'),
    status: s('status'),
    tipo: s('tipo'),
    classificacao: s('classificacao'),
    agenda_item_id: s('agenda_item_id', 'agendaItemId'),
    valor_estimado: n('valor_estimado', 'valorEstimado'),
  };
}

type GerarParams = {
  empresa_id: string;
  data_inicio: string;
};

type UpdateStatusParams = {
  id: string;
  status: string;
};

type UpdateItemParams = {
  id: string;
  data_vencimento?: string;
  valor?: number;
};

export default function EmpresaCompromissoService() {
  return {
    getAcompanhamento: async () => {
      const apiClient = setupAPIClient(undefined);
      const response = await apiClient.get('/api/empresacompromissos/acompanhamento');
      const payload = response?.data;
      const rawItens =
        payload != null &&
        typeof payload === 'object' &&
        Array.isArray((payload as { itens?: unknown }).itens)
          ? (payload as { itens: unknown[] }).itens
          : [];
      const itens = rawItens
        .filter((x): x is Record<string, unknown> => x != null && typeof x === 'object')
        .map(normalizeAcompanhamentoItem);
      return { data: { itens } };
    },

    gerar: async (params: GerarParams) => {
      const apiClient = setupAPIClient(undefined);
      const response = await apiClient.post('/api/empresacompromissos/gerar', { params });
      return { data: response.data };
    },

    updateStatus: async (params: UpdateStatusParams) => {
      const apiClient = setupAPIClient(undefined);
      const response = await apiClient.put('/api/empresacompromissos/status', { params });
      return { data: response.data };
    },

    updateItem: async (params: UpdateItemParams) => {
      const apiClient = setupAPIClient(undefined);
      const response = await apiClient.put('/api/empresacompromissos/item', { params });
      return { data: response.data };
    },
  };
}
