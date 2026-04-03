import React, { useEffect, useState, useRef } from 'react';
import FullCalendar from '@fullcalendar/react';
import dayGridPlugin from '@fullcalendar/daygrid';
import timeGridPlugin from '@fullcalendar/timegrid';
import interactionPlugin from '@fullcalendar/interaction';
import { Dropdown } from 'primereact/dropdown';
import { Dialog } from 'primereact/dialog';
import { InputText } from 'primereact/inputtext';
import { Checkbox } from 'primereact/checkbox';
//import { Calendar as PRCalendar } from 'primereact/calendar';
import { Calendar as PRCalendar } from 'primereact/calendar';
//import EventService from '../service/EventService';
import AgendaService from '../../services/cruds/AgendaService';
import styles from './agenda.module.css';
//import AgendaDialog from './AgendaDialog';
import { canSSRAuth } from '../../components/utils/canSSRAuth';
import setupAPIClient from '../../components/api/api';
import { Calendar } from '@fullcalendar/core'
import dynamic from 'next/dynamic';

const AgendaDialog = dynamic(() => import('./AgendaDialog'), {
  ssr: false, // Isso desativa a renderização no servidor para este componente
});

type CalendarioProps = {
  dados: string;
};

const Calendario = ({ dados }: CalendarioProps) => {

  const tenantid = dados


  const calendarRef = useRef<any>(null);
  const [currentMonth, setCurrentMonth] = useState(new Date().getMonth());
  const [currentYear, setCurrentYear] = useState(new Date().getFullYear());

  const meses = [
    { label: 'Janeiro', value: 0 }, { label: 'Fevereiro', value: 1 },
    { label: 'Março', value: 2 }, { label: 'Abril', value: 3 },
    { label: 'Maio', value: 4 }, { label: 'Junho', value: 5 },
    { label: 'Julho', value: 6 }, { label: 'Agosto', value: 7 },
    { label: 'Setembro', value: 8 }, { label: 'Outubro', value: 9 },
    { label: 'Novembro', value: 10 }, { label: 'Dezembro', value: 11 },
  ];

  const anoAtual = new Date().getFullYear();
  const anos = Array.from({ length: 11 }, (_, i) => {
    const y = anoAtual - 5 + i;
    return { label: String(y), value: y };
  });

  const onMesChange = (mes: number) => {
    setCurrentMonth(mes);
    calendarRef.current?.getApi()?.gotoDate(new Date(currentYear, mes, 1));
  };

  const onAnoChange = (ano: number) => {
    setCurrentYear(ano);
    calendarRef.current?.getApi()?.gotoDate(new Date(ano, currentMonth, 1));
  };

  const onDatesSet = (info: any) => {
    // currentStart pode cair na última semana do mês anterior (grade começa no domingo).
    // Usar o meio do intervalo ativo garante o mês correto exibido.
    const mid = new Date((info.view.activeStart.getTime() + info.view.activeEnd.getTime()) / 2);
    setCurrentMonth(mid.getMonth());
    setCurrentYear(mid.getFullYear());
  };

  const [eventDialog, setEventDialog] = useState(false);
  const [clickedEvent, setClickedEvent] = useState<any>(null);
  const [changedEvent, setChangedEvent] = useState({ title: '', start: null, end: null });
  const [events, setEvents] = useState<any[]>([]);
  const [isUpdating, setIsUpdating] = useState(false);
  const [rotina_id, setRotina_id] = useState('');
  const [agenda_id, setAgenda_id] = useState('');

  const eventClick = (e: any) => {
    const { title, start, end } = e.event;
    const rotinaId = e.event._def.extendedProps.rotina_id;
    const agendaId = e.event._def.publicId;
    setRotina_id(rotinaId != null ? String(rotinaId) : '');
    setAgenda_id(agendaId != null ? String(agendaId) : '');
    setChangedEvent({ title, start, end: null });
    setClickedEvent(e.event);
    setEventDialog(true);

  };

  const closeEventDialog = () => {
    setEventDialog(false);
    setIsUpdating(true);
  };

  useEffect(() => {
    const agendaService = AgendaService();
    const params = {
      tenant_id: tenantid
    };

    const carregarEventos = async () => {
      try {
        const eventos = await agendaService.getAgendaList(params);
        setEvents(Array.isArray(eventos) ? eventos : []);
      } catch (error) {
        setEvents([]);
      }
    };

    if (isUpdating) {
      carregarEventos();
      setIsUpdating(false);
    } else {
      carregarEventos();
    }
    //console.log('data no useEffect', events[0]);
  }, [isUpdating, tenantid]);

  return (
    <div className="grid">
      <div className="col-12">
        <div className={`card calendar-demo ${styles.calendarWrapper}`}>
          <FullCalendar
            ref={calendarRef}
            datesSet={onDatesSet}
            events={events}
            eventClick={eventClick}
            initialDate={new Date()}
            initialView="dayGridMonth"
            plugins={[dayGridPlugin, timeGridPlugin, interactionPlugin]}
            rerenderDelay={10}
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
              center: "",
              right: "today prevYear,prev,next,nextYear",
            }}
          />
          <div className={styles.navDropdowns}>
            <Dropdown
              value={currentMonth}
              options={meses}
              onChange={(e) => onMesChange(e.value)}
              style={{ width: '10rem' }}
            />
            <Dropdown
              value={currentYear}
              options={anos}
              onChange={(e) => onAnoChange(e.value)}
              style={{ width: '6rem' }}
            />
          </div>

          <Dialog visible={eventDialog && !!clickedEvent} style={{ width: '80%', height: '80%' }} header="Detalhes do Evento" modal closable onHide={closeEventDialog}>
            <div className="p-fluid">
              <div className="field">
                <label htmlFor="title">Empresa : Rotina</label>
                <InputText id="title" value={changedEvent.title} onChange={(e) => setChangedEvent({ ...changedEvent, ...{ title: e.target.value } })} required autoFocus />
              </div>

              <div className="second-calendar-container">
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
