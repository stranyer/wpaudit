import { mergeInventory } from './inventory';
import type { Rng } from './rng';
import type { Inventory, LootEntry, SupplyDef } from './types';

/** Escala una cantidad con redondeo probabilístico (1,15 x 3 = 3 o 4). */
function scaleQty(qty: number, multiplier: number, rng: Rng): number {
  const scaled = qty * multiplier;
  const base = Math.floor(scaled);
  return Math.max(1, base + (rng.chance(scaled - base) ? 1 : 0));
}

/** Tira cada entrada de la tabla de forma independiente. */
export function rollLoot(entries: LootEntry[], rng: Rng, multiplier = 1): Inventory {
  const out: Inventory = {};
  for (const e of entries) {
    if (!rng.chance(e.chance)) continue;
    const qty = scaleQty(rng.int(e.min, e.max), multiplier, rng);
    out[e.itemId] = (out[e.itemId] ?? 0) + qty;
  }
  return out;
}

/**
 * Botín de un punto de suministros: varias pasadas por la tabla y, si no salió
 * nada, garantiza al menos la entrada más probable (nunca vuelve vacío).
 */
export function rollSupplyLoot(def: SupplyDef, rng: Rng, multiplier = 1): Inventory {
  let out: Inventory = {};
  const passes = rng.int(def.rolls[0], def.rolls[1]);
  for (let i = 0; i < passes; i++) {
    out = mergeInventory(out, rollLoot(def.loot, rng, multiplier));
  }
  if (Object.keys(out).length === 0) {
    const fallback = rng.weighted(def.loot, (e) => e.chance);
    out[fallback.itemId] = fallback.min;
  }
  return out;
}
