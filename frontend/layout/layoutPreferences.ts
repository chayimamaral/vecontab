import type { LayoutConfig } from '../types/types';

/** Estado inicial igual ao LayoutProvider (tema padrão da aplicação). */
export const DEFAULT_LAYOUT_CONFIG: LayoutConfig = {
  ripple: false,
  inputStyle: 'outlined',
  menuMode: 'static',
  colorScheme: 'dark',
  theme: 'vela-blue',
  scale: 12,
};

const STORAGE_PREFIX = '@vecontab.layoutPrefs.v1';

export function layoutPrefsStorageKey(userId: string): string {
  return `${STORAGE_PREFIX}:${userId}`;
}

/** Valida e devolve apenas chaves conhecidas do layout (evita lixo no localStorage). */
export function mergeStoredLayout(parsed: unknown): Partial<LayoutConfig> | null {
  if (!parsed || typeof parsed !== 'object') {
    return null;
  }
  const o = parsed as Record<string, unknown>;
  const out: Partial<LayoutConfig> = {};

  if (typeof o.ripple === 'boolean') {
    out.ripple = o.ripple;
  }
  if (o.inputStyle === 'outlined' || o.inputStyle === 'filled') {
    out.inputStyle = o.inputStyle;
  }
  if (o.menuMode === 'static' || o.menuMode === 'overlay') {
    out.menuMode = o.menuMode;
  }
  if (o.colorScheme === 'light' || o.colorScheme === 'dark') {
    out.colorScheme = o.colorScheme;
  }
  if (typeof o.theme === 'string' && o.theme.trim() !== '') {
    out.theme = o.theme.trim();
  }
  if (typeof o.scale === 'number' && Number.isFinite(o.scale) && o.scale >= 12 && o.scale <= 16) {
    out.scale = o.scale;
  }

  return Object.keys(out).length > 0 ? out : null;
}
