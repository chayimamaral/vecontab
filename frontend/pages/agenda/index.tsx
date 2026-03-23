import React, { useEffect, useState } from 'react';
import FullCalendar from '@fullcalendar/react';
import dayGridPlugin from '@fullcalendar/daygrid';
import timeGridPlugin from '@fullcalendar/timegrid';
import interactionPlugin from '@fullcalendar/interaction';
import { Button } from 'primereact/button';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
import { Checkbox } from 'primereact/checkbox';
//import { Calendar as PRCalendar } from 'primereact/calendar';
import { Calendar as PRCalendar } from 'primereact/calendar';
//import EventService from '../service/EventService';
import AgendaService from '../../services/cruds/AgendaService';
import AgendaDialog from './AgendaDialog';
import { canSSRAuth } from '../../components/utils/canSSRAuth';
import setupAPIClient from '../../components/api/api';
import { Calendar } from '@fullcalendar/core'

const Calendario = ({ dados }) => {

  const tenantid = dados

  let initialEvents = [
    {
      title: '', start: null, end: null
    }];

  const [eventDialog, setEventDialog] = useState(false);
  const [clickedEvent, setClickedEvent] = useState<any>(null);
  const [changedEvent, setChangedEvent] = useState({ title: '', start: null, end: null });
  const [events, setEvents] = useState([initialEvents]);
  const [isUpdating, setIsUpdating] = useState(false);
  const [rotina_id, setRotina_id] = useState(0);
  const [agenda_id, setAgenda_id] = useState(0);

  const eventClick = (e) => {
    const { title, start, end } = e.event;
    const rotinaId = e.event._def.extendedProps.rotina_id;
    const agendaId = e.event._def.publicId;
    setRotina_id(rotinaId);
    setAgenda_id(agendaId)
    setChangedEvent({ title, start, end: null });
    setClickedEvent(e.event);
    setEventDialog(true);

  };

  useEffect(() => {
    const agendaService = AgendaService();
    const params = {
      tenant_id: tenantid
    }
    if (isUpdating) {
      agendaService.getAgendaList(params)
        .then(({ data }) => setEvents(data.events))
      setIsUpdating(false);
    } else {
      agendaService.getAgendaList(params)
        .then(({ data }) => setEvents(data.events));
    }
    //console.log('data no useEffect', events[0]);
  }, [isUpdating]);

  const save = () => {
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
    setChangedEvent({ title, start, end: null });
  };

  const footer = (
    <>
      <Button type="button" label="Salvar" icon="pi pi-check" className="p-button-text" onClick={save} />
      <Button type="button" label="Recarregar" icon="pi pi-refresh" className="p-button-text" onClick={reset} />
    </>
  );

  return (
    <div className="grid">
      <div className="col-12">
        <div className="card calendar-demo">
          <FullCalendar
            events={events}
            eventClick={eventClick}
            initialDate={new Date()}
            initialView="dayGridMonth"
            plugins={[dayGridPlugin, timeGridPlugin, interactionPlugin]}
            rerenderDelay={10}
            //headerToolbar={{ left: 'prev,next today', center: 'title', right: 'dayGridMonth,timeGridWeek,timeGridDay' }}
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
              prevMonth: 'Mês anterior'
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

          />

          <Dialog visible={eventDialog && !!clickedEvent} style={{ width: '80%', height: '80%' }} header="Detalhes do Evento" footer={footer} modal closable onHide={() => setEventDialog(false)}>
            <div className="p-fluid">
              <div className="field">
                <label htmlFor="title">Empresa : Rotina</label>
                <InputText id="title" value={changedEvent.title} onChange={(e) => setChangedEvent({ ...changedEvent, ...{ title: e.target.value } })} required autoFocus />
              </div>

              <div className="second-calendar-container" style={{ width: '100%', height: '100%' }}>
                {clickedEvent !== null && <AgendaDialog eventData={clickedEvent} agenda_id={agenda_id} isOpen={eventDialog} />}
              </div>

              {/* <div className="field">
                <label htmlFor="start">From</label>
                <PRCalendar id="start" value={changedEvent.start} onChange={(e) => setChangedEvent({ ...changedEvent, ...{ start: e.value } })} showTime appendTo={document.body} />
              </div>
              <div className="field">
                <label htmlFor="end">To</label>
                <PRCalendar id="end" value={changedEvent.end} onChange={(e) => setChangedEvent({ ...changedEvent, ...{ end: e.value } })} showTime appendTo={document.body} />
              </div>
               */}
            </div>
          </Dialog>
        </div>
      </div>
    </div>
  );
};

export default Calendario;


export const getServerSideProps = canSSRAuth(async (ctx) => {
  try {
    const apiClient = setupAPIClient(ctx);
    const response = await apiClient.get('/api/usuariotenant');

    return {

      props: {

        dados: response.data.tenantid,

      }
    };

  } catch (err) {
    console.log(err);

    return {
      redirect: {
        destination: '/',
        permanent: false
      }
    };
  }
});
