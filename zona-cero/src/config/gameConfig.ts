import type { LatLng } from '../core/types';

// Configuración de juego y balance. Todo lo ajustable vive acá.

const env = import.meta.env;

function numberFromEnv(value: string | undefined, fallback: number): number {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

export const GAME_CONFIG = {
  /** Semilla compartida del mundo: misma semilla = mismos spawns para todos. */
  worldSeed: (env?.VITE_WORLD_SEED as string | undefined) || 'zona-cero-v1',

  /** Radio (m) dentro del cual se puede interactuar con un punto. */
  interactionRadiusM: numberFromEnv(env?.VITE_INTERACTION_RADIUS_M as string | undefined, 40),
  /** Tolerancia extra por imprecisión del GPS (se suma al radio, con tope). */
  maxAccuracyBonusM: 15,
  /** Por encima de esta precisión (m) no se permiten interacciones. */
  maxAccuracyForInteractionM: 80,

  /** Velocidad máxima (m/s) para interactuar: ~43 km/h. Más rápido = vehículo. */
  maxInteractionSpeedMps: 12,
  /** Tiempo de bloqueo tras detectar velocidad excesiva. */
  speedLockMs: 30_000,

  /** Celdas alrededor del jugador donde se generan spawns (radio en celdas). */
  spawnRadiusCells: 2,
  /** Ventanas de tiempo de los spawns: al cambiar de ventana aparecen nuevos. */
  zombieWindowMs: 10 * 60 * 1000,
  supplyWindowMs: 30 * 60 * 1000,
  /** Distancia máxima para mover un spawn a la calle/sendero más cercano. */
  snapMaxDistanceM: 70,
  /** Radio alrededor de refugios donde no aparecen zombies. */
  shelterSafeRadiusM: 60,
  /** Probabilidad de que una celda sea "zona infestada". */
  infestedCellChance: 0.15,

  /** GPS: filtrado para ahorrar batería y evitar saltos. */
  gps: {
    minMoveM: 3,
    minIntervalMs: 1000,
    maximumAgeMs: 5000,
    timeoutMs: 20000,
    maxAcceptedAccuracyM: 150,
  },

  /** Modo demo. */
  demo: {
    start: { lat: -34.60372, lng: -58.38159 } as LatLng, // Obelisco, Buenos Aires
    walkSpeedMps: 4.5, // un poco más rápido que caminar para que la demo sea ágil
    runMultiplier: 2.2,
  },

  /** Regeneración pasiva. */
  regen: {
    staminaPerMinute: 3,
    healthPerMinute: 1,
    /** La salud solo se regenera sola hasta este porcentaje. */
    healthPassiveCap: 0.5,
  },

  /** XP por acciones de exploración. */
  xp: {
    perCellExplored: 15,
    per250mWalked: 5,
    craft: 8,
    donatePerUnit: 1,
  },

  /** Penalización al caer en combate. */
  death: {
    healthRestoreRatio: 0.3,
    staminaRestore: 20,
    resourceLossRatio: 0.3,
  },

  /** Frecuencia de autoguardado y ticks de juego. */
  tickMs: 5000,
  saveDebounceMs: 1500,
} as const;
