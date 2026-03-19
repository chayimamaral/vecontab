/* eslint-disable @next/next/no-img-element */

import Link from 'next/link';
import { classNames } from 'primereact/utils';
import React, { forwardRef, useContext, useImperativeHandle, useRef } from 'react';
import { AppTopbarRef } from '../types/types';
import { LayoutContext } from './context/layoutcontext';
import AuthContext from '../components/context/AuthContext';
import { Tooltip } from 'primereact/tooltip';

const AppTopbar = forwardRef<AppTopbarRef>((props, ref) => {
    const { layoutConfig, layoutState, onMenuToggle, showProfileSidebar } = useContext(LayoutContext);
    const menubuttonRef = useRef(null);
    const topbarmenuRef = useRef(null);
    const topbarmenubuttonRef = useRef(null);
    const { logoutUser } = useContext(AuthContext);

    useImperativeHandle(ref, () => ({
        menubutton: menubuttonRef.current,
        topbarmenu: topbarmenuRef.current,
        topbarmenubutton: topbarmenubuttonRef.current
    }));

    function handleProfile(): void {
        logoutUser();
    }

    return (
        <div className="layout-topbar">
            <Link href="/" className="layout-topbar-logo">
                {/*}
             <img src={`/layout/images/logo-${layoutConfig.colorScheme !== 'light' ? 'white' : 'dark'}.svg`} width="47.22px" height={'35px'} alt="logo" />
    */}
                <img src={`/layout/images/vecontab-${layoutConfig.colorScheme === 'light' ? 'dark' : 'white'}.svg`} width="47.22px" height={'35px'} alt="logo" />

                <span>VECONTAB</span>
            </Link>

            <button ref={menubuttonRef} type="button" className="p-link layout-menu-button layout-topbar-button" onClick={onMenuToggle}>
                <i className="pi pi-bars" />
            </button>

            <button ref={topbarmenubuttonRef} type="button" className="p-link layout-topbar-menu-button layout-topbar-button" onClick={showProfileSidebar}>
                <i className="pi pi-ellipsis-v" />
            </button>

            <div ref={topbarmenuRef} className={classNames('layout-topbar-menu', { 'layout-topbar-menu-mobile-active': layoutState.profileSidebarVisible })}>
                <Link href="/agenda">
                    <Tooltip target=".btn-agenda" position="bottom" />
                    <button type="button" className="btn-agenda p-link layout-topbar-button" data-pr-tooltip='Agenda'>
                        <i className="pi pi-calendar"></i>
                        <span>Calendar</span>
                    </button>
                </Link>
                <Tooltip target=".btn-login" position="bottom" />
                <button type="button" className="btn-login p-link layout-topbar-button" data-pr-tooltip='Trocar Usuário' onClick={handleProfile}>
                    <i className="pi pi-user"></i>
                    <span>Profile</span>
                </button>

                <Link href="/registro">
                    <Tooltip target=".btn-setup" position="bottom" />
                    <button type="button" className="btn-setup p-link layout-topbar-button" data-pr-tooltip='Empresa'>
                        <i className="pi pi-cog"></i>
                        <span>Settings</span>
                    </button>
                </Link>
            </div>
        </div>
    );
});

AppTopbar.displayName = 'AppTopbar';

export default AppTopbar;
