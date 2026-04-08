import { Button } from 'primereact/button';
import { Card } from 'primereact/card';
import { Toast } from 'primereact/toast';
import { useQuery } from '@tanstack/react-query';
import { useEffect, useRef, useState } from 'react';
import setupAPIClient from '../../components/api/api';
import { withAuthServerSideProps } from '../../components/utils/crudUtils';
import { GetServerSidePropsContext } from 'next';

type Config = {
    gerar_das_por_procuracao: boolean;
    gerar_darf_dctfweb_por_procuracao: boolean;
};

export default function GeracaoGuiasPage() {
    const toast = useRef<Toast>(null);
    const api = setupAPIClient(undefined);
    const [form, setForm] = useState<Config>({
        gerar_das_por_procuracao: false,
        gerar_darf_dctfweb_por_procuracao: false,
    });

    const { data, refetch, isFetching } = useQuery({
        queryKey: ['tenant-config-geracao-guias'],
        queryFn: async () => {
            const { data } = await api.get('/api/tenant-configuracoes');
            return data?.configuracoes ?? {};
        },
    });

    useEffect(() => {
        if (!data) return;
        setForm({
            gerar_das_por_procuracao: Boolean(data.gerar_das_por_procuracao),
            gerar_darf_dctfweb_por_procuracao: Boolean(data.gerar_darf_dctfweb_por_procuracao),
        });
    }, [data]);

    const save = async () => {
        try {
            await api.put('/api/tenant-configuracoes', form);
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Configuração salva', life: 3000 });
            await refetch();
        } catch (e: any) {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: e?.response?.data?.message || 'Falha ao salvar', life: 4000 });
        }
    };

    const onDAS = (e: React.ChangeEvent<HTMLInputElement>) => setForm((prev) => ({ ...prev, gerar_das_por_procuracao: e.target.checked }));
    const onDARF = (e: React.ChangeEvent<HTMLInputElement>) => setForm((prev) => ({ ...prev, gerar_darf_dctfweb_por_procuracao: e.target.checked }));

    return (
        <div className="grid">
            <div className="col-12">
                <Toast ref={toast} />
                <Card title="Geração de Guias (ADMIN)">
                    <div className="field-checkbox mb-3">
                        <input id="das" type="checkbox" checked={form.gerar_das_por_procuracao} onChange={onDAS} />
                        <label htmlFor="das" className="ml-2">Gerar guia DAS pela API Integra Contador com certificado digital do contador (por procuração)</label>
                    </div>
                    <div className="field-checkbox mb-4">
                        <input id="darf" type="checkbox" checked={form.gerar_darf_dctfweb_por_procuracao} onChange={onDARF} />
                        <label htmlFor="darf" className="ml-2">Gerar guia DARF DCTFWeb pela API Integra Contador com certificado digital do contador (por procuração)</label>
                    </div>
                    <Button label={isFetching ? 'Salvando...' : 'Salvar'} icon="pi pi-save" onClick={save} disabled={isFetching} />
                </Card>
            </div>
        </div>
    );
}

export const getServerSideProps = withAuthServerSideProps(async (_ctx: GetServerSidePropsContext) => ({}));
