import React, { useState, createContext, useContext, useEffect, useRef } from 'react';
import PrimeReact from 'primereact/api';
import AuthContext from '../../components/context/AuthContext';
import { LayoutState, ChildContainerProps, LayoutConfig, LayoutContextProps } from '../../types/types';
import { DEFAULT_LAYOUT_CONFIG, layoutPrefsStorageKey, mergeStoredLayout } from '../layoutPreferences';

export const LayoutContext = createContext({} as LayoutContextProps);

export const LayoutProvider = ({ children }: ChildContainerProps) => {
    const { user } = useContext(AuthContext);

    const [layoutConfig, setLayoutConfig] = useState<LayoutConfig>({ ...DEFAULT_LAYOUT_CONFIG });

    const [layoutState, setLayoutState] = useState<LayoutState>({
        staticMenuDesktopInactive: false,
        overlayMenuActive: false,
        profileSidebarVisible: false,
        configSidebarVisible: false,
        staticMenuMobileActive: false,
        menuHoverActive: false
    });

    const currentThemeRef = useRef<string>(DEFAULT_LAYOUT_CONFIG.theme);
    const prevUserIdRef = useRef<string | undefined>(undefined);
    /** Evita sobrescrever o localStorage logo após restaurar do disco. */
    const skipNextPersistRef = useRef(false);

    currentThemeRef.current = layoutConfig.theme;

    /* Restaura preferências por usuário (localStorage). */
    useEffect(() => {
        if (!user?.id) {
            return;
        }
        const key = layoutPrefsStorageKey(user.id);
        try {
            const raw = localStorage.getItem(key);
            if (!raw) {
                return;
            }
            const partial = mergeStoredLayout(JSON.parse(raw));
            if (!partial) {
                return;
            }

            skipNextPersistRef.current = true;

            setLayoutConfig((prev) => {
                const prevTheme = prev.theme;
                const next = { ...prev, ...partial };
                queueMicrotask(() => {
                    if (next.theme !== prevTheme) {
                        PrimeReact.changeTheme?.(prevTheme, next.theme, 'theme-css', () => {});
                    }
                    PrimeReact.ripple = next.ripple;
                    document.documentElement.style.fontSize = `${next.scale}px`;
                });
                currentThemeRef.current = next.theme;
                return next;
            });
        } catch {
            /* ignore */
        }
    }, [user?.id]);

    /* Logout: reverte ao tema padrão na UI pública (login). */
    useEffect(() => {
        if (user?.id) {
            prevUserIdRef.current = user.id;
            return;
        }
        if (!prevUserIdRef.current) {
            return;
        }
        prevUserIdRef.current = undefined;

        const prevTheme = currentThemeRef.current;
        setLayoutConfig({ ...DEFAULT_LAYOUT_CONFIG });
        queueMicrotask(() => {
            PrimeReact.changeTheme?.(prevTheme, DEFAULT_LAYOUT_CONFIG.theme, 'theme-css', () => {});
            PrimeReact.ripple = DEFAULT_LAYOUT_CONFIG.ripple;
            document.documentElement.style.fontSize = `${DEFAULT_LAYOUT_CONFIG.scale}px`;
            currentThemeRef.current = DEFAULT_LAYOUT_CONFIG.theme;
        });
    }, [user?.id]);

    /* Persiste alterações feitas na engrenagem (debounce simples). */
    useEffect(() => {
        if (!user?.id) {
            return;
        }
        if (skipNextPersistRef.current) {
            skipNextPersistRef.current = false;
            return;
        }
        const key = layoutPrefsStorageKey(user.id);
        const t = window.setTimeout(() => {
            try {
                localStorage.setItem(key, JSON.stringify(layoutConfig));
            } catch {
                /* quota / modo privado */
            }
        }, 350);
        return () => window.clearTimeout(t);
    }, [user?.id, layoutConfig]);

    const onMenuToggle = () => {
        if (isOverlay()) {
            setLayoutState((prevLayoutState) => ({ ...prevLayoutState, overlayMenuActive: !prevLayoutState.overlayMenuActive }));
        }

        if (isDesktop()) {
            setLayoutState((prevLayoutState) => ({ ...prevLayoutState, staticMenuDesktopInactive: !prevLayoutState.staticMenuDesktopInactive }));
        } else {
            setLayoutState((prevLayoutState) => ({ ...prevLayoutState, staticMenuMobileActive: !prevLayoutState.staticMenuMobileActive }));
        }
    };

    const showProfileSidebar = () => {
        setLayoutState((prevLayoutState) => ({ ...prevLayoutState, profileSidebarVisible: !prevLayoutState.profileSidebarVisible }));
    };

    const isOverlay = () => {
        return layoutConfig.menuMode === 'overlay';
    };

    const isDesktop = () => {
        return window.innerWidth > 991;
    };

    const value: LayoutContextProps = {
        layoutConfig,
        setLayoutConfig,
        layoutState,
        setLayoutState,
        onMenuToggle,
        showProfileSidebar
    };

    return <LayoutContext.Provider value={value}>{children}</LayoutContext.Provider>;
};
