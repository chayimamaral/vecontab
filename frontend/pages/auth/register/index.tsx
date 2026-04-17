/* eslint-disable @next/next/no-img-element */

import { useRouter } from 'next/router';
import React, { useContext, useState, useRef } from 'react';
import AppConfig from '../../../layout/AppConfig';
import { Checkbox } from 'primereact/checkbox';
import { Button } from 'primereact/button';
import { Password } from 'primereact/password';
import { LayoutContext } from '../../../layout/context/layoutcontext';
import { InputText } from 'primereact/inputtext';
import { classNames } from 'primereact/utils';
import { Page } from '../../../types/types';

import AuthContext  from "../../../components/context/AuthContext";
import { Toast } from 'primereact/toast';
import Link from 'next/link';

export const RegisterPage: Page = () => {
    const [password, setPassword] = useState('');
    const [email, setEmail] = useState('');
    const [nome, setNome] = useState('');
    const [checked, setChecked] = useState(false);
    const [empresaNome, setEmpresaNome] = useState('');
    const { layoutConfig } = useContext(LayoutContext);
    const { signUp } = useContext(AuthContext);
    const toast = useRef<Toast>(null);
    const [isInvalid, setIsInvalid] = useState(false);

    const router = useRouter();
    const containerClassName = classNames('surface-ground flex align-items-center justify-content-center min-h-screen min-w-screen overflow-hidden', { 'p-input-filled': layoutConfig.inputStyle === 'filled' });

    async function handleRegister() {

        if (!nome || !email || !password || !empresaNome) {
            setIsInvalid(true);
            toast?.current?.show({ severity: 'error', summary: 'Erro', detail: 'Preencha todos os campos!', life: 3000 });
            return;
        }

        try {
        const created = await signUp({
            nome,
            email,
            password,
            empresa_nome: empresaNome.trim(),
        })

        toast?.current?.show({
            severity: 'success',
            summary: 'Sucesso',
            detail: `Conta criada. Tenant: ${created.tenantid || 'n/d'} | Schema: ${created.tenant_schema || 'n/d'}`,
            life: 5000
        });
        } catch (err) {
            setIsInvalid(true);
            const message = err instanceof Error ? err.message : 'Erro ao criar conta';
            toast?.current?.show({ severity: 'error', summary: 'Erro', detail: message, life: 3500 });
            return;
        }
    }

    return (
        <div className={containerClassName}>
            <div className="flex flex-column align-items-center justify-content-center">
                <img src={`/layout/images/vecontab-${layoutConfig.colorScheme === 'light' ? 'dark' : 'white'}.svg`} alt="VECONTAB logo" className="mb-5 w-6rem flex-shrink-0" />
                <div style={{ borderRadius: '56px', padding: '0.3rem', background: 'linear-gradient(180deg, var(--primary-color) 10%, rgba(33, 150, 243, 0) 30%)' }}>
                    <div className="w-full surface-card py-8 px-5 sm:px-8" style={{ borderRadius: '53px' }}>
                        <div className="text-center mb-5">

                            <div className="text-900 text-3xl font-medium mb-3">

                                VECONTAB</div>
                            <span className="text-600 font-medium">Crie sua conta no VECONTAB!</span>
                        </div>
                        <div>
                            <label htmlFor="nome1" className="block text-900 text-xl font-medium mb-2">
                                Nome
                            </label>
                            <InputText id="nome1" value={nome} onChange={(e) => setNome(e.target.value)} type="text" placeholder="Nome" className={`w-full md:w-30rem mb-5 ${isInvalid ? 'p-invalid' : ''}`} style={{ padding: '1rem' }} />

                            <label htmlFor="email1" className="block text-900 text-xl font-medium mb-2">
                                Email
                            </label>
                            <InputText id="email1" value={email} onChange={(e) => setEmail(e.target.value)} type="text" placeholder="Email" className={`w-full md:w-30rem mb-5 ${isInvalid ? 'p-invalid' : ''}`} style={{ padding: '1rem' }} />

                            <label htmlFor="empresaNome1" className="block text-900 text-xl font-medium mb-2">
                                Empresa/Escritório
                            </label>
                            <InputText
                                id="empresaNome1"
                                value={empresaNome}
                                onChange={(e) => setEmpresaNome(e.target.value)}
                                type="text"
                                placeholder="ex: Vec Contabilidade"
                                className={`w-full md:w-30rem mb-5 ${isInvalid ? 'p-invalid' : ''}`}
                                style={{ padding: '1rem' }}
                            />

                            <label htmlFor="password1" className="block text-900 font-medium text-xl mb-2">
                                Senha
                            </label>
                            <Password inputId="password1" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Senha" toggleMask className={`w-full md:w-30rem mb-5 ${isInvalid ? 'p-invalid' : ''}`} inputClassName="w-full p-3 md:w-30rem"></Password>

                            <div className="flex align-items-center justify-content-between mb-5 gap-5">
  
                                <a className="font-medium no-underline ml-2 text-center cursor-pointer" style={{ color: 'var(--primary-color)' }}>
                                    Já possui conta ? Faça login  <Link href='/auth/login'><strong> aqui</strong></Link>
                                </a>
                            </div>
                            
                                <div className="card flex justify-content-center">
                                    <Toast ref={toast} />
                                    <Button label="Acessar" className="w-full p-3 text-xl" onClick={handleRegister}></Button>
                                </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
};

RegisterPage.getLayout = function getLayout(page) {
    return (
        <React.Fragment>
            {page}
            <AppConfig simple />
        </React.Fragment>
    );
};

export default RegisterPage;