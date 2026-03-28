import { createContext, ReactNode, useEffect, useState } from 'react';
import { destroyCookie, setCookie, parseCookies } from 'nookies';
import Router from 'next/router';
import { AxiosError } from 'axios';

import api from '../api/apiClient'

interface AuthContextData {
  user?: UserProps | undefined;
  isAuthenticated: boolean;
  signIn: (credentials: SignInProps) => Promise<void>;
  signUp: (credentials: SignUpProps) => Promise<void>;
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

}

const AuthContext = createContext({} as AuthContextData)

export function signOut() {

  try {
    destroyCookie(null, '@vecontab.token', { path: '/' })
    Router.push('/auth/login');

  } catch (err) {

  }
}

export function AuthProvider({ children }: AuthProviderProps) {
  const [user, setUser] = useState<UserProps>()
  const isAuthenticated = !!user;

  useEffect(() => {
    const { '@vecontab.token': token } = parseCookies()

    if (token) {
      api.get('/api/me').then(response => {

        //const { id, nome, email, empresa, tenant } = response.data
        const { id, nome, email, empresa, tenant } = response.data?.usuarios?.[0]?.resultado ?? response.data
        setUser({ id, nome, email, tenant })

      })
        .catch(() => {
          signOut()
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


      setCookie(undefined, '@vecontab.token', token, {
        maxAge: 60 * 60 * 24 * 30, // Expirar em 1 mês
        path: '/'
      })

      setUser({
        id,
        nome,
        email
      })

      api.defaults.headers.common['Authorization'] = `Bearer ${token}`


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

  async function signUp({ nome, email, password, }: SignUpProps) {
    try {
      const response = await api.post("/api/registro", {
        nome,
        email,
        password,
      })

      Router.push('/auth/login')

    } catch (err) {
      const message = err instanceof Error ? err.message : 'Erro ao registrar usuário';
      throw new Error(message)
    }
  }

  async function logoutUser() {
    try {
      destroyCookie(null, '@vecontab.token', { path: '/' })
      //setUser(undefined)
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