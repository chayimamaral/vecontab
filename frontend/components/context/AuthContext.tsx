import { createContext, ReactNode, useEffect, useState } from 'react';
import { setCookie, parseCookies } from 'nookies';
import Router from 'next/router';
import { AxiosError } from 'axios';

import api from '../api/apiClient';
import {
  AUTH_TOKEN_COOKIE,
  clearAuthTokenCookies,
  clearLegacyAuthTokenCookieBrowser,
  getAuthTokenFromParsedCookies,
} from '../../constants/authCookie';

interface AuthContextData {
  user?: UserProps | undefined;
  isAuthenticated: boolean;
  signIn: (credentials: SignInProps) => Promise<void>;
  signUp: (credentials: SignUpProps) => Promise<SignUpResult>;
  logoutUser: () => Promise<void>;
}

interface UserProps {
  id: string;
  nome: string;
  email: string;
  tenant?: Tenant | null;
}

interface Tenant {
  id: string;
  nome?: string;
  schema_name?: string;
  schemaName?: string;
}

interface SubscriptionProps {
  id: string;
  status: string;
}

type AuthProviderProps = {
  children: ReactNode;
}

interface SignInProps {
  email: string;
  password: string;
}

interface SignUpProps {
  nome: string;
  email: string;
  password: string;
  empresa_nome: string;

}

interface SignUpResult {
  id: string;
  nome: string;
  email: string;
  role: string;
  tenantid: string;
  tenant_schema?: string;
  active: boolean;
}

const AuthContext = createContext({} as AuthContextData)

export function signOut() {

  try {
    clearAuthTokenCookies(null);
    if (typeof window !== 'undefined') {
      window.localStorage.removeItem('vecontab_token');
    }
    Router.push('/auth/login');

  } catch (err) {

  }
}

export function AuthProvider({ children }: AuthProviderProps) {
  const [user, setUser] = useState<UserProps>()
  const isAuthenticated = !!user;

  useEffect(() => {
    const cookieToken = getAuthTokenFromParsedCookies(parseCookies());
    const token =
      cookieToken ||
      (typeof window !== 'undefined' ? String(window.localStorage.getItem('vecontab_token') ?? '').trim() : '');

    if (token) {
      api.defaults.headers.common['Authorization'] = `Bearer ${token}`;
      api.get('/api/me').then(response => {

        //const { id, nome, email, empresa, tenant } = response.data
        const { id, nome, email, empresa, tenant } = response.data?.usuarios?.[0]?.resultado ?? response.data
        setUser({ id, nome, email, tenant })

      })
        .catch((err) => {
          const axiosErr = err as AxiosError;
          if (axiosErr?.response?.status === 401) {
            signOut();
          }
        })
    }
  }, [])

  const signIn = async ({ email, password }: SignInProps) => {

    //async function signIn({ email, password }: SignInProps) {
    try {
      const response = await api.post("/api/session", {
        email,
        password,
      })

      const { id, nome, token, empresa } = response.data;


      setCookie(undefined, AUTH_TOKEN_COOKIE, token, {
        maxAge: 60 * 60 * 24 * 30, // Expirar em 1 mês
        path: '/',
        sameSite: 'lax',
      })
      clearLegacyAuthTokenCookieBrowser();
      try {
        window.localStorage.setItem('vecontab_token', token);
      } catch {
        // ignore
      }

      api.defaults.headers.common['Authorization'] = `Bearer ${token}`

      try {
        const me = await api.get('/api/me');
        const meData = me.data?.usuarios?.[0]?.resultado ?? me.data;
        const tenant = meData?.tenant ?? undefined;
        setUser({
          id: meData?.id ?? id,
          nome: meData?.nome ?? nome,
          email: meData?.email ?? email,
          tenant,
        });
      } catch {
        setUser({
          id,
          nome,
          email,
        });
      }


      Router.push('/')


    } catch (err) {
      const axiosErr = err as AxiosError<{ error?: string; message?: string }>;
      const message =
        axiosErr.response?.data?.error ||
        axiosErr.response?.data?.message ||
        axiosErr.message ||
        'Erro ao autenticar';
      throw new Error(message)

    }
  }

  async function signUp({ nome, email, password, empresa_nome }: SignUpProps): Promise<SignUpResult> {
    try {
      const response = await api.post("/api/registro", {
        nome,
        email,
        password,
        empresa_nome,
      })

      Router.push('/auth/login')
      return response.data as SignUpResult;

    } catch (err) {
      const axiosErr = err as AxiosError<{ error?: string; message?: string }>;
      const message =
        axiosErr.response?.data?.error ||
        axiosErr.response?.data?.message ||
        (err instanceof Error ? err.message : 'Erro ao registrar usuário');
      throw new Error(message)
    }
  }

  async function logoutUser() {
    try {
      clearAuthTokenCookies(null);
      if (typeof window !== 'undefined') {
        window.localStorage.removeItem('vecontab_token');
      }
      Router.push('/auth/login');
      setUser(undefined)
    } catch (err) {
      //console.log("Erro ao Sair", err)
      const message = err instanceof Error ? err.message : 'Erro ao sair';
      throw new Error(message)

    }
  }

  return (
    <AuthContext.Provider
      value={{
        user,
        isAuthenticated,
        signIn,
        signUp,
        logoutUser,
      }}>
      {children}
    </AuthContext.Provider>
  )
}

export default AuthContext;