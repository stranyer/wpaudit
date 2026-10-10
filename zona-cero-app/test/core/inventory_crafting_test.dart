import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';

Recipe recipe(String id) => recipeById(id)!;

void main() {
  group('inventario', () {
    test('agrega respetando la capacidad y reporta el excedente', () {
      final r = addItems(
        {ItemId.wood: 8},
        {ItemId.wood: 5, ItemId.metal: 3, ItemId.machete: 1},
        capacity: 10,
      );
      expect(r.inventory[ItemId.wood], 10);
      expect(r.overflow, {ItemId.wood: 3, ItemId.metal: 3});
      // El equipo no pesa: siempre entra.
      expect(r.inventory[ItemId.machete], 1);
      expect(carriedWeight(r.inventory), 10);
    });

    test('quita objetos solo si alcanzan', () {
      expect(removeItems({ItemId.food: 1}, {ItemId.food: 2}), isNull);
      expect(removeItems({ItemId.food: 2, ItemId.water: 1}, {ItemId.food: 2}), {ItemId.water: 1});
      expect(hasItems({ItemId.food: 2}, {ItemId.food: 2}), isTrue);
    });

    test('helpers básicos (countOf, merge, missing, isInventoryEmpty, entries)', () {
      const inv = {ItemId.food: 2, ItemId.ammo: 0};
      expect(countOf(inv, ItemId.food), 2);
      expect(countOf(inv, ItemId.water), 0);
      expect(entries(inv).map((e) => e.key), [ItemId.food]);
      expect(mergeInventory(inv, {ItemId.food: 1, ItemId.wood: 3}), {ItemId.food: 3, ItemId.ammo: 0, ItemId.wood: 3});
      expect(missingItems(inv, {ItemId.food: 5, ItemId.water: 1}), {ItemId.food: 3, ItemId.water: 1});
      expect(isInventoryEmpty({ItemId.ammo: 0}), isTrue);
      expect(isInventoryEmpty(inv), isFalse);
      expect(carryCapacity(1), 80);
      expect(carryCapacity(5), 120);
    });
  });

  group('fabricación', () {
    test('fabrica consumiendo insumos', () {
      final r = craft({ItemId.wood: 3, ItemId.metal: 3}, recipe('nail_bat'), 0);
      expect(r, isNotNull);
      expect(r!.inventory, {ItemId.metal: 1, ItemId.nailBat: 1});
    });

    test('bloquea recetas por nivel de refugio, faltantes o equipo repetido', () {
      expect(checkRecipe({ItemId.medicine: 5, ItemId.water: 5}, recipe('medkit'), 2).block, CraftBlock.shelterLevel);
      final missing = checkRecipe({ItemId.medicine: 1}, recipe('medkit'), 3);
      expect(missing.block, CraftBlock.missingItems);
      expect(missing.missing, {ItemId.medicine: 2, ItemId.water: 1});
      expect(
        checkRecipe({ItemId.wood: 9, ItemId.metal: 9, ItemId.nailBat: 1}, recipe('nail_bat'), 0).block,
        CraftBlock.alreadyOwned,
      );
    });

    test('nombre de receta con cantidad', () {
      expect(recipeName(recipe('ammo')), 'Munición x2');
      expect(recipeName(recipe('machete')), 'Machete');
    });
  });

  group('botín', () {
    test('es determinístico con la misma semilla', () {
      final a = rollLoot(supplyDefs[SupplyTypeId.car]!.loot, createRng('x'));
      final b = rollLoot(supplyDefs[SupplyTypeId.car]!.loot, createRng('x'));
      expect(a, b);
    });

    test('un suministro nunca devuelve botín vacío', () {
      for (var i = 0; i < 300; i++) {
        final loot = rollSupplyLoot(supplyDefs[SupplyTypeId.backpack]!, createRng(i));
        expect(loot.keys, isNotEmpty);
      }
    });
  });
}
