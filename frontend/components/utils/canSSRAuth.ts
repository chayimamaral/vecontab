import { GetServerSideProps, GetServerSidePropsContext, GetServerSidePropsResult } from "next";
import { destroyCookie, parseCookies } from "nookies";
import { AuthTokenError } from "../errors/AuthTokenError";

export function canSSRAuth<P extends { [key: string]: any; }>(fn: GetServerSideProps<P>){
  return async (ctx: GetServerSidePropsContext): Promise<GetServerSidePropsResult<P>> => {
    const cookies = parseCookies(ctx);

    const token = cookies['@vecontab.token'];

    if (!token) {
      return {
        redirect: {
          destination: '/auth/login',
          permanent: false,
        }
      }
    }

    try {
      return await fn(ctx);
    } catch (err) {
      if (err instanceof AuthTokenError) {
        destroyCookie(ctx, '@vecontab.token', { path: '/' });
        //destroyCookie(ctx, 'nextauth.refreshToken');
        return {
          redirect: {
            destination: '/auth/login',
            permanent: false,
          }
        }
      }

      return {
        props: {} as P
      }
    }
  }
}