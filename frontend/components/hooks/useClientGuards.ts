import { useEffect } from 'react';
import { useRouter } from 'next/router';
import { parseCookies } from 'nookies';
import { useQuery } from '@tanstack/react-query';
import api from '../api/apiClient';
import { getAuthTokenFromParsedCookies } from '../../constants/authCookie';

type UserRole = 'SUPER' | 'ADMIN' | 'USER';

const GUEST_ONLY_ROUTES = new Set<string>(['/auth/login', '/auth/register']);

const AUTH_REQUIRED_ROUTES = new Set<string>([
    '/agenda',
    '/agenda-arvore',
    '/catalogo-servicos',
    '/cliente-pf',
    '/clientes',
    '/cnae',
    '/compromissos',
    '/compromissos-empresas',
    '/compromissos-por-natureza',
    '/compromissos-visao',
    '/configuracoes/api-integra-contador',
    '/configuracoes/certificado-digital',
    '/configuracoes/geracao-guias',
    '/configuracoes/integra-contador-servicos',
    '/configuracoes/integra-contador-tabela-consumo',
    '/empresas',
    '/estados',
    '/feriados',
    '/grupopassos',
    '/matriz-conformidade-fiscal',
    '/monitor',
    '/municipios',
    '/obrigacoes',
    '/passos',
    '/regimes-tributarios',
    '/registro',
    '/rotinas',
    '/rotinas-pf',
    '/salario-minimo',
    '/tenants',
    '/tipoempresa',
    '/usuarios',
]);

const ROLE_RESTRICTED_ROUTES: Partial<Record<string, UserRole[]>> = {
    '/catalogo-servicos': ['SUPER'],
    '/configuracoes/api-integra-contador': ['SUPER'],
    '/configuracoes/integra-contador-servicos': ['SUPER'],
    '/configuracoes/integra-contador-tabela-consumo': ['SUPER'],
    '/matriz-conformidade-fiscal': ['SUPER'],
    '/monitor': ['SUPER', 'ADMIN'],
    '/tenants': ['SUPER'],
    '/usuarios': ['SUPER', 'ADMIN'],
};

export function useRouteClientGuard(): void {
    const router = useRouter();
    const pathname = router.pathname;
    const isGuestOnly = GUEST_ONLY_ROUTES.has(pathname);
    const needsAuth = AUTH_REQUIRED_ROUTES.has(pathname) || Boolean(ROLE_RESTRICTED_ROUTES[pathname]);
    const rolesPermitidas = ROLE_RESTRICTED_ROUTES[pathname];

    const cookieToken = getAuthTokenFromParsedCookies(parseCookies());
    const token =
        cookieToken ||
        (typeof window !== 'undefined' ? String(window.localStorage.getItem('vecontab_token') ?? '').trim() : '');

    const { data: roleData, isFetching: roleLoading } = useQuery({
        // Inclui token na chave para não reaproveitar cache de outro login
        // (ex.: usuário anterior USER causando redirect indevido para '/' após login SUPER).
        queryKey: ['route-role-guard', pathname, token],
        enabled: !!rolesPermitidas && !!token,
        queryFn: async () => {
            const { data } = await api.get('/api/usuariorole');
            return String(data?.logado?.role ?? '').trim().toUpperCase();
        },
    });

    useEffect(() => {
        const cookies = parseCookies();
        const cookieToken = getAuthTokenFromParsedCookies(cookies);
        const token =
            cookieToken ||
            (typeof window !== 'undefined' ? String(window.localStorage.getItem('vecontab_token') ?? '').trim() : '');

        if (isGuestOnly && token) {
            void router.replace('/');
            return;
        }

        if (needsAuth && !token) {
            void router.replace('/auth/login');
            return;
        }

        if (rolesPermitidas && roleLoading) {
            return;
        }

        if (rolesPermitidas && roleData && !rolesPermitidas.includes(roleData as UserRole)) {
            void router.replace('/');
        }
    }, [isGuestOnly, needsAuth, roleData, roleLoading, rolesPermitidas, router]);
}

export function useTenantIdQuery() {
    const cookieToken = getAuthTokenFromParsedCookies(parseCookies());
    const token =
        cookieToken ||
        (typeof window !== 'undefined' ? String(window.localStorage.getItem('vecontab_token') ?? '').trim() : '');

    return useQuery<string>({
        queryKey: ['tenant-id-client'],
        enabled: !!token,
        queryFn: async () => {
            try {
                const { data } = await api.get('/api/usuariotenant');
                const tenantFromTenantEndpoint = String(data?.tenantid ?? '').trim();
                if (tenantFromTenantEndpoint) {
                    return tenantFromTenantEndpoint;
                }
            } catch {
                // tenta fallback abaixo
            }

            const { data } = await api.get('/api/me');
            const tenantFallback =
                data?.usuarios?.[0]?.resultado?.tenant?.id ??
                data?.tenant?.id ??
                data?.tenantid ??
                '';
            return String(tenantFallback).trim();
        },
        retry: 2,
    });
}

export function useUserIdQuery() {
    return useQuery<string>({
        queryKey: ['user-id-cookie'],
        queryFn: async () => {
            const cookies = parseCookies();
            return String(cookies.user_id ?? '');
        },
    });
}
