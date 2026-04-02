import { Button } from 'primereact/button';
import { Column } from 'primereact/column';
import { DataTable, DataTableFilterMeta, DataTableFilterMetaData } from 'primereact/datatable';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
import { InputTextarea } from 'primereact/inputtextarea';
import { Toast } from 'primereact/toast';
import { Toolbar } from 'primereact/toolbar';
import { classNames } from 'primereact/utils';
import { InputMask } from "primereact/inputmask";
import React, { SyntheticEvent, lazy, useEffect, useRef, useState } from 'react';
import { Vec } from '../../types/types';

import { Dropdown } from 'primereact/dropdown';
import { withAuthServerSideProps } from '../../components/utils/crudUtils';
import CnaeService from '../../services/cruds/CnaeService';
import { FormEvent } from 'primereact/ts-helpers';

/** Máscara IBGE: XX.XX-X/XX (7 dígitos). */
function formatSubclasseCNAE(raw: string): string {
  const d = (raw ?? '').replace(/\D/g, '');
  if (d.length !== 7) return (raw ?? '').trim();
  return `${d.slice(0, 2)}.${d.slice(2, 4)}-${d.slice(4, 5)}/${d.slice(5)}`;
}

interface LazyTableState {
  totalRecords: number;
  first: number;
  rows: number;
  page: number;
  sortField?: string;
  sortOrder?: number;
  filters: DataTableFilterMeta;
}

const Cnae = () => {

  let emptyCnae: Vec.CNAE = {
    id: '',
    secao: '',
    divisao: '',
    grupo: '',
    classe: '',
    subclasse: '',
    denominacao: ''
  };

  const [cnaes, setCnaes] = useState([]);
  const [cnaeDialog, setCnaeDialog] = useState(false);
  const [deleteCnaeDialog, setDeleteCnaeDialog] = useState(false);
  const [cnae, setCnae] = useState<Vec.CNAE>(emptyCnae);
  const [submitted, setSubmitted] = useState(false);
  /** Texto do campo de busca (controlado); Enter aplica em lazyState.filters. */
  const [buscaTexto, setBuscaTexto] = useState('');
  const toast = useRef<Toast>(null);

  const [loading, setLoading] = useState<boolean>(false);
  const [first, setFirst] = useState(0);
  const [rows, setRows] = useState(20);
  const [currentPage, setCurrentPage] = useState(1);
  const [sortOrder, setSortOrder] = useState(1);
  const [sortField, setSortField] = useState('denominacao');
  const paginatorRight = <Button type="button" icon="pi pi-cloud" className="p-button-text" />;
  const [pageInputTooltip, setPageInputTooltip] = useState('');

  const [totalRecords, setTotalRecords] = useState<number>(0);
  /** Campos de hierarquia/denominação travados quando preenchidos pelo catálogo IBGE. */
  const [hierarquiaIbge, setHierarquiaIbge] = useState(false);
  const prevSubDigitosRef = useRef<string>('');
  const [lazyState, setLazyState] = useState<LazyTableState>({
    totalRecords: totalRecords,
    first: first,
    rows: rows,
    page: currentPage,
    sortField: 'denominacao',
    sortOrder: 1,
    filters: {},
  });

  useEffect(() => {
    loadLazyCnae();
  }, [lazyState]);

  const cnaeService = CnaeService();

  const loadLazyCnae = () => {
    setLoading(true);
    cnaeService.getCnaes({ lazyEvent: JSON.stringify(lazyState) }).then(({ data }) => {
      setCnaes(data.cnaes);
      setTotalRecords(data.totalRecords);
    })
      .catch((error) => {
        toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao carregar CNAEs', life: 3000 });
      })
      .finally(() => setLoading(false));

  }
  const paginatorLeft = <Button type="button" icon="pi pi-refresh" tooltip='Atualizar' className="p-button-text" onClick={loadLazyCnae} />;

  const onPage = (event) => {
    setFirst(event.first);
    setRows(event.rows);
    setCurrentPage(event.page + 1);
    setSortOrder(event.sortOrder);
    setSortField(event.sortField ?? 'denominacao');
    setLazyState((prev) => ({
      ...prev,
      first: event.first,
      rows: event.rows,
      page: event.page + 1,
      sortField: event.sortField ?? prev.sortField,
      sortOrder: event.sortOrder ?? prev.sortOrder,
      filters: event.filters && Object.keys(event.filters).length > 0 ? event.filters : prev.filters,
    }));
  };

  const onPageInputKeyDown = (event, options) => {
    if (event.key === 'Enter') {
      const page = currentPage;
      if (page < 1 || page > options.totalPages) {
        setPageInputTooltip(`Valor deve estar entre 1 e ${options.totalPages}.`);
      }
      else {
        const first = currentPage ? options.rows * (page - 1) : 0;

        setFirst(options.first);
        setRows(options.rows);
        setCurrentPage(page);
        setLazyState({ ...lazyState, first: first, rows: options.rows, page: currentPage });
      }
    }

  }

  const onPageInputChange = (event) => {
    setCurrentPage(event.target.value);
  }

  const template = {
    layout: 'PrevPageLink PageLinks NextPageLink RowsPerPageDropdown CurrentPageReport',
    'PrevPageLink': (options) => {
      return (
        <button type="button" className={options.className} onClick={options.onClick} disabled={options.disabled}>
          <span className="p-3">Página anterior</span>
        </button>
      )
    },
    'NextPageLink': (options) => {
      return (
        <button type="button" className={options.className} onClick={options.onClick} disabled={options.disabled}>
          <span className="p-3">Próxima página</span>
        </button>
      )
    },
    'PageLinks': (options) => {
      if ((options.view.startPage === options.page && options.view.startPage !== 0) || (options.view.endPage === options.page && options.page + 1 !== options.totalPages)) {
        const className = classNames(options.className, { 'p-disabled': true });

        return <span className={className} style={{ userSelect: 'none' }}>...</span>;
      }

      return (
        <button type="button" className={options.className} onClick={options.onClick}>
          {options.page + 1}
        </button>
      )
    },
    'RowsPerPageDropdown': (options) => {
      const dropdownOptions = [
        { label: 10, value: 10 },
        { label: 20, value: 20 },
        { label: 50, value: 50 }
      ];

      return <Dropdown value={options.value} options={dropdownOptions} onChange={options.onChange} />;
    },
    'CurrentPageReport': (options) => {
      return (
        <span className="mx-3" style={{ color: 'var(--text-color)', userSelect: 'none' }}>
          Página <InputText className="ml-1" value={currentPage.toString()} tooltip={pageInputTooltip}
            onKeyDown={(e) => onPageInputKeyDown(e, options)} onChange={onPageInputChange} />
        </span>
      )
    }
  };



  const onSort = (event) => {
    setFirst(0);
    setCurrentPage(1);
    setSortOrder(event.sortOrder);
    setSortField(event.sortField ?? 'denominacao');
    setLazyState((prev) => ({
      ...event,
      first: 0,
      page: 1,
      filters: prev.filters,
    }));
  };

  const onFilter = (event) => {
    setLazyState((prev) => ({
      ...event,
      first: 0,
      filters: event.filters ?? prev.filters,
    }));
  };

  const openNew = () => {
    prevSubDigitosRef.current = '';
    setHierarquiaIbge(false);
    setCnae(emptyCnae);
    setSubmitted(false);
    setCnaeDialog(true);
  };

  const hideDialog = () => {
    setSubmitted(false);
    setHierarquiaIbge(false);
    setCnaeDialog(false);
  };

  const hideDeleteCnaeDialog = () => {
    setDeleteCnaeDialog(false);
  };

  const saveCnae = (event) => {
    setSubmitted(true);

    const subDigits = (cnae?.subclasse ?? '').replace(/\D/g, '');
    if (subDigits.length !== 7) {
      toast.current?.show({ severity: 'warn', summary: 'Validação', detail: 'Subclasse deve ter 7 dígitos.', life: 3500 });
      setSubmitted(false);
      return;
    }

    const _cnae = {
      ...cnae,
      subclasse: subDigits,
    };

    const msgErro = (padrao: string, err: unknown) => {
      const ax = err as { response?: { data?: string | { error?: string; message?: string } } };
      const d = ax?.response?.data;
      const texto = typeof d === 'string' ? d : (d?.error ?? d?.message ?? padrao);
      toast.current?.show({ severity: 'error', summary: 'Erro', detail: texto, life: 5000 });
    };

    if (cnae.id) {
      cnaeService.updateCnae(_cnae)
        .then((response) => {
          const { cnaes, totalRecords } = response.data;
          setCnaes(cnaes);
          setTotalRecords(totalRecords);
          toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'CNAE Atualizado', life: 3000 });
        })
        .catch((error) => msgErro('Erro ao atualizar o CNAE', error))
        .finally(() => {
          setCnaeDialog(false);
          setCnae(emptyCnae);
          setHierarquiaIbge(false);
          loadLazyCnae();
          setSubmitted(false);
        });
    } else {
      cnaeService.createCnae(_cnae)
        .then((response) => {
          const { cnaes, totalRecords } = response.data;
          setCnaes(cnaes);
          setTotalRecords(totalRecords);
          toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'CNAE Criado', life: 3000 });
        })
        .catch((error) => msgErro('Erro ao criar CNAE', error))
        .finally(() => {
          setCnaeDialog(false);
          setCnae(emptyCnae);
          setHierarquiaIbge(false);
          loadLazyCnae();
          setSubmitted(false);
        });
    }
  };

  const deleteCnae = (event) => {
    setSubmitted(true);

    if (cnae.id) {
      let _cnae = { ...cnae };
      cnaeService.deleteCnae(_cnae)
        .then((response) => {
          const { cnaes, totalRecords } = response.data;
          setCnaes(cnaes);
          setTotalRecords(totalRecords);
          toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'CNAE Excluído', life: 3000 });
        })
        .catch((error) => {
          toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao excluir CNAE', life: 5000 });
        })
        .finally(() => {
          setDeleteCnaeDialog(false);
          setCnae(emptyCnae);
          loadLazyCnae();
        });
    }
  };


  const editCnae = (row: Vec.CNAE) => {
    prevSubDigitosRef.current = (row.subclasse ?? '').replace(/\D/g, '');
    setHierarquiaIbge(false);
    setCnae({
      ...row,
      subclasse: formatSubclasseCNAE(row.subclasse ?? ''),
    });
    setCnaeDialog(true);
  };

  useEffect(() => {
    if (!cnaeDialog) return;
    const d = (cnae.subclasse ?? '').replace(/\D/g, '');
    if (d.length !== 7) return;
    if (d === prevSubDigitosRef.current) return;
    prevSubDigitosRef.current = d;
    let cancel = false;
    cnaeService.resolveCnae(d).then(({ data }) => {
      if (cancel || !data?.found) return;
      setHierarquiaIbge(true);
      setCnae((prev) => ({
        ...prev,
        secao: data.secao ?? '',
        divisao: data.divisao ?? '',
        grupo: data.grupo ?? '',
        classe: data.classe ?? '',
        denominacao: data.denominacao ?? '',
      }));
    }).catch(() => { /* silencioso: código fora do catálogo ou rede */ });
    return () => { cancel = true; };
  }, [cnae.subclasse, cnaeDialog]);

  const confirmDeleteCnae = (cnae: Vec.CNAE) => {
    setCnae(cnae);
    setDeleteCnaeDialog(true);
  };

  const onInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>, nome: string) => {
    const val = (e.target && e.target.value) || '';
    let _cnae = { ...cnae };
    _cnae[`${nome}`] = val;

    setCnae(_cnae);
  };

  function onSubClasseChange(e: FormEvent<string, SyntheticEvent<Element, Event>>, name: string) {
    const val = e.value;
    setHierarquiaIbge(false);
    setCnae(prevState => ({
      ...prevState,
      [name]: val
    }));
  }

  const leftToolbarTemplate = () => {
    return (
      <React.Fragment>
        <div className="my-2">
          <Button label="Criar" icon="pi pi-plus" severity="success" className=" mr-2" onClick={openNew} />
        </div>
      </React.Fragment>
    );
  };

  const descricaoBodyTemplate = (rowData: Vec.CNAE) => {
    return (
      <>
        <span className="p-column-title">Denominação</span>
        {rowData.denominacao}
      </>
    );
  };

  const subClasseBodyTemplate = (subclasse: string) => formatSubclasseCNAE(subclasse ?? '');

  const textoResumido = (t: string, max = 48) => {
    const s = (t ?? '').trim();
    if (s.length <= max) return s;
    return `${s.slice(0, max)}…`;
  };

  const secaoBodyTemplate = (rowData: Vec.CNAE) => (
    <>
      <span className="p-column-title">Seção</span>
      <span title={rowData.secao}>{textoResumido(rowData.secao ?? '')}</span>
    </>
  );
  const divisaoBodyTemplate = (rowData: Vec.CNAE) => (
    <>
      <span className="p-column-title">Divisão</span>
      <span title={rowData.divisao}>{textoResumido(rowData.divisao ?? '', 40)}</span>
    </>
  );
  const grupoBodyTemplate = (rowData: Vec.CNAE) => (
    <>
      <span className="p-column-title">Grupo</span>
      <span title={rowData.grupo}>{textoResumido(rowData.grupo ?? '', 40)}</span>
    </>
  );
  const classeBodyTemplate = (rowData: Vec.CNAE) => (
    <>
      <span className="p-column-title">Classe</span>
      <span title={rowData.classe}>{textoResumido(rowData.classe ?? '', 56)}</span>
    </>
  );

  /** Enter aplica busca. Backend usa filtro denominacao para ILIKE em hierarquia + nome + subclasse. */
  function handleBuscaCnae(event: React.KeyboardEvent<HTMLInputElement>): void {
    if (event.key !== 'Enter') return;
    const value = buscaTexto.trim();
    setFirst(0);
    setCurrentPage(1);
    if (value !== '') {
      setLazyState((prev) => {
        const filters: DataTableFilterMeta =
          prev.sortField === 'subclasse'
            ? { subclasse: { value: value.replace(/\D/g, ''), matchMode: 'contains' } }
            : { denominacao: { value, matchMode: 'contains' } };
        return { ...prev, first: 0, page: 1, filters };
      });
    } else {
      setLazyState((prev) => ({ ...prev, first: 0, page: 1, filters: {} }));
    }
  }

  const actionBodyTemplate = (rowData: Vec.CNAE) => {
    return (
      <>
        <Button icon="pi pi-pencil" rounded severity="success" className="mr-2" onClick={() => editCnae(rowData)} />
        <Button icon="pi pi-trash" rounded severity="warning" onClick={() => confirmDeleteCnae(rowData)} />
      </>
    );
  };

  const header = (
    <div className="flex flex-column md:flex-row md:justify-content-between md:align-items-center">
      <h5 className="m-0">Cadastro de CNAEs (IBGE 2.3)</h5>
      <span className="block mt-2 md:mt-0 p-input-icon-left">
        <i className="pi pi-search" />
        <InputText
          type="search"
          value={buscaTexto}
          onChange={(e) => {
            const v = e.target.value;
            setBuscaTexto(v);
            if (!v.trim()) {
              setLazyState((prev) => ({ ...prev, first: 0, page: 1, filters: {} }));
              setFirst(0);
              setCurrentPage(1);
            }
          }}
          onKeyDown={handleBuscaCnae}
          placeholder="Buscar (código, nome ou hierarquia) — Enter"
          tooltip="Ordenado por denominação: busca em todos os níveis + código. Ordenado por subclasse: filtra pelo prefixo numérico. Enter para aplicar."
          tooltipOptions={{ position: 'left' }}
        />
      </span>
    </div>
  );

  const cnaeDialogFooter = (
    <>
      <Button label="Cancelar" icon="pi pi-times" text onClick={hideDialog} />
      <Button label="Salvar" icon="pi pi-check" text onClick={saveCnae} />
    </>
  );

  const deleteCnaeDialogFooter = (
    <>
      <Button label="Não" icon="pi pi-times" text onClick={hideDeleteCnaeDialog} />
      <Button label="Sim" icon="pi pi-check" text onClick={deleteCnae} />
    </>
  );

  return (
    <div className="grid crud-demo">
      <div className="col-12">
        <div className="card">
          <Toast ref={toast} />
          <Toolbar className="mb-4" left={leftToolbarTemplate} ></Toolbar>

          <DataTable
            value={cnaes}
            lazy
            dataKey="id"
            paginator
            rows={rows}
            rowsPerPageOptions={[10, 20, 30]}
            className="datatable-responsive"
            paginatorTemplate={template}
            emptyMessage="Nenhum CNAE encontrado."
            header={header}
            size="small"
            stripedRows
            filterDisplay='row'
            first={lazyState.first}
            onPage={onPage}
            onSort={onSort}
            sortField={lazyState.sortField}
            sortOrder={(lazyState.sortOrder === 1) ? 1 : -1}
            onFilter={onFilter}
            loading={loading}
            totalRecords={totalRecords}
            paginatorLeft={paginatorLeft}
          //paginatorRight={paginatorRight}
          >
            <Column field="secao" header="Seção" sortable body={secaoBodyTemplate} headerStyle={{ minWidth: '10rem' }}></Column>
            <Column field="divisao" header="Divisão" sortable body={divisaoBodyTemplate} headerStyle={{ minWidth: '10rem' }}></Column>
            <Column field="grupo" header="Grupo" sortable body={grupoBodyTemplate} headerStyle={{ minWidth: '10rem' }}></Column>
            <Column field="classe" header="Classe" sortable body={classeBodyTemplate} headerStyle={{ minWidth: '12rem' }}></Column>
            <Column field="subclasse" header="Subclasse" sortable body={(rowData) => subClasseBodyTemplate(rowData.subclasse)} headerStyle={{ minWidth: '9rem' }}></Column>
            <Column field="denominacao" header="Denominação" sortable body={descricaoBodyTemplate} headerStyle={{ minWidth: '14rem' }}></Column>
            <Column body={actionBodyTemplate} headerStyle={{ minWidth: '10rem' }}></Column>

          </DataTable>

          <Dialog visible={cnaeDialog} style={{ width: 'min(640px, 96vw)' }} header="Detalhe do CNAE (subclasse)" modal className="p-fluid" footer={cnaeDialogFooter} onHide={hideDialog}>
            <p className="text-sm text-color-secondary mt-0 mb-3">
              Informe os 7 dígitos da subclasse: se existir no catálogo IBGE (CNAE 2.3), seção à classe e a denominação são preenchidas automaticamente no servidor e aqui.
            </p>
            <div className="field">
              <label htmlFor="cnae_secao">Seção</label>
              <InputTextarea id="cnae_secao" readOnly={hierarquiaIbge} value={cnae.secao ?? ''} rows={2} autoResize className="w-full" onChange={(e) => onInputChange(e, 'secao')} />
            </div>
            <div className="field">
              <label htmlFor="cnae_divisao">Divisão</label>
              <InputTextarea id="cnae_divisao" readOnly={hierarquiaIbge} value={cnae.divisao ?? ''} rows={2} autoResize className="w-full" onChange={(e) => onInputChange(e, 'divisao')} />
            </div>
            <div className="field">
              <label htmlFor="cnae_grupo">Grupo</label>
              <InputTextarea id="cnae_grupo" readOnly={hierarquiaIbge} value={cnae.grupo ?? ''} rows={2} autoResize className="w-full" onChange={(e) => onInputChange(e, 'grupo')} />
            </div>
            <div className="field">
              <label htmlFor="cnae_classe">Classe</label>
              <InputTextarea id="cnae_classe" readOnly={hierarquiaIbge} value={cnae.classe ?? ''} rows={2} autoResize className="w-full" onChange={(e) => onInputChange(e, 'classe')} />
            </div>
            <div className="field">
              <label htmlFor="subclasse">Subclasse (máscara IBGE)</label>
              <InputMask id="subclasse" value={cnae.subclasse} mask="99.99-9/99" onChange={(e) => onSubClasseChange(e, 'subclasse')} placeholder="99.99-9/99" required autoFocus className={classNames('w-full', { 'p-invalid': submitted && (cnae.subclasse?.replace(/\D/g, '')?.length ?? 0) !== 7 })} />
              {submitted && (cnae.subclasse?.replace(/\D/g, '')?.length ?? 0) !== 7 && (
                <small className="p-invalid">Informe os 7 dígitos da subclasse.</small>
              )}
            </div>
            <div className="field">
              <label htmlFor="denominacao">Denominação</label>
              <InputText id="denominacao" readOnly={hierarquiaIbge} value={cnae.denominacao} type="text" onChange={(e) => onInputChange(e, 'denominacao')} required className={classNames('w-full', { 'p-invalid': submitted && !cnae.denominacao?.trim() && !hierarquiaIbge })} />
              {submitted && !cnae.denominacao?.trim() && !hierarquiaIbge && (
                <small className="p-invalid">Para códigos fora do catálogo IBGE, a denominação é obrigatória.</small>
              )}
            </div>
          </Dialog>

          <Dialog visible={deleteCnaeDialog} style={{ width: '450px' }} header="Confirma a exclusão ?" modal footer={deleteCnaeDialogFooter} onHide={hideDeleteCnaeDialog} className="red-header">
            <div className="flex align-items-center justify-content-center">
              <i className="pi pi-exclamation-triangle mr-3" style={{ fontSize: '2rem', color: '#d6551e' }} />
              {cnae && (
                <span>
                  Tem certeza que quer deletar <b>{cnae.denominacao}</b>?
                </span>
              )}
            </div>
          </Dialog>

        </div>
      </div>
    </div>
  );
};

export default Cnae;


export const getServerSideProps = withAuthServerSideProps(async (ctx) => {
  // Aqui não é necessário nenhum processamento adicional
});

