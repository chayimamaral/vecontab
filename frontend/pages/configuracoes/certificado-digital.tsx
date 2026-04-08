import { Button } from 'primereact/button';
import { Card } from 'primereact/card';
import { Dropdown } from 'primereact/dropdown';
import { InputText } from 'primereact/inputtext';
import { Toast } from 'primereact/toast';
import { useQuery } from '@tanstack/react-query';
import { useEffect, useRef, useState } from 'react';
import setupAPIClient from '../../components/api/api';
import { withAuthServerSideProps } from '../../components/utils/crudUtils';
import { GetServerSidePropsContext } from 'next';

type CertConfig = {
    tipo_certificado: string;
    senha_certificado: string;
    nome_certificado: string;
    emitido_para: string;
    emitido_por: string;
    validade_de: string;
    validade_ate: string;
};

const tipos = [
    { label: 'A1', value: 'A1' },
    { label: 'A3', value: 'A3' },
];

export default function CertificadoDigitalPage() {
    const toast = useRef<Toast>(null);
    const fileInputRef = useRef<HTMLInputElement>(null);
    const api = setupAPIClient(undefined);
    const [certFile, setCertFile] = useState<File | null>(null);
    const [form, setForm] = useState<CertConfig>({
        tipo_certificado: '',
        senha_certificado: '',
        nome_certificado: '',
        emitido_para: '',
        emitido_por: '',
        validade_de: '',
        validade_ate: '',
    });

    const { data, refetch, isFetching } = useQuery({
        queryKey: ['certificado-digital-tenant'],
        queryFn: async () => {
            const { data } = await api.get('/api/certificado-digital');
            return data?.certificado ?? {};
        },
    });

    useEffect(() => {
        if (!data) return;
        setForm((prev) => ({
            ...prev,
            tipo_certificado: data.tipo_certificado ?? 'A1',
            senha_certificado: '',
            nome_certificado: data.nome_certificado ?? '',
            emitido_para: data.emitido_para ?? '',
            emitido_por: data.emitido_por ?? '',
            validade_de: data.validade_de ?? '',
            validade_ate: data.validade_ate ?? '',
        }));
    }, [data]);

    const save = async () => {
        try {
            if (certFile) {
                if (!form.senha_certificado.trim()) {
                    toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Informe a senha do certificado digital.', life: 4000 });
                    return;
                }
                const body = new FormData();
                body.append('arquivo', certFile);
                body.append('senha_certificado', form.senha_certificado);
                if (form.emitido_para.trim()) {
                    body.append('titular_nome', form.emitido_para.trim());
                }
                await api.post('/api/certificado-digital/upload', body, {
                    headers: { 'Content-Type': 'multipart/form-data' },
                });
            }
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Certificado salvo', life: 3000 });
            await refetch();
        } catch (e: any) {
            const apiError = e?.response?.data?.error || e?.response?.data?.message || 'Falha ao salvar';
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: apiError, life: 7000 });
        }
    };

    const openFilePicker = () => {
        fileInputRef.current?.click();
    };

    const onFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (!file) return;
        setCertFile(file);
    };

    const onValidadeDeChange = (value: string) => {
        if (!value) {
            setForm((prev) => ({ ...prev, validade_de: '', validade_ate: '' }));
            return;
        }

        const inicio = new Date(`${value}T00:00:00`);
        if (Number.isNaN(inicio.getTime())) {
            setForm((prev) => ({ ...prev, validade_de: value }));
            return;
        }

        const fim = new Date(inicio);
        fim.setFullYear(fim.getFullYear() + 1);
        const fimISO = fim.toISOString().slice(0, 10);

        setForm((prev) => ({
            ...prev,
            validade_de: value,
            validade_ate: fimISO,
        }));
    };

    return (
        <div className="grid">
            <div className="col-12 md:col-10 lg:col-8">
                <Toast ref={toast} />
                <Card>
                    <h3 className="text-left mt-0 mb-4">Certificado Digital (ADMIN)</h3>
                    <div className="grid align-items-center mb-3">
                        <div className="col-12 md:col-4 text-right"><label htmlFor="tipo">Tipo de Certificado</label></div>
                        <div className="col-12 md:col-6">
                            <Dropdown id="tipo" options={tipos} value={form.tipo_certificado} onChange={(e) => setForm((prev) => ({ ...prev, tipo_certificado: e.value ?? '' }))} placeholder="Selecione" className="w-full p-inputtext-sm" />
                        </div>
                    </div>
                    <div className="grid align-items-center mb-3">
                        <div className="col-12 md:col-4 text-right"><label htmlFor="arquivo_nome">Arquivo .pfx</label></div>
                        <div className="col-12 md:col-6">
                            <div className="p-inputgroup">
                                <InputText
                                    id="arquivo_nome"
                                    value={certFile?.name ?? (form.validade_ate ? 'Certificado carregado' : '')}
                                    readOnly
                                    placeholder="Selecione o arquivo PFX"
                                    className="p-inputtext-sm"
                                />
                                <Button icon="pi pi-upload" type="button" onClick={openFilePicker} tooltip="Selecionar arquivo PFX" size="small" />
                            </div>
                            <input ref={fileInputRef} type="file" accept=".pfx,application/x-pkcs12" style={{ display: 'none' }} onChange={onFileChange} />
                        </div>
                    </div>
                    <div className="grid align-items-center mb-3">
                        <div className="col-12 md:col-4 text-right"><label htmlFor="senha">Senha do Certificado Digital</label></div>
                        <div className="col-12 md:col-6">
                            <InputText id="senha" type="password" value={form.senha_certificado} onChange={(e) => setForm((prev) => ({ ...prev, senha_certificado: e.target.value }))} className="w-full p-inputtext-sm" />
                        </div>
                    </div>
                    <div className="grid align-items-center mb-3">
                        <div className="col-12 md:col-4 text-right"><label htmlFor="nome">Nome</label></div>
                        <div className="col-12 md:col-6">
                            <InputText id="nome" value={form.nome_certificado} onChange={(e) => setForm((prev) => ({ ...prev, nome_certificado: e.target.value }))} className="w-full p-inputtext-sm" />
                        </div>
                    </div>
                    <div className="grid align-items-center mb-3">
                        <div className="col-12 md:col-4 text-right"><label htmlFor="emitido_para">Emitido para</label></div>
                        <div className="col-12 md:col-6">
                            <InputText id="emitido_para" value={form.emitido_para} onChange={(e) => setForm((prev) => ({ ...prev, emitido_para: e.target.value }))} className="w-full p-inputtext-sm" />
                        </div>
                    </div>
                    <div className="grid align-items-center mb-3">
                        <div className="col-12 md:col-4 text-right"><label htmlFor="emitido_por">Emitido por</label></div>
                        <div className="col-12 md:col-6">
                            <InputText id="emitido_por" value={form.emitido_por} onChange={(e) => setForm((prev) => ({ ...prev, emitido_por: e.target.value }))} className="w-full p-inputtext-sm" />
                        </div>
                    </div>
                    <div className="grid align-items-center mb-3">
                        <div className="col-12 md:col-4 text-right"><label htmlFor="validade_de">Validade (início e fim)</label></div>
                        <div className="col-12 md:col-6 grid">
                            <div className="col-12 md:col-6">
                                <InputText id="validade_de" type="date" value={form.validade_de} onChange={(e) => onValidadeDeChange(e.target.value)} className="w-full p-inputtext-sm" />
                            </div>
                            <div className="col-12 md:col-6">
                                <InputText id="validade_ate" type="date" value={form.validade_ate} onChange={(e) => setForm((prev) => ({ ...prev, validade_ate: e.target.value }))} className="w-full p-inputtext-sm" />
                            </div>
                        </div>
                    </div>
                    <div className="mt-4">
                        <Button label={isFetching ? 'Salvando...' : 'Salvar'} icon="pi pi-save" onClick={save} disabled={isFetching} />
                    </div>
                </Card>
            </div>
        </div>
    );
}

export const getServerSideProps = withAuthServerSideProps(async (_ctx: GetServerSidePropsContext) => ({}));
