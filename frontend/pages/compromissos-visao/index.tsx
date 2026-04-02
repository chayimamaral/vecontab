import { useEffect, useMemo, useRef, useState, type Dispatch, type SetStateAction } from 'react';
import { canSSRAuth } from '../../components/utils/canSSRAuth';
import { DataTable } from 'primereact/datatable';
import type { DataTableFilterMeta, DataTableProps } from 'primereact/datatable';
import { Column } from 'primereact/column';
import { Button } from 'primereact/button';
import { InputText } from 'primereact/inputtext';
import { InputNumber } from 'primereact/inputnumber';
import { Dialog } from 'primereact/dialog';
import { Tag } from 'primereact/tag';
import { Toast } from 'primereact/toast';
import { FilterMatchMode } from 'primereact/api';
import { Calendar } from 'primereact/calendar';
import { Dropdown } from 'primereact/dropdown';
import { InputTextarea } from 'primereact/inputtextarea';
import EmpresaCompromissoService from '../../services/cruds/EmpresaCompromissoService';
import type { Vec } from '../../types/types';

type SelectOption = { label: string; value: string };
type PrazoFiltro = 'TODOS' | 'VENCENDO' | 'ATRASADOS' | 'FUTUROS';
type TableFilters = DataTableFilterMeta;

type RowData = {
    id: string;
    empresaNome: string;
    nome: string;
    categoria: string;
    vencimento: string;
    vencimentoOrdem: string;
    status: string;
    valorText: string;
    dataVencimentoISO: string;
    valorNum?: number | null;
    pendenteUrgencia?: 'ok' | 'warn' | 'overdue';
};

const TABLE_STATE_STORAGE_KEY = 'vecontab.compromissos-visao.datatable.v1';

const INITIAL_FILTERS: TableFilters = {
    empresaNome: { value: '', matchMode: FilterMatchMode.CONTAINS },
    nome: { value: '', matchMode: FilterMatchMode.CONTAINS },
    categoria: { value: null, matchMode: FilterMatchMode.EQUALS },
    vencimentoOrdem: { value: null, matchMode: FilterMatchMode.CUSTOM },
    valorText: { value: '', matchMode: FilterMatchMode.CONTAINS },
    status: { value: null, matchMode: FilterMatchMode.EQUALS },
};

const NATUREZA_FILTER_OPTIONS = [
    { label: 'Todas', value: null },
    { label: 'Tributária', value: 'Tributária' },
    { label: 'Informativa', value: 'Informativa' },
];

const STATUS_FILTER_OPTIONS = [
    { label: 'Pendente', value: 'pendente' },
    { label: 'Concluído', value: 'concluido' },
];

const PRAZO_FILTER_OPTIONS: Array<{ label: string; value: PrazoFiltro }> = [
    { label: 'Todos', value: 'TODOS' },
    { label: 'Vencendo', value: 'VENCENDO' },
    { label: 'Atrasados', value: 'ATRASADOS' },
    { label: 'Futuros', value: 'FUTUROS' },
];

const statusNorm = (s: string) => s.trim().toLowerCase();

const formatDate = (value?: string): string => {
    if (!value) return '';
    const [year, month, day] = value.split('-');
    if (!year || !month || !day) return value;
    return `${day}/${month}/${year}`;
};

function formatBRL(n: number | null | undefined): string {
    if (n == null || Number.isNaN(Number(n))) return '—';
    return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(Number(n));
}

function diffDiasParaHoje(isoDate?: string): number | null {
    if (!isoDate || isoDate.length < 10) return null;
    const alvo = new Date(`${isoDate.slice(0, 10)}T00:00:00`);
    if (Number.isNaN(alvo.getTime())) return null;
    const hoje = new Date();
    hoje.setHours(0, 0, 0, 0);
    return Math.floor((alvo.getTime() - hoje.getTime()) / 86400000);
}

function pendenteUrgenciaPorVencimento(isoDate: string): 'ok' | 'warn' | 'overdue' {
    const d = diffDiasParaHoje(isoDate);
    if (d == null) return 'ok';
    if (d < 0) return 'overdue';
    if (d <= 7) return 'warn';
    return 'ok';
}

function vencimentoOrdemFilter(value: unknown, filter: unknown): boolean {
    if (filter == null || !(filter instanceof Date) || Number.isNaN(filter.getTime())) return true;
    if (value == null || String(value).length < 10) return false;
    const dv = new Date(`${String(value).slice(0, 10)}T12:00:00`);
    return dv.toDateString() === filter.toDateString();
}

function emitFieldFilter(
    setFilters: Dispatch<SetStateAction<TableFilters>>,
    setFirst: Dispatch<SetStateAction<number>>,
    field: string,
    value: unknown,
    matchMode: string,
) {
    setFirst(0);
    setFilters((prev) => ({
        ...prev,
        [field]: { value, matchMode },
    }));
}

export default function CompromissosVisaoPage() {
    const [rowsData, setRowsData] = useState<RowData[]>([]);
    const [loading, setLoading] = useState(false);
    const [first, setFirst] = useState(0);
    const [rows, setRows] = useState(10);
    const [sortField, setSortField] = useState('empresaNome');
    const [sortOrder, setSortOrder] = useState<1 | -1>(1);
    const [globalFilterValue, setGlobalFilterValue] = useState('');
    const [globalFilterDraft, setGlobalFilterDraft] = useState('');
    const [filters, setFilters] = useState<TableFilters>(() => ({ ...INITIAL_FILTERS }));
    const [prazoFiltro, setPrazoFiltro] = useState<PrazoFiltro>('TODOS');
    const toast = useRef<Toast>(null);
    const svc = useMemo(() => EmpresaCompromissoService(), []);

    const [editDialog, setEditDialog] = useState(false);
    const [editId, setEditId] = useState('');
    const [editVenc, setEditVenc] = useState('');
    const [editValor, setEditValor] = useState<number | null>(null);
    const [createDialog, setCreateDialog] = useState(false);
    const [empresaOptions, setEmpresaOptions] = useState<SelectOption[]>([]);
    const [obrigacaoOptions, setObrigacaoOptions] = useState<SelectOption[]>([]);
    const [createEmpresaID, setCreateEmpresaID] = useState('');
    const [createObrigacaoID, setCreateObrigacaoID] = useState('');
    const [createDescricao, setCreateDescricao] = useState('');
    const [createVenc, setCreateVenc] = useState('');
    const [createValor, setCreateValor] = useState<number | null>(null);
    const [createObservacao, setCreateObservacao] = useState('');
    const [createStatus, setCreateStatus] = useState<'pendente' | 'concluido'>('pendente');
    const [createLoading, setCreateLoading] = useState(false);

    const load = () => {
        setLoading(true);
        svc.getAcompanhamento()
            .then(({ data }) => {
                const itens = (data.itens ?? []) as Vec.EmpresaAgendaAcompanhamentoItem[];
                const mapped: RowData[] = itens.map((item) => {
                    const aid = (item.agenda_item_id || '').trim();
                    const st = statusNorm(item.status || '');
                    const vencIso = (item.data_vencimento || '').trim();
                    const cls = (item.classificacao || '').toUpperCase();
                    const categoria = cls === 'FINANCEIRO' ? 'Tributária' : 'Informativa';
                    return {
                        id: aid,
                        empresaNome: item.empresa_nome || 'Empresa sem nome',
                        nome: item.descricao || 'Compromisso sem descrição',
                        categoria,
                        vencimento: formatDate(vencIso),
                        vencimentoOrdem: vencIso || '9999-12-31',
                        status: item.status || '',
                        valorText: formatBRL(item.valor_estimado ?? null),
                        dataVencimentoISO: vencIso,
                        valorNum: item.valor_estimado ?? null,
                        pendenteUrgencia: st === 'pendente' && vencIso.length >= 10 ? pendenteUrgenciaPorVencimento(vencIso) : 'ok',
                    };
                }).filter((r) => r.id);
                setRowsData(mapped);
                setFirst(0);
            })
            .catch((error: unknown) => {
                setRowsData([]);
                toast.current?.show({
                    severity: 'error',
                    summary: 'Erro',
                    detail: error instanceof Error ? error.message : 'Erro ao carregar compromissos',
                    life: 3000,
                });
            })
            .finally(() => setLoading(false));
    };

    const loadFormOptions = () => {
        svc.getFormOptions()
            .then(({ data }) => {
                const empresas: Array<{ id?: string; nome?: string }> = Array.isArray(data?.empresas) ? data.empresas : [];
                setEmpresaOptions(
                    empresas
                        .map((e) => ({ value: String(e.id || '').trim(), label: String(e.nome || '').trim() || 'Empresa sem nome' }))
                        .filter((e) => e.value !== ''),
                );
            })
            .catch(() => setEmpresaOptions([]));
    };

    const loadObrigacoesByEmpresa = (empresaID: string) => {
        if (!empresaID) {
            setObrigacaoOptions([]);
            setCreateObrigacaoID('');
            return;
        }
        svc.getObrigacoesByEmpresa(empresaID)
            .then(({ data }) => {
                const obrigacoes: Array<{ id?: string; descricao?: string }> = Array.isArray(data?.obrigacoes) ? data.obrigacoes : [];
                setObrigacaoOptions(
                    obrigacoes
                        .map((o) => ({ value: String(o.id || '').trim(), label: String(o.descricao || '').trim() || 'Obrigação sem descrição' }))
                        .filter((o) => o.value !== ''),
                );
            })
            .catch(() => setObrigacaoOptions([]));
    };

    useEffect(() => {
        if (typeof window === 'undefined') return;
        const raw = window.localStorage.getItem(TABLE_STATE_STORAGE_KEY);
        if (!raw) return;
        try {
            const parsed = JSON.parse(raw) as { first?: number; rows?: number; sortField?: string; sortOrder?: number };
            if (typeof parsed.first === 'number') setFirst(parsed.first);
            if (typeof parsed.rows === 'number') setRows(parsed.rows);
            if (typeof parsed.sortField === 'string' && parsed.sortField) setSortField(parsed.sortField);
            if (parsed.sortOrder === 1 || parsed.sortOrder === -1) setSortOrder(parsed.sortOrder);
        } catch {
            window.localStorage.removeItem(TABLE_STATE_STORAGE_KEY);
        }
    }, []);

    useEffect(() => {
        if (typeof window === 'undefined') return;
        window.localStorage.setItem(TABLE_STATE_STORAGE_KEY, JSON.stringify({ first, rows, sortField, sortOrder }));
    }, [first, rows, sortField, sortOrder]);

    useEffect(() => {
        load();
        loadFormOptions();
    }, []);

    const rowsFiltradosPrazo = useMemo(() => {
        if (prazoFiltro === 'TODOS') return rowsData;
        return rowsData.filter((r) => {
            const diff = diffDiasParaHoje(r.dataVencimentoISO);
            if (diff == null) return false;
            const st = statusNorm(r.status || '');
            if (prazoFiltro === 'VENCENDO') return diff >= 0 && diff <= 7;
            if (prazoFiltro === 'ATRASADOS') return diff < 0 && st === 'pendente';
            if (prazoFiltro === 'FUTUROS') return diff > 7;
            return true;
        });
    }, [rowsData, prazoFiltro]);

    const onPage = (event: { first?: number; rows?: number }) => {
        setFirst(typeof event.first === 'number' ? event.first : 0);
        setRows(typeof event.rows === 'number' && event.rows > 0 ? event.rows : rows);
    };

    const onSort: DataTableProps<RowData[]>['onSort'] = (event) => {
        setSortField(event.sortField || 'empresaNome');
        setSortOrder(event.sortOrder === -1 ? -1 : 1);
    };

    const clearFilters = () => {
        setFirst(0);
        setGlobalFilterValue('');
        setGlobalFilterDraft('');
        setFilters({ ...INITIAL_FILTERS });
        setPrazoFiltro('TODOS');
    };

    const statusBodyTemplate = (d: RowData) => {
        const st = statusNorm(d.status || '');
        if (st === 'concluido') return <Tag value="Concluído" style={{ background: '#a5d6a7', color: '#0d260d', fontWeight: 700, border: '1px solid #2e7d32' }} />;
        if (st === 'pendente') {
            if (d.pendenteUrgencia === 'warn') return <Tag value="Pendente" style={{ background: '#fff9c4', color: '#e65100' }} />;
            if (d.pendenteUrgencia === 'overdue') return <Tag value="Pendente" style={{ background: '#ffcdd2', color: '#b71c1c' }} />;
            return <Tag value="Pendente" style={{ background: '#c8e6c9', color: '#1b5e20' }} />;
        }
        return <Tag value={d.status || '—'} severity="warning" />;
    };

    const openEdit = (d: RowData) => {
        setEditId(d.id);
        setEditVenc((d.dataVencimentoISO || '').slice(0, 10));
        setEditValor(d.valorNum ?? null);
        setEditDialog(true);
    };

    const salvarEdicao = () => {
        if (!editId || !editVenc.trim()) {
            toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Informe a data de vencimento.', life: 3000 });
            return;
        }
        svc.updateItem({ id: editId, data_vencimento: editVenc.trim(), valor: editValor ?? undefined })
            .then(() => {
                toast.current?.show({ severity: 'success', summary: 'Salvo', detail: 'Compromisso atualizado.', life: 2500 });
                setEditDialog(false);
                load();
            })
            .catch(() => toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Não foi possível salvar.', life: 3500 }));
    };

    const toggleConcluido = (d: RowData) => {
        const next = statusNorm(d.status || '') === 'concluido' ? 'pendente' : 'concluido';
        svc.updateStatus({ id: d.id, status: next })
            .then(() => load())
            .catch(() => toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Não foi possível alterar o status.', life: 3500 }));
    };

    const rowClassName: DataTableProps<RowData[]>['rowClassName'] = (d) => {
        if (statusNorm(d?.status || '') === 'concluido') {
            return { 'vecontab-dash-concluido': true };
        }
        return {};
    };

    const abrirInclusaoManual = () => {
        setCreateEmpresaID('');
        setCreateObrigacaoID('');
        setCreateDescricao('');
        setCreateVenc('');
        setCreateValor(null);
        setCreateObservacao('');
        setCreateStatus('pendente');
        setObrigacaoOptions([]);
        setCreateDialog(true);
    };

    const salvarInclusaoManual = () => {
        if (!createEmpresaID || !createObrigacaoID || !createDescricao.trim() || !createVenc.trim()) {
            toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Preencha os campos obrigatórios.', life: 3000 });
            return;
        }
        setCreateLoading(true);
        svc.createManual({
            empresa_id: createEmpresaID,
            tipoempresa_obrigacao_id: createObrigacaoID,
            descricao: createDescricao.trim(),
            data_vencimento: createVenc.trim(),
            valor: createValor ?? undefined,
            observacao: createObservacao.trim() || undefined,
            status: createStatus,
        })
            .then(() => {
                toast.current?.show({ severity: 'success', summary: 'Incluído', detail: 'Compromisso incluído manualmente.', life: 2500 });
                setCreateDialog(false);
                load();
            })
            .catch((error: unknown) => toast.current?.show({
                severity: 'error',
                summary: 'Erro',
                detail: error instanceof Error ? error.message : 'Não foi possível incluir compromisso.',
                life: 3500,
            }))
            .finally(() => setCreateLoading(false));
    };

    const naturezaFilterEl = (
        <Dropdown
            value={filters.categoria?.value as string | null | undefined}
            options={NATUREZA_FILTER_OPTIONS}
            onChange={(e) => emitFieldFilter(setFilters, setFirst, 'categoria', e.value ?? null, FilterMatchMode.EQUALS)}
            placeholder="Natureza"
            showClear
            className="p-column-filter w-full"
        />
    );

    const statusFilterEl = (
        <Dropdown
            value={filters.status?.value as string | null | undefined}
            options={STATUS_FILTER_OPTIONS}
            onChange={(e) => emitFieldFilter(setFilters, setFirst, 'status', e.value ?? null, FilterMatchMode.EQUALS)}
            placeholder="Status"
            showClear
            className="p-column-filter w-full"
        />
    );

    const vencFilterVal = filters.vencimentoOrdem?.value instanceof Date ? filters.vencimentoOrdem.value : null;
    const vencimentoFilterEl = (
        <Calendar
            value={vencFilterVal}
            onChange={(e) => emitFieldFilter(setFilters, setFirst, 'vencimentoOrdem', e.value ?? null, FilterMatchMode.CUSTOM)}
            dateFormat="dd/mm/yy"
            showIcon
            showButtonBar
            className="p-column-filter w-full"
            inputClassName="w-full"
        />
    );

    return (
        <div className="card">
            <Toast ref={toast} />

            <div className="flex align-items-center justify-content-start mb-3">
                <Button icon="pi pi-plus" label="Incluir" severity="success" className=" mr-2" onClick={abrirInclusaoManual} tooltip="Inclusão Manual de Compromisso" />
                <div className="ml-2" style={{ minWidth: '16rem' }}>
                    <Dropdown value={prazoFiltro} options={PRAZO_FILTER_OPTIONS} onChange={(e) => { setPrazoFiltro((e.value as PrazoFiltro) || 'TODOS'); setFirst(0); }} className="w-full" />
                </div>
            </div>

            <div className="flex align-items-center justify-content-end gap-2 mb-2">
                <span className="p-input-icon-left w-full">
                    <i className="pi pi-search" />
                    <InputText
                        type="search"
                        value={globalFilterDraft}
                        onChange={(e) => {
                            setGlobalFilterDraft(e.target.value);
                            if (!e.target.value) {
                                setGlobalFilterValue('');
                                setFirst(0);
                            }
                        }}
                        onKeyDown={(e) => {
                            if (e.key === 'Enter') {
                                setGlobalFilterValue(globalFilterDraft);
                                setFirst(0);
                            }
                        }}
                        placeholder="Filtrar compromissos"
                        className="w-full"
                    />
                </span>
                <Button icon="pi pi-filter-slash" label="Limpar" severity="secondary" outlined onClick={clearFilters} />
            </div>

            <DataTable
                value={rowsFiltradosPrazo}
                loading={loading}
                rowClassName={rowClassName}
                paginator
                rows={rows}
                first={first}
                onPage={onPage}
                rowsPerPageOptions={[5, 10, 20, 50]}
                sortField={sortField}
                sortOrder={sortOrder}
                onSort={onSort}
                filters={filters}
                onFilter={(e) => {
                    setFirst(0);
                    setFilters(e.filters as TableFilters);
                }}
                globalFilter={globalFilterValue}
                globalFilterFields={['empresaNome', 'nome', 'valorText', 'status', 'categoria']}
                filterDisplay="row"
                emptyMessage="Nenhum compromisso gerado para empresas deste tenant"
                dataKey="id"
                size="small"
                stripedRows
            >
                <Column field="empresaNome" header="Empresa" sortable filter filterMatchMode={FilterMatchMode.CONTAINS} showFilterMenu={false} />
                <Column field="nome" header="Compromisso" sortable filter filterMatchMode={FilterMatchMode.CONTAINS} showFilterMenu={false} />
                <Column field="categoria" header="Natureza" sortable filter showFilterMenu={false} filterMatchMode={FilterMatchMode.EQUALS} filterElement={naturezaFilterEl} />
                <Column
                    field="vencimentoOrdem"
                    header="Vencimento"
                    sortable
                    filter
                    showFilterMenu={false}
                    filterMatchMode={FilterMatchMode.CUSTOM}
                    filterFunction={vencimentoOrdemFilter}
                    filterElement={vencimentoFilterEl}
                    body={(d: RowData) => d.vencimento || '—'}
                />
                <Column field="valorText" header="Valor" sortable filter filterMatchMode={FilterMatchMode.CONTAINS} showFilterMenu={false} />
                <Column field="status" header="Status" body={statusBodyTemplate} sortable filter showFilterMenu={false} filterMatchMode={FilterMatchMode.EQUALS} filterElement={statusFilterEl} />
                <Column
                    header="Ações"
                    body={(d: RowData) => (
                        <div className="flex gap-1 flex-wrap align-items-center vecontab-acoes-comp">
                            <Button
                                icon="pi pi-pencil"
                                rounded
                                outlined
                                severity="secondary"
                                onClick={() => openEdit(d)}
                                tooltip="Editar valor e vencimento"
                                tooltipOptions={{ position: 'left' }}
                                className="text-sm vecontab-comp-editar"
                            />
                            <Button
                                type="button"
                                label={statusNorm(d.status || '') === 'concluido' ? 'Reabrir' : 'Concluído'}
                                rounded
                                outlined
                                severity="secondary"
                                onClick={() => toggleConcluido(d)}
                                className={`text-sm ${statusNorm(d.status || '') === 'concluido' ? 'vecontab-comp-reabrir' : 'vecontab-comp-concluir'}`}
                            />
                        </div>
                    )}
                />
            </DataTable>

            <Dialog
                header="Editar compromisso"
                visible={editDialog}
                style={{ width: '420px' }}
                onHide={() => setEditDialog(false)}
                footer={
                    <>
                        <Button label="Cancelar" icon="pi pi-times" text onClick={() => setEditDialog(false)} />
                        <Button label="Salvar" icon="pi pi-check" text onClick={salvarEdicao} />
                    </>
                }
            >
                <div className="field">
                    <label htmlFor="editVencCv" className="block mb-1">Vencimento</label>
                    <input id="editVencCv" type="date" className="p-inputtext p-component w-full" value={editVenc} onChange={(e) => setEditVenc(e.target.value)} />
                </div>
                <div className="field">
                    <label htmlFor="editValorCv" className="block mb-1">Valor (R$)</label>
                    <InputNumber id="editValorCv" value={editValor ?? undefined} onChange={(e) => setEditValor(e.value ?? null)} mode="currency" currency="BRL" locale="pt-BR" className="w-full" />
                </div>
            </Dialog>

            <Dialog
                header="Inclusão Manual de Compromisso"
                visible={createDialog}
                style={{ width: '640px' }}
                onHide={() => setCreateDialog(false)}
                footer={
                    <>
                        <Button label="Cancelar" icon="pi pi-times" text onClick={() => setCreateDialog(false)} disabled={createLoading} />
                        <Button label="Salvar" icon="pi pi-check" text onClick={salvarInclusaoManual} loading={createLoading} />
                    </>
                }
            >
                <div className="formgrid grid">
                    <div className="field col-12 md:col-6">
                        <label className="block mb-1">Empresa</label>
                        <Dropdown
                            value={createEmpresaID}
                            options={empresaOptions}
                            onChange={(e) => {
                                const next = String(e.value || '');
                                setCreateEmpresaID(next);
                                setCreateObrigacaoID('');
                                loadObrigacoesByEmpresa(next);
                            }}
                            filter
                            showClear
                            placeholder="Selecione a empresa"
                            className="w-full"
                        />
                    </div>
                    <div className="field col-12 md:col-6">
                        <label className="block mb-1">Obrigação</label>
                        <Dropdown
                            value={createObrigacaoID}
                            options={obrigacaoOptions}
                            onChange={(e) => setCreateObrigacaoID(String(e.value || ''))}
                            filter
                            showClear
                            placeholder="Selecione a obrigação"
                            className="w-full"
                            disabled={!createEmpresaID}
                        />
                    </div>
                    <div className="field col-12 md:col-8">
                        <label className="block mb-1">Descrição</label>
                        <InputText value={createDescricao} onChange={(e) => setCreateDescricao(e.target.value)} className="w-full" />
                    </div>
                    <div className="field col-12 md:col-4">
                        <label className="block mb-1">Status</label>
                        <Dropdown
                            value={createStatus}
                            options={[{ label: 'Pendente', value: 'pendente' }, { label: 'Concluído', value: 'concluido' }]}
                            onChange={(e) => setCreateStatus((e.value as 'pendente' | 'concluido') || 'pendente')}
                            className="w-full"
                        />
                    </div>
                    <div className="field col-12 md:col-6">
                        <label className="block mb-1">Vencimento</label>
                        <input type="date" className="p-inputtext p-component w-full" value={createVenc} onChange={(e) => setCreateVenc(e.target.value)} />
                    </div>
                    <div className="field col-12 md:col-6">
                        <label className="block mb-1">Valor (R$)</label>
                        <InputNumber value={createValor ?? undefined} onChange={(e) => setCreateValor(e.value ?? null)} mode="currency" currency="BRL" locale="pt-BR" className="w-full" />
                    </div>
                    <div className="field col-12">
                        <label className="block mb-1">Observação</label>
                        <InputTextarea value={createObservacao} onChange={(e) => setCreateObservacao(e.target.value)} rows={3} className="w-full" />
                    </div>
                </div>
            </Dialog>

            <style jsx>{`
                :global(.p-datatable .p-datatable-tbody > tr.vecontab-dash-concluido > td) {
                    background-color: #d5e0d6 !important;
                    color: #0d1f0d !important;
                }
                :global(.p-datatable .p-datatable-tbody > tr.vecontab-dash-concluido .vecontab-acoes-comp .p-button) {
                    color: #1b5e20 !important;
                }
                :global(.p-datatable .p-datatable-tbody > tr.vecontab-dash-concluido .vecontab-comp-editar.p-button-outlined) {
                    color: #1b3d24 !important;
                    border-color: #2e7d32 !important;
                }
                :global(.p-datatable .p-datatable-tbody > tr.vecontab-dash-concluido .vecontab-comp-editar.p-button-outlined:not(:disabled):hover) {
                    background: rgba(27, 94, 32, 0.12) !important;
                    color: #0d260d !important;
                }
                :global(.vecontab-comp-concluir.p-button.p-button-outlined) {
                    color: #009c3b !important;
                    border-color: #009c3b !important;
                }
                :global(.vecontab-comp-concluir.p-button.p-button-outlined:not(:disabled):hover) {
                    background: rgba(0, 156, 59, 0.12) !important;
                    color: #006b29 !important;
                    border-color: #006b29 !important;
                }
                :global(tr:not(.vecontab-dash-concluido) .vecontab-comp-reabrir.p-button.p-button-outlined) {
                    color: #37474f !important;
                    border-color: #78909c !important;
                }
                :global(.p-datatable .p-datatable-tbody > tr.vecontab-dash-concluido .vecontab-comp-reabrir.p-button-outlined) {
                    color: #0d260d !important;
                    border-color: #1b5e20 !important;
                    font-weight: 600;
                }
                :global(.p-datatable .p-datatable-tbody > tr.vecontab-dash-concluido .vecontab-comp-reabrir.p-button-outlined:not(:disabled):hover) {
                    background: rgba(13, 38, 13, 0.08) !important;
                }
            `}</style>
        </div>
    );
}

export const getServerSideProps = canSSRAuth(async () => {
    return { props: {} };
});
