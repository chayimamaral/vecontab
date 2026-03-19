import React, { useEffect, useRef, useState } from 'react';
import { classNames } from 'primereact/utils';
import { withAuthServerSideProps } from '../../components/utils/crudUtils';
import { DataTable, DataTableFilterMeta } from 'primereact/datatable';
import FeriadoService from '../../services/cruds/FeriadoService';
import { Toast } from 'primereact/toast';
import { Button } from 'primereact/button';
import PaginatorLeft from './PaginatorLeft';
import { Dropdown } from 'primereact/dropdown';
import { InputText } from 'primereact/inputtext';
import { Toolbar } from 'primereact/toolbar';
import { Column } from 'primereact/column';
import { Dialog } from 'primereact/dialog';
import MunicipioService from '../../services/cruds/MunicipioService';
import EstadoService from '../../services/cruds/EstadoService';

interface TipoFeriado {
  name: string;
  code: string;
}

interface Feriados {
  id: string;
  descricao: string;
  feriado: string;
  data: string;
  municipio: Municipio;
  estado: Estado;
}

interface Municipio {
  id: string;
  nome: string;
}

interface Estado {
  id: string;
  nome: string;
}

interface LazyTableState {
  totalRecords: number;
  first: number;
  rows: number;
  page: number;
  sortField?: string;
  sortOrder?: number;
  filters: DataTableFilterMeta;
  holiday: TipoFeriado;
}

const Feriados = () => {

  let emptyFeriado: Feriados = {
    id: '',
    descricao: '',
    feriado: '',
    data: '',
    municipio: {
      id: '',
      nome: ''
    },
    estado: {
      id: '',
      nome: ''
    }
  };

  let emptyEstado: Estado = {
    id: '',
    nome: ''
  }

  let emptyMunicipio: Municipio = {
    id: '',
    nome: ''
  }


  const [feriados, setFeriados] = useState<Feriados[]>([]);
  const [feriado, setFeriado] = useState<Feriados>(emptyFeriado);
  const [feriadoDialog, setFeriadoDialog] = useState(false);
  const [first, setFirst] = useState(0);
  const [rows, setRows] = useState(20);
  const [currentPage, setCurrentPage] = useState(1);
  const [totalRecords, setTotalRecords] = useState<number>(0);
  const [sortOrder, setSortOrder] = useState(1);
  const [sortField, setSortField] = useState('descricao');
  const emptyTipoFeriado: TipoFeriado = {
    name: '',
    code: ''
  };
  const [loading, setLoading] = useState<boolean>(false);
  const toast = useRef<Toast>(null);
  const [pageInputTooltip, setPageInputTooltip] = useState('');
  const [deleteFeriadoDialog, setDeleteFeriadoDialog] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [globalFilter, setGlobalFilter] = useState<string>('');
  const [tipo, setTipo] = useState('');
  const [municipios, setMunicipios] = useState<Municipio[]>([]);
  const [municipio, setMunicipio] = useState<Municipio>();
  const [estados, setEstados] = useState<Estado[]>([]);
  const [estado, setEstado] = useState<Estado>();

  const tipos = [
    { name: 'Variável', code: 'VARIAVEL' },
    { name: 'Municipal', code: 'MUNICIPAL' },
    { name: 'Estadual', code: 'ESTADUAL' },
    { name: 'Fixo', code: 'FIXO' }
  ];

  const [selectedTipo, setSelectedTipo] = useState<TipoFeriado>(tipos[0]);

  const [holiday, setHoliday] = useState<TipoFeriado>(tipos[0]);

  const [lazyState, setLazyState] = useState<LazyTableState>({
    totalRecords: totalRecords,
    first: first,
    rows: rows,
    page: currentPage,
    sortField: '',
    sortOrder: 1,
    filters: {
      descricao: { value: '', matchMode: 'contains' }
    },
    holiday: tipos[0]
  });

  const feriadoService = FeriadoService();

  useEffect(() => {
    loadLazyFeriado();
    loadLazyMunicipios();
    loadLazyEstados();
  }, [lazyState]);


  const loadLazyFeriado = () => {
    setLoading(true);
    feriadoService.getFeriados({ lazyEvent: JSON.stringify(lazyState) }).then(({ data }) => {
      setFeriados(data.feriados);
      setTotalRecords(data.totalRecords);
    })
      .catch((error) => {
        toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao carregar os feriados', life: 3000 });
      })
      .finally(() => setLoading(false));
  }

  const loadLazyMunicipios = () => {
    const municipioService = MunicipioService();
    municipioService.getMunicipiosLite().then(({ data }) => {
      setMunicipios(data?.municipios);
    })
  }

  const loadLazyEstados = () => {
    const estadoService = EstadoService();
    estadoService.getUFCidade().then(({ data }) => {
      setEstados(data?.estados);
    });
  }

  const paginatorLeft = <Button type="button" icon="pi pi-refresh" tooltip='Atualizar' className="p-button-text" onClick={loadLazyFeriado} />;

  const onPage = (event) => {
    setFirst(event.first);
    setRows(event.rows);
    setCurrentPage(event.page + 1);
    setSortOrder(event.sortOrder);
    setSortField(event.sortField);
    setHoliday(event.holiday);
    setLazyState({ ...lazyState, first: event.first, rows: event.rows, page: event.page + 1, sortField: event.sortField, sortOrder: event.sortOrder, holiday: event.holiday });
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
  }

  const onFilter = (event) => {
    event['first'] = 0;
    setLazyState(event)
  };

  const openNew = () => {
    setFeriado(emptyFeriado);
    feriado.estado = estado?.id !== undefined ? estado : emptyEstado;
    feriado.municipio = municipio?.id !== undefined ? municipio : emptyMunicipio;
    setSubmitted(false);
    setFeriadoDialog(true);
  };

  const hideDialog = () => {
    setSubmitted(false);
    setFeriadoDialog(false);
  };

  const hideDeleteFeriadoDialog = () => {
    setDeleteFeriadoDialog(false);
  };

  function handleBuscaFeriado(event, value: string): void {
    if (event.key === 'Enter') {
      if (value !== '') {
        setLazyState({ ...lazyState, filters: { descricao: { value: value, matchMode: 'contains' } } });
      } else {
        setLazyState({ ...lazyState, filters: { descricao: { value: '', matchMode: 'contains' } } });
      }
    }
  }

  function handleClear(e): void {
    if (!e.target.value) {
      setLazyState({ ...lazyState, filters: { descricao: { value: '', matchMode: 'contains' } } });
    }
  }

  const saveFeriado = (event) => {
    // alert('xegay no saveFeriado')
    setSubmitted(true);
    //below the rule is: if tipo === 'ESTADUAL' then feriado.estado = estado

    if (feriado?.descricao?.trim()) {
      let _feriado = { ...feriado, holiday };



      if (tipo === 'ESTADUAL') {
        _feriado = { ..._feriado, estado: estado !== undefined ? estado : emptyEstado };
      }
      if (tipo === 'MUNICIPAL') {
        _feriado = { ..._feriado, municipio: municipio !== undefined ? municipio : emptyMunicipio };
      }

      if (feriado.id) {
        feriadoService.updateFeriado(_feriado)
          .then(() => {
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Feriado Atualizado', life: 3000 });
          })
          .catch((error) => {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao atualizar o feriado', life: 3000 });
          })
          .finally(() => {
            //setLoading(false);
            setFeriadoDialog(false);
            setFeriado(emptyFeriado);
            loadLazyFeriado();
          });
      } else {
        feriadoService.createFeriado(_feriado)
          .then((response) => {
            if (response && response.data) {
              setFeriados(response.data.feriados);
              setTotalRecords(response.data.totalRecords);
            }
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Feriado Criado', life: 3000 });
          })
          .catch((error) => {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao criar o feriado', life: 3000 });
          })
          .finally(() => {
            //setLoading(false);
            setFeriadoDialog(false);
            setFeriado(emptyFeriado);
            loadLazyFeriado();
          });
      }
    }
    setSubmitted(false);
  };

  const editFeriado = (feriado: Feriados) => {

    setEstado(feriado.estado);
    setMunicipio(feriado.municipio);

    setFeriado({ ...feriado });
    setFeriadoDialog(true);
  };

  const confirmDeleteFeriado = (feriado: Feriados) => {
    setFeriado(feriado);
    setDeleteFeriadoDialog(true);
  };

  const deleteFeriado = (event) => {
    setSubmitted(true);

    if (feriado?.descricao?.trim()) {
      let _feriado = { ...feriado };

      if (feriado.id) {
        feriadoService.deleteFeriado(_feriado)
          .then(() => {
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Feriado Excluído', life: 3000 });
          })
          .catch((error) => {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao excluir o feriado', life: 5000 });
          })
          .finally(() => {
            setDeleteFeriadoDialog(false);
            setFeriado(emptyFeriado);
            loadLazyFeriado();
          });
      }
    }
  };

  function handleTipoChange(selectedValue) {
    setTipo(selectedValue.code);
    setSelectedTipo(selectedValue);
    setHoliday(selectedValue !== null ? selectedValue : '');
    feriado.feriado = selectedValue.code;
    setLazyState(prevState => ({
      ...prevState,
      holiday: selectedValue !== null ? selectedValue : ''

    }));
  }

  function handleEstadoChange(selectedValue) {
    setEstado(selectedValue);
    feriado.estado = selectedValue;
  }

  function handleMunicipioChange(selectedValue) {

    setMunicipio(selectedValue);
    feriado.municipio = selectedValue;
  }

  const onInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>, nome: string) => {
    const val = (e.target && e.target.value) || '';
    let _feriado = { ...feriado };
    _feriado[`${nome}`] = val;

    setFeriado(_feriado);
  };

  const leftToolbarTemplate = () => {
    return (
      <React.Fragment>
        <div className="my-2">
          <Button label="Criar" icon="pi pi-plus" severity="success" className=" mr-2" onClick={openNew} />
        </div>
      </React.Fragment>
    );
  };

  const tipoBodyTemplate = (rowData: Feriados) => {
    return (
      <>
        <span className="p-column-title">Tipo</span>
        {rowData.feriado}
      </>
    );
  };

  const descricaoBodyTemplate = (rowData: Feriados) => {
    return (
      <>
        <span className="p-column-title">Descrição</span>
        {rowData.descricao}
      </>
    );
  };

  const actionBodyTemplate = (rowData: Feriados) => {
    return (
      <>
        <Button icon="pi pi-pencil" rounded severity="success" className="mr-2" onClick={() => editFeriado(rowData)} />
        <Button icon="pi pi-trash" rounded severity="warning" onClick={() => confirmDeleteFeriado(rowData)} />
      </>
    );
  };

  const header = (
    <div className="flex flex-column md:flex-row md:justify-content-between md:align-items-center">
      <h5 className="m-0">Cadastro de Feriados</h5>
      <div className=" flex justify-content-center">
        <Dropdown value={selectedTipo} onChange={(e) => handleTipoChange(e.value)} options={tipos} optionLabel="name"
          editable className="w-full md:w-14rem" defaultValue='Variável' defaultChecked />
      </div>
      <span className="block mt-2 md:mt-0 p-input-icon-left">
        <i className="pi pi-search" />
        <InputText type="search" onKeyDown={(e) => handleBuscaFeriado(e, e.currentTarget.value)} onChange={handleClear} placeholder="Procurar Feriado..." tooltip='Digite o Feriado e tecle Enter' tooltipOptions={{ position: 'left' }} />
      </span>

    </div>
  );

  const feriadoDialogFooter = (
    <>
      <Button label="Cancelar" icon="pi pi-times" text onClick={hideDialog} />
      <Button label="Salvar" icon="pi pi-check" text onClick={saveFeriado} />
    </>
  );

  const deleteFeriadoDialogFooter = (
    <>
      <Button label="Não" icon="pi pi-times" text onClick={hideDeleteFeriadoDialog} />
      <Button label="Sim" icon="pi pi-check" text onClick={deleteFeriado} />
    </>
  );

  return (
    <div className="grid crud-demo">
      <div className="col-12">
        <div className="card">
          <Toast ref={toast} />
          <Toolbar className="mb-4" left={leftToolbarTemplate} ></Toolbar>

          <DataTable
            value={feriados}
            lazy
            dataKey="id"
            paginator
            rows={rows}
            rowsPerPageOptions={[10, 20, 30]}
            className="datatable-responsive"
            paginatorTemplate={template}
            globalFilter={globalFilter}
            emptyMessage="Nenhum feriado encontrado."
            header={header}
            size="small"
            stripedRows
            filterDisplay='row'
            first={lazyState.first}
            onPage={onPage}
            onSort={onSort}
            sortField={lazyState.sortField}
            //atenção para o padrão abaixo...sempre tem que ser assim senão não funcionayk
            sortOrder={(lazyState.sortOrder === 1) ? 1 : -1}
            onFilter={onFilter}
            loading={loading}
            totalRecords={totalRecords}
            paginatorLeft={paginatorLeft}
          >
            <Column field="descricao" header="Descrição" body={descricaoBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
            <Column field="feriado" header="Tipo" body={tipoBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
            <Column field="data" header="Data" headerStyle={{ minWidth: '15rem' }}></Column>
            {tipo === 'MUNICIPAL' && (
              <Column field="municipio.nome" header="Municipio" headerStyle={{ minWidth: '15rem' }}></Column>
            )}
            {tipo === 'ESTADUAL' && (
              <Column field="estado.nome" header="Estado" headerStyle={{ minWidth: '15rem' }}></Column>
            )}
            <Column body={actionBodyTemplate} headerStyle={{ minWidth: '10rem' }}></Column>
          </DataTable>

          <Dialog visible={feriadoDialog} style={{ width: '450px' }} header="Detalhe do Feriado" modal className="p-fluid" footer={feriadoDialogFooter} onHide={hideDialog}>
            <div className="field">
              <label htmlFor="descricao">Descrição</label>
              <InputText id="descricao" value={feriado.descricao} type='text' onChange={(e) => onInputChange(e, 'descricao')} required autoFocus className={classNames({ 'p-invalid': submitted && !feriado.descricao })} />
              {submitted && !feriado.descricao && <small className="p-invalid">Descrição do Feriado é obrigatório.</small>}
            </div>

            <div className="field">
              <label htmlFor="data">Data</label>
              <InputText id="data" value={feriado.data?.toUpperCase()} type='text' onChange={(e) => onInputChange(e, 'data')} required className={classNames({ 'p-invalid': submitted && !feriado.descricao })} />
              {submitted && !feriado.data && <small className="p-invalid">Data do Feriado é obrigatório.</small>}
            </div>

            {tipo === 'MUNICIPAL' && (
              <div className="field">
                <label htmlFor="ddmunicipio">Municipio</label>
                <span className='p-float-label'>
                  <Dropdown
                    id="ddmunicipio"
                    value={municipio}
                    options={municipios}
                    onChange={(e) => handleMunicipioChange(e.value)}
                    optionLabel='nome'
                    dataKey='id'

                  //dplaceholder="Selecione um Município"
                  />
                  {submitted && !feriado.municipio && <small className="p-invalid">Municipio do Feriado é obrigatório.</small>}
                </span>
              </div>
            )}

            {tipo === 'ESTADUAL' && (
              <div className="field">
                <label htmlFor="ddestado">Estado</label>
                <span className="p-float-label">
                  <Dropdown id="ddestado" value={estado} options={estados} onChange={(e) => handleEstadoChange(e.value)} optionLabel="nome" placeholder='Selecione um Estado'></Dropdown>
                  {submitted && !feriado.estado && <small className="p-invalid">Estado do Feriado é obrigatório.</small>}
                  {/* <label htmlFor="dropdown">Estado</label> */}
                </span>
              </div>
            )}

          </Dialog>

          <Dialog visible={deleteFeriadoDialog} style={{ width: '450px' }} header="Confirma a exclusão ?" modal footer={deleteFeriadoDialogFooter} onHide={hideDeleteFeriadoDialog} className="red-header">
            <div className="flex align-items-center justify-content-center">
              <i className="pi pi-exclamation-triangle mr-3" style={{ fontSize: '2rem', color: '#d6551e' }} />
              {feriado && (
                <span>
                  Tem certeza que quer deletar <b>{feriado.descricao}</b>?
                </span>
              )}
            </div>
          </Dialog>

        </div>
      </div>
    </div>
  );

}



export default Feriados;

export const getServerSideProps = withAuthServerSideProps(async (ctx) => {
  // Aqui não é necessário nenhum processamento adicional
});
