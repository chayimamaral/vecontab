import { useEffect, useMemo, useRef, useState } from 'react';
import { canSSRAuth } from '../components/utils/canSSRAuth';
import { TreeTable } from 'primereact/treetable';
import { Column } from 'primereact/column';
import { Button } from 'primereact/button';
import { InputText } from 'primereact/inputtext';
import { Tag } from 'primereact/tag';
import { Toast } from 'primereact/toast';
import { TreeNode } from 'primereact/treenode';
import EmpresaAgendaService from '../services/cruds/EmpresaAgendaService';

type DashboardNodeData = {
    nome: string;
    tipoNo: 'EMPRESA' | 'GRUPO' | 'COMPROMISSO';
    categoria: string;
    vencimento: string;
    vencimentoOrdem: string;
    status: string;
};

type DashboardTableFilters = {
    nome: { value: string; matchMode: string };
    categoria: { value: string; matchMode: string };
    vencimento: { value: string; matchMode: string };
    status: { value: string; matchMode: string };
};

// v2: não persistir filtros globais/coluna (escondiam empresas na TreeTable).
const TABLE_STATE_STORAGE_KEY = 'mare.dashboard.treetable.state.v2';

const INITIAL_FILTERS: DashboardTableFilters = {
    nome: { value: '', matchMode: 'contains' },
    categoria: { value: '', matchMode: 'contains' },
    vencimento: { value: '', matchMode: 'contains' },
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

/** FINANCEIRO: TRIBUTO no template ou campo classificacao da API. */
const isCompromissoFinanceiro = (item: Vec.EmpresaAgendaAcompanhamentoItem): boolean => {
    const c = (item.classificacao || '').toUpperCase();
    if (c === 'FINANCEIRO') {
        return true;
    }
    if (c === 'NAO_FINANCEIRO') {
        return false;
    }
    const t = (item.tipo || '').toUpperCase();
    return t === 'TRIBUTO' || t === 'FINANCEIRO';
};

const defaultExpandedKeys = (roots: TreeNode<DashboardNodeData>[]): Record<string, boolean> => {
    const keys: Record<string, boolean> = {};
    for (const emp of roots) {
        if (emp.key) {
            keys[emp.key] = true;
        }
        for (const grp of emp.children || []) {
            if (grp.key) {
                keys[grp.key] = true;
            }
        }
    }
    return keys;
};

const mapStatusSeverity = (status: string): 'success' | 'warning' | 'danger' | null => {
    const normalized = (status || '').toUpperCase();
    if (normalized === 'PAGO') {
        return 'success';
    }
    if (normalized === 'ATRASADO') {
        return 'danger';
    }
    if (normalized === 'PENDENTE') {
        return 'warning';
    }
    return null;
};

export default function Home() {
    const [nodes, setNodes] = useState<TreeNode<DashboardNodeData>[]>([]);
    const [expandedKeys, setExpandedKeys] = useState<Record<string, boolean>>({});
    const [loading, setLoading] = useState(false);
    const [first, setFirst] = useState(0);
    const [rows, setRows] = useState(10);
    const [sortField, setSortField] = useState('nome');
    const [sortOrder, setSortOrder] = useState<1 | -1>(1);
    const [globalFilterValue, setGlobalFilterValue] = useState('');
    const [globalFilterDraft, setGlobalFilterDraft] = useState('');
    const [filters, setFilters] = useState<DashboardTableFilters>(INITIAL_FILTERS);
    const toast = useRef<Toast>(null);
    const empresaAgendaService = useMemo(() => EmpresaAgendaService(), []);

    const buildTree = (itens: Vec.EmpresaAgendaAcompanhamentoItem[]): TreeNode<DashboardNodeData>[] => {
        const byEmpresa = new Map<string, { nome: string; itens: Vec.EmpresaAgendaAcompanhamentoItem[] }>();

        for (const item of itens || []) {
            const empresaID = item.empresa_id || '';
            if (!empresaID) {
                continue;
            }

            const current = byEmpresa.get(empresaID);
            if (current) {
                current.itens.push(item);
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

        return ordered.map(([empresaID, empresa]) => {
            const financeiros: TreeNode<DashboardNodeData>[] = [];
            const naoFinanceiros: TreeNode<DashboardNodeData>[] = [];
            const seenFin = new Set<string>();
            const seenNao = new Set<string>();

            for (const item of empresa.itens) {
                if (!item.compromisso_id) {
                    continue;
                }
                const cid = item.compromisso_id;
                const fin = isCompromissoFinanceiro(item);
                if (fin && seenFin.has(cid)) {
                    continue;
                }
                if (!fin && seenNao.has(cid)) {
                    continue;
                }
                if (fin) {
                    seenFin.add(cid);
                } else {
                    seenNao.add(cid);
                }

                const compromissoNode: TreeNode<DashboardNodeData> = {
                    key: `cmp-${empresaID}-${cid}`,
                    data: {
                        nome: item.descricao || 'Compromisso sem descrição',
                        tipoNo: 'COMPROMISSO',
                        categoria: fin ? 'Financeiro' : 'Não financeiro',
                        vencimento: formatDate(item.data_vencimento),
                        vencimentoOrdem: item.data_vencimento || '9999-12-31',
                        status: item.status || '',
                    },
                };

                if (fin) {
                    financeiros.push(compromissoNode);
                } else {
                    naoFinanceiros.push(compromissoNode);
                }
            }

            financeiros.sort((a, b) => (a.data?.vencimentoOrdem || '').localeCompare(b.data?.vencimentoOrdem || ''));
            naoFinanceiros.sort((a, b) => (a.data?.vencimentoOrdem || '').localeCompare(b.data?.vencimentoOrdem || ''));

            return {
                key: `emp-${empresaID}`,
                data: {
                    nome: empresa.nome,
                    tipoNo: 'EMPRESA',
                    categoria: '',
                    vencimento: '',
                    vencimentoOrdem: '',
                    status: '',
                },
                children: [
                    {
                        key: `grp-fin-${empresaID}`,
                        data: {
                            nome: 'Compromissos Financeiros',
                            tipoNo: 'GRUPO',
                            categoria: 'Financeiro',
                            vencimento: '',
                            vencimentoOrdem: '',
                            status: '',
                        },
                        children: financeiros,
                    },
                    {
                        key: `grp-nao-fin-${empresaID}`,
                        data: {
                            nome: 'Compromissos Não Financeiros',
                            tipoNo: 'GRUPO',
                            categoria: 'Não financeiro',
                            vencimento: '',
                            vencimentoOrdem: '',
                            status: '',
                        },
                        children: naoFinanceiros,
                    },
                ],
            };
        });
    };

    const loadAcompanhamento = () => {
        setLoading(true);
        empresaAgendaService
            .getAcompanhamento()
            .then(({ data }) => {
                const tree = buildTree(data.itens || []);
                setNodes(tree);
                setExpandedKeys(defaultExpandedKeys(tree));
                setFirst(0);
            })
            .catch((error: unknown) => {
                setNodes([]);
                toast.current?.show({
                    severity: 'error',
                    summary: 'Erro',
                    detail: error instanceof Error ? error.message : 'Erro ao carregar acompanhamento',
                    life: 3000,
                });
            })
            .finally(() => {
                setLoading(false);
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
            JSON.stringify({
                first,
                rows,
                sortField,
                sortOrder,
            }),
        );
    }, [first, rows, sortField, sortOrder]);

    useEffect(() => {
        loadAcompanhamento();
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

    const onSort = (event: { sortField?: string; sortOrder?: number }) => {
        if (event.sortField) {
            setSortField(event.sortField);
        }
        if (event.sortOrder === 1 || event.sortOrder === -1) {
            setSortOrder(event.sortOrder);
        }
    };

    const onFilter = (event: { filters: DashboardTableFilters }) => {
        setFirst(0);
        setFilters(event.filters);
    };

    const clearFilters = () => {
        setFirst(0);
        setGlobalFilterValue('');
        setGlobalFilterDraft('');
        setFilters(INITIAL_FILTERS);
    };

    const statusBodyTemplate = (node: TreeNode<DashboardNodeData>) => {
        if (!node?.data?.status) {
            return null;
        }

        return <Tag value={node.data.status} severity={mapStatusSeverity(node.data.status)} />;
    };

    const tableHeader = (
        <div className="flex align-items-center justify-content-between gap-3">
            <span className="text-900 font-semibold">
                Empresa → Compromissos financeiros / não financeiros → Vencimentos na agenda
            </span>
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
                <h2 className="m-0">Acompanhamento de Compromissos</h2>
                <Button icon="pi pi-refresh" label="Atualizar" onClick={loadAcompanhamento} loading={loading} />
            </div>

            <TreeTable
                value={nodes}
                loading={loading}
                expandedKeys={expandedKeys}
                onToggle={(e: { value: Record<string, boolean> }) => setExpandedKeys(e.value)}
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
                tableStyle={{ minWidth: '60rem' }}
                emptyMessage="Nenhuma empresa ou compromisso na agenda deste tenant"
            >
                <Column field="nome" header="Empresa / Grupo / Compromisso" expander sortable filter filterPlaceholder="Filtrar descrição" style={{ width: '44%' }} />
                <Column field="categoria" header="Categoria" sortable filter filterPlaceholder="Filtrar categoria" style={{ width: '22%' }} />
                <Column field="vencimento" header="Vencimento" sortable filter filterPlaceholder="Filtrar vencimento" style={{ width: '18%' }} />
                <Column field="status" header="Status" body={statusBodyTemplate} sortable filter filterPlaceholder="Filtrar status" style={{ width: '16%' }} />
            </TreeTable>

            <style jsx>{`
        .tree-global-filter {
          min-width: 20rem;
        }
      `}</style>
        </div>
    );
}

export const getServerSideProps = canSSRAuth(async () => {
    return {
        props: {},
    };
});