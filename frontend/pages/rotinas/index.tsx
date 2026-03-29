import { Button } from 'primereact/button';
import { Column } from 'primereact/column';
import { DataTable, DataTableExpandedRows, DataTableFilterMeta, DataTableRowEvent, DataTableValueArray } from 'primereact/datatable';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
import { Toast } from 'primereact/toast';
import { Toolbar } from 'primereact/toolbar';
import { PickList, PickListEvent } from 'primereact/picklist';
import { PrimeIcons } from 'primereact/api';
import { classNames } from 'primereact/utils';
import React, { useEffect, useRef, useState } from 'react';
import { canSSRAuth } from '../../components/utils/canSSRAuth';
import setupAPIClient from '../../components/api/api';
import { Vec } from '../../types/types';

import { Dropdown } from 'primereact/dropdown';
import { InputNumber, InputNumberChangeEvent, InputNumberValueChangeEvent } from 'primereact/inputnumber';
import { RadioButton, RadioButtonChangeEvent } from 'primereact/radiobutton';

import RotinaService from '../../services/cruds/RotinaService';
import MunicipioService from '../../services/cruds/MunicipioService';
import PassoService from '../../services/cruds/PassoService';
import TipoEmpresaService from '../../services/cruds/TipoEmpresaService';
import LeftToolbar from '../../components/toolbar/LeftToolbar';
import RightToolbar from '../../components/toolbar/RightToolbar';
import SaveCancelDialogFooter from '../../components/toolbar/SaveCancelDialogFooter';
import { withAuthServerSideProps } from '../../components/utils/crudUtils';
import { GetServerSidePropsContext } from 'next';

interface LazyTableState {
    totalRecords: number;
    first: number;
    rows: number;
    page: number;
    sortField?: string;
    sortOrder?: number;
    filters: DataTableFilterMeta;
}

const Rotinas = () => {

    let emptyRotinas: Rotinas = {
        id: '',
        descricao: '',
        cidade_id: '',
        tipo_empresa_id: '',
        municipio: {
            id: '',
            nome: '',
        },
        tipo_empresa: {
            id: '',
            descricao: '',
        },
        rotinaitens: [{
            id: '',
            descricao: '',
            tempoestimado: 0,
            tipopasso: '',
            rotina_id: '',
            ordem: 0,
            link: '',
        }]
    }

    interface RotinaItems {
        id: string;
        descricao: string;
        tempoestimado: number;
        tipopasso: string;
        rotina_id: string;
        ordem: number;
        link: string;
    }

    interface Rotinas {
        id: string;
        descricao: string;
        cidade_id: string;
        tipo_empresa_id?: string;
        municipio: {
            id: string;
            nome: string;
        };
        tipo_empresa?: {
            id: string;
            descricao: string;
        };
        rotinaitens: RotinaItems[];
    }

    interface MunicipioLite {
        id?: string;
        nome?: string;
    }

    interface Passos {
        id: string;
        descricao: string;
        tempoestimado: number;
        rotina_id: string;
        link: string;
        ordem: number;
    }

    interface PickListPassoChangeEvent {
        source: Passos[];
        target: Passos[];
    }

    const [rotinas, setRotinas] = useState<Rotinas[]>([]);
    const [expandedRows, setExpandedRows] = useState<DataTableExpandedRows | DataTableValueArray | undefined>(undefined);
    const [municipios, setMunicipios] = useState<MunicipioLite[]>([]);
    const [municipio, setMunicipio] = useState<MunicipioLite>();
    const [tiposEmpresa, setTiposEmpresa] = useState<Vec.TipoEmpresaLite[]>([]);
    const [tipoEmpresa, setTipoEmpresa] = useState<Vec.TipoEmpresaLite | undefined>(undefined);

    const [rotinaDialog, setRotinaDialog] = useState(false);
    const [deleteRotinaDialog, setDeleteRotinaDialog] = useState(false);
    const [deletePassosDialog, setDeletePassosDialog] = useState(false);
    const [inserePassosDialog, setInserePassosDialog] = useState(false);
    const [passoDialog, setPassoDialog] = useState(false);
    const [rotina, setRotina] = useState<Rotinas>(emptyRotinas);


    const [submitted, setSubmitted] = useState(false);
    const [globalFilter, setGlobalFilter] = useState<string>('');
    const toast = useRef<Toast>(null);
    const dt = useRef<DataTable<Rotinas[]>>(null);

    const [loading, setLoading] = useState<boolean>(false);
    const [first, setFirst] = useState(0);
    const [currentPage, setCurrentPage] = useState(1);
    const [sortOrder, setSortOrder] = useState(1);
    const [sortField, setSortField] = useState('descricao');
    const paginatorRight = <Button type="button" icon="pi pi-cloud" className="p-button-text" />;
    const [pageInputTooltip, setPageInputTooltip] = useState('');
    const [value, setValue] = useState('');
    const [totalRecords, setTotalRecords] = useState<number>(0);

    const [source, setSource] = useState<Passos[]>([]);
    const [target, setTarget] = useState<Passos[]>([]);
    const [auxRotina, setAuxRotina] = useState<string>('');
    const [empresaSelecionada, setEmpresaSelecionada] = useState<string>('');
    //const [deletarItem, setDeletarItem] = useState([]);
    const [deletarItem, setDeletarItem] = useState<{ id: string; rotina_id: string; }[]>([]);

    const [lazyState, setLazyState] = useState<LazyTableState>({
        totalRecords: 0,
        first: 0,
        rows: 20,
        page: 1,
        sortField: '',
        sortOrder: 1,
        filters: {
            descricao: { value: '', matchMode: 'contains' }
        }
    });

    useEffect(() => {
        loadLazyMunicipios();
        loadTiposEmpresa();
    }, []);

    useEffect(() => {
        fetchRotinasList(lazyState);
    }, [lazyState]);

    useEffect(() => {
    }, [deletarItem]);

    const rotinaService = RotinaService();

    const fetchRotinasList = async (st: LazyTableState) => {
        try {
            setLoading(true);
            const { data } = await rotinaService.getRotinas({ lazyEvent: JSON.stringify(st) });
            setRotinas(data.rotinas);
            setTotalRecords(data.totalRecords);
        } catch (error) {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao carregar os Rotinas', life: 3000 });
        } finally {
            setLoading(false);
        }
    };

    const loadLazyRotina = async () => fetchRotinasList(lazyState);

    const loadLazyMunicipios = () => {
        const municipioService = MunicipioService();
        municipioService.getMunicipiosLite().then(({ data }) => {
            setMunicipios(data?.municipios);
        })
    }

    const loadTiposEmpresa = () => {
        const tipoEmpresaService = TipoEmpresaService();
        tipoEmpresaService.getTiposEmpresaLite().then(({ data }) => {
            setTiposEmpresa(data?.tiposEmpresa ?? []);
        });
    };

    const loadLazyPassosPorCidade = async (rotinas: Rotinas) => {
        try {
            const passosService = PassoService();
            const { data } = await passosService.getPassosPorCidade(rotinas);
            if (data?.passos != null) {
                setSource(data?.passos);
            } else {
                setSource([]);
            }

        } catch (error) {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao carregar os Passos', life: 3000 });
        }
    }

    const loadLazyPassosSelecionados = (rotinas: Rotinas) => {
        const rotinaService = RotinaService();
        rotinaService.getRotinaPassosSelecionados(rotinas).then(({ data }) => {
            if (data?.passos != null) {
                setTarget(data?.passos);
            } else {
                setTarget([]);
            }
        })
    }

    function handleClear(e: React.ChangeEvent<HTMLInputElement>): void {
        if (!e.target.value) {
            setLazyState({ ...lazyState, filters: { descricao: { value: '', matchMode: 'contains' } } });
        }
    }

    const paginatorLeft = <Button type="button" icon="pi pi-refresh" tooltip='Atualizar' className="p-button-text" onClick={loadLazyRotina} />;

    const onPage = (event: any) => {
        setFirst(event.first);
        setCurrentPage(event.page + 1);
        setSortOrder(event.sortOrder ?? 1);
        setSortField(event.sortField ?? 'descricao');
        setLazyState((prev) => {
            const nextRows = typeof event.rows === 'number' && event.rows > 0 ? event.rows : prev.rows;
            return {
                ...prev,
                first: event.first,
                rows: nextRows,
                page: event.page + 1,
                sortField: event.sortField ?? prev.sortField,
                sortOrder: event.sortOrder ?? prev.sortOrder,
                filters: event.filters ?? prev.filters,
            };
        });
    }

    const onPageInputKeyDown = (event: React.KeyboardEvent<HTMLInputElement>, options: any) => {
        if (event.key === 'Enter') {
            const page = currentPage;
            if (page < 1 || page > options.totalPages) {
                setPageInputTooltip(`Valor deve estar entre 1 e ${options.totalPages}.`);
            }
            else {
                const first = currentPage ? options.rows * (page - 1) : 0;

                setFirst(first);
                setCurrentPage(page);
                setLazyState((prev) => ({
                    ...prev,
                    first,
                    rows: options.rows,
                    page,
                }));
            }
        }

    }

    const onPageInputChange = (event: React.ChangeEvent<HTMLInputElement>) => {
        setCurrentPage(Number(event.target.value || 1));
    }


    const onSort = (event: any) => {
        setLazyState((prev) => ({
            ...prev,
            first: 0,
            page: 1,
            rows: typeof event.rows === 'number' && event.rows > 0 ? event.rows : prev.rows,
            sortField: event.sortField ?? prev.sortField,
            sortOrder: event.sortOrder ?? prev.sortOrder,
            filters: event.filters ?? prev.filters,
        }));
        setFirst(0);
        setCurrentPage(1);
        if (event.sortField != null && event.sortField !== '') {
            setSortField(event.sortField);
        }
        if (event.sortOrder != null) {
            setSortOrder(event.sortOrder);
        }
    };

    const onFilter = (event: any) => {
        setLazyState((prev) => ({
            ...prev,
            first: 0,
            page: 1,
            rows: typeof event.rows === 'number' && event.rows > 0 ? event.rows : prev.rows,
            sortField: event.sortField ?? prev.sortField,
            sortOrder: event.sortOrder ?? prev.sortOrder,
            filters: event.filters ?? prev.filters,
        }));
        setFirst(0);
        setCurrentPage(1);
    };

    const handleCreate = () => {
        setRotina(emptyRotinas);
        setMunicipio(undefined);
        setTipoEmpresa(undefined);
        setSubmitted(false);
        setRotinaDialog(true);
    };

    const hideDialog = () => {
        setSubmitted(false);
        setTipoEmpresa(undefined);
        setRotinaDialog(false);
    };

    const hideDeleteRotinaDialog = () => {
        setDeleteRotinaDialog(false);
    };

    function handleBuscaRotina(event: React.KeyboardEvent<HTMLInputElement>, value: string): void {
        if (event.key === 'Enter') {
            if (value !== '') {
                setLazyState({ ...lazyState, filters: { descricao: { value: value, matchMode: 'contains' } } });
            } else {
                setLazyState({ ...lazyState, filters: { descricao: { value: '', matchMode: 'contains' } } });
            }
        }
    }

    const saveRotina = () => {
        setSubmitted(true);
        if (!rotina?.descricao?.trim()) {
            setSubmitted(false);
            return;
        }
        if (!municipio?.id) {
            toast.current?.show({
                severity: 'warn',
                summary: 'Município obrigatório',
                detail: 'Selecione o município da rotina (necessário para listar e vincular passos).',
                life: 5000,
            });
            setSubmitted(false);
            return;
        }
        if (!tipoEmpresa?.id) {
            toast.current?.show({
                severity: 'warn',
                summary: 'Tipo de empresa obrigatório',
                detail: 'Selecione o tipo de empresa vinculado a esta rotina.',
                life: 5000,
            });
            setSubmitted(false);
            return;
        }
        rotina['cidade_id'] = municipio.id;

        let _rotina = { ...rotina, tipo_empresa_id: tipoEmpresa.id };

        if (rotina.id) {
            rotinaService.updateRotina(_rotina)
                .then(() => {
                    toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Rotina Atualizado', life: 3000 });
                })
                .catch((error) => {
                    toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao atualizar o rotina', life: 3000 });
                })
                .finally(() => {
                    setRotinaDialog(false);
                    setRotina(emptyRotinas);
                    setMunicipio(undefined);
                    setTipoEmpresa(undefined);
                    setSource([]);
                    fetchRotinasList(lazyState);
                });
        } else {
            rotinaService.createRotina(_rotina)
                .then(() => {
                    toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Rotina Criado', life: 3000 });
                })
                .catch((error) => {
                    toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao criar o rotina', life: 3000 });
                })
                .finally(() => {
                    setRotinaDialog(false);
                    setRotina(emptyRotinas);
                    setMunicipio(undefined);
                    setTipoEmpresa(undefined);
                    setFirst(0);
                    setCurrentPage(1);
                    setLazyState((prev) => ({ ...prev, first: 0, page: 1 }));
                });
        }
        setSubmitted(false);
    };

    const editRotina = (rotina: Rotinas) => {
        setMunicipio(rotina.municipio)
        setTipoEmpresa(
            rotina.tipo_empresa?.id
                ? { id: rotina.tipo_empresa.id, descricao: rotina.tipo_empresa.descricao ?? '' }
                : undefined
        );
        setRotina({ ...rotina });
        setRotinaDialog(true);
    };

    const confirmDeleteRotina = (rotina: Rotinas) => {
        setRotina(rotina);
        setDeleteRotinaDialog(true);
    };

    const deleteRotina = () => {
        setSubmitted(true);

        if (rotina?.descricao?.trim()) {
            let _rotina = { ...rotina };

            if (rotina.id) {
                rotinaService.deleteRotina(_rotina)
                    .then(() => {
                        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Rotina Excluído', life: 3000 });
                    })
                    .catch((error) => {
                        toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao excluir o rotina', life: 5000 });
                    })
                    .finally(() => {
                        setDeleteRotinaDialog(false);
                        setRotina(emptyRotinas);
                        loadLazyRotina();
                    });
            }
        }
    };

    const exportCSV = () => {
        dt.current?.exportCSV();
    };

    const onInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>, descricao: keyof Rotinas) => {
        const val = (e.target && e.target.value) || '';
        let _rotina = { ...rotina };

        if (descricao === 'descricao') {
            _rotina.descricao = val;
        }

        setRotina(_rotina);
    };

    //===========================================================================
    // EXPANDIR E CONTRAIR ROTINAS
    //===========================================================================

    const expandAll = () => {
        let _expandedRows: DataTableExpandedRows = {};

        rotinas.forEach((p) => (_expandedRows[p.id as string] = true as boolean));

        setExpandedRows(_expandedRows);
    };

    const hidePassoDialog = () => {
        setSubmitted(false);
        setPassoDialog(false);
    };

    const collapseAll = () => {
        setExpandedRows(undefined);
    };

    const savePassos = async () => {

        let _rotina = { ...rotina };
        const rotinaComPassos = { ..._rotina, passos: target };

        if (deletarItem.length > 0) {
            rotinaService.removerPassoSelecionado(deletarItem)
            setDeletarItem([])
        }

        if (target.length > 0) {
            try {

                await rotinaService.salvarPassosSelecionados(rotinaComPassos)

            } catch (error) {
                throw new Error('Erro ao salvar passos selecionados')
            } finally {
                setDeletarItem([])
                setRotina(emptyRotinas);
                setSubmitted(false)
                setPassoDialog(false);
            }
        }

        await loadLazyPassosPorCidade(_rotina);
        await loadLazyRotina()

        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Passos Salvos', life: 3000 });

    }

    const passoDialogFooter = (
        <>
            <Button label="Cancelar" icon="pi pi-times" text onClick={hidePassoDialog} />
            <Button label="Salvar" icon="pi pi-check" text onClick={savePassos} />
        </>
    );



    const handleSelectPassos = (rowData: Rotinas) => {

        let _rotinas = { ...rowData }
        setAuxRotina(_rotinas.id)
        setEmpresaSelecionada(_rotinas.descricao)
        loadLazyPassosPorCidade(_rotinas);
        loadLazyPassosSelecionados(_rotinas);
        loadLazyRotina();
        setSubmitted(false);
        setPassoDialog(true);
    }

    const onRowExpand = (event: DataTableRowEvent) => {
        //toast.current?.show({ severity: 'info', summary: 'Rotina Expandida', detail: event.data.descricao, life: 3000 });
    };

    const onRowCollapse = (event: DataTableRowEvent) => {
        //toast.current?.show({ severity: 'success', summary: 'Rotina Colapsada', detail: event.data.descricao, life: 3000 });
    };

    const allowExpansion = (rowData: Rotinas) => {
        // Verificar se rowData.rotinaitens é uma matriz e não está vazia
        // Verificar, antes, se é um array e se tem pelo menos um elemento

        if (rowData.rotinaitens === undefined) {
            return false
        }

        return (rowData.rotinaitens!.length > 0)
    };

    const onPassoChange = (e: PickListPassoChangeEvent) => {

        if (e.target) {
            const updatedTarget = e.target.map((item, index) => ({
                ...item,
                ordem: index,
                rotina_id: auxRotina,
            }));
            setTarget(updatedTarget);
        }

        if (e.source) {
            setSource(e.source);
        }
    }

    const handleMoveToSource = (event: PickListEvent) => {

        const { id, rotina_id } = event.value[0];

        setDeletarItem((prevDeletarItem) => [...prevDeletarItem, { id, rotina_id }]);

    }

    const handleMoveAllToSource = (event: PickListEvent) => {

        if (event.value) {
            setDeletarItem([]);
            for (let i = 0; i < event.value.length; i++) {
                const { id, rotina_id } = event.value[i];
                setDeletarItem((prevDeletarItem) => [...prevDeletarItem, { id, rotina_id }]);
            }
        }

        setTarget([]);

        console.table(deletarItem)
    }



    function onTargetPassosChange(event: PickListEvent): void {
        // console.log('onTargetPassosChange')
        // console.table([source, target, event])
        // if (event.value === 'target' && event.value.items) {
        //     const updatedSource = source.concat(event.value.items);
        //     const updateTarget = target.filter(item => !event.value.items.includes(item));

        //     setSource(updatedSource);
        //     setTarget(updateTarget);
        // }
    }

    function retornaDias(dias: number) {
        if (dias > 1) {
            return `${dias} dias`
        } else {
            return `${dias} dia`
        }
    }

    const passoTemplate = (item: Passos) => {
        return (
            <div className="flex flex-wrap p-2 align-items-center gap-3">
                <div className="flex-1 flex flex-column gap-2">
                    <span className="font-bold">
                        <i className={`pi ${PrimeIcons.ARROW_CIRCLE_RIGHT} small-icon`} style={{ marginRight: '0.5rem' }} />
                        {`${item.descricao}  (${retornaDias(item.tempoestimado)})`}

                    </span>
                    {item.link && (
                        <div className="flex align-items-center gap-2">
                            <i className="pi pi-globe text-sm"></i>
                            <span>{item.link}</span>
                        </div>
                    )}
                </div>
            </div>
        );
    };

    // const rowExpansionTemplate = (data: Rotinas) => {

    //     return (
    //         <div className="p-3" style={{ backgroundColor: '#f7f2df' }}>
    //             <h5 style={{ color: 'black', fontWeight: 'bold' }}>Passos para {data.descricao}</h5>
    //             <Button label="Selecionar Passos" icon="pi pi-plus" severity="success" className=" mr-2 mb-3" onClick={() => handleSelectPassos(data)} />
    //             <DataTable value={data.rotinaitens}>
    //                 <Column field="descricao" header="Passo" ></Column>
    //                 <Column field="tempoestimado" header="Tempo Estimado"></Column>
    //                 <Column field="link" header="Link Externo"></Column>
    //             </DataTable>

    //             <Dialog visible={passoDialog} style={{ width: '100%', height: '100%' }} header="Manutenção de Passos" modal className="p-fluid" footer={passoDialogFooter} onHide={hidePassoDialog}>
    //                 <Column expander={allowExpansion} style={{ width: '10rem' }} />

    //                 <div className="card">
    //                     <PickList
    //                         source={source}
    //                         target={target}
    //                         onChange={onPassoChange}
    //                         itemTemplate={passoTemplate}
    //                         onMoveToSource={handleMoveToSource}
    //                         breakpoint='1200px'

    //                         sourceHeader="Passos Disponíveis"
    //                         targetHeader="Passos Selecionados"
    //                         sourceStyle={{ height: '40rem' }}
    //                         targetStyle={{ height: '50rem' }}
    //                         onTargetSelectionChange={onTargetPassosChange}
    //                         onMoveAllToSource={handleMoveAllToSource}
    //                     //style={{ width: '40rem', height: '40rem' }}
    //                     />

    //                 </div>

    //             </Dialog>

    //         </div>
    //     );
    // };

    //===========================================================================
    // FIM EXPANDIR E CONTRAIR ROTINAS
    //===========================================================================

    const descricaoBodyTemplate = (rowData: Rotinas) => {
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

    const tipoEmpresaBodyTemplate = (rowData: Rotinas) => {
        return (
            <>
                <span className="p-column-title">Tipo de Empresa</span>
                {rowData.tipo_empresa?.descricao ?? '—'}
            </>
        );
    };

    const template = {
        layout: 'PrevPageLink PageLinks NextPageLink RowsPerPageDropdown CurrentPageReport',
        'PrevPageLink': (options: any) => {
            return (
                <button type="button" className={options.className} onClick={options.onClick} disabled={options.disabled}>
                    <span className="p-3">Página anterior</span>
                </button>
            )
        },
        'NextPageLink': (options: any) => {
            return (
                <button type="button" className={options.className} onClick={options.onClick} disabled={options.disabled}>
                    <span className="p-3">Próxima página</span>
                </button>
            )
        },
        'PageLinks': (options: any) => {
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
        'RowsPerPageDropdown': (options: any) => {
            const dropdownOptions = [
                { label: '10', value: 10 },
                { label: '20', value: 20 },
                { label: '30', value: 30 },
            ];

            return (
                <Dropdown
                    value={options.value}
                    options={dropdownOptions}
                    optionLabel="label"
                    optionValue="value"
                    onChange={options.onChange}
                />
            );
        },
        'CurrentPageReport': (options: any) => {
            return (
                <span className="mx-3" style={{ color: 'var(--text-color)', userSelect: 'none' }}>
                    Página <InputText className="ml-1" value={currentPage.toString()} tooltip={pageInputTooltip}
                        onKeyDown={(e) => onPageInputKeyDown(e, options)} onChange={onPageInputChange} />
                </span>
            )
        }
    };

    const actionBodyTemplate = (rowData: Rotinas) => {
        return (
            <>
                <Button icon="pi pi-arrows-h" tooltip='Selecionar Passos' rounded severity="success" className="mr-2" onClick={() => handleSelectPassos(rowData)} />
                <Button icon="pi pi-pencil" tooltip='Editar' rounded severity="success" className="mr-2" onClick={() => editRotina(rowData)} />
                <Button icon="pi pi-trash" tooltip='Excluir' rounded severity="warning" onClick={() => confirmDeleteRotina(rowData)} />
            </>
        );
    };

    const header = (
        <div className="flex flex-column md:flex-row md:justify-content-between md:align-items-center">
            <h5 className="m-0">Cadastro de Rotinas</h5>
            {/* <Button icon="pi pi-plus" label="Expandir Todos" onClick={expandAll} text />
            <Button icon="pi pi-minus" label="Contrair Todos" onClick={collapseAll} text /> */}
            <span className="block mt-2 md:mt-0 p-input-icon-left">
                <i className="pi pi-search" />
                <InputText type="search" onKeyDown={(e) => handleBuscaRotina(e, e.currentTarget.value)} onChange={handleClear} placeholder="Procurar Rotina..." tooltip='Digite o Rotina e tecle Enter' tooltipOptions={{ position: 'left' }} />
            </span>
        </div>
    );

    const rotinaDialogFooter = (
        <>
            <Button label="Cancelar" icon="pi pi-times" text onClick={hideDialog} />
            <Button label="Salvar" icon="pi pi-check" text onClick={saveRotina} />
        </>
    );

    const deleteRotinaDialogFooter = (
        <>
            <Button label="Não" icon="pi pi-times" text onClick={hideDeleteRotinaDialog} />
            <Button label="Sim" icon="pi pi-check" text onClick={deleteRotina} />
        </>
    );

    return (
        <div className="grid crud-demo">
            <div className="col-12">
                <div className="card">
                    <Toast ref={toast} />
                    <Toolbar className="mb-4" left={<LeftToolbar label='Criar' icon="pi pi-plus" severity="success" onClick={handleCreate} />} right={<RightToolbar onExportCSV={exportCSV} />}  ></Toolbar>

                    <DataTable
                        ref={dt}
                        value={rotinas}
                        lazy
                        dataKey="id"
                        paginator
                        rows={lazyState.rows}
                        rowsPerPageOptions={[10, 20, 30]}
                        className="datatable-responsive"
                        paginatorTemplate={template}
                        globalFilter={globalFilter}
                        emptyMessage="Nenhum rotina encontrado."
                        header={header}
                        size="small"
                        stripedRows
                        filterDisplay='row'
                        first={lazyState.first}
                        onPage={onPage}
                        onSort={onSort}
                        sortField={lazyState.sortField || undefined}
                        sortOrder={lazyState.sortOrder === -1 ? -1 : 1}
                        onFilter={onFilter}
                        loading={loading}
                        totalRecords={totalRecords}
                        paginatorLeft={paginatorLeft}

                    // expandedRows={expandedRows}
                    // onRowToggle={(e) => setExpandedRows(e.data)}
                    // onRowExpand={onRowExpand}
                    // onRowCollapse={onRowCollapse}
                    // rowExpansionTemplate={rowExpansionTemplate}
                    >
                        {/* <Column expander={allowExpansion} style={{ width: '5rem' }} /> */}
                        <Column field="descricao" header="Descrição" sortable body={descricaoBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
                        <Column field="municipio" header="Municipio" sortable body={municipioBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
                        <Column field="tipo_empresa" header="Tipo de Empresa" body={tipoEmpresaBodyTemplate} headerStyle={{ minWidth: '12rem' }}></Column>
                        <Column body={actionBodyTemplate} headerStyle={{ minWidth: '10rem' }}></Column>
                    </DataTable>

                    <Dialog visible={passoDialog} style={{ width: '1000px', height: '1000px' }} header={`Manutenção de Passos - ${empresaSelecionada}`} modal className="p-fluid" footer={passoDialogFooter} onHide={hidePassoDialog}>
                        <Column expander={allowExpansion} style={{ width: '5rem' }} />

                        <div className='card' >
                            <PickList
                                source={source}
                                target={target}
                                dataKey="id"
                                onChange={onPassoChange}
                                itemTemplate={passoTemplate}
                                onMoveToSource={handleMoveToSource}
                                breakpoint='1200px'

                                sourceHeader="Passos Disponíveis"
                                targetHeader="Passos Selecionados"
                                sourceStyle={{ height: '50rem' }}
                                targetStyle={{ height: '50rem' }}
                                onTargetSelectionChange={onTargetPassosChange}
                                onMoveAllToSource={handleMoveAllToSource}

                            //style={{ width: '100%', height: '100%' }}
                            />

                        </div>

                    </Dialog>

                    <Dialog visible={rotinaDialog} style={{ width: '550px' }} header="Detalhe do Rotina" modal className="p-fluid" footer={rotinaDialogFooter} onHide={hideDialog}>
                        {/* <Column expander={allowExpansion} style={{ width: '5rem' }} /> */}
                        <div className="field">
                            <label htmlFor="descricao">Descrição</label>
                            <InputText id="descricao" value={rotina.descricao} type='text' onChange={(e) => onInputChange(e, 'descricao')} required autoFocus className={classNames({ 'p-invalid': submitted && !rotina.descricao })} />
                            {submitted && !rotina.descricao && <small className="p-invalid">Descrição do Rotina é obrigatório.</small>}
                        </div>
                        <div className="field">
                            <label htmlFor="dropdownCidade">Município</label>
                            <span className="p-float-label">
                                <Dropdown id="dropdownCidade" options={municipios} value={municipio} onChange={(e) => setMunicipio(e.value)} optionLabel="nome"></Dropdown>
                            </span>
                        </div>
                        <div className="field">
                            <label htmlFor="dropdownTipoEmpresa">Tipo de Empresa</label>
                            <Dropdown
                                id="dropdownTipoEmpresa"
                                options={tiposEmpresa}
                                value={tipoEmpresa}
                                onChange={(e) => setTipoEmpresa(e.value)}
                                optionLabel="descricao"
                                dataKey="id"
                                placeholder="Selecione o tipo de empresa"
                                emptyMessage="Nenhum tipo encontrado"
                                filter
                                filterBy="descricao"
                                showClear
                            />
                        </div>

                    </Dialog>

                    <Dialog visible={deleteRotinaDialog} style={{ width: '450px' }} header="Confirma a exclusão ?" modal footer={deleteRotinaDialogFooter} onHide={hideDeleteRotinaDialog} className="red-header">
                        <div className="flex align-items-center justify-content-center">
                            <i className="pi pi-exclamation-triangle mr-3" style={{ fontSize: '2rem', color: '#d6551e' }} />
                            {rotina && (
                                <span>
                                    Tem certeza que quer deletar <b>{rotina.descricao}</b>?
                                </span>
                            )}
                        </div>
                    </Dialog>

                </div>
            </div>
        </div>
    );
};

export default Rotinas;


export const getServerSideProps = withAuthServerSideProps(async (ctx: GetServerSidePropsContext) => {
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





