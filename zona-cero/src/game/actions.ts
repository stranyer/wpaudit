import { GAME_CONFIG } from '../config/gameConfig';
import { combatReward, resolveTurn, startCombat } from '../core/combat';
import { craft, RECIPES } from '../core/crafting';
import { factionModifiers } from '../core/factions';
import { haversineM } from '../core/geo';
import { REJECTION_MESSAGES, isWithinReach } from '../core/interaction';
import { entries, removeItems } from '../core/inventory';
import { ITEMS } from '../core/items';
import { rollSupplyLoot } from '../core/loot';
import { placePoint } from '../core/placement';
import {
  applyDeathPenalty,
  capacityOf,
  consumeItem,
  equipItem,
  giveItems,
  restAtShelter,
  takeItems,
  unequipSlot,
} from '../core/player';
import { randomRng } from '../core/rng';
import { shelterLevelDef } from '../core/shelter';
import { SUPPLIES } from '../core/supplies';
import type {
  CombatAction,
  EquipmentSlot,
  FactionId,
  Inventory,
  ItemId,
  LatLng,
  ResourceId,
  Shelter,
  SupplySpawn,
  ZombieSpawn,
} from '../core/types';
import { fuzzPosition } from '../services/privacy';
import { useGameStore, type CombatOutcome } from '../store/gameStore';
import { useLocationStore } from '../store/locationStore';
import { useUiStore, type ToastTone } from '../store/uiStore';
import { useWorldStore } from '../store/worldStore';
import { getMapPlacementData } from '../map/placementBridge';
import { awardXp, demoProvider, getRepo, loadShelters } from './session';

// Acciones del jugador. Cada una valida, aplica la lógica pura del core y
// actualiza los stores. La UI solo llama a estas funciones.

const toast = (text: string, tone?: ToastTone) => useUiStore.getState().toast(text, tone);

export function describeItems(items: Inventory): string {
  return entries(items)
    .map(([id, n]) => `${n} ${ITEMS[id].name}`)
    .join(', ');
}

function currentFix(): { position: LatLng; accuracyM: number } | null {
  const loc = useLocationStore.getState();
  return loc.position ? { position: loc.position, accuracyM: loc.accuracyM } : null;
}

/** Nivel del refugio propio (habilita recetas y bonus de botín). */
export function ownShelter(): Shelter | null {
  const player = useGameStore.getState().player;
  if (!player) return null;
  return useWorldStore.getState().shelters.find((s) => s.ownerId === player.id) ?? null;
}

export function workshopLevel(): number {
  return ownShelter()?.level ?? 0;
}

function markDepleted(id: string, expiresAt: number): void {
  const game = useGameStore.getState();
  game.set({ depleted: { ...game.depleted, [id]: expiresAt } });
  useWorldStore.getState().removeSpawn(id);
}

// ---------------------------------------------------------------------------
// Exploración
// ---------------------------------------------------------------------------

export async function scavenge(spawn: SupplySpawn): Promise<void> {
  const game = useGameStore.getState();
  const player = game.player;
  const fix = currentFix();
  if (!player || !fix) return;
  const def = SUPPLIES[spawn.supplyType];
  if (player.stamina < def.staminaCost) {
    toast('Estás agotado. Comé algo o descansá un poco.', 'warn');
    return;
  }
  const result = await getRepo().validateInteraction({
    playerId: player.id,
    action: 'scavenge',
    targetId: spawn.id,
    targetExpiresAt: spawn.expiresAt,
    targetPosition: spawn.position,
    playerPosition: fix.position,
    accuracyM: fix.accuracyM,
    timestamp: Date.now(),
  });
  if (!result.ok) {
    toast(REJECTION_MESSAGES[result.reason ?? 'out_of_range'], 'warn');
    if (result.reason === 'depleted' || result.reason === 'expired') markDepleted(spawn.id, spawn.expiresAt);
    return;
  }

  const multiplier = factionModifiers(player.factionId).supplyLoot + shelterLevelDef(workshopLevel() || 1).lootBonus;
  const loot = rollSupplyLoot(def, randomRng(), multiplier);
  let added: Inventory = {};
  let overflow: Inventory = {};
  game.updatePlayer((p) => {
    const r = giveItems({ ...p, stamina: Math.max(0, p.stamina - def.staminaCost) }, loot);
    added = r.added;
    overflow = r.overflow;
    return { ...r.player, stats: { ...r.player.stats, suppliesLooted: r.player.stats.suppliesLooted + 1 } };
  });
  markDepleted(spawn.id, spawn.expiresAt);
  if (entries(added).length > 0) toast(`+ ${describeItems(added)}`, 'loot');
  if (entries(overflow).length > 0) toast(`Mochila llena: dejaste ${describeItems(overflow)}`, 'warn');
  awardXp(def.xp, null);
}

// ---------------------------------------------------------------------------
// Combate
// ---------------------------------------------------------------------------

export async function engage(spawn: ZombieSpawn): Promise<void> {
  const game = useGameStore.getState();
  const player = game.player;
  const fix = currentFix();
  if (!player || !fix || game.combat) return;
  if (player.health <= 5) {
    toast('Estás muy herido para pelear. Curate primero.', 'warn');
    return;
  }
  const result = await getRepo().validateInteraction({
    playerId: player.id,
    action: 'encounter',
    targetId: spawn.id,
    targetExpiresAt: spawn.expiresAt,
    targetPosition: spawn.position,
    playerPosition: fix.position,
    accuracyM: fix.accuracyM,
    timestamp: Date.now(),
  });
  if (!result.ok) {
    toast(REJECTION_MESSAGES[result.reason ?? 'out_of_range'], 'warn');
    return;
  }
  const combat = startCombat({ spawnId: spawn.id, zombieType: spawn.zombieType, player, rng: randomRng() });
  game.set({ combat, combatSpawn: spawn, combatOutcome: null });
  useUiStore.getState().go('combat');
}

/** Resuelve un turno. Devuelve el nuevo estado para que la UI anime los eventos. */
export function combatAction(action: CombatAction) {
  const game = useGameStore.getState();
  const state = game.combat;
  if (!state || state.status !== 'ongoing') return state;
  const next = resolveTurn(state, action, randomRng());
  game.set({ combat: next });
  if (next.status !== 'ongoing') settleCombat();
  return next;
}

/** Aplica el resultado del combate al jugador (se llama una sola vez al terminar). */
function settleCombat(): void {
  const game = useGameStore.getState();
  const state = game.combat;
  const spawn = game.combatSpawn;
  const player = game.player;
  if (!state || !spawn || !player || state.status === 'ongoing') return;

  // Estado del combate -> jugador: salud, resistencia y objetos gastados.
  let p = {
    ...player,
    health: state.player.health,
    stamina: state.player.stamina,
    lastRegenAt: Date.now(),
  };
  p = takeItems(p, state.consumed) ?? p;

  const outcome: CombatOutcome = { status: state.status, reward: null, added: {}, overflow: {}, lost: {}, levelsGained: 0 };

  if (state.status === 'won') {
    const reward = combatReward(state, randomRng());
    const r = giveItems(p, reward.items);
    p = {
      ...r.player,
      stats: {
        ...r.player.stats,
        encountersWon: r.player.stats.encountersWon + 1,
        zombiesKilled: {
          ...r.player.stats.zombiesKilled,
          [state.zombie.typeId]: (r.player.stats.zombiesKilled[state.zombie.typeId] ?? 0) + 1,
        },
      },
    };
    outcome.reward = reward;
    outcome.added = r.added;
    outcome.overflow = r.overflow;
    markDepleted(spawn.id, spawn.expiresAt);
  } else if (state.status === 'lost') {
    const death = applyDeathPenalty(p, GAME_CONFIG.death);
    p = death.player;
    outcome.lost = death.lost;
  } else {
    p = { ...p, stats: { ...p.stats, encountersFled: p.stats.encountersFled + 1 } };
  }

  game.set({ player: p, combatOutcome: outcome });
  if (outcome.reward) outcome.levelsGained = awardXp(outcome.reward.xp, null);
  game.set({ combatOutcome: { ...outcome } });
}

export function leaveCombat(): void {
  useGameStore.getState().set({ combat: null, combatSpawn: null, combatOutcome: null });
  useUiStore.getState().go('map');
}

// ---------------------------------------------------------------------------
// Inventario y fabricación
// ---------------------------------------------------------------------------

export function consumeFromInventory(itemId: ItemId): void {
  const game = useGameStore.getState();
  const player = game.player;
  if (!player) return;
  const next = consumeItem(player, itemId);
  if (!next) return;
  game.set({ player: next });
  const dh = Math.round(next.health - player.health);
  const ds = Math.round(next.stamina - player.stamina);
  const parts = [dh > 0 ? `+${dh} salud` : '', ds > 0 ? `+${ds} resistencia` : ''].filter(Boolean);
  toast(`${ITEMS[itemId].name}: ${parts.join(', ') || 'ya estabas al máximo'}`, 'good');
}

export function equip(itemId: ItemId): void {
  const game = useGameStore.getState();
  const next = game.player && equipItem(game.player, itemId);
  if (next) {
    game.set({ player: next });
    toast(`Equipaste: ${ITEMS[itemId].name}`, 'good');
  }
}

export function unequip(slot: EquipmentSlot): void {
  useGameStore.getState().updatePlayer((p) => unequipSlot(p, slot));
}

export function craftRecipe(recipeId: string): void {
  const game = useGameStore.getState();
  const player = game.player;
  const recipe = RECIPES.find((r) => r.id === recipeId);
  if (!player || !recipe) return;
  const result = craft(player.inventory, recipe, workshopLevel(), capacityOf(player));
  if (!result) {
    toast('No se puede fabricar ahora.', 'warn');
    return;
  }
  game.set({
    player: { ...player, inventory: result.inventory, stats: { ...player.stats, itemsCrafted: player.stats.itemsCrafted + 1 } },
  });
  toast(`Fabricaste: ${describeItems(result.crafted)}`, 'good');
  awardXp(GAME_CONFIG.xp.craft, null);
}

// ---------------------------------------------------------------------------
// Refugios
// ---------------------------------------------------------------------------

export const SHELTER_BUILD_COST: Inventory = { wood: 5, metal: 3 };

/**
 * Crea el refugio propio. Por privacidad, NO se ubica en la posición real del jugador:
 * se difumina a una grilla de ~250 m y se ajusta a la calle pública más cercana.
 */
export async function buildShelter(name: string): Promise<Shelter | null> {
  const game = useGameStore.getState();
  const player = game.player;
  const fix = currentFix();
  if (!player || !fix) return null;
  if (ownShelter()) {
    toast('Ya tenés un refugio.', 'warn');
    return null;
  }
  const afterCost = takeItems(player, SHELTER_BUILD_COST);
  if (!afterCost) {
    toast(`Necesitás ${describeItems(SHELTER_BUILD_COST)} para montar el campamento.`, 'warn');
    return null;
  }
  const fuzzed = fuzzPosition(fix.position, `shelter:${player.id}`);
  const data = getMapPlacementData();
  const publicPosition = (data && placePoint(fuzzed, data, 150)) || fuzzed;
  try {
    const shelter = await getRepo().createShelter({
      name: name.trim().slice(0, 32) || `Refugio de ${player.name}`,
      ownerId: player.id,
      ownerName: player.name,
      factionId: player.factionId,
      publicPosition,
    });
    game.set({ player: afterCost });
    useWorldStore.getState().upsertShelter(shelter);
    toast('¡Campamento montado! Está en un punto público cercano.', 'good');
    awardXp(25, null);
    return shelter;
  } catch (err) {
    toast(err instanceof Error ? err.message : 'No se pudo crear el refugio.', 'bad');
    return null;
  }
}

export function distanceToShelter(shelter: Shelter): number | null {
  const fix = currentFix();
  return fix ? haversineM(fix.position, shelter.position) : null;
}

export function isNearShelter(shelter: Shelter): boolean {
  const fix = currentFix();
  return !!fix && isWithinReach(fix.position, shelter.position, fix.accuracyM, GAME_CONFIG);
}

export async function donate(shelter: Shelter, resources: Partial<Record<ResourceId, number>>): Promise<void> {
  const game = useGameStore.getState();
  const player = game.player;
  const fix = currentFix();
  if (!player || !fix) return;
  // Solo se ofrece lo que el jugador realmente tiene.
  const offered: Partial<Record<ResourceId, number>> = {};
  for (const [res, n] of Object.entries(resources) as [ResourceId, number][]) {
    const have = player.inventory[res] ?? 0;
    const amount = Math.min(have, Math.floor(n));
    if (amount > 0) offered[res] = amount;
  }
  if (Object.keys(offered).length === 0) {
    toast('No tenés esos recursos.', 'warn');
    return;
  }
  const result = await getRepo().donateToShelter({
    shelterId: shelter.id,
    playerId: player.id,
    playerName: player.name,
    resources: offered,
    playerPosition: fix.position,
    accuracyM: fix.accuracyM,
  });
  if (!result.ok || !result.shelter) {
    const msg =
      result.reason === 'out_of_range'
        ? 'Tenés que estar en el refugio para donar.'
        : result.reason === 'invalid_amount'
          ? 'El refugio no necesita esos recursos ahora.'
          : 'No se encontró el refugio.';
    toast(msg, 'warn');
    return;
  }
  const accepted = result.accepted as Inventory;
  const total = entries(accepted).reduce((a, [, n]) => a + n, 0);
  game.updatePlayer((p) => {
    const inv = removeItems(p.inventory, accepted) ?? p.inventory;
    return { ...p, inventory: inv, stats: { ...p.stats, resourcesDonated: p.stats.resourcesDonated + total } };
  });
  useWorldStore.getState().upsertShelter(result.shelter);
  toast(`Donaste ${describeItems(accepted)}`, 'good');
  awardXp(total * GAME_CONFIG.xp.donatePerUnit, null);
  if (result.leveledUp) {
    const def = shelterLevelDef(result.shelter.level);
    useUiStore.getState().celebrate({ title: `${result.shelter.name}: Nivel ${result.shelter.level}`, subtitle: `${def.name}. ${def.perks.join(' · ')}` });
  }
}

export function rest(shelter: Shelter): void {
  const game = useGameStore.getState();
  const player = game.player;
  if (!player) return;
  if (!isNearShelter(shelter)) {
    toast('Tenés que estar en el refugio para descansar.', 'warn');
    return;
  }
  const r = restAtShelter(player, shelter.level, Date.now());
  if (!r.ok) {
    toast(`Todavía no podés descansar (faltan ${Math.ceil(r.cooldownLeftMs / 60000)} min).`, 'warn');
    return;
  }
  game.set({ player: r.player });
  toast('Descansaste junto al fuego. Te sentís mejor.', 'good');
}

// ---------------------------------------------------------------------------
// Comunidad y perfil
// ---------------------------------------------------------------------------

export async function joinFaction(factionId: FactionId | null): Promise<void> {
  const game = useGameStore.getState();
  const player = game.player;
  if (!player) return;
  game.set({ player: { ...player, factionId } });
  if (factionId) {
    await getRepo().joinFaction(player.id, factionId).catch(() => undefined);
    toast('Te uniste a la facción.', 'good');
  }
}

export function renamePlayer(name: string): void {
  const clean = name.trim().slice(0, 20);
  if (clean.length < 2) return;
  useGameStore.getState().updatePlayer((p) => ({ ...p, name: clean }));
}

/** Teletransporte en modo demo (para probar refugios lejanos). */
export function demoTravel(to: LatLng): void {
  if (useLocationStore.getState().mode !== 'demo') return;
  demoProvider()?.teleport(to);
}

export async function refreshShelters(): Promise<void> {
  const p = useLocationStore.getState().position;
  if (p) await loadShelters(p);
}
