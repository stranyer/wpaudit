import { cellBounds, cellId, cellsAround, haversineM, type CellCoord } from './geo';
import { createRng } from './rng';
import { SUPPLIES, SUPPLY_TYPES } from './supplies';
import { ZOMBIES, ZOMBIE_TYPES } from './zombies';
import type { LatLng, Spawn, SupplySpawn, Zone, ZoneThreat, ZombieSpawn } from './types';

// Generación determinística del mundo.
// Cada celda de la grilla produce sus spawns a partir de (semilla, celda, ventana de tiempo),
// así que todos los jugadores ven lo mismo sin necesidad de un servidor, y un backend
// puede regenerar exactamente los mismos spawns para validar interacciones.

export interface SpawnConfig {
  worldSeed: string;
  zombieWindowMs: number;
  supplyWindowMs: number;
  infestedCellChance: number;
}

/** Las zonas infestadas rotan cada 6 horas. */
const THREAT_WINDOW_MS = 6 * 60 * 60 * 1000;

export function cellThreat(cell: CellCoord, now: number, cfg: SpawnConfig): ZoneThreat {
  const w = Math.floor(now / THREAT_WINDOW_MS);
  const rng = createRng(`${cfg.worldSeed}:threat:${cellId(cell)}:${w}`);
  return rng.chance(cfg.infestedCellChance) ? 'infested' : 'calm';
}

/** Punto aleatorio dentro de la celda, dejando un margen del 8% en los bordes. */
function pointInCell(cell: CellCoord, rng: ReturnType<typeof createRng>): LatLng {
  const [sw, ne] = cellBounds(cell);
  const m = 0.08;
  return {
    lat: sw.lat + (ne.lat - sw.lat) * rng.range(m, 1 - m),
    lng: sw.lng + (ne.lng - sw.lng) * rng.range(m, 1 - m),
  };
}

export function generateCellSpawns(cell: CellCoord, now: number, cfg: SpawnConfig): Spawn[] {
  const id = cellId(cell);
  const threat = cellThreat(cell, now, cfg);
  const infested = threat === 'infested';
  const out: Spawn[] = [];

  // Zombies: rotan rápido (deambulan).
  const zw = Math.floor(now / cfg.zombieWindowMs);
  const zr = createRng(`${cfg.worldSeed}:z:${id}:${zw}`);
  const zCount = infested ? zr.int(2, 4) : zr.int(0, 2);
  for (let i = 0; i < zCount; i++) {
    const type = zr.weighted(ZOMBIE_TYPES, (t) => {
      const w = ZOMBIES[t].spawnWeight;
      return infested && (t === 'runner' || t === 'brute' || t === 'screamer') ? w * 2 : w;
    });
    const z: ZombieSpawn = {
      kind: 'zombie',
      id: `z:${id}:${zw}:${i}`,
      cellId: id,
      position: pointInCell(cell, zr),
      zombieType: type,
      expiresAt: (zw + 1) * cfg.zombieWindowMs,
      placement: 'raw',
    };
    out.push(z);
  }

  // Suministros: duran más.
  const sw = Math.floor(now / cfg.supplyWindowMs);
  const sr = createRng(`${cfg.worldSeed}:s:${id}:${sw}`);
  const sCount = sr.int(1, 3) + (infested ? 1 : 0);
  for (let i = 0; i < sCount; i++) {
    const type = sr.weighted(SUPPLY_TYPES, (t) => {
      if (t === 'military') return infested ? SUPPLIES[t].spawnWeight * 4 : 0;
      return SUPPLIES[t].spawnWeight;
    });
    const s: SupplySpawn = {
      kind: 'supply',
      id: `s:${id}:${sw}:${i}`,
      cellId: id,
      position: pointInCell(cell, sr),
      supplyType: type,
      expiresAt: (sw + 1) * cfg.supplyWindowMs,
      placement: 'raw',
    };
    out.push(s);
  }
  return out;
}

export interface WorldSnapshot {
  spawns: Spawn[];
  zones: Zone[];
}

export function generateWorld(center: LatLng, radiusCells: number, now: number, cfg: SpawnConfig): WorldSnapshot {
  const spawns: Spawn[] = [];
  const zones: Zone[] = [];
  for (const cell of cellsAround(center, radiusCells)) {
    spawns.push(...generateCellSpawns(cell, now, cfg));
    zones.push({ cellId: cellId(cell), threat: cellThreat(cell, now, cfg), bounds: cellBounds(cell) });
  }
  return { spawns, zones };
}

/** Quita zombies dentro del radio seguro de los refugios. */
export function filterSafeZones(spawns: Spawn[], shelters: LatLng[], safeRadiusM: number): Spawn[] {
  if (shelters.length === 0) return spawns;
  return spawns.filter(
    (s) => s.kind !== 'zombie' || shelters.every((p) => haversineM(p, s.position) > safeRadiusM),
  );
}

/** Siguiente cambio de ventana: cuándo conviene regenerar el mundo. */
export function nextWindowChange(now: number, cfg: SpawnConfig): number {
  const nz = (Math.floor(now / cfg.zombieWindowMs) + 1) * cfg.zombieWindowMs;
  const ns = (Math.floor(now / cfg.supplyWindowMs) + 1) * cfg.supplyWindowMs;
  return Math.min(nz, ns);
}
