import React, { useMemo, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { GetServerSidePropsContext } from 'next';
import { classNames } from 'primereact/utils';
import { withAuthServerSideProps } from '../../components/utils/crudUtils';
import { DataTable, DataTableFilterMeta, DataTableStateEvent } from 'primereact/datatable';
import { PaginatorTemplate } from 'primereact/paginator';
import ObrigacaoLegaisService from '../../services/cruds/ObrigacaoLegaisService';
import MunicipioService from '../../services/cruds/MunicipioService';
import EstadoService from '../../services/cruds/EstadoService';
import TipoEmpresaService from '../../services/cruds/TipoEmpresaService';
import CatalogoServicoService, { CatalogoServico } from '../../services/cruds/CatalogoServicoService';
import { Toast } from 'primereact/toast';
import { Button } from 'primereact/button';
import { Dropdown } from 'primereact/dropdown';
import { InputText } from 'primereact/inputtext';
import { InputNumber } from 'primereact/inputnumber';
import { InputTextarea } from 'primereact/inputtextarea';
import { Toolbar } from 'primereact/toolbar';
import { Column } from 'primereact/column';
import { Dialog } from 'primereact/dialog';

interface AbrangenciaOpcao {
  name: string;
  code: string;
}

interface GeoRef {
  id: string;
  nome: string;
}

interface TipoEmpresaRef {
  id: string;
  descricao: string;
}

interface ObrigacaoLegais {
  id?: string;
  tipo_empresa_id?: string;
  tipoempresa?: GeoRef;
  descricao?: string;
  periodicidade?: string;
  abrangencia?: string;
  dia_base?: number;
  mes_base?: string;
  tipo_classificacao?: string;
  valor?: number;
  observacao?: string;
  estado?: GeoRef;
  municipio?: GeoRef;
  bairro?: string;
  catalogo_servico_ids?: string[];
  servicos_serpro?: { catalogo_servico_id: string; descricao?: string; codigo?: string }[];
}

interface LazyTableState {
  first: number;
  rows: number;
  page: number;
  sortField?: string;
  sortOrder?: number | null;
  filters: DataTableFilterMeta;
  abrangencia: AbrangenciaOpcao;
  tipo_empresa_id?: string;
  tipo_classificacao?: string;
  periodicidade?: string;
  localizacao?: string;
}

interface PageEvent {
  first: number;
  rows: number;
  page: number;
}

interface PageInputOptions {
  first: number;
  rows: number;
  totalPages: number;
}

const abrangencias: AbrangenciaOpcao[] = [
  { name: 'Todos', code: 'TODOS' },
  { name: 'Federal', code: 'FEDERAL' },
  { name: 'Estadual', code: 'ESTADUAL' },
  { name: 'Municipal', code: 'MUNICIPAL' },
  { name: 'Bairro', code: 'BAIRRO' },
];

const periodicidades: AbrangenciaOpcao[] = [
  { name: 'Mensal', code: 'MENSAL' },
  { name: 'Anual', code: 'ANUAL' },
];

const tiposClassificacao: AbrangenciaOpcao[] = [
  { name: 'Tributária', code: 'TRIBUTARIA' },
  { name: 'Informativa', code: 'INFORMATIVA' },
];

const tipoClassificacaoFiltroTodos: AbrangenciaOpcao = { name: 'Todos os Tipos', code: 'TODOS' };
const periodicidadeFiltroTodas: AbrangenciaOpcao = { name: 'Todas Periodicidades', code: 'TODOS' };

const mesesBaseOptions = [
  { label: '(nenhum)', value: '' },
  { label: 'Janeiro', value: '1' },
  { label: 'Fevereiro', value: '2' },
  { label: 'Março', value: '3' },
  { label: 'Abril', value: '4' },
  { label: 'Maio', value: '5' },
  { label: 'Junho', value: '6' },
  { label: 'Julho', value: '7' },
  { label: 'Agosto', value: '8' },
  { label: 'Setembro', value: '9' },
  { label: 'Outubro', value: '10' },
  { label: 'Novembro', value: '11' },
  { label: 'Dezembro', value: '12' },
];

const emptyObrigacao: ObrigacaoLegais = {
  id: '',
  tipo_empresa_id: '',
  tipoempresa: { id: '', nome: '' },
  tipo_classificacao: 'TRIBUTARIA',
  descricao: '',
  periodicidade: 'MENSAL',
  abrangencia: 'FEDERAL',
  dia_base: 20,
  mes_base: '',
  valor: undefined,
  observacao: '',
  estado: { id: '', nome: '' },
  municipio: { id: '', nome: '' },
  bairro: '',
};

const ObrigacoesLegaisPage = () => {
  const [obrigacoes, setObrigacoes] = useState<ObrigacaoLegais[]>([]);
  const [obrigacao, setObrigacao] = useState<ObrigacaoLegais>({ ...emptyObrigacao });
  const [obrigacaoDialog, setObrigacaoDialog] = useState(false);
  const [deleteObrigacaoDialog, setDeleteObrigacaoDialog] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [totalRecords, setTotalRecords] = useState(0);
  const [first, setFirst] = useState(0);
  const [rows, setRows] = useState(20);
  const [currentPage, setCurrentPage] = useState(1);
  const [pageInputTooltip, setPageInputTooltip] = useState('');

  const [municipiosFallback, setMunicipiosFallback] = useState<GeoRef[]>([]);
  const [estadosFallback, setEstadosFallback] = useState<GeoRef[]>([]);
  const [tiposEmpresaFallback, setTiposEmpresaFallback] = useState<TipoEmpresaRef[]>([]);

  // Dialog-level selected geo values
  const [selectedEstado, setSelectedEstado] = useState<GeoRef | undefined>();
  const [selectedMunicipio, setSelectedMunicipio] = useState<GeoRef | undefined>();
  const [selectedTipoEmpresa, setSelectedTipoEmpresa] = useState<TipoEmpresaRef | undefined>();
  const [selectedCatalogoServicoIDs, setSelectedCatalogoServicoIDs] = useState<string[]>([]);
  const [catalogoDialogVisible, setCatalogoDialogVisible] = useState(false);
  const [catalogoDraftIDs, setCatalogoDraftIDs] = useState<string[]>([]);
  const [catalogoSecaoFiltro, setCatalogoSecaoFiltro] = useState<string>('TODAS');
  const [catalogoBusca, setCatalogoBusca] = useState('');

  // Selected abrangencia/periodicidade options (dropdown objects)
  const [selectedAbrangencia, setSelectedAbrangencia] = useState<AbrangenciaOpcao>(abrangencias[1]); // FEDERAL default in form
  const [selectedPeriodicidade, setSelectedPeriodicidade] = useState<AbrangenciaOpcao>(periodicidades[0]); // MENSAL default
  const [selectedTipoClassificacao, setSelectedTipoClassificacao] = useState<AbrangenciaOpcao>(tiposClassificacao[0]); // TRIBUTARIA default

  // Filter in header (list view)
  const [filterAbrangencia, setFilterAbrangencia] = useState<AbrangenciaOpcao>(abrangencias[0]); // TODOS
  const [filterTipoEmpresa, setFilterTipoEmpresa] = useState<TipoEmpresaRef | undefined>(undefined);
  const [filterTipoClassificacao, setFilterTipoClassificacao] = useState<AbrangenciaOpcao>(tipoClassificacaoFiltroTodos);
  const [filterPeriodicidade, setFilterPeriodicidade] = useState<AbrangenciaOpcao>(periodicidadeFiltroTodas);
  const [filterLocalizacao, setFilterLocalizacao] = useState('');

  const toast = useRef<Toast>(null);

  const [lazyState, setLazyState] = useState<LazyTableState>({
    first: 0,
    rows: 20,
    page: 1,
    sortField: 'descricao',
    sortOrder: 1,
    filters: { descricao: { value: '', matchMode: 'contains' } },
    abrangencia: abrangencias[0],
    tipo_empresa_id: '',
    tipo_classificacao: '',
    periodicidade: '',
    localizacao: '',
  });

  const obrigacaoLegaisService = ObrigacaoLegaisService();
  const catalogoServicoService = CatalogoServicoService();

  const getSortValue = (item: ObrigacaoLegais, field?: string): string | number => {
    switch (field) {
      case 'descricao':
        return (item.descricao ?? '').toLowerCase();
      case 'tipoempresa.nome':
        return (item.tipoempresa?.nome ?? '').toLowerCase();
      case 'tipo_classificacao':
        return (item.tipo_classificacao ?? '').toLowerCase();
      case 'periodicidade':
        return (item.periodicidade ?? '').toLowerCase();
      case 'abrangencia':
        return (item.abrangencia ?? '').toLowerCase();
      case 'valor':
        return item.valor ?? 0;
      default:
        return (item.descricao ?? '').toLowerCase();
    }
  };

  const sortObrigacoesLocal = (items: ObrigacaoLegais[]): ObrigacaoLegais[] => {
    const field = lazyState.sortField ?? 'descricao';
    const order = lazyState.sortOrder === -1 ? -1 : 1;

    return [...items].sort((a, b) => {
      const left = getSortValue(a, field);
      const right = getSortValue(b, field);

      if (typeof left === 'number' && typeof right === 'number') {
        return (left - right) * order;
      }

      return String(left).localeCompare(String(right), 'pt-BR', { sensitivity: 'base' }) * order;
    });
  };

  const loadObrigacoes = async () => {
    const { data } = await obrigacaoLegaisService.getObrigacoes({ lazyEvent: JSON.stringify(lazyState) });
    return {
      obrigacoes: sortObrigacoesLocal(data?.obrigacoes ?? []),
      totalRecords: data?.totalRecords ?? 0,
    };
  };

  const tipoEmpresaSelecionado = Boolean((lazyState.tipo_empresa_id ?? '').trim());

  const { data, isFetching, refetch } = useQuery({
    queryKey: ['obrigacoes', lazyState],
    queryFn: () => loadObrigacoes(),
    enabled: tipoEmpresaSelecionado,
  });

  const { data: municipios = municipiosFallback } = useQuery<GeoRef[]>({
    queryKey: ['municipios-lite'],
    queryFn: async () => {
      const { data } = await MunicipioService().getMunicipiosLite();
      const lista = data?.municipios ?? [];
      setMunicipiosFallback(lista);
      return lista;
    },
  });

  const { data: estados = estadosFallback } = useQuery<GeoRef[]>({
    queryKey: ['estados-uf-cidade'],
    queryFn: async () => {
      const { data } = await EstadoService().getUFCidade();
      const lista = data?.estados ?? [];
      setEstadosFallback(lista);
      return lista;
    },
  });

  const { data: tiposEmpresa = tiposEmpresaFallback } = useQuery<TipoEmpresaRef[]>({
    queryKey: ['tiposempresa-lite'],
    queryFn: async () => {
      const { data } = await TipoEmpresaService().getTiposEmpresaLite();
      const lista = data?.tiposEmpresa ?? [];
      setTiposEmpresaFallback(lista);
      return lista;
    },
  });

  const { data: catalogoServicos = [] } = useQuery<CatalogoServico[]>({
    queryKey: ['catalogo-servicos-lite-obrigacoes'],
    queryFn: () => catalogoServicoService.list({ incluirInativos: false }),
  });

  const secoesCatalogo = useMemo(
    () =>
      ['TODAS', ...Array.from(new Set(catalogoServicos.map((item) => item.secao?.trim()).filter((item): item is string => Boolean(item && item.length > 0)))).sort((a, b) =>
        a.localeCompare(b, 'pt-BR', { sensitivity: 'base' }),
      )],
    [catalogoServicos],
  );

  const catalogoFiltrado = useMemo(() => {
    const termo = catalogoBusca.trim().toLowerCase();
    return catalogoServicos.filter((item) => {
      if (catalogoSecaoFiltro !== 'TODAS' && item.secao !== catalogoSecaoFiltro) {
        return false;
      }
      if (!termo) {
        return true;
      }
      return [item.descricao, item.codigo, item.id_sistema, item.id_servico, item.secao]
        .map((v) => String(v ?? '').toLowerCase())
        .some((v) => v.includes(termo));
    });
  }, [catalogoServicos, catalogoSecaoFiltro, catalogoBusca]);

  const catalogoSelecionadoDraft = useMemo(
    () => catalogoServicos.filter((item) => catalogoDraftIDs.includes(item.id)),
    [catalogoServicos, catalogoDraftIDs],
  );

  const catalogoSelecionadoFinal = useMemo(
    () => catalogoServicos.filter((item) => selectedCatalogoServicoIDs.includes(item.id)),
    [catalogoServicos, selectedCatalogoServicoIDs],
  );

  // ── paginator ────────────────────────────────────────────────────────────

  const paginatorLeft = (
    <Button type="button" icon="pi pi-refresh" tooltip="Atualizar" className="p-button-text" onClick={() => refetch()} />
  );

  const onPage = (event: DataTableStateEvent) => {
    const nextFirst = event.first ?? 0;
    const nextRows = event.rows ?? 20;
    const nextPage = event.page ?? 0;

    setFirst(nextFirst);
    setRows(nextRows);
    setCurrentPage(nextPage + 1);
    setLazyState((prev) => ({ ...prev, ...event, first: nextFirst, rows: nextRows, page: nextPage }));
  };

  const onSort = (event: DataTableStateEvent) => {
    setLazyState((prev) => ({
      ...prev,
      sortField: event.sortField ?? 'descricao',
      sortOrder: event.sortOrder ?? 1,
      first: 0,
      page: 0,
    }));
  };

  const onPageInputKeyDown = (event: React.KeyboardEvent<HTMLInputElement>, options: PageInputOptions) => {
    if (event.key === 'Enter') {
      const page = currentPage;
      if (page < 1 || page > options.totalPages) {
        setPageInputTooltip(`Valor deve estar entre 1 e ${options.totalPages}.`);
      } else {
        const f = currentPage ? options.rows * (page - 1) : 0;
        setFirst(options.first);
        setRows(options.rows);
        setCurrentPage(page);
        setLazyState({ ...lazyState, first: f, rows: options.rows, page: currentPage });
      }
    }
  };

  const onPageInputChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    setCurrentPage(Number(event.target.value || 1));
  };

  const template: PaginatorTemplate = {
    layout: 'PrevPageLink PageLinks NextPageLink RowsPerPageDropdown CurrentPageReport',
    PrevPageLink: (options) => (
      <button type="button" className={options.className} onClick={options.onClick} disabled={options.disabled}>
        <span className="p-3">Página anterior</span>
      </button>
    ),
    NextPageLink: (options) => (
      <button type="button" className={options.className} onClick={options.onClick} disabled={options.disabled}>
        <span className="p-3">Próxima página</span>
      </button>
    ),
    PageLinks: (options) => {
      if (
        (options.view.startPage === options.page && options.view.startPage !== 0) ||
        (options.view.endPage === options.page && options.page + 1 !== options.totalPages)
      ) {
        return (
          <span className={classNames(options.className, 'obrigacao-page-ellipsis', { 'p-disabled': true })}>
            ...
          </span>
        );
      }
      return (
        <button type="button" className={options.className} onClick={options.onClick}>
          {options.page + 1}
        </button>
      );
    },
    RowsPerPageDropdown: (options) => (
      <Dropdown
        value={options.value}
        options={[
          { label: 10, value: 10 },
          { label: 20, value: 20 },
          { label: 50, value: 50 },
        ]}
        onChange={options.onChange}
      />
    ),
    CurrentPageReport: (options) => (
      <span className="mx-3 obrigacao-current-page-report">
        Página{' '}
        <InputText
          className="ml-1"
          value={currentPage.toString()}
          tooltip={pageInputTooltip}
          onKeyDown={(e) => onPageInputKeyDown(e, options)}
          onChange={onPageInputChange}
        />
      </span>
    ),
  };

  // ── dialog helpers ───────────────────────────────────────────────────────

  const openNew = () => {
    setObrigacao({ ...emptyObrigacao });
    setSelectedAbrangencia(abrangencias[1]); // FEDERAL
    setSelectedPeriodicidade(periodicidades[0]); // MENSAL
    setSelectedTipoClassificacao(tiposClassificacao[0]); // TRIBUTARIA
    setSelectedEstado(undefined);
    setSelectedMunicipio(undefined);
    setSelectedTipoEmpresa(undefined);
    setSelectedCatalogoServicoIDs([]);
    setSubmitted(false);
    setObrigacaoDialog(true);
  };

  const hideDialog = () => {
    setSubmitted(false);
    setObrigacaoDialog(false);
  };

  const abrirDialogCatalogo = () => {
    setCatalogoDraftIDs(selectedCatalogoServicoIDs);
    setCatalogoSecaoFiltro('TODAS');
    setCatalogoBusca('');
    setCatalogoDialogVisible(true);
  };

  const aplicarDialogCatalogo = () => {
    setSelectedCatalogoServicoIDs(catalogoDraftIDs);
    setCatalogoDialogVisible(false);
  };

  const editObrigacao = (row: ObrigacaoLegais) => {
    const mesNorm =
      row.mes_base === undefined || row.mes_base === null || row.mes_base === ''
        ? ''
        : String(row.mes_base);
    setObrigacao({ ...row, mes_base: mesNorm });
    setSelectedAbrangencia(abrangencias.find((a) => a.code === row.abrangencia) ?? abrangencias[1]);
    setSelectedPeriodicidade(periodicidades.find((p) => p.code === row.periodicidade) ?? periodicidades[0]);
    setSelectedTipoClassificacao(
      tiposClassificacao.find((t) => t.code === (row.tipo_classificacao || '').toUpperCase()) ?? tiposClassificacao[0],
    );
    setSelectedEstado(row.estado?.id ? row.estado : undefined);
    setSelectedMunicipio(row.municipio?.id ? row.municipio : undefined);
    setSelectedTipoEmpresa(row.tipo_empresa_id && row.tipoempresa?.nome ? { id: row.tipo_empresa_id, descricao: row.tipoempresa.nome } : undefined);
    setSelectedCatalogoServicoIDs(
      (row.catalogo_servico_ids ?? row.servicos_serpro?.map((s) => s.catalogo_servico_id) ?? [])
        .filter((id): id is string => typeof id === 'string' && id.trim() !== ''),
    );
    setObrigacaoDialog(true);
  };

  const confirmDelete = (row: ObrigacaoLegais) => {
    setObrigacao(row);
    setDeleteObrigacaoDialog(true);
  };

  const onInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>, field: string) => {
    const val = e.target.value || '';
    setObrigacao((prev) => ({ ...prev, [field]: val }));
  };

  // ── save ─────────────────────────────────────────────────────────────────

  const saveObrigacao = () => {
    setSubmitted(true);
    if (!obrigacao?.descricao?.trim() || !selectedTipoEmpresa?.id) return;

    const abrangCode = selectedAbrangencia?.code ?? 'FEDERAL';
    const tipoClassificacao = (selectedTipoClassificacao?.code ?? 'TRIBUTARIA').toUpperCase();
    const payload = {
      ...obrigacao,
      tipoempresa: selectedTipoEmpresa,
      tipo_classificacao: tipoClassificacao,
      periodicidade: selectedPeriodicidade?.code ?? 'MENSAL',
      abrangencia: abrangCode,
      estado: abrangCode === 'ESTADUAL' ? selectedEstado : undefined,
      municipio: (abrangCode === 'MUNICIPAL' || abrangCode === 'BAIRRO') ? selectedMunicipio : undefined,
      bairro: abrangCode === 'BAIRRO' ? (obrigacao.bairro ?? '').trim() : '',
      catalogo_servico_ids: selectedCatalogoServicoIDs,
      dia_base: obrigacao.dia_base ?? 20,
      mes_base: obrigacao.mes_base && String(obrigacao.mes_base).trim() !== '' ? String(obrigacao.mes_base) : null,
    };

    const action = obrigacao.id
      ? obrigacaoLegaisService.updateObrigacao(payload)
      : obrigacaoLegaisService.createObrigacao(payload);

    const label = obrigacao.id ? 'atualizado' : 'criado';

    action
      .then(() => {
        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: `Obrigação legal ${label} com sucesso`, life: 3000 });
      })
      .catch(() => {
        toast.current?.show({ severity: 'error', summary: 'Erro', detail: `Erro ao ${obrigacao.id ? 'atualizar' : 'criar'} a obrigação legal`, life: 3000 });
      })
      .finally(() => {
        setObrigacaoDialog(false);
        setObrigacao({ ...emptyObrigacao });
        setSubmitted(false);
        refetch();
      });
  };

  const deleteObrigacao = () => {
    if (!obrigacao?.id) return;
    obrigacaoLegaisService
      .deleteObrigacao({ id: obrigacao.id })
      .then(() => {
        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Obrigação legal excluída', life: 3000 });
      })
      .catch(() => {
        toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao excluir a obrigação legal', life: 3000 });
      })
      .finally(() => {
        setDeleteObrigacaoDialog(false);
        setObrigacao({ ...emptyObrigacao });
        refetch();
      });
  };

  // ── filter ───────────────────────────────────────────────────────────────

  const handleFilterAbrangenciaChange = (selected: AbrangenciaOpcao) => {
    setFilterAbrangencia(selected);
    setLazyState((prev) => ({ ...prev, abrangencia: selected, first: 0 }));
  };

  const handleFilterTipoEmpresaChange = (selected: TipoEmpresaRef | undefined) => {
    setFilterTipoEmpresa(selected);
    setLazyState((prev) => ({
      ...prev,
      tipo_empresa_id: selected?.id?.trim() ?? '',
      first: 0,
      page: 1,
    }));
    setFirst(0);
    setCurrentPage(1);
  };

  const handleFilterTipoClassificacaoChange = (selected: AbrangenciaOpcao) => {
    setFilterTipoClassificacao(selected);
    setLazyState((prev) => ({
      ...prev,
      tipo_classificacao: selected?.code === 'TODOS' ? '' : selected?.code ?? '',
      first: 0,
    }));
  };

  const handleFilterPeriodicidadeChange = (selected: AbrangenciaOpcao) => {
    setFilterPeriodicidade(selected);
    setLazyState((prev) => ({
      ...prev,
      periodicidade: selected?.code === 'TODOS' ? '' : selected?.code ?? '',
      first: 0,
    }));
  };

  const handleFilterLocalizacao = (event: React.KeyboardEvent<HTMLInputElement>, value: string) => {
    if (event.key === 'Enter') {
      setLazyState((prev) => ({
        ...prev,
        localizacao: value,
        first: 0,
      }));
    }
  };

  const handleFilterLocalizacaoClear = (event: React.ChangeEvent<HTMLInputElement>) => {
    const value = event.target.value;
    setFilterLocalizacao(value);
    if (!value) {
      setLazyState((prev) => ({
        ...prev,
        localizacao: '',
        first: 0,
      }));
    }
  };

  const handleSearch = (event: React.KeyboardEvent<HTMLInputElement>, value: string) => {
    if (event.key === 'Enter') {
      setLazyState((prev) => ({
        ...prev,
        filters: { descricao: { value, matchMode: 'contains' } },
        first: 0,
      }));
    }
  };

  const handleSearchClear = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (!e.target.value) {
      setLazyState((prev) => ({
        ...prev,
        filters: { descricao: { value: '', matchMode: 'contains' } },
      }));
    }
  };

  // ── templates ────────────────────────────────────────────────────────────

  const leftToolbarTemplate = () => (
    <div className="my-2">
      <Button label="Novo" icon="pi pi-plus" severity="success" className="mr-2" onClick={openNew} />
    </div>
  );

  const periodicidadeBodyTemplate = (rowData: ObrigacaoLegais) => {
    const label = periodicidades.find((p) => p.code === rowData.periodicidade)?.name ?? rowData.periodicidade;
    return <span>{label}</span>;
  };

  const abrangenciaBodyTemplate = (rowData: ObrigacaoLegais) => {
    const label = abrangencias.find((a) => a.code === rowData.abrangencia)?.name ?? rowData.abrangencia;
    return <span>{label}</span>;
  };

  const localizacaoBodyTemplate = (rowData: ObrigacaoLegais) => {
    if (rowData.abrangencia === 'ESTADUAL' && rowData.estado?.nome) {
      return <span>{rowData.estado.nome}</span>;
    }
    if ((rowData.abrangencia === 'MUNICIPAL' || rowData.abrangencia === 'BAIRRO') && rowData.municipio?.nome) {
      if (rowData.abrangencia === 'BAIRRO') {
        const localBairro = (rowData.bairro ?? '').trim();
        if (localBairro !== '') {
          return <span>{`${localBairro} / ${rowData.municipio.nome}`}</span>;
        }
      }
      return <span>{rowData.municipio.nome}</span>;
    }
    return <span>—</span>;
  };

  const valorBodyTemplate = (rowData: ObrigacaoLegais) => {
    if ((rowData.tipo_classificacao || '').toUpperCase() !== 'TRIBUTARIA') return <span>—</span>;
    if (rowData.valor == null) return <span>—</span>;
    return (
      <span>
        {rowData.valor.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })}
      </span>
    );
  };

  const tipoClassificacaoBodyTemplate = (rowData: ObrigacaoLegais) => {
    const code = (rowData.tipo_classificacao || '').toUpperCase();
    if (code === 'TRIBUTARIA') return <span>Tributária</span>;
    if (code === 'INFORMATIVA') return <span>Informativa</span>;
    return <span>{rowData.tipo_classificacao || '—'}</span>;
  };

  const actionBodyTemplate = (rowData: ObrigacaoLegais) => (
    <>
      <Button icon="pi pi-pencil" rounded severity="success" className="mr-2" onClick={() => editObrigacao(rowData)} tooltip="Editar" tooltipOptions={{ position: 'left' }} />
      <Button icon="pi pi-trash" rounded severity="warning" onClick={() => confirmDelete(rowData)} tooltip="Excluir" tooltipOptions={{ position: 'left' }} />
    </>
  );

  const servicosSerproBodyTemplate = (rowData: ObrigacaoLegais) => {
    const itens = rowData.servicos_serpro ?? [];
    if (itens.length === 0) {
      return <span>—</span>;
    }
    if (itens.length === 1) {
      return <span>{itens[0].descricao || itens[0].codigo || 'Serviço vinculado'}</span>;
    }
    return <span>{`${itens.length} serviços`}</span>;
  };

  const toggleCatalogoDraft = (servicoID: string) => {
    setCatalogoDraftIDs((prev) =>
      prev.includes(servicoID) ? prev.filter((id) => id !== servicoID) : [...prev, servicoID],
    );
  };

  const acaoCatalogoBodyTemplate = (rowData: CatalogoServico) => {
    const selecionado = catalogoDraftIDs.includes(rowData.id);
    return (
      <Button
        type="button"
        label={selecionado ? 'Remover' : 'Selecionar'}
        icon={selecionado ? 'pi pi-times' : 'pi pi-plus'}
        className={selecionado ? 'p-button-text p-button-danger' : 'p-button-text p-button-success'}
        onClick={() => toggleCatalogoDraft(rowData.id)}
      />
    );
  };

  const currentAbrang = selectedAbrangencia?.code ?? 'FEDERAL';

  const dialogFooter = (
    <>
      <Button label="Cancelar" icon="pi pi-times" text onClick={hideDialog} />
      <Button label="Salvar" icon="pi pi-check" text onClick={saveObrigacao} />
    </>
  );

  const deleteDialogFooter = (
    <>
      <Button label="Não" icon="pi pi-times" text onClick={() => setDeleteObrigacaoDialog(false)} />
      <Button label="Sim" icon="pi pi-check" text onClick={deleteObrigacao} />
    </>
  );

  const header = (
    <div className="flex flex-column md:flex-row md:justify-content-between md:align-items-center">
      <h5 className="m-0">Obrigações Legais</h5>
      <div className="flex justify-content-center">
        <Dropdown
          value={filterTipoEmpresa}
          onChange={(e) => handleFilterTipoEmpresaChange(e.value)}
          options={tiposEmpresa}
          optionLabel="descricao"
          dataKey="id"
          className="w-full md:w-16rem"
          placeholder="Filtre por Enquadramento Jurídico"
          filter
          showClear
        />
      </div>
      <div className="flex justify-content-center">
        <Dropdown
          value={filterAbrangencia}
          onChange={(e) => handleFilterAbrangenciaChange(e.value)}
          options={abrangencias}
          optionLabel="name"
          className="w-full md:w-14rem"
        />
      </div>
      <div className="flex justify-content-center">
        <Dropdown
          value={filterTipoClassificacao}
          onChange={(e) => handleFilterTipoClassificacaoChange(e.value)}
          options={[tipoClassificacaoFiltroTodos, ...tiposClassificacao]}
          optionLabel="name"
          className="w-full md:w-14rem"
          placeholder="Tipo de Classificação"
        />
      </div>
      <div className="flex justify-content-center">
        <Dropdown
          value={filterPeriodicidade}
          onChange={(e) => handleFilterPeriodicidadeChange(e.value)}
          options={[periodicidadeFiltroTodas, ...periodicidades]}
          optionLabel="name"
          className="w-full md:w-14rem"
        />
      </div>
      <span className="block mt-2 md:mt-0 p-input-icon-left">
        <i className="pi pi-map-marker" />
        <InputText
          type="search"
          value={filterLocalizacao}
          onKeyDown={(e) => handleFilterLocalizacao(e, e.currentTarget.value)}
          onChange={handleFilterLocalizacaoClear}
          placeholder="Localização (Enter)"
          tooltip="Digite estado, município ou bairro e tecle Enter"
          tooltipOptions={{ position: 'left' }}
        />
      </span>
      <span className="block mt-2 md:mt-0 p-input-icon-left">
        <i className="pi pi-search" />
        <InputText
          type="search"
          onKeyDown={(e) => handleSearch(e, e.currentTarget.value)}
          onChange={handleSearchClear}
          placeholder="Procurar..."
          tooltip="Digite e tecle Enter"
          tooltipOptions={{ position: 'left' }}
        />
      </span>
    </div>
  );

  return (
    <>
      <div className="grid crud-demo">
        <div className="col-12">
          <div className="card">
            <Toast ref={toast} />
            <Toolbar className="mb-4" left={leftToolbarTemplate} />

            <DataTable
              value={tipoEmpresaSelecionado ? (data?.obrigacoes ?? obrigacoes) : []}
              lazy
              dataKey="id"
              paginator
              rows={rows}
              rowsPerPageOptions={[10, 20, 50]}
              className="datatable-responsive"
              paginatorTemplate={template}
              emptyMessage={tipoEmpresaSelecionado ? 'Nenhuma obrigação legal encontrada.' : 'Selecione um Enquadramento Jurídico para listar.'}
              header={header}
              size="small"
              stripedRows
              filterDisplay="row"
              first={lazyState.first}
              onPage={onPage}
              onSort={onSort}
              sortField={lazyState.sortField}
              sortOrder={(lazyState.sortOrder ?? 1) as 1 | 0 | -1 | null}
              loading={isFetching}
              totalRecords={tipoEmpresaSelecionado ? (data?.totalRecords ?? totalRecords) : 0}
              paginatorLeft={paginatorLeft}
            >
              <Column field="descricao" header="Descrição" sortable headerStyle={{ minWidth: '16rem' }} />
              <Column field="tipoempresa.nome" header="Enquadramento Jurídico" sortable headerStyle={{ minWidth: '14rem' }} />
              <Column
                field="tipo_classificacao"
                header="Tipo de Classificação"
                sortable
                body={tipoClassificacaoBodyTemplate}
                headerStyle={{ minWidth: '12rem' }}
              />
              <Column field="periodicidade" header="Periodicidade" sortable body={periodicidadeBodyTemplate} headerStyle={{ minWidth: '10rem' }} />
              <Column field="abrangencia" header="Abrangência" sortable body={abrangenciaBodyTemplate} headerStyle={{ minWidth: '10rem' }} />
              <Column header="Localização" body={localizacaoBodyTemplate} headerStyle={{ minWidth: '14rem' }} />
              <Column field="valor" header="Valor" sortable body={valorBodyTemplate} headerStyle={{ minWidth: '10rem' }} />
              <Column header="Serviço Serpro" body={servicosSerproBodyTemplate} headerStyle={{ minWidth: '14rem' }} />
              <Column body={actionBodyTemplate} headerStyle={{ minWidth: '8rem' }} />
            </DataTable>

            {/* ── Create / Edit dialog ─── */}
            <Dialog
              visible={obrigacaoDialog}
              style={{ width: '520px' }}
              header="Obrigação legal"
              modal
              className="p-fluid"
              footer={dialogFooter}
              onHide={hideDialog}
            >
              <div className="field">
                <label htmlFor="ddtipoempresa">Enquadramento Jurídico *</label>
                <Dropdown
                  id="ddtipoempresa"
                  value={selectedTipoEmpresa}
                  options={tiposEmpresa}
                  onChange={(e) => setSelectedTipoEmpresa(e.value)}
                  optionLabel="descricao"
                  dataKey="id"
                  placeholder="Selecione um Enquadramento Jurídico"
                  filter
                  className={classNames({ 'p-invalid': submitted && !selectedTipoEmpresa })}
                />
                {submitted && !selectedTipoEmpresa && <small className="p-invalid">Tipo de empresa é obrigatório.</small>}
              </div>

              <div className="field">
                <label htmlFor="tipo_classificacao">Tipo de Classificação</label>
                <Dropdown
                  id="tipo_classificacao"
                  value={selectedTipoClassificacao}
                  options={tiposClassificacao}
                  onChange={(e) => setSelectedTipoClassificacao(e.value)}
                  optionLabel="name"
                />
              </div>

              {/* Descrição */}
              <div className="field">
                <label htmlFor="descricao">Descrição *</label>
                <InputText
                  id="descricao"
                  value={obrigacao.descricao ?? ''}
                  onChange={(e) => onInputChange(e, 'descricao')}
                  required
                  autoFocus
                  className={classNames({ 'p-invalid': submitted && !obrigacao.descricao })}
                />
                {submitted && !obrigacao.descricao && <small className="p-invalid">Descrição é obrigatória.</small>}
              </div>

              {/* Periodicidade */}
              <div className="field">
                <label htmlFor="periodicidade">Periodicidade</label>
                <Dropdown
                  id="periodicidade"
                  value={selectedPeriodicidade}
                  options={periodicidades}
                  onChange={(e) => setSelectedPeriodicidade(e.value)}
                  optionLabel="name"
                />
              </div>

              <div className="formgrid grid">
                <div className="field col">
                  <label htmlFor="dia_base">Dia base</label>
                  <InputNumber
                    id="dia_base"
                    value={obrigacao.dia_base ?? null}
                    onValueChange={(e) => setObrigacao((prev) => ({ ...prev, dia_base: e.value ?? undefined }))}
                    min={1}
                    max={31}
                    showButtons
                    placeholder="Ex.: 20"
                  />
                </div>
                <div className="field col">
                  <label htmlFor="mes_base">Mês base</label>
                  <Dropdown
                    id="mes_base"
                    value={obrigacao.mes_base ?? ''}
                    options={mesesBaseOptions}
                    onChange={(e) => setObrigacao((prev) => ({ ...prev, mes_base: e.value ?? '' }))}
                    optionLabel="label"
                    optionValue="value"
                    placeholder="(nenhum)"
                  />
                </div>
              </div>

              {/* Abrangência */}
              <div className="field">
                <label htmlFor="abrangencia">Abrangência</label>
                <Dropdown
                  id="abrangencia"
                  value={selectedAbrangencia}
                  options={abrangencias.filter((a) => a.code !== 'TODOS')}
                  onChange={(e) => {
                    setSelectedAbrangencia(e.value);
                    setSelectedEstado(undefined);
                    setSelectedMunicipio(undefined);
                    setObrigacao((prev) => ({ ...prev, bairro: '' }));
                  }}
                  optionLabel="name"
                />
              </div>

              {/* Estado – only ESTADUAL */}
              {currentAbrang === 'ESTADUAL' && (
                <div className="field">
                  <label htmlFor="ddestado">Estado</label>
                  <Dropdown
                    id="ddestado"
                    value={selectedEstado}
                    options={estados}
                    onChange={(e) => setSelectedEstado(e.value)}
                    optionLabel="nome"
                    dataKey="id"
                    placeholder="Selecione um Estado"
                    filter
                  />
                  {submitted && currentAbrang === 'ESTADUAL' && !selectedEstado && (
                    <small className="p-invalid">Estado é obrigatório.</small>
                  )}
                </div>
              )}

              {/* Município – escopos municipais */}
              {(currentAbrang === 'MUNICIPAL' || currentAbrang === 'BAIRRO') && (
                <div className="field">
                  <label htmlFor="ddmunicipio">Município</label>
                  <Dropdown
                    id="ddmunicipio"
                    value={selectedMunicipio}
                    options={municipios}
                    onChange={(e) => setSelectedMunicipio(e.value)}
                    optionLabel="nome"
                    dataKey="id"
                    placeholder="Selecione um Município"
                    filter
                  />
                  {submitted && (currentAbrang === 'MUNICIPAL' || currentAbrang === 'BAIRRO') && !selectedMunicipio && (
                    <small className="p-invalid">Município é obrigatório.</small>
                  )}
                </div>
              )}

              {currentAbrang === 'BAIRRO' && (
                <div className="field">
                  <label htmlFor="bairro">Bairro</label>
                  <InputText
                    id="bairro"
                    value={obrigacao.bairro ?? ''}
                    onChange={(e) => onInputChange(e, 'bairro')}
                    placeholder="Informe o bairro"
                  />
                </div>
              )}

              {/* Valor */}
              {selectedTipoClassificacao?.code === 'TRIBUTARIA' && (
                <div className="field">
                  <label htmlFor="valor">Valor (opcional)</label>
                  <InputNumber
                    id="valor"
                    value={obrigacao.valor ?? null}
                    onValueChange={(e) => setObrigacao((prev) => ({ ...prev, valor: e.value ?? undefined }))}
                    mode="currency"
                    currency="BRL"
                    locale="pt-BR"
                  />
                </div>
              )}

              {/* Observação */}
              <div className="field">
                <label htmlFor="observacao">Observação</label>
                <InputTextarea
                  id="observacao"
                  value={obrigacao.observacao ?? ''}
                  onChange={(e) => onInputChange(e, 'observacao')}
                  rows={3}
                  placeholder="Informações adicionais sobre esta obrigação legal"
                />
              </div>

              <div className="field">
                <label htmlFor="catalogo_servico_ids">Serviços vinculados (Serpro)</label>
                <div className="flex flex-column gap-2">
                  <Button
                    type="button"
                    icon="pi pi-list"
                    label={selectedCatalogoServicoIDs.length > 0 ? `Selecionar serviços (${selectedCatalogoServicoIDs.length})` : 'Selecionar serviços'}
                    className="p-button-outlined"
                    onClick={abrirDialogCatalogo}
                  />
                  <div className="surface-50 border-1 border-round border-300 p-2" style={{ maxHeight: '8rem', overflowY: 'auto' }}>
                    {catalogoSelecionadoFinal.length === 0 ? (
                      <span className="text-600">Nenhum serviço selecionado.</span>
                    ) : (
                      <div className="flex flex-column gap-1">
                        {catalogoSelecionadoFinal.map((item) => (
                          <span key={item.id} className="text-700">
                            {item.secao} - {item.codigo} - {item.descricao}
                          </span>
                        ))}
                      </div>
                    )}
                  </div>
                </div>
                <small className="text-600">
                  Vínculo opcional. Use para obrigações que dependem de integração com o Catálogo de Serviços.
                </small>
              </div>
            </Dialog>

            <Dialog
              visible={catalogoDialogVisible}
              header="Selecionar serviços vinculados (Serpro)"
              style={{ width: 'min(96vw, 78rem)' }}
              modal
              onHide={() => setCatalogoDialogVisible(false)}
              footer={
                <div className="flex justify-content-end gap-2">
                  <Button type="button" label="Cancelar" text onClick={() => setCatalogoDialogVisible(false)} />
                  <Button type="button" label="Aplicar" icon="pi pi-check" onClick={aplicarDialogCatalogo} />
                </div>
              }
            >
              <div className="flex flex-column md:flex-row gap-2 mb-3">
                <Dropdown
                  value={catalogoSecaoFiltro}
                  options={secoesCatalogo.map((secao) => ({ label: secao === 'TODAS' ? 'Todas as seções' : secao, value: secao }))}
                  optionLabel="label"
                  optionValue="value"
                  onChange={(e) => setCatalogoSecaoFiltro(e.value)}
                  className="w-full md:w-18rem"
                  placeholder="Filtrar seção"
                />
                <span className="p-input-icon-left w-full">
                  <i className="pi pi-search" />
                  <InputText
                    value={catalogoBusca}
                    onChange={(e) => setCatalogoBusca(e.target.value)}
                    placeholder="Buscar por descricao, codigo, idSistema ou idServico"
                    className="w-full"
                  />
                </span>
              </div>

              <DataTable
                value={catalogoFiltrado}
                dataKey="id"
                paginator
                rows={10}
                rowsPerPageOptions={[10, 20, 50]}
                size="small"
                stripedRows
                emptyMessage="Nenhum serviço encontrado para os filtros."
              >
                <Column header="Ação" body={acaoCatalogoBodyTemplate} style={{ width: '8rem' }} />
                <Column field="secao" header="Seção" style={{ minWidth: '11rem' }} />
                <Column field="codigo" header="Código" style={{ minWidth: '6rem' }} />
                <Column field="descricao" header="Descrição" style={{ minWidth: '22rem' }} />
                <Column field="id_sistema" header="idSistema" style={{ minWidth: '8rem' }} />
                <Column field="id_servico" header="idServico" style={{ minWidth: '8rem' }} />
              </DataTable>
            </Dialog>

            {/* ── Delete confirm dialog ─── */}
            <Dialog
              visible={deleteObrigacaoDialog}
              style={{ width: '450px' }}
              header="Confirmar Exclusão"
              modal
              footer={deleteDialogFooter}
              onHide={() => setDeleteObrigacaoDialog(false)}
            >
              <div className="flex align-items-center justify-content-center">
                <i className="pi pi-exclamation-triangle mr-3 obrigacao-delete-icon" />
                {obrigacao && (
                  <span>
                    Deseja excluir a obrigação legal <b>{obrigacao.descricao}</b>?
                  </span>
                )}
              </div>
            </Dialog>
          </div>
        </div>
      </div>
      <style jsx>{`
        .obrigacao-page-ellipsis {
          user-select: none;
        }

        .obrigacao-current-page-report {
          color: var(--text-color);
          user-select: none;
        }

        .obrigacao-delete-icon {
          font-size: 2rem;
          color: #d6551e;
        }
      `}</style>
    </>
  );
};

export default ObrigacoesLegaisPage;

export const getServerSideProps = withAuthServerSideProps(async (_ctx: GetServerSidePropsContext) => {
  // sem processamento adicional
});
