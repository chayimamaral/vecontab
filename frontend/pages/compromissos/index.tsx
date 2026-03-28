import React, { useEffect, useRef, useState } from 'react';
import { GetServerSidePropsContext } from 'next';
import { classNames } from 'primereact/utils';
import { withAuthServerSideProps } from '../../components/utils/crudUtils';
import { DataTable, DataTableFilterMeta, DataTableStateEvent } from 'primereact/datatable';
import { PaginatorTemplate } from 'primereact/paginator';
import CompromissoService from '../../services/cruds/CompromissoService';
import MunicipioService from '../../services/cruds/MunicipioService';
import EstadoService from '../../services/cruds/EstadoService';
import TipoEmpresaService from '../../services/cruds/TipoEmpresaService';
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

interface Compromisso {
  id?: string;
  tipo_empresa_id?: string;
  tipoempresa?: GeoRef;
  natureza?: string;
  descricao?: string;
  periodicidade?: string;
  abrangencia?: string;
  valor?: number;
  observacao?: string;
  estado?: GeoRef;
  municipio?: GeoRef;
  bairro?: string;
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
  natureza?: string;
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

const tipoEmpresaFiltroTodos: TipoEmpresaRef = {
  id: '',
  descricao: 'Todos os tipos',
};

const abrangencias: AbrangenciaOpcao[] = [
  { name: 'Todos', code: 'TODOS' },
  { name: 'Federal', code: 'FEDERAL' },
  { name: 'Estadual', code: 'ESTADUAL' },
  { name: 'Municipal', code: 'MUNICIPAL' },
  { name: 'Por Bairro', code: 'BAIRRO' },
];

const periodicidades: AbrangenciaOpcao[] = [
  { name: 'Mensal', code: 'MENSAL' },
  { name: 'Anual', code: 'ANUAL' },
];

const naturezas: AbrangenciaOpcao[] = [
  { name: 'Financeiro', code: 'FINANCEIRO' },
  { name: 'Não Financeiro', code: 'NAO_FINANCEIRO' },
];

const naturezaFiltroTodas: AbrangenciaOpcao = { name: 'Todas Naturezas', code: 'TODOS' };
const periodicidadeFiltroTodas: AbrangenciaOpcao = { name: 'Todas Periodicidades', code: 'TODOS' };

const emptyCompromisso: Compromisso = {
  id: '',
  tipo_empresa_id: '',
  tipoempresa: { id: '', nome: '' },
  natureza: 'FINANCEIRO',
  descricao: '',
  periodicidade: 'MENSAL',
  abrangencia: 'FEDERAL',
  valor: undefined,
  observacao: '',
  estado: { id: '', nome: '' },
  municipio: { id: '', nome: '' },
  bairro: '',
};

const CompromissosFinanceiros = () => {
  const [compromissos, setCompromissos] = useState<Compromisso[]>([]);
  const [compromisso, setCompromisso] = useState<Compromisso>({ ...emptyCompromisso });
  const [compromissoDialog, setCompromissoDialog] = useState(false);
  const [deleteCompromissoDialog, setDeleteCompromissoDialog] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [loading, setLoading] = useState(false);
  const [totalRecords, setTotalRecords] = useState(0);
  const [first, setFirst] = useState(0);
  const [rows, setRows] = useState(20);
  const [currentPage, setCurrentPage] = useState(1);
  const [pageInputTooltip, setPageInputTooltip] = useState('');

  const [municipios, setMunicipios] = useState<GeoRef[]>([]);
  const [estados, setEstados] = useState<GeoRef[]>([]);
  const [tiposEmpresa, setTiposEmpresa] = useState<TipoEmpresaRef[]>([]);

  // Dialog-level selected geo values
  const [selectedEstado, setSelectedEstado] = useState<GeoRef | undefined>();
  const [selectedMunicipio, setSelectedMunicipio] = useState<GeoRef | undefined>();
  const [selectedTipoEmpresa, setSelectedTipoEmpresa] = useState<TipoEmpresaRef | undefined>();

  // Selected abrangencia/periodicidade options (dropdown objects)
  const [selectedAbrangencia, setSelectedAbrangencia] = useState<AbrangenciaOpcao>(abrangencias[1]); // FEDERAL default in form
  const [selectedPeriodicidade, setSelectedPeriodicidade] = useState<AbrangenciaOpcao>(periodicidades[0]); // MENSAL default
  const [selectedNatureza, setSelectedNatureza] = useState<AbrangenciaOpcao>(naturezas[0]); // FINANCEIRO default

  // Filter in header (list view)
  const [filterAbrangencia, setFilterAbrangencia] = useState<AbrangenciaOpcao>(abrangencias[0]); // TODOS
  const [filterTipoEmpresa, setFilterTipoEmpresa] = useState<TipoEmpresaRef>(tipoEmpresaFiltroTodos);
  const [filterNatureza, setFilterNatureza] = useState<AbrangenciaOpcao>(naturezaFiltroTodas);
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
    natureza: '',
    periodicidade: '',
    localizacao: '',
  });

  const compromissoService = CompromissoService();

  const getSortValue = (item: Compromisso, field?: string): string | number => {
    switch (field) {
      case 'descricao':
        return (item.descricao ?? '').toLowerCase();
      case 'tipoempresa.nome':
        return (item.tipoempresa?.nome ?? '').toLowerCase();
      case 'natureza':
        return (item.natureza ?? '').toLowerCase();
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

  const sortCompromissosLocal = (items: Compromisso[]): Compromisso[] => {
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

  useEffect(() => {
    loadCompromissos();
  }, [lazyState]);

  useEffect(() => {
    loadGeoData();
  }, []);

  const loadCompromissos = () => {
    setLoading(true);
    compromissoService
      .getCompromissos({ lazyEvent: JSON.stringify(lazyState) })
      .then(({ data }) => {
        setCompromissos(sortCompromissosLocal(data.compromissos ?? []));
        setTotalRecords(data.totalRecords ?? 0);
      })
      .catch(() => {
        toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao carregar compromissos', life: 3000 });
      })
      .finally(() => setLoading(false));
  };

  const loadGeoData = () => {
    MunicipioService()
      .getMunicipiosLite()
      .then(({ data }) => setMunicipios(data?.municipios ?? []));

    EstadoService()
      .getUFCidade()
      .then(({ data }) => setEstados(data?.estados ?? []));

    TipoEmpresaService()
      .getTiposEmpresaLite()
      .then(({ data }) => setTiposEmpresa(data?.tiposEmpresa ?? []));
  };

  // ── paginator ────────────────────────────────────────────────────────────

  const paginatorLeft = (
    <Button type="button" icon="pi pi-refresh" tooltip="Atualizar" className="p-button-text" onClick={loadCompromissos} />
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
          <span className={classNames(options.className, 'compromisso-page-ellipsis', { 'p-disabled': true })}>
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
      <span className="mx-3 compromisso-current-page-report">
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
    setCompromisso({ ...emptyCompromisso });
    setSelectedAbrangencia(abrangencias[1]); // FEDERAL
    setSelectedPeriodicidade(periodicidades[0]); // MENSAL
    setSelectedNatureza(naturezas[0]); // FINANCEIRO
    setSelectedEstado(undefined);
    setSelectedMunicipio(undefined);
    setSelectedTipoEmpresa(undefined);
    setSubmitted(false);
    setCompromissoDialog(true);
  };

  const hideDialog = () => {
    setSubmitted(false);
    setCompromissoDialog(false);
  };

  const editCompromisso = (row: Compromisso) => {
    setCompromisso({ ...row });
    setSelectedAbrangencia(abrangencias.find((a) => a.code === row.abrangencia) ?? abrangencias[1]);
    setSelectedPeriodicidade(periodicidades.find((p) => p.code === row.periodicidade) ?? periodicidades[0]);
    setSelectedNatureza(naturezas.find((n) => n.code === row.natureza) ?? naturezas[0]);
    setSelectedEstado(row.estado?.id ? row.estado : undefined);
    setSelectedMunicipio(row.municipio?.id ? row.municipio : undefined);
    setSelectedTipoEmpresa(row.tipo_empresa_id && row.tipoempresa?.nome ? { id: row.tipo_empresa_id, descricao: row.tipoempresa.nome } : undefined);
    setCompromissoDialog(true);
  };

  const confirmDelete = (row: Compromisso) => {
    setCompromisso(row);
    setDeleteCompromissoDialog(true);
  };

  const onInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>, field: string) => {
    const val = e.target.value || '';
    setCompromisso((prev) => ({ ...prev, [field]: val }));
  };

  // ── save ─────────────────────────────────────────────────────────────────

  const saveCompromisso = () => {
    setSubmitted(true);
    if (!compromisso?.descricao?.trim() || !selectedTipoEmpresa?.id) return;

    const abrangCode = selectedAbrangencia?.code ?? 'FEDERAL';
    const payload = {
      ...compromisso,
      tipoempresa: selectedTipoEmpresa,
      natureza: selectedNatureza?.code ?? 'FINANCEIRO',
      periodicidade: selectedPeriodicidade?.code ?? 'MENSAL',
      abrangencia: abrangCode,
      estado: abrangCode === 'ESTADUAL' ? selectedEstado : undefined,
      municipio: (abrangCode === 'MUNICIPAL' || abrangCode === 'BAIRRO') ? selectedMunicipio : undefined,
      bairro: abrangCode === 'BAIRRO' ? compromisso.bairro : '',
    };

    const action = compromisso.id
      ? compromissoService.updateCompromisso(payload)
      : compromissoService.createCompromisso(payload);

    const label = compromisso.id ? 'atualizado' : 'criado';

    action
      .then(() => {
        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: `Compromisso ${label} com sucesso`, life: 3000 });
      })
      .catch(() => {
        toast.current?.show({ severity: 'error', summary: 'Erro', detail: `Erro ao ${compromisso.id ? 'atualizar' : 'criar'} o compromisso`, life: 3000 });
      })
      .finally(() => {
        setCompromissoDialog(false);
        setCompromisso({ ...emptyCompromisso });
        setSubmitted(false);
        loadCompromissos();
      });
  };

  const deleteCompromisso = () => {
    if (!compromisso?.id) return;
    compromissoService
      .deleteCompromisso({ id: compromisso.id })
      .then(() => {
        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Compromisso excluído', life: 3000 });
      })
      .catch(() => {
        toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao excluir o compromisso', life: 3000 });
      })
      .finally(() => {
        setDeleteCompromissoDialog(false);
        setCompromisso({ ...emptyCompromisso });
        loadCompromissos();
      });
  };

  // ── filter ───────────────────────────────────────────────────────────────

  const handleFilterAbrangenciaChange = (selected: AbrangenciaOpcao) => {
    setFilterAbrangencia(selected);
    setLazyState((prev) => ({ ...prev, abrangencia: selected, first: 0 }));
  };

  const handleFilterTipoEmpresaChange = (selected: TipoEmpresaRef) => {
    setFilterTipoEmpresa(selected);
    setLazyState((prev) => ({
      ...prev,
      tipo_empresa_id: selected?.id ?? '',
      first: 0,
    }));
  };

  const handleFilterNaturezaChange = (selected: AbrangenciaOpcao) => {
    setFilterNatureza(selected);
    setLazyState((prev) => ({
      ...prev,
      natureza: selected?.code === 'TODOS' ? '' : selected?.code ?? '',
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

  const periodicidadeBodyTemplate = (rowData: Compromisso) => {
    const label = periodicidades.find((p) => p.code === rowData.periodicidade)?.name ?? rowData.periodicidade;
    return <span>{label}</span>;
  };

  const abrangenciaBodyTemplate = (rowData: Compromisso) => {
    const label = abrangencias.find((a) => a.code === rowData.abrangencia)?.name ?? rowData.abrangencia;
    return <span>{label}</span>;
  };

  const localizacaoBodyTemplate = (rowData: Compromisso) => {
    if (rowData.abrangencia === 'ESTADUAL' && rowData.estado?.nome) {
      return <span>{rowData.estado.nome}</span>;
    }
    if (rowData.abrangencia === 'MUNICIPAL' && rowData.municipio?.nome) {
      return <span>{rowData.municipio.nome}</span>;
    }
    if (rowData.abrangencia === 'BAIRRO') {
      const parts = [rowData.bairro, rowData.municipio?.nome].filter(Boolean);
      return <span>{parts.join(' / ')}</span>;
    }
    return <span>—</span>;
  };

  const valorBodyTemplate = (rowData: Compromisso) => {
    if (rowData.natureza !== 'FINANCEIRO') return <span>—</span>;
    if (rowData.valor == null) return <span>—</span>;
    return (
      <span>
        {rowData.valor.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })}
      </span>
    );
  };

  const naturezaBodyTemplate = (rowData: Compromisso) => {
    const label = naturezas.find((n) => n.code === rowData.natureza)?.name ?? rowData.natureza;
    return <span>{label}</span>;
  };

  const actionBodyTemplate = (rowData: Compromisso) => (
    <>
      <Button icon="pi pi-pencil" rounded severity="success" className="mr-2" onClick={() => editCompromisso(rowData)} tooltip="Editar" tooltipOptions={{ position: 'left' }} />
      <Button icon="pi pi-trash" rounded severity="warning" onClick={() => confirmDelete(rowData)} tooltip="Excluir" tooltipOptions={{ position: 'left' }} />
    </>
  );

  const currentAbrang = selectedAbrangencia?.code ?? 'FEDERAL';

  const dialogFooter = (
    <>
      <Button label="Cancelar" icon="pi pi-times" text onClick={hideDialog} />
      <Button label="Salvar" icon="pi pi-check" text onClick={saveCompromisso} />
    </>
  );

  const deleteDialogFooter = (
    <>
      <Button label="Não" icon="pi pi-times" text onClick={() => setDeleteCompromissoDialog(false)} />
      <Button label="Sim" icon="pi pi-check" text onClick={deleteCompromisso} />
    </>
  );

  const header = (
    <div className="flex flex-column md:flex-row md:justify-content-between md:align-items-center">
      <h5 className="m-0">Compromissos</h5>
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
          value={filterTipoEmpresa}
          onChange={(e) => handleFilterTipoEmpresaChange(e.value)}
          options={[tipoEmpresaFiltroTodos, ...tiposEmpresa]}
          optionLabel="descricao"
          dataKey="id"
          className="w-full md:w-16rem"
          placeholder="Tipo de Empresa"
          filter
        />
      </div>
      <div className="flex justify-content-center">
        <Dropdown
          value={filterNatureza}
          onChange={(e) => handleFilterNaturezaChange(e.value)}
          options={[naturezaFiltroTodas, ...naturezas]}
          optionLabel="name"
          className="w-full md:w-14rem"
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
              value={compromissos}
              lazy
              dataKey="id"
              paginator
              rows={rows}
              rowsPerPageOptions={[10, 20, 50]}
              className="datatable-responsive"
              paginatorTemplate={template}
              emptyMessage="Nenhum compromisso encontrado."
              header={header}
              size="small"
              stripedRows
              filterDisplay="row"
              first={lazyState.first}
              onPage={onPage}
              onSort={onSort}
              sortField={lazyState.sortField}
              sortOrder={(lazyState.sortOrder ?? 1) as 1 | 0 | -1 | null}
              loading={loading}
              totalRecords={totalRecords}
              paginatorLeft={paginatorLeft}
            >
              <Column field="descricao" header="Descrição" sortable headerStyle={{ minWidth: '16rem' }} />
              <Column field="tipoempresa.nome" header="Tipo de Empresa" sortable headerStyle={{ minWidth: '14rem' }} />
              <Column field="natureza" header="Natureza" sortable body={naturezaBodyTemplate} headerStyle={{ minWidth: '10rem' }} />
              <Column field="periodicidade" header="Periodicidade" sortable body={periodicidadeBodyTemplate} headerStyle={{ minWidth: '10rem' }} />
              <Column field="abrangencia" header="Abrangência" sortable body={abrangenciaBodyTemplate} headerStyle={{ minWidth: '10rem' }} />
              <Column header="Localização" body={localizacaoBodyTemplate} headerStyle={{ minWidth: '14rem' }} />
              <Column field="valor" header="Valor" sortable body={valorBodyTemplate} headerStyle={{ minWidth: '10rem' }} />
              <Column body={actionBodyTemplate} headerStyle={{ minWidth: '8rem' }} />
            </DataTable>

            {/* ── Create / Edit dialog ─── */}
            <Dialog
              visible={compromissoDialog}
              style={{ width: '520px' }}
              header="Compromisso"
              modal
              className="p-fluid"
              footer={dialogFooter}
              onHide={hideDialog}
            >
              <div className="field">
                <label htmlFor="ddtipoempresa">Tipo de Empresa *</label>
                <Dropdown
                  id="ddtipoempresa"
                  value={selectedTipoEmpresa}
                  options={tiposEmpresa}
                  onChange={(e) => setSelectedTipoEmpresa(e.value)}
                  optionLabel="descricao"
                  dataKey="id"
                  placeholder="Selecione um Tipo de Empresa"
                  filter
                  className={classNames({ 'p-invalid': submitted && !selectedTipoEmpresa })}
                />
                {submitted && !selectedTipoEmpresa && <small className="p-invalid">Tipo de empresa é obrigatório.</small>}
              </div>

              <div className="field">
                <label htmlFor="natureza">Natureza</label>
                <Dropdown
                  id="natureza"
                  value={selectedNatureza}
                  options={naturezas}
                  onChange={(e) => setSelectedNatureza(e.value)}
                  optionLabel="name"
                />
              </div>

              {/* Descrição */}
              <div className="field">
                <label htmlFor="descricao">Descrição *</label>
                <InputText
                  id="descricao"
                  value={compromisso.descricao ?? ''}
                  onChange={(e) => onInputChange(e, 'descricao')}
                  required
                  autoFocus
                  className={classNames({ 'p-invalid': submitted && !compromisso.descricao })}
                />
                {submitted && !compromisso.descricao && <small className="p-invalid">Descrição é obrigatória.</small>}
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

              {/* Município – MUNICIPAL or BAIRRO */}
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

              {/* Bairro – only BAIRRO */}
              {currentAbrang === 'BAIRRO' && (
                <div className="field">
                  <label htmlFor="bairro">Bairro (opcional)</label>
                  <InputText
                    id="bairro"
                    value={compromisso.bairro ?? ''}
                    onChange={(e) => onInputChange(e, 'bairro')}
                    placeholder="Ex: Alphaville"
                  />
                </div>
              )}

              {/* Valor */}
              {selectedNatureza?.code === 'FINANCEIRO' && (
                <div className="field">
                  <label htmlFor="valor">Valor (opcional)</label>
                  <InputNumber
                    id="valor"
                    value={compromisso.valor ?? null}
                    onValueChange={(e) => setCompromisso((prev) => ({ ...prev, valor: e.value ?? undefined }))}
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
                  value={compromisso.observacao ?? ''}
                  onChange={(e) => onInputChange(e, 'observacao')}
                  rows={3}
                  placeholder="Informações adicionais sobre este compromisso"
                />
              </div>
            </Dialog>

            {/* ── Delete confirm dialog ─── */}
            <Dialog
              visible={deleteCompromissoDialog}
              style={{ width: '450px' }}
              header="Confirmar Exclusão"
              modal
              footer={deleteDialogFooter}
              onHide={() => setDeleteCompromissoDialog(false)}
            >
              <div className="flex align-items-center justify-content-center">
                <i className="pi pi-exclamation-triangle mr-3 compromisso-delete-icon" />
                {compromisso && (
                  <span>
                    Deseja excluir o compromisso <b>{compromisso.descricao}</b>?
                  </span>
                )}
              </div>
            </Dialog>
          </div>
        </div>
      </div>
      <style jsx>{`
        .compromisso-page-ellipsis {
          user-select: none;
        }

        .compromisso-current-page-report {
          color: var(--text-color);
          user-select: none;
        }

        .compromisso-delete-icon {
          font-size: 2rem;
          color: #d6551e;
        }
      `}</style>
    </>
  );
};

export default CompromissosFinanceiros;

export const getServerSideProps = withAuthServerSideProps(async (_ctx: GetServerSidePropsContext) => {
  // sem processamento adicional
});
