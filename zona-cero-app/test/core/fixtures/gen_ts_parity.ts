// Generador de fixtures de paridad TS -> Dart.
//
// Corre la implementación ORIGINAL (TypeScript) y vuelca resultados que los tests
// de Dart (test/core/parity_test.dart) deben reproducir exactamente.
//
// Uso (Node >= 22.6):
//   1. Copiar zona-cero/src/{core,config,services} a un directorio temporal y agregar
//      la extensión `.ts` a los imports relativos:
//        sed -i -E "s#from '(\.\.?/[^']+)'#from '\1.ts'#g" **/*.ts
//   2. Copiar este archivo a la raíz de ese directorio y correr:
//        node --experimental-transform-types --no-warnings gen_ts_parity.ts > ts_parity.json
import { createRng, hashString } from './core/rng.ts';
import { generateWorld, generateCellSpawns, cellThreat } from './core/spawns.ts';
import { cellOf, haversineM, offsetM, normalizeLng, bearingDeg, formatDistance, snapToSegments } from './core/geo.ts';
import { xpToNext, addXp } from './core/progression.ts';
import { rollLoot, rollSupplyLoot } from './core/loot.ts';
import { SUPPLIES, SUPPLY_TYPES } from './core/supplies.ts';
import { ZOMBIE_TYPES } from './core/zombies.ts';
import { startCombat, resolveTurn, usableItems, canShoot, combatReward, describeEvent } from './core/combat.ts';
import {
  createPlayer, equipItem, applyRegen, grantXp, giveItems, consumeItem, applyDeathPenalty, restAtShelter, takeItems,
} from './core/player.ts';
import { applyDonation, planHordeAttack, resolveHordeAttack, upgradeProgress } from './core/shelter.ts';
import { fuzzPosition, approximateDistanceLabel } from './services/privacy.ts';
import { GpsSmoother } from './services/location/smoothing.ts';
import { GAME_CONFIG } from './config/gameConfig.ts';
import type { CombatAction, CombatState, PlayerState, Shelter } from './core/types.ts';

const NOW = 1_760_000_000_000;
const OBELISCO = { lat: -34.60372, lng: -58.38159 };
const out: Record<string, unknown> = {};

// --- RNG -------------------------------------------------------------------
const seq = (seed: number | string, n = 10) => {
  const r = createRng(seed);
  return Array.from({ length: n }, () => r.next());
};
out.rng = {
  seeds: ['zona-cero-v1', 12345, 0, -1, 4294967301, 3.7, -7.9, 'Ñandú ¡é!', '🧟 zona', ''].map((s) => ({ seed: s, values: seq(s) })),
  hashes: ['', 'a', 'zona-cero-v1', 'Ñandú ¡é!', '🧟 zona', 'zona-cero-v1:z:-24326_-19225:2933333'].map((s) => ({ input: s, hash: hashString(s) })),
  helpers: (() => {
    const r = createRng('helpers');
    const ints = Array.from({ length: 20 }, () => r.int(-3, 7));
    const ranges = Array.from({ length: 10 }, () => r.range(0.08, 0.92));
    const chances = Array.from({ length: 10 }, () => r.chance(0.4));
    const picks = Array.from({ length: 10 }, () => r.pick(['a', 'b', 'c', 'd']));
    const weighted = Array.from({ length: 20 }, () => r.weighted([1, 2, 3, 4], (x) => (x === 3 ? 0 : x * 1.5)));
    return { ints, ranges, chances, picks, weighted };
  })(),
};

// --- Progresión ---------------------------------------------------------------
out.xpToNext = Array.from({ length: 40 }, (_, i) => xpToNext(i + 1));
out.addXp = [[1, 0, 95], [3, 50, 1234.5], [39, 0, 99999], [1, 0, -20], [2, 10, 2.5]].map(([l, x, a]) => ({ args: [l, x, a], result: addXp(l, x, a) }));

// --- Mundo --------------------------------------------------------------------
const CFG_DEFAULT = { worldSeed: GAME_CONFIG.worldSeed, zombieWindowMs: GAME_CONFIG.zombieWindowMs, supplyWindowMs: GAME_CONFIG.supplyWindowMs, infestedCellChance: GAME_CONFIG.infestedCellChance };
const CFG_TEST = { worldSeed: 'test', zombieWindowMs: 600_000, supplyWindowMs: 1_800_000, infestedCellChance: 0.15 };
out.world = {
  defaultCfg: generateWorld(OBELISCO, 2, NOW, CFG_DEFAULT),
  testCfg: generateWorld(OBELISCO, 1, NOW + 3_600_000, CFG_TEST),
  cellAtTimes: [0, 599_999, 600_000, NOW, NOW + 2_000_000].map((t) => ({ now: t, spawns: generateCellSpawns(cellOf(OBELISCO), t, CFG_DEFAULT) })),
  threats: [-2, -1, 0, 1, 2].flatMap((dx) => [0, 1].map((dy) => {
    const c = { cx: cellOf(OBELISCO).cx + dx * 37, cy: cellOf(OBELISCO).cy + dy * 53 };
    return { cell: c, threat: cellThreat(c, NOW, CFG_DEFAULT) };
  })),
};

// --- Botín --------------------------------------------------------------------
out.loot = {
  carX: rollLoot(SUPPLIES.car.loot, createRng('x')),
  supplies: SUPPLY_TYPES.flatMap((t) => [0, 1, 2, 3, 4, 5].map((i) => ({ type: t, seed: i, mult: i % 2 ? 1.15 : 1, loot: rollSupplyLoot(SUPPLIES[t], createRng(`${t}:${i}`), i % 2 ? 1.15 : 1) }))),
};

// --- Combate ------------------------------------------------------------------
function choose(s: CombatState, t: number): CombatAction {
  if (s.zombie.charging) return { type: 'defend' };
  const heal = usableItems(s).find((id) => id === 'medicine' || id === 'medkit');
  if (s.player.health < s.player.maxHealth * 0.3 && heal) return { type: 'use_item', itemId: heal };
  if (t === 2 && s.player.firearm) return { type: 'shoot' };
  if (t === 3) return { type: 'use_item', itemId: 'adrenaline' };
  if (t % 5 === 4 && canShoot(s)) return { type: 'shoot' };
  if (t === 9) return { type: 'flee' };
  if (t % 6 === 5) return { type: 'defend' };
  if (s.player.stamina >= 15 && s.zombie.health > 12) return { type: 'heavy' };
  return { type: 'attack' };
}
const novato = createPlayer('p', 'Novato', 0);
const gunner: PlayerState = (() => {
  let p: PlayerState = { ...createPlayer('g', 'Pistolera', 0), level: 4, health: 120, stamina: 90.5, factionId: 'resistencia', inventory: { pistol: 1, ammo: 5, medicine: 2, pipe: 1, ration: 1, leather_jacket: 1 } };
  p = equipItem(p, 'pipe')!;
  p = equipItem(p, 'pistol')!;
  p = equipItem(p, 'leather_jacket')!;
  return p;
})();
const vet: PlayerState = (() => {
  let p: PlayerState = { ...createPlayer('v', 'Vet', 0), level: 6, health: 77.25, stamina: 33, factionId: 'nomades', inventory: { machete: 1, medicine: 2, medkit: 1, scrap_vest: 1, food: 3 } };
  p = equipItem(p, 'machete')!;
  p = equipItem(p, 'scrap_vest')!;
  return p;
})();
const players = { novato, gunner, vet };
out.combat = Object.entries(players).flatMap(([pname, player]) =>
  ZOMBIE_TYPES.flatMap((z) => [0, 1, 2, 3].map((i) => {
    const rng = createRng(`${z}:${pname}:${i}`);
    let s = startCombat({ spawnId: `sp${i}`, zombieType: z, player, rng });
    const start = { zombie: s.zombie, player: s.player, available: s.available, xpMultiplier: s.xpMultiplier };
    const actions: CombatAction[] = [];
    for (let t = 0; t < 60 && s.status === 'ongoing'; t++) {
      const a = choose(s, t);
      actions.push(a);
      s = resolveTurn(s, a, rng);
    }
    const reward = s.status === 'won' ? combatReward(s, createRng(`reward:${z}:${i}`)) : null;
    return {
      player: pname, zombie: z, seed: i, start, actions, log: s.log, texts: s.log.map((e) => describeEvent(e, s)),
      final: { status: s.status, turn: s.turn, zombie: s.zombie, player: s.player, consumed: s.consumed }, reward,
    };
  })),
);

// --- Jugador (forma JSON de la partida) ----------------------------------------
out.player = (() => {
  const steps: unknown[] = [];
  let p: PlayerState = { ...createPlayer('p1', 'Ana', NOW), factionId: 'nomades', stamina: 10, health: 30 };
  steps.push(p);
  p = applyRegen(p, NOW + 37 * 60_000 + 12_345, GAME_CONFIG.regen); steps.push(p);
  p = grantXp(p, 95).player; steps.push(p);
  p = giveItems(p, { machete: 1, metal: 5, ammo: 200 }).player; steps.push(p);
  p = equipItem(p, 'machete')!; steps.push(p);
  p = consumeItem(p, 'food')!; steps.push(p);
  p = applyDeathPenalty(p, GAME_CONFIG.death).player; steps.push(p);
  p = restAtShelter(p, 3, NOW + 3_600_000).player; steps.push(p);
  p = takeItems(p, { machete: 1 })!; steps.push(p);
  p = { ...p, stats: { ...p.stats, zombiesKilled: { walker: 3, brute: 1 }, distanceWalkedM: 1234.56 } };
  p = applyRegen(p, NOW + 9 * 3_600_000, GAME_CONFIG.regen); steps.push(p);
  return steps;
})();

// --- Refugios -------------------------------------------------------------------
out.shelter = (() => {
  const base: Shelter = { id: 'sh1', name: 'Refugio', ownerId: 'p1', ownerName: 'Ana', factionId: 'guardia', level: 1, position: { lat: -34.6, lng: -58.38 }, progress: {}, contributions: [], createdAt: NOW };
  const steps: unknown[] = [];
  let s = base;
  const donations: [string, string, Record<string, number>][] = [
    ['p1', 'Ana', { wood: 10, food: 3 }], ['p2', 'Beto', { wood: 15.7, metal: 2 }], ['p3', 'Caro', { metal: 2 }],
    ['p2', 'Beto R.', { metal: 2 }], ['p3', 'Caro', { metal: 1, wood: 30, food: 10 }], ['p1', 'Ana', { metal: 30, food: 20 }],
  ];
  for (const [id, name, offered] of donations) {
    const r = applyDonation(s, id, name, offered as never);
    steps.push({ offered, outcome: { accepted: r.accepted, acceptedTotal: r.acceptedTotal, leveledUp: r.leveledUp, progress: upgradeProgress(r.shelter) }, shelter: r.shelter });
    s = r.shelter;
  }
  const rng = createRng('horda');
  const hordes = [1, 2, 3, 4, 5].map((level) => {
    const attack = planHordeAttack({ id: 'sh', level }, NOW, rng);
    const outcome = resolveHordeAttack({ level }, attack, level * 3, rng);
    return { level, attack, outcome };
  });
  return { steps, hordes };
})();

// --- Geo, privacidad y suavizado ------------------------------------------------
const pts = [OBELISCO, { lat: -34.6083, lng: -58.3712 }, { lat: 40.4168, lng: -3.7038 }, { lat: 0.0001, lng: 179.9999 }, { lat: -0.5, lng: -179.99 }];
out.geo = {
  haversine: pts.map((a) => pts.map((b) => haversineM(a, b))),
  bearing: pts.map((a) => pts.map((b) => bearingDeg(a, b))),
  offset: pts.map((p) => [offsetM(p, 123.4, -567.8), offsetM(p, -1000, 2500)]),
  normalizeLng: [-540, -180.0001, -180, 0, 179.9999, 180, 181.5, 359.123456789, 1000.25].map((x) => [x, normalizeLng(x)]),
  formatDistance: [0, 35.4, 999.4, 999.6, 1000, 1234, 1250, 1349.99, 12345.678].map((m) => [m, formatDistance(m)]),
  snap: (() => {
    const a = offsetM(OBELISCO, 0, -100);
    const b = offsetM(OBELISCO, 0, 100);
    const r = snapToSegments(offsetM(OBELISCO, 30, 10), [[a, b]], 50);
    return r;
  })(),
};
out.privacy = {
  fuzz: pts.flatMap((p) => ['jugador-1', 'otro'].flatMap((salt) => [250, 100].map((g) => ({ p, salt, gridM: g, out: fuzzPosition(p, salt, g) })))),
  labels: [10, 149.9, 150, 342, 351, 999, 1000, 1249, 1250, 3333].map((m) => [m, approximateDistanceLabel(m)]),
};
out.smoothing = (() => {
  const s = new GpsSmoother();
  const reads: [typeof OBELISCO, number, number][] = [
    [OBELISCO, 5, 0], [offsetM(OBELISCO, 60, 0), 100, 1000], [offsetM(OBELISCO, 5, 5), 8, 3000], [offsetM(OBELISCO, 10, 10), 0.5, 3000], [offsetM(OBELISCO, 30, -4), 12, 9000],
  ];
  return reads.map(([p, acc, t]) => ({ input: { p, acc, t }, out: s.process(p, acc, t) }));
})();

console.log(JSON.stringify(out));
