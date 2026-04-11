import setupAPIClient from '../../components/api/api';
import { canSSRAuth } from '../../components/utils/canSSRAuth';
import { Button } from 'primereact/button';
import { Column } from 'primereact/column';
import { Dialog } from 'primereact/dialog';
import { Dropdown } from 'primereact/dropdown';
import { InputText } from 'primereact/inputtext';
import { Toast } from 'primereact/toast';
import { Toolbar } from 'primereact/toolbar';
import { TreeTable } from 'primereact/treetable';
import type { TreeTableProps } from 'primereact/treetable';
import type { TreeNode } from 'primereact/treenode';
import { classNames } from 'primereact/utils';
import { useQueries, useQuery, useQueryClient } from '@tanstack/react-query';
import { AxiosError } from 'axios';
import { useEffect, useMemo, useRef, useState } from 'react';
import UsuarioService from '../../services/cruds/UsuarioService';

type TenantListRow = {
  id: string;
  nome: string;
  contato: string;
  active: boolean;
  plano: string;
  cnpj?: string;
  razaosocial?: string;
  fantasia?: string;
};

type DadosTenant = {
  tenantid: string;
  cnpj: string;
  cep: string;
  endereco: string;
  bairro: string;
  cidade: string;
  estado: string;
  telefone: string;
  email: string;
  ie: string;
  im: string;
  razaosocial: string;
  fantasia: string;
  observacoes: string;
};

const emptyDados = (tenantId: string): DadosTenant => ({
  tenantid: tenantId,
  cnpj: '',
  cep: '',
  endereco: '',
  bairro: '',
  cidade: '',
  estado: '',
  telefone: '',
  email: '',
  ie: '',
  im: '',
  razaosocial: '',
  fantasia: '',
  observacoes: '',
});

const PLANO_OPTS = [
  { label: 'DEMO', value: 'DEMO' },
  { label: 'Básico', value: 'BASICO' },
  { label: 'PRO', value: 'PRO' },
  { label: 'PREMIUM', value: 'PREMIUM' },
];

const STATUS_TENANT_OPTS = [
  { label: 'Ativo', value: true },
  { label: 'Inativo', value: false },
];

type UsuarioLinha = {
  id: string;
  nome: string;
  email: string;
  role: string;
  tenantid: string;
  active: boolean;
};

const apiErr = (err: unknown) =>
  (err as AxiosError<{ error?: string }>)?.response?.data?.error ||
  (err as Error)?.message ||
  'Operação não concluída.';

export default function TenantsPage() {
  const api = setupAPIClient(undefined);
  const qc = useQueryClient();
  const toast = useRef<Toast>(null);
  const usuarioService = UsuarioService();

  const [tenantDialog, setTenantDialog] = useState(false);
  const [isNewTenant, setIsNewTenant] = useState(false);
  const [submitted, setSubmitted] = useState(false);

  const [tenantId, setTenantId] = useState('');
  const [nome, setNome] = useState('');
  const [contato, setContato] = useState('');
  const [plano, setPlano] = useState('DEMO');
  const [active, setActive] = useState(true);
  const [dados, setDados] = useState<DadosTenant>(emptyDados(''));

  const [userDialog, setUserDialog] = useState(false);
  const [userDeleteOpen, setUserDeleteOpen] = useState(false);
  const [usuarioEdicao, setUsuarioEdicao] = useState<UsuarioLinha | null>(null);
  const [usuarioNome, setUsuarioNome] = useState('');
  const [usuarioEmail, setUsuarioEmail] = useState('');
  const [usuarioRole, setUsuarioRole] = useState('USER');
  const [usuarioSenha, setUsuarioSenha] = useState('');
  /** Tenant ao qual o diálogo de usuário (criar/editar) se refere — independente do diálogo de tenant. */
  const [usuarioTenantId, setUsuarioTenantId] = useState('');

  const [expandedKeysLista, setExpandedKeysLista] = useState<Record<string, boolean>>({});

  const { data: tenants = [], isFetching, refetch } = useQuery({
    queryKey: ['tenants-super-list'],
    queryFn: async () => {
      const { data } = await api.get<TenantListRow[]>('/api/tenants');
      return Array.isArray(data) ? data : [];
    },
  });

  const { data: dadosApi, isFetching: loadingDados } = useQuery({
    queryKey: ['tenant-dados', tenantId],
    enabled: tenantDialog && !isNewTenant && Boolean(tenantId),
    queryFn: async () => {
      const { data } = await api.get<DadosTenant>('/api/tenant-dados', { params: { tenantId } });
      return data;
    },
  });

  const usuariosPorTenantQueries = useQueries({
    queries: tenants.map((t) => ({
      queryKey: ['usuarios-tenant', t.id] as const,
      enabled: tenants.length > 0,
      queryFn: async () => {
        const { data } = await api.get<{ usuarios: UsuarioLinha[]; totalRecords?: { resTotal: number } }>('/api/usuarios', {
          params: {
            first: 0,
            rows: 500,
            sortField: 'nome',
            sortOrder: 1,
            filters: JSON.stringify({ nome: { value: '', matchMode: 'contains' } }),
            tenantId: t.id,
          },
        });
        return data;
      },
    })),
  });

  const usuariosListaVersao = usuariosPorTenantQueries.map((q) => q.dataUpdatedAt).join('|');

  const arvoreCadastroTenants: TreeNode[] = useMemo(() => {
    return tenants.map((t, idx) => {
      const usuarios = usuariosPorTenantQueries[idx]?.data?.usuarios ?? [];
      const filhos: TreeNode[] = (usuarios as UsuarioLinha[]).map((u) => ({
        key: `u-${t.id}-${u.id}`,
        data: {
          tipo: 'usuario' as const,
          tenantId: t.id,
          id: u.id,
          nome: u.nome,
          email: u.email,
          role: u.role,
        },
      }));
      return {
        key: `t-${t.id}`,
        data: {
          tipo: 'tenant' as const,
          id: t.id,
          nome: t.nome,
          contato: t.contato ?? '',
          active: t.active,
          plano: t.plano ?? '',
          cnpj: t.cnpj ?? '',
          razaosocial: t.razaosocial ?? '',
          fantasia: t.fantasia ?? '',
        },
        children: filhos,
      };
    });
  }, [tenants, usuariosListaVersao, usuariosPorTenantQueries]);

  const loadingUsuariosLista = usuariosPorTenantQueries.some((q) => q.isFetching);

  const onToggleLista: TreeTableProps['onToggle'] = (e) => setExpandedKeysLista(e.value as Record<string, boolean>);

  const expandirTudoLista = () => {
    if (tenants.length === 0) {
      return;
    }
    const next: Record<string, boolean> = {};
    tenants.forEach((t) => {
      next[`t-${t.id}`] = true;
    });
    setExpandedKeysLista(next);
  };

  const recolherTudoLista = () => setExpandedKeysLista({});

  useEffect(() => {
    if (!tenantDialog || isNewTenant || !tenantId) {
      return;
    }
    if (dadosApi) {
      setDados({
        ...emptyDados(tenantId),
        ...dadosApi,
        tenantid: tenantId,
      });
    }
  }, [dadosApi, tenantDialog, isNewTenant, tenantId]);

  const openNew = () => {
    setIsNewTenant(true);
    setTenantId('');
    setNome('');
    setContato('');
    setPlano('DEMO');
    setActive(true);
    setDados(emptyDados(''));
    setSubmitted(false);
    setTenantDialog(true);
  };

  const openEdit = (row: TenantListRow) => {
    setIsNewTenant(false);
    setTenantId(row.id);
    setNome(row.nome);
    setContato(row.contato ?? '');
    setPlano(row.plano || 'DEMO');
    setActive(row.active);
    setDados(emptyDados(row.id));
    setSubmitted(false);
    setTenantDialog(true);
  };

  const hideTenantDialog = () => {
    setTenantDialog(false);
    setSubmitted(false);
  };

  const salvarNovoTenant = async () => {
    setSubmitted(true);
    if (!nome.trim()) {
      toast.current?.show({ severity: 'warn', summary: 'Validação', detail: 'Informe o nome do tenant.', life: 3500 });
      return;
    }
    try {
      await api.post('/api/tenant', { nome: nome.trim(), contato: contato.trim(), plano });
      toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Tenant criado.', life: 3000 });
      await qc.invalidateQueries({ queryKey: ['tenants-super-list'] });
      await qc.invalidateQueries({ queryKey: ['usuarios-tenant'] });
      hideTenantDialog();
    } catch (e) {
      toast.current?.show({ severity: 'error', summary: 'Erro', detail: apiErr(e), life: 5000 });
    }
  };

  const salvarDados = async (): Promise<boolean> => {
    if (!tenantId || isNewTenant) {
      return true;
    }
    try {
      await api.put('/api/tenant-dados', {
        tenantId,
        cnpj: dados.cnpj,
        cep: dados.cep,
        endereco: dados.endereco,
        bairro: dados.bairro,
        cidade: dados.cidade,
        estado: dados.estado,
        telefone: dados.telefone,
        email: dados.email,
        ie: dados.ie,
        im: dados.im,
        razaosocial: dados.razaosocial,
        fantasia: dados.fantasia,
        observacoes: dados.observacoes,
      });
      await qc.invalidateQueries({ queryKey: ['tenants-super-list'] });
      await qc.invalidateQueries({ queryKey: ['tenant-dados', tenantId] });
      return true;
    } catch (e) {
      toast.current?.show({ severity: 'error', summary: 'Erro', detail: apiErr(e), life: 5000 });
      return false;
    }
  };

  /** Persiste cabeçalho do tenant (plano, etc.) + endereço em tenant_dados. */
  const salvarPrincipalTenant = async () => {
    setSubmitted(true);
    if (!nome.trim()) {
      toast.current?.show({ severity: 'warn', summary: 'Validação', detail: 'Informe o nome do tenant.', life: 3500 });
      return;
    }
    try {
      await api.put('/api/tenant', {
        id: tenantId,
        nome: nome.trim(),
        contato: contato.trim(),
        plano,
        active,
      });
    } catch (e) {
      toast.current?.show({ severity: 'error', summary: 'Erro', detail: apiErr(e), life: 5000 });
      return;
    }
    const dadosOk = await salvarDados();
    if (!dadosOk) {
      return;
    }
    toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Tenant e endereço atualizados.', life: 3000 });
    await qc.invalidateQueries({ queryKey: ['tenants-super-list'] });
    await qc.invalidateQueries({ queryKey: ['usuarios-tenant'] });
    hideTenantDialog();
  };

  const recarregarCadastro = () => {
    void qc.invalidateQueries({ queryKey: ['tenants-super-list'] });
    void qc.invalidateQueries({ queryKey: ['usuarios-tenant'] });
    void refetch();
  };

  const colunaListaIdentificacao = (node: TreeNode) => {
    if (node.data?.tipo === 'tenant') {
      return (
        <div className="flex flex-column gap-1">
          <span className="p-tag p-tag-info">Tenant</span>
          <span className="font-semibold">{node.data.nome}</span>
        </div>
      );
    }
    return (
      <div className="flex flex-column gap-1 pl-2" style={{ borderLeft: '2px solid var(--primary-color)' }}>
        <span className="p-tag p-tag-secondary text-xs">Usuário</span>
        <span>{node.data?.nome}</span>
        <span className="text-600 text-sm">{node.data?.email}</span>
      </div>
    );
  };

  const colunaListaPlano = (node: TreeNode) => {
    if (node.data?.tipo !== 'tenant') {
      return <span className="text-500">{node.data?.role ?? '—'}</span>;
    }
    return <span>{PLANO_OPTS.find((p) => p.value === node.data?.plano)?.label ?? node.data?.plano}</span>;
  };

  const colunaListaContato = (node: TreeNode) => (node.data?.tipo === 'tenant' ? node.data?.contato || '—' : '—');

  const colunaListaCnpj = (node: TreeNode) => (node.data?.tipo === 'tenant' ? node.data?.cnpj || '—' : '—');

  const colunaListaRazao = (node: TreeNode) => (node.data?.tipo === 'tenant' ? node.data?.razaosocial || '—' : '—');

  const colunaListaAtivo = (node: TreeNode) => {
    if (node.data?.tipo !== 'tenant') {
      return '—';
    }
    return node.data?.active ? 'Sim' : 'Não';
  };

  const colunaListaAcoes = (node: TreeNode) => {
    if (node.data?.tipo === 'tenant') {
      const row: TenantListRow = {
        id: String(node.data.id),
        nome: String(node.data.nome),
        contato: String(node.data.contato ?? ''),
        active: Boolean(node.data.active),
        plano: String(node.data.plano ?? ''),
        cnpj: String(node.data.cnpj ?? ''),
        razaosocial: String(node.data.razaosocial ?? ''),
        fantasia: String(node.data.fantasia ?? ''),
      };
      const tid = String(node.data.id);
      return (
        <div className="flex flex-wrap gap-2 justify-content-end">
          <Button type="button" icon="pi pi-pencil" rounded severity="success" tooltip="Plano e endereço" onClick={() => openEdit(row)} />
          <Button type="button" icon="pi pi-user-plus" rounded severity="info" tooltip="Novo usuário" onClick={() => abrirNovoUsuario(tid)} />
        </div>
      );
    }
    if (node.data?.tipo === 'usuario') {
      const tid = String(node.data.tenantId);
      const u: UsuarioLinha = {
        id: String(node.data.id),
        nome: String(node.data.nome),
        email: String(node.data.email),
        role: String(node.data.role),
        tenantid: tid,
        active: true,
      };
      return (
        <div className="flex flex-wrap gap-2 justify-content-end">
          <Button type="button" icon="pi pi-pencil" rounded severity="success" tooltip="Editar usuário" onClick={() => abrirEditarUsuario(u, tid)} />
          <Button type="button" icon="pi pi-trash" rounded severity="warning" tooltip="Desativar usuário" onClick={() => confirmarExcluirUsuario(u, tid)} />
        </div>
      );
    }
    return null;
  };

  const abrirNovoUsuario = (tid: string) => {
    setUsuarioTenantId(tid);
    setUsuarioEdicao(null);
    setUsuarioNome('');
    setUsuarioEmail('');
    setUsuarioRole('USER');
    setUsuarioSenha('');
    setUserDialog(true);
  };

  const abrirEditarUsuario = (u: UsuarioLinha, tid: string) => {
    setUsuarioTenantId(tid);
    setUsuarioEdicao(u);
    setUsuarioNome(u.nome);
    setUsuarioEmail(u.email);
    setUsuarioRole(u.role === 'ADMIN' ? 'ADMIN' : 'USER');
    setUsuarioSenha('');
    setUserDialog(true);
  };

  const salvarUsuario = async () => {
    const tid = usuarioTenantId.trim();
    if (!tid) {
      toast.current?.show({ severity: 'warn', summary: 'Validação', detail: 'Tenant do usuário não identificado.', life: 3500 });
      return;
    }
    if (!usuarioNome.trim() || !usuarioEmail.trim()) {
      toast.current?.show({ severity: 'warn', summary: 'Validação', detail: 'Nome e e-mail são obrigatórios.', life: 3500 });
      return;
    }
    if (!usuarioEdicao && !usuarioSenha.trim()) {
      toast.current?.show({ severity: 'warn', summary: 'Validação', detail: 'Informe a senha para o novo usuário.', life: 3500 });
      return;
    }
    try {
      if (usuarioEdicao) {
        await usuarioService.updateUsuario({
          id: usuarioEdicao.id,
          nome: usuarioNome.trim(),
          email: usuarioEmail.trim(),
          role: usuarioRole,
          tenantId: tid,
        });
        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Usuário atualizado.', life: 3000 });
      } else {
        await usuarioService.createUsuario({
          nome: usuarioNome.trim(),
          email: usuarioEmail.trim(),
          password: usuarioSenha,
          role: usuarioRole,
          tenantId: tid,
        });
        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Usuário criado.', life: 3000 });
      }
      setUserDialog(false);
      await qc.invalidateQueries({ queryKey: ['usuarios-tenant'] });
    } catch (e) {
      toast.current?.show({ severity: 'error', summary: 'Erro', detail: apiErr(e), life: 5000 });
    }
  };

  const confirmarExcluirUsuario = (u: UsuarioLinha, tid: string) => {
    setUsuarioTenantId(tid);
    setUsuarioEdicao(u);
    setUserDeleteOpen(true);
  };

  const excluirUsuario = async () => {
    if (!usuarioEdicao) {
      return;
    }
    try {
      await usuarioService.deleteUsuario({ id: usuarioEdicao.id });
      toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Usuário desativado.', life: 3000 });
      setUserDeleteOpen(false);
      setUsuarioEdicao(null);
      await qc.invalidateQueries({ queryKey: ['usuarios-tenant'] });
    } catch (e) {
      toast.current?.show({ severity: 'error', summary: 'Erro', detail: apiErr(e), life: 5000 });
    }
  };

  return (
    <div className="grid crud-demo">
      <div className="col-12">
        <div className="card">
          <Toast ref={toast} />
          <Toolbar
            className="mb-4"
            left={
              <div className="my-2 flex flex-wrap align-items-center gap-2">
                <Button type="button" label="Novo tenant" icon="pi pi-plus" severity="success" onClick={openNew} />
                <Button type="button" label="Expandir tudo" icon="pi pi-angle-double-down" text onClick={expandirTudoLista} disabled={tenants.length === 0} />
                <Button type="button" label="Recolher tudo" icon="pi pi-angle-double-up" text onClick={recolherTudoLista} disabled={tenants.length === 0} />
              </div>
            }
          />

          <div className="flex align-items-center justify-content-between mb-3 flex-wrap gap-2">
            <h5 className="m-0">Cadastro de Tenants (SUPER)</h5>
            <Button type="button" icon="pi pi-refresh" tooltip="Atualizar" className="p-button-text" onClick={() => recarregarCadastro()} />
          </div>
          <TreeTable
            value={arvoreCadastroTenants}
            loading={isFetching || loadingUsuariosLista}
            emptyMessage="Nenhum tenant encontrado."
            expandedKeys={expandedKeysLista}
            onToggle={onToggleLista}
            tableStyle={{ minWidth: '48rem' }}
          >
            <Column header="Tenant / Usuário" expander body={colunaListaIdentificacao} style={{ minWidth: '18rem' }} />
            <Column header="Plano / Perfil" body={colunaListaPlano} style={{ minWidth: '9rem' }} />
            <Column header="Contato (tenant)" body={colunaListaContato} style={{ minWidth: '10rem' }} />
            <Column header="CNPJ" body={colunaListaCnpj} style={{ minWidth: '9rem' }} />
            <Column header="Razão social" body={colunaListaRazao} style={{ minWidth: '12rem' }} />
            <Column header="Ativo" body={colunaListaAtivo} style={{ width: '5rem' }} />
            <Column header="Ações" body={colunaListaAcoes} style={{ minWidth: '8rem' }} />
          </TreeTable>

          <Dialog
            visible={tenantDialog}
            onHide={hideTenantDialog}
            header={isNewTenant ? 'Novo tenant' : 'Tenant — plano e endereço'}
            modal
            className="p-fluid"
            style={{ width: 'min(40rem, 96vw)' }}
            footer={
              <>
                <Button type="button" label="Cancelar" icon="pi pi-times" text onClick={hideTenantDialog} />
                {isNewTenant ? (
                  <Button type="button" label="Salvar" icon="pi pi-check" text onClick={() => void salvarNovoTenant()} />
                ) : (
                  <Button
                    type="button"
                    label="Salvar tenant e endereço"
                    icon="pi pi-check"
                    text
                    disabled={loadingDados}
                    onClick={() => void salvarPrincipalTenant()}
                  />
                )}
              </>
            }
          >
            {isNewTenant ? (
              <>
                <div className="field">
                  <label htmlFor="tnome">Nome</label>
                  <InputText
                    id="tnome"
                    value={nome}
                    onChange={(e) => setNome(e.target.value)}
                    className={classNames({ 'p-invalid': submitted && !nome.trim() })}
                  />
                  {submitted && !nome.trim() && <small className="p-invalid">Obrigatório.</small>}
                </div>
                <div className="field">
                  <label htmlFor="tcontato">Contato</label>
                  <InputText id="tcontato" value={contato} onChange={(e) => setContato(e.target.value)} className="w-full" />
                </div>
                <div className="field">
                  <label htmlFor="tplano">Plano</label>
                  <Dropdown inputId="tplano" value={plano} options={PLANO_OPTS} onChange={(e) => setPlano(e.value)} className="w-full" />
                </div>
              </>
            ) : (
              <>
                {loadingDados && <p className="text-600 text-sm mb-3">Carregando dados complementares…</p>}
                <div className="field">
                  <label htmlFor="tnome2">Nome</label>
                  <InputText
                    id="tnome2"
                    value={nome}
                    onChange={(e) => setNome(e.target.value)}
                    className={classNames('w-full', { 'p-invalid': submitted && !nome.trim() })}
                  />
                  {submitted && !nome.trim() && <small className="p-invalid">Obrigatório.</small>}
                </div>
                <div className="field">
                  <label htmlFor="statusTenant">Situação</label>
                  <Dropdown
                    inputId="statusTenant"
                    value={active}
                    options={STATUS_TENANT_OPTS}
                    onChange={(e) => setActive(Boolean(e.value))}
                    optionLabel="label"
                    optionValue="value"
                    className="w-full"
                  />
                </div>
                <div className="field">
                  <label htmlFor="tplano2">Plano</label>
                  <Dropdown inputId="tplano2" value={plano} options={PLANO_OPTS} onChange={(e) => setPlano(e.value)} className="w-full" />
                </div>
                <div className="field">
                  <label htmlFor="tcontato2">Contato</label>
                  <InputText id="tcontato2" value={contato} onChange={(e) => setContato(e.target.value)} className="w-full" />
                </div>
                <fieldset className="border-round p-3 mt-3" style={{ border: '1px solid var(--surface-border)' }}>
                  <legend className="text-sm font-semibold px-2">Endereço (tenant_dados)</legend>
                  <div className="formgrid grid">
                    <div className="field col-12 md:col-3">
                      <label htmlFor="cep">CEP</label>
                      <InputText id="cep" value={dados.cep} onChange={(e) => setDados((p) => ({ ...p, cep: e.target.value }))} className="w-full" />
                    </div>
                    <div className="field col-12 md:col-9">
                      <label htmlFor="end">Logradouro</label>
                      <InputText id="end" value={dados.endereco} onChange={(e) => setDados((p) => ({ ...p, endereco: e.target.value }))} className="w-full" />
                    </div>
                    <div className="field col-12 md:col-4">
                      <label htmlFor="bairro">Bairro</label>
                      <InputText id="bairro" value={dados.bairro} onChange={(e) => setDados((p) => ({ ...p, bairro: e.target.value }))} className="w-full" />
                    </div>
                    <div className="field col-12 md:col-5">
                      <label htmlFor="cidade">Cidade</label>
                      <InputText id="cidade" value={dados.cidade} onChange={(e) => setDados((p) => ({ ...p, cidade: e.target.value }))} className="w-full" />
                    </div>
                    <div className="field col-12 md:col-3">
                      <label htmlFor="uf">UF</label>
                      <InputText id="uf" value={dados.estado} onChange={(e) => setDados((p) => ({ ...p, estado: e.target.value }))} className="w-full" maxLength={2} />
                    </div>
                  </div>
                </fieldset>
              </>
            )}
          </Dialog>

          <Dialog
            visible={userDialog}
            onHide={() => setUserDialog(false)}
            header={usuarioEdicao ? 'Editar usuário' : 'Novo usuário'}
            modal
            style={{ width: '420px' }}
            footer={
              <>
                <Button type="button" label="Cancelar" icon="pi pi-times" text onClick={() => setUserDialog(false)} />
                <Button type="button" label="Salvar" icon="pi pi-check" text onClick={() => void salvarUsuario()} />
              </>
            }
          >
            <div className="field">
              <label>Nome</label>
              <InputText value={usuarioNome} onChange={(e) => setUsuarioNome(e.target.value)} className="w-full" />
            </div>
            <div className="field">
              <label>E-mail</label>
              <InputText value={usuarioEmail} onChange={(e) => setUsuarioEmail(e.target.value)} className="w-full" />
            </div>
            <div className="field">
              <label>Perfil</label>
              <Dropdown
                value={usuarioRole}
                options={[
                  { label: 'Administrador', value: 'ADMIN' },
                  { label: 'Usuário', value: 'USER' },
                ]}
                onChange={(e) => setUsuarioRole(e.value)}
                className="w-full"
              />
            </div>
            {!usuarioEdicao && (
              <div className="field">
                <label>Senha inicial</label>
                <InputText type="password" value={usuarioSenha} onChange={(e) => setUsuarioSenha(e.target.value)} className="w-full" autoComplete="new-password" />
              </div>
            )}
          </Dialog>

          <Dialog
            visible={userDeleteOpen}
            onHide={() => setUserDeleteOpen(false)}
            header="Confirmar exclusão"
            modal
            footer={
              <>
                <Button type="button" label="Não" icon="pi pi-times" text onClick={() => setUserDeleteOpen(false)} />
                <Button type="button" label="Sim, desativar" icon="pi pi-check" text onClick={() => void excluirUsuario()} />
              </>
            }
          >
            {usuarioEdicao && (
              <span>
                Desativar o usuário <b>{usuarioEdicao.nome}</b>?
              </span>
            )}
          </Dialog>
        </div>
      </div>
    </div>
  );
}

export const getServerSideProps = canSSRAuth(async (ctx) => {
  const apiClient = setupAPIClient(ctx);
  try {
    await apiClient.get('/api/registro');
  } catch (err: unknown) {
    const ax = err as { response?: { status?: number; data?: { error?: string } } };
    const msg = ax?.response?.data?.error ?? '';
    if (ax?.response?.status === 400 && msg.includes('no rows in result set')) {
      // mesmo critério de outras páginas autenticadas
    } else {
      return { redirect: { destination: '/', permanent: false } };
    }
  }

  const { data } = await apiClient.get('/api/usuariorole');
  const role = data?.logado?.role;
  if (role !== 'SUPER') {
    return { redirect: { destination: '/', permanent: false } };
  }

  return { props: {} };
});
