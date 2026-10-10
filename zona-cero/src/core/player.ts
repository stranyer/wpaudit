import { factionModifiers } from './factions';
import { addItems, carryCapacity, countOf, entries, removeItems } from './inventory';
import { ITEMS, isResource } from './items';
import { addXp, maxHealthForLevel, maxStaminaForLevel } from './progression';
import { REST_COOLDOWN_MS, shelterLevelDef } from './shelter';
import type { EquipmentSlot, Inventory, ItemId, PlayerState } from './types';

// Operaciones puras sobre el estado del jugador. Todas devuelven un estado nuevo.

export function createPlayer(id: string, name: string, now: number): PlayerState {
  return {
    id,
    name,
    level: 1,
    xp: 0,
    health: maxHealthForLevel(1),
    stamina: maxStaminaForLevel(1),
    inventory: { food: 2, water: 2, medicine: 1, wood: 2 },
    equipment: { melee: null, firearm: null, armor: null },
    stats: {
      zombiesKilled: {},
      suppliesLooted: 0,
      itemsCrafted: 0,
      resourcesDonated: 0,
      distanceWalkedM: 0,
      encountersWon: 0,
      encountersFled: 0,
      deaths: 0,
      cellsExplored: 0,
    },
    factionId: null,
    lastRegenAt: now,
    lastRestAt: 0,
    createdAt: now,
  };
}

export const maxHealth = (p: Pick<PlayerState, 'level'>): number => maxHealthForLevel(p.level);
export const maxStamina = (p: Pick<PlayerState, 'level'>): number => maxStaminaForLevel(p.level);
export const capacityOf = (p: Pick<PlayerState, 'level'>): number => carryCapacity(p.level);

const clamp = (v: number, min: number, max: number): number => Math.max(min, Math.min(max, v));

export interface RegenConfig {
  staminaPerMinute: number;
  healthPerMinute: number;
  healthPassiveCap: number;
}

/** Regeneración pasiva desde `lastRegenAt` (máximo 8 horas acumuladas). */
export function applyRegen(p: PlayerState, now: number, cfg: RegenConfig): PlayerState {
  const elapsedMin = Math.min(8 * 60, Math.max(0, now - p.lastRegenAt) / 60000);
  if (elapsedMin <= 0) return p;
  const mods = factionModifiers(p.factionId);
  const maxH = maxHealth(p);
  const maxS = maxStamina(p);
  const stamina = clamp(p.stamina + elapsedMin * cfg.staminaPerMinute * mods.staminaRegen, 0, maxS);
  const healthCap = Math.max(p.health, maxH * cfg.healthPassiveCap);
  const health = clamp(p.health + elapsedMin * cfg.healthPerMinute, 0, healthCap);
  return { ...p, stamina, health, lastRegenAt: now };
}

export interface XpGain {
  player: PlayerState;
  levelsGained: number;
}

/** Suma XP; al subir de nivel se recupera toda la salud y resistencia. */
export function grantXp(p: PlayerState, amount: number): XpGain {
  const r = addXp(p.level, p.xp, amount);
  if (r.levelsGained === 0) return { player: { ...p, xp: r.xp }, levelsGained: 0 };
  const leveled: PlayerState = { ...p, level: r.level, xp: r.xp };
  return {
    player: { ...leveled, health: maxHealth(leveled), stamina: maxStamina(leveled) },
    levelsGained: r.levelsGained,
  };
}

export interface LootGain {
  player: PlayerState;
  added: Inventory;
  overflow: Inventory;
}

export function giveItems(p: PlayerState, items: Inventory): LootGain {
  const r = addItems(p.inventory, items, capacityOf(p));
  return { player: { ...p, inventory: r.inventory }, added: r.added, overflow: r.overflow };
}

export function takeItems(p: PlayerState, items: Inventory): PlayerState | null {
  const inv = removeItems(p.inventory, items);
  if (!inv) return null;
  return unequipMissing({ ...p, inventory: inv });
}

/** Consume un objeto con efectos (comida, agua, medicina...). */
export function consumeItem(p: PlayerState, itemId: ItemId): PlayerState | null {
  const def = ITEMS[itemId];
  if (!def.effects || countOf(p.inventory, itemId) <= 0) return null;
  const after = takeItems(p, { [itemId]: 1 });
  if (!after) return null;
  return {
    ...after,
    health: clamp(after.health + (def.effects.health ?? 0), 0, maxHealth(after)),
    stamina: clamp(after.stamina + (def.effects.stamina ?? 0), 0, maxStamina(after)),
  };
}

export function slotFor(itemId: ItemId): EquipmentSlot | null {
  const def = ITEMS[itemId];
  if (def.armor) return 'armor';
  if (def.weapon) return def.weapon.ammoPerShot > 0 ? 'firearm' : 'melee';
  return null;
}

export function equipItem(p: PlayerState, itemId: ItemId): PlayerState | null {
  const slot = slotFor(itemId);
  if (!slot || countOf(p.inventory, itemId) <= 0) return null;
  return { ...p, equipment: { ...p.equipment, [slot]: itemId } };
}

export function unequipSlot(p: PlayerState, slot: EquipmentSlot): PlayerState {
  return { ...p, equipment: { ...p.equipment, [slot]: null } };
}

/** Si un objeto equipado ya no está en el inventario, se desequipa. */
function unequipMissing(p: PlayerState): PlayerState {
  let eq = p.equipment;
  for (const slot of ['melee', 'firearm', 'armor'] as EquipmentSlot[]) {
    const id = eq[slot];
    if (id && countOf(p.inventory, id) <= 0) eq = { ...eq, [slot]: null };
  }
  return eq === p.equipment ? p : { ...p, equipment: eq };
}

export function armorDefense(p: PlayerState): number {
  return p.equipment.armor ? (ITEMS[p.equipment.armor].armor?.defense ?? 0) : 0;
}

export interface DeathConfig {
  healthRestoreRatio: number;
  staminaRestore: number;
  resourceLossRatio: number;
}

/** Al caer: se pierde una parte de cada recurso y se reaparece debilitado. */
export function applyDeathPenalty(p: PlayerState, cfg: DeathConfig): { player: PlayerState; lost: Inventory } {
  const lost: Inventory = {};
  for (const [id, n] of entries(p.inventory)) {
    if (!isResource(id)) continue;
    const loss = Math.floor(n * cfg.resourceLossRatio);
    if (loss > 0) lost[id] = loss;
  }
  const inventory = removeItems(p.inventory, lost) ?? p.inventory;
  return {
    player: {
      ...p,
      inventory,
      health: Math.round(maxHealth(p) * cfg.healthRestoreRatio),
      stamina: Math.min(maxStamina(p), cfg.staminaRestore),
      stats: { ...p.stats, deaths: p.stats.deaths + 1 },
    },
    lost,
  };
}

export interface RestResult {
  player: PlayerState;
  ok: boolean;
  cooldownLeftMs: number;
}

/** Descansar en un refugio: recupera según el nivel, con enfriamiento. */
export function restAtShelter(p: PlayerState, shelterLevel: number, now: number): RestResult {
  const left = p.lastRestAt + REST_COOLDOWN_MS - now;
  if (left > 0) return { player: p, ok: false, cooldownLeftMs: left };
  const def = shelterLevelDef(shelterLevel);
  return {
    player: {
      ...p,
      health: clamp(p.health + def.restHealth, 0, maxHealth(p)),
      stamina: clamp(p.stamina + def.restStamina, 0, maxStamina(p)),
      lastRestAt: now,
    },
    ok: true,
    cooldownLeftMs: 0,
  };
}
