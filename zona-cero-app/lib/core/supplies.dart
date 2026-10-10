// Puntos de suministros: qué se puede encontrar en cada tipo de lugar.

import 'types.dart';

const Map<SupplyTypeId, SupplyDef> supplyDefs = {
  SupplyTypeId.backpack: SupplyDef(
    id: SupplyTypeId.backpack,
    name: 'Mochila abandonada',
    description: 'Alguien huyó con lo puesto. Puede quedar algo útil.',
    rarity: Rarity.common,
    spawnWeight: 30,
    rolls: (min: 1, max: 1),
    staminaCost: 4,
    xp: 10,
    loot: [
      LootEntry(itemId: ItemId.food, chance: 0.5, min: 1, max: 2),
      LootEntry(itemId: ItemId.water, chance: 0.5, min: 1, max: 2),
      LootEntry(itemId: ItemId.medicine, chance: 0.15, min: 1, max: 1),
      LootEntry(itemId: ItemId.ammo, chance: 0.15, min: 1, max: 2),
      LootEntry(itemId: ItemId.wood, chance: 0.2, min: 1, max: 2),
    ],
  ),
  SupplyTypeId.car: SupplyDef(
    id: SupplyTypeId.car,
    name: 'Auto abandonado',
    description: 'Chapa, repuestos y, con suerte, la guantera intacta.',
    rarity: Rarity.common,
    spawnWeight: 24,
    rolls: (min: 1, max: 2),
    staminaCost: 6,
    xp: 12,
    loot: [
      LootEntry(itemId: ItemId.metal, chance: 0.75, min: 2, max: 4),
      LootEntry(itemId: ItemId.water, chance: 0.25, min: 1, max: 1),
      LootEntry(itemId: ItemId.ammo, chance: 0.15, min: 1, max: 3),
      LootEntry(itemId: ItemId.leatherJacket, chance: 0.03, min: 1, max: 1),
    ],
  ),
  SupplyTypeId.debris: SupplyDef(
    id: SupplyTypeId.debris,
    name: 'Escombros',
    description: 'Restos de una barricada caída. Madera y metal.',
    rarity: Rarity.common,
    spawnWeight: 24,
    rolls: (min: 1, max: 1),
    staminaCost: 5,
    xp: 10,
    loot: [
      LootEntry(itemId: ItemId.wood, chance: 0.85, min: 2, max: 4),
      LootEntry(itemId: ItemId.metal, chance: 0.4, min: 1, max: 2),
    ],
  ),
  SupplyTypeId.grocery: SupplyDef(
    id: SupplyTypeId.grocery,
    name: 'Almacén saqueado',
    description: 'Las góndolas están vacías... casi.',
    rarity: Rarity.uncommon,
    spawnWeight: 14,
    rolls: (min: 1, max: 2),
    staminaCost: 6,
    xp: 15,
    loot: [
      LootEntry(itemId: ItemId.food, chance: 0.8, min: 2, max: 4),
      LootEntry(itemId: ItemId.water, chance: 0.6, min: 1, max: 3),
      LootEntry(itemId: ItemId.ration, chance: 0.1, min: 1, max: 1),
    ],
  ),
  SupplyTypeId.pharmacy: SupplyDef(
    id: SupplyTypeId.pharmacy,
    name: 'Farmacia saqueada',
    description: 'Cajones revueltos y estantes rotos.',
    rarity: Rarity.uncommon,
    spawnWeight: 11,
    rolls: (min: 1, max: 2),
    staminaCost: 6,
    xp: 18,
    loot: [
      LootEntry(itemId: ItemId.medicine, chance: 0.75, min: 1, max: 3),
      LootEntry(itemId: ItemId.water, chance: 0.4, min: 1, max: 2),
      LootEntry(itemId: ItemId.medkit, chance: 0.1, min: 1, max: 1),
      LootEntry(itemId: ItemId.adrenaline, chance: 0.04, min: 1, max: 1),
    ],
  ),
  SupplyTypeId.hardware: SupplyDef(
    id: SupplyTypeId.hardware,
    name: 'Ferretería en ruinas',
    description: 'Herramientas, clavos y caños por todos lados.',
    rarity: Rarity.uncommon,
    spawnWeight: 11,
    rolls: (min: 1, max: 2),
    staminaCost: 7,
    xp: 18,
    loot: [
      LootEntry(itemId: ItemId.metal, chance: 0.7, min: 2, max: 4),
      LootEntry(itemId: ItemId.wood, chance: 0.6, min: 2, max: 4),
      LootEntry(itemId: ItemId.pipe, chance: 0.08, min: 1, max: 1),
      LootEntry(itemId: ItemId.nailBat, chance: 0.04, min: 1, max: 1),
    ],
  ),
  SupplyTypeId.military: SupplyDef(
    id: SupplyTypeId.military,
    name: 'Caja militar',
    description: 'Suministros del ejército. Solo en zonas infestadas.',
    rarity: Rarity.epic,
    spawnWeight: 3,
    rolls: (min: 2, max: 3),
    staminaCost: 8,
    xp: 40,
    loot: [
      LootEntry(itemId: ItemId.ammo, chance: 0.9, min: 3, max: 8),
      LootEntry(itemId: ItemId.ration, chance: 0.4, min: 1, max: 2),
      LootEntry(itemId: ItemId.medkit, chance: 0.35, min: 1, max: 1),
      LootEntry(itemId: ItemId.scrapVest, chance: 0.12, min: 1, max: 1),
      LootEntry(itemId: ItemId.pistol, chance: 0.1, min: 1, max: 1),
      LootEntry(itemId: ItemId.riotArmor, chance: 0.05, min: 1, max: 1),
    ],
  ),
};

/// Tipos de suministro en el orden del registro web (afecta a la generación del mundo).
const List<SupplyTypeId> supplyTypes = [
  SupplyTypeId.backpack,
  SupplyTypeId.car,
  SupplyTypeId.debris,
  SupplyTypeId.grocery,
  SupplyTypeId.pharmacy,
  SupplyTypeId.hardware,
  SupplyTypeId.military,
];

extension SupplyTypeIdDef on SupplyTypeId {
  /// Definición del tipo de suministro.
  SupplyDef get def => supplyDefs[this]!;
}
