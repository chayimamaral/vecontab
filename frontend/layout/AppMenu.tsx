/* eslint-disable @next/next/no-img-element */

import React, { useEffect, useMemo, useState } from 'react';
import AppMenuitem from './AppMenuitem';
import { MenuProvider } from './context/menucontext';
import { AppMenuItem } from '../types/types';
import setupAPIClient from '../components/api/api';
// Onde está o nome: logoIntegra
// Onde está o local: '../assets/logo_integracontador_limpo.avif'
import logoIntegra from '../public/logo_integracontador.avif';
import { options } from '@fullcalendar/core/preact';

const AppMenu = () => {
  const [userRole, setUserRole] = useState<string | null>(null);

  useEffect(() => {
    const api = setupAPIClient(undefined);
    api.get('/api/usuariorole')
      .then((r) => setUserRole(r.data?.logado?.role ?? null))
      .catch(() => setUserRole(null));
  }, []);

  const podeGerenciarUsuarios = userRole === 'ADMIN' || userRole === 'SUPER';
  const podeVerMonitor = userRole === 'ADMIN' || userRole === 'SUPER';

  const model: AppMenuItem[] = useMemo(
    () => [
      {
        label: 'Home',
        items: [
          { label: 'Dashboard', icon: 'pi pi-fw pi-home', to: '/' },
          {
            label: 'Processos Fiscais',
            icon: 'pi pi-fw pi-list',
            items: [
              {
                label: 'Processos por empresas',
                icon: 'pi pi-fw pi-list',
                to: '/compromissos-empresas',
              },
              {
                label: 'Processos por natureza',
                icon: 'pi pi-fw pi-sitemap',
                to: '/compromissos-por-natureza',
              },
              {
                label: 'Processos (visão corrida)',
                icon: 'pi pi-fw pi-table',
                to: '/compromissos-visao',
              },
            ],
          },
          {
            label: 'Fluxos de Processos',
            icon: 'pi pi-fw pi-calendar',
            items: [
              {
                label: 'Fluxo em Árvore',
                icon: 'pi pi-fw pi-sitemap',
                to: '/agenda-arvore',
              },
              {
                label: 'Fluxo em Agenda (calendário)',
                icon: 'pi pi-fw pi-calendar',
                to: '/agenda',
              },
            ],
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
                    label: 'Clientes',
                    icon: 'pi pi-fw pi-id-card',
                    to: '/clientes',
                  },
                  {
                    label: 'Feriados',
                    icon: 'pi pi-fw pi-table',
                    to: '/feriados',
                  },
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
                    label: 'Configurações Fiscais',
                    icon: 'pi pi-fw pi-table',
                    items: [
                      {
                        label: 'Enquadramento Jurídico',
                        icon: 'pi pi-fw pi-table',
                        to: '/tipoempresa',
                      },
                      {
                        label: 'Regras de Obrigações',
                        icon: 'pi pi-fw pi-money-bill',
                        to: '/obrigacoes',
                      },
                    ],
                  },
                  {

                    label: 'Processos para Empresas', // O item pai agora agrupa os dois
                    icon: 'pi pi-fw pi-briefcase',
                    items: [
                      {
                        label: 'Processos',
                        icon: 'pi pi-fw pi-list',
                        to: '/rotinas', // Mantive o path atual para não quebrar seus links
                      },
                      {
                        label: 'Etapas',
                        icon: 'pi pi-fw pi-check-square',
                        to: '/passos',
                      },
                    ]
                  },
                  {
                    label: 'Processos PF (IRPF / Carnê-Leão)',
                    icon: 'pi pi-fw pi-user',
                    to: '/rotinas-pf',
                  },

                ],
              },
              {
                label: 'Cadastros Contábeis',
                icon: 'pi pi-fw pi-sitemap',
                items: [

                  {
                    label: 'CNAE',
                    icon: 'pi pi-fw pi-table',
                    to: '/cnae',
                  },
                  {
                    label: 'Regime tributário',
                    icon: 'pi pi-fw pi-percentage',
                    to: '/regimes-tributarios',
                  },
                ],
              },
            ],
          },
        ],
      },
      {
        label: 'Diversos',
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
            label: 'Tenants',
            icon: 'pi pi-fw pi-server',
            visible: userRole === 'SUPER',
            items: [
              {
                label: 'Manutenção',
                icon: 'pi pi-fw pi-table',
                to: '/tenants',
              },
            ],
          },
          {
            label: 'Monitor',
            icon: 'pi pi-fw pi-chart-line',
            visible: podeVerMonitor,
            items: [
              {
                label: 'Operações',
                icon: 'pi pi-fw pi-list',
                to: '/monitor',
              },
            ],
          },
          {
            label: 'Configurações',
            icon: 'pi pi-fw pi-cog',
            visible: userRole === 'SUPER' || userRole === 'ADMIN' || userRole === 'USER',
            items: [
              {
                label: 'Integra Contador - Serpro',
                iconSrc: '/microservice-icon.svg',
                items: [
                  {
                    label: 'Chave de Autenticação',
                    icon: 'pi pi-fw pi-key',
                    to: '/configuracoes/api-integra-contador',
                    visible: userRole === 'SUPER',
                  },
                  {
                    label: 'Geração de Guias',
                    icon: 'pi pi-fw pi-file',
                    to: '/configuracoes/geracao-guias',
                    visible: userRole === 'ADMIN',
                  },
                  {
                    label: 'Execução de Serviços',
                    icon: 'pi pi-fw pi-play',
                    to: '/configuracoes/integra-contador-servicos',
                    visible: userRole === 'ADMIN' || userRole === 'SUPER',
                  },
                  {
                    label: 'Certificado Digital',
                    icon: 'pi pi-fw pi-shield',
                    to: '/configuracoes/certificado-digital',
                    visible: userRole === 'ADMIN',
                  },
                  {
                    label: 'Catálogo de Serviços',
                    icon: 'pi pi-fw pi-sitemap',
                    to: '/catalogo-servicos',
                  },
                  {
                    label: 'Tabela de Consumo',
                    icon: 'pi pi-fw pi-wallet',
                    to: '/configuracoes/integra-contador-tabela-consumo',
                    visible: userRole === 'ADMIN' || userRole === 'SUPER',
                  },
                ],
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
    [podeGerenciarUsuarios, podeVerMonitor, userRole],
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
