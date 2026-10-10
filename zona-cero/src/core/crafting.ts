import { addItems, countOf, hasItems, missingItems, removeItems } from './inventory';
import { ITEMS, isEquippable } from './items';
import type { Inventory, ItemId } from './types';

export interface Recipe {
  id: string;
  output: ItemId;
  outputQty: number;
  inputs: Inventory;
  /** Nivel de refugio necesario (0 = se puede fabricar en cualquier lado). */
  requiresShelterLevel: number;
}

export const RECIPES: Recipe[] = [
  { id: 'ration', output: 'ration', outputQty: 1, inputs: { food: 2, water: 2 }, requiresShelterLevel: 0 },
  { id: 'nail_bat', output: 'nail_bat', outputQty: 1, inputs: { wood: 3, metal: 2 }, requiresShelterLevel: 0 },
  { id: 'ammo', output: 'ammo', outputQty: 2, inputs: { metal: 3 }, requiresShelterLevel: 2 },
  { id: 'scrap_vest', output: 'scrap_vest', outputQty: 1, inputs: { metal: 6, wood: 2 }, requiresShelterLevel: 2 },
  { id: 'medkit', output: 'medkit', outputQty: 1, inputs: { medicine: 3, water: 1 }, requiresShelterLevel: 3 },
  { id: 'machete', output: 'machete', outputQty: 1, inputs: { metal: 5, wood: 1 }, requiresShelterLevel: 3 },
  { id: 'pistol', output: 'pistol', outputQty: 1, inputs: { metal: 10, wood: 2, ammo: 3 }, requiresShelterLevel: 4 },
];

export type CraftBlock = 'missing_items' | 'shelter_level' | 'already_owned' | 'no_space';

export interface CraftCheck {
  ok: boolean;
  block?: CraftBlock;
  missing: Inventory;
}

export function checkRecipe(inv: Inventory, recipe: Recipe, shelterLevel: number): CraftCheck {
  const missing = missingItems(inv, recipe.inputs);
  if (shelterLevel < recipe.requiresShelterLevel) return { ok: false, block: 'shelter_level', missing };
  // El equipo es único: no tiene sentido fabricar un segundo machete.
  if (isEquippable(recipe.output) && countOf(inv, recipe.output) > 0) {
    return { ok: false, block: 'already_owned', missing };
  }
  if (!hasItems(inv, recipe.inputs)) return { ok: false, block: 'missing_items', missing };
  return { ok: true, missing };
}

export interface CraftResult {
  inventory: Inventory;
  crafted: Inventory;
}

export function craft(inv: Inventory, recipe: Recipe, shelterLevel: number, capacity = Infinity): CraftResult | null {
  if (!checkRecipe(inv, recipe, shelterLevel).ok) return null;
  const afterInputs = removeItems(inv, recipe.inputs);
  if (!afterInputs) return null;
  const { inventory, added, overflow } = addItems(afterInputs, { [recipe.output]: recipe.outputQty }, capacity);
  // Como los insumos pesan al menos lo mismo que el producto, no debería sobrar nada.
  if (Object.keys(overflow).length > 0) return null;
  return { inventory, crafted: added };
}

export function recipeName(recipe: Recipe): string {
  const item = ITEMS[recipe.output];
  return recipe.outputQty > 1 ? `${item.name} x${recipe.outputQty}` : item.name;
}
