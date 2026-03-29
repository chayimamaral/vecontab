import { useEffect, useMemo, useRef, useState } from 'react';
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
import EmpresaCompromissoService from '../../services/cruds/EmpresaCompromissoService';
import type { Vec } from '../../types/types';

type NodeData = {
    nome: string;
    tipoNo: 'EMPRESA' | 'COMPROMISSO';
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

const TABLE_STATE_STORAGE_KEY = 'vecontab.compromissos-empresas.treetable.v1';

const INITIAL_FILTERS: TableFilters = {
    nome: { value: '', matchMode: 'contains' },
    categoria: { value: '', matchMode: 'contains' },
    vencimento: { value: '', matchMode: 'contains' },
    valor: { value: '', matchMode: 'contains' },
    status: { value: '', matchMode: 'contains' },
};

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
    for (const emp of roots) {
        if (emp.key) {
            keys[emp.key] = true;
        }
    }
    return keys;
};

const statusNorm = (s: string) => s.trim().toLowerCase();

export default function CompromissosEmpresasPage() {
    const [nodes, setNodes] = useState<TreeNode[]>([]);
    const [expandedKeys, setExpandedKeys] = useState<Record<string, boolean>>({});
    const [loading, setLoading] = useState(false);
    const [first, setFirst] = useState(0);
    const [rows, setRows] = useState(10);
    const [sortField, setSortField] = useState('nome');
    const [sortOrder, setSortOrder] = useState<1 | -1>(1);
    const [globalFilterValue, setGlobalFilterValue] = useState('');
    const [globalFilterDraft, setGlobalFilterDraft] = useState('');
    const [filters, setFilters] = useState<TableFilters>(INITIAL_FILTERS);
    const toast = useRef<Toast>(null);
    const svc = useMemo(() => EmpresaCompromissoService(), []);

    const [editDialog, setEditDialog] = useState(false);
    const [editId, setEditId] = useState('');
    const [editVenc, setEditVenc] = useState('');
    const [editValor, setEditValor] = useState<number | null>(null);

    const buildTree = (itens: Vec.EmpresaAgendaAcompanhamentoItem[]): TreeNode[] => {
        const byEmpresa = new Map<string, { nome: string; itens: Vec.EmpresaAgendaAcompanhamentoItem[] }>();

        for (const item of itens || []) {
            const empresaID = item.empresa_id || '';
            if (!empresaID) {
                continue;
            }
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

        const ordered = Array.from(byEmpresa.entries()).sort((a, b) =>
            (a[1].nome || '').localeCompare(b[1].nome || '', 'pt-BR', { sensitivity: 'base' }),
        );

        return ordered.map(([empresaID, emp]) => {
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
                const fin = (item.classificacao || '').toUpperCase() === 'FINANCEIRO';
                children.push({
                    key: `cmp-${aid}`,
                    data: {
                        nome: item.descricao || 'Compromisso sem descrição',
                        tipoNo: 'COMPROMISSO',
                        categoria: fin ? 'Financeiro' : 'Não financeiro',
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
                key: `emp-${empresaID}`,
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
                setSortField(parsed.sortField);
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

    const onPage = (event: { first: number; rows: number }) => {
        setFirst(event.first);
        setRows(event.rows);
    };

    const onSort: TreeTableProps['onSort'] = (event) => {
        if (event.sortField) {
            setSortField(event.sortField);
        }
        if (event.sortOrder === 1 || event.sortOrder === -1) {
            setSortOrder(event.sortOrder);
        }
    };

    const onFilter: TreeTableProps['onFilter'] = (next) => {
        setFirst(0);
        if (next) {
            setFilters(next as TableFilters);
        }
    };

    const clearFilters = () => {
        setFirst(0);
        setGlobalFilterValue('');
        setGlobalFilterDraft('');
        setFilters(INITIAL_FILTERS);
    };

    const statusBodyTemplate = (node: TreeNode) => {
        const d = node?.data as NodeData | undefined;
        const st = statusNorm(d?.status || '');
        if (!st) {
            return null;
        }
        if (st === 'concluido') {
            return <Tag value="Concluído" style={{ background: '#e0e0e0', color: '#424242' }} />;
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
        return <span>{t || '—'}</span>;
    };

    const valorBodyTemplate = (node: TreeNode) => {
        const d = node?.data as NodeData | undefined;
        if (d?.tipoNo !== 'COMPROMISSO') {
            return null;
        }
        return <span>{d?.valorText ?? '—'}</span>;
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
            <div className="flex gap-1 flex-wrap">
                <Button
                    type="button"
                    icon="pi pi-pencil"
                    rounded
                    text
                    severity="secondary"
                    onClick={() => openEdit(node)}
                    tooltip="Editar valor e vencimento"
                    tooltipOptions={{ position: 'left' }}
                />
                <Button
                    type="button"
                    label={st === 'concluido' ? 'Reabrir' : 'Concluído'}
                    rounded
                    text
                    severity={st === 'concluido' ? 'secondary' : 'success'}
                    onClick={() => toggleConcluido(node)}
                    className="text-sm"
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

    const tableHeader = (
        <div className="flex align-items-center justify-content-between gap-3">
            <span className="text-900 font-semibold">Empresa → Compromissos legais gerados</span>
            <div className="flex align-items-center gap-2 tree-global-filter">
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

            <div className="flex align-items-center justify-content-between mb-3">
                <h2 className="m-0">Compromissos das Empresas</h2>
                <Button icon="pi pi-refresh" label="Atualizar" onClick={load} loading={loading} />
            </div>

            <TreeTable
                value={nodes}
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
                onFilter={onFilter}
                globalFilter={globalFilterValue}
                filterMode="lenient"
                header={tableHeader}
                tableStyle={{ minWidth: '55rem' }}
                emptyMessage="Nenhum compromisso gerado para empresas deste tenant"
            >
                <Column field="nome" header="Empresa / Compromisso" expander sortable filter filterPlaceholder="Filtrar" style={{ width: '34%' }} />
                <Column field="categoria" header="Natureza" sortable filter filterPlaceholder="Filtrar" style={{ width: '14%' }} />
                <Column
                    field="vencimento"
                    header="Vencimento"
                    sortable
                    filter
                    filterPlaceholder="Filtrar"
                    body={vencimentoBodyTemplate}
                    style={{ width: '12%' }}
                />
                <Column field="valorText" header="Valor" sortable filter filterPlaceholder="Filtrar" body={valorBodyTemplate} style={{ width: '12%' }} />
                <Column field="status" header="Status" body={statusBodyTemplate} sortable filter filterPlaceholder="Filtrar" style={{ width: '14%' }} />
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

            <style jsx>{`
                .tree-global-filter {
                    min-width: 20rem;
                }
                :global(.vecontab-dash-concluido) {
                    background-color: #f0f0f0 !important;
                }
            `}</style>
        </div>
    );
}

export const getServerSideProps = canSSRAuth(async () => {
    return { props: {} };
});
