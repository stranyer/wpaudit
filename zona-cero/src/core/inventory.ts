import { ITEMS } from './items';
import type { Inventory, ItemId } from './types';

export function countOf(inv: Inventory, id: ItemId): number {
  return inv[id] ?? 0;
}

export function entries(inv: Inventory): [ItemId, number][] {
  return (Object.entries(inv) as [ItemId, number][]).filter(([, n]) => n > 0);
}

export function mergeInventory(a: Inventory, b: Inventory): Inventory {
  const out: Inventory = { ...a };
  for (const [id, n] of entries(b)) out[id] = (out[id] ?? 0) + n;
  return out;
}

export function hasItems(inv: Inventory, required: Inventory): boolean {
  return entries(required).every(([id, n]) => countOf(inv, id) >= n);
}

/** Lo que falta para cubrir `required` (vacío si alcanza). */
export function missingItems(inv: Inventory, required: Inventory): Inventory {
  const out: Inventory = {};
  for (const [id, n] of entries(required)) {
    const left = n - countOf(inv, id);
    if (left > 0) out[id] = left;
  }
  return out;
}

/** Quita objetos; devuelve null si no alcanzan. */
export function removeItems(inv: Inventory, items: Inventory): Inventory | null {
  if (!hasItems(inv, items)) return null;
  const out: Inventory = { ...inv };
  for (const [id, n] of entries(items)) {
    const left = countOf(out, id) - n;
    if (left > 0) out[id] = left;
    else delete out[id];
  }
  return out;
}

export function carriedWeight(inv: Inventory): number {
  return entries(inv).reduce((acc, [id, n]) => acc + ITEMS[id].weight * n, 0);
}

/** Capacidad de la mochila según nivel. */
export function carryCapacity(level: number): number {
  return 80 + 10 * (level - 1);
}

export interface AddResult {
  inventory: Inventory;
  added: Inventory;
  overflow: Inventory;
}

/**
 * Agrega objetos respetando la capacidad. Los objetos sin peso (equipo) siempre entran.
 * Lo que no entra se informa en `overflow` y se pierde.
 */
export function addItems(inv: Inventory, items: Inventory, capacity = Infinity): AddResult {
  const out: Inventory = { ...inv };
  const added: Inventory = {};
  const overflow: Inventory = {};
  let free = capacity - carriedWeight(inv);
  for (const [id, n] of entries(items)) {
    const w = ITEMS[id].weight;
    const fit = w === 0 ? n : Math.max(0, Math.min(n, Math.floor(free / w)));
    if (fit > 0) {
      out[id] = countOf(out, id) + fit;
      added[id] = fit;
      free -= fit * w;
    }
    if (fit < n) overflow[id] = n - fit;
  }
  return { inventory: out, added, overflow };
}

export function isEmpty(inv: Inventory): boolean {
  return entries(inv).length === 0;
}
