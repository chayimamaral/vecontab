/* eslint-disable @next/next/no-img-element */

import React, { useEffect, useMemo, useState } from 'react';
import AppMenuitem from './AppMenuitem';
import { MenuProvider } from './context/menucontext';
import { AppMenuItem } from '../types/types';
import setupAPIClient from '../components/api/api';

const AppMenu = () => {
    const [userRole, setUserRole] = useState<string | null>(null);

    useEffect(() => {
        const api = setupAPIClient(undefined);
        api.get('/api/usuariorole')
            .then((r) => setUserRole(r.data?.logado?.role ?? null))
            .catch(() => setUserRole(null));
    }, []);

    const podeGerenciarUsuarios = userRole === 'ADMIN' || userRole === 'SUPER';

    const model: AppMenuItem[] = useMemo(
        () => [
            {
                label: 'Home',
                items: [
                    { label: 'Dashboard', icon: 'pi pi-fw pi-home', to: '/' },
                    {
                        label: 'Compromissos por Empresas',
                        icon: 'pi pi-fw pi-list',
                        to: '/compromissos-empresas',
                    },
                    {
                        label: 'Compromissos por Natureza',
                        icon: 'pi pi-fw pi-sitemap',
                        to: '/compromissos-por-natureza',
                    },
                    {
                        label: 'Compromissos (Visão Corrida)',
                        icon: 'pi pi-fw pi-table',
                        to: '/compromissos-visao',
                    },
                    {
                        label: 'Agenda',
                        icon: 'pi pi-fw pi-calendar',
                        to: '/agenda',
                    },
                    {
                        label: 'Manutenção de Empresas',
                        icon: 'pi pi-fw pi-table',
                        to: '/empresas',
                    },
                ],
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
                                        to: '/municipios',
                                    },
                                    {
                                        label: 'Estados',
                                        icon: 'pi pi-fw pi-flag',
                                        to: '/estados',
                                    },
                                ],
                            },
                            {
                                label: 'Cadastros Operacionais',
                                icon: 'pi pi-fw pi-sitemap',
                                items: [
                                    {
                                        label: 'Rotinas para Empresas',
                                        icon: 'pi pi-fw pi-bookmark',
                                        to: '/rotinas',
                                    },
                                    {
                                        label: 'Passos das Rotinas',
                                        icon: 'pi pi-fw pi-bookmark',
                                        to: '/passos',
                                    },
                                    {
                                        label: 'Feriados',
                                        icon: 'pi pi-fw pi-table',
                                        to: '/feriados',
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
                                        to: '/cnae',
                                    },
                                    {
                                        label: 'Tipos de Empresas',
                                        icon: 'pi pi-fw pi-table',
                                        items: [
                                            {
                                                label: 'Cadastro de Tipos de Empresas',
                                                icon: 'pi pi-fw pi-table',
                                                to: '/tipoempresa',
                                            },
                                            {
                                                label: 'Obrigações Legais',
                                                icon: 'pi pi-fw pi-money-bill',
                                                to: '/obrigacoes',
                                            },
                                        ],
                                    },
                                ],
                            },
                        ],
                    },
                ],
            },
            {
                label: 'Pages',
                icon: 'pi pi-fw pi-briefcase',
                to: '/pages',
                items: [
                    {
                        label: 'Usuários',
                        icon: 'pi pi-fw pi-user',
                        visible: podeGerenciarUsuarios,
                        items: [
                            {
                                label: 'Usuários',
                                icon: 'pi pi-fw pi-users',
                                to: '/usuarios',
                            },
                        ],
                    },
                    {
                        label: 'Sobre',
                        icon: 'pi pi-fw pi-pencil',
                        to: '/pages/landing',
                    },
                ],
            },
        ],
        [podeGerenciarUsuarios],
    );

    return (
        <MenuProvider>
            <ul className="layout-menu">
                {model.map((item, i) => {
                    return !item?.seperator ? (
                        <AppMenuitem item={item} root={true} index={i} key={item.label} />
                    ) : (
                        <li className="menu-separator"></li>
                    );
                })}
            </ul>
        </MenuProvider>
    );
};

export default AppMenu;
