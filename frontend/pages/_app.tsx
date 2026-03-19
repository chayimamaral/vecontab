import type { AppProps } from 'next/app';
import { LayoutConfig, type Page } from '../types/types';
import React, { useEffect } from 'react';
import { LayoutProvider } from '../layout/context/layoutcontext';
import Layout from '../layout/layout';
import 'primereact/resources/primereact.css';
import 'primeflex/primeflex.css';
import 'primeicons/primeicons.css';
import '../styles/layout/layout.scss';
import  AuthContext, { AuthProvider } from '../components/context/AuthContext';
// import userPersistedState from '../components/utils/usePersistedState';

type Props = AppProps & {
    Component: Page;
};

export default function App({ Component, pageProps }: Props) {

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
            <AuthProvider>
                <LayoutProvider>{Component.getLayout(<Component {...pageProps} />)}</LayoutProvider>;
            </AuthProvider>
        )
    } else {
        return (
            <AuthProvider>
                <LayoutProvider>
                    <Layout>
                        <Component {...pageProps} />
                    </Layout>
                </LayoutProvider>
            </AuthProvider>
        );
    }
}
