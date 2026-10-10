import { useEffect, useState } from 'react';
import { Medal, Users } from 'lucide-react';
import { FACTION_DEFS } from '../../core/factions';
import { haversineM } from '../../core/geo';
import type { Faction, LeaderboardEntry, PublicSurvivor } from '../../core/types';
import { joinFaction } from '../../game/actions';
import { getRepo } from '../../game/session';
import { approximateDistanceLabel } from '../../services/privacy';
import { useGameStore } from '../../store/gameStore';
import { useLocationStore } from '../../store/locationStore';
import { useUiStore } from '../../store/uiStore';
import { useWorldStore } from '../../store/worldStore';
import { ShelterRow } from './ShelterScreen';

type Tab = 'shelters' | 'factions' | 'ranking' | 'survivors';

const TABS: { id: Tab; label: string }[] = [
  { id: 'shelters', label: 'Refugios' },
  { id: 'factions', label: 'Facciones' },
  { id: 'ranking', label: 'Ranking' },
  { id: 'survivors', label: 'Cerca' },
];

function timeAgo(ms: number): string {
  const min = Math.max(1, Math.round((Date.now() - ms) / 60000));
  return min < 60 ? `hace ${min} min` : `hace ${Math.round(min / 60)} h`;
}

export function CommunityScreen() {
  const [tab, setTab] = useState<Tab>('shelters');
  return (
    <div className="screen">
      <div className="screen-header">
        <h1 className="screen-title">
          Comunidad
          <small>Sobrevivientes de la zona</small>
        </h1>
        <Users size={28} color="var(--muted)" />
      </div>
      <div className="tabs">
        {TABS.map((t) => (
          <button key={t.id} className={`tab ${tab === t.id ? 'active' : ''}`} onClick={() => setTab(t.id)}>
            {t.label}
          </button>
        ))}
      </div>
      {tab === 'shelters' && <SheltersTab />}
      {tab === 'factions' && <FactionsTab />}
      {tab === 'ranking' && <RankingTab />}
      {tab === 'survivors' && <SurvivorsTab />}
    </div>
  );
}

function SheltersTab() {
  const shelters = useWorldStore((s) => s.shelters);
  const openShelter = useUiStore((s) => s.openShelter);
  return (
    <div className="list">
      {shelters.map((s) => (
        <ShelterRow key={s.id} shelter={s} onClick={() => openShelter(s.id)} />
      ))}
      {shelters.length === 0 && <div className="empty-state">No hay refugios comunitarios cerca todavía.</div>}
    </div>
  );
}

function FactionsTab() {
  const player = useGameStore((s) => s.player);
  const [factions, setFactions] = useState<Faction[]>([]);
  useEffect(() => {
    void getRepo().getFactions().then(setFactions).catch(() => setFactions([]));
  }, [player?.factionId]);
  return (
    <div className="list">
      {factions.map((f) => {
        const mine = player?.factionId === f.id;
        return (
          <div key={f.id} className="panel" style={{ margin: 0, borderColor: mine ? f.color : undefined }}>
            <h3 className="panel-title" style={{ color: f.color }}>
              <span className="faction-dot" style={{ ['--faction' as string]: f.color }} /> {f.name}
            </h3>
            <p className="dim" style={{ margin: '0 0 8px', fontStyle: 'italic', fontSize: 13 }}>“{f.motto}”</p>
            <div className="cost-chips" style={{ marginBottom: 10 }}>
              <span className="chip ok">{f.bonusDescription}</span>
              <span className="chip">{f.members} miembros</span>
              <span className="chip">{f.totalContribution} aportes</span>
            </div>
            <button
              className={`btn btn-sm btn-block ${mine ? 'btn-ghost' : 'btn-primary'}`}
              onClick={() => {
                if (mine) {
                  if (window.confirm('¿Abandonar la facción?')) void joinFaction(null);
                } else if (!player?.factionId || window.confirm(`¿Cambiarte a ${f.name}?`)) {
                  void joinFaction(f.id);
                }
              }}
            >
              {mine ? 'Abandonar' : player?.factionId ? 'Cambiarme' : 'Unirme'}
            </button>
          </div>
        );
      })}
    </div>
  );
}

function RankingTab() {
  const playerId = useGameStore((s) => s.player?.id);
  const [rows, setRows] = useState<LeaderboardEntry[] | null>(null);
  useEffect(() => {
    void getRepo().getLeaderboard(20).then(setRows).catch(() => setRows([]));
  }, []);
  if (!rows) return <div className="empty-state">Cargando…</div>;
  return (
    <>
      <p className="label" style={{ marginTop: 0 }}>Recursos donados a refugios</p>
      <div className="list">
        {rows.map((r, i) => (
          <div key={r.playerId} className={`list-row ${r.playerId === playerId ? 'me' : ''}`}>
            <span className={`rank-num ${i < 3 ? 'top' : ''}`}>{i < 3 ? <Medal size={20} /> : i + 1}</span>
            <div className="list-main">
              <div className="list-title">{r.playerName}</div>
              <div className="list-sub">
                Nv {r.level}
                {r.factionId ? ` · ${FACTION_DEFS[r.factionId].name}` : ''}
              </div>
            </div>
            <span className="chip warn">{r.contribution}</span>
          </div>
        ))}
      </div>
    </>
  );
}

function SurvivorsTab() {
  const position = useLocationStore((s) => s.position);
  const [rows, setRows] = useState<PublicSurvivor[] | null>(null);
  useEffect(() => {
    if (!position) return;
    void getRepo().getNearbySurvivors(position, 3000).then(setRows).catch(() => setRows([]));
    // Se consulta al abrir la pestaña; la presencia cambia cada pocos minutos.
  }, [position !== null]);
  if (!rows || !position) return <div className="empty-state">Buscando sobrevivientes…</div>;
  return (
    <>
      <p className="label" style={{ marginTop: 0, lineHeight: 1.5 }}>
        Las ubicaciones son aproximadas para proteger la privacidad de cada jugador.
      </p>
      <div className="list">
        {rows.map((s) => (
          <div key={s.id} className="list-row">
            <span className="faction-dot" style={{ ['--faction' as string]: s.factionId ? FACTION_DEFS[s.factionId].color : undefined }} />
            <div className="list-main">
              <div className="list-title">{s.name}</div>
              <div className="list-sub">
                Nv {s.level} · {timeAgo(s.lastSeenAt)}
              </div>
            </div>
            <span className="chip">{approximateDistanceLabel(haversineM(position, s.approxPosition))}</span>
          </div>
        ))}
        {rows.length === 0 && <div className="empty-state">No hay nadie cerca ahora.</div>}
      </div>
    </>
  );
}
