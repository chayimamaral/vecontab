import { GetServerSideProps, GetServerSidePropsContext, GetServerSidePropsResult } from "next";
import { parseCookies } from "nookies";
import { AuthTokenError } from "../errors/AuthTokenError";
import { clearAuthTokenCookies, getAuthTokenFromParsedCookies } from "../../constants/authCookie";

export function canSSRAuth<P extends { [key: string]: any; }>(fn: GetServerSideProps<P>){
  return async (ctx: GetServerSidePropsContext): Promise<GetServerSidePropsResult<P>> => {
    const cookies = parseCookies(ctx);

    const token = getAuthTokenFromParsedCookies(cookies);

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
        clearAuthTokenCookies(ctx);
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