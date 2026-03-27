import React, { useState, useEffect, useRef } from 'react';
import FullCalendar from '@fullcalendar/react';
import dayGridPlugin from '@fullcalendar/daygrid';
import timeGridPlugin from '@fullcalendar/timegrid';
import interactionPlugin from '@fullcalendar/interaction';
import AgendaService from '../../services/cruds/AgendaService';
import { Calendar as PRCalendar } from 'primereact/calendar';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
import { Checkbox } from 'primereact/checkbox';
import { Button } from 'primereact/button';
import { Toast } from 'primereact/toast';
import { render } from '@fullcalendar/core/preact';

const SecondCalendar = ({ eventData, agenda_id, isOpen }) => {

  const [events, setEvents] = useState<any[]>([]);

  const [isUpdating, setIsUpdating] = useState(false);
  const [currentEvents, setCurrentEvents] = useState([]);
  const [weekendsVisible, setWeekendsVisible] = useState(true); // Estado para controlar a visibilidade dos fins de semana
  const [eventDialog, setEventDialog] = useState(false);
  const [clickedEvent, setClickedEvent] = useState<any>(null);
  const [changedEvent, setChangedEvent] = useState({ title: '', start: null, end: null, allDay: null });
  const calendarRef = useRef<any>(null);
  const toast = useRef<Toast>(null);

  const focusDate = eventData?.start ? new Date(eventData.start) : new Date();

  useEffect(() => {
    const agendaService = AgendaService();
    const params = {
      agenda_id: agenda_id
    };

    agendaService.getDetalhes(params)
      .then((eventos) => setEvents(Array.isArray(eventos) ? eventos : []))
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

  // const handleWeekendsToggle = () => {
  //   setWeekendsVisible(!weekendsVisible);
  // }

  // const handleDateSelect = (selectInfo) => {
  //   let title = prompt('Please enter a new title for your event')
  //   let calendarApi = selectInfo.view.calendar

  //   calendarApi.unselect() // clear date selection

  //   if (title) {
  //     calendarApi.addEvent({
  //       //id: createEventId(),
  //       title,
  //       start: selectInfo.startStr,
  //       end: selectInfo.endStr,
  //       allDay: selectInfo.allDay
  //     })
  //   }
  // }

  // const handleEventClick = (e) => {
  //   // if (confirm(`Are you sure you want to delete the event '${clickInfo.event.title}'`)) {
  //   //   clickInfo.event.remove()
  //   //setChangedEvent({ title, start, end, allDay: null });
  //   const _changeEvent = e.event;
  //   const { title, start, end } = e.event;
  //   //setClickedEvent(e.event);
  //   setEventDialog(true);
  // }


  const concluirPasso = async () => {
    const agendaItemId = clickedEvent?._def?.publicId;
    if (!agendaItemId || !agenda_id) {
      toast.current?.show({ severity: 'warn', summary: 'Atenção', detail: 'Passo da agenda inválido.', life: 3000 });
      return;
    }

    try {
      const agendaService = AgendaService();
      const response = await agendaService.concluirPasso({
        agenda_id: String(agenda_id),
        agenda_item_id: String(agendaItemId)
      });

      toast.current?.show({ severity: 'success', summary: 'Sucesso', detail: 'Passo concluído manualmente.', life: 3000 });

      if (response?.data?.todos_passos_concluidos) {
        toast.current?.show({ severity: 'info', summary: 'Rotina', detail: 'Todos os passos foram concluídos.', life: 4000 });
      }

      setEventDialog(false);
      setIsUpdating(true);
    } catch (error: any) {
      toast.current?.show({
        severity: 'error',
        summary: 'Erro',
        detail: error?.message || 'Erro ao concluir passo.',
        life: 4000
      });
    }
  };

  const footer = (
    <>
      <Button type="button" label="Concluir Passo" icon="pi pi-check-circle" className="p-button-success p-button-text" onClick={concluirPasso} />
    </>
  );

  const eventClick = (e) => {
    const { title, start, end } = e.event;
    setEventDialog(true);
    setClickedEvent(e.event);
    setChangedEvent({ title, start, end, allDay: null });
  };

  function renderEventContent(eventInfo) {
    render
  }

  return (

    <div className="card calendar-demo">
      <Toast ref={toast} />
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
        locale={'pt-br'}
        timeZone={"UTC"}
        buttonText={{
          today: "Hoje",
          month: "Mês",
          week: "Semana",
          day: "Dia",
          list: "Lista",
          nextYear: 'Próximo ano',
          prevYear: 'Ano anterior',
          nextMonth: 'Próximo mês',
          prevMonth: 'Mês anterior',
          allDay: 'Dia inteiro',

        }}

        customButtons={{

          btnAtualizar: {
            text: "Atualizar",
            click: function () {
              setIsUpdating(true);
            },
          },
        }}
        headerToolbar={{
          left: "dayGridMonth,timeGridWeek,timeGridDay btnAtualizar",
          center: "title",
          right: "today prevYear,prev,next,nextYear",
        }}
        contentHeight={750}

      />
      <Dialog visible={eventDialog && !!clickedEvent} style={{ width: '50%' }} header="Detalhes do Evento" footer={footer} modal closable onHide={() => setEventDialog(false)}>
        <div className="p-fluid">
          <div className="field">
            <label htmlFor="title">Título</label>
            <InputText id="title" value={changedEvent.title} onChange={(e) => setChangedEvent({ ...changedEvent, ...{ title: e.target.value } })} required autoFocus />
          </div>
          <div className="field">
            <label htmlFor="start">De</label>
            <PRCalendar id="start" value={changedEvent.start} onChange={(e) => setChangedEvent({ ...changedEvent, ...{ start: null } })} showTime appendTo={document.body} />
          </div>
          <div className="field">
            <label htmlFor="end">Até</label>
            <PRCalendar id="end" value={changedEvent.end} onChange={(e) => setChangedEvent({ ...changedEvent, ...{ end: null } })} showTime appendTo={document.body} />
          </div>
        </div>
      </Dialog>
    </div>
  );

}


export default SecondCalendar;
