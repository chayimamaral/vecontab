import { Button } from 'primereact/button';
import { Card } from 'primereact/card';
import { InputText } from 'primereact/inputtext';
import { Toast } from 'primereact/toast';
import { useQuery } from '@tanstack/react-query';
import { useRef, useState } from 'react';
import setupAPIClient from '../../components/api/api';
import { withAuthServerSideProps } from '../../components/utils/crudUtils';
import { GetServerSidePropsContext } from 'next';

type Chaves = {
    consumer_key: string;
    consumer_secret: string;
};

export default function ApiIntegraContadorPage() {
    const toast = useRef<Toast>(null);
    const api = setupAPIClient(undefined);
    const [form, setForm] = useState<Chaves>({ consumer_key: '', consumer_secret: '' });

    const { data, refetch, isFetching } = useQuery({
        queryKey: ['chaves-super'],
        queryFn: async () => {
            const { data } = await api.get('/api/chavessuper');
            const ch = data?.chaves ?? {};
            const parsed: Chaves = {
                consumer_key: ch.consumer_key ?? '',
                consumer_secret: ch.consumer_secret ?? '',
            };
            setForm(parsed);
            return parsed;
        },
    });

    const save = async () => {
        if (!form.consumer_key.trim() || !form.consumer_secret.trim()) {
            toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Preencha Consumer Key e Consumer Secret', life: 3500 });
            return;
        }
        try {
            await api.put('/api/chavessuper', form);
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Chaves salvas', life: 3000 });
            await refetch();
        } catch (e: any) {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: e?.response?.data?.message || 'Falha ao salvar', life: 4000 });
        }
    };

    return (
        <div className="grid">
            <div className="col-12">
                <Toast ref={toast} />
                <Card title="API Integra Contador (SUPER)">
                    <div className="field">
                        <label htmlFor="consumer_key">Consumer Key</label>
                        <InputText id="consumer_key" value={form.consumer_key} onChange={(e) => setForm((prev) => ({ ...prev, consumer_key: e.target.value }))} />
                    </div>
                    <div className="field mt-3">
                        <label htmlFor="consumer_secret">Consumer Secret</label>
                        <InputText id="consumer_secret" value={form.consumer_secret} onChange={(e) => setForm((prev) => ({ ...prev, consumer_secret: e.target.value }))} />
                    </div>
                    <div className="mt-4">
                        <Button label={isFetching ? 'Salvando...' : 'Salvar'} icon="pi pi-save" onClick={save} disabled={isFetching} />
                    </div>
                    {!data && <small className="block mt-3">Nenhuma chave cadastrada para este tenant.</small>}
                </Card>
            </div>
        </div>
    );
}

export const getServerSideProps = withAuthServerSideProps(async (_ctx: GetServerSidePropsContext) => ({}));
