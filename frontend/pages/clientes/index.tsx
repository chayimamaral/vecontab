import { Button } from 'primereact/button';
import { Column } from 'primereact/column';
import { Chips } from 'primereact/chips';
import { DataTable, DataTableFilterMeta } from 'primereact/datatable';
import type { PaginatorTemplate } from 'primereact/paginator';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
import { InputNumber } from 'primereact/inputnumber';
import { InputTextarea } from 'primereact/inputtextarea';
import { ProgressSpinner } from 'primereact/progressspinner';
import { Toast } from 'primereact/toast';
import { Toolbar } from 'primereact/toolbar';
import { classNames } from 'primereact/utils';
import React, { useEffect, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { canSSRAuth } from '../../components/utils/canSSRAuth';
import setupAPIClient from '../../components/api/api';
import { Vec } from '../../types/types';

import { Dropdown } from 'primereact/dropdown';
import { TabView, TabPanel } from 'primereact/tabview';
import MunicipioService from '../../services/cruds/MunicipioService';
import CertificadoClienteService from '../../services/cruds/CertificadoClienteService';
import EmpresaService from '../../services/cruds/EmpresaService';
import EmpresaDadosService from '../../services/cruds/EmpresaDadosService';
import RegimeTributarioService from '../../services/cruds/RegimeTributarioService';
import TipoEmpresaService from '../../services/cruds/TipoEmpresaService';

interface LazyTableState {
  totalRecords: number;
  first: number;
  rows: number;
  page: number;
  sortField?: string;
  sortOrder?: number;
  filters: DataTableFilterMeta;
  tenantid: string;
}

type ClientesDataTablePageEvent = Parameters<
  NonNullable<React.ComponentProps<typeof DataTable<Vec.Empresa[]>>['onPage']>
>[0];
type ClientesDataTableSortEvent = Parameters<
  NonNullable<React.ComponentProps<typeof DataTable<Vec.Empresa[]>>['onSort']>
>[0];
type ClientesDataTableFilterEvent = Parameters<
  NonNullable<React.ComponentProps<typeof DataTable<Vec.Empresa[]>>['onFilter']>
>[0];
type ClientesChipsChangeEvent = Parameters<NonNullable<React.ComponentProps<typeof Chips>['onChange']>>[0];

type PaginatorPrevNextLinkOptions = {
  className: string;
  onClick: (e: React.SyntheticEvent) => void;
  disabled: boolean;
};
type PaginatorPageLinksOptions = {
  className: string;
  onClick: (e: React.SyntheticEvent) => void;
  page: number;
  view: { startPage: number; endPage: number };
  totalPages: number;
};
type PaginatorRowsPerPageOptions = {
  value: number;
  options: { label: number; value: number }[];
  onChange: (e: { value: number }) => void;
};
type PaginatorCurrentPageReportOptions = {
  totalPages: number;
  rows: number;
};

const Clientes = ({ dados }: { dados: string }) => {

  const tenantid = dados

  const tipoPessoaOptions = [
    { label: 'Pessoa jurídica (PJ)', value: 'PJ' },
    { label: 'Pessoa física (PF)', value: 'PF' },
  ];

  const tipoCertificadoOptions = [
    { label: 'A1', value: 'A1' },
    { label: 'A3', value: 'A3' },
  ];

  let emptyEmpresa: Vec.Empresa = {
    id: '',
    nome: '',
    tipo_pessoa: 'PJ',
    documento: '',
    cnpj: '',
    ie: '',
    im: '',
    razaosocial: '',
    fantasia: '',
    endereco: '',
    numero: '',
    complemento: '',
    bairro: '',
    municipio: {
      id: '',
      nome: ''
    },
    rotina: {
      id: '',
      descricao: ''
    },
    rotina_pf: {
      id: '',
      nome: '',
      categoria: ''
    },
    regime_tributario: {
      id: '',
      nome: '',
      codigo_crt: undefined,
    },
    tipo_empresa: {
      id: '',
      descricao: ''
    },
    uf: '',
    cep: '',
    tenantid: '',
    cnaes: [],
    iniciado: false,
    passos_concluidos: false,
    compromissos_gerados: false,
  };

  const [empresas, setEmpresas] = useState([]);

  const [municipios, setMunicipios] = useState<Vec.MunicipioLite[]>([]);

  type ClienteExtraForm = {
    logradouro: string;
    numero: string;
    cep: string;
    email_contato: string;
    telefone: string;
    telefone2: string;
    /** PJ; gravado em clientes_dados.capital_social */
    capital_social: number | null;
    data_abertura: string;
    data_encerramento: string;
    observacao: string;
  };

  const emptyClienteExtra: ClienteExtraForm = {
    logradouro: '',
    numero: '',
    cep: '',
    email_contato: '',
    telefone: '',
    telefone2: '',
    capital_social: null,
    data_abertura: '',
    data_encerramento: '',
    observacao: '',
  };

  const [clienteExtra, setClienteExtra] = useState<ClienteExtraForm>(emptyClienteExtra);

  type CertClienteForm = {
    tipo_certificado: string;
    senha_certificado: string;
    nome_certificado: string;
    emitido_para: string;
    emitido_por: string;
    validade_de: string;
    validade_ate: string;
  };
  const emptyCertCliente: CertClienteForm = {
    tipo_certificado: 'A1',
    senha_certificado: '',
    nome_certificado: '',
    emitido_para: '',
    emitido_por: '',
    validade_de: '',
    validade_ate: '',
  };
  const [certClienteForm, setCertClienteForm] = useState<CertClienteForm>(emptyCertCliente);
  const [certArquivo, setCertArquivo] = useState<File | null>(null);
  const certFileInputRef = useRef<HTMLInputElement>(null);

  const [empresaDialog, setEmpresaDialog] = useState(false);
  /** Navegação explícita das abas do cadastro (evita barra nativa do TabView comprimida no Dialog). */
  const [clienteDialogTabIndex, setClienteDialogTabIndex] = useState(0);
  const [deleteEmpresaDialog, setDeleteEmpresaDialog] = useState(false);
  const [empresa, setEmpresa] = useState<Vec.Empresa>(emptyEmpresa);
  const [submitted, setSubmitted] = useState(false);
  const [globalFilter, setGlobalFilter] = useState<string>('');
  const toast = useRef<Toast>(null);

  const [loading, setLoading] = useState<boolean>(false);
  const [first, setFirst] = useState(0);
  const [rows, setRows] = useState(20);
  const [currentPage, setCurrentPage] = useState(1);
  const [sortOrder, setSortOrder] = useState(1);
  const [sortField, setSortField] = useState('descricao');
  const paginatorRight = <Button type="button" icon="pi pi-cloud" className="p-button-text" />;
  const [pageInputTooltip, setPageInputTooltip] = useState('');
  const [value, setValue] = useState('');
  const [totalRecords, setTotalRecords] = useState<number>(0);
  const [logado, setLogado] = useState<boolean>(false);

  const [lazyState, setLazyState] = useState<LazyTableState>({
    totalRecords: totalRecords,
    first: first,
    rows: rows,
    page: currentPage,
    sortField: '',
    sortOrder: 1,
    filters: {
      nome: { value: '', matchMode: 'contains' }
    },
    tenantid: tenantid
  });

  const lazyStateRef = useRef(lazyState);
  lazyStateRef.current = lazyState;

  useEffect(() => {
    loadLazyMunicipios();
    loadLazyEmpresa();
  }, []);

  const {
    data: userRole = null,
    isLoading: userRoleLoading,
    isError: userRoleError,
    refetch: refetchUserRole,
  } = useQuery<string | null>({
    queryKey: ['user-role'],
    queryFn: async () => {
      const api = setupAPIClient(undefined);
      const r = await api.get('/api/usuariorole');
      const raw = r.data?.logado?.role;
      if (typeof raw !== 'string') {
        return null;
      }
      const norm = raw.trim().toUpperCase();
      return norm || null;
    },
    /** Nunca tratar perfil como "fresco" por minutos: null em cache bloqueava Ações até expirar staleTime global. */
    staleTime: 0,
    gcTime: 1000 * 60,
    retry: 2,
  });

  const empresaService = EmpresaService();
  const empresaDadosService = EmpresaDadosService();

  const podeCadastrarClientes = userRole === 'ADMIN' || userRole === 'SUPER';
  const podeEditarDadosComplementares = userRole === 'ADMIN' || userRole === 'USER' || userRole === 'SUPER';
  const podeEditarComplementosCliente = podeCadastrarClientes || podeEditarDadosComplementares;
  /** ADMIN/SUPER podem ajustar enquadramento jurídico e regime (CRT) mesmo com processo iniciado; USER só complementos. */
  const podeEditarEnquadramentoRegimePJ =
    (userRole === 'ADMIN' || userRole === 'SUPER') && !userRoleLoading && !userRoleError;
  /** Certificado por cliente: ADMIN do escritório e SUPER; USER não vê nem altera (EF-907). */
  const podeAnexarCertificadoCliente = userRole === 'ADMIN' || userRole === 'SUPER';
  const abaCertificadoClienteHabilitada = podeAnexarCertificadoCliente;

  const certClienteService = CertificadoClienteService();

  const {
    data: regimesTributariosOptions = [],
    isPending: regimesTributariosLoading,
    isError: regimesTributariosError,
  } = useQuery<Vec.RegimeTributario[]>({
    queryKey: ['regimes-tributarios', 'cliente-dropdown'],
    queryFn: async () => {
      const svc = RegimeTributarioService();
      const { data } = await svc.getRegimes({
        lazyEvent: JSON.stringify({
          first: 0,
          rows: 500,
          sortField: 'codigo_crt',
          sortOrder: 1,
          filters: { nome: { value: '', matchMode: 'contains' } },
        }),
      });
      return Array.isArray(data?.regimes) ? data.regimes : [];
    },
    /** Pré-carrega para inclusão e edição: ao abrir o Dialog, a lista já está disponível (evita painel vazio). */
    enabled: true,
    staleTime: 1000 * 60 * 5,
    retry: 2,
  });

  const { data: tiposEmpresaOptions = [] } = useQuery<Vec.TipoEmpresaLite[]>({
    queryKey: ['tiposempresa-lite', 'cliente-form'],
    queryFn: async () => {
      const { data } = await TipoEmpresaService().getTiposEmpresaLite();
      return Array.isArray(data?.tiposEmpresa) ? data.tiposEmpresa : [];
    },
    staleTime: 1000 * 60 * 5,
    retry: 2,
  });

  useEffect(() => {
    if (!empresaDialog || !regimesTributariosError) {
      return;
    }
    toast.current?.show({
      severity: 'warn',
      summary: 'Regimes tributários',
      detail: 'Não foi possível carregar a lista (GET /api/regimes-tributarios). Verifique o console de rede ou o cadastro em Regimes tributários.',
      life: 6000,
    });
  }, [empresaDialog, regimesTributariosError]);

  const {
    data: certClienteRemote,
    refetch: refetchCertCliente,
    isFetching: certClienteLoading,
  } = useQuery({
    queryKey: ['certificado-cliente', empresa.id],
    queryFn: async () => {
      const id = (empresa.id ?? '').trim();
      if (!id) {
        return {};
      }
      const { data } = await certClienteService.getByEmpresa(id);
      return data?.certificado ?? {};
    },
    enabled: empresaDialog && !!(empresa.id ?? '').trim() && abaCertificadoClienteHabilitada,
  });

  useEffect(() => {
    if (!empresaDialog || abaCertificadoClienteHabilitada) {
      return;
    }
    if (clienteDialogTabIndex === 2) {
      setClienteDialogTabIndex(0);
    }
  }, [empresaDialog, abaCertificadoClienteHabilitada, clienteDialogTabIndex]);

  useEffect(() => {
    if (!empresaDialog || !certClienteRemote) {
      return;
    }
    const data = certClienteRemote as Record<string, unknown>;
    setCertClienteForm((prev) => ({
      ...prev,
      tipo_certificado: typeof data.tipo_certificado === 'string' ? data.tipo_certificado : 'A1',
      senha_certificado: '',
      nome_certificado: typeof data.nome_certificado === 'string' ? data.nome_certificado : '',
      emitido_para: typeof data.emitido_para === 'string' ? data.emitido_para : '',
      emitido_por: typeof data.emitido_por === 'string' ? data.emitido_por : '',
      validade_de: typeof data.validade_de === 'string' ? data.validade_de : '',
      validade_ate: typeof data.validade_ate === 'string' ? data.validade_ate : '',
    }));
  }, [certClienteRemote, empresaDialog]);

  const fetchEmpresasPayload = (payload: LazyTableState) => {
    setLoading(true);
    const body = { ...payload, tenantid };
    empresaService
      .getEmpresas({ lazyEvent: JSON.stringify(body) })
      .then(({ data }) => {
        setEmpresas(data.empresas);
        setTotalRecords(data.totalRecords);
      })
      .catch(() => {
        toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao carregar as Empresas', life: 3000 });
      })
      .finally(() => setLoading(false));
  };

  const loadLazyEmpresa = () => {
    const next: LazyTableState = { ...lazyStateRef.current, tenantid };
    setLazyState(next);
    fetchEmpresasPayload(next);
  };

  async function handleCnaesChange(event: ClientesChipsChangeEvent): Promise<void> {
    const value: string[] = Array.isArray(event.value) ? [...event.value] : [];

    let prevLen = 0;
    setEmpresa((prev) => {
      prevLen = Array.isArray(prev.cnaes) ? prev.cnaes.length : 0;
      return { ...prev, cnaes: value };
    });

    if (value.length === 0 || value.length <= prevLen) {
      return;
    }

    const last = value[value.length - 1];
    const isValid = await validaCnae(last);
    if (!isValid) {
      setEmpresa((prev) => ({ ...prev, cnaes: value.slice(0, -1) }));
    }
  }

  const loadLazyMunicipios = () => {
    const municipioService = MunicipioService();
    municipioService.getMunicipiosLite().then(({ data }) => {
      setMunicipios(data?.municipios);
    })
  }

  const paginatorLeft = <Button type="button" icon="pi pi-refresh" tooltip='Atualizar' className="p-button-text" onClick={loadLazyEmpresa} />;

  const onPage = (event: ClientesDataTablePageEvent) => {
    setFirst(event.first);
    setRows(event.rows);
    const pageIndex = (event.page ?? 0) + 1;
    setCurrentPage(pageIndex);
    setSortOrder(event.sortOrder ?? 1);
    setSortField(event.sortField ?? '');
    const prev = lazyStateRef.current;
    const next: LazyTableState = {
      ...prev,
      tenantid,
      first: event.first,
      rows: event.rows,
      page: pageIndex,
      sortField: event.sortField ?? prev.sortField,
      sortOrder: event.sortOrder ?? prev.sortOrder,
      filters: event.filters ?? prev.filters,
    };
    setLazyState(next);
    fetchEmpresasPayload(next);
  };

  //const onPageInputKeyDown = (event: React.KeyboardEvent<HTMLInputElement>, options: { totalPages: number; rows: React.SetStateAction<number>; first: React.SetStateAction<number>; }) => {
  const onPageInputKeyDown = (
    event: React.KeyboardEvent<HTMLInputElement>,
    options: PaginatorCurrentPageReportOptions,
  ) => {
    if (event.key === 'Enter') {
      const page = currentPage;
      if (page < 1 || page > options.totalPages) {
        setPageInputTooltip(`Valor deve estar entre 1 e ${options.totalPages}.`);
      }
      else {
        const pageNum = typeof page === 'number' ? page : parseInt(String(page), 10);
        const firstIdx = options.rows * (pageNum - 1);

        setFirst(firstIdx);
        setRows(options.rows);
        setCurrentPage(pageNum);
        const prev = lazyStateRef.current;
        const next: LazyTableState = {
          ...prev,
          tenantid,
          first: firstIdx,
          rows: options.rows,
          page: pageNum,
        };
        setLazyState(next);
        fetchEmpresasPayload(next);
      }
    }

  }

  const onPageInputChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    setCurrentPage(event.target.value as unknown as number);
  };

  const onSort = (event: ClientesDataTableSortEvent) => {
    const prev = lazyStateRef.current;
    const next: LazyTableState = {
      ...prev,
      tenantid,
      sortField: event.sortField ?? prev.sortField,
      sortOrder: event.sortOrder ?? prev.sortOrder,
      filters: event.filters ?? prev.filters,
      first: event.first ?? prev.first,
    };
    setLazyState(next);
    fetchEmpresasPayload(next);
  };

  const onFilter = (event: ClientesDataTableFilterEvent) => {
    const prev = lazyStateRef.current;
    const next: LazyTableState = {
      ...prev,
      tenantid,
      first: 0,
      page: 1,
      filters: event.filters ?? prev.filters,
      rows: event.rows ?? prev.rows,
      sortField: event.sortField ?? prev.sortField,
      sortOrder: event.sortOrder ?? prev.sortOrder,
    };
    setFirst(0);
    setCurrentPage(1);
    setLazyState(next);
    fetchEmpresasPayload(next);
  };

  const openNew = () => {
    setEmpresa(emptyEmpresa);
    setClienteExtra(emptyClienteExtra);
    setCertClienteForm(emptyCertCliente);
    setCertArquivo(null);
    if (certFileInputRef.current) {
      certFileInputRef.current.value = '';
    }
    setSubmitted(false);
    setClienteDialogTabIndex(0);
    setEmpresaDialog(true);
  };

  const hideDialog = () => {
    setSubmitted(false);
    setEmpresaDialog(false);
    setClienteDialogTabIndex(0);
    setClienteExtra(emptyClienteExtra);
    setCertClienteForm(emptyCertCliente);
    setCertArquivo(null);
    if (certFileInputRef.current) {
      certFileInputRef.current.value = '';
    }
  };

  const hideDeleteEmpresaDialog = () => {
    setDeleteEmpresaDialog(false);
  };

  function handleBuscaEmpresa(event: React.KeyboardEvent<HTMLInputElement>, value: string): void {
    if (event.key === 'Enter') {
      const prev = lazyStateRef.current;
      const next: LazyTableState = {
        ...prev,
        tenantid,
        first: 0,
        page: 1,
        filters: { nome: { value: value.trim(), matchMode: 'contains' } },
      };
      setFirst(0);
      setCurrentPage(1);
      setLazyState(next);
      fetchEmpresasPayload(next);
    }
  }

  function handleClear(e: React.ChangeEvent<HTMLInputElement>): void {
    if (!e.target.value) {
      const prev = lazyStateRef.current;
      const next: LazyTableState = {
        ...prev,
        tenantid,
        first: 0,
        page: 1,
        filters: { nome: { value: '', matchMode: 'contains' } },
      };
      setFirst(0);
      setCurrentPage(1);
      setLazyState(next);
      fetchEmpresasPayload(next);
    }
  }

  const isClientePF = (empresa.tipo_pessoa ?? 'PJ') === 'PF';

  const coreCamposBloqueados =
    empresa?.iniciado === true || (!podeCadastrarClientes && podeEditarDadosComplementares);

  /** PrimeReact Dropdown: objeto da lista `options`. */
  const municipioFormDropdownValue = (() => {
    const id = (empresa.municipio?.id ?? '').trim();
    if (!id) {
      return null;
    }
    const fromList = municipios.find((m) => (m.id ?? '').trim() === id);
    if (fromList) {
      return fromList;
    }
    return { id: empresa.municipio.id, nome: empresa.municipio.nome ?? '' };
  })();

  const regimeTributarioFormDropdownValue = (() => {
    const id = (empresa.regime_tributario?.id ?? '').trim();
    if (!id) {
      return null;
    }
    const fromList = regimesTributariosOptions.find((r) => (r.id ?? '').trim() === id);
    if (fromList) {
      return fromList;
    }
    return {
      id: empresa.regime_tributario?.id ?? '',
      nome: empresa.regime_tributario?.nome ?? '',
      codigo_crt: empresa.regime_tributario?.codigo_crt,
    } as Vec.RegimeTributario;
  })();

  const tipoEmpresaFormDropdownValue = (() => {
    const id = (empresa.tipo_empresa?.id ?? '').trim();
    if (!id) {
      return null;
    }
    const fromList = tiposEmpresaOptions.find((t) => (t.id ?? '').trim() === id);
    if (fromList) {
      return fromList;
    }
    return {
      id: empresa.tipo_empresa?.id ?? '',
      descricao: empresa.tipo_empresa?.descricao ?? '',
    } as Vec.TipoEmpresaLite;
  })();

  const onlyDigits = (s: string) => String(s ?? '').replace(/\D/g, '');

  const buildPayloadDados = (empresaId: string) => {
    const pf = (empresa.tipo_pessoa ?? 'PJ').toUpperCase() === 'PF';
    return {
      id: empresaId,
      municipio_id: (empresa.municipio?.id ?? '').trim(),
      bairro: (empresa.bairro ?? '').trim(),
      cnpj: '',
      endereco: clienteExtra.logradouro.trim(),
      numero: clienteExtra.numero.trim(),
      cep: onlyDigits(clienteExtra.cep),
      email_contato: clienteExtra.email_contato.trim(),
      telefone: clienteExtra.telefone.trim(),
      telefone2: clienteExtra.telefone2.trim(),
      capital_social: pf ? null : (clienteExtra.capital_social ?? null),
      data_abertura: clienteExtra.data_abertura.trim(),
      data_encerramento: clienteExtra.data_encerramento.trim(),
      observacao: clienteExtra.observacao.trim(),
    };
  };

  const saveEmpresa = (event: any) => {
    setSubmitted(true);

    const docDigits = onlyDigits(empresa.documento ?? '');
    const munOk = (empresa.municipio?.id ?? '').trim() !== '';
    const docOkPf = isClientePF && docDigits.length === 11;
    const docOkPj = !isClientePF && (docDigits.length === 0 || docDigits.length === 14);
    /** Somente USER grava só clientes_dados; ADMIN/SUPER sempre passam por update do cliente (inclui regime/tipo) + dados. */
    const salvarSomenteClientesDados = !!empresa.id && podeEditarComplementosCliente && userRole === 'USER';

    if (salvarSomenteClientesDados) {
      if (!munOk) {
        toast.current?.show({ severity: 'warn', summary: 'Alerta', detail: 'Selecione o município.', life: 3500 });
        setSubmitted(false);
        return;
      }
      empresaDadosService
        .save(buildPayloadDados(empresa.id!))
        .then(() => {
          toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Dados do cliente atualizados', life: 3000 });
        })
        .catch((err) => {
          const msg = err?.response?.data?.error ?? 'Erro ao gravar';
          toast.current?.show({ severity: 'error', summary: 'Erro', detail: String(msg), life: 4500 });
        })
        .finally(() => {
          setEmpresaDialog(false);
          setEmpresa(emptyEmpresa);
          setClienteExtra(emptyClienteExtra);
          loadLazyEmpresa();
        });
      setSubmitted(false);
      return;
    }

    const canSave =
      !!empresa?.nome?.trim() &&
      munOk &&
      (isClientePF ? docOkPf : docOkPj);

    if (canSave) {
      const eid = (empresa.id ?? '').trim();
      const _empresa = {
        ...empresa,
        id: eid,
        tenantid,
        tipo_pessoa: isClientePF ? 'PF' : 'PJ',
        municipio: { id: (empresa.municipio?.id ?? '').trim() },
        rotina: { id: (empresa.rotina?.id ?? '').trim() },
        ie: isClientePF ? '' : (empresa.ie ?? ''),
        im: isClientePF ? '' : (empresa.im ?? ''),
        regime_tributario: isClientePF
          ? { id: '' }
          : { id: (empresa.regime_tributario?.id ?? '').trim() },
        tipo_empresa: isClientePF ? { id: '' } : { id: (empresa.tipo_empresa?.id ?? '').trim() },
        rotina_pf: {
          id: (empresa.rotina_pf?.id ?? '').trim(),
        },
        cnaes: Array.isArray(empresa.cnaes) ? [...empresa.cnaes] : [],
      };

      const afterEmpresaOk = (id: string) => {
        empresaDadosService
          .save(buildPayloadDados(id))
          .then(() => {
            toast.current?.show({
              severity: 'success',
              summary: 'Sucesso',
              detail: empresa.id ? 'Cliente atualizado' : 'Cliente criado',
              life: 3000,
            });
          })
          .catch((err) => {
            const msg = err?.response?.data?.error ?? 'Cliente salvo, mas falhou ao gravar endereço/contatos';
            toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: String(msg), life: 5000 });
          })
          .finally(() => {
            setEmpresaDialog(false);
            setEmpresa(emptyEmpresa);
            setClienteExtra(emptyClienteExtra);
            loadLazyEmpresa();
          });
      };

      if (eid) {
        empresaService
          .updateEmpresa(_empresa)
          .then(() => afterEmpresaOk(eid))
          .catch((error: unknown) => {
            const ax = error as { response?: { data?: { error?: string } } };
            const msg = ax?.response?.data?.error ?? (error instanceof Error ? error.message : null) ?? 'Erro ao atualizar o cliente';
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: String(msg), life: 6000 });
            setSubmitted(false);
          });
      } else {
        empresaService
          .createEmpresa(_empresa)
          .then((res) => {
            const nid = res?.data?.empresas?.[0]?.id;
            if (nid) {
              afterEmpresaOk(nid);
            } else {
              toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Resposta sem id do cliente', life: 4000 });
              loadLazyEmpresa();
            }
          })
          .catch(() => {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao criar o cliente', life: 3000 });
            setSubmitted(false);
          });
      }
    } else {
      if (!empresa?.nome?.trim()) {
        toast.current?.show({ severity: 'warn', summary: 'Alerta', detail: 'Preencha o nome do cliente', life: 3000 });
      }
      if (!munOk) {
        toast.current?.show({ severity: 'warn', summary: 'Alerta', detail: 'Selecione o município', life: 3000 });
      }
      if (isClientePF && !docOkPf) {
        toast.current?.show({
          severity: 'warn',
          summary: 'Alerta',
          detail: 'CPF deve ter 11 dígitos (apenas números ou formatado)',
          life: 3500,
        });
      }
      if (!isClientePF && !docOkPj) {
        toast.current?.show({
          severity: 'warn',
          summary: 'Alerta',
          detail: 'CNPJ, se informado, deve ter 14 dígitos',
          life: 3500,
        });
      }
    }
    setSubmitted(false);
  };

  const editEmpresa = (row: Vec.Empresa) => {
    setClienteDialogTabIndex(0);
    setCertClienteForm(emptyCertCliente);
    setCertArquivo(null);
    if (certFileInputRef.current) {
      certFileInputRef.current.value = '';
    }
    const rawCnaes = row.cnaes as unknown;
    const cnaesArr = Array.isArray(rawCnaes)
      ? rawCnaes.map((c) => String(c).replace(/\D/g, '')).filter(Boolean)
      : [];
    setClienteExtra(emptyClienteExtra);
    setEmpresa({
      ...row,
      municipio: row.municipio ?? { id: '', nome: '' },
      rotina: row.rotina,
      rotina_pf: row.rotina_pf ?? { id: '', nome: '', categoria: '' },
      regime_tributario: row.regime_tributario?.id
        ? {
            id: row.regime_tributario.id,
            nome: row.regime_tributario.nome ?? '',
            codigo_crt: row.regime_tributario.codigo_crt,
          }
        : { id: '', nome: '', codigo_crt: undefined },
      ie: row.ie ?? '',
      im: row.im ?? '',
      bairro: row.bairro ?? '',
      cnaes: cnaesArr,
      tipo_pessoa: (row.tipo_pessoa ?? 'PJ').toUpperCase() === 'PF' ? 'PF' : 'PJ',
      documento: row.documento ?? '',
    });
    setEmpresaDialog(true);

    if (row.id) {
      empresaDadosService.getByEmpresa(row.id).then(({ data }) => {
        const cap = data?.capital_social;
        setClienteExtra({
          logradouro: data?.endereco ?? '',
          numero: data?.numero ?? '',
          cep: data?.cep ?? '',
          email_contato: data?.email_contato ?? '',
          telefone: data?.telefone ?? '',
          telefone2: data?.telefone2 ?? '',
          capital_social: typeof cap === 'number' && !Number.isNaN(cap) ? cap : null,
          data_abertura: data?.data_abertura ?? '',
          data_encerramento: data?.data_encerramento ?? '',
          observacao: data?.observacao ?? '',
        });
        const m = data?.municipio;
        if (m?.id) {
          setEmpresa((prev) => ({
            ...prev,
            municipio: { id: m.id, nome: m.nome ?? '' },
          }));
        }
      }).catch(() => { /* sem linha clientes_dados */ });
    }
  };

  const confirmDeleteEmpresa = (empresa: Vec.Empresa) => {
    setEmpresa(empresa);
    setDeleteEmpresaDialog(true);
  };

  const deleteEmpresa = (event: any) => {
    setSubmitted(true);

    if (empresa?.nome?.trim()) {
      let _empresa = { ...empresa };

      if (empresa.id) {
        empresaService.deleteEmpresa(_empresa)
          .then(() => {
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Cliente excluído', life: 3000 });
          })
          .catch((error) => {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao excluir o cliente', life: 5000 });
          })
          .finally(() => {
            setDeleteEmpresaDialog(false);
            setEmpresa(emptyEmpresa);
            loadLazyEmpresa();
          });
      }
    }
  };

  const onInputChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>,
    campo: keyof Vec.Empresa,
  ) => {
    const val = e.target?.value ?? '';
    setEmpresa((prev) => ({ ...prev, [campo]: val }));
  };

  function onTipoPessoaChange(value: string) {
    const v = value === 'PF' ? 'PF' : 'PJ';
    if (v === 'PF') {
      setEmpresa((prev) => ({
        ...prev,
        tipo_pessoa: 'PF',
        rotina: { id: '', descricao: '' },
        rotina_pf: { id: '', nome: '', categoria: '' },
        regime_tributario: { id: '', nome: '', codigo_crt: undefined },
        ie: '',
        im: '',
        tipo_empresa: { id: '', descricao: '' },
        cnaes: [],
      }));
      return;
    }
    setEmpresa((prev) => ({
      ...prev,
      tipo_pessoa: 'PJ' as const,
      rotina_pf: { id: '', nome: '', categoria: '' },
    }));
  }

  function onMunicipioClienteChange(m: Vec.MunicipioLite | null): void {
    const muni = m?.id ? { id: m.id, nome: m.nome ?? '' } : { id: '', nome: '' };
    setEmpresa((prev) => ({ ...prev, municipio: muni }));
  }

  async function validaCnae(cnae: string): Promise<boolean> {
    const empresaService = EmpresaService();
    try {
      const data = await empresaService.validaCnae(cnae);
      return data.data.cnaeValido;
    } catch (error) {
      toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao validar o CNAE', life: 3000 });
      return false;
    }
  }

  function onValidadeCertClienteChange(value: string) {
    if (!value) {
      setCertClienteForm((prev) => ({ ...prev, validade_de: '', validade_ate: '' }));
      return;
    }
    const inicio = new Date(`${value}T00:00:00`);
    if (Number.isNaN(inicio.getTime())) {
      setCertClienteForm((prev) => ({ ...prev, validade_de: value }));
      return;
    }
    const fim = new Date(inicio);
    fim.setFullYear(fim.getFullYear() + 1);
    const fimISO = fim.toISOString().slice(0, 10);
    setCertClienteForm((prev) => ({
      ...prev,
      validade_de: value,
      validade_ate: fimISO,
    }));
  }

  async function saveCertificadoCliente() {
    const eid = (empresa.id ?? '').trim();
    if (!eid) {
      toast.current?.show({
        severity: 'warn',
        summary: 'Atenção',
        detail: 'Grave o cliente antes de anexar o certificado.',
        life: 4000,
      });
      return;
    }
    if (!certArquivo) {
      toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Selecione o arquivo .pfx.', life: 3500 });
      return;
    }
    if (!certClienteForm.senha_certificado.trim()) {
      toast.current?.show({
        severity: 'warn',
        summary: 'Atenção',
        detail: 'Informe a senha do certificado digital.',
        life: 4000,
      });
      return;
    }
    try {
      await certClienteService.upload({
        empresaId: eid,
        arquivo: certArquivo,
        senha_certificado: certClienteForm.senha_certificado,
        titular_nome: certClienteForm.emitido_para.trim() ? certClienteForm.emitido_para.trim() : undefined,
      });
      toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Certificado do cliente atualizado', life: 3000 });
      setCertArquivo(null);
      setCertClienteForm((c) => ({ ...c, senha_certificado: '' }));
      if (certFileInputRef.current) {
        certFileInputRef.current.value = '';
      }
      await refetchCertCliente();
    } catch (e: unknown) {
      const err = e as { response?: { data?: { error?: string; message?: string } } };
      const msg = err?.response?.data?.error || err?.response?.data?.message || 'Falha ao enviar certificado';
      toast.current?.show({ severity: 'error', summary: 'Erro', detail: String(msg), life: 7000 });
    }
  }

  const leftToolbarTemplate = () => {
    if (!podeCadastrarClientes) {
      return (
        <p className="text-600 m-0 text-sm">
          Cadastro completo (inclui endereço e contatos) na edição do cliente. Criar, alterar e excluir clientes é restrito a administradores; usuários do escritório podem ajustar município e contatos. Processo e compromissos em{' '}
          <strong>Manutenção de Empresas</strong>.
        </p>
      );
    }
    return (
      <div className="my-2">
        <Button label="Novo cliente" icon="pi pi-plus" severity="success" className="mr-2" onClick={openNew} />
      </div>
    );
  };

  const nomeBodyTemplate = (rowData: Vec.Empresa) => {
    return (
      <>
        <span className="p-column-title">Nome</span>
        {rowData.nome}
      </>
    );
  };

  const municipioBodyTemplate = (rowData: Vec.Empresa) => {
    const n = rowData.municipio?.nome?.trim();
    return (
      <>
        <span className="p-column-title">Município</span>
        {n ? n : '—'}
      </>
    );
  };

  const tipoEmpresaBodyTemplate = (rowData: Vec.Empresa) => {
    return (
      <>
        <span className="p-column-title">Enquadramento Jurídico</span>
        {rowData.tipo_empresa?.descricao ?? '—'}
      </>
    );
  };

  const regimeTributarioBodyTemplate = (rowData: Vec.Empresa) => {
    const r = rowData.regime_tributario;
    const nome = (r?.nome ?? '').trim();
    const crt = r?.codigo_crt;
    const crtTxt = crt !== undefined && crt !== null && Number(crt) > 0 ? ` (CRT ${crt})` : '';
    return (
      <>
        <span className="p-column-title">Regime tributário</span>
        {nome ? `${nome}${crtTxt}` : '—'}
      </>
    );
  };

  const template = {
    layout: 'PrevPageLink PageLinks NextPageLink RowsPerPageDropdown CurrentPageReport',
    'PrevPageLink': (options: PaginatorPrevNextLinkOptions) => {
      return (
        <button type="button" className={options.className} onClick={options.onClick} disabled={options.disabled}>
          <span className="p-3">Página anterior</span>
        </button>
      )
    },
    'NextPageLink': (options: PaginatorPrevNextLinkOptions) => {
      return (
        <button type="button" className={options.className} onClick={options.onClick} disabled={options.disabled}>
          <span className="p-3">Próxima página</span>
        </button>
      )
    },
    'PageLinks': (options: PaginatorPageLinksOptions) => {
      if ((options.view.startPage === options.page && options.view.startPage !== 0) || (options.view.endPage === options.page && options.page + 1 !== options.totalPages)) {
        const className = classNames(options.className, { 'p-disabled': true });

        return <span className={className} style={{ userSelect: 'none' }}>...</span>;
      }

      return (
        <button type="button" className={options.className} onClick={options.onClick}>
          {options.page + 1}
        </button>
      )
    },
    'RowsPerPageDropdown': (options: PaginatorRowsPerPageOptions) => {
      const dropdownOptions = [
        { label: 10, value: 10 },
        { label: 20, value: 20 },
        { label: 50, value: 50 }
      ];

      return <Dropdown value={options.value} options={dropdownOptions} onChange={options.onChange} />;
    },
    'CurrentPageReport': (options: PaginatorCurrentPageReportOptions) => {
      return (
        <span className="mx-3" style={{ color: 'var(--text-color)', userSelect: 'none' }}>
          Página <InputText className="ml-1" value={currentPage.toString()} tooltip={pageInputTooltip} tooltipOptions={{ position: 'left' }}
            onKeyDown={(e) => onPageInputKeyDown(e, options)} onChange={onPageInputChange} />
        </span>
      )
    }
  };

  const actionBodyTemplate = (rowData: Vec.Empresa) => {
    if (userRoleLoading) {
      return <ProgressSpinner style={{ width: '1.35rem', height: '1.35rem' }} />;
    }
    if (userRoleError) {
      return (
        <span className="text-500 text-sm ml-1 inline-flex align-items-center gap-2 flex-wrap">
          Não foi possível verificar o perfil.
          <Button type="button" label="Tentar" className="p-button-text p-0" onClick={() => void refetchUserRole()} />
        </span>
      );
    }
    const podeEditarLinha = podeCadastrarClientes || podeEditarDadosComplementares;
    return (
      <>
        {podeEditarLinha ? (
          <>
            <Button
              icon="pi pi-pencil"
              tooltip={podeCadastrarClientes ? 'Alterar' : 'Alterar contatos e município'}
              tooltipOptions={{ position: 'left' }}
              rounded
              severity="success"
              className="mr-2"
              onClick={() => editEmpresa(rowData)}
            />
            {podeCadastrarClientes && (
              <Button icon="pi pi-trash" tooltip='Excluir' tooltipOptions={{ position: 'left' }} rounded severity="warning" onClick={() => confirmDeleteEmpresa(rowData)} />
            )}
          </>
        ) : (
          <span className="text-500 text-sm ml-1">Sem permissão para editar</span>
        )}
      </>
    );
  };

  const header = (
    <div className="flex flex-column md:flex-row md:justify-content-between md:align-items-center">
      <div>
        <h5 className="m-0">Cadastro de Clientes</h5>
        <p className="m-0 mt-1 text-600 text-sm">Cadastro unificado: município, CNAEs, CPF/CNPJ, IE/IM/regime (PJ), endereço e contatos. Processos PF/municipais e fases na Manutenção de Empresas.</p>
      </div>
      <span className="block mt-2 md:mt-0 p-input-icon-left">
        <i className="pi pi-search" />
        <InputText type="search" onKeyDown={(e) => handleBuscaEmpresa(e, e.currentTarget.value)} onChange={handleClear} placeholder="Procurar por nome..." tooltip='Digite o nome e tecle Enter' tooltipOptions={{ position: 'left' }} />
      </span>
    </div>
  );

  const empresaDialogFooter = (
    <>
      <Button label="Cancelar" icon="pi pi-times" text onClick={hideDialog} />
      <Button label="Salvar" icon="pi pi-check" text onClick={saveEmpresa} />
    </>
  );

  const deleteEmpresaDialogFooter = (
    <>
      <Button label="Não" icon="pi pi-times" text onClick={hideDeleteEmpresaDialog} />
      <Button label="Sim" icon="pi pi-check" text onClick={deleteEmpresa} />
    </>
  );

  return (
    <div className="grid crud-demo" >
      <div className="col-12">
        <div className="card">
          <Toast ref={toast} />
          <Toolbar className="mb-4" left={leftToolbarTemplate} ></Toolbar>

          <DataTable
            value={empresas}
            lazy
            dataKey="id"
            paginator
            rows={rows}
            rowsPerPageOptions={[10, 20, 30]}
            className="datatable-responsive"
            paginatorTemplate={template as unknown as PaginatorTemplate}
            globalFilter={globalFilter}
            emptyMessage="Nenhum cliente encontrado."
            header={header}
            size="small"
            stripedRows
            filterDisplay='row'
            first={lazyState.first}
            onPage={onPage}
            onSort={onSort}
            sortField={lazyState.sortField}
            //atenção para o padrão abaixo...sempre tem que ser assim senão não funciona
            sortOrder={(lazyState.sortOrder === 1) ? 1 : -1}
            onFilter={onFilter}
            loading={loading}
            totalRecords={totalRecords}
            paginatorLeft={paginatorLeft}
          >
            <Column field="nome" header="Nome" sortable body={nomeBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
            <Column
              field="tipo_pessoa"
              header="Tipo"
              body={(row: Vec.Empresa) => (
                <>
                  <span className="p-column-title">Tipo</span>
                  {(row.tipo_pessoa ?? 'PJ') === 'PF' ? 'PF' : 'PJ'}
                </>
              )}
              headerStyle={{ minWidth: '6rem' }}
            />
            <Column field="municipio" header="Municipio" body={municipioBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
            <Column field="tipo_empresa" header="Enquadramento Jurídico" body={tipoEmpresaBodyTemplate} headerStyle={{ minWidth: '12rem' }}></Column>
            <Column field="regime_tributario" header="Regime tributário" body={regimeTributarioBodyTemplate} headerStyle={{ minWidth: '14rem' }}></Column>
            <Column body={actionBodyTemplate} header="Ações" headerStyle={{ minWidth: '10rem' }}></Column>
          </DataTable>

          <Dialog
            visible={empresaDialog}
            style={{ width: 'min(920px, 96vw)' }}
            header={empresa?.id ? 'Cliente (edição)' : 'Cliente (novo)'}
            modal
            className="p-fluid"
            footer={empresaDialogFooter}
            onHide={hideDialog}
          >
            {coreCamposBloqueados && (
              <p className="text-600 text-sm mb-3">
                Você pode alterar município, bairro, endereço e contatos (dados complementares em clientes_dados), mesmo após o processo ter sido iniciado na Manutenção de Empresas.
              </p>
            )}

            <div className="relative w-full mb-2" style={{ maxWidth: '100%' }}>
              <div
                className="flex gap-2 align-items-center flex-shrink-0"
                style={{
                  position: 'absolute',
                  top: '0.35rem',
                  right: '0.15rem',
                  zIndex: 2,
                  pointerEvents: 'auto',
                }}
              >
                <Button
                  type="button"
                  tooltip="Dados principais"
                  tooltipOptions={{ position: 'bottom' }}
                  onClick={() => setClienteDialogTabIndex(0)}
                  className="w-2rem h-2rem p-0"
                  rounded
                  outlined={clienteDialogTabIndex !== 0}
                  label="1"
                />
                <Button
                  type="button"
                  tooltip="Endereço e meios de contato"
                  tooltipOptions={{ position: 'bottom' }}
                  onClick={() => setClienteDialogTabIndex(1)}
                  className="w-2rem h-2rem p-0"
                  rounded
                  outlined={clienteDialogTabIndex !== 1}
                  label="2"
                />
                <Button
                  type="button"
                  tooltip={
                    abaCertificadoClienteHabilitada
                      ? 'Certificado digital'
                      : 'Certificado digital (somente administrador do escritório)'
                  }
                  tooltipOptions={{ position: 'bottom' }}
                  onClick={() => setClienteDialogTabIndex(2)}
                  className="w-2rem h-2rem p-0"
                  rounded
                  outlined={clienteDialogTabIndex !== 2}
                  label="3"
                  disabled={!abaCertificadoClienteHabilitada}
                />
              </div>
              <TabView
                activeIndex={clienteDialogTabIndex}
                onTabChange={(e) => {
                  if (!abaCertificadoClienteHabilitada && e.index === 2) {
                    return;
                  }
                  setClienteDialogTabIndex(e.index);
                }}
                className="w-full cliente-tabview-dialog"
                pt={{
                  root: {
                    style: { maxWidth: '100%' },
                  },
                  navContainer: {
                    className: 'w-full',
                    style: {
                      boxSizing: 'border-box',
                      paddingLeft: 0,
                      paddingRight: '11.25rem',
                      position: 'relative',
                      borderBottom: 'none',
                    },
                  },
                  navContent: {
                    style: {
                      flex: '1 1 auto',
                      minWidth: 0,
                      overflowX: 'auto',
                      overflowY: 'hidden',
                    },
                  },
                  /* O <li> da ink bar é irmão das abas no <ul>; space-between o tratava como 4º item e gerava traços/pontos estranhos. */
                  inkbar: { style: { display: 'none' } },
                  nav: {
                    style: {
                      display: 'flex',
                      flexWrap: 'nowrap',
                      width: '100%',
                      justifyContent: 'flex-start',
                      alignItems: 'flex-end',
                      columnGap: '1.5rem',
                      listStyle: 'none',
                      margin: 0,
                      paddingLeft: 0,
                      paddingRight: 0,
                    },
                  },
                }}
              >
                <TabPanel header="Dados Principais" headerStyle={{ whiteSpace: 'nowrap' }}>
                  <div className="field">
                    <label htmlFor="ddtipo_pessoa">Pessoa física ou jurídica</label>
                    <Dropdown
                      id="ddtipo_pessoa"
                      value={isClientePF ? 'PF' : 'PJ'}
                      options={tipoPessoaOptions}
                      onChange={(e) => onTipoPessoaChange(e.value)}
                      optionLabel="label"
                      optionValue="value"
                      disabled={empresa?.iniciado === true || coreCamposBloqueados}
                      className="w-full"
                    />
                  </div>

                  <div className="field">
                    <label htmlFor="nome_">Nome</label>
                    <InputText
                      id="nome_"
                      value={empresa.nome}
                      type="text"
                      onChange={(e) => onInputChange(e, 'nome')}
                      required
                      autoFocus
                      disabled={empresa?.iniciado === true || coreCamposBloqueados}
                      className={classNames({ 'p-invalid': submitted && !empresa.nome })}
                    />
                    {submitted && !empresa.nome && <small className="p-invalid">Nome do cliente é obrigatório.</small>}
                  </div>

                  <div className="field">
                    <label htmlFor="ddmuncli">Município</label>
                    <Dropdown
                      id="ddmuncli"
                      value={municipioFormDropdownValue}
                      options={municipios}
                      onChange={(e) => onMunicipioClienteChange(e.value ?? null)}
                      optionLabel="nome"
                      dataKey="id"
                      placeholder="Selecione o município"
                      emptyMessage="Nenhum município encontrado"
                      disabled={!podeEditarComplementosCliente}
                      className="w-full"
                      showClear
                    />
                  </div>

                  {!isClientePF && (
                    <div className="formgrid grid">
                      <div className="field col-12 md:col-6">
                        <label htmlFor="dd_tipo_emp_cli">Enquadramento jurídico</label>
                        <Dropdown
                          id="dd_tipo_emp_cli"
                          value={tipoEmpresaFormDropdownValue}
                          options={tiposEmpresaOptions}
                          onChange={(e) => {
                            const opt = e.value as Vec.TipoEmpresaLite | null;
                            if (!opt?.id) {
                              setEmpresa((prev) => ({
                                ...prev,
                                tipo_empresa: { id: '', descricao: '' },
                              }));
                              return;
                            }
                            setEmpresa((prev) => ({
                              ...prev,
                              tipo_empresa: {
                                id: opt.id ?? '',
                                descricao: opt.descricao ?? '',
                              },
                            }));
                          }}
                          optionLabel="descricao"
                          dataKey="id"
                          placeholder="Selecione o enquadramento"
                          emptyMessage="Cadastre tipos em Tipos de empresa"
                          disabled={!podeEditarEnquadramentoRegimePJ}
                          className="w-full"
                          showClear
                          filter
                          filterBy="descricao"
                        />
                      </div>
                      <div className="field col-12 md:col-6">
                        <label htmlFor="dd_regime_trib">Regime tributário</label>
                        <Dropdown
                          id="dd_regime_trib"
                          value={regimeTributarioFormDropdownValue}
                          options={regimesTributariosOptions}
                          onChange={(e) => {
                            const opt = e.value as Vec.RegimeTributario | null;
                            if (!opt?.id) {
                              setEmpresa((prev) => ({
                                ...prev,
                                regime_tributario: { id: '', nome: '', codigo_crt: undefined },
                              }));
                              return;
                            }
                            setEmpresa((prev) => ({
                              ...prev,
                              regime_tributario: {
                                id: opt.id ?? '',
                                nome: opt.nome ?? '',
                                codigo_crt: opt.codigo_crt,
                              },
                            }));
                          }}
                          optionLabel="nome"
                          itemTemplate={(r: Vec.RegimeTributario) => (
                            <span>
                              {r.nome ?? ''} (CRT {r.codigo_crt ?? ''})
                            </span>
                          )}
                          valueTemplate={(r: Vec.RegimeTributario | null) =>
                            r?.id ? (
                              <span>
                                {r.nome ?? ''} (CRT {r.codigo_crt ?? ''})
                              </span>
                            ) : (
                              <span className="text-500">Selecione o regime (CRT)</span>
                            )
                          }
                          dataKey="id"
                          placeholder="Selecione o regime (CRT)"
                          emptyMessage="Cadastre regimes em Regimes tributários"
                          disabled={!podeEditarEnquadramentoRegimePJ}
                          className="w-full"
                          showClear
                          loading={regimesTributariosLoading}
                          filter
                          filterBy="nome"
                        />
                      </div>
                    </div>
                  )}

                  {!isClientePF && (
                    <div className="p-fluid field">
                      <label htmlFor="ddtag">CNAE&apos;s (somente PJ)</label>
                      <Chips
                        id="ddtag"
                        value={empresa.cnaes}
                        onChange={handleCnaesChange}
                        itemTemplate={(cnae: string) => (
                          <div className="p-d-flex p-ai-center p-flex-wrap">
                            <div className="p-mr-2">{cnae.replace(/(\d{2})(\d{2})(\d{1})(\d{2})/, '$1.$2-$3/$4')}</div>
                          </div>
                        )}
                        keyfilter="alphanum"
                        disabled={empresa?.iniciado === true || coreCamposBloqueados}
                      />
                    </div>
                  )}

                  {isClientePF ? (
                    <div className="field">
                      <label htmlFor="documento_">CPF (11 dígitos)</label>
                      <InputText
                        id="documento_"
                        value={empresa.documento ?? ''}
                        type="text"
                        inputMode="numeric"
                        maxLength={14}
                        onChange={(e) => onInputChange(e, 'documento')}
                        disabled={empresa?.iniciado === true || coreCamposBloqueados}
                        className={classNames({ 'p-invalid': submitted && onlyDigits(empresa.documento ?? '').length !== 11 })}
                        placeholder="Somente números ou formatado"
                      />
                    </div>
                  ) : (
                    <>
                      <div className="formgrid grid">
                        <div className="field col-12 md:col-4">
                          <label htmlFor="documento_">CNPJ (14 dígitos, opcional)</label>
                          <InputText
                            id="documento_"
                            value={empresa.documento ?? ''}
                            type="text"
                            inputMode="numeric"
                            maxLength={18}
                            onChange={(e) => onInputChange(e, 'documento')}
                            disabled={empresa?.iniciado === true || coreCamposBloqueados}
                            className={classNames({
                              'p-invalid': submitted && onlyDigits(empresa.documento ?? '').length > 0 && onlyDigits(empresa.documento ?? '').length !== 14,
                            })}
                            placeholder="Opcional para PJ"
                          />
                        </div>
                        <div className="field col-12 md:col-4">
                          <label htmlFor="ie_cli">Inscrição estadual</label>
                          <InputText
                            id="ie_cli"
                            value={empresa.ie ?? ''}
                            type="text"
                            onChange={(e) => onInputChange(e, 'ie')}
                            disabled={empresa?.iniciado === true || coreCamposBloqueados}
                            className="w-full"
                            maxLength={30}
                            placeholder="Ex.: ISENTO"
                          />
                        </div>
                        <div className="field col-12 md:col-4">
                          <label htmlFor="im_cli">Inscrição municipal</label>
                          <InputText
                            id="im_cli"
                            value={empresa.im ?? ''}
                            type="text"
                            onChange={(e) => onInputChange(e, 'im')}
                            disabled={empresa?.iniciado === true || coreCamposBloqueados}
                            className="w-full"
                            maxLength={30}
                          />
                        </div>
                      </div>
                    </>
                  )}

                  {!isClientePF && (
                    <div className="field">
                      <label htmlFor="cap_social">Capital social</label>
                      <InputNumber
                        id="cap_social"
                        inputId="cap_social"
                        value={clienteExtra.capital_social ?? undefined}
                        onChange={(e) =>
                          setClienteExtra((x) => ({
                            ...x,
                            capital_social: e.value === null || e.value === undefined ? null : Number(e.value),
                          }))
                        }
                        mode="currency"
                        currency="BRL"
                        locale="pt-BR"
                        minFractionDigits={2}
                        maxFractionDigits={7}
                        className="w-full"
                        disabled={!podeEditarComplementosCliente}
                      />
                    </div>
                  )}
                </TabPanel>

                <TabPanel header="Endereço e Meios de Contato" headerStyle={{ whiteSpace: 'nowrap' }}>
                  <p className="text-600 text-sm mt-0 mb-3">
                    Município e dados principais foram informados na aba <strong>Dados Principais</strong>.
                  </p>

                  <div className="formgrid grid">
                    <div className="field col-12 md:col-8">
                      <label htmlFor="logr_">Logradouro (rua)</label>
                      <InputText
                        id="logr_"
                        value={clienteExtra.logradouro}
                        onChange={(e) => setClienteExtra((x) => ({ ...x, logradouro: e.target.value }))}
                        disabled={!podeEditarComplementosCliente}
                        className="w-full"
                      />
                    </div>
                    <div className="field col-12 md:col-4">
                      <label htmlFor="num_">Número</label>
                      <InputText
                        id="num_"
                        value={clienteExtra.numero}
                        onChange={(e) => setClienteExtra((x) => ({ ...x, numero: e.target.value }))}
                        disabled={!podeEditarComplementosCliente}
                        className="w-full"
                        maxLength={40}
                      />
                    </div>
                  </div>

                  <div className="field">
                    <label htmlFor="bairro_">Bairro</label>
                    <InputText
                      id="bairro_"
                      value={empresa.bairro ?? ''}
                      type="text"
                      onChange={(e) => onInputChange(e, 'bairro')}
                      disabled={!podeEditarComplementosCliente}
                      placeholder="Obrigatório quando houver compromissos por bairro"
                    />
                  </div>

                  <div className="field">
                    <label htmlFor="cep_">CEP</label>
                    <InputText
                      id="cep_"
                      value={clienteExtra.cep}
                      inputMode="numeric"
                      maxLength={9}
                      onChange={(e) => setClienteExtra((x) => ({ ...x, cep: e.target.value }))}
                      disabled={!podeEditarComplementosCliente}
                      placeholder="00000000 ou 00000-000"
                    />
                  </div>

                  <div className="field">
                    <label htmlFor="edemail">E-mail de contato</label>
                    <InputText
                      id="edemail"
                      type="email"
                      value={clienteExtra.email_contato}
                      onChange={(e) => setClienteExtra((x) => ({ ...x, email_contato: e.target.value }))}
                      disabled={!podeEditarComplementosCliente}
                      className="w-full"
                    />
                  </div>

                  <div className="formgrid grid">
                    <div className="field col-12 md:col-6">
                      <label htmlFor="edtel1">Telefone</label>
                      <InputText
                        id="edtel1"
                        value={clienteExtra.telefone}
                        onChange={(e) => setClienteExtra((x) => ({ ...x, telefone: e.target.value }))}
                        disabled={!podeEditarComplementosCliente}
                        maxLength={40}
                      />
                    </div>
                    <div className="field col-12 md:col-6">
                      <label htmlFor="edtel2">Telefone 2</label>
                      <InputText
                        id="edtel2"
                        value={clienteExtra.telefone2}
                        onChange={(e) => setClienteExtra((x) => ({ ...x, telefone2: e.target.value }))}
                        disabled={!podeEditarComplementosCliente}
                        maxLength={40}
                      />
                    </div>
                  </div>

                  <div className="formgrid grid">
                    <div className="field col-12 md:col-6">
                      <label htmlFor="edaber">Data de abertura</label>
                      <input
                        id="edaber"
                        type="date"
                        className="p-inputtext p-component w-full"
                        value={clienteExtra.data_abertura}
                        disabled={!podeEditarComplementosCliente}
                        onChange={(e) => setClienteExtra((x) => ({ ...x, data_abertura: e.target.value }))}
                      />
                      <small className="text-600">Formato conforme o navegador (aaaa-mm-dd enviado à API).</small>
                    </div>
                    <div className="field col-12 md:col-6">
                      <label htmlFor="edenc">Data de encerramento</label>
                      <input
                        id="edenc"
                        type="date"
                        className="p-inputtext p-component w-full"
                        value={clienteExtra.data_encerramento}
                        disabled={!podeEditarComplementosCliente}
                        onChange={(e) => setClienteExtra((x) => ({ ...x, data_encerramento: e.target.value }))}
                      />
                    </div>
                  </div>

                  <div className="field">
                    <label htmlFor="edobs">Observações</label>
                    <InputTextarea
                      id="edobs"
                      value={clienteExtra.observacao}
                      onChange={(e) => setClienteExtra((x) => ({ ...x, observacao: e.target.value }))}
                      disabled={!podeEditarComplementosCliente}
                      rows={3}
                      className="w-full"
                      autoResize
                    />
                  </div>
                </TabPanel>

                <TabPanel
                  header="Certificado Digital"
                  headerStyle={{ whiteSpace: 'nowrap' }}
                  disabled={!abaCertificadoClienteHabilitada}
                >
                  {!empresa.id ? (
                    <p className="text-600 text-sm">Salve o cliente para anexar o certificado A1 (.pfx).</p>
                  ) : (
                    <>
                      <p className="text-600 text-sm mt-0 mb-3">
                        Certificado por cliente (armazenamento cifrado). Mesmo fluxo da tela de configurações do escritório.
                      </p>
                      <div className="field">
                        <label htmlFor="cert_cli_tipo">Tipo de certificado</label>
                        <Dropdown
                          id="cert_cli_tipo"
                          options={tipoCertificadoOptions}
                          value={certClienteForm.tipo_certificado}
                          onChange={(e) => setCertClienteForm((p) => ({ ...p, tipo_certificado: e.value ?? 'A1' }))}
                          placeholder="Selecione"
                          className="w-full"
                          disabled={!podeAnexarCertificadoCliente}
                        />
                      </div>
                      <div className="field">
                        <label htmlFor="cert_cli_arq">Arquivo .pfx</label>
                        <div className="p-inputgroup flex-wrap w-full">
                          <InputText
                            id="cert_cli_arq"
                            value={certArquivo?.name ?? (certClienteForm.validade_ate ? 'Certificado carregado' : '')}
                            readOnly
                            placeholder="Selecione o arquivo PFX"
                            className="flex-1 w-full"
                          />
                          <Button
                            type="button"
                            icon="pi pi-upload"
                            onClick={() => certFileInputRef.current?.click()}
                            tooltip="Selecionar arquivo PFX"
                            disabled={!podeAnexarCertificadoCliente}
                          />
                        </div>
                        <input
                          ref={certFileInputRef}
                          type="file"
                          accept=".pfx,application/x-pkcs12"
                          style={{ display: 'none' }}
                          onChange={(e) => {
                            const f = e.target.files?.[0];
                            setCertArquivo(f ?? null);
                          }}
                        />
                      </div>
                      <div className="field">
                        <label htmlFor="cert_cli_senha">Senha do certificado</label>
                        <InputText
                          id="cert_cli_senha"
                          type="password"
                          autoComplete="new-password"
                          value={certClienteForm.senha_certificado}
                          onChange={(e) => setCertClienteForm((p) => ({ ...p, senha_certificado: e.target.value }))}
                          className="w-full"
                          disabled={!podeAnexarCertificadoCliente}
                        />
                      </div>
                      <div className="field">
                        <label htmlFor="cert_cli_nome">Nome</label>
                        <InputText
                          id="cert_cli_nome"
                          value={certClienteForm.nome_certificado}
                          onChange={(e) => setCertClienteForm((p) => ({ ...p, nome_certificado: e.target.value }))}
                          className="w-full"
                          readOnly
                        />
                        <small className="text-600">Preenchido a partir do certificado após o envio.</small>
                      </div>
                      <div className="field">
                        <label htmlFor="cert_cli_para">Emitido para</label>
                        <InputText
                          id="cert_cli_para"
                          value={certClienteForm.emitido_para}
                          onChange={(e) => setCertClienteForm((p) => ({ ...p, emitido_para: e.target.value }))}
                          className="w-full"
                          disabled={!podeAnexarCertificadoCliente}
                        />
                      </div>
                      <div className="field">
                        <label htmlFor="cert_cli_por">Emitido por</label>
                        <InputText
                          id="cert_cli_por"
                          value={certClienteForm.emitido_por}
                          onChange={(e) => setCertClienteForm((p) => ({ ...p, emitido_por: e.target.value }))}
                          className="w-full"
                          readOnly
                        />
                      </div>
                      <div className="formgrid grid">
                        <div className="field col-12 md:col-6">
                          <label htmlFor="cert_cli_val">Validade (início)</label>
                          <InputText
                            id="cert_cli_val"
                            type="date"
                            value={certClienteForm.validade_de}
                            onChange={(e) => onValidadeCertClienteChange(e.target.value)}
                            className="w-full"
                            disabled={!podeAnexarCertificadoCliente}
                          />
                        </div>
                        <div className="field col-12 md:col-6">
                          <label htmlFor="cert_cli_val_ate">Validade (fim)</label>
                          <InputText
                            id="cert_cli_val_ate"
                            type="date"
                            value={certClienteForm.validade_ate}
                            onChange={(e) => setCertClienteForm((p) => ({ ...p, validade_ate: e.target.value }))}
                            className="w-full"
                            disabled={!podeAnexarCertificadoCliente}
                          />
                        </div>
                      </div>
                      {!podeAnexarCertificadoCliente && (
                        <p className="text-600 text-sm">Somente administradores podem enviar ou alterar o .pfx do cliente.</p>
                      )}
                      <div className="mt-3">
                        <Button
                          type="button"
                          label={certClienteLoading ? 'Carregando…' : 'Salvar certificado'}
                          icon="pi pi-save"
                          onClick={() => void saveCertificadoCliente()}
                          disabled={!podeAnexarCertificadoCliente || certClienteLoading}
                        />
                      </div>
                    </>
                  )}
                </TabPanel>
              </TabView>
            </div>
          </Dialog>

          <Dialog visible={deleteEmpresaDialog} style={{ width: '450px' }} header="Confirma a exclusão ?" modal footer={deleteEmpresaDialogFooter} onHide={hideDeleteEmpresaDialog} className="red-header">
            <div className="flex align-items-center justify-content-center">
              <i className="pi pi-exclamation-triangle mr-3" style={{ fontSize: '2rem', color: '#d6551e' }} />
              {empresa && (
                <span>
                  Tem certeza que quer deletar <b>{empresa.nome}</b>?
                </span>
              )}
            </div>
          </Dialog>

        </div>
      </div>
    </div >
  );
};

export default Clientes;

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
