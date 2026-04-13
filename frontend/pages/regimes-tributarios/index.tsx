import { Button } from 'primereact/button';
import { Column } from 'primereact/column';
import { DataTable, DataTableFilterMeta, DataTableStateEvent } from 'primereact/datatable';
import { Dialog } from 'primereact/dialog';
import { Dropdown } from 'primereact/dropdown';
import { InputSwitch } from 'primereact/inputswitch';
import { InputText } from 'primereact/inputtext';
import { InputTextarea } from 'primereact/inputtextarea';
import { Toast } from 'primereact/toast';
import { Toolbar } from 'primereact/toolbar';
import { classNames } from 'primereact/utils';
import { AxiosError } from 'axios';
import React, { useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { withAuthServerSideProps } from '../../components/utils/crudUtils';
import RegimeTributarioService from '../../services/cruds/RegimeTributarioService';
import { Vec } from '../../types/types';

interface LazyTableState {
  totalRecords: number;
  first: number;
  rows: number;
  page: number;
  sortField?: string;
  sortOrder?: number;
  filters: DataTableFilterMeta;
}

const opcoesCRT = [
  { label: '1 - Simples Nacional', value: 1 },
  { label: '2 - Simples Nacional (excesso de sublimite)', value: 2 },
  { label: '3 - Lucro Presumido', value: 3 },
  { label: '4 - Lucro Real', value: 4 },
];

const opcoesApuracao = [
  { label: 'Mensal', value: 'MENSAL' },
  { label: 'Trimestral', value: 'TRIMESTRAL' },
];

function rotuloCRT(c: number | undefined) {
  const o = opcoesCRT.find((x) => x.value === c);
  return o?.label ?? String(c ?? '');
}

const RegimesTributarios = () => {
  const empty: Vec.RegimeTributario = {
    id: '',
    nome: '',
    codigo_crt: 1,
    tipo_apuracao: 'MENSAL',
    ativo: true,
    configuracao_json: {},
  };

  const [regimeDialog, setRegimeDialog] = useState(false);
  const [deleteDialog, setDeleteDialog] = useState(false);
  const [regime, setRegime] = useState<Vec.RegimeTributario>(empty);
  const [configJsonText, setConfigJsonText] = useState('{}');
  const [submitted, setSubmitted] = useState(false);
  const toast = useRef<Toast>(null);
  // PrimeReact DataTable ref (exportCSV); generics do not aceitar Vec.RegimeTributario nesta versão.
  const dt = useRef<{ exportCSV: (options?: { selectionOnly?: boolean }) => void } | null>(null);

  const [first, setFirst] = useState(0);
  const [rows, setRows] = useState(20);
  const [currentPage, setCurrentPage] = useState(1);
  const [sortOrder, setSortOrder] = useState(1);
  const [sortField, setSortField] = useState('nome');
  const [pageInputTooltip, setPageInputTooltip] = useState('');
  const [totalRecords, setTotalRecords] = useState(0);

  const [lazyState, setLazyState] = useState<LazyTableState>({
    totalRecords: 0,
    first: 0,
    rows: 20,
    page: 1,
    sortField: 'nome',
    sortOrder: 1,
    filters: {
      nome: { value: '', matchMode: 'contains' },
    },
  });

  const svc = RegimeTributarioService();

  const fetchRegimes = async (st: LazyTableState) => {
    const { data } = await svc.getRegimes({ lazyEvent: JSON.stringify(st) });
    return {
      regimes: data?.regimes ?? [],
      totalRecords: data?.totalRecords ?? 0,
    };
  };

  const { data, isFetching, refetch } = useQuery({
    queryKey: ['regimes-tributarios', lazyState],
    queryFn: () => fetchRegimes(lazyState),
  });

  const paginatorLeft = (
    <Button type="button" icon="pi pi-refresh" tooltip="Atualizar" className="p-button-text" onClick={() => refetch()} />
  );

  const apiErr = (err: unknown) =>
    (err as AxiosError<{ error?: string }>)?.response?.data?.error || (err as Error)?.message || 'Operação não concluída.';

  const onPage = (event: DataTableStateEvent) => {
    const pageIdx = event.page ?? 0;
    setFirst(event.first);
    setRows(event.rows);
    setCurrentPage(pageIdx + 1);
    setSortOrder((event.sortOrder as number | undefined) ?? 1);
    setSortField(String((event.sortField as string | undefined) ?? lazyState.sortField ?? 'nome'));
    setLazyState((prev) => ({
      ...prev,
      first: event.first,
      rows: event.rows,
      page: pageIdx + 1,
      sortField: (event.sortField as string | undefined) ?? prev.sortField,
      sortOrder: (event.sortOrder as number | undefined) ?? prev.sortOrder,
      filters: event.filters && Object.keys(event.filters).length > 0 ? event.filters : prev.filters,
    }));
  };

  const onPageInputKeyDown = (event: React.KeyboardEvent, options: { totalPages: number; rows: number; first: number }) => {
    if (event.key === 'Enter') {
      const page = currentPage;
      if (page < 1 || page > options.totalPages) {
        setPageInputTooltip(`Valor deve estar entre 1 e ${options.totalPages}.`);
      } else {
        const f = options.rows * (page - 1);
        setFirst(f);
        setRows(options.rows);
        setCurrentPage(page);
        setLazyState((prev) => ({ ...prev, first: f, rows: options.rows, page }));
      }
    }
  };

  const onPageInputChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    setCurrentPage(Number(event.target.value) || 1);
  };

  const template = {
    layout: 'PrevPageLink PageLinks NextPageLink RowsPerPageDropdown CurrentPageReport',
    PrevPageLink: (options: { className: string; onClick: () => void; disabled: boolean }) => (
      <button type="button" className={options.className} onClick={options.onClick} disabled={options.disabled}>
        <span className="p-3">Página anterior</span>
      </button>
    ),
    NextPageLink: (options: { className: string; onClick: () => void; disabled: boolean }) => (
      <button type="button" className={options.className} onClick={options.onClick} disabled={options.disabled}>
        <span className="p-3">Próxima página</span>
      </button>
    ),
    PageLinks: (options: {
      className: string;
      onClick: () => void;
      page: number;
      view: { startPage: number; endPage: number };
      totalPages: number;
    }) => {
      if (
        (options.view.startPage === options.page && options.view.startPage !== 0) ||
        (options.view.endPage === options.page && options.page + 1 !== options.totalPages)
      ) {
        const cls = classNames(options.className, { 'p-disabled': true });
        return (
          <span className={cls} style={{ userSelect: 'none' }}>
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
    RowsPerPageDropdown: (options: { value: number; onChange: (e: { value: number }) => void }) => {
      const dropdownOptions = [
        { label: 10, value: 10 },
        { label: 20, value: 20 },
        { label: 50, value: 50 },
      ];
      return <Dropdown value={options.value} options={dropdownOptions} onChange={options.onChange} />;
    },
    CurrentPageReport: (options: { totalPages: number; rows: number; first: number }) => (
      <span className="mx-3" style={{ color: 'var(--text-color)', userSelect: 'none' }}>
        Página{' '}
        <InputText
          className="ml-1"
          value={currentPage.toString()}
          tooltip={pageInputTooltip}
          tooltipOptions={{ position: 'left' }}
          onKeyDown={(e) => onPageInputKeyDown(e, options)}
          onChange={onPageInputChange}
        />
      </span>
    ),
  };

  const onSort = (event: DataTableStateEvent) => {
    setFirst(0);
    setCurrentPage(1);
    const so = (event.sortOrder as number | undefined) ?? 1;
    const sf = String((event.sortField as string | undefined) ?? 'nome');
    setSortOrder(so);
    setSortField(sf);
    setLazyState((prev) => ({
      totalRecords: prev.totalRecords,
      first: 0,
      page: 1,
      rows: prev.rows,
      sortField: sf,
      sortOrder: so,
      filters: prev.filters,
    }));
  };

  const onFilter = (event: DataTableStateEvent) => {
    setLazyState((prev) => ({
      totalRecords: prev.totalRecords,
      first: 0,
      page: 1,
      rows: event.rows ?? prev.rows,
      sortField: prev.sortField,
      sortOrder: prev.sortOrder,
      filters: event.filters ?? prev.filters,
    }));
    setFirst(0);
    setCurrentPage(1);
  };

  function handleBuscaNome(event: React.KeyboardEvent<HTMLInputElement>, value: string) {
    if (event.key === 'Enter') {
      setLazyState((prev) => ({
        ...prev,
        first: 0,
        page: 1,
        filters: { nome: { value, matchMode: 'contains' } },
      }));
      setFirst(0);
      setCurrentPage(1);
    }
  }

  function handleClearBusca(e: React.ChangeEvent<HTMLInputElement>) {
    if (!e.target.value) {
      setLazyState((prev) => ({
        ...prev,
        first: 0,
        page: 1,
        filters: { nome: { value: '', matchMode: 'contains' } },
      }));
      setFirst(0);
      setCurrentPage(1);
    }
  }

  const openNew = () => {
    setRegime({ ...empty, codigo_crt: 1, tipo_apuracao: 'MENSAL', ativo: true });
    setConfigJsonText('{}');
    setSubmitted(false);
    setRegimeDialog(true);
  };

  const hideDialog = () => {
    setSubmitted(false);
    setRegimeDialog(false);
  };

  const editRow = (row: Vec.RegimeTributario) => {
    setRegime({ ...row });
    try {
      setConfigJsonText(JSON.stringify(row.configuracao_json ?? {}, null, 2));
    } catch {
      setConfigJsonText('{}');
    }
    setSubmitted(false);
    setRegimeDialog(true);
  };

  const confirmDelete = (row: Vec.RegimeTributario) => {
    setRegime(row);
    setDeleteDialog(true);
  };

  const hideDelete = () => setDeleteDialog(false);

  const save = () => {
    setSubmitted(true);
    const nomeOk = Boolean(regime.nome?.trim());
    const crtOk = typeof regime.codigo_crt === 'number' && regime.codigo_crt >= 1 && regime.codigo_crt <= 4;
    const tipoOk = regime.tipo_apuracao === 'MENSAL' || regime.tipo_apuracao === 'TRIMESTRAL';
    if (!nomeOk || !crtOk || !tipoOk) {
      toast.current?.show({ severity: 'warn', summary: 'Validação', detail: 'Preencha nome, CRT e tipo de apuração.', life: 4000 });
      return;
    }
    let configuracao_json: Record<string, unknown>;
    try {
      configuracao_json = JSON.parse(configJsonText.trim() || '{}') as Record<string, unknown>;
    } catch {
      toast.current?.show({ severity: 'error', summary: 'JSON inválido', detail: 'Revise o campo configuração (JSON).', life: 5000 });
      return;
    }

    const payload = {
      id: regime.id,
      nome: regime.nome!.trim(),
      codigo_crt: regime.codigo_crt,
      tipo_apuracao: regime.tipo_apuracao,
      ativo: regime.ativo !== false,
      configuracao_json,
    };

    const done = () => {
      setSubmitted(false);
      setRegimeDialog(false);
      setRegime(empty);
      setConfigJsonText('{}');
      refetch();
    };

    if (regime.id) {
      svc
        .updateRegime(payload)
        .then(() => {
          toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Regime atualizado.', life: 3000 });
          done();
        })
        .catch((err) => toast.current?.show({ severity: 'error', summary: 'Erro', detail: apiErr(err), life: 5000 }));
    } else {
      svc
        .createRegime(payload)
        .then(() => {
          toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Regime criado.', life: 3000 });
          done();
        })
        .catch((err) => toast.current?.show({ severity: 'error', summary: 'Erro', detail: apiErr(err), life: 5000 }));
    }
  };

  const doDelete = () => {
    if (!regime.id) return;
    svc
      .deleteRegime({ id: regime.id })
      .then(() => {
        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Regime desativado.', life: 3000 });
        setDeleteDialog(false);
        setRegime(empty);
        refetch();
      })
      .catch((err) => toast.current?.show({ severity: 'error', summary: 'Erro', detail: apiErr(err), life: 5000 }));
  };

  const leftToolbar = () => (
    <div className="my-2">
      <Button label="Criar" icon="pi pi-plus" severity="success" className="mr-2" onClick={openNew} />
    </div>
  );

  const rightToolbar = () => (
    <Button label="Exportar" icon="pi pi-upload" severity="help" onClick={() => dt.current?.exportCSV()} />
  );

  const nomeBody = (row: Vec.RegimeTributario) => (
    <>
      <span className="p-column-title">Nome</span>
      {row.nome}
    </>
  );

  const crtBody = (row: Vec.RegimeTributario) => (
    <>
      <span className="p-column-title">CRT</span>
      {rotuloCRT(row.codigo_crt)}
    </>
  );

  const tipoBody = (row: Vec.RegimeTributario) => (
    <>
      <span className="p-column-title">Apuração</span>
      {row.tipo_apuracao === 'TRIMESTRAL' ? 'Trimestral' : 'Mensal'}
    </>
  );

  const ativoBody = (row: Vec.RegimeTributario) => (
    <>
      <span className="p-column-title">Ativo</span>
      {row.ativo ? 'Sim' : 'Não'}
    </>
  );

  const actionBody = (row: Vec.RegimeTributario) => (
    <>
      <Button icon="pi pi-pencil" rounded severity="success" className="mr-2" onClick={() => editRow(row)} />
      <Button icon="pi pi-trash" rounded severity="warning" onClick={() => confirmDelete(row)} />
    </>
  );

  const header = (
    <div className="flex flex-column md:flex-row md:justify-content-between md:align-items-center">
      <h5 className="m-0">Regime tributário</h5>
      <span className="block mt-2 md:mt-0 p-input-icon-left">
        <i className="pi pi-search" />
        <InputText
          type="search"
          onKeyDown={(e) => handleBuscaNome(e, e.currentTarget.value)}
          onChange={handleClearBusca}
          placeholder="Procurar por nome (Enter)..."
          tooltip="Digite e tecle Enter"
          tooltipOptions={{ position: 'left' }}
        />
      </span>
    </div>
  );

  const dialogFooter = (
    <>
      <Button label="Cancelar" icon="pi pi-times" text onClick={hideDialog} />
      <Button label="Salvar" icon="pi pi-check" text onClick={save} />
    </>
  );

  const deleteFooter = (
    <>
      <Button label="Não" icon="pi pi-times" text onClick={hideDelete} />
      <Button label="Sim" icon="pi pi-check" text onClick={doDelete} />
    </>
  );

  return (
    <div className="grid crud-demo">
      <div className="col-12">
        <div className="card">
          <Toast ref={toast} />
          <Toolbar className="mb-4" left={leftToolbar} right={rightToolbar} />

          <DataTable
            ref={dt as never}
            value={data?.regimes ?? []}
            lazy
            dataKey="id"
            paginator
            rows={rows}
            rowsPerPageOptions={[10, 20, 30]}
            className="datatable-responsive"
            paginatorTemplate={template as never}
            emptyMessage="Nenhum regime encontrado."
            header={header}
            size="small"
            stripedRows
            filterDisplay="row"
            first={lazyState.first}
            onPage={onPage}
            onSort={onSort}
            sortField={lazyState.sortField}
            sortOrder={lazyState.sortOrder === 1 ? 1 : -1}
            onFilter={onFilter}
            loading={isFetching}
            totalRecords={data?.totalRecords ?? totalRecords}
            paginatorLeft={paginatorLeft}
          >
            <Column field="nome" header="Nome" sortable body={nomeBody} headerStyle={{ minWidth: '14rem' }} />
            <Column field="codigo_crt" header="CRT" sortable body={crtBody} headerStyle={{ minWidth: '12rem' }} />
            <Column field="tipo_apuracao" header="Apuração" sortable body={tipoBody} headerStyle={{ minWidth: '8rem' }} />
            <Column field="ativo" header="Ativo" body={ativoBody} headerStyle={{ minWidth: '6rem' }} />
            <Column body={actionBody} headerStyle={{ minWidth: '10rem' }} />
          </DataTable>

          <Dialog
            visible={regimeDialog}
            style={{ width: 'min(520px, 95vw)' }}
            header={regime.id ? 'Editar regime' : 'Novo regime'}
            modal
            className="p-fluid"
            footer={dialogFooter}
            onHide={hideDialog}
          >
            <div className="field">
              <label htmlFor="rt_nome">Nome</label>
              <InputText
                id="rt_nome"
                value={regime.nome ?? ''}
                onChange={(e) => setRegime({ ...regime, nome: e.target.value })}
                className={classNames({ 'p-invalid': submitted && !regime.nome?.trim() })}
              />
              {submitted && !regime.nome?.trim() && <small className="p-invalid">Obrigatório.</small>}
            </div>
            <div className="field">
              <label htmlFor="rt_crt">Código CRT (federal)</label>
              <Dropdown
                inputId="rt_crt"
                value={regime.codigo_crt}
                options={opcoesCRT}
                onChange={(e) => setRegime({ ...regime, codigo_crt: e.value as number })}
                placeholder="Selecione"
              />
            </div>
            <div className="field">
              <label htmlFor="rt_apur">Tipo de apuração</label>
              <Dropdown
                inputId="rt_apur"
                value={regime.tipo_apuracao}
                options={opcoesApuracao}
                onChange={(e) => setRegime({ ...regime, tipo_apuracao: e.value as string })}
              />
            </div>
            <div className="field flex align-items-center gap-2">
              <InputSwitch checked={regime.ativo !== false} onChange={(e) => setRegime({ ...regime, ativo: Boolean(e.value) })} />
              <label htmlFor="rt_ativo">Ativo</label>
            </div>
            <div className="field">
              <label htmlFor="rt_cfg">Configuração (JSON) — obrigações sugeridas, EFDs, etc.</label>
              <InputTextarea
                id="rt_cfg"
                value={configJsonText}
                onChange={(e) => setConfigJsonText(e.target.value)}
                rows={10}
                className="w-full font-mono text-sm"
                autoResize
              />
            </div>
          </Dialog>

          <Dialog visible={deleteDialog} style={{ width: '450px' }} header="Confirma desativação?" modal footer={deleteFooter} onHide={hideDelete} className="red-header">
            <div className="flex align-items-center justify-content-center">
              <i className="pi pi-exclamation-triangle mr-3" style={{ fontSize: '2rem', color: '#d6551e' }} />
              {regime?.nome && (
                <span>
                  Desativar o regime <b>{regime.nome}</b>? Ele deixará de aparecer nas listagens.
                </span>
              )}
            </div>
          </Dialog>
        </div>
      </div>
    </div>
  );
};

export default RegimesTributarios;

export const getServerSideProps = withAuthServerSideProps(async () => undefined);
