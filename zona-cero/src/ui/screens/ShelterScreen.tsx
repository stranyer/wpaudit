import { lazy, Suspense, useState } from 'react';
import { ChevronLeft, Flame, MapPin, Shield, Tent } from 'lucide-react';
import { FACTION_DEFS } from '../../core/factions';
import { formatDistance } from '../../core/geo';
import { countOf, entries } from '../../core/inventory';
import { ITEMS } from '../../core/items';
import { REST_COOLDOWN_MS, MAX_SHELTER_LEVEL, nextLevelRequirements, remainingRequirements, shelterLevelDef, upgradeProgress } from '../../core/shelter';
import type { ResourceId, Shelter } from '../../core/types';
import {
  SHELTER_BUILD_COST,
  buildShelter,
  demoTravel,
  distanceToShelter,
  donate,
  isNearShelter,
  ownShelter,
  rest,
} from '../../game/actions';
import { useGameStore } from '../../store/gameStore';
import { useLocationStore } from '../../store/locationStore';
import { useUiStore } from '../../store/uiStore';
import { useWorldStore } from '../../store/worldStore';
import { ItemIcon } from '../components/ItemIcon';
import { StatBar } from '../components/StatBar';
import { shelterIcon } from '../components/icons';

const ShelterViewport = lazy(() => import('../../three/react/ShelterViewport'));

export function ShelterScreen() {
  const viewId = useUiStore((s) => s.shelterViewId);
  const shelters = useWorldStore((s) => s.shelters);
  const player = useGameStore((s) => s.player);
  if (!player) return null;
  const own = shelters.find((s) => s.ownerId === player.id) ?? null;
  const shelter = viewId ? (shelters.find((s) => s.id === viewId) ?? null) : own;

  return <div className="screen">{shelter ? <ShelterDetail shelter={shelter} /> : <NoShelter />}</div>;
}

function NoShelter() {
  const player = useGameStore((s) => s.player)!;
  const shelters = useWorldStore((s) => s.shelters);
  const position = useLocationStore((s) => s.position);
  const openShelter = useUiStore((s) => s.openShelter);
  const [name, setName] = useState(`Refugio de ${player.name}`);
  const [busy, setBusy] = useState(false);
  const canPay = entries(SHELTER_BUILD_COST).every(([id, n]) => countOf(player.inventory, id) >= n);

  return (
    <>
      <div className="screen-header">
        <h1 className="screen-title">
          Refugio
          <small>Todavía no tenés base</small>
        </h1>
      </div>
      <div className="panel">
        <h3 className="panel-title">
          <Tent size={18} className="accent" /> Montar campamento
        </h3>
        <p className="dim" style={{ fontSize: 13, marginTop: 0, lineHeight: 1.45 }}>
          Un refugio te deja descansar, desbloquea recetas en el taller y suma botín. Otros sobrevivientes pueden verlo y
          donar recursos para mejorarlo.
        </p>
        <input className="text-input" value={name} maxLength={32} onChange={(e) => setName(e.target.value)} aria-label="Nombre del refugio" />
        <div className="cost-chips" style={{ margin: '10px 0' }}>
          {entries(SHELTER_BUILD_COST).map(([id, n]) => (
            <span key={id} className={`chip ${countOf(player.inventory, id) >= n ? 'ok' : 'bad'}`}>
              <ItemIcon id={id} size={13} /> {countOf(player.inventory, id)}/{n} {ITEMS[id].name}
            </span>
          ))}
        </div>
        <button
          className="btn btn-primary btn-lg btn-block"
          disabled={!canPay || busy || !position}
          onClick={async () => {
            setBusy(true);
            const created = await buildShelter(name);
            setBusy(false);
            if (created) openShelter(created.id);
          }}
        >
          Montar campamento
        </button>
        <p className="label" style={{ marginTop: 10, lineHeight: 1.5, letterSpacing: '0.06em' }}>
          <MapPin size={11} /> Por tu privacidad, el refugio se ubica en una calle pública cercana, nunca en tu ubicación exacta.
          No lo crees dentro de propiedades privadas.
        </p>
      </div>

      <div className="panel">
        <h3 className="panel-title">Refugios comunitarios</h3>
        <div className="list">
          {shelters.slice(0, 6).map((s) => (
            <ShelterRow key={s.id} shelter={s} onClick={() => openShelter(s.id)} />
          ))}
          {shelters.length === 0 && <div className="muted">No hay refugios cerca. ¡Sé el primero!</div>}
        </div>
      </div>
    </>
  );
}

export function ShelterRow({ shelter, onClick }: { shelter: Shelter; onClick: () => void }) {
  const d = distanceToShelter(shelter);
  const Icon = shelterIcon(shelter.level);
  const faction = shelter.factionId ? FACTION_DEFS[shelter.factionId] : null;
  return (
    <div className="list-row clickable" onClick={onClick}>
      <Icon size={24} color={faction?.color ?? 'var(--green)'} />
      <div className="list-main">
        <div className="list-title">{shelter.name}</div>
        <div className="list-sub">
          Nv {shelter.level} · {shelterLevelDef(shelter.level).name}
          {faction ? ` · ${faction.name}` : ''}
        </div>
      </div>
      {d !== null && <span className="chip">{formatDistance(d)}</span>}
    </div>
  );
}

function ShelterDetail({ shelter }: { shelter: Shelter }) {
  const player = useGameStore((s) => s.player)!;
  const mode = useLocationStore((s) => s.mode);
  // Recalcula distancia al moverse.
  useLocationStore((s) => s.position);
  const viewId = useUiStore((s) => s.shelterViewId);
  const openShelter = useUiStore((s) => s.openShelter);
  const [busy, setBusy] = useState(false);

  const def = shelterLevelDef(shelter.level);
  const next = shelter.level < MAX_SHELTER_LEVEL ? shelterLevelDef(shelter.level + 1) : null;
  const req = nextLevelRequirements(shelter);
  const remaining = remainingRequirements(shelter);
  const near = isNearShelter(shelter);
  const distance = distanceToShelter(shelter);
  const isOwn = shelter.ownerId === player.id;
  const faction = shelter.factionId ? FACTION_DEFS[shelter.factionId] : null;
  const restLeft = player.lastRestAt + REST_COOLDOWN_MS - Date.now();

  const give = async (resources: Partial<Record<ResourceId, number>>) => {
    setBusy(true);
    await donate(shelter, resources);
    setBusy(false);
  };
  const giveAll = () => {
    const offer: Partial<Record<ResourceId, number>> = {};
    for (const [res, left] of Object.entries(remaining) as [ResourceId, number][]) {
      const have = countOf(player.inventory, res);
      if (have > 0) offer[res] = Math.min(have, left);
    }
    void give(offer);
  };
  const canGiveAny = (Object.entries(remaining) as [ResourceId, number][]).some(([res]) => countOf(player.inventory, res) > 0);

  return (
    <>
      <div className="shelter-stage">
        <Suspense fallback={<div className="loading">Cargando…</div>}>
          <ShelterViewport level={shelter.level} />
        </Suspense>
        <div className="shelter-stage-overlay">
          <div>
            {(viewId || !isOwn) && (
              <button className="btn btn-sm btn-ghost" style={{ marginBottom: 8, background: 'rgba(0,0,0,.5)' }} onClick={() => openShelter(null)}>
                <ChevronLeft size={16} /> Volver
              </button>
            )}
            <h1 className="screen-title" style={{ fontSize: 22, textShadow: '0 2px 8px #000' }}>
              {shelter.name}
              <small>
                Nivel {shelter.level} · {def.name}
              </small>
            </h1>
          </div>
          <div style={{ display: 'grid', gap: 4, justifyItems: 'end' }}>
            {isOwn && <span className="chip warn">Tuyo</span>}
            {faction && (
              <span className="chip" style={{ color: faction.color, borderColor: faction.color }}>
                {faction.name}
              </span>
            )}
          </div>
        </div>
      </div>

      <div className="panel">
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
          <span className={`chip ${near ? 'ok' : 'warn'}`}>
            <MapPin size={12} /> {near ? 'Estás en el refugio' : distance !== null ? `A ${formatDistance(distance)}` : 'Sin ubicación'}
          </span>
          <span className="chip">
            <Shield size={12} /> Defensa {def.defense}
          </span>
          {!near && mode === 'demo' && (
            <button className="btn btn-sm" onClick={() => demoTravel(shelter.position)}>
              Viajar (demo)
            </button>
          )}
        </div>
        <div className="divider" />
        <button className="btn btn-green btn-block" disabled={!near || restLeft > 0} onClick={() => rest(shelter)}>
          <Flame size={18} />
          {restLeft > 0 ? `Descansar (en ${Math.ceil(restLeft / 60000)} min)` : `Descansar junto al fuego · +${def.restHealth}`}
        </button>
      </div>

      {req && next ? (
        <div className="panel">
          <h3 className="panel-title">
            Mejora → <span className="accent">Nv {shelter.level + 1} {next.name}</span>
          </h3>
          <StatBar value={upgradeProgress(shelter)} max={1} kind="progress" />
          <p className="dim" style={{ fontSize: 13 }}>{next.description}</p>
          <div>
            {(Object.entries(req) as [ResourceId, number][]).map(([res, amount]) => {
              const done = Math.min(amount, shelter.progress[res] ?? 0);
              const have = countOf(player.inventory, res);
              const left = remaining[res] ?? 0;
              return (
                <div key={res} className="req-row">
                  <ItemIcon id={res} size={22} />
                  <div>
                    <div className="req-name">
                      <span>{ITEMS[res].name}</span>
                      <span className="dim">
                        {done}/{amount}
                      </span>
                    </div>
                    <StatBar value={done} max={amount} kind="progress" />
                  </div>
                  <button
                    className="btn btn-sm"
                    disabled={!near || busy || left === 0 || have === 0}
                    onClick={() => give({ [res]: Math.min(have, left) })}
                    title={`Tenés ${have}`}
                  >
                    {left === 0 ? '✓' : `Donar ${Math.min(have, left)}`}
                  </button>
                </div>
              );
            })}
          </div>
          <button className="btn btn-primary btn-block" style={{ marginTop: 10 }} disabled={!near || busy || !canGiveAny} onClick={giveAll}>
            Donar todo lo posible
          </button>
          {!near && <p className="label" style={{ marginBottom: 0 }}>Acercate al refugio para donar.</p>}
          <div className="divider" />
          <div className="label" style={{ marginBottom: 6 }}>Al mejorar</div>
          <div className="cost-chips">
            {next.perks.map((perk) => (
              <span key={perk} className="chip ok">
                {perk}
              </span>
            ))}
          </div>
        </div>
      ) : (
        <div className="panel">
          <h3 className="panel-title">Fortaleza completa</h3>
          <p className="dim" style={{ margin: 0 }}>Este refugio alcanzó el nivel máximo. Un faro en la Zona Cero.</p>
        </div>
      )}

      <div className="panel">
        <h3 className="panel-title">Beneficios actuales</h3>
        <div className="cost-chips">
          {def.perks.map((perk) => (
            <span key={perk} className="chip">
              {perk}
            </span>
          ))}
        </div>
      </div>

      <div className="panel">
        <h3 className="panel-title">Aportes</h3>
        <div className="list">
          {shelter.contributions.slice(0, 8).map((c, i) => (
            <div key={c.playerId} className={`list-row ${c.playerId === player.id ? 'me' : ''}`}>
              <span className={`rank-num ${i < 3 ? 'top' : ''}`}>{i + 1}</span>
              <div className="list-main">
                <div className="list-title">{c.playerName}</div>
              </div>
              <span className="chip">{c.amount} recursos</span>
            </div>
          ))}
          {shelter.contributions.length === 0 && <div className="muted">Nadie aportó todavía. ¡Sé el primero!</div>}
        </div>
      </div>
      {!isOwn && !ownShelter() && (
        <button className="btn btn-ghost btn-block" onClick={() => openShelter(null)}>
          Crear mi propio refugio
        </button>
      )}
    </>
  );
}
