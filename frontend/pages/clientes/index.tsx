import { Button } from 'primereact/button';
import { Column } from 'primereact/column';
import { Chips } from 'primereact/chips';
import { DataTable, DataTableFilterMeta } from 'primereact/datatable';
import type { PaginatorTemplate } from 'primereact/paginator';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
import { InputNumber } from 'primereact/inputnumber';
import { InputTextarea } from 'primereact/inputtextarea';
import { Toast } from 'primereact/toast';
import { Toolbar } from 'primereact/toolbar';
import { classNames } from 'primereact/utils';
import React, { useEffect, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { canSSRAuth } from '../../components/utils/canSSRAuth';
import setupAPIClient from '../../components/api/api';
import { Vec } from '../../types/types';

import { Dropdown } from 'primereact/dropdown';
import MunicipioService from '../../services/cruds/MunicipioService';
import EmpresaService from '../../services/cruds/EmpresaService';
import RotinaService from '../../services/cruds/RotinaService';
import RotinaPFService from '../../services/cruds/RotinaPFService';
import EmpresaDadosService from '../../services/cruds/EmpresaDadosService';

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

  let emptyRotina: Vec.RotinaLite = {
    id: '',
    descricao: ''
  }

  let emptyRotinaPF: Vec.RotinaPFLite = {
    id: '',
    nome: '',
    categoria: ''
  }

  const [empresas, setEmpresas] = useState([]);

  const [municipios, setMunicipios] = useState<Vec.MunicipioLite[]>([]);

  const [rotinas, setRotinas] = useState<Vec.RotinaLite[]>([]);
  const [rotina, setRotina] = useState<Vec.RotinaLite>(emptyRotina);
  const [rotinasPF, setRotinasPF] = useState<Vec.RotinaPFLite[]>([]);
  const [rotinaPF, setRotinaPF] = useState<Vec.RotinaPFLite>(emptyRotinaPF);

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

  const [empresaDialog, setEmpresaDialog] = useState(false);
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

  const loadRotinasPF = () => {
    const svc = RotinaPFService();
    svc
      .getRotinasPFLite()
      .then(({ data }) => {
        setRotinasPF(Array.isArray(data?.rotinas_pf) ? data.rotinas_pf : []);
      })
      .catch(() => {
        setRotinasPF([]);
        toast.current?.show({
          severity: 'warn',
          summary: 'Atenção',
          detail: 'Não foi possível carregar rotinas PF (cadastre templates no banco após a migration 025).',
          life: 5000,
        });
      });
  };

  useEffect(() => {
    if (!empresaDialog) {
      return;
    }
    if ((empresa.tipo_pessoa ?? 'PJ') !== 'PF') {
      return;
    }
    loadRotinasPF();
  }, [empresaDialog, empresa.tipo_pessoa]);

  const { data: userRole = null } = useQuery<string | null>({
    queryKey: ['user-role'],
    queryFn: async () => {
      try {
        const api = setupAPIClient(undefined);
        const r = await api.get('/api/usuariorole');
        return r.data?.logado?.role ?? null;
      } catch {
        return null;
      }
    },
  });

  const empresaService = EmpresaService();
  const empresaDadosService = EmpresaDadosService();

  const podeCadastrarClientes = userRole === 'ADMIN';
  const podeEditarDadosComplementares = userRole === 'ADMIN' || userRole === 'USER';
  const podeEditarComplementosCliente = podeCadastrarClientes || podeEditarDadosComplementares;

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

  const loadRotinasPorMunicipio = (municipioId: string) => {
    const mid = (municipioId ?? '').trim();
    if (!mid) {
      setRotinas([]);
      return;
    }
    const rotinaService = RotinaService();
    rotinaService.getRotinasLite({ id: mid }).then(({ data }) => {
      const raw = data?.rotinas ?? [];
      setRotinas(
        raw.map((r: Vec.RotinaLite) => ({
          ...r,
          lista_label: r.municipio?.nome ? `${r.descricao ?? ''} (${r.municipio.nome})` : (r.descricao ?? ''),
        })),
      );
    });
  };

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
    setRotina(emptyRotina);
    setRotinaPF(emptyRotinaPF);
    setClienteExtra(emptyClienteExtra);
    setRotinas([]);
    setRotinasPF([]);
    setSubmitted(false);
    setEmpresaDialog(true);
  };

  const hideDialog = () => {
    setSubmitted(false);
    setEmpresaDialog(false);
    setClienteExtra(emptyClienteExtra);
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

  function onRotinaChange(selectedValue: Vec.RotinaLite) {
    setRotina(selectedValue);
    setEmpresa((prev) => ({
      ...prev,
      rotina: {
        id: selectedValue?.id ?? '',
        descricao: selectedValue?.descricao ?? '',
      },
      tipo_empresa:
        selectedValue?.tipo_empresa?.id != null && selectedValue.tipo_empresa.id !== ''
          ? {
              id: selectedValue.tipo_empresa.id,
              descricao: selectedValue.tipo_empresa.descricao ?? '',
            }
          : { id: '', descricao: '' },
    }));
  }

  function onRotinaPFChange(selectedValue: Vec.RotinaPFLite) {
    const v = selectedValue ?? emptyRotinaPF;
    setRotinaPF(v);
    setEmpresa((prev) => ({
      ...prev,
      rotina_pf: {
        id: v.id ?? '',
        nome: v.nome ?? '',
        categoria: v.categoria ?? '',
      },
    }));
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

  const rotinaPFFormDropdownValue = (() => {
    const id = (rotinaPF?.id ?? empresa.rotina_pf?.id ?? '').trim();
    if (!id) {
      return null;
    }
    const fromList = rotinasPF.find((r) => (r.id ?? '').trim() === id);
    if (fromList) {
      return fromList;
    }
    return {
      id: rotinaPF.id,
      nome: rotinaPF.nome ?? empresa.rotina_pf?.nome ?? '',
      categoria: rotinaPF.categoria ?? empresa.rotina_pf?.categoria ?? '',
    };
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
    empresa.tenantid = tenantid;
    empresa.rotina = rotina;
    empresa.rotina_pf = rotinaPF;
    setSubmitted(true);

    const docDigits = onlyDigits(empresa.documento ?? '');
    const munOk = (empresa.municipio?.id ?? '').trim() !== '';
    const docOkPf = isClientePF && docDigits.length === 11;
    const docOkPj = !isClientePF && (docDigits.length === 0 || docDigits.length === 14);
    const rotinaOk = (empresa.rotina?.id ?? '').trim() !== '';
    const rotinaPfOk = (empresa.rotina_pf?.id ?? '').trim() !== '';

    const salvarSomenteClientesDados =
      !!empresa.id &&
      podeEditarComplementosCliente &&
      (empresa.iniciado === true || !podeCadastrarClientes);

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
      (isClientePF ? docOkPf && rotinaPfOk : rotinaOk && docOkPj);

    if (canSave) {
      const _empresa = {
        ...empresa,
        tipo_pessoa: isClientePF ? 'PF' : 'PJ',
        municipio: { id: (empresa.municipio?.id ?? '').trim() },
        rotina_pf: {
          id: (empresa.rotina_pf?.id ?? rotinaPF?.id ?? '').trim(),
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

      if (empresa.id) {
        empresaService
          .updateEmpresa(_empresa)
          .then(() => afterEmpresaOk(empresa.id!))
          .catch((error) => {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao atualizar o cliente', life: 3000 });
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
      if (!isClientePF && !rotinaOk) {
        toast.current?.show({ severity: 'warn', summary: 'Alerta', detail: 'Selecione a rotina (obrigatória para PJ)', life: 3000 });
      }
      if (isClientePF && !rotinaPfOk) {
        toast.current?.show({
          severity: 'warn',
          summary: 'Alerta',
          detail: 'Selecione a rotina PF (obrigatória para pessoa física)',
          life: 3500,
        });
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
    setRotina(row.rotina);
    const rpf = row.rotina_pf;
    setRotinaPF(
      rpf?.id
        ? { id: rpf.id, nome: rpf.nome ?? '', categoria: rpf.categoria ?? '' }
        : emptyRotinaPF
    );
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
      bairro: row.bairro ?? '',
      cnaes: cnaesArr,
      tipo_pessoa: (row.tipo_pessoa ?? 'PJ').toUpperCase() === 'PF' ? 'PF' : 'PJ',
      documento: row.documento ?? '',
    });
    setEmpresaDialog(true);

    const mid = (row.municipio?.id ?? '').trim();
    if (mid && (row.tipo_pessoa ?? 'PJ') !== 'PF') {
      loadRotinasPorMunicipio(mid);
    } else {
      setRotinas([]);
    }
    if ((row.tipo_pessoa ?? 'PJ') === 'PF') {
      loadRotinasPF();
    }

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
          if ((row.tipo_pessoa ?? 'PJ') !== 'PF') {
            loadRotinasPorMunicipio(m.id);
          }
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
      setRotina(emptyRotina);
      setRotinaPF(emptyRotinaPF);
      setEmpresa((prev) => ({
        ...prev,
        tipo_pessoa: 'PF',
        rotina: { id: '', descricao: '' },
        rotina_pf: { id: '', nome: '', categoria: '' },
        tipo_empresa: { id: '', descricao: '' },
        cnaes: [],
      }));
      setRotinas([]);
      loadRotinasPF();
      return;
    }
    setRotinaPF(emptyRotinaPF);
    setEmpresa((prev) => {
      const next = {
        ...prev,
        tipo_pessoa: 'PJ' as const,
        rotina_pf: { id: '', nome: '', categoria: '' },
      };
      const mid = (next.municipio?.id ?? '').trim();
      if (mid) {
        loadRotinasPorMunicipio(mid);
      }
      return next;
    });
  }

  function onMunicipioClienteChange(m: Vec.MunicipioLite | null): void {
    const muni = m?.id ? { id: m.id, nome: m.nome ?? '' } : { id: '', nome: '' };
    setEmpresa((prev) => {
      const next = { ...prev, municipio: muni };
      if ((next.tipo_pessoa ?? 'PJ') === 'PJ') {
        if (muni.id) {
          loadRotinasPorMunicipio(muni.id);
        } else {
          setRotinas([]);
        }
      }
      return next;
    });
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

  const rotinaBodyTemplate = (rowData: Vec.Empresa) => {
    const pf = (rowData.tipo_pessoa ?? 'PJ') === 'PF';
    const label = pf ? rowData.rotina_pf?.nome : rowData.rotina?.descricao;
    return (
      <>
        <span className="p-column-title">Rotina</span>
        {label?.trim() ? label : '—'}
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
        <p className="m-0 mt-1 text-600 text-sm">Cadastro unificado: município, rotina municipal (PJ), rotina PF (IRPF/Carnê-Leão), CNAEs, CPF/CNPJ, endereço e contatos. Processo e compromissos na Manutenção de Empresas.</p>
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
            <Column field="rotina" header="Rotina (PJ / PF)" body={rotinaBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
            <Column field="tipo_empresa" header="Enquadramento Jurídico" body={tipoEmpresaBodyTemplate} headerStyle={{ minWidth: '12rem' }}></Column>
            <Column body={actionBodyTemplate} header="Ações" headerStyle={{ minWidth: '10rem' }}></Column>
          </DataTable>

          <Dialog
            visible={empresaDialog}
            style={{ width: 'min(720px, 96vw)' }}
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
              <small className="text-600">
                {isClientePF ? 'Município de residência ou contato.' : 'Define a lista de rotinas disponíveis para PJ.'}
              </small>
            </div>

            {!isClientePF && (
            <div className="field">
              <label htmlFor="ddrotina">Rotina (somente PJ)</label>
              <Dropdown
                id="ddrotina"
                value={empresa.rotina}
                options={rotinas}
                onChange={(e) => onRotinaChange(e.value)}
                optionLabel="lista_label"
                dataKey="id"
                placeholder={
                  (empresa.municipio?.id ?? '').trim()
                    ? 'Selecione a rotina do município'
                    : 'Selecione o município primeiro'
                }
                emptyMessage="Nenhuma rotina para este município"
                disabled={empresa?.iniciado === true || coreCamposBloqueados}
              />
              {submitted && !(empresa.rotina?.id ?? '').trim() && (
                <small className="p-invalid">Rotina é obrigatória para pessoa jurídica.</small>
              )}
            </div>
            )}

            <div className="field">
              <label htmlFor="ddrotinapf">Rotina PF (somente pessoa física)</label>
              <Dropdown
                id="ddrotinapf"
                value={rotinaPFFormDropdownValue}
                options={rotinasPF}
                onChange={(e) => onRotinaPFChange(e.value ?? emptyRotinaPF)}
                optionLabel="nome"
                dataKey="id"
                placeholder={
                  isClientePF
                    ? rotinasPF.length
                      ? 'Selecione a rotina federal / sazonal'
                      : 'Cadastre rotinas PF no banco (tabela rotina_pf)'
                    : 'Não aplicável a PJ'
                }
                emptyMessage="Nenhuma rotina PF para este tenant"
                disabled={empresa?.iniciado === true || !isClientePF || coreCamposBloqueados}
                className="w-full"
              />
              {submitted && isClientePF && !(empresa.rotina_pf?.id ?? rotinaPF?.id ?? '').trim() && (
                <small className="p-invalid">Rotina PF é obrigatória para pessoa física.</small>
              )}
              <small className="text-600">Templates por tenant (Carnê-Leão mensal, IRPF anual, etc.).</small>
            </div>

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

            <div className="field">
              <label htmlFor="documento_">{isClientePF ? 'CPF (11 dígitos)' : 'CNPJ (14 dígitos, opcional)'}</label>
              <InputText
                id="documento_"
                value={empresa.documento ?? ''}
                type="text"
                inputMode="numeric"
                maxLength={isClientePF ? 14 : 18}
                onChange={(e) => onInputChange(e, 'documento')}
                disabled={empresa?.iniciado === true || coreCamposBloqueados}
                className={classNames({ 'p-invalid': submitted && isClientePF && onlyDigits(empresa.documento ?? '').length !== 11 })}
                placeholder={isClientePF ? 'Somente números ou formatado' : 'Opcional para PJ'}
              />
              <small className="text-600">Único cadastro de CPF/CNPJ; não duplicar em outros campos.</small>
            </div>

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
                <small className="text-600">Por cliente (PJ). O enquadramento jurídico mantém apenas faturamento anual de referência.</small>
              </div>
            )}

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
