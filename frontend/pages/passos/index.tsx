import { Button } from 'primereact/button';
import { Column } from 'primereact/column';
import { DataTable, DataTableFilterMeta } from 'primereact/datatable';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
import { Toast } from 'primereact/toast';
import { Toolbar } from 'primereact/toolbar';
import { classNames } from 'primereact/utils';
import React, { useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { canSSRAuth } from '../../components/utils/canSSRAuth';
import setupAPIClient from '../../components/api/api';
import { Vec } from '../../types/types';

import { Dropdown } from 'primereact/dropdown';
import PassoService from '../../services/cruds/PassoService';
import { InputNumber, InputNumberChangeEvent, InputNumberValueChangeEvent } from 'primereact/inputnumber';
import { RadioButton, RadioButtonChangeEvent } from 'primereact/radiobutton';
import MunicipioService from '../../services/cruds/MunicipioService';
import { withAuthServerSideProps } from '../../components/utils/crudUtils';

interface LazyTableState {
    totalRecords: number;
    first: number;
    rows: number;
    page: number;
    sortField?: string;
    sortOrder?: number;
    filters: DataTableFilterMeta;
}

const Passos = () => {

    let emptyPasso: Vec.Passo = {
        id: '',
        descricao: '',
        tempoestimado: 0,
        tipopasso: '',
        link: '',
        municipio_id: '',
        municipio: { nome: '' }
    };

    const [passos, setPassos] = useState([]);

    const [municipio, setMunicipio] = useState<Vec.MunicipioLite>();

    const [passoDialog, setPassoDialog] = useState(false);
    const [deletePassoDialog, setDeletePassoDialog] = useState(false);
    const [passo, setPasso] = useState<Vec.Passo>(emptyPasso);
    const [submitted, setSubmitted] = useState(false);
    const [globalFilter, setGlobalFilter] = useState<string>('');
    const toast = useRef<Toast>(null);
    const dt = useRef<DataTable<Vec.Passo[]>>(null);

    const [first, setFirst] = useState(0);
    const [rows, setRows] = useState(20);
    const [currentPage, setCurrentPage] = useState(1);
    const [sortOrder, setSortOrder] = useState(1);
    const [sortField, setSortField] = useState('descricao');
    const paginatorRight = <Button type="button" icon="pi pi-cloud" className="p-button-text" />;
    const [pageInputTooltip, setPageInputTooltip] = useState('');
    const [value, setValue] = useState('');
    const [totalRecords, setTotalRecords] = useState<number>(0);

    const [lazyState, setLazyState] = useState<LazyTableState>({
        totalRecords: totalRecords,
        first: first,
        rows: rows,
        page: currentPage,
        sortField: '',
        sortOrder: 1,
        filters: {
            descricao: { value: '', matchMode: 'contains' }
        }
    });

    const tipospasso = [
        { name: 'Municipal', key: 'M' },
        { name: 'Estadual', key: 'E' },
        { name: 'Federal', key: 'F' },
        { name: 'Pessoal', key: 'P' }
    ];

    const renderTipoPasso = (rowData) => {
        const tipoPassoLabel = tipospasso.find((d) => d.key === rowData.tipopasso)?.name;

        return <span>{tipoPassoLabel}</span>;
    };

    const [selectedTipoPasso, setSelectedTipoPasso] = useState(tipospasso[0]);

    const passoService = PassoService();

    const fetchPassos = async (st: LazyTableState) => {
        const { data } = await passoService.getPassos({ lazyEvent: JSON.stringify(st) });
        return {
            passos: data?.passos ?? [],
            totalRecords: data?.totalRecords ?? 0,
        };
    };

    const { data, isFetching, refetch } = useQuery({
        queryKey: ['passos', lazyState],
        queryFn: () => fetchPassos(lazyState),
    });

    const { data: municipios = [] } = useQuery<Vec.MunicipioLite[]>({
        queryKey: ['municipios-lite'],
        queryFn: async () => {
            const municipioService = MunicipioService();
            const { data } = await municipioService.getMunicipiosLite();
            return data?.municipios ?? [];
        },
    });

    const paginatorLeft = <Button type="button" icon="pi pi-refresh" tooltip='Atualizar' className="p-button-text" onClick={() => refetch()} />;

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


    const onSort = (event) => {
        setLazyState(event);
    }

    const onFilter = (event) => {
        event['first'] = 0;
        setLazyState(event)
    };

    const openNew = () => {
        setPasso(emptyPasso);
        setSubmitted(false);
        setPassoDialog(true);
    };

    const hideDialog = () => {
        setSubmitted(false);
        setPassoDialog(false);
    };

    const hideDeletePassoDialog = () => {
        setDeletePassoDialog(false);
    };

    function handleBuscaPasso(event, value: string): void {
        if (event.key === 'Enter') {
            if (value !== '') {
                setLazyState({ ...lazyState, filters: { descricao: { value: value, matchMode: 'contains' } } });
            } else {
                setLazyState({ ...lazyState, filters: { descricao: { value: '', matchMode: 'contains' } } });
            }
        }
    }

    function onMunicipioChange(event): void {
        setMunicipio(event.value);
        setLazyState({ ...lazyState, filters: { municipio: { value: event.value, matchMode: 'contains' } } });
    }

    function handleClear(e): void {
        if (!e.target.value) {
            setLazyState({ ...lazyState, filters: { descricao: { value: '', matchMode: 'contains' } } });
        }
    }

    const savePasso = (event) => {

        passo['municipio_id'] = municipio?.id;
        setSubmitted(true);

        if (passo?.descricao?.trim()) {
            let _passo = { ...passo };

            if (passo.id) {
                passoService.updatePasso(_passo)
                    .then(() => {
                        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Passo Atualizado', life: 3000 });
                    })
                    .catch((error) => {
                        toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao atualizar o passo', life: 3000 });
                    })
                    .finally(() => {
                        //setLoading(false);
                        setPassoDialog(false);
                        setPasso(emptyPasso);
                        refetch();
                    });
            } else {
                passoService.createPasso(_passo)
                    .then((response) => {
                        if (response && response.data) {
                            setPassos(response.data.passos);
                            setTotalRecords(response.data.totalRecords);
                        }
                        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Passo Criado', life: 3000 });
                    })
                    .catch((error) => {
                        toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao criar o passo', life: 3000 });
                    })
                    .finally(() => {
                        //setLoading(false);
                        setPassoDialog(false);
                        setPasso(emptyPasso);
                        refetch();
                    });
            }
        }
        setSubmitted(false);
    };

    const editPasso = (passo: Vec.Passo) => {
        setMunicipio(passo.municipio)
        setPasso({ ...passo });
        setPassoDialog(true);
    };

    const confirmDeletePasso = (passo: Vec.Passo) => {
        setPasso(passo);
        setDeletePassoDialog(true);
    };

    const deletePasso = (event) => {
        setSubmitted(true);

        if (passo?.descricao?.trim()) {
            let _passo = { ...passo };

            if (passo.id) {
                passoService.deletePasso(_passo)
                    .then(() => {
                        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Passo Excluído', life: 3000 });
                    })
                    .catch((error) => {
                        toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao excluir o passo', life: 5000 });
                    })
                    .finally(() => {
                        setDeletePassoDialog(false);
                        setPasso(emptyPasso);
                        refetch();
                    });
            }
        }
    };

    const exportCSV = () => {
        dt.current?.exportCSV();
    };

    const onInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>, descricao: string) => {
        const val = (e.target && e.target.value) || '';
        let _passo = { ...passo };
        _passo[`${descricao}`] = val;

        setPasso(_passo);
    };

    function onNumberChange(e: InputNumberChangeEvent, tempoestimado: string) {
        const newValue = typeof e.value === 'string' ? parseInt(e.value) : e.value;
        let _passo = { ...passo };

        _passo[`${tempoestimado}`] = newValue;

        setPasso(_passo);
    };

    function onTipoPassoChange(e: RadioButtonChangeEvent, tipopasso: string): void {
        let _passo = { ...passo };
        setSelectedTipoPasso(e.value);
        _passo[`${tipopasso}`] = e.value;

        setPasso(_passo);
    }

    const leftToolbarTemplate = () => {
        return (
            <React.Fragment>
                <div className="my-2">
                    <Button label="Criar" icon="pi pi-plus" severity="success" className=" mr-2" onClick={openNew} />
                    {/* estou <Button label="Deletar" icon="pi pi-trash" severity="danger" onClick={confirmDeleteSelected} disabled={!selectedPassos || !selectedPassos.length} /> */}
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

    const tempoBodyTemplate = (rowData: Vec.Passo) => {
        return (
            <>
                <span className="p-column-title">Tempo Estimado</span>
                {rowData.tempoestimado}
            </>
        );
    };

    const tipoPassoBodyTemplate = (rowData: Vec.Passo) => {
        return (
            <>
                <span className="p-column-title">Tipo de Passo</span>
                {rowData.tipopasso}
            </>
        );
    };

    const descricaoBodyTemplate = (rowData: Vec.Passo) => {
        return (
            <>
                <span className="p-column-title">Descrição</span>
                {rowData.descricao}
            </>
        );
    };

    const municipioBodyTemplate = (rowData: Vec.Passo) => {
        return (
            <>
                <span className="p-column-title">Município</span>
                {rowData.municipio?.nome}
            </>
        );
    };

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

    const actionBodyTemplate = (rowData: Vec.Passo) => {
        return (
            <>
                <Button icon="pi pi-pencil" rounded severity="success" className="mr-2" onClick={() => editPasso(rowData)} />
                <Button icon="pi pi-trash" rounded severity="warning" onClick={() => confirmDeletePasso(rowData)} />
            </>
        );
    };

    const header = (
        <div className="flex flex-column md:flex-row md:justify-content-between md:align-items-center">
            <h5 className="m-0">Cadastro de Etapas dos Processos</h5>
            {/* <div className=" flex justify-content-center">
                <Dropdown value={selectedTipo} onChange={(e) => handleTipoChange(e.value)} options={tipos} optionLabel="name"
                    editable className="w-full md:w-14rem" defaultValue='Variável' defaultChecked />
            </div> */}
            <div className='flex align-items-center justify-content-center'>
                <label htmlFor="ddcidade">Município:</label>

                <Dropdown id="ddCidade" options={municipios} value={municipio} onChange={onMunicipioChange} optionLabel="nome"
                    editable tooltip='Selecione o Município' tooltipOptions={{ position: 'left' }} />{/*className="w-full md:w-14rem" */}

            </div>
            <span className="block mt-2 md:mt-0 p-input-icon-left">
                <i className="pi pi-search" />
                <InputText type="search" onKeyDown={(e) => handleBuscaPasso(e, e.currentTarget.value)} onChange={handleClear} placeholder="Procurar Passo..." tooltip='Digite o Passo e tecle Enter' tooltipOptions={{ position: 'left' }} />
            </span>
        </div>
    );

    const passoDialogFooter = (
        <>
            <Button label="Cancelar" icon="pi pi-times" text onClick={hideDialog} />
            <Button label="Salvar" icon="pi pi-check" text onClick={savePasso} />
        </>
    );

    const deletePassoDialogFooter = (
        <>
            <Button label="Não" icon="pi pi-times" text onClick={hideDeletePassoDialog} />
            <Button label="Sim" icon="pi pi-check" text onClick={deletePasso} />
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
                        value={data?.passos ?? passos}
                        lazy
                        dataKey="id"
                        paginator
                        rows={rows}
                        rowsPerPageOptions={[10, 20, 30]}
                        className="datatable-responsive"
                        paginatorTemplate={template}
                        globalFilter={globalFilter}
                        emptyMessage="Nenhum passo encontrado."
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
                        loading={isFetching}
                        totalRecords={data?.totalRecords ?? totalRecords}
                        paginatorLeft={paginatorLeft}
                    >
                        <Column field="descricao" header="Descricao" sortable body={descricaoBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
                        <Column field="tempoestimado" header="Tempo Estimado" body={tempoBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
                        <Column field='tipopasso' header='Tipo de Passo' body={renderTipoPasso} headerStyle={{ minWidth: '15rem' }}></Column>
                        <Column field="municipio" header="Municipio" body={municipioBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
                        <Column field='link' header='Link Externo' headerStyle={{ minWidth: '15rem' }}></Column>
                        <Column header="Ações" body={actionBodyTemplate} headerStyle={{ minWidth: '10rem' }}></Column>

                    </DataTable>

                    <Dialog visible={passoDialog} style={{ width: '550px' }} header="Detalhe do Passo" modal className="p-fluid" footer={passoDialogFooter} onHide={hideDialog}>
                        <div className="field">
                            <label htmlFor="descricao">Descrição</label>
                            <InputText id="descricao" value={passo.descricao} type='text' onChange={(e) => onInputChange(e, 'descricao')} required autoFocus className={classNames({ 'p-invalid': submitted && !passo.descricao })} />
                            {submitted && !passo.descricao && <small className="p-invalid">Descrição do Passo é obrigatório.</small>}
                        </div>

                        <div className="field">
                            <label htmlFor="tempo">Tempo Estimado</label>
                            <InputNumber inputId="tempo" value={passo.tempoestimado} onChange={(e) => onNumberChange(e, 'tempoestimado')} className={classNames({ 'p-invalid': submitted && !passo.tempoestimado })} />
                        </div>

                        <div className="field">
                            <label htmlFor="dropdownCidade">Município</label>
                            <span className="p-float-label">
                                <Dropdown id="dropdownCidade" options={municipios} value={municipio} onChange={(e) => setMunicipio(e.value)} optionLabel="nome"></Dropdown>
                            </span>
                        </div>

                        <div className="field">
                            <label htmlFor="link">Link Externo</label>
                            <InputText id="link" value={passo.link} type='text' onChange={(e) => onInputChange(e, 'link')} />
                        </div>

                        <div className="flex flex-wrap gap-3">
                            <label htmlFor="tipopasso">Tipo de Passo :  </label>
                            {tipospasso.map((tipopasso) => {
                                return (
                                    <div key={tipopasso.key} className="flex align-items-center">
                                        <RadioButton inputId={tipopasso.key} name="tipopasso" value={tipopasso.key} onChange={(e) => onTipoPassoChange(e, 'tipopasso')} checked={passo.tipopasso === tipopasso.key} />
                                        <label htmlFor={tipopasso.key} className="ml-2">{tipopasso.name}</label>
                                    </div>
                                );
                            })}
                        </div>

                    </Dialog>

                    <Dialog visible={deletePassoDialog} style={{ width: '450px' }} header="Confirma a exclusão ?" modal footer={deletePassoDialogFooter} onHide={hideDeletePassoDialog} className="red-header">
                        <div className="flex align-items-center justify-content-center">
                            <i className="pi pi-exclamation-triangle mr-3" style={{ fontSize: '2rem', color: '#d6551e' }} />
                            {passo && (
                                <span>
                                    Tem certeza que quer deletar <b>{passo.descricao}</b>?
                                </span>
                            )}
                        </div>
                    </Dialog>

                </div>
            </div>
        </div>
    );
};

export default Passos;


export const getServerSideProps = withAuthServerSideProps(async (ctx) => {
    // Aqui não é necessário nenhum processamento adicional
});

// export const getServerSideProps = canSSRAuth(async (ctx) => {
//     try {
//         const apiClient = setupAPIClient(ctx);
//         const response = await apiClient.get('/api/registro');

//         const dados = {

//         };
//         return {

//             props: {

//                 dados: dados

//             }
//         };

//     } catch (err) {
//         console.log(err);

//         return {
//             redirect: {
//                 destination: '/',
//                 permanent: false
//             }
//         };
//     }
// });



