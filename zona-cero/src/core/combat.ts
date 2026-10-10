import { GAME_STAMINA, HEAVY_MULTIPLIER } from './balance';
import { factionModifiers } from './factions';
import { countOf } from './inventory';
import { FISTS, ITEMS } from './items';
import { rollLoot } from './loot';
import { armorDefense, maxHealth, maxStamina } from './player';
import type { Rng } from './rng';
import { ZOMBIES, zombieDamageForLevel, zombieHealthForLevel } from './zombies';
import type {
  CombatAction,
  CombatEvent,
  CombatState,
  Inventory,
  ItemId,
  PlayerState,
  Reward,
  WeaponStats,
  ZombieTypeId,
} from './types';

// Motor de combate por turnos. Puro y determinístico dado un RNG:
// el mismo RNG + mismas acciones = mismo resultado (útil para tests y para
// validarlo en un servidor en el futuro).

const clamp = (v: number, min: number, max: number): number => Math.max(min, Math.min(max, v));

const CRIT_MULTIPLIER = 1.75;
const EXHAUSTED_DAMAGE = 0.6;
const EXHAUSTED_ACCURACY = 0.25;
const DEFEND_DAMAGE = 0.4;
const DEFEND_STAMINA = 12;
const CHARGE_MULTIPLIER = 1.8;
/** Ataques normales del Bruto entre embestidas. */
const CHARGE_EVERY = 3;

export interface StartCombatParams {
  spawnId: string;
  zombieType: ZombieTypeId;
  player: PlayerState;
  rng: Rng;
}

function weaponOf(id: ItemId | null): WeaponStats | null {
  return id ? (ITEMS[id].weapon ?? null) : null;
}

export function startCombat({ spawnId, zombieType, player, rng }: StartCombatParams): CombatState {
  const def = ZOMBIES[zombieType];
  // Los tipos avanzados nunca aparecen muy por debajo de su nivel recomendado:
  // un Bruto sigue siendo peligroso aunque el jugador sea novato.
  const level = Math.max(1, def.recommendedLevel - 1, player.level + rng.int(-1, 1));
  const hp = zombieHealthForLevel(def, level);
  const meleeId = player.equipment.melee;
  const firearmId = player.equipment.firearm;
  const available: Inventory = {};
  for (const id of Object.keys(player.inventory) as ItemId[]) {
    if (id === 'ammo' || ITEMS[id].effects) available[id] = countOf(player.inventory, id);
  }
  return {
    spawnId,
    zombie: {
      typeId: zombieType,
      name: def.name,
      level,
      health: hp,
      maxHealth: hp,
      damage: zombieDamageForLevel(def, level),
      accuracy: def.accuracy,
      evasion: def.evasion,
      charging: false,
      chargeIn: CHARGE_EVERY,
      stunned: false,
      screamsLeft: def.ability === 'call_horde' ? 2 : 0,
    },
    player: {
      health: player.health,
      maxHealth: maxHealth(player),
      stamina: player.stamina,
      maxStamina: maxStamina(player),
      defending: false,
      melee: weaponOf(meleeId) ?? FISTS,
      meleeName: meleeId ? ITEMS[meleeId].name : 'Puños',
      firearm: weaponOf(firearmId),
      firearmName: firearmId ? ITEMS[firearmId].name : null,
      defense: armorDefense(player),
    },
    available,
    consumed: {},
    turn: 1,
    status: 'ongoing',
    lastEvents: [],
    log: [],
    xpMultiplier: factionModifiers(player.factionId).combatXp,
  };
}

/** Cantidad disponible de un objeto descontando lo gastado en el combate. */
export function remainingInCombat(state: CombatState, id: ItemId): number {
  return countOf(state.available, id) - countOf(state.consumed, id);
}

export function canShoot(state: CombatState): boolean {
  const fa = state.player.firearm;
  return !!fa && remainingInCombat(state, 'ammo') >= fa.ammoPerShot;
}

/** Objetos que se pueden usar durante el combate. */
export function usableItems(state: CombatState): ItemId[] {
  return (Object.keys(state.available) as ItemId[]).filter(
    (id) => ITEMS[id].effects && remainingInCombat(state, id) > 0,
  );
}

function rollDamage(range: [number, number], rng: Rng): number {
  return rng.int(range[0], range[1]);
}

/** Resuelve un turno completo: acción del jugador + respuesta del zombie. */
export function resolveTurn(prev: CombatState, action: CombatAction, rng: Rng): CombatState {
  if (prev.status !== 'ongoing') return prev;

  const s: CombatState = {
    ...prev,
    zombie: { ...prev.zombie },
    player: { ...prev.player, defending: false },
    consumed: { ...prev.consumed },
  };
  const events: CombatEvent[] = [];
  const z = s.zombie;
  const p = s.player;
  const def = ZOMBIES[z.typeId];
  let zombieActs = true;
  let fleeFailed = false;
  let killedByRanged = false;

  const strike = (weapon: WeaponStats, opts: { ranged: boolean; multiplier: number; accuracyMod: number; critMod: number }) => {
    const stunBonus = z.stunned;
    const hitChance = clamp(weapon.accuracy + opts.accuracyMod - z.evasion * (opts.ranged ? 0.5 : 1) + (stunBonus ? 0.2 : 0), 0.05, 0.98);
    if (!rng.chance(hitChance)) {
      events.push({ kind: 'player_miss', ranged: opts.ranged });
      return;
    }
    const crit = stunBonus || rng.chance(weapon.critChance + opts.critMod);
    const dmg = Math.max(1, Math.round(rollDamage(weapon.damage, rng) * opts.multiplier * (crit ? CRIT_MULTIPLIER : 1)));
    z.health = Math.max(0, z.health - dmg);
    events.push({ kind: 'player_hit', damage: dmg, crit, ranged: opts.ranged, stunBonus });
    if (z.health <= 0 && opts.ranged) killedByRanged = true;
  };

  // --- Turno del jugador --------------------------------------------------
  switch (action.type) {
    case 'attack':
    case 'heavy': {
      const heavy = action.type === 'heavy';
      const cost = heavy ? GAME_STAMINA.heavy : GAME_STAMINA.attack;
      const exhausted = p.stamina < cost;
      if (exhausted) events.push({ kind: 'exhausted' });
      p.stamina = Math.max(0, p.stamina - cost);
      const multiplier = (heavy && !exhausted ? HEAVY_MULTIPLIER : 1) * (exhausted ? EXHAUSTED_DAMAGE : 1);
      strike(p.melee, {
        ranged: false,
        multiplier,
        accuracyMod: (heavy && !exhausted ? -0.15 : 0) - (exhausted ? EXHAUSTED_ACCURACY : 0),
        critMod: heavy && !exhausted ? 0.05 : 0,
      });
      break;
    }
    case 'shoot': {
      const fa = p.firearm;
      if (!fa || remainingInCombat(s, 'ammo') < fa.ammoPerShot) {
        // Sin munición no se pierde el turno: solo se avisa.
        events.push({ kind: 'no_ammo' });
        return { ...s, player: { ...p, defending: prev.player.defending }, lastEvents: events, log: [...prev.log, ...events] };
      }
      s.consumed.ammo = countOf(s.consumed, 'ammo') + fa.ammoPerShot;
      p.stamina = Math.max(0, p.stamina - GAME_STAMINA.shoot);
      strike(fa, { ranged: true, multiplier: 1, accuracyMod: 0, critMod: 0 });
      break;
    }
    case 'defend': {
      p.defending = true;
      const before = p.stamina;
      p.stamina = Math.min(p.maxStamina, p.stamina + DEFEND_STAMINA);
      events.push({ kind: 'defend', stamina: p.stamina - before });
      break;
    }
    case 'use_item': {
      const item = ITEMS[action.itemId];
      if (!item.effects || remainingInCombat(s, action.itemId) <= 0) {
        return prev;
      }
      s.consumed[action.itemId] = countOf(s.consumed, action.itemId) + 1;
      const hBefore = p.health;
      const sBefore = p.stamina;
      p.health = Math.min(p.maxHealth, p.health + (item.effects.health ?? 0));
      p.stamina = Math.min(p.maxStamina, p.stamina + (item.effects.stamina ?? 0));
      events.push({ kind: 'heal', itemId: action.itemId, health: p.health - hBefore, stamina: p.stamina - sBefore });
      break;
    }
    case 'flee': {
      const chance = clamp(def.fleeChance + (z.stunned ? 0.15 : 0) - (z.charging ? 0.1 : 0), 0.05, 0.95);
      if (rng.chance(chance)) {
        events.push({ kind: 'flee_success' });
        s.status = 'fled';
        zombieActs = false;
      } else {
        events.push({ kind: 'flee_fail' });
        fleeFailed = true;
      }
      break;
    }
  }

  // --- ¿Murió el zombie? ----------------------------------------------------
  if (z.health <= 0) {
    events.push({ kind: 'zombie_killed' });
    s.status = 'won';
    zombieActs = false;
    if (def.ability === 'toxic_burst' && !killedByRanged) {
      // La explosión tóxica nunca remata: deja al jugador con al menos 1 de salud.
      const burst = rng.int(6, 10) + (z.level - 1);
      const dmg = Math.min(burst, Math.max(0, p.health - 1));
      p.health -= dmg;
      events.push({ kind: 'toxic_burst', damage: dmg });
    }
  }

  // --- Turno del zombie -------------------------------------------------------
  if (zombieActs && s.status === 'ongoing') {
    zombieTurn(s, events, rng, fleeFailed);
  }

  s.turn = prev.turn + 1;
  s.lastEvents = events;
  s.log = [...prev.log, ...events];
  return s;
}

function zombieTurn(s: CombatState, events: CombatEvent[], rng: Rng, fleeFailed: boolean): void {
  const z = s.zombie;
  const p = s.player;
  const def = ZOMBIES[z.typeId];

  if (z.stunned) {
    // Pierde el turno mientras se recupera.
    z.stunned = false;
    events.push({ kind: 'zombie_stunned' });
    return;
  }

  // Bruto: tras algunos ataques normales prepara una embestida que se resuelve al turno siguiente.
  if (def.ability === 'charge') {
    if (z.charging) {
      z.charging = false;
      z.chargeIn = CHARGE_EVERY;
      if (p.defending) {
        z.stunned = true;
        events.push({ kind: 'zombie_miss', charged: true });
        events.push({ kind: 'zombie_stunned' });
        return;
      }
      attack(s, events, rng, { multiplier: CHARGE_MULTIPLIER, accuracyMod: 0.15, charged: true });
      return;
    }
    if (z.chargeIn <= 0) {
      z.charging = true;
      events.push({ kind: 'zombie_charge_prepare' });
      return;
    }
    z.chargeIn--;
  }

  // Chillón: si está herido, grita y llegan refuerzos que lo protegen.
  if (def.ability === 'call_horde' && z.screamsLeft > 0 && z.health < z.maxHealth * 0.6 && rng.chance(0.5)) {
    z.screamsLeft--;
    const healed = Math.min(z.maxHealth - z.health, Math.round(z.maxHealth * 0.3));
    z.health += healed;
    events.push({ kind: 'zombie_scream', healed });
    return;
  }

  attack(s, events, rng, { multiplier: 1, accuracyMod: fleeFailed ? 0.1 : 0, charged: false });

  // Corredor: a veces ataca dos veces.
  if (def.ability === 'double_strike' && s.status === 'ongoing' && rng.chance(0.3)) {
    attack(s, events, rng, { multiplier: 0.7, accuracyMod: 0, charged: false });
  }
}

function attack(
  s: CombatState,
  events: CombatEvent[],
  rng: Rng,
  opts: { multiplier: number; accuracyMod: number; charged: boolean },
): void {
  const z = s.zombie;
  const p = s.player;
  const hitChance = clamp(z.accuracy + opts.accuracyMod - (p.defending ? 0.15 : 0), 0.05, 0.95);
  if (!rng.chance(hitChance)) {
    events.push({ kind: 'zombie_miss', charged: opts.charged });
    return;
  }
  const raw = Math.round(rollDamage(z.damage, rng) * opts.multiplier * (p.defending ? DEFEND_DAMAGE : 1));
  const damage = Math.max(1, raw - p.defense);
  const blocked = raw - damage;
  p.health = Math.max(0, p.health - damage);
  events.push({ kind: 'zombie_hit', damage, blocked: Math.max(0, blocked), charged: opts.charged });
  if (p.health <= 0) {
    events.push({ kind: 'player_down' });
    s.status = 'lost';
  }
}

/** Recompensa por ganar el encuentro. */
export function combatReward(state: CombatState, rng: Rng): Reward {
  const def = ZOMBIES[state.zombie.typeId];
  const xp = Math.round(def.xp * (1 + 0.15 * (state.zombie.level - 1)) * state.xpMultiplier);
  return { xp, items: rollLoot(def.loot, rng) };
}

/** Texto en español para cada evento (registro de combate). */
export function describeEvent(e: CombatEvent, state: Pick<CombatState, 'zombie' | 'player'>): string {
  const zn = state.zombie.name;
  switch (e.kind) {
    case 'player_hit':
      if (e.stunBonus) return `¡Golpe certero al ${zn} aturdido! −${e.damage}`;
      if (e.ranged) return e.crit ? `¡Disparo a la cabeza! −${e.damage}` : `Disparo certero. −${e.damage}`;
      return e.crit ? `¡Golpe crítico! −${e.damage}` : `Golpeás al ${zn}. −${e.damage}`;
    case 'player_miss':
      return e.ranged ? 'El disparo se pierde en la oscuridad.' : `El ${zn} esquiva tu golpe.`;
    case 'exhausted':
      return 'Estás agotado: tus golpes pierden fuerza.';
    case 'no_ammo':
      return 'Sin munición suficiente.';
    case 'defend':
      return `Te cubrís y recuperás el aliento (+${e.stamina} resistencia).`;
    case 'heal': {
      const parts = [e.health > 0 ? `+${e.health} salud` : '', e.stamina > 0 ? `+${e.stamina} resistencia` : ''].filter(Boolean);
      return `Usás ${ITEMS[e.itemId].name}: ${parts.join(', ') || 'sin efecto'}.`;
    }
    case 'flee_success':
      return 'Lográs escapar entre los escombros.';
    case 'flee_fail':
      return `¡El ${zn} te corta el paso!`;
    case 'zombie_hit':
      if (e.charged) return `¡EMBESTIDA! Recibís −${e.damage}${e.blocked > 0 ? ` (bloqueado ${e.blocked})` : ''}`;
      return `El ${zn} te muerde. −${e.damage}${e.blocked > 0 ? ` (bloqueado ${e.blocked})` : ''}`;
    case 'zombie_miss':
      return e.charged ? '¡Esquivás la embestida! Queda aturdido.' : `El ${zn} falla el ataque.`;
    case 'zombie_charge_prepare':
      return `El ${zn} se prepara para embestir... ¡Cubrite!`;
    case 'zombie_stunned':
      return `El ${zn} está aturdido.`;
    case 'zombie_scream':
      return `¡El ${zn} chilla! Llegan refuerzos (+${e.healed} vida).`;
    case 'toxic_burst':
      return `¡Explota en una nube tóxica! −${e.damage}`;
    case 'zombie_killed':
      return `${zn} eliminado.`;
    case 'player_down':
      return 'Caés al suelo...';
  }
}
