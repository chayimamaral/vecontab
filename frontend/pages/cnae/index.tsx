import { Button } from 'primereact/button';
import { Column } from 'primereact/column';
import { DataTable, DataTableFilterMeta, DataTableFilterMetaData } from 'primereact/datatable';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
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
    subclasse: '',
    denominacao: ''
  };

  const [cnaes, setCnaes] = useState([]);
  const [cnaeDialog, setCnaeDialog] = useState(false);
  const [deleteCnaeDialog, setDeleteCnaeDialog] = useState(false);
  const [cnae, setCnae] = useState<Vec.CNAE>(emptyCnae);
  const [submitted, setSubmitted] = useState(false);
  const [globalFilter, setGlobalFilter] = useState<string>('');
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
  const [lazyState, setLazyState] = useState<LazyTableState>({
    totalRecords: totalRecords,
    first: first,
    rows: rows,
    page: currentPage,
    sortField: '',
    sortOrder: 1,
    filters: {}
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
    setSortField(event.sortField);
    if (sortField === 'denominacao') {
      lazyState.filters.denominacao = { value: globalFilter, matchMode: 'contains' };
    } else if (sortField === 'subclasse') {
      lazyState.filters.subclasse = { value: globalFilter, matchMode: 'contains' };
    }
    setLazyState({ ...lazyState, first: event.first, rows: event.rows, page: event.page + 1, sortField: event.sortField, sortOrder: event.sortOrder, filters: event.filters });
    setLazyState(event)
  }

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
    setLazyState(event);
  };

  const onFilter = (event) => {
    event['first'] = 0;
    setLazyState(event)
  };

  const openNew = () => {
    setCnae(emptyCnae);
    setSubmitted(false);
    setCnaeDialog(true);
  };

  const hideDialog = () => {
    setSubmitted(false);
    setCnaeDialog(false);
  };

  const hideDeleteCnaeDialog = () => {
    setDeleteCnaeDialog(false);
  };

  const saveCnae = (event) => {
    setSubmitted(true);

    if (cnae?.denominacao?.trim()) {
      let _cnae = { ...cnae };

      if (cnae.id) {
        cnaeService.updateCnae(_cnae)
          .then((response) => {
            const { cnaes, totalRecords } = response.data;
            setCnaes(cnaes);
            setTotalRecords(totalRecords);
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'CNAE Atualizado', life: 3000 });
          })
          .catch((error) => {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao atualizar o CNAE', life: 3000 });
          })
          .finally(() => {
            setCnaeDialog(false);
            setCnae(emptyCnae);
            loadLazyCnae();
          });
      } else {
        cnaeService.createCnae(_cnae)
          .then((response) => {
            const { cnaes, totalRecords } = response.data;
            setCnaes(cnaes);
            setTotalRecords(totalRecords);
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'CNAE Criado', life: 3000 });
          })
          .catch((error) => {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao criar CNAE', life: 3000 });
          })
          .finally(() => {
            setCnaeDialog(false);
            setCnae(emptyCnae);
            loadLazyCnae();
          });
      }
    }
    setSubmitted(false);
  };

  const deleteCnae = (event) => {
    setSubmitted(true);

    if (cnae.id) {
      let _cnae = { ...cnae };
      cnaeService.deleteCnae(_cnae)
        .then((response) => {
          const { cnaes, totalRecords } = response.data;
          setCnae(cnaes);
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


  const editCnae = (cnae: Vec.CNAE) => {
    setCnae({ ...cnae });
    setCnaeDialog(true);
  };

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

  const subClasseBodyTemplate = (subclasse) => {
    if (subclasse) {
      return subclasse.replace(/(\d{2})(\d{2})(\d)(\d{2})/, '$1,$2-$3/$4')
    }
    return subclasse;
  };

  function handleClear(e): void {
    if (!e.target.value) {
      setLazyState({
        ...lazyState,
        filters: {}
      });
    }
  }

  function handleBuscaCnae(event, value: string): void {
    if (event.key === 'Enter') {
      if (value !== '') {
        if (lazyState.sortField === 'denominacao') {
          lazyState.filters = {
            denominacao: { value: value, matchMode: 'contains' }
          }
        } else if (lazyState.sortField === 'subclasse') {
          lazyState.filters = {
            subclasse: { value: value, matchMode: 'contains' }
          }
        }

        setLazyState({
          ...lazyState,
        });
      } else {
        setLazyState({
          ...lazyState,
          filters: {}
        });
      }
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
      <h5 className="m-0">Cadastro de CNAEs</h5>
      <span className="block mt-2 md:mt-0 p-input-icon-left">
        <i className="pi pi-search" />
        <InputText type="search" onKeyDown={(e) => handleBuscaCnae(e, e.currentTarget.value)} onChange={handleClear} placeholder="Procurar CNAE pelo índice" tooltip='Clique no índice para fazer a busca por aquele campo...' tooltipOptions={{ position: 'left' }} />
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
            globalFilter={globalFilter}
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
            <Column field="subclasse" header="Sub Classe" sortable body={(rowData) => subClasseBodyTemplate(rowData.subclasse)} headerStyle={{ minWidth: '15rem' }}></Column>
            <Column field="denominacao" header="Denominação" sortable body={descricaoBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
            <Column body={actionBodyTemplate} headerStyle={{ minWidth: '10rem' }}></Column>

          </DataTable>

          <Dialog visible={cnaeDialog} style={{ width: '450px' }} header="Detalhe do CNAE" modal className="p-fluid" footer={cnaeDialogFooter} onHide={hideDialog}>
            <div className="field">
              <label htmlFor="subclasse">Sub Classe</label>
              <InputMask id="subclasse" value={cnae.subclasse} mask='99.99-9/99' onChange={(e) => onSubClasseChange(e, 'subclasse')} placeholder="99.99-9/99" required autoFocus className={classNames({ 'p-invalid': submitted && !cnae.subclasse })} />
              {submitted && !cnae.subclasse && <small className="p-invalid">Sub Classe do CNAE é obrigatória.</small>}
            </div>
            <div className="field">
              <label htmlFor="denominacao">Denominação</label>
              <InputText id="denominacao" value={cnae.denominacao} type='text' onChange={(e) => onInputChange(e, 'denominacao')} required className={classNames({ 'p-invalid': submitted && !cnae.denominacao })} />
              {submitted && !cnae.denominacao && <small className="p-invalid">Denominação do CNAE é obrigatória.</small>}
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

