import { useMemo, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Card } from 'primereact/card';
import { Toast } from 'primereact/toast';
import { DataTable } from 'primereact/datatable';
import { Column } from 'primereact/column';
import { Button } from 'primereact/button';
import { InputText } from 'primereact/inputtext';
import { InputNumber } from 'primereact/inputnumber';
import { Dropdown } from 'primereact/dropdown';
import { Dialog } from 'primereact/dialog';
import { withAuthServerSideProps } from '../../components/utils/crudUtils';
import { GetServerSidePropsContext } from 'next';
import setupAPIClient from '../../components/api/api';
import IntegraTabelaConsumoService, { IntegraGasto, TabelaConsumoFaixa } from '../../services/cruds/IntegraTabelaConsumoService';

type FormFaixa = {
    id: string;
    tipo: string;
    faixa: number;
    quantidade_de: number;
    quantidade_ate: number | null;
    preco: number;
};

const emptyForm: FormFaixa = {
    id: '',
    tipo: 'consultar',
    faixa: 1,
    quantidade_de: 1,
    quantidade_ate: null,
    preco: 0,
};

export default function IntegraContadorTabelaConsumoPage() {
    const toast = useRef<Toast>(null);
    const svc = useMemo(() => IntegraTabelaConsumoService(), []);
    const api = setupAPIClient(undefined);
    const [filtroTipo, setFiltroTipo] = useState<string>('');
    const [filtroEmpresa, setFiltroEmpresa] = useState<string>('');
    const [dialogVisible, setDialogVisible] = useState(false);
    const [form, setForm] = useState<FormFaixa>(emptyForm);
    const [submitted, setSubmitted] = useState(false);

    const { data: roleData } = useQuery({
        queryKey: ['integra-tabela-consumo-role'],
        queryFn: async () => {
            const { data } = await api.get('/api/usuariorole');
            return data?.logado?.role ?? '';
        },
    });
    const podeManter = roleData === 'SUPER';

    const { data: faixas = [], isFetching: loadingFaixas, refetch: refetchFaixas } = useQuery<TabelaConsumoFaixa[]>({
        queryKey: ['integra-tabela-consumo-faixas', filtroTipo],
        queryFn: () => svc.listFaixas(filtroTipo),
    });

    const { data: gastosResult, isFetching: loadingGastos, refetch: refetchGastos } = useQuery({
        queryKey: ['integra-tabela-consumo-gastos', filtroTipo, filtroEmpresa],
        queryFn: () => svc.listGastos({ tipo: filtroTipo, empresaDocumento: filtroEmpresa.replace(/\D/g, '') }),
    });

    const gastos = gastosResult?.gastos ?? [];
    const totalValor = gastosResult?.totalValor ?? 0;
    const totalQuantidade = gastosResult?.totalQuantidade ?? 0;

    const abrirNovo = () => {
        setSubmitted(false);
        setForm(emptyForm);
        setDialogVisible(true);
    };

    const abrirEditar = (faixa: TabelaConsumoFaixa) => {
        setSubmitted(false);
        setForm({
            id: faixa.id,
            tipo: faixa.tipo,
            faixa: faixa.faixa,
            quantidade_de: faixa.quantidade_de,
            quantidade_ate: faixa.quantidade_ate ?? null,
            preco: faixa.preco,
        });
        setDialogVisible(true);
    };

    const salvar = async () => {
        setSubmitted(true);
        if (!form.tipo.trim() || form.faixa <= 0 || form.quantidade_de <= 0 || form.preco < 0) {
            return;
        }
        if (form.quantidade_ate !== null && form.quantidade_ate < form.quantidade_de) {
            toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Quantidade final deve ser maior ou igual à inicial.', life: 4000 });
            return;
        }
        try {
            const payload = {
                id: form.id,
                tipo: form.tipo.trim().toLowerCase(),
                faixa: form.faixa,
                quantidade_de: form.quantidade_de,
                quantidade_ate: form.quantidade_ate,
                preco: form.preco,
            };
            if (form.id) {
                await svc.updateFaixa(payload);
            } else {
                await svc.createFaixa(payload);
            }
            setDialogVisible(false);
            await refetchFaixas();
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Faixa salva.', life: 2500 });
        } catch (e: any) {
            const msg = e?.response?.data?.error || e?.response?.data?.message || 'Falha ao salvar faixa';
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: msg, life: 6000 });
        }
    };

    const excluir = async (id: string) => {
        try {
            await svc.deleteFaixa(id);
            await refetchFaixas();
            toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Faixa excluída.', life: 2500 });
        } catch (e: any) {
            const msg = e?.response?.data?.error || e?.response?.data?.message || 'Falha ao excluir faixa';
            toast.current?.show({ severity: 'error', summary: 'Erro', detail: msg, life: 6000 });
        }
    };

    const moedaBody = (row: { [k: string]: any }, field: string) =>
        Number(row[field] ?? 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

    const acoesBody = (row: TabelaConsumoFaixa) => {
        if (!podeManter) return null;
        return (
            <div className="flex gap-2">
                <Button type="button" icon="pi pi-pencil" rounded severity="success" onClick={() => abrirEditar(row)} />
                <Button type="button" icon="pi pi-trash" rounded severity="warning" onClick={() => void excluir(row.id)} />
            </div>
        );
    };

    return (
        <div className="grid">
            <Toast ref={toast} />
            <div className="col-12">
                <Card title="Integra Contador - Tabela de Consumo">
                    <div className="grid">
                        <div className="col-12 md:col-3">
                            <label htmlFor="filtro-tipo" className="block mb-2 font-medium">Tipo</label>
                            <Dropdown
                                inputId="filtro-tipo"
                                className="w-full"
                                value={filtroTipo}
                                options={[
                                    { label: 'Todos', value: '' },
                                    { label: 'Consultar', value: 'consultar' },
                                    { label: 'Emitir', value: 'emitir' },
                                    { label: 'Declarar', value: 'declarar' },
                                ]}
                                optionLabel="label"
                                optionValue="value"
                                onChange={(e) => setFiltroTipo(e.value ?? '')}
                            />
                        </div>
                        {podeManter && (
                            <div className="col-12 md:col-3 flex align-items-end">
                                <Button type="button" label="Nova faixa" icon="pi pi-plus" onClick={abrirNovo} />
                            </div>
                        )}
                    </div>
                    <DataTable value={faixas} dataKey="id" loading={loadingFaixas} stripedRows responsiveLayout="scroll">
                        <Column field="tipo" header="Tipo" />
                        <Column field="faixa" header="Faixa" />
                        <Column field="quantidade_de" header="De" />
                        <Column field="quantidade_ate" header="Até" body={(row) => (row.quantidade_ate ?? 'Acima')} />
                        <Column field="preco" header="Preço" body={(row) => moedaBody(row, 'preco')} />
                        {podeManter && <Column header="Ações" body={acoesBody} />}
                    </DataTable>
                    <div className="flex justify-content-start mt-2">
                        <Button type="button" icon="pi pi-refresh" tooltip="Atualizar" className="p-button-text" onClick={() => void refetchFaixas()} />
                    </div>
                </Card>
            </div>
            <div className="col-12">
                <Card title="Gastos por Tenant e Empresa">
                    <div className="grid">
                        <div className="col-12 md:col-3">
                            <label htmlFor="filtro-empresa" className="block mb-2 font-medium">Empresa (CNPJ/CPF)</label>
                            <InputText id="filtro-empresa" className="w-full" value={filtroEmpresa} onChange={(e) => setFiltroEmpresa(e.target.value.replace(/\D/g, ''))} />
                        </div>
                        <div className="col-12 md:col-3 flex align-items-end">
                            <Button type="button" icon="pi pi-refresh" label="Atualizar gastos" onClick={() => void refetchGastos()} loading={loadingGastos} />
                        </div>
                    </div>
                    <div className="mb-2 text-700">
                        Quantidade total: <strong>{totalQuantidade}</strong> | Valor total: <strong>{totalValor.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })}</strong>
                    </div>
                    <DataTable value={gastos as IntegraGasto[]} dataKey="id" loading={loadingGastos} stripedRows responsiveLayout="scroll">
                        <Column field="empresa_documento" header="Empresa" />
                        <Column field="tipo" header="Tipo" />
                        <Column field="id_sistema" header="idSistema" />
                        <Column field="id_servico" header="idServico" />
                        <Column field="consumo_mes" header="Consumo mês" />
                        <Column field="faixa_aplicada" header="Faixa" />
                        <Column field="preco_unitario" header="Preço unitário" body={(row) => moedaBody(row, 'preco_unitario')} />
                        <Column field="valor_total" header="Valor total" body={(row) => moedaBody(row, 'valor_total')} />
                        <Column field="processado_em" header="Processado em" />
                    </DataTable>
                </Card>
            </div>
            <Dialog
                visible={dialogVisible}
                onHide={() => setDialogVisible(false)}
                header={form.id ? 'Editar faixa' : 'Nova faixa'}
                style={{ width: 'min(94vw, 40rem)' }}
                modal
                footer={
                    <div className="flex justify-content-end gap-2">
                        <Button type="button" label="Cancelar" text onClick={() => setDialogVisible(false)} />
                        <Button type="button" label="Salvar" icon="pi pi-check" onClick={() => void salvar()} />
                    </div>
                }
            >
                <div className="grid p-fluid">
                    <div className="col-12 md:col-6">
                        <label htmlFor="tipo-form" className="font-medium">Tipo</label>
                        <InputText id="tipo-form" value={form.tipo} onChange={(e) => setForm((p) => ({ ...p, tipo: e.target.value }))} className={submitted && !form.tipo.trim() ? 'p-invalid' : ''} />
                    </div>
                    <div className="col-12 md:col-3">
                        <label htmlFor="faixa-form" className="font-medium">Faixa</label>
                        <InputNumber id="faixa-form" value={form.faixa} onValueChange={(e) => setForm((p) => ({ ...p, faixa: Number(e.value ?? 0) }))} useGrouping={false} />
                    </div>
                    <div className="col-12 md:col-3">
                        <label htmlFor="preco-form" className="font-medium">Preço</label>
                        <InputNumber id="preco-form" value={form.preco} onValueChange={(e) => setForm((p) => ({ ...p, preco: Number(e.value ?? 0) }))} mode="currency" currency="BRL" locale="pt-BR" minFractionDigits={2} maxFractionDigits={4} />
                    </div>
                    <div className="col-12 md:col-6">
                        <label htmlFor="de-form" className="font-medium">Quantidade inicial</label>
                        <InputNumber id="de-form" value={form.quantidade_de} onValueChange={(e) => setForm((p) => ({ ...p, quantidade_de: Number(e.value ?? 0) }))} useGrouping={false} />
                    </div>
                    <div className="col-12 md:col-6">
                        <label htmlFor="ate-form" className="font-medium">Quantidade final (vazio = aberto)</label>
                        <InputNumber id="ate-form" value={form.quantidade_ate} onValueChange={(e) => setForm((p) => ({ ...p, quantidade_ate: e.value === null ? null : Number(e.value) }))} useGrouping={false} />
                    </div>
                </div>
            </Dialog>
        </div>
    );
}

export const getServerSideProps = withAuthServerSideProps(async (_ctx: GetServerSidePropsContext) => ({}));
