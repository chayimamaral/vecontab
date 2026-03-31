import React, { useContext, useEffect, useRef, useState } from 'react';
import { InputText } from 'primereact/inputtext';
import { Button } from 'primereact/button';

import { Toast } from 'primereact/toast';
import { Dropdown } from 'primereact/dropdown';

import { InputTextarea } from 'primereact/inputtextarea';
import RegistroService from '../../services/cruds/RegistroService';
import { withAuthServerSideProps } from '../../components/utils/crudUtils';

interface Registro {
    tenantid: string,
    razaosocial: string,
    fantasia: string,
    endereco: string,
    bairro: string,
    cidade: string,
    estado: string,
    cep: string,
    telefone: string,
    email: string,
    cnpj: string,
    ie: string,
    im: string,
    observacoes: string
}

interface RegistroProps {
    dados: Registro
}

function Registro({ dados }: RegistroProps) {

    const [dropdownItem, setDropdownItem] = useState(null);
    const toast = useRef<Toast>(null);
    const [isInvalid, setIsInvalid] = useState(false);

    const [registro, setRegistro] = useState<Registro>({
        tenantid: '',
        razaosocial: '',
        fantasia: '',
        endereco: '',
        bairro: '',
        cidade: '',
        estado: '',
        cep: '',
        telefone: '',
        email: '',
        cnpj: '',
        ie: '',
        im: '',
        observacoes: ''
    });

    const registroService = RegistroService();

    async function handleUpdateEmpresa() {
        registroService.gravaRegistro(registro)
        toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Dados atualizados com Sucesso', life: 3000 });
    }

    useEffect(() => {
        loadLazyRegistro()
    }, [])

    const toSafeString = (value: unknown): string => {
        if (value == null) return '';
        if (typeof value === 'string') return value;
        if (typeof value === 'number' || typeof value === 'boolean') return String(value);
        if (typeof value === 'object') {
            const maybeNullString = value as { String?: unknown; Valid?: unknown; string?: unknown; valid?: unknown };
            if (typeof maybeNullString.String === 'string') {
                const isValid = typeof maybeNullString.Valid === 'boolean' ? maybeNullString.Valid : true;
                return isValid ? maybeNullString.String : '';
            }
            if (typeof maybeNullString.string === 'string') {
                const isValid = typeof maybeNullString.valid === 'boolean' ? maybeNullString.valid : true;
                return isValid ? maybeNullString.string : '';
            }
        }
        return '';
    };

    const normalizeRegistro = (raw: any): Registro => ({
        tenantid: toSafeString(raw?.tenantid),
        razaosocial: toSafeString(raw?.razaosocial),
        fantasia: toSafeString(raw?.fantasia),
        endereco: toSafeString(raw?.endereco),
        bairro: toSafeString(raw?.bairro),
        cidade: toSafeString(raw?.cidade),
        estado: toSafeString(raw?.estado),
        cep: toSafeString(raw?.cep),
        telefone: toSafeString(raw?.telefone),
        email: toSafeString(raw?.email),
        cnpj: toSafeString(raw?.cnpj),
        ie: toSafeString(raw?.ie),
        im: toSafeString(raw?.im),
        observacoes: toSafeString(raw?.observacoes),
    });

    const loadLazyRegistro = async () => {
        try {
            const { dados } = await registroService.getRegistro(registro)
            setRegistro(normalizeRegistro(dados));
        } catch (error) {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao carregar os dados', life: 3000 });
        }
    }

    const onInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>, nome: keyof Registro) => {

        const val = (e.target && e.target.value) || '';
        let _registro = { ...registro };
        _registro[nome] = val;

        setRegistro(_registro);

    }

    return (
        <div className="grid">
            <div className="col-12">
                <div className="card">
                    <h5>Dados da Empresa</h5>
                    <div className="p-fluid formgrid grid">
                        <div className="field col-12 md:col-6">
                            <label htmlFor="razaosocial_">Razão Social</label>
                            <InputText value={registro.razaosocial ?? ''} onChange={(e) => onInputChange(e, 'razaosocial')} id="razaosocial_" type="text" />
                        </div>
                        <div className="field col-12 md:col-6">
                            <label htmlFor="fantasia_">Nome Fantasia</label>
                            <InputText value={registro.fantasia ?? ''} onChange={(e) => onInputChange(e, 'fantasia')} id="fantasia_" type="text" />
                        </div>
                        <div className="field col-12 md:col-6">
                            <label htmlFor="endereco_">Endereço</label>
                            <InputText value={registro.endereco ?? ''} onChange={(e) => onInputChange(e, 'endereco')} id="endereco_" type="text" />
                        </div>
                        <div className="field col-12 md:col-6">
                            <label htmlFor="_bairro_">Bairro</label>
                            <InputText value={registro.bairro ?? ''} onChange={(e) => onInputChange(e, 'bairro')} id="bairro_" type="text" />
                        </div>
                        <div className="field col-12 md:col-6">
                            <label htmlFor="cidade_">Cidade</label>
                            <InputText value={registro.cidade ?? ''} onChange={(e) => onInputChange(e, 'cidade')} id="cidade_" type="text" />
                        </div>
                        <div className="field col-12 md:col-3">
                            <label htmlFor="estado_">Estado</label>
                            <InputText value={registro.estado ?? ''} onChange={(e) => onInputChange(e, 'estado')} id="estado_" type='text' />
                        </div>
                        <div className="field col-12 md:col-3">
                            <label htmlFor="cep_">CEP</label>
                            <InputText value={registro.cep ?? ''} onChange={(e) => onInputChange(e, 'cep')} id="cep_" type="text" />
                        </div>
                        <div className="field col-12 md:col-6">
                            <label htmlFor="telefone_">Telefone</label>
                            <InputText value={registro.telefone ?? ''} onChange={(e) => onInputChange(e, 'telefone')} id="telefone" type="text" />
                        </div>
                        <div className="field col-12 md:col-6">
                            <label htmlFor="email_">Email</label>
                            <InputText value={registro.email ?? ''} onChange={(e) => onInputChange(e, 'email')} id="email_" type="text" />
                        </div>

                        <div className="field col-12 md:col-4">
                            <label htmlFor="cnpj_">CNPJ</label>
                            <InputText value={registro.cnpj ?? ''} onChange={(e) => onInputChange(e, 'cnpj')} id="cnpj_" type="text" />
                        </div>
                        <div className="field col-12 md:col-4">
                            <label htmlFor="ie_">Inscrição Estadual</label>
                            <InputText value={registro.ie ?? ''} onChange={(e) => onInputChange(e, 'ie')} id="ie_" type="text" />
                        </div>
                        <div className="field col-12 md:col-4">
                            <label htmlFor="im_">Inscrição Municipal</label>
                            <InputText value={registro.im ?? ''} onChange={(e) => onInputChange(e, 'im')} id="im_" type="text" />
                        </div>
                        <div className="field col-12">
                            <label htmlFor="observacoes_">Observações</label>
                            <InputTextarea name='observacoes' value={registro.observacoes ?? ''} onChange={(e) => onInputChange(e, 'observacoes')} id="observacoes_" rows={4} />
                        </div>

                        <div className="field col-12 md:col-12">
                            <Toast ref={toast} />
                            <Button label="Gravar" onClick={handleUpdateEmpresa}></Button>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default Registro;

export const getServerSideProps = withAuthServerSideProps(async () => {
    // Aqui não é necessário nenhum processamento adicional
});




