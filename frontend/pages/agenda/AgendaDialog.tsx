import React, { useState, useEffect, useRef } from 'react';
import FullCalendar from '@fullcalendar/react';
import dayGridPlugin from '@fullcalendar/daygrid';
import timeGridPlugin from '@fullcalendar/timegrid';
import interactionPlugin from '@fullcalendar/interaction';
import AgendaService from '../../services/cruds/AgendaService';
import { Calendar as PRCalendar } from 'primereact/calendar';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
import { Button } from 'primereact/button';
import { Toast } from 'primereact/toast';
import { ConfirmDialog, confirmDialog } from 'primereact/confirmdialog';

type AgendaEventRow = {
  id: string;
  title: string;
  start: string;
  end?: string;
  backgroundColor?: string;
  textColor?: string;
  borderColor?: string;
};

function toISODateLocal(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function mapDetalhesParaFC(rows: AgendaEventRow[]) {
  return rows.map((e) => ({
    id: e.id,
    title: e.title,
    start: (e.start || '').slice(0, 10),
    end: (e.end || e.start || '').slice(0, 10),
    allDay: true,
    backgroundColor: e.backgroundColor,
    borderColor: e.borderColor,
    textColor: e.textColor,
  }));
}

type SecondCalendarProps = {
  eventData: { start?: Date | string } | null | undefined;
  agenda_id: string;
  isOpen: boolean;
};

const SecondCalendar = ({ eventData, agenda_id, isOpen }: SecondCalendarProps) => {
  if (typeof window === 'undefined') {
    return null;
  }

  const [events, setEvents] = useState<any[]>([]);
  const [isUpdating, setIsUpdating] = useState(false);
  const [eventDialog, setEventDialog] = useState(false);
  const [clickedEvent, setClickedEvent] = useState<any>(null);
  const [changedEvent, setChangedEvent] = useState<{
    title: string;
    start: Date | null;
    end: Date | null;
  }>({ title: '', start: null, end: null });
  const [novoOpen, setNovoOpen] = useState(false);
  const [novoDesc, setNovoDesc] = useState('');
  const [novoInicio, setNovoInicio] = useState<Date | null>(null);
  const [novoTermino, setNovoTermino] = useState<Date | null>(null);
  const calendarRef = useRef<any>(null);
  const toast = useRef<Toast>(null);
  const agendaService = useRef(AgendaService());

  const focusDate = eventData?.start ? new Date(eventData.start as string | Date) : new Date();

  useEffect(() => {
    if (!agenda_id) {
      return;
    }
    agendaService.current
      .getDetalhes({ agenda_id })
      .then((raw) => {
        const list = Array.isArray(raw) ? raw : (raw as { events?: AgendaEventRow[] })?.events;
        const arr = Array.isArray(list) ? (list as AgendaEventRow[]) : [];
        setEvents(mapDetalhesParaFC(arr));
      })
      .catch(() => setEvents([]));
    if (isUpdating) {
      setIsUpdating(false);
    }
  }, [agenda_id, isUpdating]);

  useEffect(() => {
    if (!isOpen) {
      return;
    }
    const timer = setTimeout(() => {
      const calendarApi = calendarRef.current?.getApi?.();
      if (calendarApi) {
        calendarApi.gotoDate(focusDate);
        calendarApi.updateSize();
      }
    }, 180);
    return () => clearTimeout(timer);
  }, [focusDate, isOpen, events.length]);

  const itemConcluido = (ev: any) =>
    String(ev?.backgroundColor || '')
      .trim()
      .toUpperCase() === '#22C55E';

  const concluirPasso = async () => {
    const agendaItemId = clickedEvent?.id;
    if (!agendaItemId || !agenda_id) {
      toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Item inválido.', life: 3000 });
      return;
    }
    try {
      const response = await agendaService.current.concluirPasso({
        agenda_id: String(agenda_id),
        agenda_item_id: String(agendaItemId),
      });
      toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Passo concluído.', life: 3000 });
      if (response?.data?.todos_passos_concluidos) {
        toast.current?.show({ severity: 'info', summary: 'Processo', detail: 'Todos os passos concluídos.', life: 4000 });
      }
      setEventDialog(false);
      setIsUpdating(true);
    } catch (error: unknown) {
      const msg = error instanceof Error ? error.message : 'Erro ao concluir.';
      toast.current?.show({ severity: 'error', summary: 'Erro', detail: msg, life: 4000 });
    }
  };

  const reabrirPasso = async () => {
    const agendaItemId = clickedEvent?.id;
    if (!agendaItemId || !agenda_id) {
      return;
    }
    try {
      await agendaService.current.reabrirPasso({
        agenda_id: String(agenda_id),
        agenda_item_id: String(agendaItemId),
      });
      toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Passo reaberto.', life: 3000 });
      setEventDialog(false);
      setIsUpdating(true);
    } catch (error: unknown) {
      const msg = error instanceof Error ? error.message : 'Erro ao reabrir.';
      toast.current?.show({ severity: 'error', summary: 'Erro', detail: msg, life: 4000 });
    }
  };

  const salvarAlteracaoItem = async () => {
    const agendaItemId = clickedEvent?.id;
    if (!agendaItemId || !agenda_id) {
      return;
    }
    const di = changedEvent.start ? toISODateLocal(changedEvent.start) : '';
    const df = changedEvent.end ? toISODateLocal(changedEvent.end) : di;
    if (!changedEvent.title.trim() || !di) {
      toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Descrição e início são obrigatórios.', life: 3500 });
      return;
    }
    try {
      await agendaService.current.updateAgendaItem({
        agenda_id: String(agenda_id),
        agenda_item_id: String(agendaItemId),
        descricao: changedEvent.title.trim(),
        inicio: di,
        termino: df,
      });
      toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Item atualizado.', life: 3000 });
      setEventDialog(false);
      setIsUpdating(true);
    } catch (error: unknown) {
      const msg = error instanceof Error ? error.message : 'Erro ao salvar.';
      toast.current?.show({ severity: 'error', summary: 'Erro', detail: msg, life: 4000 });
    }
  };

  const excluirItem = () => {
    const agendaItemId = clickedEvent?.id;
    if (!agendaItemId || !agenda_id) {
      return;
    }
    confirmDialog({
      message: 'Excluir este item da agenda? A tabela de passos não será alterada.',
      header: 'Confirmar exclusão',
      icon: 'pi pi-exclamation-triangle',
      acceptLabel: 'Excluir',
      rejectLabel: 'Cancelar',
      acceptClassName: 'p-button-danger',
      accept: async () => {
        try {
          await agendaService.current.deleteAgendaItem(String(agenda_id), String(agendaItemId));
          toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Item excluído.', life: 3000 });
          setEventDialog(false);
          setIsUpdating(true);
        } catch (error: unknown) {
          const msg = error instanceof Error ? error.message : 'Erro ao excluir.';
          toast.current?.show({ severity: 'error', summary: 'Erro', detail: msg, life: 4000 });
        }
      },
    });
  };

  const salvarNovoItem = async () => {
    if (!agenda_id) {
      return;
    }
    const di = novoInicio ? toISODateLocal(novoInicio) : '';
    const df = novoTermino ? toISODateLocal(novoTermino) : di;
    if (!novoDesc.trim() || !di) {
      toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Descrição e início são obrigatórios.', life: 3500 });
      return;
    }
    try {
      await agendaService.current.createAgendaItem({
        agenda_id: String(agenda_id),
        descricao: novoDesc.trim(),
        inicio: di,
        termino: df,
      });
      toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Item incluído na agenda.', life: 3000 });
      setNovoOpen(false);
      setNovoDesc('');
      setNovoInicio(null);
      setNovoTermino(null);
      setIsUpdating(true);
    } catch (error: unknown) {
      const msg = error instanceof Error ? error.message : 'Erro ao incluir.';
      toast.current?.show({ severity: 'error', summary: 'Erro', detail: msg, life: 4000 });
    }
  };

  const eventClick = (e: any) => {
    const { title, start, end } = e.event;
    setClickedEvent(e.event);
    setChangedEvent({
      title: title || '',
      start: start ? new Date(start) : null,
      end: end ? new Date(end) : null,
    });
    setEventDialog(true);
  };

  const detalheFooter = (
    <div className="flex flex-wrap align-items-center gap-2 justify-content-start pr-3">
      {itemConcluido(clickedEvent) ? (
        <Button type="button" icon="pi pi-replay" rounded severity="help" tooltip="Reabrir passo" onClick={() => void reabrirPasso()} />
      ) : (
        <Button type="button" icon="pi pi-check-circle" rounded severity="success" tooltip="Concluir passo" onClick={() => void concluirPasso()} />
      )}
      <Button type="button" icon="pi pi-save" rounded severity="info" tooltip="Salvar alterações" onClick={() => void salvarAlteracaoItem()} />
      <Button type="button" icon="pi pi-trash" rounded severity="warning" tooltip="Excluir item" onClick={excluirItem} />
      <Button type="button" label="Fechar" text onClick={() => setEventDialog(false)} />
    </div>
  );

  const novoFooter = (
    <div className="flex flex-wrap align-items-center gap-2 justify-content-start pr-3">
      <Button type="button" label="Cancelar" text onClick={() => setNovoOpen(false)} />
      <Button type="button" label="Incluir" icon="pi pi-check" onClick={() => void salvarNovoItem()} />
    </div>
  );

  return (
    <div className="card calendar-demo">
      <Toast ref={toast} />
      <ConfirmDialog />
      <FullCalendar
        ref={calendarRef}
        events={events}
        eventClick={eventClick}
        initialDate={focusDate}
        initialView="dayGridMonth"
        plugins={[dayGridPlugin, timeGridPlugin, interactionPlugin]}
        editable
        selectable
        selectMirror
        dayMaxEvents
        locale="pt-br"
        timeZone="UTC"
        buttonText={{
          today: 'Hoje',
          month: 'Mês',
          week: 'Semana',
          day: 'Dia',
          list: 'Lista',
          nextYear: 'Próximo ano',
          prevYear: 'Ano anterior',
          nextMonth: 'Próximo mês',
          prevMonth: 'Mês anterior',
          allDay: 'Dia inteiro',
        }}
        customButtons={{
          btnNovoItem: {
            text: 'Novo item',
            click: () => {
              setNovoInicio(new Date());
              setNovoTermino(new Date());
              setNovoDesc('');
              setNovoOpen(true);
            },
          },
          btnAtualizar: {
            text: 'Atualizar',
            click: () => setIsUpdating(true),
          },
        }}
        headerToolbar={{
          left: 'dayGridMonth,timeGridWeek,timeGridDay btnNovoItem btnAtualizar',
          center: 'title',
          right: 'today prevYear,prev,next,nextYear',
        }}
        contentHeight={750}
      />
      <Dialog
        visible={eventDialog && !!clickedEvent}
        style={{ width: 'min(96vw, 32rem)' }}
        header="Item da agenda"
        footer={detalheFooter}
        modal
        closable
        onHide={() => setEventDialog(false)}
      >
        <div className="p-fluid flex flex-column gap-3">
          <div className="field">
            <label htmlFor="ag-diag-desc">Descrição</label>
            <InputText
              id="ag-diag-desc"
              value={changedEvent.title}
              onChange={(e) => setChangedEvent((prev) => ({ ...prev, title: e.target.value }))}
            />
          </div>
          <div className="field">
            <label htmlFor="ag-diag-ini">Início</label>
            <PRCalendar
              id="ag-diag-ini"
              value={changedEvent.start}
              onChange={(e) => setChangedEvent((prev) => ({ ...prev, start: e.value as Date | null }))}
              dateFormat="dd/mm/yy"
              showIcon
              appendTo={typeof document !== 'undefined' ? document.body : undefined}
            />
          </div>
          <div className="field">
            <label htmlFor="ag-diag-fim">Término</label>
            <PRCalendar
              id="ag-diag-fim"
              value={changedEvent.end}
              onChange={(e) => setChangedEvent((prev) => ({ ...prev, end: e.value as Date | null }))}
              dateFormat="dd/mm/yy"
              showIcon
              appendTo={typeof document !== 'undefined' ? document.body : undefined}
            />
          </div>
        </div>
      </Dialog>
      <Dialog
        visible={novoOpen}
        style={{ width: 'min(96vw, 32rem)' }}
        header="Novo item na agenda"
        footer={novoFooter}
        modal
        onHide={() => setNovoOpen(false)}
      >
        <div className="p-fluid flex flex-column gap-3">
          <div className="field">
            <label htmlFor="ag-novo-desc">Descrição</label>
            <InputText id="ag-novo-desc" value={novoDesc} onChange={(e) => setNovoDesc(e.target.value)} />
          </div>
          <div className="field">
            <label htmlFor="ag-novo-ini">Início</label>
            <PRCalendar
              id="ag-novo-ini"
              value={novoInicio}
              onChange={(e) => setNovoInicio(e.value as Date | null)}
              dateFormat="dd/mm/yy"
              showIcon
              appendTo={typeof document !== 'undefined' ? document.body : undefined}
            />
          </div>
          <div className="field">
            <label htmlFor="ag-novo-fim">Término</label>
            <PRCalendar
              id="ag-novo-fim"
              value={novoTermino}
              onChange={(e) => setNovoTermino(e.value as Date | null)}
              dateFormat="dd/mm/yy"
              showIcon
              appendTo={typeof document !== 'undefined' ? document.body : undefined}
            />
          </div>
        </div>
      </Dialog>
    </div>
  );
};

export default SecondCalendar;
