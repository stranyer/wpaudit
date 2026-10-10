import type { ZombieDef, ZombieTypeId } from './types';

export const ZOMBIES: Record<ZombieTypeId, ZombieDef> = {
  walker: {
    id: 'walker',
    name: 'Caminante',
    description: 'Lento y torpe, pero nunca se cansa.',
    baseHealth: 30,
    damage: [5, 9],
    accuracy: 0.68,
    evasion: 0.05,
    fleeChance: 0.85,
    xp: 20,
    ability: 'none',
    recommendedLevel: 1,
    spawnWeight: 50,
    loot: [
      { itemId: 'food', chance: 0.45, min: 1, max: 2 },
      { itemId: 'water', chance: 0.35, min: 1, max: 2 },
      { itemId: 'metal', chance: 0.3, min: 1, max: 2 },
      { itemId: 'ammo', chance: 0.12, min: 1, max: 2 },
      { itemId: 'leather_jacket', chance: 0.03, min: 1, max: 1 },
    ],
  },
  runner: {
    id: 'runner',
    name: 'Corredor',
    description: 'Infectado reciente. Rápido y a veces ataca dos veces.',
    baseHealth: 24,
    damage: [5, 8],
    accuracy: 0.8,
    evasion: 0.15,
    fleeChance: 0.45,
    xp: 30,
    ability: 'double_strike',
    recommendedLevel: 2,
    spawnWeight: 22,
    loot: [
      { itemId: 'water', chance: 0.4, min: 1, max: 2 },
      { itemId: 'medicine', chance: 0.25, min: 1, max: 1 },
      { itemId: 'ammo', chance: 0.2, min: 1, max: 3 },
      { itemId: 'pipe', chance: 0.05, min: 1, max: 1 },
    ],
  },
  bloater: {
    id: 'bloater',
    name: 'Hinchado',
    description: 'Lleno de gases tóxicos. Explota al morir: mejor rematarlo a distancia.',
    baseHealth: 50,
    damage: [6, 11],
    accuracy: 0.6,
    evasion: 0,
    fleeChance: 0.9,
    xp: 40,
    ability: 'toxic_burst',
    recommendedLevel: 3,
    spawnWeight: 12,
    loot: [
      { itemId: 'medicine', chance: 0.45, min: 1, max: 2 },
      { itemId: 'food', chance: 0.4, min: 1, max: 3 },
      { itemId: 'adrenaline', chance: 0.04, min: 1, max: 1 },
    ],
  },
  screamer: {
    id: 'screamer',
    name: 'Chillón',
    description: 'Sus alaridos atraen a otros infectados que lo protegen.',
    baseHealth: 28,
    damage: [4, 8],
    accuracy: 0.7,
    evasion: 0.1,
    fleeChance: 0.6,
    xp: 35,
    ability: 'call_horde',
    recommendedLevel: 3,
    spawnWeight: 11,
    loot: [
      { itemId: 'ammo', chance: 0.35, min: 1, max: 3 },
      { itemId: 'metal', chance: 0.4, min: 1, max: 3 },
      { itemId: 'medicine', chance: 0.2, min: 1, max: 1 },
      { itemId: 'nail_bat', chance: 0.05, min: 1, max: 1 },
    ],
  },
  brute: {
    id: 'brute',
    name: 'Bruto',
    description: 'Una montaña de carne. Prepara embestidas: defendete en el momento justo.',
    baseHealth: 110,
    damage: [12, 18],
    accuracy: 0.72,
    evasion: 0,
    fleeChance: 0.7,
    xp: 75,
    ability: 'charge',
    recommendedLevel: 5,
    spawnWeight: 5,
    loot: [
      { itemId: 'metal', chance: 0.7, min: 2, max: 5 },
      { itemId: 'ammo', chance: 0.5, min: 2, max: 5 },
      { itemId: 'medkit', chance: 0.25, min: 1, max: 1 },
      { itemId: 'fire_axe', chance: 0.06, min: 1, max: 1 },
      { itemId: 'riot_armor', chance: 0.04, min: 1, max: 1 },
      { itemId: 'shotgun', chance: 0.02, min: 1, max: 1 },
    ],
  },
};

export const ZOMBIE_TYPES = Object.keys(ZOMBIES) as ZombieTypeId[];

/** Escala de un zombie según su nivel. */
export function zombieHealthForLevel(def: ZombieDef, level: number): number {
  return Math.round(def.baseHealth * (1 + 0.12 * (level - 1)));
}

export function zombieDamageForLevel(def: ZombieDef, level: number): [number, number] {
  const k = 1 + 0.08 * (level - 1);
  return [Math.round(def.damage[0] * k), Math.round(def.damage[1] * k)];
}

/** Nivel de amenaza relativo al jugador: 0 = fácil, 1 = parejo, 2 = peligroso, 3 = mortal. */
export function threatRating(def: ZombieDef, playerLevel: number): 0 | 1 | 2 | 3 {
  const diff = def.recommendedLevel - playerLevel;
  if (diff <= -2) return 0;
  if (diff <= 0) return 1;
  if (diff <= 2) return 2;
  return 3;
}
