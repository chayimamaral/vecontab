/* eslint-disable @next/next/no-img-element */
import React, { useRef, useState } from 'react';
import Link from 'next/link';

import { StyleClass } from 'primereact/styleclass';
import { Button } from 'primereact/button';
import { Ripple } from 'primereact/ripple';
import { Divider } from 'primereact/divider';
import AppConfig from '../../../layout/AppConfig';
import { NodeRef, Page } from '../../../types/types';
import { classNames } from 'primereact/utils';

const LandingPage: Page = () => {
    const [isHidden, setIsHidden] = useState(false);
    const menuRef = useRef<HTMLElement | null>(null);

    const toggleMenuItemClick = () => {
        setIsHidden((prevState) => !prevState);
    };

    return (
        <div className="surface-0 flex justify-content-center">
            <div id="home" className="landing-wrapper overflow-hidden">
                <div className="py-4 px-4 mx-0 md:mx-6 lg:mx-8 lg:px-8 flex align-items-center justify-content-between relative lg:static">
                    <Link href="/" className="flex align-items-center">
                        <img src="/vecontab.svg" alt="Vecontab Logo" height="50" className="mr-0 lg:mr-2" />
                        <span className="font-medium text-2xl line-height-3 mr-8" style={{ color: '#6d98e9' }}>VECONTAB</span>
                    </Link>
                    <StyleClass nodeRef={menuRef as NodeRef} selector="@next" enterClassName="hidden" leaveToClassName="hidden" hideOnOutsideClick>
                        <i ref={menuRef} className="pi pi-bars text-4xl cursor-pointer block lg:hidden text-700"></i>
                    </StyleClass>
                    <div className={classNames('align-items-center surface-0 flex-grow-1 justify-content-between hidden lg:flex absolute lg:static w-full left-0 px-6 lg:px-0 z-2', { hidden: isHidden })} style={{ top: '100%' }}>
                        <ul className="list-none p-0 m-0 flex lg:align-items-center select-none flex-column lg:flex-row cursor-pointer">
                            <li>
                                <a href="#home" onClick={toggleMenuItemClick} className="p-ripple flex m-0 md:ml-5 px-0 py-3 text-900 font-medium line-height-3">
                                    <span>Início</span>
                                    <Ripple />
                                </a>
                            </li>
                            <li>
                                <a href="#features" onClick={toggleMenuItemClick} className="p-ripple flex m-0 md:ml-5 px-0 py-3 text-900 font-medium line-height-3">
                                    <span>Funcionalidades</span>
                                    <Ripple />
                                </a>
                            </li>
                            <li>
                                <a href="#highlights" onClick={toggleMenuItemClick} className="p-ripple flex m-0 md:ml-5 px-0 py-3 text-900 font-medium line-height-3">
                                    <span>Diferenciais</span>
                                    <Ripple />
                                </a>
                            </li>
                            <li>
                                <a href="#pricing" onClick={toggleMenuItemClick} className="p-ripple flex m-0 md:ml-5 px-0 py-3 text-900 font-medium line-height-3">
                                    <span>Preços</span>
                                    <Ripple />
                                </a>
                            </li>
                        </ul>
                        <div className="flex justify-content-between lg:block border-top-1 lg:border-top-none surface-border py-3 lg:py-0 mt-3 lg:mt-0">
                            <Link href="/auth/login">
                                <Button label="Login" text rounded className="border-none font-light line-height-2 text-blue-500"></Button>
                            </Link>
                            <Link href="/auth/register">
                                <Button label="Registro" rounded className="border-none ml-5 font-light line-height-2 bg-blue-500 text-white"></Button>
                            </Link>
                        </div>
                    </div>
                </div>

                <div
                    id="hero"
                    className="flex flex-column pt-4 px-4 lg:px-8 overflow-hidden"
                    style={{ background: 'linear-gradient(0deg, rgba(255, 255, 255, 0.2), rgba(255, 255, 255, 0.2)), radial-gradient(77.36% 256.97% at 77.36% 57.52%, #EEEFAF 0%, #C3E3FA 100%)', clipPath: 'ellipse(150% 87% at 93% 13%)' }}
                >
                    <div className="mx-4 md:mx-8 mt-0 md:mt-4">
                        <h1 className="text-6xl font-bold text-gray-900 line-height-2">
                            <span className="font-light block" style={{ color: '#6d98e9' }}>VECONTAB</span>
                            <span style={{ color: '#6d98e9' }}>Controle de Agendamentos Contábeis</span>
                        </h1>
                        <Link href="/">
                            <Button
                                type="button"
                                label="Comece aqui"
                                rounded
                                className="text-xl mt-3 bg-white border-1 border-blue-700 font-normal line-height-3 px-3"
                                style={{ color: '#6d98e9' }}
                            ></Button>
                        </Link>
                    </div>
                    <div className="flex justify-content-center md:justify-content-end">
                        <img src="/demo/images/landing/screen-1.png" alt="Hero Image" className="w-9 md:w-auto" />
                    </div>
                </div>

                <div id="features" className="py-4 px-4 lg:px-8 mt-5 mx-0 lg:mx-8">
                    <div className="grid justify-content-center">
                        <div className="col-12 text-center mt-8 mb-4">
                            <h2 className="text-900 font-normal mb-2">Ótimas Funcionalidades</h2>
                            <span className="text-600 text-2xl">O necessário para o seu dia a dia contábil</span>
                        </div>

                        <div className="col-12 md:col-12 lg:col-4 p-0 lg:pr-5 lg:pb-5 mt-4 lg:mt-0">
                            <div
                                style={{
                                    height: '145px',
                                    padding: '2px',
                                    borderRadius: '10px',
                                    background: 'linear-gradient(90deg, rgba(253, 228, 165, 0.2), rgba(187, 199, 205, 0.2)), linear-gradient(180deg, rgba(253, 228, 165, 0.2), rgba(187, 199, 205, 0.2))'
                                }}
                            >
                                <div className="p-2 surface-card h-full" style={{ borderRadius: '8px' }}>
                                    <div className="flex align-items-center justify-content-center bg-yellow-200 mb-3" style={{ width: '3rem', height: '3rem', borderRadius: '10px' }}>
                                        <i className="pi pi-fw pi-users text-2xl text-yellow-700"></i>
                                    </div>
                                    <h5 className="mb-2 text-900">Fácil de usar</h5>
                                </div>
                            </div>
                        </div>

                        <div className="col-12 md:col-12 lg:col-4 p-0 lg:pr-5 lg:pb-5 mt-4 lg:mt-0">
                            <div
                                style={{
                                    height: '145px',
                                    padding: '2px',
                                    borderRadius: '10px',
                                    background: 'linear-gradient(90deg, rgba(145,226,237,0.2),rgba(251, 199, 145, 0.2)), linear-gradient(180deg, rgba(253, 228, 165, 0.2), rgba(172, 180, 223, 0.2))'
                                }}
                            >
                                <div className="p-2 surface-card h-full" style={{ borderRadius: '8px' }}>
                                    <div className="flex align-items-center justify-content-center bg-cyan-200 mb-3" style={{ width: '3rem', height: '3rem', borderRadius: '10px' }}>
                                        <i className="pi pi-fw pi-palette text-2xl text-cyan-700"></i>
                                    </div>
                                    <h5 className="mb-2 text-900">Design inteligente e intuitivo</h5>
                                </div>
                            </div>
                        </div>

                        <div className="col-12 md:col-12 lg:col-4 p-0 lg:pb-5 mt-4 lg:mt-0">
                            <div
                                style={{
                                    height: '145px',
                                    padding: '2px',
                                    borderRadius: '10px',
                                    background: 'linear-gradient(90deg, rgba(145, 226, 237, 0.2), rgba(172, 180, 223, 0.2)), linear-gradient(180deg, rgba(172, 180, 223, 0.2), rgba(246, 158, 188, 0.2))'
                                }}
                            >
                                <div className="p-2 surface-card h-full" style={{ borderRadius: '8px' }}>
                                    <div className="flex align-items-center justify-content-center bg-indigo-200" style={{ width: '3rem', height: '3rem', borderRadius: '10px' }}>
                                        <i className="pi pi-fw pi-map text-2xl text-indigo-700"></i>
                                    </div>
                                    <h5 className="mb-2 text-900">Bem documentado</h5>
                                </div>
                            </div>
                        </div>

                        <div className="col-12 md:col-12 lg:col-4 p-0 lg:pr-5 lg:pb-5 mt-4 lg:mt-0">
                            <div
                                style={{
                                    height: '145px',
                                    padding: '2px',
                                    borderRadius: '10px',
                                    background: 'linear-gradient(90deg, rgba(187, 199, 205, 0.2),rgba(251, 199, 145, 0.2)), linear-gradient(180deg, rgba(253, 228, 165, 0.2),rgba(145, 210, 204, 0.2))'
                                }}
                            >
                                <div className="p-2 surface-card h-full" style={{ borderRadius: '8px' }}>
                                    <div className="flex align-items-center justify-content-center bg-bluegray-200 mb-3" style={{ width: '3rem', height: '3rem', borderRadius: '10px' }}>
                                        <i className="pi pi-fw pi-id-card text-2xl text-bluegray-700"></i>
                                    </div>
                                    <h5 className="mb-2 text-900">Layout Responsivo</h5>
                                </div>
                            </div>
                        </div>

                        <div className="col-12 md:col-12 lg:col-4 p-0 lg:pr-5 lg:pb-5 mt-4 lg:mt-0">
                            <div
                                style={{
                                    height: '145px',
                                    padding: '2px',
                                    borderRadius: '10px',
                                    background: 'linear-gradient(90deg, rgba(187, 199, 205, 0.2),rgba(246, 158, 188, 0.2)), linear-gradient(180deg, rgba(145, 226, 237, 0.2),rgba(160, 210, 250, 0.2))'
                                }}
                            >
                                <div className="p-2 surface-card h-full" style={{ borderRadius: '8px' }}>
                                    <div className="flex align-items-center justify-content-center bg-orange-200 mb-3" style={{ width: '3rem', height: '3rem', borderRadius: '10px' }}>
                                        <i className="pi pi-fw pi-star text-2xl text-orange-700"></i>
                                    </div>
                                    <h5 className="mb-2 text-900">Linguagem clara</h5>
                                </div>
                            </div>
                        </div>

                        <div className="col-12 md:col-12 lg:col-4 p-0 lg:pb-5 mt-4 lg:mt-0">
                            <div
                                style={{
                                    height: '145px',
                                    padding: '2px',
                                    borderRadius: '10px',
                                    background: 'linear-gradient(90deg, rgba(251, 199, 145, 0.2), rgba(246, 158, 188, 0.2)), linear-gradient(180deg, rgba(172, 180, 223, 0.2), rgba(212, 162, 221, 0.2))'
                                }}
                            >
                                <div className="p-2 surface-card h-full" style={{ borderRadius: '8px' }}>
                                    <div className="flex align-items-center justify-content-center bg-pink-200 mb-3" style={{ width: '3rem', height: '3rem', borderRadius: '10px' }}>
                                        <i className="pi pi-fw pi-moon text-2xl text-pink-700"></i>
                                    </div>
                                    <h5 className="mb-2 text-900">Dark Mode</h5>
                                </div>
                            </div>
                        </div>

                        <div className="col-12 md:col-12 lg:col-4 p-0 lg:pr-5 mt-4 lg:mt-0">
                            <div
                                style={{
                                    height: '145px',
                                    padding: '2px',
                                    borderRadius: '10px',
                                    background: 'linear-gradient(90deg, rgba(145, 210, 204, 0.2), rgba(160, 210, 250, 0.2)), linear-gradient(180deg, rgba(187, 199, 205, 0.2), rgba(145, 210, 204, 0.2))'
                                }}
                            >
                                <div className="p-2 surface-card h-full" style={{ borderRadius: '8px' }}>
                                    <div className="flex align-items-center justify-content-center bg-teal-200 mb-3" style={{ width: '3rem', height: '3rem', borderRadius: '10px' }}>
                                        <i className="pi pi-fw pi-shopping-cart text-2xl text-teal-700"></i>
                                    </div>
                                    <h5 className="mb-2 text-900">Pronto  para usar</h5>
                                </div>
                            </div>
                        </div>

                        <div className="col-12 md:col-12 lg:col-4 p-0 lg:pr-5 mt-4 lg:mt-0">
                            <div
                                style={{
                                    height: '145px',
                                    padding: '2px',
                                    borderRadius: '10px',
                                    background: 'linear-gradient(90deg, rgba(145, 210, 204, 0.2), rgba(212, 162, 221, 0.2)), linear-gradient(180deg, rgba(251, 199, 145, 0.2), rgba(160, 210, 250, 0.2))'
                                }}
                            >
                                <div className="p-2 surface-card h-full" style={{ borderRadius: '8px' }}>
                                    <div className="flex align-items-center justify-content-center bg-blue-200 mb-3" style={{ width: '3rem', height: '3rem', borderRadius: '10px' }}>
                                        <i className="pi pi-fw pi-globe text-2xl text-blue-700"></i>
                                    </div>
                                    <h5 className="mb-2 text-900">Práticas modernas de Desenvolvimento</h5>
                                </div>
                            </div>
                        </div>

                        <div className="col-12 md:col-12 lg:col-4 p-0 lg-4 mt-4 lg:mt-0">
                            <div
                                style={{
                                    height: '145px',
                                    padding: '2px',
                                    borderRadius: '10px',
                                    background: 'linear-gradient(90deg, rgba(160, 210, 250, 0.2), rgba(212, 162, 221, 0.2)), linear-gradient(180deg, rgba(246, 158, 188, 0.2), rgba(212, 162, 221, 0.2))'
                                }}
                            >
                                <div className="p-2 surface-card h-full" style={{ borderRadius: '8px' }}>
                                    <div className="flex align-items-center justify-content-center bg-purple-200 mb-3" style={{ width: '3rem', height: '3rem', borderRadius: '10px' }}>
                                        <i className="pi pi-fw pi-eye text-2xl text-purple-700"></i>
                                    </div>
                                    <h5 className="mb-2 text-900">Privacidade</h5>
                                    <span className="text-600">Seus dados nunca são expostos ou compartilhados</span>
                                </div>
                            </div>
                        </div>

                    </div>
                </div>

                <div id="highlights" className="py-4 px-4 lg:px-8 mx-0 my-6 lg:mx-8">
                    <div className="text-center">
                        <h2 className="text-900 font-normal mb-2">Utilizável em qualquer lugar</h2>
                        <span className="text-600 text-2xl">Ambiente seguro podendo ser utilizado em qualquer rede</span>
                    </div>

                    <div className="grid mt-8 pb-2 md:pb-8">
                        <div className="flex justify-content-center col-12 lg:col-6 bg-purple-100 p-0 flex-order-1 lg:flex-order-0" style={{ borderRadius: '8px' }}>
                            <img src="/demo/images/landing/mockup.svg" className="w-11" alt="mockup mobile" />
                        </div>

                        <div className="col-12 lg:col-6 my-auto flex flex-column lg:align-items-end text-center lg:text-right">
                            <div className="flex align-items-center justify-content-center bg-purple-200 align-self-center lg:align-self-end" style={{ width: '4.2rem', height: '4.2rem', borderRadius: '10px' }}>
                                <i className="pi pi-fw pi-mobile text-5xl text-purple-700"></i>
                            </div>
                            <h2 className="line-height-1 text-900 text-4xl font-normal">O layout se  adapta ao seu dispositivo: desktop ou mobile</h2>
                            <span className="text-700 text-2xl line-height-3 ml-0 md:ml-2" style={{ maxWidth: '650px' }}>
                                Interface adaptada para desktop, notebook, tablet e celular, com a mesma qualidade de navegação em qualquer tela.
                            </span>
                        </div>
                    </div>

                    <div className="grid my-8 pt-2 md:pt-8">
                        <div className="col-12 lg:col-6 my-auto flex flex-column text-center lg:text-left lg:align-items-start">
                            <div className="flex align-items-center justify-content-center bg-yellow-200 align-self-center lg:align-self-start" style={{ width: '4.2rem', height: '4.2rem', borderRadius: '10px' }}>
                                <i className="pi pi-fw pi-desktop text-5xl text-yellow-700"></i>
                            </div>
                            <h2 className="line-height-1 text-900 text-4xl font-normal">Bando de dados adaptável</h2>
                            <span className="text-700 text-2xl line-height-3 mr-0 md:mr-2" style={{ maxWidth: '650px' }}>
                                Algumas empresas preferem ter seus Bancos de Dados alocados particularmente. O VECONTAB conta com essa possibilidade (consulte)
                            </span>
                        </div>

                        <div className="flex justify-content-end flex-order-1 sm:flex-order-2 col-12 lg:col-6 bg-yellow-100 p-0" style={{ borderRadius: '8px' }}>
                            <img src="/demo/images/landing/mockup-desktop.svg" className="w-11" alt="mockup" />
                        </div>
                    </div>
                </div>

                <div id="pricing" className="py-4 px-4 lg:px-8 my-2 md:my-4">
                    <div className="text-center">
                        <h2 className="text-900 font-normal mb-2">Preços conforme sua necessidade</h2>
                        <span className="text-600 text-2xl">Pagamento por cartão de crédito para sua comodidade</span>
                    </div>

                    <div className="grid justify-content-between mt-8 md:mt-0">
                        <div className="col-12 lg:col-4 p-0 md:p-3">
                            <div className="p-3 flex flex-column border-200 pricing-card cursor-pointer border-2 hover:border-primary transition-duration-300 transition-all">
                                <h3 className="text-900 text-center my-5">Padrão</h3>
                                <img src="/demo/images/landing/free.svg" className="w-10 h-10 mx-auto" alt="free" />
                                <div className="my-5 text-center">
                                    <span className="text-5xl font-bold mr-2 text-900">R$ 100,00</span>
                                    <span className="text-600">1 mês para você testar à vontade, podendo desistir caso o aplicativo não atenda suas necessidades</span>
                                    <Button label="Get Started" rounded className="block mx-auto mt-4 border-none ml-3 font-light line-height-2 bg-blue-500 text-white"></Button>
                                </div>
                                <Divider className="w-full bg-surface-200"></Divider>
                                <ul className="my-5 list-none p-0 flex text-900 flex-column">
                                    <li className="py-2">
                                        <i className="pi pi-fw pi-check text-xl text-cyan-500 mr-2"></i>
                                        <span className="text-xl line-height-3">Layout Responsivo</span>
                                    </li>
                                    <li className="py-2">
                                        <i className="pi pi-fw pi-check text-xl text-cyan-500 mr-2"></i>
                                        <span className="text-xl line-height-3">Gerencia até 10 empresas</span>
                                    </li>
                                    <li className="py-2">
                                        <i className="pi pi-fw pi-check text-xl text-cyan-500 mr-2"></i>
                                        <span className="text-xl line-height-3">Atendimento por fila</span>
                                    </li>
                                    <li className="py-2">
                                        <i className="pi pi-fw pi-check text-xl text-cyan-500 mr-2"></i>
                                        <span className="text-xl line-height-3">Opções padrão</span>
                                    </li>
                                </ul>
                            </div>
                        </div>

                        <div className="col-12 lg:col-4 p-0 md:p-3 mt-4 md:mt-0">
                            <div className="p-3 flex flex-column border-200 pricing-card cursor-pointer border-2 hover:border-primary transition-duration-300 transition-all">
                                <h3 className="text-900 text-center my-5">Padrão</h3>
                                <img src="/demo/images/landing/startup.svg" className="w-10 h-10 mx-auto" alt="startup" />
                                <div className="my-5 text-center">
                                    <span className="text-5xl font-bold mr-2 text-900">R$ 250,00</span>
                                    <span className="text-600">mensal</span>
                                    <Button label="Try Free" rounded className="block mx-auto mt-4 border-none ml-3 font-light line-height-2 bg-blue-500 text-white"></Button>
                                </div>
                                <Divider className="w-full bg-surface-200"></Divider>
                                <ul className="my-5 list-none p-0 flex text-900 flex-column">
                                    <li className="py-2">
                                        <i className="pi pi-fw pi-check text-xl text-cyan-500 mr-2"></i>
                                        <span className="text-xl line-height-3">Layout Responsivo</span>
                                    </li>
                                    <li className="py-2">
                                        <i className="pi pi-fw pi-check text-xl text-cyan-500 mr-2"></i>
                                        <span className="text-xl line-height-3">Número ilimitado de empreas</span>
                                    </li>
                                    <li className="py-2">
                                        <i className="pi pi-fw pi-check text-xl text-cyan-500 mr-2"></i>
                                        <span className="text-xl line-height-3">Atendimento preferencial</span>
                                    </li>
                                    <li className="py-2">
                                        <i className="pi pi-fw pi-check text-xl text-cyan-500 mr-2"></i>
                                        <span className="text-xl line-height-3">Análise de Pedidos de Customizações Básicas</span>
                                    </li>
                                </ul>
                            </div>
                        </div>

                        <div className="col-12 lg:col-4 p-0 md:p-3 mt-4 md:mt-0">
                            <div className="p-3 flex flex-column border-200 pricing-card cursor-pointer border-2 hover:border-primary transition-duration-300 transition-all">
                                <h3 className="text-900 text-center my-5">Premium</h3>
                                <img src="/demo/images/landing/enterprise.svg" className="w-10 h-10 mx-auto" alt="enterprise" />
                                <div className="my-5 text-center">
                                    <span className="text-5xl font-bold mr-2 text-900">R$ (Consulte)</span>
                                    <span className="text-600">mensal</span>
                                    <Button label="Get a Quote" rounded className="block mx-auto mt-4 border-none ml-3 font-light line-height-2 bg-blue-500 text-white"></Button>
                                </div>
                                <Divider className="w-full bg-surface-200"></Divider>udemy
                                <ul className="my-5 list-none p-0 flex text-900 flex-column">

                                    <li className="py-2">
                                        <i className="pi pi-fw pi-check text-xl text-cyan-500 mr-2"></i>
                                        <span className="text-xl line-height-3">Bando de Dados Privado</span>
                                    </li>
                                    <li className="py-2">
                                        <i className="pi pi-fw pi-check text-xl text-cyan-500 mr-2"></i>
                                        <span className="text-xl line-height-3">Atendimento Personalizado</span>
                                    </li>
                                    <li className="py-2">
                                        <i className="pi pi-fw pi-check text-xl text-cyan-500 mr-2"></i>
                                        <span className="text-xl line-height-3">Solicitações de customizações avançadas</span>
                                    </li>
                                    <li className="py-2">
                                        <i className="pi pi-fw pi-check text-xl text-cyan-500 mr-2"></i>
                                        <span className="text-xl line-height-3">Geração de boletos, recibos e NF´s on-line</span>
                                    </li>
                                </ul>
                            </div>
                        </div>
                    </div>
                </div>

                <div className="py-4 px-4 mx-0 mt-8 lg:mx-8">
                    <div className="surface-card p-4 mb-4 border-round">
                        <h4 className="font-medium text-2xl mb-3 text-900">Sobre</h4>
                        <p className="text-700 m-0"><strong>Telefone:</strong> +55 48 9 8815 1381</p>
                        <p className="text-700 mt-2 mb-0"><strong>Email:</strong> Carlos Amaral: chayimamaral@gmail.com</p>
                    </div>
                    <div className="grid justify-content-between">
                        <div className="col-12 md:col-2" style={{ marginTop: '-1.5rem' }}>
                            <Link href="/" className="flex flex-wrap align-items-center justify-content-center md:justify-content-start md:mb-0 mb-3 cursor-pointer">
                                <img src="/vecontab.svg" alt="Vecontab" width="50" height="50" className="mr-2" />
                                <span className="font-medium text-3xl" style={{ color: '#0B4FCE' }}>VECONTAB</span>
                            </Link>
                        </div>

                        <div className="col-12 md:col-10 lg:col-7">
                            <div className="grid text-center md:text-left">
                                <div className="col-12 md:col-3">
                                    <h4 className="font-medium text-2xl line-height-3 mb-3 text-900">VEC</h4>
                                    <a className="line-height-3 text-xl block cursor-pointer mb-2 text-700">Sobre nós</a>
                                    <a className="line-height-3 text-xl block cursor-pointer mb-2 text-700">News</a>
                                    <a className="line-height-3 text-xl block cursor-pointer mb-2 text-700">Relação com Clientes</a>
                                    <a className="line-height-3 text-xl block cursor-pointer mb-2 text-700">Carreira</a>
                                </div>

                                <div className="col-12 md:col-3 mt-4 md:mt-0">
                                    <h4 className="font-medium text-2xl line-height-3 mb-3 text-900">Recursos</h4>
                                    <a className="line-height-3 text-xl block cursor-pointer mb-2 text-700">Comece aqui</a>
                                    <a className="line-height-3 text-xl block cursor-pointer mb-2 text-700">Aprenda</a>
                                    <a className="line-height-3 text-xl block cursor-pointer text-700">Casos de Uso</a>
                                </div>

                                <div className="col-12 md:col-3 mt-4 md:mt-0">
                                    <h4 className="font-medium text-2xl line-height-3 mb-3 text-900">Community</h4>
                                    <a className="line-height-3 text-xl block cursor-pointer mb-2 text-700">Discord</a>
                                    <a className="line-height-3 text-xl block cursor-pointer mb-2 text-700">
                                        Events
                                        <img src="/demo/images/landing/new-badge.svg" className="ml-2" alt="badge" />
                                    </a>
                                    <a className="line-height-3 text-xl block cursor-pointer mb-2 text-700">FAQ</a>
                                    <a className="line-height-3 text-xl block cursor-pointer text-700">Blog</a>
                                </div>

                                <div className="col-12 md:col-3 mt-4 md:mt-0">
                                    <h4 className="font-medium text-2xl line-height-3 mb-3 text-900">Legal</h4>
                                    <a className="line-height-3 text-xl block cursor-pointer mb-2 text-700">Brand Policy</a>
                                    <a className="line-height-3 text-xl block cursor-pointer mb-2 text-700">Privacy Policy</a>
                                    <a className="line-height-3 text-xl block cursor-pointer text-700">Terms of Service</a>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
};

LandingPage.getLayout = function getLayout(page) {
    return (
        <React.Fragment>
            {page}
            <AppConfig simple />
        </React.Fragment>
    );
};

export default LandingPage;
