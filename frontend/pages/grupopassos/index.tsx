import { Button } from 'primereact/button';
import { Column } from 'primereact/column';
import { DataTable, DataTableFilterMeta } from 'primereact/datatable';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
import { Toast } from 'primereact/toast';
import { Toolbar } from 'primereact/toolbar';
import { classNames } from 'primereact/utils';
import React, { useEffect, useRef, useState } from 'react';
import GrupoPassoService from '../../services/cruds/GrupoPassosService';
import MunicipioService from '../../services/cruds/MunicipioService';
import TipoEmpresaService from '../../services/cruds/TipoEmpresaService';
import { canSSRAuth } from '../../components/utils/canSSRAuth';
import setupAPIClient from '../../components/api/api';
import { Vec } from '../../types/types';

import { Dropdown } from 'primereact/dropdown';

interface LazyTableState {
  totalRecords: number;
  first: number;
  rows: number;
  page: number;
  sortField?: string;
  sortOrder?: number;
  filters: DataTableFilterMeta;
}

const GrupoPassos = () => {

  let emptyGrupoPasso: Vec.GrupoPasso = {
    id: '',
    descricao: '',
    municipio_id: '',
    municipio: { nome: '' },
    tipoempresa_id: '',
    tipoempresa: { descricao: '' },
  };


  const [grupopassos, setGrupoPassos] = useState([]);
  const [grupopassoDialog, setGrupoPassoDialog] = useState(false);

  const [municipios, setMunicipios] = useState<Vec.MunicipioLite[]>([]);
  const [municipio, setMunicipio] = useState<Vec.MunicipioLite>();

  const [tipoempresas, setTipoempresas] = useState<Vec.TipoEmpresaLite[]>([]);
  const [tipoempresa, setTipoempresa] = useState<Vec.TipoEmpresaLite>();

  const [deleteGrupoPassoDialog, setDeleteGrupoPassoDialog] = useState(false);
  const [grupopasso, setGrupoPasso] = useState<Vec.GrupoPasso>(emptyGrupoPasso);
  const [submitted, setSubmitted] = useState(false);
  const [globalFilter, setGlobalFilter] = useState<string>('');
  const toast = useRef<Toast>(null);
  const dt = useRef<DataTable<Vec.GrupoPasso[]>>(null);

  const [loading, setLoading] = useState<boolean>(false);
  const [first, setFirst] = useState(0);
  const [rows, setRows] = useState(20);
  const [currentPage, setCurrentPage] = useState(1);
  const [sortOrder, setSortOrder] = useState(1);
  const [sortField, setSortField] = useState('descricao');
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
    filters: {
      descricao: { value: '', matchMode: 'contains' },
      tipoempresa: { value: '', matchMode: 'contains' },
      municipio: { value: '', matchMode: 'contains' },
    }
  });


  useEffect(() => {
    loadLazyMunicipios();
    loadLazyTipoEmpresas();
    loadLazyGrupoPasso();
  }, [lazyState]);

  const grupopassoService = GrupoPassoService();

  const loadLazyGrupoPasso = () => {
    setLoading(true);

    grupopassoService.getGrupoPassos({ lazyEvent: JSON.stringify(lazyState) }).then(({ data }) => {
      setGrupoPassos(data.grupopassos);
      setTotalRecords(data.totalRecords);
    }).finally(() => setLoading(false));

  }

  const loadLazyMunicipios = () => {
    const municipioService = MunicipioService();
    municipioService.getMunicipiosLite().then(({ data }) => {
      setMunicipios(data?.municipios);
    })
  }

  const loadLazyTipoEmpresas = () => {
    const tipoempresaService = TipoEmpresaService();
    tipoempresaService.getTiposEmpresaLite().then(({ data }) => {
      setTipoempresas(data?.tiposEmpresa);
    })
  }


  function handleClear(e): void {
    if (!e.target.value) {
      setLazyState({ ...lazyState, filters: { descricao: { value: '', matchMode: 'contains' } } });
    }
  }

  const paginatorLeft = <Button type="button" icon="pi pi-refresh" tooltip='Atualizar' className="p-button-text" onClick={loadLazyGrupoPasso} />;

  const onPage = (event) => {
    setFirst(event.first);
    setRows(event.rows);
    setCurrentPage(event.page + 1);
    setSortOrder(event.sortOrder);
    setSortField(event.sortField);
    setLazyState({ ...lazyState, first: event.first, rows: event.rows, page: event.page + 1, sortField: event.sortField, sortOrder: event.sortOrder });
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
        { label: 50, value: 50 },
        // { label: 'Todos', value: options.totalRecords }
      ];

      return <Dropdown value={options.value} options={dropdownOptions} onChange={options.onChange} />;
    },
    'CurrentPageReport': (options) => {
      return (
        <span className="mx-3" style={{ color: 'var(--text-color)', userSelect: 'none' }}>
          Página <InputText className="ml-1" value={currentPage.toString()} tooltip={pageInputTooltip} tooltipOptions={{ position: 'left' }}
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
    setGrupoPasso(emptyGrupoPasso);
    setSubmitted(false);
    setGrupoPassoDialog(true);
  };

  const hideDialog = () => {
    setSubmitted(false);
    setGrupoPassoDialog(false);
  };

  const hideDeleteGrupoPassoDialog = () => {
    setDeleteGrupoPassoDialog(false);
  };

  function handleBuscaGrupoPasso(event, value: string): void {
    if (event.key === 'Enter') {
      if (value !== '') {
        setLazyState({ ...lazyState, filters: { descricao: { value: value, matchMode: 'contains' } } });
      } else {
        setLazyState({ ...lazyState, filters: { descricao: { value: '', matchMode: 'contains' } } });
      }
    }
  }

  const saveGrupoPasso = (event) => {

    grupopasso['municipio_id'] = municipio?.id;
    grupopasso['tipoempresa_id'] = tipoempresa?.id;

    setSubmitted(true);

    if (grupopasso?.descricao?.trim()) {
      let _grupopasso = { ...grupopasso };

      if (grupopasso.id) {
        grupopassoService.updateGrupoPassos(_grupopasso)
          .then(({ data }) => {
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'GrupoPasso Atualizado', life: 3000 });
          })
          .finally(() => {
            //setLoading(false);
            setGrupoPassoDialog(false);
            setGrupoPasso(emptyGrupoPasso);
            loadLazyGrupoPasso();
          });
      } else {
        grupopassoService.createGrupoPassos(_grupopasso)
          .then((data) => {
            if (data && data.data) {
              setGrupoPassos(data.data.grupopassos);
              setTotalRecords(data.data.totalRecords);
            }
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'GrupoPasso Criado', life: 3000 });
          })
          .finally(() => {
            //setLoading(false);
            setGrupoPassoDialog(false);
            setGrupoPasso(emptyGrupoPasso);
            loadLazyGrupoPasso();
          });
      }
    }
    setSubmitted(false);
  };

  const editGrupoPasso = (grupopasso: Vec.GrupoPasso) => {
    setMunicipio(grupopasso.municipio)
    setTipoempresa(grupopasso.tipoempresa)
    setGrupoPasso({ ...grupopasso });
    setGrupoPassoDialog(true);
  };

  const confirmDeleteGrupoPasso = (grupopasso: Vec.GrupoPasso) => {
    setGrupoPasso(grupopasso);
    setDeleteGrupoPassoDialog(true);
  };

  const editItemsGrupoPasso = (grupopasso: Vec.GrupoPasso) => {
    alert('not implemented yet!')
  }

  const deleteGrupoPasso = (event) => {
    setSubmitted(true);

    if (grupopasso?.descricao?.trim()) {
      let _grupopasso = { ...grupopasso };

      if (grupopasso.id) {
        grupopassoService.deleteGrupoPassos(_grupopasso)
          .then(() => {
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Grupo de Passos Excluído', life: 3000 });
          })
          .finally(() => {
            setDeleteGrupoPassoDialog(false);
            setGrupoPasso(emptyGrupoPasso);
            loadLazyGrupoPasso();
          });
      }
    }
  };

  const exportCSV = () => {
    dt.current?.exportCSV();
  };

  const onInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>, nome: string) => {
    const val = (e.target && e.target.value) || '';
    let _grupopasso = { ...grupopasso };
    _grupopasso[`${nome}`] = val;

    setGrupoPasso(_grupopasso);
  };

  const leftToolbarTemplate = () => {
    return (
      <React.Fragment>
        <div className="my-2">
          <Button label="Criar" icon="pi pi-plus" severity="success" className=" mr-2" onClick={openNew} />
          {/* estou <Button label="Deletar" icon="pi pi-trash" severity="danger" onClick={confirmDeleteSelected} disabled={!selectedGrupoPassos || !selectedGrupoPassos.length} /> */}
        </div>
      </React.Fragment>
    );
  };

  const rightToolbarTemplate = () => {
    return (
      <React.Fragment>
        <Button label="Exportar" icon="pi pi-upload" severity="help" onClick={exportCSV} />
      </React.Fragment>
    );
  };

  const descricaoBodyTemplate = (rowData: Vec.GrupoPasso) => {
    return (
      <>
        <span className="p-column-title">Descrição</span>
        {rowData.descricao}
      </>
    );
  };

  const municipioBodyTemplate = (rowData: Vec.GrupoPasso) => {
    return (
      <>
        <span className="p-column-title">Município</span>
        {rowData.municipio?.nome}
      </>
    );
  };

  const tipoempresaBodyTemplate = (rowData: Vec.GrupoPasso) => {
    return (
      <>
        <span className="p-column-title">Tipo de Empresa</span>
        {rowData.tipoempresa?.descricao}
      </>
    );
  };

  const actionBodyTemplate = (rowData: Vec.GrupoPasso) => {
    return (
      <>
        <Button icon="pi pi-pencil" rounded severity="success" className="mr-2" onClick={() => editGrupoPasso(rowData)} />
        <Button icon="pi pi-trash" rounded severity="warning" className="mr-2" onClick={() => confirmDeleteGrupoPasso(rowData)} />
        <Button icon="pi pi-book" rounded severity="info" onClick={() => editItemsGrupoPasso(rowData)} />
      </>
    );
  };

  const header = (
    <div className="flex flex-column md:flex-row md:justify-content-between md:align-items-center">
      <h5 className="m-0">Cadastro de Grupos de Passos</h5>
      <span className="block mt-2 md:mt-0 p-input-icon-left">
        <i className="pi pi-search" />
        <InputText type="search" onKeyDown={(e) => handleBuscaGrupoPasso(e, e.currentTarget.value)} onChange={handleClear} placeholder="Procurar Grupo de Passos..." tooltip='Digite o Grupo de Passos e tecle Enter' tooltipOptions={{ position: 'left' }} />
      </span>
    </div>
  );

  const grupopassoDialogFooter = (
    <>
      <Button label="Cancelar" icon="pi pi-times" text onClick={hideDialog} />
      <Button label="Salvar" icon="pi pi-check" text onClick={saveGrupoPasso} />
    </>
  );

  const deleteGrupoPassoDialogFooter = (
    <>
      <Button label="Não" icon="pi pi-times" text onClick={hideDeleteGrupoPassoDialog} />
      <Button label="Sim" icon="pi pi-check" text onClick={deleteGrupoPasso} />
    </>
  );

  return (
    <div className="grid crud-demo">
      <div className="col-12">
        <div className="card">
          <Toast ref={toast} />
          <Toolbar className="mb-4" left={leftToolbarTemplate} right={rightToolbarTemplate}></Toolbar>

          <DataTable
            ref={dt}
            value={grupopassos}
            lazy
            dataKey="id"
            paginator
            rows={rows}
            rowsPerPageOptions={[10, 20, 30]}
            className="datatable-responsive"
            paginatorTemplate={template}
            globalFilter={globalFilter}
            emptyMessage="Nenhum Grupo de Passos encontrado."
            header={header}
            size="small"
            stripedRows
            filterDisplay='row'
            first={lazyState.first}
            onPage={onPage}
            onSort={onSort}
            sortField={lazyState.sortField}
            //sortOrder={lazyState.sortOrder? 1 : -1}
            sortOrder={(lazyState.sortOrder === 1) ? 1 : -1}
            onFilter={onFilter}
            loading={loading}
            totalRecords={totalRecords}
            paginatorLeft={paginatorLeft}
          //paginatorRight={paginatorRight}
          >
            <Column field="descricao" header="Descrição" sortable body={descricaoBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
            <Column field="municipio" header="Municipio" sortable body={municipioBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
            <Column field="tipoempresa" header="TipoEmpresa" sortable body={tipoempresaBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
            <Column body={actionBodyTemplate} headerStyle={{ minWidth: '10rem' }}></Column>
          </DataTable>

          <Dialog visible={grupopassoDialog} style={{ width: '450px' }} header="Detalhe do Grupo de Passos" modal className="p-fluid" footer={grupopassoDialogFooter} onHide={hideDialog}>
            <div className="field">
              <label htmlFor="descricao">Descrição</label>
              <InputText id="descricao" value={grupopasso.descricao} type='text' onChange={(e) => onInputChange(e, 'descricao')} required autoFocus className={classNames({ 'p-invalid': submitted && !grupopasso.descricao })} />
              {submitted && !grupopasso.descricao && <small className="p-invalid">Descrição do Grupo de Passos é obrigatório.</small>}
            </div>

            <div className="field">
              <label htmlFor="dropdownCidade">Município</label>
              <span className="p-float-label">
                <Dropdown id="dropdownCidade" options={municipios} value={municipio} onChange={(e) => setMunicipio(e.value)} optionLabel="nome"></Dropdown>
              </span>
            </div>

            <div className="field">
              <label htmlFor="dropdownTipo">Tipo de Empresa</label>
              <span className="p-float-label">
                <Dropdown id="dropdownTipo" options={tipoempresas} value={tipoempresa} onChange={(e) => setTipoempresa(e.value)} optionLabel="descricao"></Dropdown>
              </span>
            </div>

          </Dialog>

          <Dialog visible={deleteGrupoPassoDialog} style={{ width: '450px' }} header="Confirma exclusão?" modal footer={deleteGrupoPassoDialogFooter} onHide={hideDeleteGrupoPassoDialog} className="red-header">
            <div className="flex align-items-center justify-content-center">
              <i className="pi pi-exclamation-triangle mr-3" style={{ fontSize: '2rem', color: '#d6551e' }} />
              {grupopasso && (
                <span>
                  Tem certeza que quer deletar <b>{grupopasso.descricao}</b>?
                </span>
              )}
            </div>
          </Dialog>

        </div>
      </div>
    </div>
  );
};

export default GrupoPassos;

export const getServerSideProps = canSSRAuth(async (ctx) => {
  try {
    const apiClient = setupAPIClient(ctx);
    const response = await apiClient.get('/api/registro');

    const dados = {

    };
    return {

      props: {

        dados: dados

      }
    };

  } catch (err) {
    console.log(err);

    return {
      redirect: {
        destination: '/',
        permanent: false
      }
    };
  }
});
