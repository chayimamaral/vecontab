-- Para bancos onde 014 foi aplicado antes da criação de cnae_ibge_hierarquia.
CREATE TABLE IF NOT EXISTS public.cnae_ibge_hierarquia (
    subclasse TEXT PRIMARY KEY,
    secao     TEXT NOT NULL,
    divisao   TEXT NOT NULL,
    grupo     TEXT NOT NULL,
    classe    TEXT NOT NULL
);
