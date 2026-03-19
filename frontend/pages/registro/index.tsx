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

    const loadLazyRegistro = async () => {
        try {
            const { dados } = await registroService.getRegistro(registro)
            setRegistro(dados);
        } catch (error) {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: 'Erro ao carregar os dados', life: 3000 });
        }
    }

    const onInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>, nome: string) => {

        const val = (e.target && e.target.value) || '';
        let _registro = { ...registro };
        _registro[`${nome}`] = val;

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
                            <InputText value={registro.razaosocial !== null ? registro.razaosocial : ''} onChange={(e) => onInputChange(e, 'razaosocial')} id="razaosocial_" type="text" />
                        </div>
                        <div className="field col-12 md:col-6">
                            <label htmlFor="fantasia_">Nome Fantasia</label>
                            <InputText value={registro.fantasia !== null ? registro.fantasia : ''} onChange={(e) => onInputChange(e, 'fantasia')} id="fantasia_" type="text" />
                        </div>
                        <div className="field col-12 md:col-6">
                            <label htmlFor="endereco_">Endereço</label>
                            <InputText value={registro.endereco !== null ? registro.endereco : ''} onChange={(e) => onInputChange(e, 'endereco')} id="endereco_" type="text" />
                        </div>
                        <div className="field col-12 md:col-6">
                            <label htmlFor="_bairro_">Bairro</label>
                            <InputText value={registro.bairro !== null ? registro.bairro : ''} onChange={(e) => onInputChange(e, 'bairro')} id="bairro_" type="text" />
                        </div>
                        <div className="field col-12 md:col-6">
                            <label htmlFor="cidade_">Cidade</label>
                            <InputText value={registro.cidade !== null ? registro.cidade : ''} onChange={(e) => onInputChange(e, 'cidade')} id="cidade_" type="text" />
                        </div>
                        <div className="field col-12 md:col-3">
                            <label htmlFor="estado_">Estado</label>
                            <InputText value={registro.estado !== null ? registro.estado : ''} onChange={(e) => onInputChange(e, 'estado')} id="estado_" type='text' />
                        </div>
                        <div className="field col-12 md:col-3">
                            <label htmlFor="cep_">CEP</label>
                            <InputText value={registro.cep !== null ? registro.cep : ''} onChange={(e) => onInputChange(e, 'cep')} id="cep_" type="text" />
                        </div>
                        <div className="field col-12 md:col-6">
                            <label htmlFor="telefone_">Telefone</label>
                            <InputText value={registro.telefone !== null ? registro.telefone : ''} onChange={(e) => onInputChange(e, 'telefone_')} id="telefone" type="text" />
                        </div>
                        <div className="field col-12 md:col-6">
                            <label htmlFor="email_">Email</label>
                            <InputText value={registro.email !== null ? registro.email : ''} onChange={(e) => onInputChange(e, 'email')} id="email_" type="text" />
                        </div>

                        <div className="field col-12 md:col-4">
                            <label htmlFor="cnpj_">CNPJ</label>
                            <InputText value={registro.cnpj !== null ? registro.cnpj : ''} onChange={(e) => onInputChange(e, 'cnpj')} id="cnpj_" type="text" />
                        </div>
                        <div className="field col-12 md:col-4">
                            <label htmlFor="ie_">Inscrição Estadual</label>
                            <InputText value={registro.ie !== null ? registro.ie : ''} onChange={(e) => onInputChange(e, 'ie')} id="ie_" type="text" />
                        </div>
                        <div className="field col-12 md:col-4">
                            <label htmlFor="im_">Inscrição Municipal</label>
                            <InputText value={registro.im !== null ? registro.im : ''} onChange={(e) => onInputChange(e, 'im')} id="im_" type="text" />
                        </div>
                        <div className="field col-12">
                            <label htmlFor="observacoes_">Observações</label>
                            <InputTextarea name='observacoes' value={registro.observacoes !== null ? registro.observacoes : ''} onChange={(e) => onInputChange(e, 'observacoes')} id="observacoes_" rows={4} />
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

export const getServerSideProps = withAuthServerSideProps(async (ctx) => {
    // Aqui não é necessário nenhum processamento adicional
});




