import React, { useEffect, useMemo, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { TreeTable, type TreeTableProps } from 'primereact/treetable';
import { TreeNode } from 'primereact/treenode';
import { Column } from 'primereact/column';
import { Button } from 'primereact/button';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
import { Dropdown } from 'primereact/dropdown';
import { Calendar } from 'primereact/calendar';
import { Toast } from 'primereact/toast';
import { ConfirmDialog, confirmDialog } from 'primereact/confirmdialog';
import { Checkbox } from 'primereact/checkbox';
import { Tag } from 'primereact/tag';
import CatalogoServicoService, { CatalogoServico } from '../../services/cruds/CatalogoServicoService';
import { canSSRAuth } from '../../components/utils/canSSRAuth';
import setupAPIClient from '../../components/api/api';

type FormState = Omit<CatalogoServico, 'id'>;

const SECOES_FIXAS = [
    'Integra-SN',
    'Integra-MEI',
    'Integra-DCTFWeb',
    'Integra-Procurações',
    'Integra-Sicalc',
    'Integra-CaixaPostal',
    'Integra-Pagamento',
    'Integra-Contador-Gerenciador',
    'Integra-SITFIS',
    'Integra-Parcelamentos',
    'Integra-Redesim',
    'Integra-e-Processo',
];

const emptyForm: FormState = {
    secao: '',
    sequencial: 1,
    codigo: '',
    id_sistema: '',
    id_servico: '',
    data_implantacao: '',
    tipo: '',
    descricao: '',
};

function toNodes(items: CatalogoServico[]): TreeNode[] {
    const agrupado = new Map<string, CatalogoServico[]>();
    for (const item of items) {
        const key = item.secao?.trim() || 'Sem seção';
        const lista = agrupado.get(key) ?? [];
        lista.push(item);
        agrupado.set(key, lista);
    }

    const secoesOrdenadas = Array.from(agrupado.keys()).sort((a, b) => a.localeCompare(b, 'pt-BR', { sensitivity: 'base' }));
    return secoesOrdenadas.map((secao) => {
        const children = (agrupado.get(secao) ?? [])
            .sort((a, b) => {
                const sa = Number(a.sequencial) || 0;
                const sb = Number(b.sequencial) || 0;
                if (sa !== sb) return sa - sb;
                return String(a.codigo ?? '').localeCompare(String(b.codigo ?? ''), 'pt-BR', { numeric: true, sensitivity: 'base' });
            })
            .map((s) => ({
                key: String(s.id),
                leaf: true,
                data: {
                    ...s,
                    isSecao: false,
                },
            }));
        return {
            key: `secao:${secao}`,
            leaf: false,
            data: {
                id: '',
                secao,
                sequencial: 0,
                codigo: '',
                id_sistema: '',
                id_servico: '',
                data_implantacao: '',
                tipo: '',
                descricao: `${children.length} serviço(s)`,
                ativo: true,
                isSecao: true,
            },
            children,
        } as TreeNode;
    });
}

export default function CatalogoServicosPage() {
    const toast = useRef<Toast>(null);
    const svc = useMemo(() => CatalogoServicoService(), []);
    const [secaoFiltro, setSecaoFiltro] = useState<string>('TODAS');
    const [incluirInativos, setIncluirInativos] = useState(false);
    const [dialogVisible, setDialogVisible] = useState(false);
    const [submitted, setSubmitted] = useState(false);
    const [editingId, setEditingId] = useState<string | null>(null);
    const [secaoContextoDialog, setSecaoContextoDialog] = useState<string>('');
    const [form, setForm] = useState<FormState>(emptyForm);
    const { data: roleData, isFetching: isFetchingRole } = useQuery({
        queryKey: ['catalogo-servicos-user-role'],
        queryFn: async () => {
            const api = setupAPIClient(undefined);
            const { data } = await api.get('/api/usuariorole');
            return data?.logado?.role ?? '';
        },
        staleTime: 0,
        gcTime: 0,
        refetchOnMount: 'always',
        refetchOnWindowFocus: true,
        refetchOnReconnect: 'always',
    });
    const podeManter = !isFetchingRole && roleData === 'SUPER';

    const { data, isFetching, refetch, isError, error } = useQuery<CatalogoServico[]>({
        queryKey: ['catalogo-servicos', secaoFiltro, incluirInativos],
        queryFn: () =>
            svc.list({
                secao: secaoFiltro === 'TODAS' ? '' : secaoFiltro,
                incluirInativos,
            }),
        staleTime: 0,
        gcTime: 0,
        refetchOnMount: 'always',
        refetchOnWindowFocus: true,
    });

    useEffect(() => {
        if (!isError || !error) return;
        const msg =
            (error as { response?: { data?: { error?: string; message?: string } } })?.response?.data?.error ||
            (error as { response?: { data?: { error?: string; message?: string } } })?.response?.data?.message ||
            (error as Error)?.message ||
            'Falha ao carregar catálogo.';
        toast.current?.show({ severity: 'error', summary: 'Erro', detail: msg, life: 7000 });
    }, [isError, error]);

    const nodes = useMemo(() => toNodes(data ?? []), [data]);

    const opcoesSecao = useMemo(() => {
        return [{ label: 'Todas as seções', value: 'TODAS' }, ...SECOES_FIXAS.map((s) => ({ label: s, value: s }))];
    }, []);

    const abrirNovo = (secaoPadrao?: string) => {
        if (!podeManter) return;
        const secaoInicial = (secaoPadrao ?? '').trim() || (secaoFiltro !== 'TODAS' ? secaoFiltro : '');
        setSubmitted(false);
        setEditingId(null);
        setSecaoContextoDialog(secaoInicial);
        setForm({ ...emptyForm, secao: secaoInicial });
        setDialogVisible(true);
    };

    const abrirEditar = (row: CatalogoServico) => {
        if (!podeManter) return;
        setSubmitted(false);
        setEditingId(row.id);
        setSecaoContextoDialog(row.secao);
        setForm({
            secao: row.secao,
            sequencial: row.sequencial,
            codigo: row.codigo,
            id_sistema: row.id_sistema,
            id_servico: row.id_servico,
            data_implantacao: row.data_implantacao || '',
            tipo: row.tipo,
            descricao: row.descricao,
        });
        setDialogVisible(true);
    };

    const excluir = (id: string) => {
        if (!podeManter) return;
        confirmDialog({
            header: 'Confirmar exclusão',
            message: 'Deseja excluir este serviço do catálogo?',
            icon: 'pi pi-exclamation-triangle',
            acceptLabel: 'Excluir',
            rejectLabel: 'Cancelar',
            acceptClassName: 'p-button-danger',
            accept: async () => {
                try {
                    await svc.remove(id);
                    toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Serviço excluído.', life: 3000 });
                    await refetch();
                } catch (e: any) {
                    const msg = e?.response?.data?.error || e?.response?.data?.message || 'Falha ao excluir';
                    toast.current?.show({ severity: 'error', summary: 'Erro', detail: msg, life: 5000 });
                }
            },
        });
    };

    const salvar = async () => {
        if (!podeManter) return;
        setSubmitted(true);
        if (!form.secao.trim() || form.sequencial <= 0 || !form.codigo.trim() || !form.id_sistema.trim() || !form.id_servico.trim() || !form.tipo.trim() || !form.descricao.trim()) {
            return;
        }
        try {
            if (editingId) {
                await svc.update({ id: editingId, ...form });
            } else {
                await svc.create(form);
            }
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Serviço salvo.', life: 3000 });
            setDialogVisible(false);
            setForm(emptyForm);
            setEditingId(null);
            setSecaoContextoDialog('');
            await refetch();
        } catch (e: any) {
            const msg = e?.response?.data?.error || e?.response?.data?.message || 'Falha ao salvar';
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: msg, life: 5000 });
        }
    };

    const isInvalid = (v: string) => submitted && !v.trim();

    const descricaoTemplate = (node: TreeNode) => {
        const d = node.data as any;
        if (d.isSecao) {
            return <strong>{d.descricao}</strong>;
        }
        return (
            <span className="flex align-items-center gap-2 flex-wrap">
                <span>{d.descricao}</span>
                {d.ativo === false && <Tag value="Inativo" severity="secondary" className="text-xs" />}
            </span>
        );
    };

    const rowClassCatalogo: TreeTableProps['rowClassName'] = (node) => {
        const d = node.data as { isSecao?: boolean; ativo?: boolean } | undefined;
        if (d?.isSecao || d?.ativo !== false) {
            return '';
        }
        return 'vecontab-catalogo-linha-inativa';
    };

    const acoesTemplate = (node: TreeNode) => {
        const d = node.data as any;
        if (!podeManter) return null;
        if (d.isSecao) {
            return (
                <div className="flex justify-content-start pl-1">
                    <Button
                        type="button"
                        icon="pi pi-plus"
                        rounded
                        severity="success"
                        tooltip={`Incluir serviço em ${d.secao}`}
                        tooltipOptions={{ position: 'left' }}
                        onClick={() => abrirNovo(String(d.secao ?? ''))}
                        aria-label={`Incluir serviço na seção ${d.secao}`}
                    />
                </div>
            );
        }
        if (d.ativo === false) return null;
        return (
            <div className="flex align-items-center justify-content-start gap-2 flex-wrap pl-1">
                <Button type="button" icon="pi pi-pencil" rounded severity="success" onClick={() => abrirEditar(d as CatalogoServico)} />
                <Button type="button" icon="pi pi-trash" rounded severity="warning" onClick={() => excluir(d.id)} />
            </div>
        );
    };

    return (
        <div className="grid">
            <div className="col-12">
                <div className="card vecontab-catalogo-servico-card">
                    <Toast ref={toast} />
                    <ConfirmDialog />
                    <h1 className="text-2xl font-bold text-900 m-0 mb-3">Catálogo de Serviços - Integra Contador</h1>
                    <div className="flex flex-wrap gap-3 align-items-end mb-3">
                        <div className="flex flex-column gap-1" style={{ minWidth: '18rem' }}>
                            <label htmlFor="filtro-secao" className="text-sm font-semibold">Seção</label>
                            <Dropdown
                                inputId="filtro-secao"
                                value={secaoFiltro}
                                options={opcoesSecao}
                                optionLabel="label"
                                optionValue="value"
                                onChange={(e) => setSecaoFiltro(e.value)}
                                className="w-full"
                            />
                        </div>
                        <div className="flex align-items-center gap-2">
                            <Checkbox
                                inputId="catalogo-incluir-inativos"
                                checked={incluirInativos}
                                onChange={(e) => setIncluirInativos(Boolean(e.checked))}
                            />
                            <label htmlFor="catalogo-incluir-inativos" className="text-sm cursor-pointer m-0">
                                Incluir inativos (excluídos logicamente)
                            </label>
                        </div>
                    </div>
                    <p className="text-600 text-sm mt-0 mb-3">
                        Por padrão a lista mostra apenas serviços ativos. Marque a opção acima para ver também registros com{' '}
                        <code className="text-sm">ativo = false</code> (exclusão lógica).
                    </p>
                    <TreeTable
                        value={nodes}
                        stripedRows
                        loading={isFetching}
                        sortMode="single"
                        defaultSortOrder={1}
                        tableStyle={{ minWidth: '72rem' }}
                        rowClassName={rowClassCatalogo}
                    >
                        <Column field="secao" header="Seção" expander style={{ minWidth: '14rem' }} />
                        <Column field="sequencial" header="Sequencial" sortable style={{ width: '8rem' }} />
                        <Column field="codigo" header="Código" style={{ width: '8rem' }} />
                        <Column field="id_sistema" header="idSistema" style={{ minWidth: '10rem' }} />
                        <Column field="id_servico" header="idServico" style={{ minWidth: '12rem' }} />
                        <Column field="data_implantacao" header="Data implantação" style={{ minWidth: '10rem' }} />
                        <Column field="tipo" header="Tipo" style={{ width: '9rem' }} />
                        <Column header="Descrição" body={descricaoTemplate} field="descricao" style={{ minWidth: '16rem' }} />
                        {podeManter && <Column header="Ações" body={acoesTemplate} style={{ width: '8rem' }} />}
                    </TreeTable>
                    <div className="flex justify-content-start mt-2">
                        <Button
                            type="button"
                            icon="pi pi-refresh"
                            tooltip="Atualizar"
                            className="p-button-text"
                            loading={isFetching}
                            onClick={() => void refetch()}
                        />
                    </div>
                    <Dialog
                        visible={dialogVisible}
                        onHide={() => {
                            setDialogVisible(false);
                            setSecaoContextoDialog('');
                        }}
                        header={editingId ? 'Alterar serviço' : 'Novo serviço'}
                        style={{ width: 'min(96vw, 52rem)' }}
                        modal
                        footer={
                            <div className="flex gap-2 justify-content-end">
                                <Button type="button" label="Cancelar" text onClick={() => setDialogVisible(false)} />
                                <Button type="button" label="Salvar" icon="pi pi-check" onClick={() => void salvar()} />
                            </div>
                        }
                    >
                        <div className="mb-3 p-2 border-round surface-50">
                            <span className="text-sm text-700">
                                Seção vinculada: <strong>{form.secao || secaoContextoDialog || 'Selecione uma seção'}</strong>
                            </span>
                        </div>
                        <div className="grid p-fluid">
                            <div className="col-12 md:col-5">
                                <label htmlFor="secao" className="font-medium">Seção</label>
                                <Dropdown
                                    id="secao"
                                    value={form.secao}
                                    options={SECOES_FIXAS.map((s) => ({ label: s, value: s }))}
                                    optionLabel="label"
                                    optionValue="value"
                                    onChange={(e) => setForm((p) => ({ ...p, secao: e.value ?? '' }))}
                                    className={`w-full ${isInvalid(form.secao) ? 'p-invalid' : ''}`}
                                />
                                {isInvalid(form.secao) && <small className="p-error">Informe a seção.</small>}
                            </div>
                            <div className="col-12 md:col-2">
                                <label htmlFor="sequencial" className="font-medium">Sequencial</label>
                                <InputText
                                    id="sequencial"
                                    type="number"
                                    value={String(form.sequencial)}
                                    onChange={(e) => setForm((p) => ({ ...p, sequencial: Number(e.target.value || 0) }))}
                                />
                            </div>
                            <div className="col-12 md:col-2">
                                <label htmlFor="codigo" className="font-medium">Código</label>
                                <InputText id="codigo" value={form.codigo} onChange={(e) => setForm((p) => ({ ...p, codigo: e.target.value }))} className={isInvalid(form.codigo) ? 'p-invalid' : ''} />
                                {isInvalid(form.codigo) && <small className="p-error">Informe o código.</small>}
                            </div>
                            <div className="col-12 md:col-3">
                                <label htmlFor="tipo" className="font-medium">Tipo</label>
                                <InputText id="tipo" value={form.tipo} onChange={(e) => setForm((p) => ({ ...p, tipo: e.target.value }))} className={isInvalid(form.tipo) ? 'p-invalid' : ''} />
                                {isInvalid(form.tipo) && <small className="p-error">Informe o tipo.</small>}
                            </div>
                            <div className="col-12 md:col-4">
                                <label htmlFor="idsistema" className="font-medium">idSistema</label>
                                <InputText id="idsistema" value={form.id_sistema} onChange={(e) => setForm((p) => ({ ...p, id_sistema: e.target.value }))} className={isInvalid(form.id_sistema) ? 'p-invalid' : ''} />
                                {isInvalid(form.id_sistema) && <small className="p-error">Informe o idSistema.</small>}
                            </div>
                            <div className="col-12 md:col-4">
                                <label htmlFor="idservico" className="font-medium">idServico</label>
                                <InputText id="idservico" value={form.id_servico} onChange={(e) => setForm((p) => ({ ...p, id_servico: e.target.value }))} className={isInvalid(form.id_servico) ? 'p-invalid' : ''} />
                                {isInvalid(form.id_servico) && <small className="p-error">Informe o idServico.</small>}
                            </div>
                            <div className="col-12 md:col-4">
                                <label htmlFor="data_implantacao" className="font-medium">Data de implantação</label>
                                <Calendar
                                    id="data_implantacao"
                                    value={form.data_implantacao ? new Date(`${form.data_implantacao}T12:00:00`) : null}
                                    onChange={(e) => {
                                        const dt = e.value as Date | null;
                                        if (!dt) {
                                            setForm((p) => ({ ...p, data_implantacao: '' }));
                                            return;
                                        }
                                        const y = dt.getFullYear();
                                        const m = String(dt.getMonth() + 1).padStart(2, '0');
                                        const d = String(dt.getDate()).padStart(2, '0');
                                        setForm((p) => ({ ...p, data_implantacao: `${y}-${m}-${d}` }));
                                    }}
                                    dateFormat="dd/mm/yy"
                                    showIcon
                                    appendTo={typeof document !== 'undefined' ? document.body : undefined}
                                    className="w-full"
                                />
                            </div>
                            <div className="col-12">
                                <label htmlFor="descricao" className="font-medium">Descrição</label>
                                <InputText id="descricao" value={form.descricao} onChange={(e) => setForm((p) => ({ ...p, descricao: e.target.value }))} className={isInvalid(form.descricao) ? 'p-invalid' : ''} />
                                {isInvalid(form.descricao) && <small className="p-error">Informe a descrição.</small>}
                            </div>
                        </div>
                    </Dialog>
                </div>
            </div>
            <style jsx global>{`
                .vecontab-catalogo-servico-card {
                    position: relative;
                }
                :global(.p-treetable .p-treetable-tbody > tr.vecontab-catalogo-linha-inativa > td) {
                    opacity: 0.72;
                    background: var(--surface-100, #f1f5f9) !important;
                }
            `}</style>
        </div>
    );
}

export const getServerSideProps = canSSRAuth(async (ctx) => {
    try {
        const apiClient = setupAPIClient(ctx);
        await apiClient.get('/api/registro');
        return { props: {} };
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
