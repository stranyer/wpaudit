import { lazy, Suspense, useEffect, useRef, useState } from 'react';
import { BriefcaseMedical, Crosshair, Footprints, HandFist, Hammer, ShieldHalf, Zap } from 'lucide-react';
import { GAME_STAMINA, HEAVY_MULTIPLIER } from '../../core/balance';
import { canShoot, describeEvent, remainingInCombat, usableItems } from '../../core/combat';
import { ITEMS } from '../../core/items';
import { ZOMBIES, threatRating } from '../../core/zombies';
import type { CombatAction, CombatEvent, CombatState } from '../../core/types';
import { combatAction, describeItems, leaveCombat } from '../../game/actions';
import { useGameStore } from '../../store/gameStore';
import type { CombatAnimation, CombatViewportHandle } from '../../three/types';
import { ItemIcon } from '../components/ItemIcon';
import { StatBar } from '../components/StatBar';

const CombatViewport = lazy(() => import('../../three/react/CombatViewport'));

/** Eventos que pertenecen a la respuesta del zombie (se muestran con retraso). */
const ZOMBIE_PHASE = new Set<CombatEvent['kind']>([
  'zombie_hit',
  'zombie_miss',
  'zombie_charge_prepare',
  'zombie_stunned',
  'zombie_scream',
  'player_down',
]);

interface Float {
  id: number;
  text: string;
  kind: '' | 'crit' | 'player' | 'heal' | 'miss';
  x: number;
}

let floatSeq = 1;

function animationFor(e: CombatEvent): CombatAnimation | null {
  switch (e.kind) {
    case 'player_hit':
      return e.ranged ? 'player_shoot' : e.crit ? 'player_crit' : 'player_hit';
    case 'player_miss':
      return 'player_miss';
    case 'defend':
      return 'defend';
    case 'heal':
      return 'heal';
    case 'flee_success':
      return 'flee';
    case 'zombie_killed':
      return 'zombie_death';
    case 'toxic_burst':
      return 'toxic_burst';
    case 'zombie_hit':
      return e.charged ? 'zombie_charge' : 'zombie_attack';
    case 'zombie_miss':
      return 'zombie_miss';
    case 'zombie_charge_prepare':
      return 'zombie_charge_prepare';
    case 'zombie_stunned':
      return 'zombie_stunned';
    case 'zombie_scream':
      return 'zombie_scream';
    default:
      return null;
  }
}

export function CombatScreen() {
  const combat = useGameStore((s) => s.combat);
  const outcome = useGameStore((s) => s.combatOutcome);
  const playerLevel = useGameStore((s) => s.player?.level ?? 1);
  const viewport = useRef<CombatViewportHandle>(null);
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);
  const [busy, setBusy] = useState(false);
  const [floats, setFloats] = useState<Float[]>([]);
  const [log, setLog] = useState<string[]>([]);
  const [hurt, setHurt] = useState(0);
  const [itemsOpen, setItemsOpen] = useState(false);
  const [showResult, setShowResult] = useState(false);
  const [shown, setShown] = useState(() => ({
    zombieHp: combat?.zombie.health ?? 0,
    playerHp: combat?.player.health ?? 0,
    stamina: combat?.player.stamina ?? 0,
  }));

  useEffect(() => {
    if (combat) setLog([`Un ${combat.zombie.name} de nivel ${combat.zombie.level} te bloquea el paso.`]);
    return () => timers.current.forEach(clearTimeout);
    // Solo al abrir el encuentro.
  }, [combat?.spawnId]);

  if (!combat) return null;
  const def = ZOMBIES[combat.zombie.typeId];
  const threat = threatRating(def, playerLevel);

  const later = (ms: number, fn: () => void) => {
    timers.current.push(setTimeout(fn, ms));
  };

  const addFloat = (text: string, kind: Float['kind']) => {
    const f = { id: floatSeq++, text, kind, x: 40 + Math.random() * 20 };
    setFloats((all) => [...all.slice(-5), f]);
    later(1200, () => setFloats((all) => all.filter((x) => x.id !== f.id)));
  };

  const showEvent = (e: CombatEvent, state: CombatState) => {
    const anim = animationFor(e);
    if (anim) viewport.current?.play(anim);
    setLog((l) => [...l.slice(-1), describeEvent(e, state)]);
    switch (e.kind) {
      case 'player_hit':
        setShown((s) => ({ ...s, zombieHp: Math.max(0, s.zombieHp - e.damage) }));
        addFloat(`-${e.damage}`, e.crit ? 'crit' : '');
        break;
      case 'player_miss':
        addFloat('FALLO', 'miss');
        break;
      case 'zombie_scream':
        setShown((s) => ({ ...s, zombieHp: s.zombieHp + e.healed }));
        break;
      case 'heal':
        setShown((s) => ({ ...s, playerHp: s.playerHp + e.health, stamina: s.stamina + e.stamina }));
        if (e.health > 0) addFloat(`+${e.health}`, 'heal');
        break;
      case 'zombie_hit':
      case 'toxic_burst':
        setShown((s) => ({ ...s, playerHp: Math.max(0, s.playerHp - e.damage) }));
        addFloat(`-${e.damage}`, 'player');
        setHurt((h) => h + 1);
        navigator.vibrate?.(e.kind === 'zombie_hit' && e.charged ? [80, 40, 120] : 60);
        break;
      case 'zombie_miss':
        if (e.charged) addFloat('¡ESQUIVADO!', 'heal');
        break;
      default:
        break;
    }
  };

  const act = (action: CombatAction) => {
    if (busy || combat.status !== 'ongoing') return;
    setItemsOpen(false);
    const next = combatAction(action);
    if (!next || next === combat) return;
    setBusy(true);
    const playerPhase = next.lastEvents.filter((e) => !ZOMBIE_PHASE.has(e.kind));
    const zombiePhase = next.lastEvents.filter((e) => ZOMBIE_PHASE.has(e.kind));
    // La resistencia gastada en la acción se refleja al instante.
    setShown((s) => ({ ...s, stamina: next.player.stamina - playerPhase.reduce((a, e) => a + (e.kind === 'heal' ? e.stamina : 0), 0) }));
    playerPhase.forEach((e, i) => later(i * 380, () => showEvent(e, next)));
    const zStart = playerPhase.length > 0 ? 650 + (playerPhase.length - 1) * 380 : 0;
    zombiePhase.forEach((e, i) => later(zStart + i * 520, () => showEvent(e, next)));
    const end = zStart + zombiePhase.length * 520 + 250;
    later(end, () => {
      setShown({ zombieHp: next.zombie.health, playerHp: next.player.health, stamina: next.player.stamina });
      setBusy(false);
      if (next.status !== 'ongoing') later(next.status === 'won' ? 1300 : 700, () => setShowResult(true));
    });
  };

  const p = combat.player;
  const ammoLeft = remainingInCombat(combat, 'ammo');
  const items = usableItems(combat);
  const fleePct = Math.round(Math.min(95, def.fleeChance * 100));
  const disabled = busy || combat.status !== 'ongoing';

  return (
    <div className="combat">
      <div className="combat-stage">
        <Suspense fallback={<div className="loading">Cargando…</div>}>
          <CombatViewport ref={viewport} zombieType={combat.zombie.typeId} />
        </Suspense>
        <div key={hurt} className={`damage-vignette ${hurt > 0 ? 'on' : ''}`} />
        <div className="float-layer">
          {floats.map((f) => (
            <div key={f.id} className={`float-num ${f.kind}`} style={{ left: `${f.x}%` }}>
              {f.text}
            </div>
          ))}
        </div>
        <div className="combat-top">
          <div className="combat-name">
            <h2>{combat.zombie.name}</h2>
            <span className="label">Nivel {combat.zombie.level}</span>
          </div>
          <StatBar value={shown.zombieHp} max={combat.zombie.maxHealth} kind="enemy" />
          <div className="combat-status">
            {threat >= 2 && <span className={`chip ${threat === 3 ? 'bad' : 'warn'}`}>{threat === 3 ? 'Mortal' : 'Peligroso'}</span>}
            {combat.zombie.charging && <span className="chip warn">¡Va a embestir!</span>}
            {combat.zombie.stunned && <span className="chip ok">Aturdido</span>}
          </div>
          {combat.zombie.charging && <div className="combat-hint">Cubrite para esquivar la embestida y aturdirlo.</div>}
          {def.ability === 'toxic_burst' && combat.status === 'ongoing' && (
            <div className="combat-hint">Explota al morir: rematalo con un disparo para evitar la nube tóxica.</div>
          )}
        </div>
      </div>

      <div className="combat-panel">
        {itemsOpen && (
          <div className="item-picker">
            {items.length === 0 && <div className="muted" style={{ fontSize: 13 }}>No tenés objetos para usar.</div>}
            {items.map((id) => (
              <button key={id} className={`btn btn-sm rarity-${ITEMS[id].rarity}`} style={{ justifyContent: 'flex-start' }} onClick={() => act({ type: 'use_item', itemId: id })}>
                <ItemIcon id={id} size={18} className="rarity-text" /> {ITEMS[id].name}
                <span className="muted" style={{ marginLeft: 'auto' }}>x{remainingInCombat(combat, id)}</span>
              </button>
            ))}
          </div>
        )}
        <div className="combat-log">
          {log.map((line, i) => (
            <div key={`${i}-${line}`}>{line}</div>
          ))}
        </div>
        <div className="combat-player">
          <div className="hud-row" style={{ gridTemplateColumns: '60px 1fr 52px' }}>
            <span className="label">Salud</span>
            <StatBar value={shown.playerHp} max={p.maxHealth} kind="health" />
            <span className="val">{Math.round(shown.playerHp)}/{p.maxHealth}</span>
          </div>
          <div className="hud-row" style={{ gridTemplateColumns: '60px 1fr 52px' }}>
            <span className="label">Resist.</span>
            <StatBar value={shown.stamina} max={p.maxStamina} kind="stamina" />
            <span className="val">{Math.round(shown.stamina)}</span>
          </div>
        </div>
        <div className="combat-actions">
          <button className="btn action-btn btn-primary" disabled={disabled} onClick={() => act({ type: 'attack' })}>
            <HandFist />
            Atacar
            <span className="cost">{p.meleeName} · −{GAME_STAMINA.attack} <Zap size={10} /></span>
          </button>
          <button className="btn action-btn" disabled={disabled || p.stamina < GAME_STAMINA.heavy} onClick={() => act({ type: 'heavy' })}>
            <Hammer />
            Golpe fuerte
            <span className="cost">x{String(HEAVY_MULTIPLIER).replace('.', ',')} daño · −{GAME_STAMINA.heavy} <Zap size={10} /></span>
          </button>
          <button className="btn action-btn" disabled={disabled || !canShoot(combat)} onClick={() => act({ type: 'shoot' })}>
            <Crosshair />
            Disparar
            <span className="cost">{p.firearm ? `${p.firearmName} · ${ammoLeft} bal.` : 'Sin arma de fuego'}</span>
          </button>
          <button className={`btn action-btn ${combat.zombie.charging ? 'btn-green' : ''}`} disabled={disabled} onClick={() => act({ type: 'defend' })}>
            <ShieldHalf />
            Cubrirse
            <span className="cost">−60% daño · +12 <Zap size={10} /></span>
          </button>
          <button className="btn action-btn" disabled={disabled} onClick={() => setItemsOpen((o) => !o)}>
            <BriefcaseMedical />
            Objetos
            <span className="cost">{items.length} disponibles</span>
          </button>
          <button className="btn action-btn btn-ghost" disabled={disabled} onClick={() => act({ type: 'flee' })}>
            <Footprints />
            Huir
            <span className="cost">{fleePct}% de éxito</span>
          </button>
        </div>
      </div>

      {showResult && combat.status !== 'ongoing' && (
        <div className={`combat-result ${combat.status}`}>
          {combat.status === 'won' && (
            <>
              <h2>Eliminado</h2>
              <p className="dim" style={{ textAlign: 'center', margin: 0 }}>
                {def.name} nivel {combat.zombie.level} · +{outcome?.reward?.xp ?? 0} XP
              </p>
              <div className="loot-list">
                {Object.entries(outcome?.added ?? {}).map(([id, n], i) => {
                  const item = ITEMS[id as keyof typeof ITEMS];
                  return (
                    <div key={id} className={`loot-item rarity-${item.rarity}`} style={{ animationDelay: `${i * 90}ms` }}>
                      <ItemIcon id={item.id} size={20} /> {n} × {item.name}
                    </div>
                  );
                })}
                {Object.keys(outcome?.added ?? {}).length === 0 && <span className="muted">No llevaba nada útil.</span>}
              </div>
              {outcome && Object.keys(outcome.overflow).length > 0 && (
                <p className="chip warn" style={{ justifySelf: 'center', margin: '0 auto 16px' }}>
                  Mochila llena: dejaste {describeItems(outcome.overflow)}
                </p>
              )}
            </>
          )}
          {combat.status === 'lost' && (
            <>
              <h2>Caíste</h2>
              <p className="dim" style={{ textAlign: 'center' }}>
                Te arrastraste hasta un lugar seguro.
                {outcome && Object.keys(outcome.lost).length > 0 ? ` Perdiste ${describeItems(outcome.lost)}.` : ''}
              </p>
              <div style={{ height: 16 }} />
            </>
          )}
          {combat.status === 'fled' && (
            <>
              <h2 style={{ color: 'var(--text)' }}>Escapaste</h2>
              <p className="dim" style={{ textAlign: 'center' }}>Vivís para pelear otro día.</p>
              <div style={{ height: 16 }} />
            </>
          )}
          <button className="btn btn-primary btn-lg btn-block" onClick={leaveCombat}>
            Volver al mapa
          </button>
        </div>
      )}
    </div>
  );
}
