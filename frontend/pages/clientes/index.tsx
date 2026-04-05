import { Button } from 'primereact/button';
import { Column } from 'primereact/column';
import { DataTable, DataTableFilterMeta } from 'primereact/datatable';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
import { InputTextarea } from 'primereact/inputtextarea';
import { Toast } from 'primereact/toast';
import { Toolbar } from 'primereact/toolbar';
import { classNames } from 'primereact/utils';
import React, { useEffect, useRef, useState } from 'react';
import { canSSRAuth } from '../../components/utils/canSSRAuth';
import setupAPIClient from '../../components/api/api';
import { Vec } from '../../types/types';

import { Dropdown } from 'primereact/dropdown';
import MunicipioService from '../../services/cruds/MunicipioService';
import EmpresaService from '../../services/cruds/EmpresaService';
import RotinaService from '../../services/cruds/RotinaService';
import EmpresaDadosService from '../../services/cruds/EmpresaDadosService';
import { Chips } from "primereact/chips";

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
const Clientes = ({ dados }) => {

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

  const [empresas, setEmpresas] = useState([]);

  const [municipios, setMunicipios] = useState<Vec.MunicipioLite[]>([]);

  const [rotinas, setRotinas] = useState<Vec.RotinaLite[]>([]);
  const [rotina, setRotina] = useState<Vec.RotinaLite>(emptyRotina);
  const [userRole, setUserRole] = useState<string | null>(null);

  const [dadosComplementaresDialog, setDadosComplementaresDialog] = useState(false);
  const [empresaDadosRef, setEmpresaDadosRef] = useState<Vec.Empresa | null>(null);
  const [empresaDadosMunicipio, setEmpresaDadosMunicipio] = useState<Vec.MunicipioLite>({ id: '', nome: '' });
  const [empresaDadosForm, setEmpresaDadosForm] = useState<Vec.EmpresaDados>({
    cnpj: '',
    endereco: '',
    email_contato: '',
    telefone: '',
    telefone2: '',
    data_abertura: '',
    data_encerramento: '',
    observacao: '',
  });

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

  useEffect(() => {
    loadLazyMunicipios();
    loadRotinasTodas();
    loadLazyEmpresa();
  }, []);

  useEffect(() => {
    const api = setupAPIClient(undefined);
    api
      .get('/api/usuariorole')
      .then((r) => setUserRole(r.data?.logado?.role ?? null))
      .catch(() => setUserRole(null));
  }, []);

  const empresaService = EmpresaService();
  const empresaDadosService = EmpresaDadosService();

  const podeCadastrarClientes = userRole === 'ADMIN' || userRole === 'SUPER';
  const podeEditarDadosComplementares = userRole === 'ADMIN' || userRole === 'USER';

  const loadLazyEmpresa = () => {
    setLazyState(prevState => ({
      ...prevState,
      tenantid: tenantid
    }))
    empresaService.getEmpresas({ lazyEvent: JSON.stringify(lazyState) })

      .then(({ data }) => {
        setEmpresas(data.empresas);
        setTotalRecords(data.totalRecords);
      })
      .catch((error) => {
        toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao carregar as Empresas', life: 3000 });
      })
      .finally(() => setLoading(false));

  }

  async function handleCnaesChange(event): Promise<void> {
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

  const loadRotinasTodas = () => {
    const rotinaService = RotinaService();
    rotinaService.getRotinasLite(null).then(({ data }) => {
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

  const onPage = (event) => {
    setFirst(event.first);
    setRows(event.rows);
    setCurrentPage(event.page + 1);
    setSortOrder(event.sortOrder);
    setSortField(event.sortField);
    setLazyState({ ...lazyState, first: event.first, rows: event.rows, page: event.page + 1, sortField: event.sortField, sortOrder: event.sortOrder });
    setLazyState(event)
  }

  //const onPageInputKeyDown = (event: React.KeyboardEvent<HTMLInputElement>, options: { totalPages: number; rows: React.SetStateAction<number>; first: React.SetStateAction<number>; }) => {
  const onPageInputKeyDown = (event, options) => {
    if (event.key === 'Enter') {
      const page = currentPage;
      if (page < 1 || page > options.totalPages) {
        setPageInputTooltip(`Valor deve estar entre 1 e ${options.totalPages}.`);
      }
      else {
        const first = currentPage ? options.rows * (page - 1) : 0;

        setFirst(options.first);
        setRows(options.rows);
        setCurrentPage(page);
        setLazyState({ ...lazyState, first: first, rows: options.rows, page: currentPage });
      }
    }

  }

  const onPageInputChange = (event) => {
    setCurrentPage(event.target.value);
  }


  const onSort = (event) => {
    setLazyState(event);
  }

  const onFilter = (event) => {
    event['first'] = 0;
    setLazyState(event)
  };

  const openNew = () => {
    setEmpresa(emptyEmpresa);
    setRotina(emptyRotina);
    setSubmitted(false);
    setEmpresaDialog(true);
  };

  const hideDialog = () => {
    setSubmitted(false);
    setEmpresaDialog(false);
  };

  const hideDeleteEmpresaDialog = () => {
    setDeleteEmpresaDialog(false);
  };

  function handleBuscaEmpresa(event, value: string): void {
    if (event.key === 'Enter') {
      if (value !== '') {
        setLazyState({ ...lazyState, filters: { nome: { value: value, matchMode: 'contains' } } });
      } else {
        setLazyState({ ...lazyState, filters: { nome: { value: '', matchMode: 'contains' } } });
      }
    }
  }

  function handleClear(e): void {
    if (!e.target.value) {
      setLazyState({ ...lazyState, filters: { nome: { value: '', matchMode: 'contains' } } });
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

  const isClientePF = (empresa.tipo_pessoa ?? 'PJ') === 'PF';

  /** PrimeReact Dropdown exige o mesmo objeto da lista `options` (ou valor alinhado por id). */
  const dadosComplMunicipioDropdownValue = (() => {
    const id = (empresaDadosMunicipio?.id ?? '').trim();
    if (!id) {
      return null;
    }
    const fromList = municipios.find((m) => (m.id ?? '').trim() === id);
    if (fromList) {
      return fromList;
    }
    return { id: empresaDadosMunicipio.id, nome: empresaDadosMunicipio.nome ?? '' };
  })();

  const saveEmpresa = (event: any) => {
    empresa.tenantid = tenantid;
    empresa.rotina = rotina;
    setSubmitted(true);
    const docOk = (empresa.documento ?? '').trim() !== '';
    const rotinaOk = (empresa.rotina?.id ?? '').trim() !== '';
    const canSave = !!empresa?.nome?.trim() && (isClientePF ? docOk : rotinaOk);

    if (canSave) {
      let _empresa = {
        ...empresa,
        tipo_pessoa: isClientePF ? 'PF' : 'PJ',
        cnaes: Array.isArray(empresa.cnaes) ? [...empresa.cnaes] : [],
      };

      if (empresa.id) {
        empresaService.updateEmpresa(_empresa)
          .then(() => {
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Cliente atualizado', life: 3000 });
          })
          .catch((error) => {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao atualizar o cliente', life: 3000 });
          })
          .finally(() => {
            //setLoading(false);
            setEmpresaDialog(false);
            setEmpresa(emptyEmpresa);
            loadLazyEmpresa();
          });
      } else {
        empresaService.createEmpresa(_empresa)
          .then((response) => {
            if (response && response.data) {
              setEmpresas(response.data.empresas);
              setTotalRecords(response.data.totalRecords);
            }
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Cliente criado', life: 3000 });
          })
          .catch((error) => {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao criar o cliente', life: 3000 });
          })
          .finally(() => {
            //setLoading(false);
            setEmpresaDialog(false);
            setEmpresa(emptyEmpresa);
            loadLazyEmpresa();
          });
      }
    } else {
      if (!empresa?.nome?.trim()) {
        toast.current?.show({ severity: 'warn', summary: 'Alerta', detail: 'Preencha o nome do cliente', life: 3000 });
      }
      if (!isClientePF && !rotinaOk) {
        toast.current?.show({ severity: 'warn', summary: 'Alerta', detail: 'Selecione a rotina (obrigatória para PJ)', life: 3000 });
      }
      if (isClientePF && !docOk) {
        toast.current?.show({ severity: 'warn', summary: 'Alerta', detail: 'Informe o CPF do cliente (pessoa física)', life: 3000 });
      }
    }
    setSubmitted(false);
  };

  const editEmpresa = (empresa: Vec.Empresa) => {
    setRotina(empresa.rotina)
    const rawCnaes = empresa.cnaes as unknown;
    const cnaesArr = Array.isArray(rawCnaes)
      ? rawCnaes.map((c) => String(c).replace(/\D/g, '')).filter(Boolean)
      : [];
    setEmpresa({
      ...empresa,
      municipio: empresa.municipio,
      rotina: empresa.rotina,
      bairro: empresa.bairro ?? '',
      cnaes: cnaesArr,
      tipo_pessoa: (empresa.tipo_pessoa ?? 'PJ').toUpperCase() === 'PF' ? 'PF' : 'PJ',
      documento: empresa.documento ?? '',
    });
    setEmpresaDialog(true);
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

  const onInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>, campo: string) => {
    const val = (e.target && e.target.value) || '';
    let _empresa = { ...empresa };
    _empresa[`${campo}`] = val;

    setEmpresa(_empresa);
  };

  function onTipoPessoaChange(value: string) {
    const v = value === 'PF' ? 'PF' : 'PJ';
    if (v === 'PF') {
      setRotina(emptyRotina);
      setEmpresa((prev) => ({
        ...prev,
        tipo_pessoa: 'PF',
        rotina: { id: '', descricao: '' },
        tipo_empresa: { id: '', descricao: '' },
        cnaes: [],
      }));
      return;
    }
    setEmpresa((prev) => ({ ...prev, tipo_pessoa: 'PJ' }));
  }

  function openDadosComplementares(row: Vec.Empresa): void {
    if (!row?.id) {
      return;
    }
    setEmpresaDadosRef(row);
    setEmpresaDadosMunicipio(
      row.municipio?.id
        ? { id: row.municipio.id, nome: row.municipio.nome ?? '' }
        : { id: '', nome: '' },
    );
    setEmpresaDadosForm({
      cnpj: '',
      endereco: '',
      email_contato: '',
      telefone: '',
      telefone2: '',
      data_abertura: '',
      data_encerramento: '',
      observacao: '',
    });
    setDadosComplementaresDialog(true);
    empresaDadosService
      .getByEmpresa(row.id)
      .then(({ data }) => {
        const mun = data?.municipio;
        setEmpresaDadosMunicipio(
          mun?.id ? { id: mun.id, nome: mun.nome ?? '' } : { id: '', nome: '' },
        );
        setEmpresaDadosForm({
          cnpj: data?.cnpj ?? '',
          endereco: data?.endereco ?? '',
          email_contato: data?.email_contato ?? '',
          telefone: data?.telefone ?? '',
          telefone2: data?.telefone2 ?? '',
          data_abertura: data?.data_abertura ?? '',
          data_encerramento: data?.data_encerramento ?? '',
          observacao: data?.observacao ?? '',
        });
      })
      .catch(() => {
        toast.current?.show({
          severity: 'error',
          summary: 'Erro',
          detail: 'Não foi possível carregar os dados complementares.',
          life: 3500,
        });
      });
  }

  function saveDadosComplementares(): void {
    if (!empresaDadosRef?.id || !podeEditarDadosComplementares) {
      return;
    }
    empresaDadosService
      .save({
        id: empresaDadosRef.id,
        municipio_id: (empresaDadosMunicipio?.id ?? '').trim(),
        cnpj: empresaDadosForm.cnpj,
        endereco: empresaDadosForm.endereco,
        email_contato: empresaDadosForm.email_contato,
        telefone: empresaDadosForm.telefone,
        telefone2: empresaDadosForm.telefone2,
        data_abertura: empresaDadosForm.data_abertura,
        data_encerramento: empresaDadosForm.data_encerramento,
        observacao: empresaDadosForm.observacao,
      })
      .then(() => {
        toast.current?.show({
          severity: 'success',
          summary: 'Sucesso',
          detail: 'Dados complementares gravados.',
          life: 3000,
        });
        setDadosComplementaresDialog(false);
        loadLazyEmpresa();
      })
      .catch((err) => {
        const msg =
          err?.response?.data?.error ??
          err?.response?.data?.message ??
          'Erro ao gravar dados complementares.';
        toast.current?.show({ severity: 'error', summary: 'Erro', detail: String(msg), life: 4500 });
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
          Cadastro (criar, alterar, excluir) é restrito a administradores. Use o ícone de livro na grade para dados complementares (município, contatos, etc.). Processo e compromissos em{' '}
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
    return (
      <>
        <span className="p-column-title">Rotina</span>
        {rowData.rotina?.descricao}
      </>
    );
  };

  const tipoEmpresaBodyTemplate = (rowData: Vec.Empresa) => {
    return (
      <>
        <span className="p-column-title">Tipo de Empresa</span>
        {rowData.tipo_empresa?.descricao ?? '—'}
      </>
    );
  };

  const template = {
    layout: 'PrevPageLink PageLinks NextPageLink RowsPerPageDropdown CurrentPageReport',
    'PrevPageLink': (options) => {
      return (
        <button type="button" className={options.className} onClick={options.onClick} disabled={options.disabled}>
          <span className="p-3">Página anterior</span>
        </button>
      )
    },
    'NextPageLink': (options) => {
      return (
        <button type="button" className={options.className} onClick={options.onClick} disabled={options.disabled}>
          <span className="p-3">Próxima página</span>
        </button>
      )
    },
    'PageLinks': (options) => {
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
    'RowsPerPageDropdown': (options) => {
      const dropdownOptions = [
        { label: 10, value: 10 },
        { label: 20, value: 20 },
        { label: 50, value: 50 }
      ];

      return <Dropdown value={options.value} options={dropdownOptions} onChange={options.onChange} />;
    },
    'CurrentPageReport': (options) => {
      return (
        <span className="mx-3" style={{ color: 'var(--text-color)', userSelect: 'none' }}>
          Página <InputText className="ml-1" value={currentPage.toString()} tooltip={pageInputTooltip} tooltipOptions={{ position: 'left' }}
            onKeyDown={(e) => onPageInputKeyDown(e, options)} onChange={onPageInputChange} />
        </span>
      )
    }
  };

  const actionBodyTemplate = (rowData: Vec.Empresa) => {
    return (
      <>
        <Button
          icon="pi pi-book"
          tooltip="Dados complementares"
          tooltipOptions={{ position: 'left' }}
          rounded
          severity="secondary"
          className="mr-2"
          onClick={() => openDadosComplementares(rowData)}
        />
        {podeCadastrarClientes ? (
          <>
            <Button icon="pi pi-pencil" tooltip='Alterar' tooltipOptions={{ position: 'left' }} rounded severity="success" className="mr-2" onClick={() => editEmpresa(rowData)} />
            <Button icon="pi pi-trash" tooltip='Excluir' tooltipOptions={{ position: 'left' }} rounded severity="warning" onClick={() => confirmDeleteEmpresa(rowData)} />
          </>
        ) : (
          <span className="text-500 text-sm ml-1">Cadastro restrito</span>
        )}
      </>
    );
  };

  const header = (
    <div className="flex flex-column md:flex-row md:justify-content-between md:align-items-center">
      <div>
        <h5 className="m-0">Cadastro de Clientes</h5>
        <p className="m-0 mt-1 text-600 text-sm">PJ: rotina e CNAEs. PF: CPF (sem rotina). Município e contatos nos dados complementares (ícone do livro). Processo e compromissos na Manutenção de Empresas.</p>
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

  const dadosComplementaresDialogFooter = (
    <>
      <Button label="Fechar" icon="pi pi-times" text onClick={() => setDadosComplementaresDialog(false)} />
      {podeEditarDadosComplementares && (
        <Button label="Salvar" icon="pi pi-check" text onClick={saveDadosComplementares} />
      )}
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
            paginatorTemplate={template}
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
            <Column field="rotina" header="Rotina" body={rotinaBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
            <Column field="tipo_empresa" header="Tipo de Empresa" body={tipoEmpresaBodyTemplate} headerStyle={{ minWidth: '12rem' }}></Column>
            <Column body={actionBodyTemplate} header="Ações" headerStyle={{ minWidth: '10rem' }}></Column>
          </DataTable>

          <Dialog visible={empresaDialog} style={{ width: '580px' }} header="Cliente (cadastro)" modal className="p-fluid" footer={empresaDialogFooter} onHide={hideDialog}>
            <div className="field">
              <label htmlFor="ddtipo_pessoa">Pessoa física ou jurídica</label>
              <Dropdown
                id="ddtipo_pessoa"
                value={isClientePF ? 'PF' : 'PJ'}
                options={tipoPessoaOptions}
                onChange={(e) => onTipoPessoaChange(e.value)}
                optionLabel="label"
                optionValue="value"
                disabled={empresa?.iniciado === true}
                className="w-full"
              />
            </div>

            <div className="field">
              <label htmlFor="nome_">Nome</label>
              <InputText id="nome_" value={empresa.nome} type='text' onChange={(e) => onInputChange(e, 'nome')} required autoFocus className={classNames({ 'p-invalid': submitted && !empresa.nome })} />
              {submitted && !empresa.nome && <small className="p-invalid">Nome do cliente é obrigatório.</small>}
            </div>

            <div className="field">
              <label htmlFor="documento_">{isClientePF ? 'CPF' : 'CNPJ (opcional)'}</label>
              <InputText
                id="documento_"
                value={empresa.documento ?? ''}
                type="text"
                onChange={(e) => onInputChange(e, 'documento')}
                disabled={empresa?.iniciado === true}
                className={classNames({ 'p-invalid': submitted && isClientePF && !(empresa.documento ?? '').trim() })}
                placeholder={isClientePF ? 'Obrigatório para PF' : 'Opcional; pode constar também nos dados complementares'}
              />
              {submitted && isClientePF && !(empresa.documento ?? '').trim() && (
                <small className="p-invalid">CPF é obrigatório para pessoa física.</small>
              )}
            </div>

            <div className="field">
              <label htmlFor="ddrotina">Rotina</label>
              <span className='p-float-label'>
                <Dropdown
                  id="ddrotina"
                  value={empresa.rotina}
                  options={rotinas}
                  onChange={(e) => onRotinaChange(e.value)}
                  optionLabel='lista_label'
                  dataKey='id'
                  placeholder={isClientePF ? 'Não aplicável a PF' : 'Selecione uma rotina (por município na descrição)'}
                  emptyMessage='Nenhuma Rotina encontrada'
                  disabled={empresa?.iniciado === true || isClientePF}
                />
                {submitted && !isClientePF && !(empresa.rotina?.id ?? '').trim() && (
                  <small className="p-invalid">Rotina é obrigatória para pessoa jurídica.</small>
                )}
              </span>
            </div>
            <div className="field">
              <label htmlFor="bairro_">Bairro</label>
              <InputText
                id="bairro_"
                value={empresa.bairro ?? ''}
                type="text"
                onChange={(e) => onInputChange(e, 'bairro')}
                disabled={empresa?.iniciado === true}
                placeholder="Obrigatório para compromissos por bairro (quando cadastrados)"
              />
            </div>
            <div className="p-fluid field">
              <label htmlFor="ddtag">CNAE's</label>
              <Chips
                id='ddtag'
                value={empresa.cnaes} onChange={handleCnaesChange}
                itemTemplate={(cnae: string) => (
                  <div className="p-d-flex p-ai-center p-flex-wrap">
                    <div className="p-mr-2">{cnae.replace(/(\d{2})(\d{2})(\d{1})(\d{2})/, '$1.$2-$3/$4')}</div>
                  </div>
                )}
                keyfilter="alphanum"
                disabled={empresa?.iniciado === true || isClientePF}
              />
              {isClientePF && <small className="text-600">CNAE's aplicam-se a pessoa jurídica.</small>}
            </div>

          </Dialog>

          <Dialog
            visible={dadosComplementaresDialog}
            style={{ width: '560px' }}
            header={
              empresaDadosRef?.nome
                ? `Dados complementares — ${empresaDadosRef.nome}`
                : 'Dados complementares'
            }
            modal
            className="p-fluid"
            footer={dadosComplementaresDialogFooter}
            onHide={() => setDadosComplementaresDialog(false)}
          >
            {!podeEditarDadosComplementares && (
              <p className="text-600 text-sm mb-3">
                Somente perfis Admin e Usuário alteram estes campos (perfil Super não mantém dados complementares).
              </p>
            )}
            <div className="field">
              <label htmlFor="ddmuncompl">Município</label>
              <Dropdown
                id="ddmuncompl"
                value={dadosComplMunicipioDropdownValue}
                options={municipios}
                onChange={(e) =>
                  setEmpresaDadosMunicipio(
                    e.value ? { id: e.value.id ?? '', nome: e.value.nome ?? '' } : { id: '', nome: '' },
                  )
                }
                optionLabel="nome"
                dataKey="id"
                placeholder="Selecione o município do cliente"
                emptyMessage="Nenhum município encontrado"
                disabled={!podeEditarDadosComplementares}
                className="w-full"
                showClear
              />
              <small className="text-600">Obrigatório para regras municipais, compromissos e processo operacional.</small>
            </div>
            <div className="field">
              <label htmlFor="edcnpj">CNPJ</label>
              <InputText
                id="edcnpj"
                value={empresaDadosForm.cnpj ?? ''}
                onChange={(e) => setEmpresaDadosForm((f) => ({ ...f, cnpj: e.target.value }))}
                disabled={!podeEditarDadosComplementares}
                className="w-full"
                maxLength={18}
              />
            </div>
            <div className="field">
              <label htmlFor="edendereco">Endereço</label>
              <InputTextarea
                id="edendereco"
                value={empresaDadosForm.endereco ?? ''}
                onChange={(e) => setEmpresaDadosForm((f) => ({ ...f, endereco: e.target.value }))}
                disabled={!podeEditarDadosComplementares}
                rows={3}
                className="w-full"
                autoResize
              />
            </div>
            <div className="field">
              <label htmlFor="edemail">E-mail de contato</label>
              <InputText
                id="edemail"
                type="email"
                value={empresaDadosForm.email_contato ?? ''}
                onChange={(e) => setEmpresaDadosForm((f) => ({ ...f, email_contato: e.target.value }))}
                disabled={!podeEditarDadosComplementares}
                className="w-full"
              />
            </div>
            <div className="formgrid grid">
              <div className="field col-12 md:col-6">
                <label htmlFor="edtel1">Telefone</label>
                <InputText
                  id="edtel1"
                  value={empresaDadosForm.telefone ?? ''}
                  onChange={(e) => setEmpresaDadosForm((f) => ({ ...f, telefone: e.target.value }))}
                  disabled={!podeEditarDadosComplementares}
                  className="w-full"
                  maxLength={40}
                />
              </div>
              <div className="field col-12 md:col-6">
                <label htmlFor="edtel2">Telefone 2</label>
                <InputText
                  id="edtel2"
                  value={empresaDadosForm.telefone2 ?? ''}
                  onChange={(e) => setEmpresaDadosForm((f) => ({ ...f, telefone2: e.target.value }))}
                  disabled={!podeEditarDadosComplementares}
                  className="w-full"
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
                  value={empresaDadosForm.data_abertura ?? ''}
                  disabled={!podeEditarDadosComplementares}
                  onChange={(e) =>
                    setEmpresaDadosForm((f) => ({ ...f, data_abertura: e.target.value }))
                  }
                />
              </div>
              <div className="field col-12 md:col-6">
                <label htmlFor="edenc">Data de encerramento</label>
                <input
                  id="edenc"
                  type="date"
                  className="p-inputtext p-component w-full"
                  value={empresaDadosForm.data_encerramento ?? ''}
                  disabled={!podeEditarDadosComplementares}
                  onChange={(e) =>
                    setEmpresaDadosForm((f) => ({ ...f, data_encerramento: e.target.value }))
                  }
                />
              </div>
            </div>
            <div className="field">
              <label htmlFor="edobs">Observações</label>
              <InputTextarea
                id="edobs"
                value={empresaDadosForm.observacao ?? ''}
                onChange={(e) => setEmpresaDadosForm((f) => ({ ...f, observacao: e.target.value }))}
                disabled={!podeEditarDadosComplementares}
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
