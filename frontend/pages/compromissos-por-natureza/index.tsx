import { useCallback, useEffect, useMemo, useRef, useState, type Dispatch, type SetStateAction } from 'react';
import { canSSRAuth } from '../../components/utils/canSSRAuth';
import { TreeTable } from 'primereact/treetable';
import type { TreeTableProps } from 'primereact/treetable';
import { Column } from 'primereact/column';
import { Button } from 'primereact/button';
import { InputText } from 'primereact/inputtext';
import { InputNumber } from 'primereact/inputnumber';
import { Dialog } from 'primereact/dialog';
import { Tag } from 'primereact/tag';
import { Toast } from 'primereact/toast';
import { TreeNode } from 'primereact/treenode';
import { FilterMatchMode } from 'primereact/api';
import { Calendar } from 'primereact/calendar';
import { Dropdown } from 'primereact/dropdown';
import { InputTextarea } from 'primereact/inputtextarea';
import EmpresaCompromissoService from '../../services/cruds/EmpresaCompromissoService';
import type { Vec } from '../../types/types';

type NodeData = {
    nome: string;
    tipoNo: 'NATUREZA' | 'EMPRESA' | 'COMPROMISSO';
    categoria: string;
    vencimento: string;
    vencimentoOrdem: string;
    status: string;
    valorText: string;
    agendaItemId?: string;
    dataVencimentoISO?: string;
    valorNum?: number | null;
    pendenteUrgencia?: 'ok' | 'warn' | 'overdue';
};

type TableFilters = NonNullable<TreeTableProps['filters']>;
type SelectOption = { label: string; value: string };
type PrazoFiltro = 'TODOS' | 'VENCENDO' | 'ATRASADOS' | 'FUTUROS';

const TABLE_STATE_STORAGE_KEY = 'vecontab.compromissos-por-natureza.treetable.v1';

/** Verde bandeira (aprox.) para ação "Concluído" */
const VERDE_BANDEIRA = '#009c3b';
const VERDE_BANDEIRA_ESCURO = '#006b29';

/** PrimeReact Dropdown não trata '' como opção válida; use null para “sem filtro”. */
const INITIAL_FILTERS: TableFilters = {
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

const formatDate = (value?: string): string => {
    if (!value) {
        return '';
    }
    const [year, month, day] = value.split('-');
    if (!year || !month || !day) {
        return value;
    }
    return `${day}/${month}/${year}`;
};

function pendenteUrgenciaPorVencimento(isoDate: string): 'ok' | 'warn' | 'overdue' {
    if (!isoDate || isoDate.length < 10) {
        return 'ok';
    }
    const fim = new Date(`${isoDate.slice(0, 10)}T23:59:59`);
    const hoje = new Date();
    hoje.setHours(0, 0, 0, 0);
    const diffDias = Math.floor((fim.getTime() - hoje.getTime()) / 86400000);
    if (diffDias < 0) {
        return 'overdue';
    }
    if (diffDias <= 7) {
        return 'warn';
    }
    return 'ok';
}

function formatBRL(n: number | null | undefined): string {
    if (n == null || Number.isNaN(Number(n))) {
        return '—';
    }
    return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(Number(n));
}

const defaultExpandedKeys = (roots: TreeNode[]): Record<string, boolean> => {
    const keys: Record<string, boolean> = {};
    for (const nat of roots) {
        if (nat.key) {
            keys[nat.key] = true;
        }
        for (const emp of nat.children || []) {
            if (emp.key) {
                keys[emp.key] = true;
            }
        }
    }
    return keys;
};

const statusNorm = (s: string) => s.trim().toLowerCase();

function diffDiasParaHoje(isoDate?: string): number | null {
    if (!isoDate || isoDate.length < 10) {
        return null;
    }
    const alvo = new Date(`${isoDate.slice(0, 10)}T00:00:00`);
    if (Number.isNaN(alvo.getTime())) {
        return null;
    }
    const hoje = new Date();
    hoje.setHours(0, 0, 0, 0);
    return Math.floor((alvo.getTime() - hoje.getTime()) / 86400000);
}

function vencimentoOrdemFilter(value: unknown, filter: unknown): boolean {
    if (filter == null || !(filter instanceof Date) || Number.isNaN(filter.getTime())) {
        return true;
    }
    if (value == null || String(value).length < 10) {
        return false;
    }
    const dv = new Date(`${String(value).slice(0, 10)}T12:00:00`);
    return dv.toDateString() === filter.toDateString();
}

type TreeTableFilterEvent =
    | { filters: TableFilters }
    | { value: unknown; field: string; matchMode?: string };

function isWrappedFilters(e: TreeTableFilterEvent): e is { filters: TableFilters } {
    return 'filters' in e && e.filters != null && typeof e.filters === 'object';
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
        [field]: { value, matchMode } as TableFilters[string],
    }));
}

export default function CompromissosPorNaturezaPage() {
    const [nodes, setNodes] = useState<TreeNode[]>([]);
    const [expandedKeys, setExpandedKeys] = useState<Record<string, boolean>>({});
    const [loading, setLoading] = useState(false);
    const [first, setFirst] = useState(0);
    const [rows, setRows] = useState(10);
    const [sortField, setSortField] = useState('nome');
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

    const onTreeFilter = useCallback((event: unknown) => {
        setFirst(0);
        const e = event as TreeTableFilterEvent;
        if (isWrappedFilters(e)) {
            setFilters({ ...e.filters });
            return;
        }
        if (e && typeof e === 'object' && 'field' in e) {
            const { field, value, matchMode } = e as { field: string; value: unknown; matchMode?: string };
            setFilters((prev) => ({
                ...prev,
                [field]: {
                    value: value as never,
                    matchMode: (matchMode || (prev[field] as { matchMode?: string } | undefined)?.matchMode || FilterMatchMode.CONTAINS) as never,
                },
            }));
        }
    }, []);

    const buildTree = (itens: Vec.EmpresaAgendaAcompanhamentoItem[]): TreeNode[] => {
        const byNatureza = new Map<string, Map<string, { nome: string; itens: Vec.EmpresaAgendaAcompanhamentoItem[] }>>();

        for (const item of itens || []) {
            const empresaID = item.empresa_id || '';
            if (!empresaID) {
                continue;
            }
            const cls = (item.classificacao || '').toUpperCase();
            const natureza = cls === 'FINANCEIRO' ? 'Tributária' : 'Informativa';
            if (!byNatureza.has(natureza)) {
                byNatureza.set(natureza, new Map());
            }
            const byEmpresa = byNatureza.get(natureza)!;
            const cur = byEmpresa.get(empresaID);
            if (cur) {
                cur.itens.push(item);
            } else {
                byEmpresa.set(empresaID, {
                    nome: item.empresa_nome || 'Empresa sem nome',
                    itens: [item],
                });
            }
        }

        const ordemNatureza = ['Tributária', 'Informativa'];
        const roots: TreeNode[] = [];

        for (const natLabel of ordemNatureza) {
            const byEmpresa = byNatureza.get(natLabel);
            if (!byEmpresa || byEmpresa.size === 0) {
                continue;
            }

            const orderedEmp = Array.from(byEmpresa.entries()).sort((a, b) =>
                (a[1].nome || '').localeCompare(b[1].nome || '', 'pt-BR', { sensitivity: 'base' }),
            );

            const empresaNodes: TreeNode[] = orderedEmp.map(([empresaID, emp]) => {
                const children: TreeNode[] = [];
                for (const item of emp.itens) {
                    const aid = (item.agenda_item_id || '').trim();
                    if (!aid) {
                        continue;
                    }
                    const st = statusNorm(item.status || '');
                    const vencIso = (item.data_vencimento || '').trim();
                    let pendUrg: 'ok' | 'warn' | 'overdue' | undefined;
                    if (st === 'pendente' && vencIso.length >= 10) {
                        pendUrg = pendenteUrgenciaPorVencimento(vencIso);
                    }
                    const cls = (item.classificacao || '').toUpperCase();
                    const categoria = cls === 'FINANCEIRO' ? 'Tributária' : 'Informativa';
                    children.push({
                        key: `cmp-${aid}`,
                        data: {
                            nome: item.descricao || 'Compromisso sem descrição',
                            tipoNo: 'COMPROMISSO',
                            categoria,
                            vencimento: formatDate(item.data_vencimento),
                            vencimentoOrdem: vencIso || '9999-12-31',
                            status: item.status || '',
                            valorText: formatBRL(item.valor_estimado ?? null),
                            agendaItemId: aid,
                            dataVencimentoISO: vencIso,
                            valorNum: item.valor_estimado ?? null,
                            pendenteUrgencia: pendUrg,
                        },
                    });
                }
                children.sort((a, b) => (a.data?.vencimentoOrdem || '').localeCompare(b.data?.vencimentoOrdem || ''));

                return {
                    key: `${natLabel}-emp-${empresaID}`,
                    data: {
                        nome: emp.nome,
                        tipoNo: 'EMPRESA',
                        categoria: '',
                        vencimento: '',
                        vencimentoOrdem: '',
                        status: '',
                        valorText: '',
                    },
                    children,
                };
            });

            roots.push({
                key: `nat-${natLabel}`,
                data: {
                    nome: natLabel,
                    tipoNo: 'NATUREZA',
                    categoria: natLabel,
                    vencimento: '',
                    vencimentoOrdem: '',
                    status: '',
                    valorText: '',
                },
                children: empresaNodes,
            });
        }

        return roots;
    };

    const load = () => {
        setLoading(true);
        svc.getAcompanhamento()
            .then(({ data }) => {
                const itens = (data.itens ?? []) as Vec.EmpresaAgendaAcompanhamentoItem[];
                const tree = buildTree(itens);
                setNodes(tree);
                setExpandedKeys(defaultExpandedKeys(tree));
                setFirst(0);
            })
            .catch((error: unknown) => {
                setNodes([]);
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
                const opts: SelectOption[] = empresas
                    .map((e: { id?: string; nome?: string }) => ({
                        value: String(e.id || '').trim(),
                        label: String(e.nome || '').trim() || 'Empresa sem nome',
                    }))
                    .filter((e: SelectOption) => e.value !== '');
                setEmpresaOptions(opts);
            })
            .catch(() => {
                setEmpresaOptions([]);
            });
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
                const opts: SelectOption[] = obrigacoes
                    .map((o: { id?: string; descricao?: string }) => ({
                        value: String(o.id || '').trim(),
                        label: String(o.descricao || '').trim() || 'Obrigação sem descrição',
                    }))
                    .filter((o: SelectOption) => o.value !== '');
                setObrigacaoOptions(opts);
            })
            .catch(() => {
                setObrigacaoOptions([]);
            });
    };

    useEffect(() => {
        if (typeof window === 'undefined') {
            return;
        }
        const raw = window.localStorage.getItem(TABLE_STATE_STORAGE_KEY);
        if (!raw) {
            return;
        }
        try {
            const parsed = JSON.parse(raw) as {
                first?: number;
                rows?: number;
                sortField?: string;
                sortOrder?: number;
            };
            if (typeof parsed.first === 'number') {
                setFirst(parsed.first);
            }
            if (typeof parsed.rows === 'number') {
                setRows(parsed.rows);
            }
            if (typeof parsed.sortField === 'string' && parsed.sortField) {
                setSortField(parsed.sortField === 'vencimento' ? 'vencimentoOrdem' : parsed.sortField);
            }
            if (parsed.sortOrder === 1 || parsed.sortOrder === -1) {
                setSortOrder(parsed.sortOrder);
            }
        } catch {
            window.localStorage.removeItem(TABLE_STATE_STORAGE_KEY);
        }
    }, []);

    useEffect(() => {
        if (typeof window === 'undefined') {
            return;
        }
        window.localStorage.setItem(
            TABLE_STATE_STORAGE_KEY,
            JSON.stringify({ first, rows, sortField, sortOrder }),
        );
    }, [first, rows, sortField, sortOrder]);

    useEffect(() => {
        load();
        loadFormOptions();
    }, []);

    const onGlobalFilterChange = (value: string) => {
        setGlobalFilterDraft(value);
        if (!value) {
            setGlobalFilterValue('');
            setFirst(0);
        }
    };

    const applyGlobalFilter = () => {
        setGlobalFilterValue(globalFilterDraft);
        setFirst(0);
    };

    const onPage = (event: { first?: number; rows?: number }) => {
        const nextFirst = typeof event.first === 'number' ? event.first : 0;
        const nextRows = typeof event.rows === 'number' && event.rows > 0 ? event.rows : rows;
        setFirst(nextFirst);
        setRows(nextRows);
    };

    const onSort: TreeTableProps['onSort'] = (event) => {
        setSortField(event.sortField || 'nome');
        setSortOrder(event.sortOrder === -1 ? -1 : 1);
    };

    const clearFilters = () => {
        setFirst(0);
        setGlobalFilterValue('');
        setGlobalFilterDraft('');
        setFilters({ ...INITIAL_FILTERS });
        setPrazoFiltro('TODOS');
    };

    const nodesFiltradosPorPrazo = useMemo(() => {
        if (prazoFiltro === 'TODOS') {
            return nodes;
        }
        const filtrarCompromissos = (child: TreeNode) => {
            const d = child.data as NodeData | undefined;
            if (d?.tipoNo !== 'COMPROMISSO') {
                return false;
            }
            const diff = diffDiasParaHoje(d.dataVencimentoISO);
            if (diff == null) {
                return false;
            }
            const st = statusNorm(d.status || '');
            switch (prazoFiltro) {
                case 'VENCENDO':
                    return diff >= 0 && diff <= 7;
                case 'ATRASADOS':
                    return diff < 0 && st === 'pendente';
                case 'FUTUROS':
                    return diff > 7;
                default:
                    return true;
            }
        };

        const filtrados: TreeNode[] = [];
        for (const nat of nodes) {
            const empresasFiltradas: TreeNode[] = [];
            for (const emp of nat.children || []) {
                const filhos = (emp.children || []).filter(filtrarCompromissos);
                if (filhos.length > 0) {
                    empresasFiltradas.push({ ...emp, children: filhos });
                }
            }
            if (empresasFiltradas.length > 0) {
                filtrados.push({ ...nat, children: empresasFiltradas });
            }
        }
        return filtrados;
    }, [nodes, prazoFiltro]);

    const pendenteCorUrgencia = (u: 'ok' | 'warn' | 'overdue' | undefined) => {
        if (u === 'warn') {
            return '#f9a825';
        }
        if (u === 'overdue') {
            return '#c62828';
        }
        return undefined;
    };

    const nomeBodyTemplate = (node: TreeNode) => {
        const d = node?.data as NodeData | undefined;
        const base = d?.nome ?? '';
        if (d?.tipoNo === 'NATUREZA') {
            return <span className="font-bold text-primary text-lg">{base}</span>;
        }
        if (d?.tipoNo === 'EMPRESA') {
            return <span className="font-semibold text-900">{base}</span>;
        }
        const st = statusNorm(d?.status || '');
        const u = d?.pendenteUrgencia;
        const color = st === 'pendente' ? pendenteCorUrgencia(u) : undefined;
        return (
            <span
                className={`font-medium${st === 'concluido' ? ' vecontab-cell-concluido' : ''}`}
                style={color ? { color } : undefined}
            >
                {base}
            </span>
        );
    };

    const statusBodyTemplate = (node: TreeNode) => {
        const d = node?.data as NodeData | undefined;
        const st = statusNorm(d?.status || '');
        if (!st) {
            return null;
        }
        if (st === 'concluido') {
            return (
                <Tag
                    value="Concluído"
                    style={{
                        background: '#a5d6a7',
                        color: '#0d260d',
                        fontWeight: 700,
                        border: '1px solid #2e7d32',
                    }}
                />
            );
        }
        if (st === 'pendente') {
            const u = d?.pendenteUrgencia ?? 'ok';
            let style = { background: '#c8e6c9', color: '#1b5e20' };
            if (u === 'warn') {
                style = { background: '#fff9c4', color: '#e65100' };
            }
            if (u === 'overdue') {
                style = { background: '#ffcdd2', color: '#b71c1c' };
            }
            return <Tag value="Pendente" style={style} />;
        }
        return <Tag value={d!.status} severity="warning" />;
    };

    const vencimentoBodyTemplate = (node: TreeNode) => {
        const d = node?.data as NodeData | undefined;
        if (d?.tipoNo !== 'COMPROMISSO') {
            return null;
        }
        const t = d?.vencimento?.trim();
        const st = statusNorm(d?.status || '');
        const u = d?.pendenteUrgencia;
        const color = st === 'pendente' ? pendenteCorUrgencia(u) : undefined;
        return (
            <span
                className={st === 'concluido' ? 'vecontab-cell-concluido' : undefined}
                style={color ? { color, fontWeight: 600 } : undefined}
            >
                {t || '—'}
            </span>
        );
    };

    const valorBodyTemplate = (node: TreeNode) => {
        const d = node?.data as NodeData | undefined;
        if (d?.tipoNo !== 'COMPROMISSO') {
            return null;
        }
        const st = statusNorm(d?.status || '');
        return (
            <span className={st === 'concluido' ? 'vecontab-cell-concluido' : undefined}>{d?.valorText ?? '—'}</span>
        );
    };

    const openEdit = (node: TreeNode) => {
        const d = node.data as NodeData | undefined;
        const id = d?.agendaItemId;
        if (!id) {
            return;
        }
        setEditId(id);
        setEditVenc((d?.dataVencimentoISO || '').slice(0, 10));
        setEditValor(d?.valorNum ?? null);
        setEditDialog(true);
    };

    const salvarEdicao = () => {
        if (!editId || !editVenc.trim()) {
            toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Informe a data de vencimento.', life: 3000 });
            return;
        }
        svc.updateItem({
            id: editId,
            data_vencimento: editVenc.trim(),
            valor: editValor ?? undefined,
        })
            .then(() => {
                toast.current?.show({ severity: 'success', summary: 'Salvo', detail: 'Compromisso atualizado.', life: 2500 });
                setEditDialog(false);
                load();
            })
            .catch(() => {
                toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Não foi possível salvar.', life: 3500 });
            });
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
        if (!createEmpresaID) {
            toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Selecione a empresa.', life: 3000 });
            return;
        }
        if (!createObrigacaoID) {
            toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Selecione a obrigação.', life: 3000 });
            return;
        }
        if (!createDescricao.trim()) {
            toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Informe a descrição.', life: 3000 });
            return;
        }
        if (!createVenc.trim()) {
            toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Informe o vencimento.', life: 3000 });
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
            .catch((error: unknown) => {
                toast.current?.show({
                    severity: 'error',
                    summary: 'Erro',
                    detail: error instanceof Error ? error.message : 'Não foi possível incluir compromisso.',
                    life: 3500,
                });
            })
            .finally(() => setCreateLoading(false));
    };

    const toggleConcluido = (node: TreeNode) => {
        const d = node.data as NodeData | undefined;
        const id = d?.agendaItemId;
        if (!id) {
            return;
        }
        const st = statusNorm(d?.status || '');
        const next = st === 'concluido' ? 'pendente' : 'concluido';
        svc.updateStatus({ id, status: next })
            .then(() => load())
            .catch(() => {
                toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Não foi possível alterar o status.', life: 3500 });
            });
    };

    const acoesBodyTemplate = (node: TreeNode) => {
        const d = node?.data as NodeData | undefined;
        if (d?.tipoNo !== 'COMPROMISSO' || !d?.agendaItemId) {
            return null;
        }
        const st = statusNorm(d?.status || '');
        return (
            <div className="flex gap-1 flex-wrap align-items-center vecontab-acoes-comp">
                <Button
                    type="button"
                    icon="pi pi-pencil"
                    rounded
                    outlined
                    severity="secondary"
                    onClick={() => openEdit(node)}
                    tooltip="Editar valor e vencimento"
                    tooltipOptions={{ position: 'left' }}
                    className="text-sm vecontab-comp-editar"
                />
                <Button
                    type="button"
                    label={st === 'concluido' ? 'Reabrir' : 'Concluído'}
                    rounded
                    outlined
                    severity="secondary"
                    onClick={() => toggleConcluido(node)}
                    className={`text-sm ${st === 'concluido' ? 'vecontab-comp-reabrir' : 'vecontab-comp-concluir'}`}
                />
            </div>
        );
    };

    const rowClassName = (node: TreeNode) => {
        const d = node?.data as NodeData | undefined;
        if (d?.tipoNo === 'COMPROMISSO' && statusNorm(d?.status || '') === 'concluido') {
            return { 'vecontab-dash-concluido': true };
        }
        return {};
    };

    const naturezaFilterEl = (
        <Dropdown
            value={filters.categoria?.value as string | null | undefined}
            options={NATUREZA_FILTER_OPTIONS}
            onChange={(e) =>
                emitFieldFilter(setFilters, setFirst, 'categoria', e.value ?? null, FilterMatchMode.EQUALS)
            }
            placeholder="Natureza"
            showClear
            className="p-column-filter w-full"
            style={{ minWidth: '10rem' }}
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
            style={{ minWidth: '10rem' }}
        />
    );

    const vencFilterVal = filters.vencimentoOrdem?.value instanceof Date ? filters.vencimentoOrdem.value : null;

    const vencimentoFilterEl = (
        <Calendar
            value={vencFilterVal}
            onChange={(e) =>
                emitFieldFilter(setFilters, setFirst, 'vencimentoOrdem', e.value ?? null, FilterMatchMode.CUSTOM)
            }
            dateFormat="dd/mm/yy"
            showIcon
            showButtonBar
            className="p-column-filter w-full"
            inputClassName="w-full"
        />
    );

    const tableHeader = (
        <div className="flex align-items-center justify-content-end gap-2 tree-global-filter">
            <div className="flex align-items-center gap-2 w-full">
                <span className="p-input-icon-left w-full">
                    <i className="pi pi-search" />
                    <InputText
                        type="search"
                        value={globalFilterDraft}
                        onChange={(e) => onGlobalFilterChange(e.target.value)}
                        onKeyDown={(e) => {
                            if (e.key === 'Enter') {
                                applyGlobalFilter();
                            }
                        }}
                        placeholder="Filtrar em toda a árvore"
                        className="w-full"
                    />
                </span>
                <Button icon="pi pi-filter-slash" label="Limpar" severity="secondary" outlined onClick={clearFilters} />
            </div>
        </div>
    );

    return (
        <div className="card">
            <Toast ref={toast} />

            <div className="mb-4">
                <h1 className="m-0 text-2xl font-bold text-900">Compromissos por natureza</h1>
                <p className="mt-2 mb-0 text-600 line-height-3 text-sm">
                    Visão em árvore: <strong>Tributária</strong> ou <strong>Informativa</strong>, depois empresa e compromissos (mesma base de dados e edição que Compromissos por Empresas).
                </p>
            </div>

            <div className="flex align-items-center justify-content-start mb-3">
                <Button
                    icon="pi pi-plus"
                    label="Incluir"
                    severity="success"
                    className=" mr-2"
                    onClick={abrirInclusaoManual}
                    tooltip="Inclusão Manual de Compromisso"
                />
                <div className="ml-2" style={{ minWidth: '16rem' }}>
                    <Dropdown
                        value={prazoFiltro}
                        options={PRAZO_FILTER_OPTIONS}
                        onChange={(e) => {
                            setPrazoFiltro((e.value as PrazoFiltro) || 'TODOS');
                            setFirst(0);
                        }}
                        className="w-full"
                    />
                </div>
            </div>

            <TreeTable
                value={nodesFiltradosPorPrazo}
                loading={loading}
                expandedKeys={expandedKeys}
                onToggle={(e: { value: Record<string, boolean> }) => setExpandedKeys(e.value)}
                rowClassName={rowClassName}
                paginator
                rows={rows}
                first={first}
                onPage={onPage}
                rowsPerPageOptions={[5, 10, 20, 50]}
                sortMode="single"
                sortField={sortField}
                sortOrder={sortOrder}
                onSort={onSort}
                filters={filters}
                onFilter={onTreeFilter}
                globalFilter={globalFilterValue}
                globalFilterMatchMode={FilterMatchMode.CONTAINS}
                filterMode="lenient"
                header={tableHeader}
                tableStyle={{ minWidth: '55rem' }}
                emptyMessage="Nenhum compromisso gerado para empresas deste tenant"
            >
                <Column
                    field="nome"
                    header="Natureza / Empresa / Compromisso"
                    expander
                    sortable
                    filter
                    filterMatchMode={FilterMatchMode.CONTAINS}
                    showFilterMenu={false}
                    filterPlaceholder="Natureza, empresa ou descrição do compromisso"
                    body={nomeBodyTemplate}
                    style={{ width: '34%' }}
                />
                <Column
                    field="categoria"
                    header="Natureza"
                    sortable
                    filter
                    showFilterMenu={false}
                    filterMatchMode={FilterMatchMode.EQUALS}
                    filterElement={naturezaFilterEl}
                    style={{ width: '14%' }}
                />
                <Column
                    field="vencimentoOrdem"
                    header="Vencimento"
                    sortable
                    filter
                    showFilterMenu={false}
                    filterMatchMode={FilterMatchMode.CUSTOM}
                    filterFunction={vencimentoOrdemFilter}
                    filterElement={vencimentoFilterEl}
                    body={vencimentoBodyTemplate}
                    style={{ width: '12%' }}
                />
                <Column field="valorText" header="Valor" sortable filter filterPlaceholder="Filtrar" body={valorBodyTemplate} style={{ width: '12%' }} />
                <Column
                    field="status"
                    header="Status"
                    body={statusBodyTemplate}
                    sortable
                    filter
                    showFilterMenu={false}
                    filterMatchMode={FilterMatchMode.EQUALS}
                    filterElement={statusFilterEl}
                    style={{ width: '14%' }}
                />
                <Column header="Ações" body={acoesBodyTemplate} style={{ width: '14%' }} />
            </TreeTable>

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
                    <label htmlFor="editVencCe" className="block mb-1">
                        Vencimento
                    </label>
                    <input
                        id="editVencCe"
                        type="date"
                        className="p-inputtext p-component w-full"
                        value={editVenc}
                        onChange={(e) => setEditVenc(e.target.value)}
                    />
                </div>
                <div className="field">
                    <label htmlFor="editValorCe" className="block mb-1">
                        Valor (R$)
                    </label>
                    <InputNumber
                        id="editValorCe"
                        value={editValor ?? undefined}
                        onChange={(e) => setEditValor(e.value ?? null)}
                        mode="currency"
                        currency="BRL"
                        locale="pt-BR"
                        className="w-full"
                    />
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
                            options={[
                                { label: 'Pendente', value: 'pendente' },
                                { label: 'Concluído', value: 'concluido' },
                            ]}
                            onChange={(e) => setCreateStatus((e.value as 'pendente' | 'concluido') || 'pendente')}
                            className="w-full"
                        />
                    </div>
                    <div className="field col-12 md:col-6">
                        <label className="block mb-1">Vencimento</label>
                        <input
                            type="date"
                            className="p-inputtext p-component w-full"
                            value={createVenc}
                            onChange={(e) => setCreateVenc(e.target.value)}
                        />
                    </div>
                    <div className="field col-12 md:col-6">
                        <label className="block mb-1">Valor (R$)</label>
                        <InputNumber
                            value={createValor ?? undefined}
                            onChange={(e) => setCreateValor(e.value ?? null)}
                            mode="currency"
                            currency="BRL"
                            locale="pt-BR"
                            className="w-full"
                        />
                    </div>
                    <div className="field col-12">
                        <label className="block mb-1">Observação</label>
                        <InputTextarea
                            value={createObservacao}
                            onChange={(e) => setCreateObservacao(e.target.value)}
                            rows={3}
                            className="w-full"
                        />
                    </div>
                </div>
            </Dialog>

            <div className="flex align-items-center justify-content-start mt-3">
                <Button icon="pi pi-refresh" className="p-button-text" tooltip="Atualizar" onClick={load} loading={loading} />
            </div>

            <style jsx>{`
                .tree-global-filter {
                    min-width: 20rem;
                }
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-dash-concluido > td) {
                    background-color: #d5e0d6 !important;
                    color: #0d1f0d !important;
                }
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-dash-concluido .vecontab-cell-concluido) {
                    color: #0d1f0d !important;
                    font-weight: 600;
                }
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-dash-concluido .vecontab-acoes-comp .p-button) {
                    color: #1b5e20 !important;
                }
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-dash-concluido .vecontab-comp-editar.p-button-outlined) {
                    color: #1b3d24 !important;
                    border-color: #2e7d32 !important;
                }
                :global(
                        .p-treetable
                            .p-treetable-tbody
                            > tr.vecontab-dash-concluido
                            .vecontab-comp-editar.p-button-outlined:not(:disabled):hover
                    ) {
                    background: rgba(27, 94, 32, 0.12) !important;
                    color: #0d260d !important;
                }
                :global(.vecontab-comp-concluir.p-button.p-button-outlined) {
                    color: ${VERDE_BANDEIRA} !important;
                    border-color: ${VERDE_BANDEIRA} !important;
                }
                :global(.vecontab-comp-concluir.p-button.p-button-outlined:not(:disabled):hover) {
                    background: rgba(0, 156, 59, 0.12) !important;
                    color: ${VERDE_BANDEIRA_ESCURO} !important;
                    border-color: ${VERDE_BANDEIRA_ESCURO} !important;
                }
                :global(tr:not(.vecontab-dash-concluido) .vecontab-comp-reabrir.p-button.p-button-outlined) {
                    color: #37474f !important;
                    border-color: #78909c !important;
                }
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-dash-concluido .vecontab-comp-reabrir.p-button-outlined) {
                    color: #0d260d !important;
                    border-color: #1b5e20 !important;
                    font-weight: 600;
                }
                :global(
                    .p-treetable
                        .p-treetable-tbody
                        > tr.vecontab-dash-concluido
                        .vecontab-comp-reabrir.p-button-outlined:not(:disabled):hover
                ) {
                    background: rgba(13, 38, 13, 0.08) !important;
                }
            `}</style>
        </div>
    );
}

export const getServerSideProps = canSSRAuth(async () => {
    return { props: {} };
});
