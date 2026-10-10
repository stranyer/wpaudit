// Fabricación: recetas y validación.

import 'inventory.dart';
import 'items.dart';
import 'types.dart';

class Recipe {
  const Recipe({
    required this.id,
    required this.output,
    required this.outputQty,
    required this.inputs,
    required this.requiresShelterLevel,
  });

  final String id;
  final ItemId output;
  final int outputQty;
  final Inventory inputs;

  /// Nivel de refugio necesario (0 = se puede fabricar en cualquier lado).
  final int requiresShelterLevel;
}

const List<Recipe> recipes = [
  Recipe(
    id: 'ration',
    output: ItemId.ration,
    outputQty: 1,
    inputs: {ItemId.food: 2, ItemId.water: 2},
    requiresShelterLevel: 0,
  ),
  Recipe(
    id: 'nail_bat',
    output: ItemId.nailBat,
    outputQty: 1,
    inputs: {ItemId.wood: 3, ItemId.metal: 2},
    requiresShelterLevel: 0,
  ),
  Recipe(id: 'ammo', output: ItemId.ammo, outputQty: 2, inputs: {ItemId.metal: 3}, requiresShelterLevel: 2),
  Recipe(
    id: 'scrap_vest',
    output: ItemId.scrapVest,
    outputQty: 1,
    inputs: {ItemId.metal: 6, ItemId.wood: 2},
    requiresShelterLevel: 2,
  ),
  Recipe(
    id: 'medkit',
    output: ItemId.medkit,
    outputQty: 1,
    inputs: {ItemId.medicine: 3, ItemId.water: 1},
    requiresShelterLevel: 3,
  ),
  Recipe(
    id: 'machete',
    output: ItemId.machete,
    outputQty: 1,
    inputs: {ItemId.metal: 5, ItemId.wood: 1},
    requiresShelterLevel: 3,
  ),
  Recipe(
    id: 'pistol',
    output: ItemId.pistol,
    outputQty: 1,
    inputs: {ItemId.metal: 10, ItemId.wood: 2, ItemId.ammo: 3},
    requiresShelterLevel: 4,
  ),
];

/// Busca una receta por su id (`'nail_bat'`, `'medkit'`...).
Recipe? recipeById(String id) {
  for (final r in recipes) {
    if (r.id == id) return r;
  }
  return null;
}

enum CraftBlock implements KeyedEnum {
  missingItems('missing_items'),
  shelterLevel('shelter_level'),
  alreadyOwned('already_owned'),
  noSpace('no_space');

  const CraftBlock(this.key);
  @override
  final String key;

  static final Map<String, CraftBlock> _byKey = {for (final v in values) v.key: v};
  static CraftBlock fromKey(String key) =>
      _byKey[key] ?? (throw ArgumentError.value(key, 'key', 'CraftBlock desconocido'));
  static CraftBlock? tryFromKey(String? key) => key == null ? null : _byKey[key];
}

class CraftCheck {
  const CraftCheck({required this.ok, this.block, required this.missing});
  final bool ok;
  final CraftBlock? block;
  final Inventory missing;
}

CraftCheck checkRecipe(Inventory inv, Recipe recipe, int shelterLevel) {
  final missing = missingItems(inv, recipe.inputs);
  if (shelterLevel < recipe.requiresShelterLevel) {
    return CraftCheck(ok: false, block: CraftBlock.shelterLevel, missing: missing);
  }
  // El equipo es único: no tiene sentido fabricar un segundo machete.
  if (isEquippable(recipe.output) && countOf(inv, recipe.output) > 0) {
    return CraftCheck(ok: false, block: CraftBlock.alreadyOwned, missing: missing);
  }
  if (!hasItems(inv, recipe.inputs)) {
    return CraftCheck(ok: false, block: CraftBlock.missingItems, missing: missing);
  }
  return CraftCheck(ok: true, missing: missing);
}

class CraftResult {
  const CraftResult({required this.inventory, required this.crafted});
  final Inventory inventory;
  final Inventory crafted;
}

CraftResult? craft(Inventory inv, Recipe recipe, int shelterLevel, {num capacity = double.infinity}) {
  if (!checkRecipe(inv, recipe, shelterLevel).ok) return null;
  final afterInputs = removeItems(inv, recipe.inputs);
  if (afterInputs == null) return null;
  final r = addItems(afterInputs, {recipe.output: recipe.outputQty}, capacity: capacity);
  // Como los insumos pesan al menos lo mismo que el producto, no debería sobrar nada.
  if (r.overflow.isNotEmpty) return null;
  return CraftResult(inventory: r.inventory, crafted: r.added);
}

String recipeName(Recipe recipe) {
  final item = itemDefs[recipe.output]!;
  return recipe.outputQty > 1 ? '${item.name} x${recipe.outputQty}' : item.name;
}
