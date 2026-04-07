import { Button } from 'primereact/button';
import { Card } from 'primereact/card';
import { Dropdown } from 'primereact/dropdown';
import { InputText } from 'primereact/inputtext';
import { Toast } from 'primereact/toast';
import { useQuery } from '@tanstack/react-query';
import { useRef, useState } from 'react';
import setupAPIClient from '../../components/api/api';
import { withAuthServerSideProps } from '../../components/utils/crudUtils';
import { GetServerSidePropsContext } from 'next';

type CertConfig = {
    tipo_certificado: string;
    local_arquivo_certificado: string;
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
    const folderInputRef = useRef<HTMLInputElement>(null);
    const api = setupAPIClient(undefined);
    const [form, setForm] = useState<CertConfig>({
        tipo_certificado: '',
        local_arquivo_certificado: '',
        senha_certificado: '',
        nome_certificado: '',
        emitido_para: '',
        emitido_por: '',
        validade_de: '',
        validade_ate: '',
    });
    const folderInputAttrs = { webkitdirectory: 'true', directory: 'true' } as any;

    const { refetch, isFetching } = useQuery({
        queryKey: ['tenant-config-certificado-digital'],
        queryFn: async () => {
            const { data } = await api.get('/api/tenant-configuracoes');
            const cfg = data?.configuracoes ?? {};
            setForm((prev) => ({
                ...prev,
                tipo_certificado: cfg.tipo_certificado ?? '',
                local_arquivo_certificado: cfg.local_arquivo_certificado ?? '',
                senha_certificado: cfg.senha_certificado ?? '',
                nome_certificado: cfg.nome_certificado ?? '',
                emitido_para: cfg.emitido_para ?? '',
                emitido_por: cfg.emitido_por ?? '',
                validade_de: cfg.validade_de ?? '',
                validade_ate: cfg.validade_ate ?? '',
            }));
            return cfg;
        },
    });

    const save = async () => {
        try {
            await api.put('/api/tenant-configuracoes', form);
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Certificado salvo', life: 3000 });
            await refetch();
        } catch (e: any) {
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: e?.response?.data?.message || 'Falha ao salvar', life: 4000 });
        }
    };

    const openFolderPicker = () => {
        folderInputRef.current?.click();
    };

    const onFolderChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (!file) return;
        const rel = (file as File & { webkitRelativePath?: string }).webkitRelativePath || '';
        const folder = rel.split('/')[0] || file.name;
        setForm((prev) => ({ ...prev, local_arquivo_certificado: folder }));
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
                    <h3 className="text-right mt-0 mb-4">Certificado Digital (ADMIN)</h3>
                    <div className="grid align-items-center mb-3">
                        <div className="col-12 md:col-4 text-right"><label htmlFor="tipo">Tipo de Certificado</label></div>
                        <div className="col-12 md:col-6">
                            <Dropdown id="tipo" options={tipos} value={form.tipo_certificado} onChange={(e) => setForm((prev) => ({ ...prev, tipo_certificado: e.value ?? '' }))} placeholder="Selecione" className="w-full p-inputtext-sm" />
                        </div>
                    </div>
                    <div className="grid align-items-center mb-3">
                        <div className="col-12 md:col-4 text-right"><label htmlFor="local">Local do Arquivo</label></div>
                        <div className="col-12 md:col-6">
                            <div className="p-inputgroup">
                                <InputText id="local" value={form.local_arquivo_certificado} onChange={(e) => setForm((prev) => ({ ...prev, local_arquivo_certificado: e.target.value }))} placeholder="Selecione a pasta no computador do cliente" className="p-inputtext-sm" />
                                <Button icon="pi pi-folder-open" type="button" onClick={openFolderPicker} tooltip="Selecionar pasta" size="small" />
                            </div>
                            <input ref={folderInputRef} type="file" style={{ display: 'none' }} onChange={onFolderChange} {...folderInputAttrs} />
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
