import type { AppProps } from 'next/app';
import { LayoutConfig, type Page } from '../types/types';
import React from 'react';
import { LayoutProvider } from '../layout/context/layoutcontext';
import Layout from '../layout/layout';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import 'primereact/resources/primereact.css';
import 'primeflex/primeflex.css';
import 'primeicons/primeicons.css';
import '../styles/layout/layout.scss';
import { AuthProvider } from '../components/context/AuthContext';
// import userPersistedState from '../components/utils/usePersistedState';

type Props = AppProps & {
    Component: Page;
};

export default function App({ Component, pageProps }: Props) {
    const [queryClient] = React.useState(
        () =>
            new QueryClient({
                defaultOptions: {
                    queries: {
                        refetchOnWindowFocus: false,
                        retry: 1,
                        /**
                         * staleTime 0: dados nascem obsoletos — ao montar a página, refetch típico.
                         * Evita perfil/permissões “congelados” (ex.: usuariorole null em cache por minutos).
                         * gcTime mantém resultado em memória após desmontar (dedupe, voltar à página).
                         * “Zero cache” absoluto não existe no TanStack; para ainda mais agressivo use gcTime: 0.
                         */
                        staleTime: 0,
                        gcTime: 1000 * 60 * 10,
                    },
                },
            })
    );

    const defaultLayoutConfig: LayoutConfig = {
        theme: 'dark',
        ripple: true,
        inputStyle: 'outlined',
        menuMode: 'layout-menu-light',
        colorScheme: 'light',
        scale: 10,
    };

    // const [layoutConfig, setLayoutConfig] = userPersistedState<LayoutConfig>('theme', {
    //     theme: 'dark',
    //     ripple: true,
    //     inputStyle: 'outlined',
    //     menuMode: 'layout-menu-light',
    //     colorScheme: 'light',
    //     scale: 10
    // });

    // const [layoutConfig, setLayoutConfig] = userPersistedState<LayoutConfig>('theme', defaultLayoutConfig);

    // useEffect(() => {
    //   if (!layoutConfig) {
    //     setLayoutConfig(defaultLayoutConfig);
    //   }
    //   localStorage.setItem('layoutConfig', JSON.stringify(layoutConfig));
    // }, [layoutConfig]);

    if (Component.getLayout) {
        return (
            <QueryClientProvider client={queryClient}>
                <AuthProvider>
                    <LayoutProvider>{Component.getLayout(<Component {...pageProps} />)}</LayoutProvider>;
                </AuthProvider>
            </QueryClientProvider>
        )
    } else {
        return (
            <QueryClientProvider client={queryClient}>
                <AuthProvider>
                    <LayoutProvider>
                        <Layout>
                            <Component {...pageProps} />
                        </Layout>
                    </LayoutProvider>
                </AuthProvider>
            </QueryClientProvider>
        );
    }
}

