/* eslint-disable @next/next/no-img-element */

import React, { useContext } from 'react';
import AppMenuitem from './AppMenuitem';
import { LayoutContext } from './context/layoutcontext';
import { MenuProvider } from './context/menucontext';
import Link from 'next/link';
import { AppMenuItem } from '../types/types';

const AppMenu = () => {
    const { layoutConfig } = useContext(LayoutContext);

    const model: AppMenuItem[] = [
        {
            label: 'Home',
            items: [
                { label: 'Dashboard', icon: 'pi pi-fw pi-home', to: '/' },
                {
                    label: 'Agenda',
                    icon: 'pi pi-fw pi-calendar',
                    to: '/agenda'
                },
                {
                    label: 'Manutenção de Empresas',
                    icon: 'pi pi-fw pi-table',
                    to: '/empresas'
                }
            ]
        },
        {
            label: 'Operações',
            items: [


                {
                    label: 'Cadastros',
                    icon: 'pi pi-fw pi-database',
                    items: [
                        {
                            label: 'Cadastros Básicos',
                            icon: 'pi pi-fw pi-bookmark',
                            items: [
                                {
                                    label: 'Municípios',
                                    icon: 'pi pi-fw pi-building',
                                    to: '/municipios'
                                },
                                {
                                    label: 'Estados',
                                    icon: 'pi pi-fw pi-flag',
                                    to: '/estados'
                                },

                            ]
                        },
                        {
                            label: 'Cadastros Operacionais',
                            icon: 'pi pi-fw pi-sitemap',
                            items: [
                                {
                                    label: 'Rotinas',
                                    icon: 'pi pi-fw pi-bookmark',
                                    to: '/rotinas'
                                },
                                {
                                    label: 'Passos',
                                    icon: 'pi pi-fw pi-bookmark',
                                    to: '/passos'
                                },
                                {
                                    label: 'Feriados',
                                    icon: 'pi pi-fw pi-table',
                                    to: '/feriados'
                                },
                            ],
                        },
                        {
                            label: 'Cadastros Contábeis (Legais)',
                            icon: 'pi pi-fw pi-sitemap',
                            items: [
                                {
                                    label: 'CNAE',
                                    icon: 'pi pi-fw pi-table',
                                    to: '/cnae'
                                },
                                {
                                    label: 'Tipos de Empresas',
                                    icon: 'pi pi-fw pi-table',
                                    items: [
                                        {
                                            label: 'Cadastro de Tipos de Empresas',
                                            icon: 'pi pi-fw pi-table',
                                            to: '/tipoempresa'
                                        },
                                        {
                                            label: 'Compromissos Legais',
                                            icon: 'pi pi-fw pi-money-bill',
                                            to: '/compromissos'
                                        }
                                    ]
                                },
                            ],
                        }

                    ]
                },
            ]
        },
        {
            label: 'Pages',
            icon: 'pi pi-fw pi-briefcase',
            to: '/pages',
            items: [

                {
                    label: 'Usuários',
                    icon: 'pi pi-fw pi-user',
                    items: [
                        {
                            label: 'Usuários',
                            icon: 'pi pi-fw pi-users',
                            to: '/usuarios'
                        }
                    ]
                },
                {
                    label: 'Sobre',
                    icon: 'pi pi-fw pi-pencil',
                    to: '/pages/landing'
                }
            ]
        },

    ];

    return (
        <MenuProvider>
            <ul className="layout-menu">
                {model.map((item, i) => {
                    return !item?.seperator ? <AppMenuitem item={item} root={true} index={i} key={item.label} /> : <li className="menu-separator"></li>;
                })}

            </ul>
        </MenuProvider>
    );
};

export default AppMenu;
