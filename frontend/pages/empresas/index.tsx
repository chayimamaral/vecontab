import { Button } from 'primereact/button';
import { Column } from 'primereact/column';
import { DataTable, DataTableFilterMeta } from 'primereact/datatable';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
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
import EmpresaCompromissoService from '../../services/cruds/EmpresaCompromissoService';
import { Chips } from "primereact/chips";

type ChipsChangeEvent<T> = {
  originalEvent: Event;
  value: T;
  target: {
    name: string;
    id: string;
    value: T;
  };
};

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
const Empresas = ({ dados }) => {

  const tenantid = dados

  let emptyEmpresa: Vec.Empresa = {
    id: '',
    nome: '',
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
    bairro: '',
    iniciado: false
  };

  let emptyMunicipio: Vec.MunicipioLite = {
    id: '',
    nome: ''
  }

  let emptyRotina: Vec.Rotina = {
    id: '',
    descricao: ''
  }

  const [empresas, setEmpresas] = useState([]);

  const [municipios, setMunicipios] = useState<Vec.MunicipioLite[]>([]);
  const [municipio, setMunicipio] = useState<Vec.MunicipioLite>(emptyMunicipio);

  const [rotinas, setRotinas] = useState<Vec.RotinaLite[]>([]);
  const [rotina, setRotina] = useState<Vec.RotinaLite>(emptyRotina);
  const [gerarCompromissosDialog, setGerarCompromissosDialog] = useState(false);
  const [dataBaseGeracao, setDataBaseGeracao] = useState(() => new Date().toISOString().slice(0, 10));

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
    const mid = municipio?.id?.trim?.() ?? '';
    if (mid) {
      loadLazyRotinasForMunicipio(municipio);
    } else {
      setRotinas([]);
    }
  }, [municipio]);

  useEffect(() => {
    loadLazyMunicipios();
    loadLazyEmpresa();
  }, []);

  const empresaService = EmpresaService();
  const empresaCompromissoService = EmpresaCompromissoService();

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

    empresa.cnaes = event.value;
    const cnae = empresa.cnaes[empresa.cnaes.length - 1];

    const isValid = await validaCnae(cnae);

    if (isValid) {
      setEmpresa({ ...empresa, cnaes: event.value });
    } else {
      empresa.cnaes.pop();
      setEmpresa({ ...empresa, cnaes: empresa.cnaes });
    }
  }

  const loadLazyMunicipios = () => {
    const municipioService = MunicipioService();
    municipioService.getMunicipiosLite().then(({ data }) => {
      setMunicipios(data?.municipios);
    })
  }

  /** Sempre passe o município explícito: evita race com setState (req. com id vazio sobrescrevendo a lista). */
  const loadLazyRotinasForMunicipio = (m: Vec.MunicipioLite) => {
    const rotinaService = RotinaService();
    const id = m?.id?.trim?.() ?? '';
    if (!id) {
      setRotinas([]);
      return;
    }
    rotinaService.getRotinasLite({ id }).then(({ data }) => {
      setRotinas(data?.rotinas ?? []);
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
    setMunicipio(emptyMunicipio);
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
      setLazyState({ ...lazyState, filters: { descricao: { value: '', matchMode: 'contains' } } });
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

  const saveEmpresa = (event: any) => {
    empresa.tenantid = tenantid;
    empresa.municipio = municipio;
    empresa.rotina = rotina;
    setSubmitted(true);
    if (empresa?.nome?.trim()) {
      let _empresa = { ...empresa };

      if (empresa.id) {
        empresaService.updateEmpresa(_empresa)
          .then(() => {
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Empresa Atualizada', life: 3000 });
          })
          .catch((error) => {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao atualizar a empresa', life: 3000 });
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
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Empresa Criada', life: 3000 });
          })
          .catch((error) => {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao criar a empresa', life: 3000 });
          })
          .finally(() => {
            //setLoading(false);
            setEmpresaDialog(false);
            setEmpresa(emptyEmpresa);
            loadLazyEmpresa();
          });
      }
    } else {
      if (empresa.nome === '') {
        toast.current?.show({ severity: 'warn', summary: 'Alerta', detail: 'Preencha o nome da empresa', life: 3000 });
      }
      if (empresa.municipio.id === '') {
        toast.current?.show({ severity: 'warn', summary: 'Alerta', detail: 'Selecione o município da empresa', life: 3000 });
      }
      if (empresa.rotina.id === '') {
        toast.current?.show({ severity: 'warn', summary: 'Alerta', detail: 'Selecione a rotina da empresa', life: 3000 });
      }
    }
    setSubmitted(false);
  };

  const editEmpresa = (empresa: Vec.Empresa) => {
    setMunicipio(empresa.municipio)
    setRotina(empresa.rotina)
    setEmpresa({
      ...empresa,
      municipio: empresa.municipio,
      rotina: empresa.rotina,
      bairro: empresa.bairro ?? '',
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
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Empresa Excluída', life: 3000 });
          })
          .catch((error) => {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao excluir a empresa', life: 5000 });
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

  function onMunicipioChange(selectedValue: Vec.MunicipioLite) {
    setMunicipio(selectedValue);
    setRotina(emptyRotina);
    setEmpresa((prev) => ({
      ...prev,
      municipio: selectedValue ?? { id: '', nome: '' },
      rotina: { id: '', descricao: '' },
      tipo_empresa: { id: '', descricao: '' },
    }));
    loadLazyRotinasForMunicipio(selectedValue ?? { id: '', nome: '' });
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
    return (
      <React.Fragment>
        <div className="my-2">
          <Button label="Criar" icon="pi pi-plus" severity="success" className=" mr-2" onClick={openNew} />
          {/* estou <Button label="Deletar" icon="pi pi-trash" severity="danger" onClick={confirmDeleteSelected} disabled={!selectedPassos || !selectedPassos.length} /> */}
        </div>
      </React.Fragment>
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
    return (
      <>
        <span className="p-column-title">Município</span>
        {rowData.municipio?.nome}
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

  function handleIniciarProcesso(empresa: Vec.Empresa): void {
    //esta função tornará 'iniciado = true' e, neste momento, internamente no BD
    //será disparado um trigger que acionará uma função para geração da agenda
    //de obrigações da empresa, incluindo os passos e calculando a data para
    //cada passo, de acordo com a data de início do processo, a saber, hoje (ou data atual).
    //após o início do processo, a única operação permitida será cancelar a
    //abertura da empresa e não será mais permitido alterar os dados da empresa.
    let _empresa = { ...empresa };

    if (_empresa.id) {
      empresaService.iniciarProcesso(_empresa)
        .then(() => {
          toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Processo Iniciado', life: 3000 });
        })
        .catch((error) => {
          toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao inicar processo', life: 3000 });
        })
        .finally(() => {
          //setLoading(false);
          setEmpresa(emptyEmpresa);
          loadLazyEmpresa();
        });
    }
  }

  function handleConcluirProcesso(empresa: Vec.Empresa): void {
    if (!empresa?.id) {
      return;
    }

    setEmpresa(empresa);
    setDataBaseGeracao(new Date().toISOString().slice(0, 10));
    setGerarCompromissosDialog(true);
  }

  function confirmarGerarCompromissos(): void {
    if (!empresa?.id) {
      toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Empresa inválida.', life: 3500 });
      return;
    }

    const inicio = (dataBaseGeracao || '').trim() || new Date().toISOString().slice(0, 10);

    empresaCompromissoService.gerar({
      empresa_id: empresa.id,
      data_inicio: inicio,
    })
      .then(({ data }) => {
        const qtd = data?.quantidade ?? data?.itens?.length ?? 0;
        toast.current?.show({
          severity: 'success',
          summary: 'Gerar Compromissos',
          detail: qtd > 0 ? `${qtd} compromissos gerados com sucesso.` : 'Nenhum compromisso foi gerado.',
          life: 4000,
        });
      })
      .catch(() => {
        toast.current?.show({
          severity: 'error',
          summary: 'Erro',
          detail: 'Erro ao gerar compromissos da empresa.',
          life: 4000,
        });
      })
      .finally(() => {
        setGerarCompromissosDialog(false);
        loadLazyEmpresa();
      });
  }


  const actionBodyTemplate = (rowData: Vec.Empresa) => {
    const isButtonDisabled = rowData?.iniciado === true;
    const isConcluirDisabled = rowData?.iniciado !== true || rowData?.passos_concluidos !== true || rowData?.compromissos_gerados === true;

    return (
      <>
        <Button icon="pi pi-pencil" tooltip='Alterar' tooltipOptions={{ position: 'left' }} rounded severity="success" className="mr-2" onClick={() => editEmpresa(rowData)} />
        <Button icon="pi pi-trash" tooltip='Excluir' tooltipOptions={{ position: 'left' }} rounded severity="warning" onClick={() => confirmDeleteEmpresa(rowData)} />
        <Button icon="pi pi-eye" tooltip='Iniciar Processo' tooltipOptions={{ position: 'left' }} rounded severity="info" disabled={isButtonDisabled} onClick={() => handleIniciarProcesso(rowData)} className="ml-2" />
        <Button icon="pi pi-check-circle" tooltip='Gerar Compromissos' tooltipOptions={{ position: 'left' }} rounded severity="help" disabled={isConcluirDisabled} onClick={() => handleConcluirProcesso(rowData)} className="ml-2" />
      </>
    );
  };

  const header = (
    <div className="flex flex-column md:flex-row md:justify-content-between md:align-items-center">
      <h5 className="m-0">Manutenção de Empresas</h5>
      <span className="block mt-2 md:mt-0 p-input-icon-left">
        <i className="pi pi-search" />
        <InputText type="search" onKeyDown={(e) => handleBuscaEmpresa(e, e.currentTarget.value)} onChange={handleClear} placeholder="Procurar Empresa..." tooltip='Digite o nome da Empresa e tecle Enter' tooltipOptions={{ position: 'left' }} />
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

  const gerarCompromissosDialogFooter = (
    <>
      <Button label="Cancelar" icon="pi pi-times" text onClick={() => setGerarCompromissosDialog(false)} />
      <Button
        label="Gerar"
        icon="pi pi-check"
        text
        disabled={!empresa?.tipo_empresa?.id}
        onClick={confirmarGerarCompromissos}
      />
    </>
  );

  const customChip = (item: string) => {
    if (item.length !== 7) {
      return "Formato Inválido"
    }
    const [n1, n2, n3, n4, n5, n6, n7] = item.split('');

    return (
      <div>
        <span>
          {n1}{n2}.{n3}{n4}-{n5}/{n6}{n7}
        </span>
      </div>
    );
  }

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
            emptyMessage="Nenhuma empresa encontrada."
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
            <Column field="municipio" header="Municipio" body={municipioBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
            <Column field="rotina" header="Rotina" body={rotinaBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
            <Column field="tipo_empresa" header="Tipo de Empresa" body={tipoEmpresaBodyTemplate} headerStyle={{ minWidth: '12rem' }}></Column>
            <Column body={actionBodyTemplate} header="Ações" headerStyle={{ minWidth: '10rem' }}></Column>
          </DataTable>

          <Dialog visible={empresaDialog} style={{ width: '550px' }} header="Detalhe da Empresa" modal className="p-fluid" footer={empresaDialogFooter} onHide={hideDialog}>
            <div className="field">
              <label htmlFor="nome_">Nome</label>
              <InputText id="nome_" value={empresa.nome} type='text' onChange={(e) => onInputChange(e, 'nome')} required autoFocus className={classNames({ 'p-invalid': submitted && !empresa.nome })} />
              {submitted && !empresa.nome && <small className="p-invalid">Descrição da Empresa é obrigatório.</small>}
            </div>

            <div className="field">
              <label htmlFor="ddmunicipio">Municipio</label>
              <span className='p-float-label'>
                <Dropdown
                  id="ddmunicipio"
                  value={empresa.municipio}
                  options={municipios}
                  onChange={(e) => onMunicipioChange(e.value)}
                  optionLabel='nome'
                  dataKey='id'
                  placeholder='Selecione um Município'
                  emptyMessage='Nenhum Município encontrado'
                  disabled={empresa?.iniciado === true}
                />
                {submitted && !empresa.municipio && <small className="p-invalid">Municipio do Feriado é obrigatório.</small>}
              </span>
            </div>
            <div className="field">
              <label htmlFor="ddrotina">Rotina</label>
              <span className='p-float-label'>
                <Dropdown
                  id="ddrotina"
                  value={empresa.rotina}
                  options={rotinas}
                  onChange={(e) => onRotinaChange(e.value)}
                  optionLabel='descricao'
                  dataKey='id'
                  placeholder='Selecione uma Rotina'
                  emptyMessage='Nenhuma Rotina encontrada'
                  disabled={empresa?.iniciado === true}
                />
                {submitted && !empresa.rotina && <small className="p-invalid">Rotina é obrigatório.</small>}
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
                keyfilter="alphanum" />
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
              Serão criados os compromissos legais (cadastro por tipo de empresa) aplicáveis ao município/UF/bairro desta empresa, com vencimentos ajustados a dias úteis e feriados.
              {!empresa?.tipo_empresa?.id?.trim() && ' Cadastre o tipo na rotina antes de gerar.'}
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
              <small className="block mt-1">Vencimentos mensais/anuais consideram fins de semana e feriados (ajuste automático).</small>
            </div>
          </Dialog>

        </div>
      </div>
    </div >
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
