import { Button } from 'primereact/button';
import { Column } from 'primereact/column';
import { DataTable, DataTableFilterMeta } from 'primereact/datatable';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
import { Toast } from 'primereact/toast';
import { Toolbar } from 'primereact/toolbar';
import { classNames } from 'primereact/utils';
import React, { SyntheticEvent, lazy, useEffect, useRef, useState } from 'react';
import { Vec } from '../../types/types';

import { Dropdown } from 'primereact/dropdown';
import UsuarioService from '../../services/cruds/UsuarioService';
import EmptyPage from '../pages/empty';
import { withAuthServerSideProps } from '../../components/utils/crudUtils';
import { ct } from '@fullcalendar/core/internal-common';
import { RadioButton, RadioButtonChangeEvent } from 'primereact/radiobutton';

interface Role {
  descricao: string;
  code: string;
}

interface Logado {
  id: string;
  email: string;
  role: string;
  tenantid: string;

}

interface LazyTableState {
  totalRecords: number;
  first: number;
  rows: number;
  page: number;
  sortField?: string;
  sortOrder?: number;
  filters: DataTableFilterMeta;
}

const Usuarios = ({ user_id }) => {

  let emptyUsuario: Vec.Usuarios = {
    id: '',
    nome: '',
    email: '',
    password: '',
    role: '',
    tenantid: '',
    active: false
  }

  const [usuarios, setUsuarios] = useState([]);
  const [usuario, setUsuario] = useState<Vec.Usuarios>(emptyUsuario);

  const [usuarioDialog, setUsuarioDialog] = useState(false);
  const [deleteUsuarioDialog, setDeleteUsuarioDialog] = useState(false);

  const [currentPage, setCurrentPage] = useState(1);
  const [totalRecords, setTotalRecords] = useState<number>(0);
  const [sortOrder, setSortOrder] = useState(1);
  const [sortField, setSortField] = useState('nome');
  const [first, setFirst] = useState(0);
  const [rows, setRows] = useState(20);
  const [loading, setLoading] = useState<boolean>(false);
  const toast = useRef<Toast>(null);
  const [pageInputTooltip, setPageInputTooltip] = useState('');
  const [submitted, setSubmitted] = useState(false);
  const [globalFilter, setGlobalFilter] = useState<string>('');
  const [acao, setAcao] = useState<string>('');
  const [novaSenha, setNovaSenha] = useState<string>('');
  const [confirmSenha, setConfirmSenha] = useState<string>('');

  const [logado, setLogado] = useState<Logado>();

  const [lazyState, setLazyState] = useState<LazyTableState>({
    totalRecords: totalRecords,
    first: first,
    rows: rows,
    page: currentPage,
    sortField: '',
    sortOrder: 1,
    filters: {
      nome: { value: '', matchMode: 'contains' },
      email: { value: '', matchMode: 'contains' },
    }
  });

  const roles = [
    { name: 'Administrador', key: 'ADMIN' },
    { name: 'Usuário', key: 'USER' }
  ];

  const [selectedRole, setSelectedRole] = useState(roles[1]);

  useEffect(() => {
    loadLazyLogado();
    loadLazyUsuario();
  }, [lazyState]);

  const usuarioService = UsuarioService();

  const loadLazyUsuario = () => {
    setLoading(true);
    usuarioService.getUsuarios({ lazyEvent: JSON.stringify(lazyState) }).then(({ data }) => {
      setUsuarios(data.usuarios);
      setTotalRecords(data.totalRecords);
    })
      .catch((error) => {
        toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao carregar usuários', life: 3000 });
      })
      .finally(() => setLoading(false));
  }

  const loadLazyLogado = () => {
    //setLoading(true);
    usuarioService.getUserRole(user_id).then(({ data }) => {
      setLogado(data.logado);
    })
  }

  const paginatorLeft = <Button type="button" icon="pi pi-refresh" tooltip='Atualizar' className="p-button-text" onClick={loadLazyUsuario} />;

  const onPage = (event) => {
    setFirst(event.first);
    setRows(event.rows);
    setCurrentPage(event.page + 1);
    setSortOrder(event.sortOrder);
    setSortField(event.sortField);
    setLazyState({ ...lazyState, first: event.first, rows: event.rows, page: event.page + 1, sortField: event.sortField, sortOrder: event.sortOrder });
    setLazyState(event)
  }

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
          Página <InputText className="ml-1" value={currentPage.toString()} tooltip={pageInputTooltip}
            onKeyDown={(e) => onPageInputKeyDown(e, options)} onChange={onPageInputChange} />
        </span>
      )
    }
  };

  const onSort = (event) => {
    setLazyState(event);
  }

  const onFilter = (event) => {
    event['first'] = 0;
    setLazyState(event)
  };

  const openNew = () => {
    setAcao('Novo')
    setUsuario(emptyUsuario);
    setSubmitted(false);
    setUsuarioDialog(true);
  };

  const hideDialog = () => {
    setSubmitted(false);
    setUsuarioDialog(false);
  };

  const hideDeleteUsuarioDialog = () => {
    setDeleteUsuarioDialog(false);
  };

  function handleBuscaUsuario(event, value: string): void {
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

  const saveUsuario = (event) => {
    setSubmitted(true);

    if (usuario?.nome?.trim()) {
      let _usuario = { ...usuario };

      if (usuario.id) {
        usuarioService.updateUsuario(_usuario)
          .then(() => {
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Usuário atualizado', life: 3000 });
          })
          .catch((error) => {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao atualizar o usuário', life: 3000 });
          })
          .finally(() => {
            //setLoading(false);
            setUsuarioDialog(false);
            setUsuario(emptyUsuario);
            loadLazyUsuario();
          });
      } else {
        _usuario.tenantid = logado?.tenantid;
        _usuario.active = true;
        //_usuario.role = 'USER';
        _usuario.password = '123456';
        usuarioService.createUsuario(_usuario)
          .then((response) => {
            if (response && response.data) {
              setUsuarios(response.data.usuarios);
              setTotalRecords(response.data.totalRecords);
            }
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Usuário criado', life: 3000 });
          })
          .catch((error) => {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao criar o usuário', life: 3000 });
          })
          .finally(() => {
            //setLoading(false);
            setUsuarioDialog(false);
            setUsuario(emptyUsuario);
            loadLazyUsuario();
          });
      }
    }
    setSubmitted(false);
  };

  const editUsuario = (usuario: Vec.Usuarios) => {
    setAcao('Editar')
    setUsuario({ ...usuario });
    setUsuarioDialog(true);
  };

  const senhaUsuario = (usuario: Vec.Usuarios) => {
    setAcao('Senha')
    setUsuario({ ...usuario });
    setUsuarioDialog(true);
  };

  const confirmDeleteUsuario = (usuario: Vec.Usuarios) => {
    setUsuario(usuario);
    setDeleteUsuarioDialog(true);
  };

  const deleteUsuario = (event) => {
    setSubmitted(true);

    if (usuario?.nome?.trim()) {
      let _usuario = { ...usuario };

      if (usuario.id) {
        usuarioService.deleteUsuario(_usuario)
          .then(() => {
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Usuário excluído', life: 3000 });
          })
          .catch((error) => {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao excluir o usuário', life: 5000 });
          })
          .finally(() => {
            setDeleteUsuarioDialog(false);
            setUsuario(emptyUsuario);
            loadLazyUsuario();
          });
      }
    }
  };

  const onInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>, nome: string) => {
    const val = (e.target && e.target.value) || '';
    let _usuario = { ...usuario };
    _usuario[`${nome}`] = val;

    setUsuario(_usuario);
  };

  function onRoleChange(e: RadioButtonChangeEvent, role: string): void {
    let _usuario = { ...usuario };
    setSelectedRole(e.value);
    _usuario[`${role}`] = e.value;

    setUsuario(_usuario);
  }

  const leftToolbarTemplate = () => {
    if (logado?.role == 'ADMIN') {
      return (
        <React.Fragment>
          <div className="my-2">
            <Button label="Criar" icon="pi pi-plus" severity="success" className=" mr-2" onClick={openNew} />
            {/* estou <Button label="Deletar" icon="pi pi-trash" severity="danger" onClick={confirmDeleteSelected} disabled={!selectedEstados || !selectedEstados.length} /> */}
          </div>
        </React.Fragment>
      );
    }
  };

  const emailBodyTemplate = (rowData: Vec.Usuarios) => {
    return (
      <>
        <span className="p-column-title">Email</span>
        {rowData.email}
      </>
    );
  };

  const nomeBodyTemplate = (rowData: Vec.Usuarios) => {
    return (
      <>
        <span className="p-column-title">Nome</span>
        {rowData.nome}
      </>
    );
  };

  const actionBodyTemplate = (rowData: Vec.Usuarios) => {
    return (
      <>
        <Button icon="pi pi-pencil" rounded severity="success" tooltip='Editar Usuário' tooltipOptions={{ position: 'left' }} className="mr-2" onClick={() => editUsuario(rowData)} />
        <Button icon='pi pi-user-edit' rounded severity="info" tooltip='Alterar sua Senha' tooltipOptions={{ position: 'left' }} className="mr-2" onClick={() => senhaUsuario(rowData)} />
        <Button icon="pi pi-trash" rounded severity="warning" tooltip='Excluir Usuário' tooltipOptions={{ position: 'left' }} onClick={() => confirmDeleteUsuario(rowData)} />
      </>
    );
  };

  const header = (
    <div className="flex flex-column md:flex-row md:justify-content-between md:align-items-center">
      <h5 className="m-0">Cadastro de Usuários</h5>
      <span className="block mt-2 md:mt-0 p-input-icon-left">
        <i className="pi pi-search" />
        <InputText type="search" onKeyDown={(e) => handleBuscaUsuario(e, e.currentTarget.value)} onChange={handleClear} placeholder="Procurar Usuário..." tooltip='Digite o Usuário e tecle Enter' tooltipOptions={{ position: 'left' }} />
      </span>
    </div>
  );

  const usuarioDialogFooter = (
    <>
      <Button label="Cancelar" icon="pi pi-times" text onClick={hideDialog} />
      <Button label="Salvar" icon="pi pi-check" text onClick={saveUsuario} />
    </>
  );

  const deleteUsuarioDialogFooter = (
    <>
      <Button label="Não" icon="pi pi-times" text onClick={hideDeleteUsuarioDialog} />
      <Button label="Sim" icon="pi pi-check" text onClick={deleteUsuario} />
    </>
  );

  return (
    <div className="grid crud-demo">
      <div className="col-12">
        <div className="card">
          <Toast ref={toast} />
          <Toolbar className="mb-4" left={leftToolbarTemplate}></Toolbar>
          <DataTable
            value={usuarios}
            lazy
            dataKey="id"
            paginator
            rows={rows}
            rowsPerPageOptions={[10, 20, 30]}
            className="datatable-responsive"
            paginatorTemplate={template}
            globalFilter={globalFilter}
            emptyMessage="Nenhum Usuário encontrado."
            header={header}
            size="small"
            stripedRows
            filterDisplay='row'
            first={lazyState.first}
            onPage={onPage}
            onSort={onSort}
            sortField={lazyState.sortField}
            //atenção para o padrão abaixo...sempre tem que ser assim senão não funcionayk
            sortOrder={(lazyState.sortOrder === 1) ? 1 : -1}
            onFilter={onFilter}
            loading={loading}
            totalRecords={totalRecords}
            paginatorLeft={paginatorLeft}
          >
            <Column field="nome" header="Nome" sortable body={nomeBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
            <Column field="email" header="Email" sortable body={emailBodyTemplate} headerStyle={{ minWidth: '15rem' }}></Column>
            <Column body={actionBodyTemplate} headerStyle={{ minWidth: '10rem' }}></Column>
          </DataTable>

          <Dialog visible={usuarioDialog} style={{ width: '450px' }} header="Detalhe do Usuário" modal className="p-fluid" footer={usuarioDialogFooter} onHide={hideDialog}>

            <div className="field">
              <label htmlFor="nome_">Nome</label>
              <InputText id="nome_" value={usuario.nome} type='text' onChange={(e) => onInputChange(e, 'nome')} required autoFocus className={classNames({ 'p-invalid': submitted && !usuario.nome })} />
              {submitted && !usuario.nome && <small className="p-invalid">Nome do Usuário é obrigatório.</small>}
            </div>
            <div className="field">
              <label htmlFor="email_">Email</label>
              <InputText id="email_" value={usuario.email} type='text' onChange={(e) => onInputChange(e, 'email')} required className={classNames({ 'p-invalid': submitted && !usuario.email })} />
              {submitted && !usuario.email && <small className="p-invalid">Email do Usuário é obrigatório.</small>}
            </div>
            <div className="flex flex-wrap gap-3">
              <label htmlFor="role">Permissão :  </label>
              {roles.map((role) => {
                return (
                  <div key={role.key} className="flex align-items-center">
                    <RadioButton inputId={role.key} name="role" value={role.key} onChange={(e) => onRoleChange(e, 'role')} checked={usuario.role === role.key} />
                    <label htmlFor={role.key} className="ml-2">{role.name}</label>
                  </div>
                );
              })}
            </div>
            {acao === 'Senha' && (
              <div className="field">
                <label htmlFor="password_">Senha Atual</label>
                <InputText id="password_" value={usuario.password} type='password' onChange={(e) => onInputChange(e, 'password')} required className={classNames({ 'p-invalid': submitted && !usuario.password })} />
                {submitted && !usuario.password && <small className="p-invalid">Senha do Usuário é obrigatório.</small>}
              </div>
            )}
            {acao === 'Senha' && (
              <div className="field">
                <label htmlFor="novasenha_">Nova Senha</label>
                <InputText id="novasenha_" value={novaSenha} type='password' onChange={(e) => onInputChange(e, 'novaSenha')} required className={classNames({ 'p-invalid': submitted && !novaSenha })} />
                {submitted && !novaSenha && <small className="p-invalid">Senha do Usuário é obrigatório.</small>}
              </div>
            )}
            {acao === 'Senha' && (
              <div className="field">
                <label htmlFor="confirmarsenha_">Confirmar Senha</label>
                <InputText id="confirmarsenha_" value={confirmSenha} type='password' onChange={(e) => onInputChange(e, 'confirmSenha')} required className={classNames({ 'p-invalid': submitted && !confirmSenha })} />
                {submitted && !confirmSenha && <small className="p-invalid">Senha do Usuário é obrigatório.</small>}
              </div>
            )}
          </Dialog>

          <Dialog visible={deleteUsuarioDialog} style={{ width: '450px' }} header="Confirma a exclusão ?" modal footer={deleteUsuarioDialogFooter} onHide={hideDeleteUsuarioDialog} className="red-header">
            <div className="flex align-items-center justify-content-center">
              <i className="pi pi-exclamation-triangle mr-3" style={{ fontSize: '2rem', color: '#d6551e' }} />
              {usuario && (
                <span>
                  Tem certeza que quer deletar <b>{usuario.nome}</b>?
                </span>
              )}
            </div>
          </Dialog>

        </div>
      </div>
    </div>
  );
};

export default Usuarios;


export const getServerSideProps = withAuthServerSideProps(async (ctx) => {
  // Aqui não é necessário nenhum processamento adicional
  const user_id = ctx.req.cookies.user_id;

  return {
    props: {
      user_id,
    },
  };
});