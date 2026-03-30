import Link from 'next/link';
import { Tooltip } from 'primereact/tooltip';
import { canSSRAuth } from '../services/utils/canSSRAuth';

type ModuloAtivo = {
    future?: false;
    titulo: string;
    descricao: string;
    href: string;
    icon: string;
    tooltip: string;
};

type ModuloFuturo = {
    future: true;
    titulo: string;
    descricao: string;
    icon: string;
    tooltip: string;
};

type ModuloCard = ModuloAtivo | ModuloFuturo;

const MODULOS: ModuloCard[] = [
    {
        titulo: 'Compromissos das Empresas',
        descricao: 'Acompanhe vencimentos e status dos compromissos legais gerados por empresa.',
        href: '/compromissos-empresas',
        icon: 'pi pi-list',
        tooltip: 'Abre o acompanhamento em árvore (empresa → compromissos).',
    },
    {
        titulo: 'Agenda',
        descricao: 'Visualize e gerencie a agenda de passos e prazos operacionais.',
        href: '/agenda',
        icon: 'pi pi-calendar',
        tooltip: 'Calendário e detalhes da agenda do tenant.',
    },
    {
        titulo: 'Manutenção de Empresas',
        descricao: 'Cadastro de empresas, rotinas e geração de compromissos após conclusão dos passos.',
        href: '/empresas',
        icon: 'pi pi-building',
        tooltip: 'CRUD de empresas e fluxo de abertura.',
    },
    {
        future: true,
        titulo: 'Relatórios gerenciais',
        descricao: 'Indicadores e exportações para gestão contábil e fiscal.',
        icon: 'pi pi-chart-bar',
        tooltip: 'Implementação futura — painéis e relatórios em desenvolvimento.',
    },
    {
        future: true,
        titulo: 'Obrigações e prazos legais',
        descricao: 'Visão consolidada de obrigações por período e alertas.',
        icon: 'pi pi-bell',
        tooltip: 'Implementação futura — módulo de monitoramento centralizado.',
    },
    {
        future: true,
        titulo: 'Integrações fiscais',
        descricao: 'Conexões com APIs governamentais e troca de arquivos.',
        icon: 'pi pi-cloud-download',
        tooltip: 'Implementação futura — integrações serão adicionadas gradualmente.',
    },
    {
        future: true,
        titulo: 'Compromissos do Dia',
        descricao: 'Compromissos as empresas para o dia atual.',
        icon: 'pi pi-calendar-clock',
        tooltip: 'Implementação futura — integrações serão adicionadas gradualmente.',
    },
    {
        future: true,
        titulo: 'Compromissos por Empresa',
        descricao: 'Compromissos as empresas para o dia atual.',
        icon: 'pi pi-building',
        tooltip: 'Implementação futura — integrações serão adicionadas gradualmente.',
    },
    {
        future: true,
        titulo: 'Compromissos por Período',
        descricao: 'Compromissos as empresas para o dia atual.',
        icon: 'pi pi-bars',
        tooltip: 'Implementação futura — integrações serão adicionadas gradualmente.',
    },
];

function ModuloTile({ modulo }: { modulo: ModuloCard }) {
    const baseClass =
        'dash-modulo-tile flex flex-column align-items-center justify-content-start text-center p-4 h-full border-round-xl ' +
        'transition-all transition-duration-200 no-underline';

    const conteudo = (
        <>
            <span
                className={`inline-flex align-items-center justify-content-center border-circle bg-primary text-primary-contrast mb-3 dash-modulo-icon-wrap ${
                    modulo.future ? 'opacity-60' : ''
                }`}
            >
                <i className={`${modulo.icon} text-3xl`} aria-hidden />
            </span>
            <span className="text-xl font-semibold text-900 mb-2">{modulo.titulo}</span>
            <span className="text-600 line-height-3 text-sm">{modulo.descricao}</span>
            {modulo.future && (
                <span className="mt-3 text-xs font-semibold uppercase letter-spacing-1 text-500">Implementação futura</span>
            )}
        </>
    );

    if (modulo.future) {
        return (
            <div
                className={`${baseClass} surface-card border-1 border-200 surface-hover opacity-80 cursor-default`}
                data-pr-tooltip={modulo.tooltip}
                data-pr-position="top"
            >
                {conteudo}
            </div>
        );
    }

    return (
        <Link
            href={modulo.href}
            className={`${baseClass} surface-card border-1 border-200 shadow-2 hover:border-primary transition-all transition-duration-200`}
            data-pr-tooltip={modulo.tooltip}
            data-pr-position="top"
        >
            {conteudo}
        </Link>
    );
}

export default function Home() {
    return (
        <div className="card">
            <Tooltip target=".dash-modulo-tile" />

            <div className="mb-5">
                <h1 className="m-0 text-3xl font-bold text-900">Bem-vindo ao VECONTAB</h1>
                <p className="mt-2 mb-0 text-600 line-height-3">
                    Escolha um módulo abaixo ou use o menu lateral. Passe o mouse sobre os cartões para dicas rápidas.
                </p>
            </div>

            <div className="grid">
                {MODULOS.map((modulo) => (
                    <div key={modulo.future ? modulo.titulo : modulo.href} className="col-12 sm:col-6 xl:col-4">
                        <ModuloTile modulo={modulo} />
                    </div>
                ))}
            </div>

            <div className="mt-5 pt-4 border-top-1 border-200">
                <p className="m-0 text-sm text-500 text-center">
                    Módulos marcados como <strong>Implementação futura</strong> são placeholders; os demais levam às telas já
                    disponíveis.
                </p>
            </div>

            <style jsx>{`
                .dash-modulo-icon-wrap {
                    width: 4.5rem;
                    height: 4.5rem;
                }
            `}</style>
        </div>
    );
}

export const getServerSideProps = canSSRAuth(async () => {
    return {
        props: {},
    };
});
