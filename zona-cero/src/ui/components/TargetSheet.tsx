import { useState } from 'react';
import { Footprints, Skull, Swords, X, Zap } from 'lucide-react';
import { GAME_CONFIG } from '../../config/gameConfig';
import { FACTION_DEFS } from '../../core/factions';
import { formatDistance, haversineM } from '../../core/geo';
import { effectiveRadius } from '../../core/interaction';
import { RARITY_LABEL } from '../../core/items';
import { shelterLevelDef } from '../../core/shelter';
import { SUPPLIES } from '../../core/supplies';
import { ZOMBIES, threatRating } from '../../core/zombies';
import type { Shelter, Spawn } from '../../core/types';
import { engage, scavenge } from '../../game/actions';
import { demoProvider } from '../../game/session';
import { useGameStore } from '../../store/gameStore';
import { useLocationStore } from '../../store/locationStore';
import { useUiStore } from '../../store/uiStore';
import { useWorldStore } from '../../store/worldStore';
import { SUPPLY_ICONS, shelterIcon } from './icons';

const THREAT_LABEL = ['Fácil', 'Parejo', 'Peligroso', 'Mortal'] as const;
const THREAT_CLASS = ['ok', '', 'warn', 'bad'] as const;

export function TargetSheet() {
  const selectedId = useWorldStore((s) => s.selectedId);
  const spawn = useWorldStore((s) => s.spawns.find((x) => x.id === s.selectedId) ?? null);
  const shelter = useWorldStore((s) => s.shelters.find((x) => x.id === s.selectedId) ?? null);
  const select = useWorldStore((s) => s.select);
  const position = useLocationStore((s) => s.position);
  const accuracy = useLocationStore((s) => s.accuracyM);
  const mode = useLocationStore((s) => s.mode);
  const [busy, setBusy] = useState(false);

  if (!selectedId || !position || (!spawn && !shelter)) return null;
  const target = (spawn?.position ?? shelter?.position)!;
  const distance = haversineM(position, target);
  const reach = effectiveRadius(GAME_CONFIG, accuracy);
  const inReach = distance <= reach;
  const missing = Math.max(1, Math.ceil(distance - reach));

  const run = async (fn: () => Promise<void>) => {
    setBusy(true);
    try {
      await fn();
    } finally {
      setBusy(false);
    }
  };

  const walkHere = mode === 'demo' && !inReach && (
    <button className="btn btn-ghost btn-sm" onClick={() => demoProvider()?.walkTo(target, Math.max(8, GAME_CONFIG.interactionRadiusM - 15))}>
      <Footprints size={16} /> Caminar hasta acá
    </button>
  );

  return (
    <div className="sheet" role="dialog">
      {spawn ? (
        <SpawnBody spawn={spawn} distance={distance} />
      ) : (
        <ShelterBody shelter={shelter!} distance={distance} />
      )}
      <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
        {spawn?.kind === 'zombie' && (
          <button className="btn btn-danger btn-lg" style={{ flex: 1 }} disabled={!inReach || busy} onClick={() => run(() => engage(spawn))}>
            <Swords size={18} /> {inReach ? 'Enfrentar' : `Acercate ${missing} m`}
          </button>
        )}
        {spawn?.kind === 'supply' && (
          <button className="btn btn-primary btn-lg" style={{ flex: 1 }} disabled={!inReach || busy} onClick={() => run(() => scavenge(spawn))}>
            {inReach ? (
              <>
                Saquear <span style={{ fontWeight: 400, opacity: 0.8 }}>−{SUPPLIES[spawn.supplyType].staminaCost}</span> <Zap size={14} />
              </>
            ) : (
              `Acercate ${missing} m`
            )}
          </button>
        )}
        {shelter && (
          <button className="btn btn-green btn-lg" style={{ flex: 1 }} onClick={() => useUiStore.getState().openShelter(shelter.id)}>
            Ver refugio
          </button>
        )}
        {walkHere}
      </div>
      <button className="sheet-close" style={{ position: 'absolute', top: 8, right: 8 }} onClick={() => select(null)} aria-label="Cerrar">
        <X size={20} />
      </button>
    </div>
  );
}

function SpawnBody({ spawn, distance }: { spawn: Spawn; distance: number }) {
  const level = useGameStore((s) => s.player?.level ?? 1);
  if (spawn.kind === 'zombie') {
    const def = ZOMBIES[spawn.zombieType];
    const threat = threatRating(def, level);
    return (
      <>
        <div className="sheet-head">
          <div className="sheet-icon" style={{ color: '#ff6a4d', borderColor: '#8e2a20' }}>
            <Skull />
          </div>
          <div>
            <h3 className="sheet-title">{def.name}</h3>
            <div style={{ display: 'flex', gap: 6, marginTop: 5 }}>
              <span className={`chip ${THREAT_CLASS[threat]}`}>{THREAT_LABEL[threat]}</span>
              <span className="chip">{formatDistance(distance)}</span>
            </div>
          </div>
        </div>
        <p className="sheet-desc">{def.description}</p>
      </>
    );
  }
  const def = SUPPLIES[spawn.supplyType];
  const Icon = SUPPLY_ICONS[spawn.supplyType];
  return (
    <>
      <div className={`sheet-head rarity-${def.rarity}`}>
        <div className="sheet-icon">
          <Icon />
        </div>
        <div>
          <h3 className="sheet-title">{def.name}</h3>
          <div style={{ display: 'flex', gap: 6, marginTop: 5 }}>
            <span className="chip rarity-text" style={{ borderColor: 'var(--rarity)' }}>
              {RARITY_LABEL[def.rarity]}
            </span>
            <span className="chip">{formatDistance(distance)}</span>
          </div>
        </div>
      </div>
      <p className="sheet-desc">{def.description}</p>
    </>
  );
}

function ShelterBody({ shelter, distance }: { shelter: Shelter; distance: number }) {
  const playerId = useGameStore((s) => s.player?.id);
  const Icon = shelterIcon(shelter.level);
  const faction = shelter.factionId ? FACTION_DEFS[shelter.factionId] : null;
  return (
    <>
      <div className="sheet-head" style={{ ['--rarity' as string]: faction?.color ?? 'var(--green)' }}>
        <div className="sheet-icon">
          <Icon />
        </div>
        <div>
          <h3 className="sheet-title">{shelter.name}</h3>
          <div style={{ display: 'flex', gap: 6, marginTop: 5, flexWrap: 'wrap' }}>
            <span className="chip ok">Nv {shelter.level}</span>
            {shelter.ownerId === playerId && <span className="chip warn">Tuyo</span>}
            <span className="chip">{formatDistance(distance)}</span>
          </div>
        </div>
      </div>
      <p className="sheet-desc">
        {shelterLevelDef(shelter.level).name}. {faction ? `Facción: ${faction.name}.` : 'Sin facción.'} Fundado por {shelter.ownerName}.
      </p>
    </>
  );
}
