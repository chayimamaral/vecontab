import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { TreeTable, type TreeTableProps } from 'primereact/treetable';
import { Column } from 'primereact/column';
import { Button } from 'primereact/button';
import { Toast } from 'primereact/toast';
import { TreeNode } from 'primereact/treenode';
import { Tag } from 'primereact/tag';
import { Toolbar } from 'primereact/toolbar';
import { Dropdown } from 'primereact/dropdown';
import { canSSRAuth } from '../../components/utils/canSSRAuth';
import setupAPIClient from '../../components/api/api';
import AgendaService from '../../services/cruds/AgendaService';

type AgendaEventDTO = {
    id: string;
    title: string;
    rotina_id?: string;
    passo_id?: string;
    agenda_id?: string;
    start: string;
    end: string;
    backgroundColor: string;
    textColor: string;
    borderColor: string;
};

/** Situação da linha conforme cores da API da agenda. */
type FiltroCorAgenda = 'TODOS' | 'ATRASADO' | 'VENCENDO' | 'FUTURO' | 'CONCLUIDO';

const OPCOES_FILTRO_COR: Array<{ label: string; value: FiltroCorAgenda }> = [
    { label: 'Todos', value: 'TODOS' },
    { label: 'Atrasado', value: 'ATRASADO' },
    { label: 'No período / vencendo', value: 'VENCENDO' },
    { label: 'Futuro', value: 'FUTURO' },
    { label: 'Concluído', value: 'CONCLUIDO' },
];

const HEX_PARA_FILTRO: Record<string, FiltroCorAgenda> = {
    '#22C55E': 'CONCLUIDO',
    '#FDE2E0': 'ATRASADO',
    '#FFDAB9': 'VENCENDO',
    '#A0D6B4': 'FUTURO',
};

function corParaFiltro(backgroundColor: string): FiltroCorAgenda | null {
    const k = (backgroundColor || '').trim().toUpperCase();
    return HEX_PARA_FILTRO[k] ?? null;
}

function filtrarNosPorCor(nodes: TreeNode[], filtro: FiltroCorAgenda): TreeNode[] {
    if (filtro === 'TODOS') {
        return nodes;
    }
    const out: TreeNode[] = [];
    for (const n of nodes) {
        const d = n.data as NoData;
        const filhosSrc = n.children ?? [];
        const filhosFiltrados = filtrarNosPorCor(filhosSrc, filtro);
        const bucket = corParaFiltro(d.backgroundColor);
        const corMatch = bucket === filtro;
        if (!corMatch && filhosFiltrados.length === 0) {
            continue;
        }
        const leaf = filhosFiltrados.length > 0 ? false : d.childrenLoaded;
        out.push({
            ...n,
            children: filhosFiltrados,
            leaf,
        });
    }
    return out;
}

function coletarChavesExpandidas(ns: TreeNode[]): Record<string, boolean> {
    const keys: Record<string, boolean> = {};
    const walk = (lista: TreeNode[]) => {
        for (const n of lista) {
            if (n.key != null && n.children && n.children.length > 0) {
                keys[String(n.key)] = true;
                walk(n.children);
            }
        }
    };
    walk(ns);
    return keys;
}

type NoData = {
    tipo: 'rotina' | 'passo';
    titulo: string;
    inicio: string;
    fim: string;
    backgroundColor: string;
    textColor: string;
    borderColor: string;
    childrenLoaded: boolean;
    /** agenda (rotina nível) */
    agendaId: string;
    /** item de passo, quando tipo === 'passo' */
    itemId?: string;
};

const formatDate = (value?: string): string => {
    if (!value) {
        return '—';
    }
    const raw = value.slice(0, 10);
    const [year, month, day] = raw.split('-');
    if (!year || !month || !day) {
        return value;
    }
    return `${day}/${month}/${year}`;
};

function normalizeListEvents(payload: unknown): AgendaEventDTO[] {
    if (Array.isArray(payload)) {
        return payload as AgendaEventDTO[];
    }
    if (payload && typeof payload === 'object' && Array.isArray((payload as { events?: unknown }).events)) {
        return (payload as { events: AgendaEventDTO[] }).events;
    }
    return [];
}

function normalizeDetailEvents(payload: unknown): AgendaEventDTO[] {
    return normalizeListEvents(payload);
}

/** Passos usam fundo neutro + indicador; rotina concluída ainda usa faixa verde clara. */
function corTextoParaCelula(d: NoData): string | undefined {
    if (d.tipo === 'passo') {
        return '#0f172a';
    }
    if (d.backgroundColor === '#22C55E') {
        return '#0f172a';
    }
    return d.textColor || undefined;
}

function classeIndicadorPasso(backgroundColor: string): string {
    const k = (backgroundColor || '').trim().toUpperCase();
    switch (k) {
        case '#22C55E':
            return 'vecontab-ind-passo-concluido';
        case '#FDE2E0':
            return 'vecontab-ind-passo-atrasado';
        case '#FFDAB9':
            return 'vecontab-ind-passo-vencendo';
        case '#A0D6B4':
            return 'vecontab-ind-passo-futuro';
        default:
            return 'vecontab-ind-passo-neutro';
    }
}

function rowClassForCor(backgroundColor: string): string {
    switch (backgroundColor) {
        case '#22C55E':
            return 'vecontab-agenda-arvore-row vecontab-agenda-arvore-concluido';
        case '#FDE2E0':
            return 'vecontab-agenda-arvore-row vecontab-agenda-arvore-atrasado';
        case '#FFDAB9':
            return 'vecontab-agenda-arvore-row vecontab-agenda-arvore-vencendo';
        case '#A0D6B4':
            return 'vecontab-agenda-arvore-row vecontab-agenda-arvore-futuro';
        default:
            return 'vecontab-agenda-arvore-row';
    }
}

function mapListToRoots(eventos: AgendaEventDTO[]): TreeNode[] {
    return eventos.map((ev) => ({
        key: ev.id,
        leaf: false,
        data: {
            tipo: 'rotina',
            titulo: ev.title,
            inicio: ev.start,
            fim: ev.end,
            backgroundColor: ev.backgroundColor,
            textColor: ev.textColor,
            borderColor: ev.borderColor,
            childrenLoaded: false,
            agendaId: ev.id,
        } satisfies NoData,
        children: [],
    }));
}

function mapDetailToChildren(agendaId: string, eventos: AgendaEventDTO[]): TreeNode[] {
    return eventos.map((ev) => ({
        key: `${agendaId}:${ev.id}`,
        leaf: true,
        data: {
            tipo: 'passo',
            titulo: ev.title,
            inicio: ev.start,
            fim: ev.end,
            backgroundColor: ev.backgroundColor,
            textColor: ev.textColor,
            borderColor: ev.borderColor,
            childrenLoaded: true,
            agendaId,
            itemId: ev.id,
        } satisfies NoData,
    }));
}

function setChildrenOnNode(tree: TreeNode[], agendaKey: string, children: TreeNode[]): TreeNode[] {
    return tree.map((n) => {
        if (n.key === agendaKey) {
            return {
                ...n,
                children,
                leaf: false,
                data: {
                    ...(n.data as NoData),
                    childrenLoaded: true,
                },
            };
        }
        if (n.children && n.children.length > 0) {
            return { ...n, children: setChildrenOnNode(n.children, agendaKey, children) };
        }
        return n;
    });
}

function mergeRootFromList(tree: TreeNode[], ev: AgendaEventDTO): TreeNode[] {
    return tree.map((n) => {
        if (n.key !== ev.id) {
            return n;
        }
        const prev = n.data as NoData;
        return {
            ...n,
            data: {
                ...prev,
                titulo: ev.title,
                inicio: ev.start,
                fim: ev.end,
                backgroundColor: ev.backgroundColor,
                textColor: ev.textColor,
                borderColor: ev.borderColor,
                agendaId: ev.id,
            },
        };
    });
}

type PaginaProps = {
    dados: string;
};

export default function AgendaArvorePage({ dados }: PaginaProps) {
    const tenantid = dados;
    const [nodes, setNodes] = useState<TreeNode[]>([]);
    const [filtroCor, setFiltroCor] = useState<FiltroCorAgenda>('TODOS');
    const [expandedKeys, setExpandedKeys] = useState<Record<string, boolean>>({});
    const [loading, setLoading] = useState(false);
    const [loadingExpand, setLoadingExpand] = useState<string | null>(null);
    const toast = useRef<Toast>(null);
    const nodesRef = useRef<TreeNode[]>([]);
    const agendaSvc = useMemo(() => AgendaService(), []);

    nodesRef.current = nodes;

    const nosVisiveis = useMemo(() => filtrarNosPorCor(nodes, filtroCor), [nodes, filtroCor]);

    const filtroAnteriorRef = useRef<FiltroCorAgenda>(filtroCor);
    useEffect(() => {
        if (filtroCor === 'TODOS') {
            if (filtroAnteriorRef.current !== 'TODOS') {
                setExpandedKeys({});
            }
            filtroAnteriorRef.current = filtroCor;
            return;
        }
        filtroAnteriorRef.current = filtroCor;
        setExpandedKeys(coletarChavesExpandidas(nosVisiveis));
    }, [filtroCor, nosVisiveis]);

    useEffect(() => {
        if (filtroCor === 'TODOS') {
            return;
        }
        let cancelled = false;
        void (async () => {
            const snap = nodesRef.current;
            const unloaded = snap.filter((n) => {
                const d = n.data as NoData;
                return d?.tipo === 'rotina' && !d.childrenLoaded;
            });
            if (unloaded.length === 0) {
                return;
            }
            setLoading(true);
            try {
                const pairs = await Promise.all(
                    unloaded.map(async (n) => {
                        const id = String(n.key);
                        const raw = await agendaSvc.getDetalhes({ agenda_id: id });
                        return { id, children: mapDetailToChildren(id, normalizeDetailEvents(raw)) };
                    }),
                );
                if (cancelled) {
                    return;
                }
                setNodes((prev) => {
                    let next = prev;
                    for (const p of pairs) {
                        next = setChildrenOnNode(next, p.id, p.children);
                    }
                    return next;
                });
            } catch (e: unknown) {
                const msg = e instanceof Error ? e.message : 'Erro ao carregar passos para o filtro';
                toast.current?.show({ severity: 'error', summary: 'Erro', detail: msg, life: 4000 });
            } finally {
                if (!cancelled) {
                    setLoading(false);
                }
            }
        })();
        return () => {
            cancelled = true;
        };
    }, [filtroCor, agendaSvc]);

    const carregarRaizes = useCallback(async () => {
        setLoading(true);
        try {
            const raw = await agendaSvc.getAgendaList({ tenant_id: tenantid });
            const eventos = normalizeListEvents(raw);
            setNodes(mapListToRoots(eventos));
        } catch (e: unknown) {
            const msg = e instanceof Error ? e.message : 'Erro ao carregar agenda';
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: msg, life: 4000 });
            setNodes([]);
        } finally {
            setLoading(false);
        }
    }, [agendaSvc, tenantid]);

    useEffect(() => {
        void carregarRaizes();
    }, [carregarRaizes]);

    const carregarPassos = useCallback(
        async (agendaId: string) => {
            setLoadingExpand(agendaId);
            try {
                const raw = await agendaSvc.getDetalhes({ agenda_id: agendaId });
                const eventos = normalizeDetailEvents(raw);
                const children = mapDetailToChildren(agendaId, eventos);
                setNodes((prev) => setChildrenOnNode(prev, agendaId, children));
            } catch (e: unknown) {
                const msg = e instanceof Error ? e.message : 'Erro ao carregar passos';
                toast.current?.show({ severity: 'error', summary: 'Erro', detail: msg, life: 4000 });
            } finally {
                setLoadingExpand(null);
            }
        },
        [agendaSvc],
    );

    const onExpand: TreeTableProps['onExpand'] = useCallback(
        async (e) => {
            const node = e.node as TreeNode;
            const data = node.data as NoData | undefined;
            if (!data || data.tipo !== 'rotina') {
                return;
            }
            const agendaId = String(node.key);
            if (data.childrenLoaded) {
                return;
            }
            await carregarPassos(agendaId);
        },
        [carregarPassos],
    );

    const atualizarRamificacao = useCallback(
        async (agendaId: string) => {
            try {
                const listaRaw = await agendaSvc.getAgendaList({ tenant_id: tenantid });
                const lista = normalizeListEvents(listaRaw);
                const ev = lista.find((x) => x.id === agendaId);
                if (ev) {
                    setNodes((prev) => mergeRootFromList(prev, ev));
                }
                const raw = await agendaSvc.getDetalhes({ agenda_id: agendaId });
                const eventos = normalizeDetailEvents(raw);
                const children = mapDetailToChildren(agendaId, eventos);
                setNodes((prev) => setChildrenOnNode(prev, agendaId, children));
            } catch {
                /* toast já em carregarRaizes se necessário */
            }
        },
        [agendaSvc, tenantid],
    );

    const concluirPasso = useCallback(
        async (agendaId: string, itemId: string) => {
            try {
                const response = await agendaSvc.concluirPasso({
                    agenda_id: String(agendaId),
                    agenda_item_id: String(itemId),
                });

                toast.current?.show({
                    severity: 'success',
                    summary: 'Sucesso',
                    detail: 'Passo concluído manualmente.',
                    life: 3000,
                });

                if (response?.data?.todos_passos_concluidos) {
                    toast.current?.show({
                        severity: 'info',
                        summary: 'Rotina',
                        detail: 'Todos os passos foram concluídos.',
                        life: 4000,
                    });
                }

                await atualizarRamificacao(agendaId);
            } catch (error: unknown) {
                const detail = error instanceof Error ? error.message : 'Erro ao concluir passo.';
                toast.current?.show({ severity: 'error', summary: 'Erro', detail, life: 4000 });
            }
        },
        [agendaSvc, atualizarRamificacao],
    );

    const reabrirPasso = useCallback(
        async (agendaId: string, itemId: string) => {
            try {
                await agendaSvc.reabrirPasso({
                    agenda_id: String(agendaId),
                    agenda_item_id: String(itemId),
                });

                toast.current?.show({
                    severity: 'success',
                    summary: 'Sucesso',
                    detail: 'Passo reaberto para pendente.',
                    life: 3000,
                });

                await atualizarRamificacao(agendaId);
            } catch (error: unknown) {
                const detail = error instanceof Error ? error.message : 'Erro ao reabrir passo.';
                toast.current?.show({ severity: 'error', summary: 'Erro', detail, life: 4000 });
            }
        },
        [agendaSvc, atualizarRamificacao],
    );

    const nomeTemplate = (row: TreeNode) => {
        const d = row.data as NoData;
        return (
            <div className="flex align-items-center gap-2 flex-wrap">
                <span className="font-medium" style={{ color: corTextoParaCelula(d) }}>
                    {d.titulo}
                </span>
                <Tag
                    value={d.tipo === 'rotina' ? 'Rotina' : 'Passo'}
                    severity={d.tipo === 'rotina' ? 'info' : 'secondary'}
                    className="text-xs"
                />
            </div>
        );
    };

    const periodoTemplate = (row: TreeNode) => {
        const d = row.data as NoData;
        return (
            <span style={{ color: corTextoParaCelula(d) }}>
                {formatDate(d.inicio)} — {formatDate(d.fim)}
            </span>
        );
    };

    const acoesTemplate = (row: TreeNode) => {
        const d = row.data as NoData;
        if (d.tipo !== 'passo' || !d.itemId) {
            return null;
        }
        const concluido = (d.backgroundColor || '').trim().toUpperCase() === '#22C55E';
        const busy = loadingExpand === d.agendaId;
        if (concluido) {
            return (
                <Button
                    type="button"
                    icon="pi pi-replay"
                    label="Reabrir Passo"
                    outlined
                    size="small"
                    className="vecontab-agenda-acao-passo"
                    disabled={busy}
                    onClick={() => void reabrirPasso(d.agendaId, d.itemId!)}
                />
            );
        }
        return (
            <Button
                type="button"
                icon="pi pi-check-circle"
                label="Concluir Passo"
                outlined
                size="small"
                className="vecontab-agenda-acao-passo"
                disabled={busy}
                onClick={() => void concluirPasso(d.agendaId, d.itemId!)}
            />
        );
    };

    const rowClassName = (row: TreeNode) => {
        const d = row.data as NoData;
        if (d?.tipo === 'passo') {
            return `vecontab-agenda-arvore-row vecontab-agenda-arvore-passo ${classeIndicadorPasso(d?.backgroundColor || '')}`;
        }
        return rowClassForCor(d?.backgroundColor || '');
    };

    const onToggleArvore: TreeTableProps['onToggle'] = (e) => setExpandedKeys(e.value);

    const toolbarStart = (
        <div className="flex align-items-center gap-2 flex-wrap">
            <span className="p-float-label" style={{ minWidth: '16rem' }}>
                <Dropdown
                    inputId="agenda-arvore-filtro-cor"
                    value={filtroCor}
                    options={OPCOES_FILTRO_COR}
                    onChange={(e) => setFiltroCor(e.value as FiltroCorAgenda)}
                    optionLabel="label"
                    optionValue="value"
                    className="w-full"
                />
                <label htmlFor="agenda-arvore-filtro-cor">Situação</label>
            </span>
            <Button
                type="button"
                icon="pi pi-refresh"
                label="Atualizar"
                onClick={() => void carregarRaizes()}
                loading={loading}
                outlined
            />
        </div>
    );

    const toolbarEnd = (
        <div className="flex align-items-center gap-3 flex-wrap text-sm text-600">
            <span className="flex align-items-center gap-2">
                <span className="inline-block border-circle w-1rem h-1rem vecontab-leg-atrasado" />
                Atrasado
            </span>
            <span className="flex align-items-center gap-2">
                <span className="inline-block border-circle w-1rem h-1rem vecontab-leg-vencendo" />
                No período / vencendo
            </span>
            <span className="flex align-items-center gap-2">
                <span className="inline-block border-circle w-1rem h-1rem vecontab-leg-futuro" />
                Futuro
            </span>
            <span className="flex align-items-center gap-2">
                <span className="inline-block border-circle w-1rem h-1rem vecontab-leg-concluido" />
                Concluído
            </span>
        </div>
    );

    return (
        <div className="grid">
            <div className="col-12">
                <div className="card">
                    <Toast ref={toast} />
                    <h1 className="text-2xl font-bold text-900 m-0 mb-3">Agenda em Árvore</h1>
                    <p className="text-600 mt-0 mb-4 line-height-3">
                        Primeiro nível: empresa e rotina com intervalo de datas. Expanda para ver os passos, o intervalo
                        de cada um e concluir manualmente — mesma regra de cores da agenda (atrasado, período atual,
                        futuro, concluído).
                    </p>
                    <Toolbar className="mb-3" start={toolbarStart} end={toolbarEnd} />
                    <TreeTable
                        value={nosVisiveis}
                        loading={loading}
                        expandedKeys={expandedKeys}
                        onToggle={onToggleArvore}
                        onExpand={onExpand}
                        tableStyle={{ minWidth: '50rem' }}
                        rowClassName={rowClassName}
                        stripedRows
                    >
                        <Column
                            header="Empresa / rotina ou passo"
                            body={nomeTemplate}
                            expander
                            style={{ minWidth: '280px' }}
                        />
                        <Column header="Período (início — fim)" body={periodoTemplate} style={{ minWidth: '220px' }} />
                        <Column header="Ações" body={acoesTemplate} style={{ width: '180px' }} />
                    </TreeTable>
                </div>
            </div>
            <style jsx global>{`
                /* Passos: fundo neutro, recuo; situação no círculo à esquerda (primeira coluna). */
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-agenda-arvore-passo > td:first-child) {
                    position: relative;
                    padding-left: 3.15rem !important;
                    background: var(--surface-0, #ffffff) !important;
                    border-left: none !important;
                }
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-agenda-arvore-passo > td:not(:first-child)) {
                    padding-left: 2.5rem !important;
                    background: var(--surface-0, #ffffff) !important;
                    border-left: none !important;
                }
                :global(
                        .p-treetable.p-treetable-striped .p-treetable-tbody > tr.vecontab-agenda-arvore-passo:nth-child(even) > td
                    ) {
                    background: var(--surface-50, #fafafa) !important;
                }
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-ind-passo-atrasado > td:first-child::after),
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-ind-passo-vencendo > td:first-child::after),
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-ind-passo-futuro > td:first-child::after),
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-ind-passo-concluido > td:first-child::after),
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-ind-passo-neutro > td:first-child::after) {
                    content: '';
                    position: absolute;
                    top: 0.35rem;
                    left: 0.45rem;
                    width: 0.7rem;
                    height: 0.7rem;
                    border-radius: 50%;
                    box-sizing: border-box;
                    pointer-events: none;
                    z-index: 1;
                }
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-ind-passo-atrasado > td:first-child::after) {
                    background: #fde2e0;
                    border: 1px solid #f8c9c4;
                }
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-ind-passo-vencendo > td:first-child::after) {
                    background: #ffdab9;
                    border: 1px solid #e8c09a;
                }
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-ind-passo-futuro > td:first-child::after) {
                    background: #a0d6b4;
                    border: 1px solid #7fb89a;
                }
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-ind-passo-concluido > td:first-child::after) {
                    background: #22c55e;
                    border: 1px solid #16a34a;
                }
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-ind-passo-neutro > td:first-child::after) {
                    background: #e2e8f0;
                    border: 1px solid #cbd5e1;
                }
                .vecontab-agenda-arvore-row > td {
                    border-color: rgba(0, 0, 0, 0.06);
                }
                .vecontab-agenda-arvore-atrasado > td {
                    background: #fde2e0 !important;
                }
                .vecontab-agenda-arvore-vencendo > td {
                    background: #ffdab9 !important;
                }
                .vecontab-agenda-arvore-futuro > td {
                    background: #a0d6b4 !important;
                }
                .vecontab-agenda-arvore-concluido > td {
                    background: #dcfce7 !important;
                    border-left: 3px solid #16a34a;
                }
                .vecontab-leg-atrasado {
                    background: #fde2e0;
                    border: 1px solid #f8c9c4;
                }
                .vecontab-leg-vencendo {
                    background: #ffdab9;
                    border: 1px solid #e8c09a;
                }
                .vecontab-leg-futuro {
                    background: #a0d6b4;
                    border: 1px solid #7fb89a;
                }
                .vecontab-leg-concluido {
                    background: #22c55e;
                    border: 1px solid #16a34a;
                }
                :global(.vecontab-agenda-acao-passo.p-button-outlined) {
                    color: #0f172a !important;
                    border-color: #0f172a !important;
                    background: transparent !important;
                }
                :global(.vecontab-agenda-acao-passo.p-button-outlined .p-button-icon) {
                    color: #0f172a !important;
                }
                :global(.vecontab-agenda-acao-passo.p-button-outlined:not(:disabled):hover) {
                    background: rgba(15, 23, 42, 0.08) !important;
                    color: #0f172a !important;
                    border-color: #0f172a !important;
                }
                :global(.vecontab-agenda-acao-passo.p-button-outlined:not(:disabled):hover .p-button-icon) {
                    color: #0f172a !important;
                }
                :global(.vecontab-agenda-acao-passo.p-button-outlined:disabled) {
                    color: #64748b !important;
                    border-color: #94a3b8 !important;
                    opacity: 1;
                }
                :global(.vecontab-agenda-acao-passo.p-button-outlined:disabled .p-button-icon) {
                    color: #64748b !important;
                }
            `}</style>
        </div>
    );
}

export const getServerSideProps = canSSRAuth(async (ctx) => {
    try {
        const apiClient = setupAPIClient(ctx);
        const response = await apiClient.get('/api/usuariotenant');

        return {
            props: {
                dados: response.data.tenantid,
            },
        };
    } catch (err) {
        console.log(err);
        return {
            redirect: {
                destination: '/',
                permanent: false,
            },
        };
    }
});
