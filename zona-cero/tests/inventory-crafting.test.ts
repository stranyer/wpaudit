import { describe, expect, it } from 'vitest';
import { checkRecipe, craft, RECIPES } from '../src/core/crafting';
import { addItems, carriedWeight, hasItems, removeItems } from '../src/core/inventory';
import { rollLoot, rollSupplyLoot } from '../src/core/loot';
import { createRng } from '../src/core/rng';
import { SUPPLIES } from '../src/core/supplies';

const recipe = (id: string) => RECIPES.find((r) => r.id === id)!;

describe('inventario', () => {
  it('agrega respetando la capacidad y reporta el excedente', () => {
    const r = addItems({ wood: 8 }, { wood: 5, metal: 3, machete: 1 }, 10);
    expect(r.inventory.wood).toBe(10);
    expect(r.overflow).toEqual({ wood: 3, metal: 3 });
    // El equipo no pesa: siempre entra.
    expect(r.inventory.machete).toBe(1);
    expect(carriedWeight(r.inventory)).toBe(10);
  });

  it('quita objetos solo si alcanzan', () => {
    expect(removeItems({ food: 1 }, { food: 2 })).toBeNull();
    expect(removeItems({ food: 2, water: 1 }, { food: 2 })).toEqual({ water: 1 });
    expect(hasItems({ food: 2 }, { food: 2 })).toBe(true);
  });
});

describe('fabricación', () => {
  it('fabrica consumiendo insumos', () => {
    const r = craft({ wood: 3, metal: 3 }, recipe('nail_bat'), 0);
    expect(r).not.toBeNull();
    expect(r!.inventory).toEqual({ metal: 1, nail_bat: 1 });
  });

  it('bloquea recetas por nivel de refugio, faltantes o equipo repetido', () => {
    expect(checkRecipe({ medicine: 5, water: 5 }, recipe('medkit'), 2).block).toBe('shelter_level');
    expect(checkRecipe({ medicine: 1 }, recipe('medkit'), 3)).toMatchObject({ block: 'missing_items', missing: { medicine: 2, water: 1 } });
    expect(checkRecipe({ wood: 9, metal: 9, nail_bat: 1 }, recipe('nail_bat'), 0).block).toBe('already_owned');
  });
});

describe('botín', () => {
  it('es determinístico con la misma semilla', () => {
    const a = rollLoot(SUPPLIES.car.loot, createRng('x'));
    const b = rollLoot(SUPPLIES.car.loot, createRng('x'));
    expect(a).toEqual(b);
  });

  it('un suministro nunca devuelve botín vacío', () => {
    for (let i = 0; i < 300; i++) {
      const loot = rollSupplyLoot(SUPPLIES.backpack, createRng(i));
      expect(Object.keys(loot).length).toBeGreaterThan(0);
    }
  });
});
