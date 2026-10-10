import { describe, expect, it } from 'vitest';
import { cellOf, haversineM, offsetM } from '../src/core/geo';
import { placeSpawns } from '../src/core/placement';
import { filterSafeZones, generateCellSpawns, generateWorld, nextWindowChange } from '../src/core/spawns';
import { isWithinReach, updateSpeedGuard, validateInteraction } from '../src/core/interaction';
import { approximateDistanceLabel, fuzzPosition } from '../src/services/privacy';
import type { InteractionRequest } from '../src/core/types';

const CFG = { worldSeed: 'test', zombieWindowMs: 600_000, supplyWindowMs: 1_800_000, infestedCellChance: 0.15 };
const OBELISCO = { lat: -34.60372, lng: -58.38159 };
const RULES = { interactionRadiusM: 40, maxAccuracyBonusM: 15, maxAccuracyForInteractionM: 80 };
const NOW = 1_760_000_000_000;

describe('generación del mundo', () => {
  it('es determinística: mismo lugar y hora = mismos spawns para todos', () => {
    const a = generateWorld(OBELISCO, 2, NOW, CFG);
    const b = generateWorld(OBELISCO, 2, NOW + 1000, CFG);
    expect(a.spawns.map((s) => s.id)).toEqual(b.spawns.map((s) => s.id));
    expect(a.zones).toHaveLength(25);
  });

  it('cambia al pasar a la siguiente ventana de tiempo', () => {
    const cell = cellOf(OBELISCO);
    const a = generateCellSpawns(cell, NOW, CFG).map((s) => s.id);
    const b = generateCellSpawns(cell, NOW + 2_000_000, CFG).map((s) => s.id);
    expect(a).not.toEqual(b);
    expect(nextWindowChange(NOW, CFG)).toBeGreaterThan(NOW);
  });

  it('genera zombies y suministros en un área razonable', () => {
    const w = generateWorld(OBELISCO, 2, NOW, CFG);
    expect(w.spawns.some((s) => s.kind === 'zombie')).toBe(true);
    expect(w.spawns.some((s) => s.kind === 'supply')).toBe(true);
    for (const s of w.spawns) expect(haversineM(OBELISCO, s.position)).toBeLessThan(900);
  });

  it('no hay zombies dentro del radio seguro de un refugio', () => {
    const w = generateWorld(OBELISCO, 2, NOW, CFG);
    const zombie = w.spawns.find((s) => s.kind === 'zombie')!;
    const filtered = filterSafeZones(w.spawns, [zombie.position], 60);
    expect(filtered.find((s) => s.id === zombie.id)).toBeUndefined();
  });

  it('mueve spawns a la calle y descarta los que caen en zonas excluidas', () => {
    const street: [typeof OBELISCO, typeof OBELISCO] = [offsetM(OBELISCO, 0, -300), offsetM(OBELISCO, 0, 300)];
    const spawns = generateWorld(OBELISCO, 0, NOW, CFG).spawns;
    const placed = placeSpawns(spawns, { walkable: [street], excluded: [] }, 500);
    expect(placed.every((s) => s.placement === 'snapped')).toBe(true);
    for (const s of placed) expect(Math.abs(s.position.lat - OBELISCO.lat)).toBeLessThan(0.0001);
    const water = [[offsetM(OBELISCO, -400, -400), offsetM(OBELISCO, -400, 400), offsetM(OBELISCO, 400, 400), offsetM(OBELISCO, 400, -400)]];
    expect(placeSpawns(spawns, { walkable: [street], excluded: [water] }, 500)).toHaveLength(0);
  });
});

describe('interacciones', () => {
  const req = (meters: number, accuracy = 5): InteractionRequest => ({
    playerId: 'p',
    action: 'scavenge',
    targetId: 't',
    targetPosition: OBELISCO,
    playerPosition: offsetM(OBELISCO, meters, 0),
    accuracyM: accuracy,
    timestamp: NOW,
  });

  it('valida alcance con tolerancia por precisión GPS', () => {
    expect(validateInteraction(req(30), RULES, { speedLocked: false, depleted: false }).ok).toBe(true);
    expect(validateInteraction(req(50, 15), RULES, { speedLocked: false, depleted: false }).ok).toBe(true);
    expect(validateInteraction(req(80), RULES, { speedLocked: false, depleted: false }).reason).toBe('out_of_range');
    expect(isWithinReach(OBELISCO, offsetM(OBELISCO, 39, 0), 0, RULES)).toBe(true);
  });

  it('rechaza por velocidad, precisión, agotado o vencido', () => {
    expect(validateInteraction(req(10), RULES, { speedLocked: true, depleted: false }).reason).toBe('too_fast');
    expect(validateInteraction(req(10, 120), RULES, { speedLocked: false, depleted: false }).reason).toBe('low_accuracy');
    expect(validateInteraction(req(10), RULES, { speedLocked: false, depleted: true }).reason).toBe('depleted');
    expect(validateInteraction(req(10), RULES, { speedLocked: false, depleted: false, expiresAt: NOW - 1 }).reason).toBe('expired');
  });

  it('bloquea al detectar velocidad de vehículo', () => {
    let g = updateSpeedGuard({ last: null, lockedUntil: 0 }, { position: OBELISCO, time: 0 }, 12, 30_000);
    g = updateSpeedGuard(g, { position: offsetM(OBELISCO, 200, 0), time: 10_000 }, 12, 30_000);
    expect(g.lockedUntil).toBe(40_000);
    let w = updateSpeedGuard({ last: null, lockedUntil: 0 }, { position: OBELISCO, time: 0 }, 12, 30_000);
    w = updateSpeedGuard(w, { position: offsetM(OBELISCO, 15, 0), time: 10_000 }, 12, 30_000);
    expect(w.lockedUntil).toBe(0);
  });
});

describe('privacidad', () => {
  it('difumina la posición de forma estable y a distancia acotada', () => {
    const a = fuzzPosition(OBELISCO, 'jugador-1');
    const b = fuzzPosition(offsetM(OBELISCO, 3, 3), 'jugador-1');
    expect(a).toEqual(b);
    expect(haversineM(OBELISCO, a)).toBeLessThan(300);
    expect(haversineM(OBELISCO, a)).toBeGreaterThan(0);
    expect(approximateDistanceLabel(342)).toBe('~300 m');
  });
});
