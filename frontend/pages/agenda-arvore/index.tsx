import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { TreeTable, type TreeTableProps } from 'primereact/treetable';
import { Column } from 'primereact/column';
import { Button } from 'primereact/button';
import { Toast } from 'primereact/toast';
import { TreeNode } from 'primereact/treenode';
import { Tag } from 'primereact/tag';
import { Dropdown } from 'primereact/dropdown';
import { InputText } from 'primereact/inputtext';
import { Dialog } from 'primereact/dialog';
import { Calendar } from 'primereact/calendar';
import { ConfirmDialog, confirmDialog } from 'primereact/confirmdialog';
import { canSSRAuth } from '../../components/utils/canSSRAuth';
import setupAPIClient from '../../components/api/api';
import AgendaService from '../../services/cruds/AgendaService';

type TreeTableExpandEventArg = Parameters<NonNullable<TreeTableProps['onExpand']>>[0];

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

/** Título da API: "Empresa => Processo" */
function parseTituloListaAgenda(title: string): { empresaNome: string; rotinaNome: string } {
  const idx = title.indexOf('=>');
  if (idx === -1) {
    return { empresaNome: title.trim(), rotinaNome: '' };
  }
  return {
    empresaNome: title.slice(0, idx).trim(),
    rotinaNome: title.slice(idx + 2).trim(),
  };
}

function normalizarTextoBusca(s: string): string {
  return s
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');
}

function filtrarNosPorEmpresaRotina(
  nosRaiz: TreeNode[],
  textoEmpresa: string,
  rotinaSelecionada: string | null,
): TreeNode[] {
  const t = normalizarTextoBusca(textoEmpresa);
  const rotSel = rotinaSelecionada?.trim() || null;
  if (!t && !rotSel) {
    return nosRaiz;
  }
  return nosRaiz.filter((n) => {
    const d = n.data as NoData | undefined;
    if (!d || d.tipo !== 'rotina') {
      return true;
    }
    if (rotSel && (d.rotinaNome || '').trim() !== rotSel) {
      return false;
    }
    if (t) {
      const emp = normalizarTextoBusca(d.empresaNome || '');
      if (!emp.includes(t)) {
        return false;
      }
    }
    return true;
  });
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
  /** Só nível processo (e replicado nos passos para contexto); vêm do título "Empresa => Processo". */
  empresaNome?: string;
  rotinaNome?: string;
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

function toISODateLocal(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function parseDataNoLocal(iso: string): Date {
  const raw = (iso || '').slice(0, 10);
  const parts = raw.split('-').map((x) => parseInt(x, 10));
  const y = parts[0];
  const mo = parts[1];
  const da = parts[2];
  if (!y || !mo || !da) {
    return new Date();
  }
  return new Date(y, mo - 1, da, 12, 0, 0, 0);
}

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

/** Classes do círculo na coluna de situação (apenas passos). */
function classeIndicadorCorCelula(backgroundColor: string): string {
  const k = (backgroundColor || '').trim().toUpperCase();
  switch (k) {
    case '#22C55E':
      return 'vecontab-ag-ind-concluido';
    case '#FDE2E0':
      return 'vecontab-ag-ind-atrasado';
    case '#FFDAB9':
      return 'vecontab-ag-ind-vencendo';
    case '#A0D6B4':
      return 'vecontab-ag-ind-futuro';
    default:
      return 'vecontab-ag-ind-neutro';
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
  return eventos.map((ev) => {
    const { empresaNome, rotinaNome } = parseTituloListaAgenda(ev.title);
    return {
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
        empresaNome,
        rotinaNome,
      } satisfies NoData,
      children: [],
    };
  });
}

function mapDetailToChildren(
  agendaId: string,
  eventos: AgendaEventDTO[],
  empresaNome: string,
  rotinaNome: string,
): TreeNode[] {
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
      empresaNome,
      rotinaNome,
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
    const { empresaNome, rotinaNome } = parseTituloListaAgenda(ev.title);
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
        empresaNome,
        rotinaNome,
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
  const [rotinaFiltro, setRotinaFiltro] = useState<string | null>(null);
  const [textoEmpresaFiltro, setTextoEmpresaFiltro] = useState('');
  const [expandedKeys, setExpandedKeys] = useState<Record<string, boolean>>({});
  const [loading, setLoading] = useState(false);
  const [loadingExpand, setLoadingExpand] = useState<string | null>(null);
  const [dialogNovoAgendaId, setDialogNovoAgendaId] = useState<string | null>(null);
  const [novoDescricao, setNovoDescricao] = useState('');
  const [novoInicio, setNovoInicio] = useState<Date | null>(null);
  const [novoTermino, setNovoTermino] = useState<Date | null>(null);
  const [dialogEdit, setDialogEdit] = useState<{
    agendaId: string;
    itemId: string;
    descricao: string;
    inicio: Date | null;
    termino: Date | null;
  } | null>(null);
  const toast = useRef<Toast>(null);
  const nodesRef = useRef<TreeNode[]>([]);
  const agendaSvc = useMemo(() => AgendaService(), []);

  nodesRef.current = nodes;

  const nosAposCor = useMemo(() => filtrarNosPorCor(nodes, filtroCor), [nodes, filtroCor]);
  const nosExibicao = useMemo(
    () => filtrarNosPorEmpresaRotina(nosAposCor, textoEmpresaFiltro, rotinaFiltro),
    [nosAposCor, textoEmpresaFiltro, rotinaFiltro],
  );

  const opcoesRotinaDropdown = useMemo(() => {
    const set = new Set<string>();
    for (const n of nodes) {
      const d = n.data as NoData | undefined;
      if (d?.tipo === 'rotina' && d.rotinaNome) {
        set.add(d.rotinaNome.trim());
      }
    }
    const ordenadas = Array.from(set).sort((a, b) =>
      a.localeCompare(b, 'pt-BR', { sensitivity: 'base' }),
    );
    return [
      { label: 'Todos os processos', value: null as string | null },
      ...ordenadas.map((r) => ({ label: r, value: r as string | null })),
    ];
  }, [nodes]);

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
    setExpandedKeys(coletarChavesExpandidas(nosExibicao));
  }, [filtroCor, nosExibicao]);

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
            const d = n.data as NoData;
            const raw = await agendaSvc.getDetalhes({ agenda_id: id });
            return {
              id,
              children: mapDetailToChildren(
                id,
                normalizeDetailEvents(raw),
                d.empresaNome ?? '',
                d.rotinaNome ?? '',
              ),
            };
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
    async (agendaId: string, empresaNome: string, rotinaNome: string) => {
      setLoadingExpand(agendaId);
      try {
        const raw = await agendaSvc.getDetalhes({ agenda_id: agendaId });
        const eventos = normalizeDetailEvents(raw);
        const children = mapDetailToChildren(agendaId, eventos, empresaNome, rotinaNome);
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
    async (e: TreeTableExpandEventArg) => {
      const node = e.node as TreeNode;
      const data = node.data as NoData | undefined;
      if (!data || data.tipo !== 'rotina') {
        return;
      }
      const agendaId = String(node.key);
      if (data.childrenLoaded) {
        return;
      }
      await carregarPassos(agendaId, data.empresaNome ?? '', data.rotinaNome ?? '');
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
        const { empresaNome, rotinaNome } = ev
          ? parseTituloListaAgenda(ev.title)
          : { empresaNome: '', rotinaNome: '' };
        const raw = await agendaSvc.getDetalhes({ agenda_id: agendaId });
        const eventos = normalizeDetailEvents(raw);
        const children = mapDetailToChildren(agendaId, eventos, empresaNome, rotinaNome);
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
            summary: 'Processo',
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

  const abrirNovoItem = useCallback((agendaId: string) => {
    setDialogNovoAgendaId(agendaId);
    setNovoDescricao('');
    setNovoInicio(new Date());
    setNovoTermino(new Date());
  }, []);

  const salvarNovoItemArvore = useCallback(async () => {
    if (!dialogNovoAgendaId) {
      return;
    }
    const di = novoInicio ? toISODateLocal(novoInicio) : '';
    const df = novoTermino ? toISODateLocal(novoTermino) : di;
    if (!novoDescricao.trim() || !di) {
      toast.current?.show({
        severity: 'warn',
        summary: 'Atenção',
        detail: 'Descrição e início são obrigatórios.',
        life: 3500,
      });
      return;
    }
    try {
      await agendaSvc.createAgendaItem({
        agenda_id: dialogNovoAgendaId,
        descricao: novoDescricao.trim(),
        inicio: di,
        termino: df,
      });
      toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Item incluído.', life: 3000 });
      setDialogNovoAgendaId(null);
      await atualizarRamificacao(dialogNovoAgendaId);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Erro ao incluir item.';
      toast.current?.show({ severity: 'error', summary: 'Erro', detail: msg, life: 4000 });
    }
  }, [agendaSvc, atualizarRamificacao, dialogNovoAgendaId, novoDescricao, novoInicio, novoTermino]);

  const salvarEdicaoItemArvore = useCallback(async () => {
    if (!dialogEdit) {
      return;
    }
    const di = dialogEdit.inicio ? toISODateLocal(dialogEdit.inicio) : '';
    const df = dialogEdit.termino ? toISODateLocal(dialogEdit.termino) : di;
    if (!dialogEdit.descricao.trim() || !di) {
      toast.current?.show({
        severity: 'warn',
        summary: 'Atenção',
        detail: 'Descrição e início são obrigatórios.',
        life: 3500,
      });
      return;
    }
    try {
      await agendaSvc.updateAgendaItem({
        agenda_id: dialogEdit.agendaId,
        agenda_item_id: dialogEdit.itemId,
        descricao: dialogEdit.descricao.trim(),
        inicio: di,
        termino: df,
      });
      toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Item atualizado.', life: 3000 });
      const aid = dialogEdit.agendaId;
      setDialogEdit(null);
      await atualizarRamificacao(aid);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Erro ao salvar.';
      toast.current?.show({ severity: 'error', summary: 'Erro', detail: msg, life: 4000 });
    }
  }, [agendaSvc, atualizarRamificacao, dialogEdit]);

  const solicitarExcluirItemArvore = useCallback(
    (agendaId: string, itemId: string) => {
      confirmDialog({
        message: 'Excluir este item da agenda? A tabela de passos não será alterada.',
        header: 'Confirmar exclusão',
        icon: 'pi pi-exclamation-triangle',
        acceptLabel: 'Excluir',
        rejectLabel: 'Cancelar',
        acceptClassName: 'p-button-danger',
        accept: async () => {
          try {
            await agendaSvc.deleteAgendaItem(agendaId, itemId);
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Item excluído.', life: 3000 });
            await atualizarRamificacao(agendaId);
          } catch (e: unknown) {
            const msg = e instanceof Error ? e.message : 'Erro ao excluir.';
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: msg, life: 4000 });
          }
        },
      });
    },
    [agendaSvc, atualizarRamificacao],
  );

  const indicadorSituacaoTemplate = (row: TreeNode) => {
    const d = row.data as NoData;
    if (d.tipo !== 'passo') {
      return null;
    }
    return (
      <div className="flex justify-content-center align-items-center w-full">
        <span
          className={`vecontab-ag-ind border-circle inline-block ${classeIndicadorCorCelula(d.backgroundColor)}`}
          title="Situação do passo"
          aria-hidden
        />
      </div>
    );
  };

  const nomeTemplate = (row: TreeNode) => {
    const d = row.data as NoData;
    return (
      <div className="flex align-items-center gap-2 flex-wrap">
        <span className="font-medium" style={{ color: corTextoParaCelula(d) }}>
          {d.titulo}
        </span>
        <Tag
          value={d.tipo === 'rotina' ? 'Processo' : 'Passo'}
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
    if (d.tipo === 'rotina') {
      const busy = loadingExpand === d.agendaId;
      return (
        <div className="flex justify-content-start pl-1">
          <Button
            type="button"
            icon="pi pi-plus"
            rounded
            severity="success"
            tooltip="Novo item na agenda"
            tooltipOptions={{ position: 'left' }}
            disabled={busy}
            onClick={() => abrirNovoItem(d.agendaId)}
            aria-label="Novo item na agenda"
          />
        </div>
      );
    }
    if (d.tipo !== 'passo' || !d.itemId) {
      return null;
    }
    const concluido = (d.backgroundColor || '').trim().toUpperCase() === '#22C55E';
    const busy = loadingExpand === d.agendaId;
    return (
      <div className="flex align-items-center justify-content-start gap-1 flex-wrap pl-1">
        {concluido ? (
          <Button
            type="button"
            icon="pi pi-replay"
            rounded
            severity="help"
            tooltip="Reabrir passo"
            tooltipOptions={{ position: 'left' }}
            disabled={busy}
            onClick={() => void reabrirPasso(d.agendaId, d.itemId!)}
            aria-label="Reabrir passo"
          />
        ) : (
          <Button
            type="button"
            icon="pi pi-check-circle"
            rounded
            severity="success"
            tooltip="Concluir passo"
            tooltipOptions={{ position: 'left' }}
            disabled={busy}
            onClick={() => void concluirPasso(d.agendaId, d.itemId!)}
            aria-label="Concluir passo"
          />
        )}
        <Button
          type="button"
          icon="pi pi-pencil"
          rounded
          severity="info"
          tooltip="Alterar"
          tooltipOptions={{ position: 'left' }}
          disabled={busy}
          onClick={() =>
            setDialogEdit({
              agendaId: d.agendaId,
              itemId: d.itemId!,
              descricao: d.titulo,
              inicio: parseDataNoLocal(d.inicio),
              termino: parseDataNoLocal(d.fim || d.inicio),
            })
          }
          aria-label="Alterar item"
        />
        <Button
          type="button"
          icon="pi pi-trash"
          rounded
          severity="warning"
          tooltip="Excluir"
          tooltipOptions={{ position: 'left' }}
          disabled={busy}
          onClick={() => solicitarExcluirItemArvore(d.agendaId, d.itemId!)}
          aria-label="Excluir item"
        />
      </div>
    );
  };

  const rowClassName = (row: TreeNode) => {
    const d = row.data as NoData;
    if (d?.tipo === 'passo') {
      return 'vecontab-agenda-arvore-row vecontab-agenda-arvore-passo';
    }
    return rowClassForCor(d?.backgroundColor || '');
  };

  const onToggleArvore: TreeTableProps['onToggle'] = (e) => setExpandedKeys(e.value);

  const painelFiltros = (
    <div className="p-toolbar mb-3 w-full">
      <div className="flex align-items-start justify-content-between gap-4 w-full flex-wrap lg:flex-nowrap">
        <div className="flex flex-wrap align-items-end gap-3 md:gap-4 flex-1 min-w-0">
          <div className="flex flex-column gap-1" style={{ minWidth: '12rem', maxWidth: '18rem', flex: '0 1 16rem' }}>
            <label htmlFor="agenda-arvore-filtro-cor" className="text-sm font-semibold text-900 m-0">
              Situação
            </label>
            <Dropdown
              inputId="agenda-arvore-filtro-cor"
              value={filtroCor}
              options={OPCOES_FILTRO_COR}
              onChange={(e) => setFiltroCor(e.value as FiltroCorAgenda)}
              optionLabel="label"
              optionValue="value"
              className="w-full"
            />
          </div>
          <div className="flex flex-column gap-1" style={{ minWidth: '12rem', maxWidth: '18rem', flex: '0 1 16rem' }}>
            <label htmlFor="agenda-arvore-filtro-rotina" className="text-sm font-semibold text-900 m-0">
              Processo
            </label>
            <Dropdown
              inputId="agenda-arvore-filtro-rotina"
              value={rotinaFiltro}
              options={opcoesRotinaDropdown}
              onChange={(e) => setRotinaFiltro((e.value as string | null) ?? null)}
              optionLabel="label"
              optionValue="value"
              showClear
              className="w-full"
            />
          </div>
          <div className="flex flex-column gap-1" style={{ minWidth: '12rem', maxWidth: '22rem', flex: '0 1 20rem' }}>
            <label htmlFor="agenda-arvore-busca-empresa" className="text-sm font-semibold text-900 m-0">
              Empresa (nome)
            </label>
            <InputText
              id="agenda-arvore-busca-empresa"
              value={textoEmpresaFiltro}
              onChange={(e) => setTextoEmpresaFiltro(e.target.value)}
              className="w-full"
            />
          </div>
        </div>
        <div className="flex flex-column gap-2 align-items-end text-right vecontab-agenda-arvore-legenda flex-shrink-0 ms-auto lg:ms-0">
          <span className="text-sm font-semibold text-900">Legenda (situação)</span>
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
        </div>
      </div>
    </div>
  );

  return (
    <div className="grid">
      <div className="col-12">
        <div className="card vecontab-agenda-arvore-card">
          <Toast ref={toast} />
          <ConfirmDialog />
          <h1 className="text-2xl font-bold text-900 m-0 mb-3">Processos em Árvore</h1>
          <p className="text-600 mt-0 mb-4 line-height-3">
            Primeiro nível: empresa e processo com intervalo de datas. Expanda para ver os passos, o intervalo
            de cada um e concluir manualmente — mesma regra de cores da agenda (atrasado, período atual,
            futuro, concluído).
          </p>
          {painelFiltros}
          <TreeTable
            value={nosExibicao}
            loading={loading}
            expandedKeys={expandedKeys}
            onToggle={onToggleArvore}
            onExpand={onExpand}
            tableStyle={{ minWidth: '50rem' }}
            rowClassName={rowClassName as unknown as TreeTableProps['rowClassName']}
            stripedRows
          >
            <Column
              header="Empresa / processo ou passo"
              body={nomeTemplate}
              expander
              style={{ minWidth: '260px' }}
            />
            <Column
              header=""
              body={indicadorSituacaoTemplate}
              headerStyle={{ width: '2.25rem', maxWidth: '2.25rem' }}
              style={{ width: '2.25rem', maxWidth: '2.25rem', textAlign: 'center', verticalAlign: 'middle' }}
            />
            <Column header="Período (início — fim)" body={periodoTemplate} style={{ minWidth: '220px' }} />
            <Column
              header="Ações"
              body={acoesTemplate}
              style={{ minWidth: '12.5rem', width: '12.5rem' }}
              bodyStyle={{ textAlign: 'left', paddingLeft: '0.35rem', paddingRight: '0.75rem' }}
            />
          </TreeTable>
          <Dialog
            visible={dialogNovoAgendaId != null}
            onHide={() => setDialogNovoAgendaId(null)}
            header="Novo item na agenda"
            style={{ width: 'min(96vw, 32rem)' }}
            modal
            footer={
              <div className="flex flex-wrap align-items-center gap-2 justify-content-start pr-3">
                <Button type="button" label="Cancelar" text onClick={() => setDialogNovoAgendaId(null)} />
                <Button type="button" label="Incluir" icon="pi pi-check" onClick={() => void salvarNovoItemArvore()} />
              </div>
            }
          >
            <div className="p-fluid flex flex-column gap-3">
              <div className="field">
                <label htmlFor="arv-novo-desc">Descrição</label>
                <InputText
                  id="arv-novo-desc"
                  value={novoDescricao}
                  onChange={(e) => setNovoDescricao(e.target.value)}
                />
              </div>
              <div className="field">
                <label htmlFor="arv-novo-ini">Início</label>
                <Calendar
                  id="arv-novo-ini"
                  value={novoInicio}
                  onChange={(e) => setNovoInicio(e.value as Date | null)}
                  dateFormat="dd/mm/yy"
                  showIcon
                  appendTo={typeof document !== 'undefined' ? document.body : undefined}
                />
              </div>
              <div className="field">
                <label htmlFor="arv-novo-fim">Término</label>
                <Calendar
                  id="arv-novo-fim"
                  value={novoTermino}
                  onChange={(e) => setNovoTermino(e.value as Date | null)}
                  dateFormat="dd/mm/yy"
                  showIcon
                  appendTo={typeof document !== 'undefined' ? document.body : undefined}
                />
              </div>
            </div>
          </Dialog>
          <Dialog
            visible={dialogEdit != null}
            onHide={() => setDialogEdit(null)}
            header="Alterar item da agenda"
            style={{ width: 'min(96vw, 32rem)' }}
            modal
            footer={
              <div className="flex flex-wrap align-items-center gap-2 justify-content-start pr-3">
                <Button type="button" label="Cancelar" text onClick={() => setDialogEdit(null)} />
                <Button type="button" label="Salvar" icon="pi pi-check" onClick={() => void salvarEdicaoItemArvore()} />
              </div>
            }
          >
            {dialogEdit && (
              <div className="p-fluid flex flex-column gap-3">
                <div className="field">
                  <label htmlFor="arv-ed-desc">Descrição</label>
                  <InputText
                    id="arv-ed-desc"
                    value={dialogEdit.descricao}
                    onChange={(e) =>
                      setDialogEdit((prev) => (prev ? { ...prev, descricao: e.target.value } : null))
                    }
                  />
                </div>
                <div className="field">
                  <label htmlFor="arv-ed-ini">Início</label>
                  <Calendar
                    id="arv-ed-ini"
                    value={dialogEdit.inicio}
                    onChange={(e) =>
                      setDialogEdit((prev) => (prev ? { ...prev, inicio: e.value as Date | null } : null))
                    }
                    dateFormat="dd/mm/yy"
                    showIcon
                    appendTo={typeof document !== 'undefined' ? document.body : undefined}
                  />
                </div>
                <div className="field">
                  <label htmlFor="arv-ed-fim">Término</label>
                  <Calendar
                    id="arv-ed-fim"
                    value={dialogEdit.termino}
                    onChange={(e) =>
                      setDialogEdit((prev) => (prev ? { ...prev, termino: e.value as Date | null } : null))
                    }
                    dateFormat="dd/mm/yy"
                    showIcon
                    appendTo={typeof document !== 'undefined' ? document.body : undefined}
                  />
                </div>
              </div>
            )}
          </Dialog>
          <div className="vecontab-agenda-arvore-fab-wrap">
            <Button
              type="button"
              icon="pi pi-refresh"
              className="p-button-text"
              tooltip="Atualizar"
              loading={loading}
              onClick={() => void carregarRaizes()}
              aria-label="Atualizar lista da agenda"
            />
          </div>
        </div>
      </div>
      <style jsx global>{`
                /* Passos: fundo neutro + recuo; coluna 2 = círculo (sem título). */
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-agenda-arvore-passo > td:nth-child(1)) {
                    padding-left: 2.5rem !important;
                    background: var(--surface-0, #ffffff) !important;
                    border-left: none !important;
                }
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-agenda-arvore-passo > td:nth-child(2)) {
                    padding: 0.35rem 0.25rem !important;
                    width: 2.25rem !important;
                    max-width: 2.25rem !important;
                    background: var(--surface-0, #ffffff) !important;
                    border-left: none !important;
                    vertical-align: middle !important;
                }
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-agenda-arvore-passo > td:nth-child(3)),
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-agenda-arvore-passo > td:nth-child(4)) {
                    padding-left: 2.5rem !important;
                    background: var(--surface-0, #ffffff) !important;
                    border-left: none !important;
                }
                :global(
                        .p-treetable.p-treetable-striped .p-treetable-tbody > tr.vecontab-agenda-arvore-passo:nth-child(even) > td
                    ) {
                    background: var(--surface-50, #fafafa) !important;
                }
                .vecontab-ag-ind {
                    width: 0.7rem;
                    height: 0.7rem;
                    box-sizing: border-box;
                    flex-shrink: 0;
                }
                .vecontab-ag-ind-atrasado {
                    background: #fde2e0;
                    border: 1px solid #f8c9c4;
                }
                .vecontab-ag-ind-vencendo {
                    background: #ffdab9;
                    border: 1px solid #e8c09a;
                }
                .vecontab-ag-ind-futuro {
                    background: #a0d6b4;
                    border: 1px solid #7fb89a;
                }
                .vecontab-ag-ind-concluido {
                    background: #22c55e;
                    border: 1px solid #16a34a;
                }
                .vecontab-ag-ind-neutro {
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
                .vecontab-agenda-arvore-legenda {
                    border-left: 1px solid var(--surface-200, #e5e7eb);
                    padding-left: 1.25rem;
                    margin-left: 0.75rem;
                }
                @media screen and (max-width: 991px) {
                    .vecontab-agenda-arvore-legenda {
                        border-left: none;
                        padding-left: 0;
                        margin-left: 0;
                    }
                }
                .vecontab-agenda-arvore-card {
                    position: relative;
                    padding-bottom: 3rem;
                }
                .vecontab-agenda-arvore-fab-wrap {
                    position: absolute;
                    left: 1rem;
                    bottom: 0.75rem;
                    z-index: 2;
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
