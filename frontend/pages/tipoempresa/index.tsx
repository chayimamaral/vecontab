import { Button } from 'primereact/button';
import { Column } from 'primereact/column';
import { DataTable, DataTableFilterMeta } from 'primereact/datatable';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
import { Toast } from 'primereact/toast';
import { Toolbar } from 'primereact/toolbar';
import { classNames } from 'primereact/utils';
import React, { useEffect, useRef, useState } from 'react';
import TipoEmpresaService from '../../services/cruds/TipoEmpresaService';
import ObrigacaoService from '../../services/cruds/ObrigacaoService';
import { canSSRAuth } from '../../components/utils/canSSRAuth';
import setupAPIClient from '../../components/api/api';
import { Vec } from '../../types/types';

import { Dropdown } from 'primereact/dropdown';
import { InputNumber, InputNumberChangeEvent, InputNumberValueChangeEvent } from 'primereact/inputnumber';
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

const TipoEmpresa = () => {

    let emptyTipoEmpresa: Vec.TipoEmpresa = {
        id: '',
        descricao: ''
    };

    const [tiposempresa, setTiposEmpresa] = useState([]);
    const [tipoEmpresaDialog, setTipoEmpresaDialog] = useState(false);
    const [deleteTipoEmpresaDialog, setDeleteTipoEmpresaDialog] = useState(false);
    const [tipoEmpresa, setTipoEmpresa] = useState<Vec.TipoEmpresa>(emptyTipoEmpresa);
    const [submitted, setSubmitted] = useState(false);
    const [globalFilter, setGlobalFilter] = useState<string>('');
    const toast = useRef<Toast>(null);
    const dt = useRef<DataTable<Vec.TipoEmpresa[]>>(null);

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
            descricao: { value: '', matchMode: 'contains' },
        }
    });

    useEffect(() => {
        loadLazyTipoEmpresa();
    }, [lazyState]);

    const tipoEmpresaService = TipoEmpresaService();
    const obrigacaoService = ObrigacaoService();

    // ── Estado do sub-cadastro de obrigações ─────────────────────────────────
    const emptyObrigacao: Vec.Obrigacao = {
        id: '',
        tipo_empresa_id: '',
        descricao: '',
        dia_base: 1,
        mes_base: null,
        frequencia: 'MENSAL',
        tipo: 'TRIBUTO',
    };

    const [obrigacaoDialogVisible, setObrigacaoDialogVisible] = useState(false);
    const [obrigacoes, setObrigacoes] = useState<Vec.Obrigacao[]>([]);
    const [obrigacao, setObrigacao] = useState<Vec.Obrigacao>(emptyObrigacao);
    const [obrigacaoFormVisible, setObrigacaoFormVisible] = useState(false);
    const [deleteObrigacaoDialog, setDeleteObrigacaoDialog] = useState(false);
    const [obrigacaoSubmitted, setObrigacaoSubmitted] = useState(false);
    const [obrigacaoLoading, setObrigacaoLoading] = useState(false);
    const [tipoEmpresaSelecionado, setTipoEmpresaSelecionado] = useState<Vec.TipoEmpresa>(emptyTipoEmpresa);

    const frequenciaOptions = [
        { label: 'Mensal', value: 'MENSAL' },
        { label: 'Anual', value: 'ANUAL' },
    ];

    const tipoObrigacaoOptions = [
        { label: 'Tributo', value: 'TRIBUTO' },
        { label: 'Informativa', value: 'INFORMATIVA' },
    ];

    const mesesOptions = [
        { label: '(nenhum)', value: null },
        { label: 'Janeiro', value: 1 },
        { label: 'Fevereiro', value: 2 },
        { label: 'Março', value: 3 },
        { label: 'Abril', value: 4 },
        { label: 'Maio', value: 5 },
        { label: 'Junho', value: 6 },
        { label: 'Julho', value: 7 },
        { label: 'Agosto', value: 8 },
        { label: 'Setembro', value: 9 },
        { label: 'Outubro', value: 10 },
        { label: 'Novembro', value: 11 },
        { label: 'Dezembro', value: 12 },
    ];

    const openObrigacoes = (te: Vec.TipoEmpresa) => {
        setTipoEmpresaSelecionado(te);
        setObrigacaoDialogVisible(true);
        loadObrigacoes(te.id!);
    };

    const loadObrigacoes = (tipoEmpresaId: string) => {
        setObrigacaoLoading(true);
        obrigacaoService.getObrigacoes(tipoEmpresaId)
            .then(({ data }) => setObrigacoes(data.obrigacoes ?? []))
            .catch(() => toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao carregar obrigações', life: 3000 }))
            .finally(() => setObrigacaoLoading(false));
    };

    const openNewObrigacao = () => {
        setObrigacao({ ...emptyObrigacao, tipo_empresa_id: tipoEmpresaSelecionado.id });
        setObrigacaoSubmitted(false);
        setObrigacaoFormVisible(true);
    };

    const hideObrigacaoForm = () => {
        setObrigacaoSubmitted(false);
        setObrigacaoFormVisible(false);
    };

    const editObrigacao = (ob: Vec.Obrigacao) => {
        setObrigacao({ ...ob });
        setObrigacaoFormVisible(true);
    };

    const confirmDeleteObrigacao = (ob: Vec.Obrigacao) => {
        setObrigacao(ob);
        setDeleteObrigacaoDialog(true);
    };

    const saveObrigacao = () => {
        setObrigacaoSubmitted(true);
        if (!obrigacao.descricao?.trim()) return;

        const action = obrigacao.id
            ? obrigacaoService.updateObrigacao(obrigacao)
            : obrigacaoService.createObrigacao(obrigacao);

        action
            .then(() => {
                toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: obrigacao.id ? 'Obrigação atualizada' : 'Obrigação criada', life: 3000 });
                loadObrigacoes(tipoEmpresaSelecionado.id!);
                setObrigacaoFormVisible(false);
            })
            .catch(() => toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao salvar obrigação', life: 3000 }));
    };

    const deleteObrigacaoConfirmed = () => {
        if (!obrigacao.id) return;
        obrigacaoService.deleteObrigacao(obrigacao)
            .then(() => {
                toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Obrigação excluída', life: 3000 });
                loadObrigacoes(tipoEmpresaSelecionado.id!);
            })
            .catch(() => toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao excluir obrigação', life: 3000 }))
            .finally(() => {
                setDeleteObrigacaoDialog(false);
                setObrigacao(emptyObrigacao);
            });
    };

    const loadLazyTipoEmpresa = () => {
        setLoading(true);
        tipoEmpresaService.getTiposEmpresa({ lazyEvent: JSON.stringify(lazyState) }).then(({ data }) => {
            setTiposEmpresa(data.tiposEmpresa);
            setTotalRecords(data.totalRecords);
        })
            .catch((error) => {
                toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao carregar os tiposempresa', life: 3000 });
            })
            .finally(() => setLoading(false));

    }
    const paginatorLeft = <Button type="button" icon="pi pi-refresh" tooltip='Atualizar' className="p-button-text" onClick={loadLazyTipoEmpresa} />;


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
    };

    const onFilter = (event) => {
        event['first'] = 0;
        setLazyState(event)
    };

    const openNew = () => {
        setTipoEmpresa(emptyTipoEmpresa);
        setSubmitted(false);
        setTipoEmpresaDialog(true);
    };

    const hideDialog = () => {
        setSubmitted(false);
        setTipoEmpresaDialog(false);
    };

    const hideDeleteTipoEmpresaDialog = () => {
        setDeleteTipoEmpresaDialog(false);
    };

    const saveTipoEmpresa = (event) => {
        setSubmitted(true);

        if (tipoEmpresa?.descricao?.trim()) {
            let _tipoEmpresa = { ...tipoEmpresa };

            if (tipoEmpresa.id) {
                tipoEmpresaService.updateTipoEmpresa(_tipoEmpresa)
                    .then((response) => {
                        const { tiposEmpresa, totalRecords } = response.data;
                        setTiposEmpresa(tiposEmpresa);
                        setTotalRecords(totalRecords);
                        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Tipo de Empresa Atualizado', life: 3000 });
                    })
                    .catch((error) => {
                        toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao atualizar o Tipo de Empresa', life: 3000 });
                    })
                    .finally(() => {
                        setTipoEmpresaDialog(false);
                        setTipoEmpresa(emptyTipoEmpresa);
                        loadLazyTipoEmpresa();
                    });
            } else {
                tipoEmpresaService.createTipoEmpresa(_tipoEmpresa)
                    .then((response) => {
                        const { tiposEmpresa, totalRecords } = response.data;
                        setTiposEmpresa(tiposEmpresa);
                        setTotalRecords(totalRecords);
                        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Tipo de Empresa Criado', life: 3000 });
                    })
                    .catch((error) => {
                        toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao criar o Tipo de Empresa', life: 3000 });
                    })
                    .finally(() => {
                        setTipoEmpresaDialog(false);
                        setTipoEmpresa(emptyTipoEmpresa);
                        loadLazyTipoEmpresa();
                    });
            }
        }
        setSubmitted(false);
    };

    const deleteTipoEmpresa = (event) => {
        setSubmitted(true);

        if (tipoEmpresa.id) {
            let _tipoEmpresa = { ...tipoEmpresa };
            tipoEmpresaService.deleteTipoEmpresa(_tipoEmpresa)
                .then((response) => {
                    const { tiposEmpresa, totalRecords } = response.data;
                    setTiposEmpresa(tiposEmpresa);
                    setTotalRecords(totalRecords);
                    toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Tipo de Empresa Excluído', life: 3000 });
                })
                .catch((error) => {
                    toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao excluir o Tipo de Empresa', life: 5000 });
                })
                .finally(() => {
                    setDeleteTipoEmpresaDialog(false);
                    setTipoEmpresa(emptyTipoEmpresa);
                    loadLazyTipoEmpresa();
                });
        }
    };


    const editTipoEmpreas = (tipoEmpresa: Vec.TipoEmpresa) => {
        setTipoEmpresa({ ...tipoEmpresa });
        setTipoEmpresaDialog(true);
    };

    const confirmDeleteTipoEmpresa = (tipoEmpresa: Vec.TipoEmpresa) => {
        setTipoEmpresa(tipoEmpresa);
        setDeleteTipoEmpresaDialog(true);
    };


    const exportCSV = () => {
        dt.current?.exportCSV();
    };

    const onInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>, nome: string) => {
        const val = (e.target && e.target.value) || '';
        let _tipoEmpresa = { ...tipoEmpresa };
        _tipoEmpresa[`${nome}`] = val;

        setTipoEmpresa(_tipoEmpresa);
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

    // const siglaBodyTemplate = (rowData: Vec.Estado) => {
    //     return (
    //         <>
    //             <span className="p-column-title">Sigla</span>
    //             {rowData.sigla}
    //         </>
    //     );
    // };

    const descricaoBodyTemplate = (rowData: Vec.TipoEmpresa) => {
        return (
            <>
                <span className="p-column-title">Nome</span>
                {rowData.descricao}
            </>
        );
    };

    const formatCurrency = (value) => {
        if (value)
            return value.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', minimumFractionDigits: 2, currencyDisplay: 'symbol' });
    };

    function handleClear(e): void {
        if (!e.target.value) {
            setLazyState({ ...lazyState, filters: { descricao: { value: '', matchMode: 'contains' } } });
        }
    }

    function handleBuscaTipo(event, value: string): void {
        if (event.key === 'Enter') {
            if (value !== '') {
                setLazyState({ ...lazyState, filters: { descricao: { value: value, matchMode: 'contains' } } });
            } else {
                setLazyState({ ...lazyState, filters: { descricao: { value: '', matchMode: 'contains' } } });
            }
        }
    }

    const actionBodyTemplate = (rowData: Vec.TipoEmpresa) => {
        return (
            <>
                <Button icon="pi pi-pencil" rounded severity="success" className="mr-2" onClick={() => editTipoEmpreas(rowData)} />
                <Button icon="pi pi-list" rounded severity="info" className="mr-2" tooltip="Obrigações" tooltipOptions={{ position: 'top' }} onClick={() => openObrigacoes(rowData)} />
                <Button icon="pi pi-trash" rounded severity="warning" onClick={() => confirmDeleteTipoEmpresa(rowData)} />
            </>
        );
    };

    const header = (
        <div className="flex flex-column md:flex-row md:justify-content-between md:align-items-center">
            <h5 className="m-0">Cadastro de Tipos de Empresa</h5>
            <span className="block mt-2 md:mt-0 p-input-icon-left">
                <i className="pi pi-search" />
                <InputText type="search" onKeyDown={(e) => handleBuscaTipo(e, e.currentTarget.value)} onChange={handleClear} placeholder="Procurar Tipo..." tooltip='Digite o Tipo de Empresa e tecle Enter' tooltipOptions={{ position: 'left' }} />
            </span>
        </div>
    );

    const tipoEmpresaDialogFooter = (
        <>
            <Button label="Cancelar" icon="pi pi-times" text onClick={hideDialog} />
            <Button label="Salvar" icon="pi pi-check" text onClick={saveTipoEmpresa} />
        </>
    );

    const deleteTipoEmpresaDialogFooter = (
        <>
            <Button label="Não" icon="pi pi-times" text onClick={hideDeleteTipoEmpresaDialog} />
            <Button label="Sim" icon="pi pi-check" text onClick={deleteTipoEmpresa} />
        </>
    );

    function onNumberChange(e: InputNumberChangeEvent, nome: string) {
        // ...) => {
        const newValue = typeof e.value === 'string' ? parseFloat(e.value) : e.value;
        let _tipoEmpresa = { ...tipoEmpresa };
        _tipoEmpresa[`${nome}`] = newValue;

        setTipoEmpresa(_tipoEmpresa);
    };

    const anualBodyTemplate = (rowData) => {
        return formatCurrency(rowData.anual);
    };

    const capitalBodyTemplate = (rowData) => {
        return formatCurrency(rowData.capital);
    };

    return (
        <div className="grid crud-demo">
            <div className="col-12">
                <div className="card">
                    <Toast ref={toast} />
                    <Toolbar className="mb-4" left={leftToolbarTemplate} right={rightToolbarTemplate}></Toolbar>

                    <DataTable
                        ref={dt}
                        value={tiposempresa}
                        lazy
                        dataKey="id"
                        paginator
                        rows={rows}
                        rowsPerPageOptions={[10, 20, 30]}
                        className="datatable-responsive"
                        paginatorTemplate={template}
                        globalFilter={globalFilter}
                        emptyMessage="Nenhum Tipo de Empresa encontrado."
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
                        <Column field="descricao" header="Descrição" sortable body={descricaoBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
                        <Column field="capital" header="Capital Social" dataType='numeric' body={capitalBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
                        <Column field="anual" header="Faturamento Anual" dataType='numeric' body={anualBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
                        <Column body={actionBodyTemplate} headerStyle={{ minWidth: '10rem' }}></Column>

                    </DataTable>

                    <Dialog visible={tipoEmpresaDialog} style={{ width: '450px' }} header="Detalhe do Tipo de Empresa" modal className="p-fluid" footer={tipoEmpresaDialogFooter} onHide={hideDialog}>
                        <div className="field">
                            <label htmlFor="descricao">Descrição</label>
                            <InputText id="descricao" value={tipoEmpresa.descricao} type='text' onChange={(e) => onInputChange(e, 'descricao')} required autoFocus className={classNames({ 'p-invalid': submitted && !tipoEmpresa.descricao })} />
                            {submitted && !tipoEmpresa.descricao && <small className="p-invalid">Descrição do Tipo de Empresa é obrigatória.</small>}
                        </div>
                        <div className="field">
                            <label htmlFor="capital">Capital Social</label>
                            <InputNumber id="capital" value={tipoEmpresa.capital} type='currency' onChange={(e) => onNumberChange(e, 'capital')} mode="currency" currency="BRL" minFractionDigits={2} maxFractionDigits={7} />
                        </div>
                        <div className="field">
                            <label htmlFor="anual">Faturamento Anual</label>
                            <InputNumber id="anual" value={tipoEmpresa.anual} type='currency' onChange={(e) => onNumberChange(e, 'anual')} mode="currency" currency="BRL" minFractionDigits={2} maxFractionDigits={7} />
                        </div>



                        {/* <div className="field">
                            <label htmlFor="sigla">Sigla</label>
                            <InputText id="sigla" value={estado.sigla?.toUpperCase()} type='text' onChange={(e) => onInputChange(e, 'sigla')} required className={classNames({ 'p-invalid': submitted && !estado.sigla })} />
                            {submitted && !estado.sigla && <small className="p-invalid">Sigla do Estado é obrigatório.</small>}
                        </div> */}

                    </Dialog>

                    <Dialog visible={deleteTipoEmpresaDialog} style={{ width: '450px' }} header="Confirma a exclusão ?" modal footer={deleteTipoEmpresaDialogFooter} onHide={hideDeleteTipoEmpresaDialog} className="red-header">
                        <div className="flex align-items-center justify-content-center">
                            <i className="pi pi-exclamation-triangle mr-3" style={{ fontSize: '2rem', color: '#d6551e' }} />
                            {tipoEmpresa && (
                                <span>
                                    Tem certeza que quer deletar <b>{tipoEmpresa.descricao}</b>?
                                </span>
                            )}
                        </div>
                    </Dialog>

                    {/* ── Dialog de Obrigações (sub-cadastro) ─────────────────── */}
                    <Dialog
                        visible={obrigacaoDialogVisible}
                        style={{ width: '900px' }}
                        header={`Obrigações - ${tipoEmpresaSelecionado.descricao ?? ''}`}
                        modal
                        onHide={() => setObrigacaoDialogVisible(false)}
                    >
                        <div className="mb-3">
                            <Button label="Nova Obrigação" icon="pi pi-plus" severity="success" onClick={openNewObrigacao} />
                        </div>

                        <DataTable value={obrigacoes} loading={obrigacaoLoading} dataKey="id" size="small" stripedRows emptyMessage="Nenhuma obrigação cadastrada.">
                            <Column field="descricao" header="Descrição" headerStyle={{ minWidth: '12rem' }} />
                            <Column field="dia_base" header="Dia Base" headerStyle={{ minWidth: '6rem' }} />
                            <Column field="frequencia" header="Frequência" headerStyle={{ minWidth: '8rem' }} />
                            <Column field="tipo" header="Tipo" headerStyle={{ minWidth: '8rem' }} />
                            <Column
                                field="mes_base"
                                header="Mês Base"
                                headerStyle={{ minWidth: '6rem' }}
                                body={(rowData: Vec.Obrigacao) => {
                                    if (rowData.mes_base == null) return '-';
                                    const nomes = ['', 'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
                                    return nomes[rowData.mes_base] ?? '-';
                                }}
                            />
                            <Column
                                body={(rowData: Vec.Obrigacao) => (
                                    <>
                                        <Button icon="pi pi-pencil" rounded severity="success" className="mr-2" onClick={() => editObrigacao(rowData)} />
                                        <Button icon="pi pi-trash" rounded severity="warning" onClick={() => confirmDeleteObrigacao(rowData)} />
                                    </>
                                )}
                                headerStyle={{ minWidth: '8rem' }}
                            />
                        </DataTable>
                    </Dialog>

                    {/* ── Form de Obrigação (criar/editar) ────────────────────── */}
                    <Dialog
                        visible={obrigacaoFormVisible}
                        style={{ width: '500px' }}
                        header={obrigacao.id ? 'Editar Obrigação' : 'Nova Obrigação'}
                        modal
                        className="p-fluid"
                        footer={
                            <>
                                <Button label="Cancelar" icon="pi pi-times" text onClick={hideObrigacaoForm} />
                                <Button label="Salvar" icon="pi pi-check" text onClick={saveObrigacao} />
                            </>
                        }
                        onHide={hideObrigacaoForm}
                    >
                        <div className="field">
                            <label htmlFor="ob_descricao">Descrição</label>
                            <InputText
                                id="ob_descricao"
                                value={obrigacao.descricao}
                                onChange={(e) => setObrigacao({ ...obrigacao, descricao: e.target.value })}
                                required
                                autoFocus
                                className={classNames({ 'p-invalid': obrigacaoSubmitted && !obrigacao.descricao })}
                            />
                            {obrigacaoSubmitted && !obrigacao.descricao && <small className="p-invalid">Descrição é obrigatória.</small>}
                        </div>
                        <div className="formgrid grid">
                            <div className="field col">
                                <label htmlFor="ob_dia_base">Dia Base</label>
                                <InputNumber
                                    id="ob_dia_base"
                                    value={obrigacao.dia_base}
                                    onValueChange={(e) => setObrigacao({ ...obrigacao, dia_base: e.value ?? 1 })}
                                    min={1}
                                    max={31}
                                    showButtons
                                />
                            </div>
                            <div className="field col">
                                <label htmlFor="ob_mes_base">Mês Base</label>
                                <Dropdown
                                    id="ob_mes_base"
                                    value={obrigacao.mes_base}
                                    options={mesesOptions}
                                    onChange={(e) => setObrigacao({ ...obrigacao, mes_base: e.value })}
                                    placeholder="Selecione..."
                                />
                            </div>
                        </div>
                        <div className="formgrid grid">
                            <div className="field col">
                                <label htmlFor="ob_frequencia">Frequência</label>
                                <Dropdown
                                    id="ob_frequencia"
                                    value={obrigacao.frequencia}
                                    options={frequenciaOptions}
                                    onChange={(e) => setObrigacao({ ...obrigacao, frequencia: e.value })}
                                />
                            </div>
                            <div className="field col">
                                <label htmlFor="ob_tipo">Tipo</label>
                                <Dropdown
                                    id="ob_tipo"
                                    value={obrigacao.tipo}
                                    options={tipoObrigacaoOptions}
                                    onChange={(e) => setObrigacao({ ...obrigacao, tipo: e.value })}
                                />
                            </div>
                        </div>
                    </Dialog>

                    {/* ── Confirmar exclusão de Obrigação ─────────────────────── */}
                    <Dialog
                        visible={deleteObrigacaoDialog}
                        style={{ width: '450px' }}
                        header="Confirma a exclusão ?"
                        modal
                        footer={
                            <>
                                <Button label="Não" icon="pi pi-times" text onClick={() => setDeleteObrigacaoDialog(false)} />
                                <Button label="Sim" icon="pi pi-check" text onClick={deleteObrigacaoConfirmed} />
                            </>
                        }
                        onHide={() => setDeleteObrigacaoDialog(false)}
                        className="red-header"
                    >
                        <div className="flex align-items-center justify-content-center">
                            <i className="pi pi-exclamation-triangle mr-3" style={{ fontSize: '2rem', color: '#d6551e' }} />
                            {obrigacao && (
                                <span>Tem certeza que quer excluir <b>{obrigacao.descricao}</b>?</span>
                            )}
                        </div>
                    </Dialog>

                </div>
            </div>
        </div>
    );
};

export default TipoEmpresa;


export const getServerSideProps = withAuthServerSideProps(async (ctx) => {
    // Aqui não é necessário nenhum processamento adicional
});

