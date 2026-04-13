import setupAPIClient from '../../components/api/api';

export default function RegimeTributarioService() {
  const getRegimes = async (params: { lazyEvent: string }) => {
    const apiClient = setupAPIClient(undefined);
    const lazy = typeof params.lazyEvent === 'string' ? JSON.parse(params.lazyEvent) : params.lazyEvent;
    const response = await apiClient.get('/api/regimes-tributarios', {
      params: {
        first: lazy.first ?? 0,
        rows: lazy.rows ?? 25,
        sortField: lazy.sortField ?? 'nome',
        sortOrder: lazy.sortOrder ?? 1,
        filters: typeof lazy.filters === 'string' ? lazy.filters : JSON.stringify(lazy.filters ?? {}),
      },
    });
    const { regimes, totalRecords } = response.data;
    return { data: { regimes, totalRecords } };
  };

  const createRegime = async (params: Record<string, unknown>) => {
    const apiClient = setupAPIClient(undefined);
    const response = await apiClient.post('/api/regime-tributario', { params });
    const { regimes, totalRecords } = response.data;
    return { data: { regimes, totalRecords } };
  };

  const updateRegime = async (params: Record<string, unknown>) => {
    const apiClient = setupAPIClient(undefined);
    const response = await apiClient.put('/api/regime-tributario', { params });
    const { regimes, totalRecords } = response.data;
    return { data: { regimes, totalRecords } };
  };

  const deleteRegime = async (params: { id: string }) => {
    const apiClient = setupAPIClient(undefined);
    const response = await apiClient.delete('/api/regime-tributario', { params });
    const { regimes, totalRecords } = response.data;
    return { data: { regimes, totalRecords } };
  };

  return { getRegimes, createRegime, updateRegime, deleteRegime };
}
