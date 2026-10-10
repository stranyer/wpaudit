import { lazy, Suspense, useState } from 'react';
import { Check, Pencil, RotateCcw } from 'lucide-react';
import { GAME_CONFIG } from '../../config/gameConfig';
import { WEB_DEMO } from '../../config/platform';
import { FACTION_DEFS } from '../../core/factions';
import { formatDistance } from '../../core/geo';
import { maxHealth, maxStamina } from '../../core/player';
import { rankTitle, xpToNext } from '../../core/progression';
import { ZOMBIES, ZOMBIE_TYPES } from '../../core/zombies';
import { renamePlayer } from '../../game/actions';
import { startLocation, stopSession } from '../../game/session';
import { useGameStore } from '../../store/gameStore';
import { useLocationStore } from '../../store/locationStore';
import { ConfirmButton } from '../components/ConfirmButton';
import { StatBar } from '../components/StatBar';

const AvatarViewport = lazy(() => import('../../three/react/AvatarViewport'));

export function ProfileScreen() {
  const player = useGameStore((s) => s.player);
  const backend = useGameStore((s) => s.backend);
  const mode = useLocationStore((s) => s.mode);
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(player?.name ?? '');
  if (!player) return null;

  const faction = player.factionId ? FACTION_DEFS[player.factionId] : null;
  const kills = ZOMBIE_TYPES.reduce((a, t) => a + (player.stats.zombiesKilled[t] ?? 0), 0);

  const reset = () => {
    stopSession();
    // Solo se borran las claves del juego (prefijo "zc:").
    for (const key of Object.keys(localStorage)) if (key.startsWith('zc:')) localStorage.removeItem(key);
    window.location.reload();
  };

  return (
    <div className="screen">
      <div className="avatar-stage">
        <Suspense fallback={null}>
          <AvatarViewport accentColor={faction?.color ?? '#ec9442'} />
        </Suspense>
      </div>

      <div className="screen-header">
        <div style={{ flex: 1, minWidth: 0 }}>
          {editing ? (
            <div style={{ display: 'flex', gap: 6 }}>
              <input className="text-input" value={name} maxLength={20} onChange={(e) => setName(e.target.value)} autoFocus aria-label="Nombre" />
              <button
                className="icon-btn"
                onClick={() => {
                  renamePlayer(name);
                  setEditing(false);
                }}
                aria-label="Guardar nombre"
              >
                <Check size={20} />
              </button>
            </div>
          ) : (
            <h1 className="screen-title" onClick={() => setEditing(true)} style={{ cursor: 'pointer' }}>
              {player.name} <Pencil size={16} color="var(--muted)" />
              <small>
                {rankTitle(player.level)}
                {faction ? ` · ${faction.name}` : ''}
              </small>
            </h1>
          )}
        </div>
        <div className="level-badge" style={{ width: 58, height: 58, fontSize: 24 }}>
          {player.level}
        </div>
      </div>

      <div className="panel">
        <div className="req-name" style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13, marginBottom: 6 }}>
          <span className="label">Experiencia</span>
          <span className="dim">
            {player.xp}/{xpToNext(player.level)} XP
          </span>
        </div>
        <StatBar value={player.xp} max={xpToNext(player.level)} kind="xp" />
        <div className="divider" />
        <div className="stat-grid">
          <div className="stat">
            <div className="label">Salud máx.</div>
            <div className="stat-value">{maxHealth(player)}</div>
          </div>
          <div className="stat">
            <div className="label">Resistencia máx.</div>
            <div className="stat-value">{maxStamina(player)}</div>
          </div>
        </div>
      </div>

      <div className="panel">
        <h3 className="panel-title">Estadísticas</h3>
        <div className="stat-grid">
          <Stat label="Infectados eliminados" value={kills} />
          <Stat label="Suministros saqueados" value={player.stats.suppliesLooted} />
          <Stat label="Distancia recorrida" value={formatDistance(player.stats.distanceWalkedM)} />
          <Stat label="Zonas exploradas" value={player.stats.cellsExplored} />
          <Stat label="Objetos fabricados" value={player.stats.itemsCrafted} />
          <Stat label="Recursos donados" value={player.stats.resourcesDonated} />
          <Stat label="Huidas" value={player.stats.encountersFled} />
          <Stat label="Caídas" value={player.stats.deaths} />
        </div>
        <div className="divider" />
        <div className="label" style={{ marginBottom: 8 }}>Bajas por tipo</div>
        <div className="cost-chips">
          {ZOMBIE_TYPES.map((t) => (
            <span key={t} className="chip">
              {ZOMBIES[t].name}: {player.stats.zombiesKilled[t] ?? 0}
            </span>
          ))}
        </div>
      </div>

      <div className="panel">
        <h3 className="panel-title">Ajustes</h3>
        <div className="list">
          <div className="list-row">
            <div className="list-main">
              <div className="list-title">Ubicación</div>
              <div className="list-sub">
                {mode === 'demo' ? 'Modo demo (simulada)' : 'GPS real'}
                {WEB_DEMO ? ' · el GPS está disponible en la app Android' : ''}
              </div>
            </div>
            {!WEB_DEMO && (
              <button className="btn btn-sm" onClick={() => void startLocation(mode === 'demo' ? 'gps' : 'demo')}>
                Cambiar a {mode === 'demo' ? 'GPS' : 'demo'}
              </button>
            )}
          </div>
          <div className="list-row">
            <div className="list-main">
              <div className="list-title">Radio de interacción</div>
              <div className="list-sub">{GAME_CONFIG.interactionRadiusM} m (+ tolerancia GPS hasta {GAME_CONFIG.maxAccuracyBonusM} m)</div>
            </div>
          </div>
          <div className="list-row">
            <div className="list-main">
              <div className="list-title">Datos</div>
              <div className="list-sub">{backend === 'supabase' ? 'Sincronizado con Supabase' : 'Guardado local en este dispositivo'}</div>
            </div>
          </div>
        </div>
        <div style={{ marginTop: 12 }}>
          <ConfirmButton className="btn btn-danger btn-block" confirmLabel="¿Borrar todo? Tocá de nuevo" onConfirm={reset}>
            <RotateCcw size={16} /> Reiniciar progreso
          </ConfirmButton>
        </div>
      </div>
      <p className="label" style={{ textAlign: 'center' }}>
        Zona Cero v0.1 · Mapas © OpenStreetMap / OpenFreeMap
      </p>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="stat">
      <div className="label">{label}</div>
      <div className="stat-value">{value}</div>
    </div>
  );
}
