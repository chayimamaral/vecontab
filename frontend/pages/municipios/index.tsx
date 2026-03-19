import { Button } from 'primereact/button';
import { Column } from 'primereact/column';
import { DataTable, DataTableFilterMeta } from 'primereact/datatable';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
import { Toast } from 'primereact/toast';
import { Toolbar } from 'primereact/toolbar';
import { classNames } from 'primereact/utils';
import React, { useEffect, useRef, useState } from 'react';
import MunicipioService from '../../services/cruds/MunicipioService';
import { canSSRAuth } from '../../components/utils/canSSRAuth';
//import { setupAPIClient } from '../services/api';
import setupAPIClient from '../../components/api/api';
import { Vec } from '../../types/types';

import { Dropdown } from 'primereact/dropdown';
import EstadoService from '../../services/cruds/EstadoService';

interface LazyTableState {
    totalRecords: number;
    first: number;
    rows: number;
    page: number;
    sortField?: string;
    sortOrder?: number;
    filters: DataTableFilterMeta;
}

const Municipios = () => {

    let emptyMunicipio: Vec.Cidade = {
        id: '',
        nome: '',
        codigo: '',
        ufid: '',
        uf: { nome: '' }
    };


    const [municipios, setMunicipios] = useState([]);
    const [municipioDialog, setMunicipioDialog] = useState(false);
    const [deleteMunicipioDialog, setDeleteMunicipioDialog] = useState(false);
    const [municipio, setMunicipio] = useState<Vec.Cidade>(emptyMunicipio);
    const [submitted, setSubmitted] = useState(false);
    const [globalFilter, setGlobalFilter] = useState<string>('');
    const toast = useRef<Toast>(null);
    const dt = useRef<DataTable<Vec.Cidade[]>>(null);

    const [estados, setEstados] = useState<Vec.Estado[]>([]);

    const [estado, setEstado] = useState<Vec.Estado>();

    const [loading, setLoading] = useState<boolean>(false);
    const [first, setFirst] = useState(0);
    const [rows, setRows] = useState(20);
    const [currentPage, setCurrentPage] = useState(1);
    const [sortOrder, setSortOrder] = useState(1);
    const [sortField, setSortField] = useState('nome');
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
            nome: { value: '', matchMode: 'contains' },
            codigo: { value: '', matchMode: 'contains' },
            municipio: { value: '', matchMode: 'contains' },
        }
    });


    useEffect(() => {
        loadLazyEstados();
        loadLazyMunicipio();
    }, [lazyState]);

    const municipioService = MunicipioService();

    const loadLazyMunicipio = () => {
        setLoading(true);

        municipioService.getMunicipios({ lazyEvent: JSON.stringify(lazyState) }).then(({ data }) => {
            setMunicipios(data.municipios);
            setTotalRecords(data.totalRecords);
        }).finally(() => setLoading(false));

    }

    const loadLazyEstados = () => {
        const estadoService = EstadoService();
        estadoService.getUFCidade().then(({ data }) => {
            setEstados(data?.estados);
        });
    }

    function handleClear(e): void {
        if (!e.target.value) {
            setLazyState({ ...lazyState, filters: { nome: { value: '', matchMode: 'contains' } } });
        }
    }

    const paginatorLeft = <Button type="button" icon="pi pi-refresh" tooltip='Atualizar' className="p-button-text" onClick={loadLazyMunicipio} />;


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
        setMunicipio(emptyMunicipio);
        setSubmitted(false);
        setMunicipioDialog(true);
    };

    const hideDialog = () => {
        setSubmitted(false);
        setMunicipioDialog(false);
    };

    const hideDeleteMunicipioDialog = () => {
        setDeleteMunicipioDialog(false);
    };



    function handleBuscaMunicipio(event, value: string): void {
        if (event.key === 'Enter') {
            if (value !== '') {
                setLazyState({ ...lazyState, filters: { nome: { value: value, matchMode: 'contains' } } });
            } else {
                setLazyState({ ...lazyState, filters: { nome: { value: '', matchMode: 'contains' } } });
            }
        }
    }

    const saveMunicipio = (event) => {

        municipio['ufid'] = estado?.id;

        setSubmitted(true);

        if (municipio?.nome?.trim()) {
            let _municipio = { ...municipio };

            if (municipio.id) {
                municipioService.updateMunicipio(_municipio)
                    .then(({ data }) => {
                        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Municipio Atualizado', life: 3000 });
                    })
                    .finally(() => {
                        //setLoading(false);
                        setMunicipioDialog(false);
                        setMunicipio(emptyMunicipio);
                        loadLazyMunicipio();
                    });
            } else {
                municipioService.createMunicipio(_municipio)
                    .then((data) => {
                        if (data && data.data) {
                            setMunicipios(data.data.municipios);
                            setTotalRecords(data.data.totalRecords);
                        }
                        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Municipio Criado', life: 3000 });
                    })
                    .finally(() => {
                        //setLoading(false);
                        setMunicipioDialog(false);
                        setMunicipio(emptyMunicipio);
                        loadLazyMunicipio();
                    });
            }
        }
        setSubmitted(false);
    };

    const editMunicipio = (municipio: Vec.Cidade) => {
        setEstado(municipio.uf)
        setMunicipio({ ...municipio });
        setMunicipioDialog(true);
    };

    const confirmDeleteMunicipio = (municipio: Vec.Cidade) => {
        setMunicipio(municipio);
        setDeleteMunicipioDialog(true);
    };

    const deleteMunicipio = (event) => {
        setSubmitted(true);

        if (municipio?.nome?.trim()) {
            let _municipio = { ...municipio };

            if (municipio.id) {
                municipioService.deleteMunicipio(_municipio)
                    .then(() => {
                        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Municipio Excluído', life: 3000 });
                    })
                    .finally(() => {
                        setDeleteMunicipioDialog(false);
                        setMunicipio(emptyMunicipio);
                        loadLazyMunicipio();
                    });
            }
        }
    };

    const exportCSV = () => {
        dt.current?.exportCSV();
    };

    const onInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>, nome: string) => {
        const val = (e.target && e.target.value) || '';
        let _municipio = { ...municipio };
        _municipio[`${nome}`] = val;

        setMunicipio(_municipio);
    };

    const leftToolbarTemplate = () => {
        return (
            <React.Fragment>
                <div className="my-2">
                    <Button label="Criar" icon="pi pi-plus" severity="success" className=" mr-2" onClick={openNew} />
                    {/* estou <Button label="Deletar" icon="pi pi-trash" severity="danger" onClick={confirmDeleteSelected} disabled={!selectedMunicipios || !selectedMunicipios.length} /> */}
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

    const codigoBodyTemplate = (rowData: Vec.Cidade) => {
        return (
            <>
                <span className="p-column-title">Código</span>
                {rowData.codigo}
            </>
        );
    };

    const estadoBodyTemplate = (rowData: Vec.Cidade) => {
        return (
            <>
                <span className="p-column-title">Estado</span>
                {rowData.uf?.nome}
            </>
        )
    }

    const nomeBodyTemplate = (rowData: Vec.Municipio) => {
        return (
            <>
                <span className="p-column-title">Nome</span>
                {rowData.nome}
            </>
        );
    };

    const actionBodyTemplate = (rowData: Vec.Municipio) => {
        return (
            <>
                <Button icon="pi pi-pencil" rounded severity="success" className="mr-2" onClick={() => editMunicipio(rowData)} />
                <Button icon="pi pi-trash" rounded severity="warning" onClick={() => confirmDeleteMunicipio(rowData)} />
            </>
        );
    };

    const header = (
        <div className="flex flex-column md:flex-row md:justify-content-between md:align-items-center">
            <h5 className="m-0">Cadastro de Municípios</h5>
            <span className="block mt-2 md:mt-0 p-input-icon-left">
                <i className="pi pi-search" />
                <InputText type="search" onKeyDown={(e) => handleBuscaMunicipio(e, e.currentTarget.value)} onChange={handleClear} placeholder="Procurar Município..." tooltip='Digite o Município e tecle Enter' tooltipOptions={{ position: 'left' }} />
            </span>
        </div>
    );

    const municipioDialogFooter = (
        <>
            <Button label="Cancelar" icon="pi pi-times" text onClick={hideDialog} />
            <Button label="Salvar" icon="pi pi-check" text onClick={saveMunicipio} />
        </>
    );

    const deleteMunicipioDialogFooter = (
        <>
            <Button label="Não" icon="pi pi-times" text onClick={hideDeleteMunicipioDialog} />
            <Button label="Sim" icon="pi pi-check" text onClick={deleteMunicipio} />
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
                        value={municipios}
                        lazy
                        dataKey="id"
                        paginator
                        rows={rows}
                        rowsPerPageOptions={[10, 20, 30]}
                        className="datatable-responsive"
                        paginatorTemplate={template}
                        globalFilter={globalFilter}
                        emptyMessage="Nenhum Município encontrado."
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
                        <Column field="nome" header="Nome" sortable body={nomeBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
                        <Column field="codigo" header="Código" sortable body={codigoBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
                        <Column field="estado" header="Estado" sortable body={estadoBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
                        <Column body={actionBodyTemplate} headerStyle={{ minWidth: '10rem' }}></Column>
                    </DataTable>

                    <Dialog visible={municipioDialog} style={{ width: '450px' }} header="Detalhe do Municipio" modal className="p-fluid" footer={municipioDialogFooter} onHide={hideDialog}>
                        <div className="field">
                            <label htmlFor="nome">Nome</label>
                            <InputText id="nome" value={municipio.nome} type='text' onChange={(e) => onInputChange(e, 'nome')} required autoFocus className={classNames({ 'p-invalid': submitted && !municipio.nome })} />
                            {submitted && !municipio.nome && <small className="p-invalid">Nome do Municipio é obrigatório.</small>}
                        </div>

                        <div className="field">
                            <label htmlFor="codigo">Código</label>
                            <InputText id="codigo" value={municipio.codigo?.toUpperCase()} type='text' onChange={(e) => onInputChange(e, 'codigo')} required className={classNames({ 'p-invalid': submitted && !municipio.codigo })} />
                            {submitted && !municipio.codigo && <small className="p-invalid">Código do Municipio é obrigatório.</small>}
                        </div>

                        <div className="field">
                            <label htmlFor="estado">Estado</label>
                            <span className="p-float-label">
                                <Dropdown id="dropdown" options={estados} value={estado} onChange={(e) => setEstado(e.value)} optionLabel="nome"></Dropdown>
                                {/* <label htmlFor="dropdown">Estado</label> */}
                            </span>
                        </div>

                    </Dialog>

                    <Dialog visible={deleteMunicipioDialog} style={{ width: '450px' }} header="Confirma exclusão?" modal footer={deleteMunicipioDialogFooter} onHide={hideDeleteMunicipioDialog} className="red-header">
                        <div className="flex align-items-center justify-content-center">
                            <i className="pi pi-exclamation-triangle mr-3" style={{ fontSize: '2rem', color: '#d6551e' }} />
                            {municipio && (
                                <span>
                                    Tem certeza que quer deletar <b>{municipio.nome}</b>?
                                </span>
                            )}
                        </div>
                    </Dialog>

                </div>
            </div>
        </div>
    );
};

export default Municipios;

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
