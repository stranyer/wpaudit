// Constantes de balance usadas por el motor (sin dependencias de entorno).

/** Costos de resistencia por acción. */
export const GAME_STAMINA = {
  attack: 6,
  heavy: 16,
  shoot: 2,
} as const;

/** Multiplicador de daño del golpe fuerte. */
export const HEAVY_MULTIPLIER = 1.7;
