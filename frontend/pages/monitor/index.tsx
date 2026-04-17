import { Button } from 'primereact/button';
import { Column } from 'primereact/column';
import { Dropdown } from 'primereact/dropdown';
import { InputText } from 'primereact/inputtext';
import { Toast } from 'primereact/toast';
import React, { useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { TreeTable, TreeTableExpandedKeysType } from 'primereact/treetable';
import MonitorOperacaoService from '../../services/cruds/MonitorOperacaoService';
import { Vec } from '../../types/types';

const fmtDetalhe = (d?: Record<string, unknown>) => {
  if (!d || typeof d !== 'object') {
    return '';
  }
  try {
    return JSON.stringify(d);
  } catch {
    return '';
  }
};

const MonitorPage = () => {
  const [itensFallback, setItensFallback] = useState<Vec.MonitorOperacaoItem[]>([]);
  const [totalRecordsFallback, setTotalRecordsFallback] = useState(0);
  const [first, setFirst] = useState(0);
  const [rows, setRows] = useState(25);
  const [clienteFiltro, setClienteFiltro] = useState('');
  const [statusFiltro, setStatusFiltro] = useState('');
  const [dataDeFiltro, setDataDeFiltro] = useState('');
  const [dataAteFiltro, setDataAteFiltro] = useState('');
  const [filtrosAplicados, setFiltrosAplicados] = useState({
    clienteNome: '',
    status: '',
    dataDe: '',
    dataAte: '',
  });
  const toast = useRef<Toast>(null);
  const [expandedKeys, setExpandedKeys] = useState<TreeTableExpandedKeysType>({});

  const load = async () => {
    const { itens: lista, total } = await MonitorOperacaoService().list(rows, first, filtrosAplicados);
    return {
      itens: lista ?? [],
      totalRecords: typeof total === 'number' ? total : 0,
    };
  };

  const { data, isFetching, refetch } = useQuery({
    queryKey: ['monitor-operacoes', rows, first, filtrosAplicados.clienteNome, filtrosAplicados.status, filtrosAplicados.dataDe, filtrosAplicados.dataAte],
    queryFn: async () => {
      try {
        const next = await load();
        setItensFallback(next.itens);
        setTotalRecordsFallback(next.totalRecords);
        return next;
      } catch (e: unknown) {
        const ax = e as { response?: { data?: { error?: string } } };
        toast.current?.show({
          severity: 'error',
          summary: 'Erro',
          detail: ax?.response?.data?.error ?? 'Falha ao carregar o monitor',
          life: 5000,
        });
        return { itens: [], totalRecords: 0 };
      }
    },
  });

  const paginatorLeft = (
    <Button
      type="button"
      icon="pi pi-refresh"
      tooltip="Atualizar"
      className="p-button-text"
      onClick={() => refetch()}
      loading={isFetching}
    />
  );

  const statusBody = (row: Vec.MonitorOperacaoItem) => (
    <span className={row.status === 'ERRO' ? 'text-red-500' : undefined}>{row.status}</span>
  );

  const toTreeNodes = (itens: Vec.MonitorOperacaoItem[]) => {
    return (itens ?? []).map((item) => {
      const filhos = (item.compromissos ?? []).map((c, idx) => ({
        key: `${item.id}-c-${c.compromisso_id ?? idx}`,
        data: {
          tipo_linha: 'filho',
          cliente_nome: c.cliente_nome ?? item.cliente_nome ?? '—',
          origem: 'COMPROMISSO',
          tipo: c.descricao ?? '',
          status: c.status ?? '',
          mensagem: `Competência ${c.competencia ?? '—'} | Vencimento ${c.vencimento ?? '—'}`,
          detalhe: { empresa_id: c.empresa_id, compromisso_id: c.compromisso_id, valor: c.valor },
          criado_em: item.criado_em,
        },
      }));
      return {
        key: item.id ?? Math.random().toString(),
        data: {
          ...item,
          tipo_linha: 'pai',
        },
        children: filhos,
      };
    });
  };

  const aplicarFiltros = () => {
    setFirst(0);
    setFiltrosAplicados({
      clienteNome: clienteFiltro.trim(),
      status: statusFiltro.trim(),
      dataDe: dataDeFiltro.trim(),
      dataAte: dataAteFiltro.trim(),
    });
  };

  const limparFiltros = () => {
    setClienteFiltro('');
    setStatusFiltro('');
    setDataDeFiltro('');
    setDataAteFiltro('');
    setFirst(0);
    setFiltrosAplicados({ clienteNome: '', status: '', dataDe: '', dataAte: '' });
  };

  return (
    <div className="grid">
      <div className="col-12">
        <div className="card">
          <h5>Monitor de operações</h5>
          <p className="text-color-secondary text-sm mb-3">
            Registros de geração de compromissos, agenda e execuções automáticas. Cada linha tem um tenant_id;
            SUPER vê todos os clientes; ADMIN vê apenas seus clientes.
          </p>
          <Toast ref={toast} />
          <div className="grid mb-3">
            <div className="col-12 md:col-3">
              <label className="block text-sm mb-2">Cliente</label>
              <InputText
                value={clienteFiltro}
                onChange={(e) => setClienteFiltro(e.target.value)}
                placeholder="Nome do cliente"
                className="w-full"
              />
            </div>
            <div className="col-12 md:col-3">
              <label className="block text-sm mb-2">Status</label>
              <Dropdown
                value={statusFiltro}
                onChange={(e) => setStatusFiltro(String(e.value ?? ''))}
                options={[
                  { label: 'Todos', value: '' },
                  { label: 'SUCESSO', value: 'SUCESSO' },
                  { label: 'ERRO', value: 'ERRO' },
                ]}
                placeholder="Selecione"
                className="w-full"
              />
            </div>
            <div className="col-12 md:col-2">
              <label className="block text-sm mb-2">Data inicial</label>
              <InputText
                type="date"
                value={dataDeFiltro}
                onChange={(e) => setDataDeFiltro(e.target.value)}
                className="w-full"
              />
            </div>
            <div className="col-12 md:col-2">
              <label className="block text-sm mb-2">Data final</label>
              <InputText
                type="date"
                value={dataAteFiltro}
                onChange={(e) => setDataAteFiltro(e.target.value)}
                className="w-full"
              />
            </div>
            <div className="col-12 md:col-2 flex align-items-end gap-2">
              <Button label="Filtrar" icon="pi pi-filter" onClick={aplicarFiltros} />
              <Button label="Limpar" outlined onClick={limparFiltros} />
            </div>
          </div>
          <TreeTable
            value={toTreeNodes(data?.itens ?? itensFallback)}
            loading={isFetching}
            paginator
            rows={rows}
            first={first}
            totalRecords={data?.totalRecords ?? totalRecordsFallback}
            lazy
            paginatorTemplate="FirstPageLink PrevPageLink PageLinks NextPageLink LastPageLink CurrentPageReport RowsPerPageDropdown"
            currentPageReportTemplate="{first} a {last} de {totalRecords}"
            rowsPerPageOptions={[10, 25, 50, 100]}
            paginatorLeft={paginatorLeft}
            onPage={(e) => {
              setFirst(e.first);
              setRows(e.rows);
            }}
            expandedKeys={expandedKeys}
            onToggle={(e) => setExpandedKeys(e.value)}
            emptyMessage="Nenhum registro"
          >
            <Column
              field="criado_em"
              expander
              header="Data"
              body={(node: { data: Vec.MonitorOperacaoItem & { tipo_linha?: string } }) =>
                node.data.criado_em ? new Date(node.data.criado_em).toLocaleString('pt-BR') : ''
              }
              style={{ minWidth: '10rem' }}
            />
            {/* <Column field="tenant_nome" header="Tenant" body={(r) => r.tenant_nome ?? r.tenant_id ?? '—'} /> */}
            <Column
              field="cliente_nome"
              header="Cliente"
              body={(node: { data: Vec.MonitorOperacaoItem & { tipo_linha?: string } }) => {
                const r = node.data;
                const empresaIDFallback =
                  r.detalhe && typeof r.detalhe.empresa_id === 'string'
                    ? r.detalhe.empresa_id
                    : '';
                return r.cliente_nome || empresaIDFallback || '—';
              }}
            />
            <Column field="origem" header="Origem" />
            <Column field="tipo" header="Tipo" style={{ minWidth: '12rem' }} />
            <Column
              field="status"
              header="Status"
              body={(node: { data: Vec.MonitorOperacaoItem }) => statusBody(node.data)}
            />
            <Column field="mensagem" header="Mensagem" style={{ minWidth: '14rem' }} />
            <Column
              header="Detalhe"
              body={(node: { data: Vec.MonitorOperacaoItem }) => (
                <span className="text-sm" style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
                  {fmtDetalhe(node.data.detalhe)}
                </span>
              )}
            />
          </TreeTable>
        </div>
      </div>
    </div>
  );
};

export default MonitorPage;
