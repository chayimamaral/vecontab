import { useQuery } from '@tanstack/react-query';
import { Button } from 'primereact/button';
import { Column } from 'primereact/column';
import { Dialog } from 'primereact/dialog';
import { Dropdown } from 'primereact/dropdown';
import { InputText } from 'primereact/inputtext';
import { Tooltip } from 'primereact/tooltip';
import { Toast } from 'primereact/toast';
import { TreeTable } from 'primereact/treetable';
import React, { useMemo, useRef, useState } from 'react';
import setupAPIClient from '../../components/api/api';
import { canSSRAuth } from '../../components/utils/canSSRAuth';
import EmpresaCompromissoService from '../../services/cruds/EmpresaCompromissoService';
import EmpresaService from '../../services/cruds/EmpresaService';
import RotinaService from '../../services/cruds/RotinaService';
import { Vec } from '../../types/types';

type EmpresaNodeData = {
  nodeType: 'empresa';
  empresa: Vec.Empresa;
};

type ProcessoNodeData = {
  nodeType: 'processo';
  empresa: Vec.Empresa;
  processo: Vec.EmpresaProcesso;
};

type NodeData = EmpresaNodeData | ProcessoNodeData;

const Empresas = ({ dados }) => {
  const tenantid = dados;
  const empresaService = EmpresaService();
  const empresaCompromissoService = EmpresaCompromissoService();
  const toast = useRef<Toast>(null);

  const [nomeFiltro, setNomeFiltro] = useState('');
  const [empresaFiltro, setEmpresaFiltro] = useState<string | null>(null);
  const [municipioFiltro, setMunicipioFiltro] = useState<string | null>(null);
  const [enquadramentoFiltro, setEnquadramentoFiltro] = useState<string | null>(null);
  const [empresaDialog, setEmpresaDialog] = useState(false);
  const [empresaSelecionada, setEmpresaSelecionada] = useState<Vec.Empresa | null>(null);
  const [processoTemplate, setProcessoTemplate] = useState<Vec.RotinaLite | null>(null);
  const [dataBaseGeracao, setDataBaseGeracao] = useState(() => new Date().toISOString().slice(0, 10));
  const [gerarCompromissosDialog, setGerarCompromissosDialog] = useState(false);
  const [processoSelecionado, setProcessoSelecionado] = useState<Vec.EmpresaProcesso | null>(null);
  const [expandedKeys, setExpandedKeys] = useState<Record<string, boolean>>({});

  const { data: empresasData, isFetching: loadingEmpresas, refetch: refetchEmpresas } = useQuery({
    queryKey: ['empresas-tree', tenantid, nomeFiltro],
    queryFn: async () => {
      const { data } = await empresaService.getEmpresas({
        lazyEvent: JSON.stringify({
          first: 0,
          rows: 500,
          page: 1,
          sortField: 'nome',
          sortOrder: 1,
          filters: { nome: { value: nomeFiltro, matchMode: 'contains' } },
          tenantid,
        }),
      });
      return data?.empresas ?? [];
    },
  });

  const { data: processosData, isFetching: loadingProcessos, refetch: refetchProcessos } = useQuery({
    queryKey: ['empresa-processos', tenantid],
    queryFn: async () => {
      const { data } = await empresaService.getEmpresaProcessos();
      return data?.processos ?? [];
    },
  });

  const { data: rotinasOptions = [], refetch: refetchRotinas } = useQuery<Vec.RotinaLite[]>({
    queryKey: ['rotinas-empresa-processo', empresaSelecionada?.id ?? '', empresaSelecionada?.municipio?.id ?? '', empresaSelecionada?.tipo_empresa?.id ?? ''],
    queryFn: async () => {
      const municipioId = (empresaSelecionada?.municipio?.id ?? '').trim();
      if (!municipioId) {
        return [];
      }
      const { data } = await RotinaService().getRotinasLite({ id: municipioId });
      const all = Array.isArray(data?.rotinas) ? data.rotinas : [];
      const tipoEmpresaID = (empresaSelecionada?.tipo_empresa?.id ?? '').trim();
      if (!tipoEmpresaID) {
        return all;
      }
      return all.filter((r: Vec.RotinaLite) => (r?.tipo_empresa?.id ?? '').trim() === tipoEmpresaID);
    },
    enabled: false,
    staleTime: 1000 * 60 * 5,
  });

  const processosByEmpresa = useMemo(() => {
    const map = new Map<string, Vec.EmpresaProcesso[]>();
    (processosData ?? []).forEach((p: Vec.EmpresaProcesso) => {
      const key = (p.empresa_id ?? '').trim();
      if (!key) {
        return;
      }
      if (!map.has(key)) {
        map.set(key, []);
      }
      map.get(key)!.push(p);
    });
    return map;
  }, [processosData]);

  const treeNodes = useMemo(() => {
    return (empresasData ?? []).map((empresa: Vec.Empresa) => {
      const children = (processosByEmpresa.get((empresa.id ?? '').trim()) ?? []).map((proc) => ({
        key: `proc-${proc.id}`,
        data: { nodeType: 'processo', empresa, processo: proc } as ProcessoNodeData,
      }));
      return {
        key: `emp-${empresa.id}`,
        data: { nodeType: 'empresa', empresa } as EmpresaNodeData,
        children,
      };
    });
  }, [empresasData, processosByEmpresa]);

  const treeNodesFiltrados = useMemo(() => {
    return treeNodes.filter((n) => {
      const d = n.data as EmpresaNodeData;
      const emp = d.empresa;
      if (empresaFiltro && (emp.nome ?? '') !== empresaFiltro) {
        return false;
      }
      if (municipioFiltro && (emp.municipio?.nome ?? '') !== municipioFiltro) {
        return false;
      }
      if (enquadramentoFiltro && (emp.tipo_empresa?.descricao ?? '') !== enquadramentoFiltro) {
        return false;
      }
      return true;
    });
  }, [treeNodes, empresaFiltro, municipioFiltro, enquadramentoFiltro]);

  const empresaOptions = useMemo(() => {
    const nomes = Array.from(new Set((empresasData ?? []).map((e: Vec.Empresa) => (e.nome ?? '').trim()).filter(Boolean)));
    return nomes.map((n) => ({ label: n, value: n }));
  }, [empresasData]);

  const municipioOptions = useMemo(() => {
    const nomes = Array.from(new Set((empresasData ?? []).map((e: Vec.Empresa) => (e.municipio?.nome ?? '').trim()).filter(Boolean)));
    return nomes.map((n) => ({ label: n, value: n }));
  }, [empresasData]);

  const enquadramentoOptions = useMemo(() => {
    const nomes = Array.from(new Set((empresasData ?? []).map((e: Vec.Empresa) => (e.tipo_empresa?.descricao ?? '').trim()).filter(Boolean)));
    return nomes.map((n) => ({ label: n, value: n }));
  }, [empresasData]);

  const onRefresh = () => {
    refetchEmpresas();
    refetchProcessos();
  };

  const onOpenNovoProcesso = (empresa: Vec.Empresa) => {
    setEmpresaSelecionada(empresa);
    setProcessoTemplate(null);
    setEmpresaDialog(true);
    refetchRotinas();
  };

  const onSalvarNovoProcesso = async () => {
    const empresaID = (empresaSelecionada?.id ?? '').trim();
    const rotinaID = (processoTemplate?.id ?? '').trim();
    const descricao = (processoTemplate?.descricao ?? '').trim();
    if (!empresaID) {
      toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Empresa inválida.', life: 3500 });
      return;
    }
    if (!rotinaID || !descricao) {
      toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Selecione o processo.', life: 3500 });
      return;
    }
    try {
      await empresaService.createEmpresaProcesso({
        empresa_id: empresaID,
        rotina: { id: rotinaID },
        descricao,
      });
      toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Novo processo criado.', life: 3000 });
      setEmpresaDialog(false);
      onRefresh();
    } catch (error) {
      toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Não foi possível criar o processo.', life: 4000 });
    }
  };

  const onIniciarProcessoFilho = async (empresa: Vec.Empresa, processo: Vec.EmpresaProcesso) => {
    try {
      await empresaService.iniciarEmpresaProcesso({
        empresa_id: (empresa.id ?? '').trim(),
        processo_id: (processo.id ?? '').trim(),
      });
      toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Processo iniciado.', life: 3000 });
      onRefresh();
    } catch {
      toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao iniciar processo.', life: 4000 });
    }
  };

  const onAbrirGerarCompromissos = (processo: Vec.EmpresaProcesso) => {
    setProcessoSelecionado(processo);
    setDataBaseGeracao(new Date().toISOString().slice(0, 10));
    setGerarCompromissosDialog(true);
  };

  const onConfirmarGerarCompromissos = async () => {
    const proc = processoSelecionado;
    if (!proc?.empresa_id) {
      toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Processo inválido.', life: 3500 });
      return;
    }
    try {
      await empresaCompromissoService.gerar({
        empresa_id: proc.empresa_id,
        data_inicio: (dataBaseGeracao || '').trim() || new Date().toISOString().slice(0, 10),
      });
      await empresaService.marcarCompromissosEmpresaProcesso({ processo_id: (proc.id ?? '').trim() });
      toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Compromissos gerados.', life: 3500 });
      setGerarCompromissosDialog(false);
      onRefresh();
    } catch {
      toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Falha ao gerar compromissos.', life: 4000 });
    }
  };

  const nomeBodyTemplate = (node) => {
    const data = node.data as NodeData;
    if (data.nodeType === 'empresa') {
      return <>{data.empresa.nome ?? '—'}</>;
    }
    const p = data.processo;
    const hint = p.compromissos_gerados
      ? 'Concluído'
      : p.iniciado
        ? 'Em andamento'
        : 'Não iniciado';
    return (
      <div className="flex flex-column">
        <span className="text-700">{p.descricao ?? 'Processo'}</span>
        <small className="text-500">{hint}</small>
      </div>
    );
  };

  const municipioBodyTemplate = (node) => {
    const data = node.data as NodeData;
    if (data.nodeType === 'empresa') {
      return data.empresa.municipio?.nome ?? '—';
    }
    return '—';
  };

  const tipoEmpresaBodyTemplate = (node) => {
    const data = node.data as NodeData;
    if (data.nodeType === 'empresa') {
      return data.empresa.tipo_empresa?.descricao ?? '—';
    }
    return '—';
  };

  const regimeBodyTemplate = (node) => {
    const data = node.data as NodeData;
    if (data.nodeType === 'empresa') {
      return data.empresa.regime_tributario?.nome ?? '—';
    }
    return '—';
  };

  const actionBodyTemplate = (node) => {
    const data = node.data as NodeData;
    if (data.nodeType === 'empresa') {
      return (
        <Button
          icon="pi pi-plus-circle"
          tooltip="Cria um novo processo para esta empresa"
          tooltipOptions={{ position: 'left' }}
          rounded
          severity="success"
          onClick={() => onOpenNovoProcesso(data.empresa)}
        />
      );
    }

    const iniciarDisabled = data.processo.iniciado === true;
    const gerarDisabled = data.processo.iniciado !== true || data.processo.compromissos_gerados === true;
    const iniciarHint = data.processo.compromissos_gerados
      ? 'Processo Concluido'
      : iniciarDisabled
        ? 'Processo já iniciado'
        : 'Inicia o processo selecionado';

    return (
      <>
        <span
          className="tt-iniciar-processo"
          data-pr-tooltip={iniciarHint}
          data-pr-position="left"
        >
          <Button
            icon="pi pi-play"
            tooltip={!iniciarDisabled ? 'Inicia o processo selecionado' : undefined}
            tooltipOptions={{ position: 'left' }}
            rounded
            severity="info"
            disabled={iniciarDisabled}
            onClick={() => onIniciarProcessoFilho(data.empresa, data.processo)}
          />
        </span>
        <span
          className="ml-2 tt-gerar-compromissos"
          data-pr-tooltip={gerarDisabled ? 'Disponível somente após iniciar e enquanto não gerado' : 'Gera compromissos do processo'}
          data-pr-position="left"
        >
          <Button
            icon="pi pi-check-circle"
            tooltip={!gerarDisabled ? 'Gera compromissos do processo' : undefined}
            tooltipOptions={{ position: 'left' }}
            rounded
            severity="help"
            disabled={gerarDisabled}
            onClick={() => onAbrirGerarCompromissos(data.processo)}
          />
        </span>
      </>
    );
  };

  const rowClassName = (node) => {
    const data = node.data as NodeData;
    if (data.nodeType !== 'empresa') {
      return '';
    }
    const children = node.children ?? [];
    const hasPendente = children.some((c) => !(c.data?.processo?.compromissos_gerados === true));
    return hasPendente ? 'empresa-processo-pendente-row' : '';
  };

  const dialogFooter = (
    <>
      <Button label="Cancelar" icon="pi pi-times" text onClick={() => setEmpresaDialog(false)} />
      <Button label="Salvar" icon="pi pi-check" text onClick={onSalvarNovoProcesso} />
    </>
  );

  const gerarCompromissosDialogFooter = (
    <>
      <Button label="Cancelar" icon="pi pi-times" text onClick={() => setGerarCompromissosDialog(false)} />
      <Button label="Gerar" icon="pi pi-check" text onClick={onConfirmarGerarCompromissos} />
    </>
  );

  return (
    <div className="grid crud-demo">
      <div className="col-12">
        <div className="card">
          <Toast ref={toast} />
          <Tooltip target=".tt-iniciar-processo" />
          <Tooltip target=".tt-gerar-compromissos" />
          <div className="mb-4">
            <p className="text-600 m-0 text-sm mb-3">
              Cadastro completo em <strong>Clientes</strong>. Aqui ficam os <strong>Processos</strong> por empresa.
            </p>
            <div
              className="empresa-filtros-grid"
              style={{
                display: 'grid',
                gridTemplateColumns: '1.2fr 1fr 1.5fr',
                gap: '1rem',
              }}
            >
              <div className="field mb-0 min-w-0">
                <label htmlFor="filtroEmpresa" className="text-sm text-600 mb-2 block">Empresa</label>
                <Dropdown
                  id="filtroEmpresa"
                  value={empresaFiltro}
                  options={empresaOptions}
                  onChange={(e) => setEmpresaFiltro((e.value as string | null) ?? null)}
                  placeholder="Todas"
                  showClear
                  className="w-full p-column-filter"
                  filter
                />
              </div>
              <div className="field mb-0 min-w-0">
                <label htmlFor="filtroMunicipio" className="text-sm text-600 mb-2 block">Municipio</label>
                <Dropdown
                  id="filtroMunicipio"
                  value={municipioFiltro}
                  options={municipioOptions}
                  onChange={(e) => setMunicipioFiltro((e.value as string | null) ?? null)}
                  placeholder="Todos"
                  showClear
                  className="w-full p-column-filter"
                  filter
                />
              </div>
              <div className="field mb-0 min-w-0">
                <label htmlFor="filtroEnquadramento" className="text-sm text-600 mb-2 block">Enquadramento Juridico</label>
                <Dropdown
                  id="filtroEnquadramento"
                  value={enquadramentoFiltro}
                  options={enquadramentoOptions}
                  onChange={(e) => setEnquadramentoFiltro((e.value as string | null) ?? null)}
                  placeholder="Todos"
                  showClear
                  className="w-full p-column-filter"
                  filter
                />
              </div>
            </div>
          </div>

          <div className="flex flex-column md:flex-row md:justify-content-between md:align-items-center mb-3">
            <div>
              <h5 className="m-0">Manutenção de Empresas</h5>
              <p className="m-0 mt-1 text-600 text-sm">Árvore de empresa e processos por fase.</p>
              <p className="m-0 mt-1 text-500 text-xs">Faixa principal: Novo Processo. Faixa filha: Iniciar Processo e Gerar Compromissos.</p>
            </div>
            <div className="flex align-items-center gap-2 mt-2 md:mt-0">
              <span className="p-input-icon-left">
                <i className="pi pi-search" />
                <InputText
                  type="search"
                  value={nomeFiltro}
                  onChange={(e) => setNomeFiltro(e.target.value)}
                  placeholder="Filtrar por nome..."
                />
              </span>
              <Button type="button" icon="pi pi-refresh" tooltip="Atualizar" className="p-button-text" onClick={onRefresh} />
            </div>
          </div>

          <TreeTable
            value={treeNodesFiltrados}
            expandedKeys={expandedKeys}
            onToggle={(e) => setExpandedKeys(e.value)}
            tableStyle={{ minWidth: '80rem' }}
            stripedRows
            loading={loadingEmpresas || loadingProcessos}
            rowClassName={rowClassName}
          >
            <Column field="nome" header="Nome (Empresa / Processo)" expander body={nomeBodyTemplate} style={{ width: '32%' }} />
            <Column field="municipio" header="Municipio" body={municipioBodyTemplate} style={{ width: '20%' }} />
            <Column field="tipo_empresa" header="Enquadramento Jurídico" body={tipoEmpresaBodyTemplate} style={{ width: '20%' }} />
            <Column field="regime" header="Regime Tributário" body={regimeBodyTemplate} style={{ width: '18%' }} />
            <Column header="Ações" body={actionBodyTemplate} style={{ width: '10%' }} />
          </TreeTable>

          <Dialog
            visible={empresaDialog}
            style={{ width: '36rem' }}
            header="Novo Processo"
            modal
            className="p-fluid"
            footer={dialogFooter}
            onHide={() => setEmpresaDialog(false)}
          >
            <p className="text-600 mt-0">
              Empresa: <strong>{empresaSelecionada?.nome ?? '—'}</strong>
            </p>
            <div className="field">
              <label htmlFor="processoTemplate">Processo</label>
              <Dropdown
                id="processoTemplate"
                value={processoTemplate}
                options={rotinasOptions}
                onChange={(e) => setProcessoTemplate(e.value as Vec.RotinaLite)}
                optionLabel="descricao"
                dataKey="id"
                placeholder="Selecione o processo"
                emptyMessage="Sem processos para município/enquadramento."
                className="w-full"
                filter
                filterBy="descricao"
              />
              <small className="text-600">Lista filtrada por município e enquadramento jurídico.</small>
            </div>
          </Dialog>

          <Dialog
            visible={gerarCompromissosDialog}
            style={{ width: '500px' }}
            header="Gerar Compromissos"
            modal
            className="p-fluid"
            footer={gerarCompromissosDialogFooter}
            onHide={() => setGerarCompromissosDialog(false)}
          >
            <p className="m-0 mb-2 text-600">
              Serão criados compromissos legais considerando dias úteis e postergação para o próximo dia útil quando aplicável.
            </p>
            <div className="field">
              <label htmlFor="dataBaseGeracao">Data base da geração</label>
              <input
                id="dataBaseGeracao"
                type="date"
                className="p-inputtext p-component w-full"
                value={dataBaseGeracao}
                onChange={(e) => setDataBaseGeracao(e.target.value)}
              />
            </div>
          </Dialog>
        </div>
      </div>
    </div>
  );
};

export default Empresas;

export const getServerSideProps = canSSRAuth(async (ctx) => {
  try {
    const apiClient = setupAPIClient(ctx);
    const response = await apiClient.get('/api/usuariotenant');

    return {

      props: {

        dados: response.data.tenantid,

      }
    };

  } catch (err) {
    console.log(err);

    return {
      redirect: {
        destination: '/',
        permanent: false
      }
    };
  }
});
