import { create } from 'zustand';
import { createJSONStorage, persist } from 'zustand/middleware';
import type { CombatState, Inventory, LatLng, PlayerState, Reward, ZombieSpawn } from '../core/types';
import type { LocationMode } from './locationStore';

export interface CombatOutcome {
  status: 'won' | 'lost' | 'fled';
  reward: Reward | null;
  /** Lo que entró efectivamente a la mochila. */
  added: Inventory;
  overflow: Inventory;
  lost: Inventory;
  levelsGained: number;
}

interface GameState {
  ready: boolean;
  backend: 'local' | 'supabase';
  player: PlayerState | null;

  combat: CombatState | null;
  combatSpawn: ZombieSpawn | null;
  combatOutcome: CombatOutcome | null;

  // --- Persistido localmente (no viaja al servidor) ---
  /** Spawns agotados por este jugador: id -> vencimiento (ms). */
  depleted: Record<string, number>;
  /** Celdas exploradas (para el bonus de exploración). */
  explored: Record<string, true>;
  /** Metros acumulados que todavía no sumaron XP. */
  walkBuffer: number;
  lastMode: LocationMode | null;
  demoPosition: LatLng | null;

  set(partial: Partial<Omit<GameState, 'set' | 'updatePlayer'>>): void;
  updatePlayer(fn: (p: PlayerState) => PlayerState): void;
}

export const useGameStore = create<GameState>()(
  persist(
    (set, get) => ({
      ready: false,
      backend: 'local',
      player: null,
      combat: null,
      combatSpawn: null,
      combatOutcome: null,
      depleted: {},
      explored: {},
      walkBuffer: 0,
      lastMode: null,
      demoPosition: null,
      set: (partial) => set(partial),
      updatePlayer: (fn) => {
        const p = get().player;
        if (p) set({ player: fn(p) });
      },
    }),
    {
      name: 'zc:session',
      version: 1,
      storage: createJSONStorage(() => localStorage),
      // Solo datos de sesión local. La ubicación GPS real nunca se guarda: solo la de demo.
      partialize: (s) => ({
        depleted: s.depleted,
        explored: s.explored,
        walkBuffer: s.walkBuffer,
        lastMode: s.lastMode,
        demoPosition: s.demoPosition,
      }),
    },
  ),
);
