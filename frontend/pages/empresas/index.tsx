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
import EmpresaService from '../../services/cruds/EmpresaService';
import EmpresaCompromissoService from '../../services/cruds/EmpresaCompromissoService';
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
    iniciado: false,
    passos_concluidos: false,
    compromissos_gerados: false,
  };

  const [empresas, setEmpresas] = useState([]);

  const [gerarCompromissosDialog, setGerarCompromissosDialog] = useState(false);
  const [dataBaseGeracao, setDataBaseGeracao] = useState(() => new Date().toISOString().slice(0, 10));

  const [empresa, setEmpresa] = useState<Vec.Empresa>(emptyEmpresa);
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

  const leftToolbarTemplate = () => {
    return (
      <p className="text-600 m-0 text-sm">
        Cadastro de clientes e dados complementares (município, contatos) em{' '}
        <strong>Operações → Cadastros Operacionais → Clientes</strong>.
      </p>
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
        <Button icon="pi pi-eye" tooltip='Iniciar Processo' tooltipOptions={{ position: 'left' }} rounded severity="info" disabled={isButtonDisabled} onClick={() => handleIniciarProcesso(rowData)} className="ml-2" />
        <Button icon="pi pi-check-circle" tooltip='Gerar Compromissos' tooltipOptions={{ position: 'left' }} rounded severity="help" disabled={isConcluirDisabled} onClick={() => handleConcluirProcesso(rowData)} className="ml-2" />
      </>
    );
  };

  const header = (
    <div className="flex flex-column md:flex-row md:justify-content-between md:align-items-center">
      <div>
        <h5 className="m-0">Manutenção de Empresas</h5>
        <p className="m-0 mt-1 text-600 text-sm">Processo e compromissos. Cadastro e dados complementares em Clientes.</p>
      </div>
      <span className="block mt-2 md:mt-0 p-input-icon-left">
        <i className="pi pi-search" />
        <InputText type="search" onKeyDown={(e) => handleBuscaEmpresa(e, e.currentTarget.value)} onChange={handleClear} placeholder="Procurar por nome..." tooltip='Digite o nome e tecle Enter' tooltipOptions={{ position: 'left' }} />
      </span>
    </div>
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
