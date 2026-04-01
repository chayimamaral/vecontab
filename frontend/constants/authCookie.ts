import type { IncomingMessage, ServerResponse } from 'http';
import type { GetServerSidePropsContext } from 'next';
import { destroyCookie, parseCookies } from 'nookies';

/** Compatível com RFC 6265 / pacote `cookie` >= 0.7 (`@` não é permitido em cookie-name). */
export const AUTH_TOKEN_COOKIE = 'vecontab_token';

const AUTH_TOKEN_COOKIE_LEGACY = '@vecontab.token';

export function getAuthTokenFromParsedCookies(cookies: Record<string, string>): string | undefined {
    const v = cookies[AUTH_TOKEN_COOKIE] ?? cookies[AUTH_TOKEN_COOKIE_LEGACY];
    return v?.trim() || undefined;
}

function appendSetCookie(res: ServerResponse<IncomingMessage>, fragment: string): void {
    const prev = res.getHeader('Set-Cookie');
    const list = Array.isArray(prev) ? [...prev] : prev ? [String(prev)] : [];
    list.push(fragment);
    res.setHeader('Set-Cookie', list);
}

/**
 * Remove o cookie de sessão (nome novo + legado). O legado não pode usar `nookies` com `cookie@0.7`.
 */
/** Após novo login: remove o cookie antigo para não manter duas sessões. */
export function clearLegacyAuthTokenCookieBrowser(): void {
    if (typeof document !== 'undefined') {
        document.cookie = `${AUTH_TOKEN_COOKIE_LEGACY}=; Path=/; Max-Age=0`;
    }
}

export function clearAuthTokenCookies(ctx?: GetServerSidePropsContext | null): void {
    destroyCookie(ctx, AUTH_TOKEN_COOKIE, { path: '/' });

    const legacyClear = `${AUTH_TOKEN_COOKIE_LEGACY}=; Path=/; Max-Age=0`;
    if (typeof document !== 'undefined') {
        document.cookie = legacyClear;
        return;
    }

    const res = ctx?.res;
    if (res && typeof res.setHeader === 'function' && !res.writableEnded) {
        appendSetCookie(res, legacyClear);
    }
}

export { parseCookies };
