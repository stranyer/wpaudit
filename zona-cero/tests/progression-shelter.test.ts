import { describe, expect, it } from 'vitest';
import { GAME_CONFIG } from '../src/config/gameConfig';
import { applyDeathPenalty, applyRegen, consumeItem, createPlayer, equipItem, grantXp, restAtShelter, takeItems } from '../src/core/player';
import { addXp, xpToNext } from '../src/core/progression';
import { applyDonation, planHordeAttack, remainingRequirements, resolveHordeAttack, upgradeProgress } from '../src/core/shelter';
import { createRng } from '../src/core/rng';
import type { Shelter } from '../src/core/types';

const shelter = (): Shelter => ({
  id: 'sh1',
  name: 'Refugio Test',
  ownerId: 'p1',
  ownerName: 'Tester',
  factionId: null,
  level: 1,
  position: { lat: -34.6, lng: -58.38 },
  progress: {},
  contributions: [],
  createdAt: 0,
});

describe('progresión', () => {
  it('sube de nivel y conserva la XP sobrante', () => {
    const r = addXp(1, 0, xpToNext(1) + 10);
    expect(r).toEqual({ level: 2, xp: 10, levelsGained: 1 });
  });

  it('subir de nivel recupera salud y resistencia', () => {
    const p = { ...createPlayer('p', 'T', 0), health: 10, stamina: 5 };
    const { player, levelsGained } = grantXp(p, 1000);
    expect(levelsGained).toBeGreaterThan(1);
    expect(player.health).toBe(100 + 8 * (player.level - 1));
  });
});

describe('supervivencia', () => {
  it('regenera resistencia con el tiempo y salud solo hasta el 50%', () => {
    const p = { ...createPlayer('p', 'T', 0), health: 20, stamina: 0 };
    const r = applyRegen(p, 60 * 60_000, GAME_CONFIG.regen);
    expect(r.stamina).toBe(100);
    expect(r.health).toBe(50);
  });

  it('consumir comida suma resistencia y la descuenta', () => {
    const p = { ...createPlayer('p', 'T', 0), stamina: 50 };
    const r = consumeItem(p, 'food')!;
    expect(r.stamina).toBe(70);
    expect(r.inventory.food).toBe(1);
    expect(consumeItem({ ...p, inventory: {} }, 'food')).toBeNull();
  });

  it('desequipa automáticamente lo que ya no está en el inventario', () => {
    const p = equipItem({ ...createPlayer('p', 'T', 0), inventory: { pipe: 1 } }, 'pipe')!;
    expect(p.equipment.melee).toBe('pipe');
    expect(takeItems(p, { pipe: 1 })!.equipment.melee).toBeNull();
  });

  it('caer en combate cuesta parte de los recursos', () => {
    const p = { ...createPlayer('p', 'T', 0), inventory: { wood: 10, metal: 3, machete: 1 } };
    const { player, lost } = applyDeathPenalty(p, GAME_CONFIG.death);
    expect(lost).toEqual({ wood: 3 });
    expect(player.inventory.machete).toBe(1);
    expect(player.stats.deaths).toBe(1);
  });

  it('descansar en el refugio tiene enfriamiento', () => {
    const p = { ...createPlayer('p', 'T', 0), health: 10 };
    const first = restAtShelter(p, 2, 1_000_000);
    expect(first.ok).toBe(true);
    expect(first.player.health).toBe(50);
    expect(restAtShelter(first.player, 2, 1_000_000 + 60_000).ok).toBe(false);
  });
});

describe('refugios', () => {
  it('acepta solo lo que el próximo nivel necesita', () => {
    const r = applyDonation(shelter(), 'p1', 'Tester', { wood: 50, food: 5 });
    expect(r.accepted).toEqual({ wood: 20 });
    expect(r.leveledUp).toBe(false);
    expect(remainingRequirements(r.shelter)).toEqual({ metal: 6 });
    expect(upgradeProgress(r.shelter)).toBeCloseTo(20 / 26);
  });

  it('sube de nivel al completar los requisitos y registra aportes', () => {
    let s = applyDonation(shelter(), 'p1', 'Tester', { wood: 20 }).shelter;
    const r = applyDonation(s, 'p2', 'Otra', { metal: 6 });
    expect(r.leveledUp).toBe(true);
    expect(r.shelter.level).toBe(2);
    expect(r.shelter.progress).toEqual({});
    s = r.shelter;
    expect(s.contributions.map((c) => c.playerId)).toEqual(['p1', 'p2']);
  });

  it('resuelve ataques de hordas según la defensa', () => {
    const rng = createRng('horda');
    const attack = planHordeAttack({ id: 'sh1', level: 3 }, 0, rng);
    const strong = resolveHordeAttack({ level: 3 }, attack, 100, rng);
    expect(strong.defended).toBe(true);
    const weak = resolveHordeAttack({ level: 1 }, { ...attack, strength: 999 }, 0, rng);
    expect(weak.defended).toBe(false);
    expect(weak.progressLossRatio).toBeGreaterThan(0);
  });
});
