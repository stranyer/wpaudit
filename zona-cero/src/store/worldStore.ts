import { create } from 'zustand';
import { GAME_CONFIG } from '../config/gameConfig';
import { cellId, cellOf } from '../core/geo';
import { placePoint, type PlacementData } from '../core/placement';
import { filterSafeZones, generateWorld } from '../core/spawns';
import type { LatLng, Shelter, Spawn, Zone } from '../core/types';

export interface ViewBounds {
  south: number;
  west: number;
  north: number;
  east: number;
}

interface WorldState {
  /** Celda central usada para generar el mundo. */
  centerCellId: string | null;
  spawns: Spawn[];
  zones: Zone[];
  shelters: Shelter[];
  /** Hay datos del mapa para ubicar spawns en calles (si no, se muestran sin ajustar). */
  placementAvailable: boolean;
  selectedId: string | null;
  generatedAt: number;

  regenerate(center: LatLng, now: number, depleted: Record<string, number>): void;
  applyPlacement(data: PlacementData, view: ViewBounds): void;
  setShelters(shelters: Shelter[]): void;
  upsertShelter(shelter: Shelter): void;
  removeSpawn(id: string): void;
  select(id: string | null): void;
}

// Resultados de ubicación ya calculados: se conservan entre regeneraciones.
const placed = new Map<string, LatLng>();
const discarded = new Set<string>();

const SPAWN_CFG = {
  worldSeed: GAME_CONFIG.worldSeed,
  zombieWindowMs: GAME_CONFIG.zombieWindowMs,
  supplyWindowMs: GAME_CONFIG.supplyWindowMs,
  infestedCellChance: GAME_CONFIG.infestedCellChance,
};

function inView(p: LatLng, v: ViewBounds): boolean {
  return p.lat >= v.south && p.lat <= v.north && p.lng >= v.west && p.lng <= v.east;
}

function cleanup(spawns: Spawn[], shelters: Shelter[], depleted: Record<string, number>, now: number): Spawn[] {
  const alive = spawns.filter((s) => s.expiresAt > now && depleted[s.id] === undefined && !discarded.has(s.id));
  return filterSafeZones(
    alive,
    shelters.map((s) => s.position),
    GAME_CONFIG.shelterSafeRadiusM,
  );
}

export const useWorldStore = create<WorldState>((set, get) => ({
  centerCellId: null,
  spawns: [],
  zones: [],
  shelters: [],
  placementAvailable: false,
  selectedId: null,
  generatedAt: 0,

  regenerate: (center, now, depleted) => {
    const world = generateWorld(center, GAME_CONFIG.spawnRadiusCells, now, SPAWN_CFG);
    const spawns = world.spawns.map((s): Spawn => {
      const pos = placed.get(s.id);
      return pos ? { ...s, position: pos, placement: 'snapped' } : s;
    });
    // Evita que los cachés crezcan sin límite en sesiones largas.
    if (placed.size > 5000) placed.clear();
    if (discarded.size > 5000) discarded.clear();
    const next = cleanup(spawns, get().shelters, depleted, now);
    // La selección se mantiene solo si el objetivo sigue existiendo.
    const sel = get().selectedId;
    const stillThere = sel !== null && (next.some((s) => s.id === sel) || get().shelters.some((s) => s.id === sel));
    set({
      centerCellId: cellId(cellOf(center)),
      spawns: next,
      zones: world.zones,
      generatedAt: now,
      selectedId: stillThere ? sel : null,
    });
  },

  applyPlacement: (data, view) => {
    let changed = false;
    const spawns: Spawn[] = [];
    for (const s of get().spawns) {
      if (s.placement === 'snapped' || !inView(s.position, view)) {
        spawns.push(s);
        continue;
      }
      changed = true;
      const pos = placePoint(s.position, data, GAME_CONFIG.snapMaxDistanceM);
      if (pos) {
        placed.set(s.id, pos);
        spawns.push({ ...s, position: pos, placement: 'snapped' });
      } else {
        discarded.add(s.id);
      }
    }
    if (changed || !get().placementAvailable) {
      set({
        spawns: filterSafeZones(
          spawns,
          get().shelters.map((sh) => sh.position),
          GAME_CONFIG.shelterSafeRadiusM,
        ),
        placementAvailable: true,
      });
    }
  },

  setShelters: (shelters) => {
    set({
      shelters,
      spawns: filterSafeZones(
        get().spawns,
        shelters.map((s) => s.position),
        GAME_CONFIG.shelterSafeRadiusM,
      ),
    });
  },

  upsertShelter: (shelter) => {
    const others = get().shelters.filter((s) => s.id !== shelter.id);
    get().setShelters([...others, shelter]);
  },

  removeSpawn: (id) =>
    set({ spawns: get().spawns.filter((s) => s.id !== id), selectedId: get().selectedId === id ? null : get().selectedId }),

  select: (id) => set({ selectedId: id }),
}));

/** Spawns visibles: si hay datos de mapa, solo los ya ubicados en calles. */
export function visibleSpawns(spawns: Spawn[], placementAvailable: boolean): Spawn[] {
  return placementAvailable ? spawns.filter((s) => s.placement === 'snapped') : spawns;
}
