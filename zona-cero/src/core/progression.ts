// Progresión: experiencia, niveles y atributos derivados.

export const MAX_LEVEL = 40;

/** XP necesaria para pasar del nivel `level` al siguiente. */
export function xpToNext(level: number): number {
  return Math.round(80 + 60 * Math.pow(level - 1, 1.3));
}

export function maxHealthForLevel(level: number): number {
  return 100 + 8 * (level - 1);
}

export function maxStaminaForLevel(level: number): number {
  return 100 + 4 * (level - 1);
}

export interface XpResult {
  level: number;
  xp: number;
  levelsGained: number;
}

/** Suma XP y resuelve las subidas de nivel (la XP guardada es la del nivel actual). */
export function addXp(level: number, xp: number, amount: number): XpResult {
  let lvl = level;
  let cur = xp + Math.max(0, Math.round(amount));
  let gained = 0;
  while (lvl < MAX_LEVEL && cur >= xpToNext(lvl)) {
    cur -= xpToNext(lvl);
    lvl++;
    gained++;
  }
  if (lvl >= MAX_LEVEL) cur = Math.min(cur, xpToNext(MAX_LEVEL));
  return { level: lvl, xp: cur, levelsGained: gained };
}

/** Título de rango según nivel. */
export function rankTitle(level: number): string {
  if (level >= 30) return 'Leyenda de la Zona';
  if (level >= 20) return 'Comandante';
  if (level >= 12) return 'Veterano';
  if (level >= 7) return 'Saqueador';
  if (level >= 3) return 'Sobreviviente';
  return 'Novato';
}
