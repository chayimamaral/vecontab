import React, { useState, useEffect, use } from 'react';
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
import { render } from '@fullcalendar/core/preact';

const SecondCalendar = ({ eventData, agenda_id }) => {

  let initialEvents = [
    {
      title: '', start: null, end: null, allDay: null
    }];

  const [events, setEvents] = useState([initialEvents]);

  const [isUpdating, setIsUpdating] = useState(false);
  const [currentEvents, setCurrentEvents] = useState([]);
  const [weekendsVisible, setWeekendsVisible] = useState(true); // Estado para controlar a visibilidade dos fins de semana
  const [eventDialog, setEventDialog] = useState(false);
  const [clickedEvent, setClickedEvent] = useState<any>(null);
  const [changedEvent, setChangedEvent] = useState({ title: '', start: null, end: null, allDay: null });

  useEffect(() => {
    const agendaService = AgendaService();
    const params = {
      agenda_id: agenda_id
    }

    agendaService.getDetalhes(params).then(({ data }) => setEvents(data.events));

    if (isUpdating) {
      setIsUpdating(false);
    }

  }, [isUpdating]);

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


  const onSave = () => {

    alert(clickedEvent.end)

    alert('salvando no index')
    // setEventDialog(false);

    // clickedEvent.setProp('title', changedEvent.title);
    // clickedEvent.setStart(changedEvent.start);
    // clickedEvent.setEnd(changedEvent.end);
    // clickedEvent.setAllDay(changedEvent.allDay);

    // setChangedEvent({ title: '', start: null, end: null, allDay: null });
  };

  const reset = () => {
    const { title, start, end } = clickedEvent;
    setChangedEvent({ title, start, end, allDay: null });
  };

  const footer = (
    <>
      <Button type="button" label="Save" icon="pi pi-check" className="p-button-text" onClick={onSave} />
      <Button type="button" label="Reset" icon="pi pi-refresh" className="p-button-text" onClick={reset} />
    </>
  );

  const eventClick = (e) => {
    const { title, start, end } = e.event;
    const publicId = e.event._def.publicId;
    setEventDialog(true);
    setClickedEvent(e.event);
    setChangedEvent({ title, start, end, allDay: null });
  };

  function renderEventContent(eventInfo) {
    render
  }

  return (

    <div className="card calendar-demo">
      <FullCalendar
        events={events}
        eventClick={eventClick}
        initialDate={new Date()}
        initialView="dayGridMonth"
        plugins={[dayGridPlugin, timeGridPlugin, interactionPlugin]}
        editable
        selectable
        selectMirror
        dayMaxEvents
        locale={'pt-br'}
        timeZone={"UTF"}
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
      <Dialog visible={eventDialog && !!eventClick} style={{ width: '50%' }} header="Detalhes do Evento" footer={footer} modal closable onHide={() => setEventDialog(false)}>
        <div className="p-fluid">
          <div className="field">
            <label htmlFor="title">Title</label>
            <InputText id="title" value={changedEvent.title} onChange={(e) => setChangedEvent({ ...changedEvent, ...{ title: e.target.value } })} required autoFocus />
          </div>
          <div className="field">
            <label htmlFor="start">From</label>
            <PRCalendar id="start" value={changedEvent.start} onChange={(e) => setChangedEvent({ ...changedEvent, ...{ start: null } })} showTime appendTo={document.body} />
          </div>
          <div className="field">
            <label htmlFor="end">To</label>
            <PRCalendar id="end" value={changedEvent.end} onChange={(e) => setChangedEvent({ ...changedEvent, ...{ end: null } })} showTime appendTo={document.body} />
          </div>
        </div>
      </Dialog>
    </div>
  );

}


export default SecondCalendar;
