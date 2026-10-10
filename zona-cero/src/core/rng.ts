// Generador pseudoaleatorio determinístico (mulberry32) con semilla de texto.
// La misma semilla produce la misma secuencia en cualquier cliente o servidor,
// lo que permite que todos los jugadores vean el mismo mundo.

export interface Rng {
  /** Número en [0, 1). */
  next(): number;
  /** Entero en [min, max] (ambos incluidos). */
  int(min: number, max: number): number;
  /** Real en [min, max). */
  range(min: number, max: number): number;
  chance(p: number): boolean;
  pick<T>(items: readonly T[]): T;
  weighted<T>(items: readonly T[], weight: (item: T) => number): T;
}

/** Hash FNV-1a de 32 bits. */
export function hashString(input: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

export function createRng(seed: number | string): Rng {
  let state = typeof seed === 'string' ? hashString(seed) : seed >>> 0;
  const next = (): number => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const rng: Rng = {
    next,
    int: (min, max) => min + Math.floor(next() * (max - min + 1)),
    range: (min, max) => min + next() * (max - min),
    chance: (p) => next() < p,
    pick: (items) => items[Math.floor(next() * items.length)],
    weighted: (items, weight) => {
      const total = items.reduce((acc, it) => acc + Math.max(0, weight(it)), 0);
      let roll = next() * total;
      for (const it of items) {
        roll -= Math.max(0, weight(it));
        if (roll < 0) return it;
      }
      return items[items.length - 1];
    },
  };
  return rng;
}

/** RNG no determinístico para tiradas de combate/botín locales. */
export function randomRng(): Rng {
  return createRng((Math.random() * 2 ** 32) >>> 0);
}
