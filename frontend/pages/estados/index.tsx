import { Button } from 'primereact/button';
import { Column } from 'primereact/column';
import { DataTable, DataTableFilterMeta } from 'primereact/datatable';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
import { Toast } from 'primereact/toast';
import { Toolbar } from 'primereact/toolbar';
import { classNames } from 'primereact/utils';
import React, { SyntheticEvent, lazy, useEffect, useRef, useState } from 'react';
import EstadoService from '../../services/cruds/EstadoService';
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

const Estados = () => {

    let emptyEstado: Vec.Estado = {
        id: '',
        nome: '',
        sigla: ''
    };

    const [estados, setEstados] = useState([]);
    const [estadoDialog, setEstadoDialog] = useState(false);
    const [deleteEstadoDialog, setDeleteEstadoDialog] = useState(false);
    const [estado, setEstado] = useState<Vec.Estado>(emptyEstado);
    const [submitted, setSubmitted] = useState(false);
    const [globalFilter, setGlobalFilter] = useState<string>('');
    const toast = useRef<Toast>(null);
    const dt = useRef<DataTable<Vec.Estado[]>>(null);

    const [loading, setLoading] = useState<boolean>(false);
    const [first, setFirst] = useState(0);
    const [rows, setRows] = useState(20);
    const [currentPage, setCurrentPage] = useState(1);
    const [totalRecords, setTotalRecords] = useState<number>(0);
    const [sortOrder, setSortOrder] = useState(1);
    const [sortField, setSortField] = useState('nome');
    const paginatorRight = <Button type="button" icon="pi pi-cloud" className="p-button-text" />;
    const [pageInputTooltip, setPageInputTooltip] = useState('');
    const [value, setValue] = useState('');

    const [lazyState, setLazyState] = useState<LazyTableState>({
        totalRecords: totalRecords,
        first: first,
        rows: rows,
        page: currentPage,
        sortField: '',
        sortOrder: 1,
        filters: {
            nome: { value: '', matchMode: 'contains' },
            sigla: { value: '', matchMode: 'contains' },
        }
    });

    useEffect(() => {
        loadLazyEstado();
    }, [lazyState]);

    const estadoService = EstadoService();

    const loadLazyEstado = () => {
        setLoading(true);
        estadoService.getEstados({ lazyEvent: JSON.stringify(lazyState) }).then(({ data }) => {
            setEstados(data.estados);
            setTotalRecords(data.totalRecords);
        })
            .catch((error) => {
                toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao carregar os estados', life: 3000 });
            })
            .finally(() => setLoading(false));

    }

    const paginatorLeft = <Button type="button" icon="pi pi-refresh" tooltip='Atualizar' className="p-button-text" onClick={loadLazyEstado} />;

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
        setEstado(emptyEstado);
        setSubmitted(false);
        setEstadoDialog(true);
    };

    const hideDialog = () => {
        setSubmitted(false);
        setEstadoDialog(false);
    };

    const hideDeleteEstadoDialog = () => {
        setDeleteEstadoDialog(false);
    };

    function handleBuscaEstado(event, value: string): void {
        if (event.key === 'Enter') {
            if (value !== '') {
                setLazyState({ ...lazyState, filters: { nome: { value: value, matchMode: 'contains' } } });
            } else {
                setLazyState({ ...lazyState, filters: { nome: { value: '', matchMode: 'contains' } } });
            }
        }
    }

    function handleClear(e): void {
        if (!e.target.value) {
            setLazyState({ ...lazyState, filters: { nome: { value: '', matchMode: 'contains' } } });
        }
    }

    const saveEstado = (event) => {
        setSubmitted(true);

        if (estado?.nome?.trim()) {
            let _estado = { ...estado };

            if (estado.id) {
                estadoService.updateEstado(_estado)
                    .then(() => {
                        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Estado Atualizado', life: 3000 });
                    })
                    .catch((error) => {
                        toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao atualizar o estado', life: 3000 });
                    })
                    .finally(() => {
                        //setLoading(false);
                        setEstadoDialog(false);
                        setEstado(emptyEstado);
                        loadLazyEstado();
                    });
            } else {
                estadoService.createEstado(_estado)
                    .then((response) => {
                        if (response && response.data) {
                            setEstados(response.data.estados);
                            setTotalRecords(response.data.totalRecords);
                        }
                        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Estado Criado', life: 3000 });
                    })
                    .catch((error) => {
                        toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao criar o estado', life: 3000 });
                    })
                    .finally(() => {
                        //setLoading(false);
                        setEstadoDialog(false);
                        setEstado(emptyEstado);
                        loadLazyEstado();
                    });
            }
        }
        setSubmitted(false);
    };

    const editEstado = (estado: Vec.Estado) => {
        setEstado({ ...estado });
        setEstadoDialog(true);
    };

    const confirmDeleteEstado = (estado: Vec.Estado) => {
        setEstado(estado);
        setDeleteEstadoDialog(true);
    };

    const deleteEstado = (event) => {
        setSubmitted(true);

        if (estado?.nome?.trim()) {
            let _estado = { ...estado };

            if (estado.id) {
                estadoService.deleteEstado(_estado)
                    .then(() => {
                        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Estado Excluído', life: 3000 });
                    })
                    .catch((error) => {
                        toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao excluir o estado', life: 5000 });
                    })
                    .finally(() => {
                        setDeleteEstadoDialog(false);
                        setEstado(emptyEstado);
                        loadLazyEstado();
                    });
            }
        }
    };

    const exportCSV = () => {
        dt.current?.exportCSV();
    };

    const onInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>, nome: string) => {
        const val = (e.target && e.target.value) || '';
        let _estado = { ...estado };
        _estado[`${nome}`] = val;

        setEstado(_estado);
    };

    const leftToolbarTemplate = () => {
        return (
            <React.Fragment>
                <div className="my-2">
                    <Button label="Criar" icon="pi pi-plus" severity="success" className=" mr-2" onClick={openNew} />
                    {/* estou <Button label="Deletar" icon="pi pi-trash" severity="danger" onClick={confirmDeleteSelected} disabled={!selectedEstados || !selectedEstados.length} /> */}
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

    const siglaBodyTemplate = (rowData: Vec.Estado) => {
        return (
            <>
                <span className="p-column-title">Sigla</span>
                {rowData.sigla}
            </>
        );
    };

    const nomeBodyTemplate = (rowData: Vec.Estado) => {
        return (
            <>
                <span className="p-column-title">Nome</span>
                {rowData.nome}
            </>
        );
    };

    const actionBodyTemplate = (rowData: Vec.Estado) => {
        return (
            <>
                <Button icon="pi pi-pencil" rounded severity="success" className="mr-2" onClick={() => editEstado(rowData)} />
                <Button icon="pi pi-trash" rounded severity="warning" onClick={() => confirmDeleteEstado(rowData)} />
            </>
        );
    };

    const header = (
        <div className="flex flex-column md:flex-row md:justify-content-between md:align-items-center">
            <h5 className="m-0">Cadastro de Estados</h5>
            <span className="block mt-2 md:mt-0 p-input-icon-left">
                <i className="pi pi-search" />
                <InputText type="search" onKeyDown={(e) => handleBuscaEstado(e, e.currentTarget.value)} onChange={handleClear} placeholder="Procurar Estado..." tooltip='Digite o Estado e tecle Enter' tooltipOptions={{ position: 'left' }} />
            </span>

            {/* <span className="block mt-2 md:mt-0 p-input-icon-left">
                <i className="pi pi-search" />
                <Button label="Procurar" icon="pi pi-search" />
            </span> */}

        </div>
    );

    const estadoDialogFooter = (
        <>
            <Button label="Cancelar" icon="pi pi-times" text onClick={hideDialog} />
            <Button label="Salvar" icon="pi pi-check" text onClick={saveEstado} />
        </>
    );

    const deleteEstadoDialogFooter = (
        <>
            <Button label="Não" icon="pi pi-times" text onClick={hideDeleteEstadoDialog} />
            <Button label="Sim" icon="pi pi-check" text onClick={deleteEstado} />
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
                        value={estados}
                        lazy
                        dataKey="id"
                        paginator
                        rows={rows}
                        rowsPerPageOptions={[10, 20, 30]}
                        className="datatable-responsive"
                        paginatorTemplate={template}
                        globalFilter={globalFilter}
                        emptyMessage="Nenhum estado encontrado."
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
                        <Column field="nome" header="Nome" sortable body={nomeBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
                        <Column field="sigla" header="Sigla" sortable body={siglaBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
                        <Column body={actionBodyTemplate} headerStyle={{ minWidth: '10rem' }}></Column>
                    </DataTable>

                    <Dialog visible={estadoDialog} style={{ width: '450px' }} header="Detalhe do Estado" modal className="p-fluid" footer={estadoDialogFooter} onHide={hideDialog}>
                        <div className="field">
                            <label htmlFor="nome">Nome</label>
                            <InputText id="nome" value={estado.nome} type='text' onChange={(e) => onInputChange(e, 'nome')} required autoFocus className={classNames({ 'p-invalid': submitted && !estado.nome })} />
                            {submitted && !estado.nome && <small className="p-invalid">Nome do Estado é obrigatório.</small>}
                        </div>

                        <div className="field">
                            <label htmlFor="sigla">Sigla</label>
                            <InputText id="sigla" value={estado.sigla?.toUpperCase()} type='text' onChange={(e) => onInputChange(e, 'sigla')} required className={classNames({ 'p-invalid': submitted && !estado.sigla })} />
                            {submitted && !estado.sigla && <small className="p-invalid">Sigla do Estado é obrigatório.</small>}
                        </div>

                    </Dialog>

                    <Dialog visible={deleteEstadoDialog} style={{ width: '450px' }} header="Confirma a exclusão ?" modal footer={deleteEstadoDialogFooter} onHide={hideDeleteEstadoDialog} className="red-header">
                        <div className="flex align-items-center justify-content-center">
                            <i className="pi pi-exclamation-triangle mr-3" style={{ fontSize: '2rem', color: '#d6551e' }} />
                            {estado && (
                                <span>
                                    Tem certeza que quer deletar <b>{estado.nome}</b>?
                                </span>
                            )}
                        </div>
                    </Dialog>

                </div>
            </div>
        </div>
    );
};

export default Estados;

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



