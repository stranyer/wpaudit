// Catálogo de objetos: recursos, consumibles, armas y protección.

import 'types.dart';

/// Recursos básicos (`ResourceId` en TS), en el orden de la versión web.
const List<ItemId> resourceIds = [
  ItemId.food,
  ItemId.water,
  ItemId.medicine,
  ItemId.wood,
  ItemId.metal,
  ItemId.ammo,
];

const Map<ItemId, ItemDef> itemDefs = {
  // --- Recursos básicos ---------------------------------------------------
  ItemId.food: ItemDef(
    id: ItemId.food,
    name: 'Comida enlatada',
    description: 'Latas abolladas pero selladas. Recupera resistencia.',
    category: ItemCategory.resource,
    rarity: Rarity.common,
    effects: ItemEffects(stamina: 20, health: 3),
    weight: 1,
  ),
  ItemId.water: ItemDef(
    id: ItemId.water,
    name: 'Agua potable',
    description: 'Botellas sin abrir. Un lujo en la Zona Cero.',
    category: ItemCategory.resource,
    rarity: Rarity.common,
    effects: ItemEffects(stamina: 12, health: 2),
    weight: 1,
  ),
  ItemId.medicine: ItemDef(
    id: ItemId.medicine,
    name: 'Medicamentos',
    description: 'Analgésicos y antibióticos. Cura heridas.',
    category: ItemCategory.resource,
    rarity: Rarity.uncommon,
    effects: ItemEffects(health: 30),
    weight: 1,
  ),
  ItemId.wood: ItemDef(
    id: ItemId.wood,
    name: 'Madera',
    description: 'Tablones y muebles rotos. Sirve para barricadas y armas.',
    category: ItemCategory.resource,
    rarity: Rarity.common,
    weight: 1,
  ),
  ItemId.metal: ItemDef(
    id: ItemId.metal,
    name: 'Chatarra de metal',
    description: 'Chapas, caños y tornillos. Base de cualquier mejora.',
    category: ItemCategory.resource,
    rarity: Rarity.common,
    weight: 1,
  ),
  ItemId.ammo: ItemDef(
    id: ItemId.ammo,
    name: 'Munición',
    description: 'Balas sueltas. Cada disparo cuenta.',
    category: ItemCategory.resource,
    rarity: Rarity.uncommon,
    weight: 1,
  ),

  // --- Consumibles --------------------------------------------------------
  ItemId.medkit: ItemDef(
    id: ItemId.medkit,
    name: 'Botiquín',
    description: 'Vendas, antisépticos y suturas. Curación mayor.',
    category: ItemCategory.consumable,
    rarity: Rarity.rare,
    effects: ItemEffects(health: 70),
    weight: 1,
  ),
  ItemId.ration: ItemDef(
    id: ItemId.ration,
    name: 'Ración de supervivencia',
    description: 'Comida y agua empaquetadas. Mucha resistencia.',
    category: ItemCategory.consumable,
    rarity: Rarity.uncommon,
    effects: ItemEffects(stamina: 50, health: 10),
    weight: 1,
  ),
  ItemId.adrenaline: ItemDef(
    id: ItemId.adrenaline,
    name: 'Jeringa de adrenalina',
    description: 'Un pinchazo y volvés a estar al cien.',
    category: ItemCategory.consumable,
    rarity: Rarity.epic,
    effects: ItemEffects(stamina: 100, health: 15),
    weight: 1,
  ),

  // --- Armas --------------------------------------------------------------
  ItemId.pipe: ItemDef(
    id: ItemId.pipe,
    name: 'Caño de plomo',
    description: 'Pesado y confiable.',
    category: ItemCategory.weapon,
    rarity: Rarity.uncommon,
    weapon: WeaponStats(damage: (min: 5, max: 9), accuracy: 0.86, critChance: 0.1, ammoPerShot: 0),
    weight: 0,
  ),
  ItemId.nailBat: ItemDef(
    id: ItemId.nailBat,
    name: 'Bate con clavos',
    description: 'Un clásico del fin del mundo.',
    category: ItemCategory.weapon,
    rarity: Rarity.uncommon,
    weapon: WeaponStats(damage: (min: 7, max: 11), accuracy: 0.84, critChance: 0.12, ammoPerShot: 0),
    weight: 0,
  ),
  ItemId.machete: ItemDef(
    id: ItemId.machete,
    name: 'Machete',
    description: 'Filo largo, cortes limpios.',
    category: ItemCategory.weapon,
    rarity: Rarity.rare,
    weapon: WeaponStats(damage: (min: 9, max: 14), accuracy: 0.86, critChance: 0.16, ammoPerShot: 0),
    weight: 0,
  ),
  ItemId.fireAxe: ItemDef(
    id: ItemId.fireAxe,
    name: 'Hacha de bombero',
    description: 'Parte cráneos y puertas por igual.',
    category: ItemCategory.weapon,
    rarity: Rarity.epic,
    weapon: WeaponStats(damage: (min: 13, max: 19), accuracy: 0.8, critChance: 0.18, ammoPerShot: 0),
    weight: 0,
  ),
  ItemId.pistol: ItemDef(
    id: ItemId.pistol,
    name: 'Pistola 9 mm',
    description: 'Ruidosa pero letal. Usa 1 munición por disparo.',
    category: ItemCategory.weapon,
    rarity: Rarity.epic,
    weapon: WeaponStats(damage: (min: 18, max: 26), accuracy: 0.88, critChance: 0.15, ammoPerShot: 1),
    weight: 0,
  ),
  ItemId.shotgun: ItemDef(
    id: ItemId.shotgun,
    name: 'Escopeta recortada',
    description: 'Devastadora a corta distancia. Usa 2 municiones.',
    category: ItemCategory.weapon,
    rarity: Rarity.legendary,
    weapon: WeaponStats(damage: (min: 32, max: 44), accuracy: 0.78, critChance: 0.12, ammoPerShot: 2),
    weight: 0,
  ),

  // --- Protección ---------------------------------------------------------
  ItemId.leatherJacket: ItemDef(
    id: ItemId.leatherJacket,
    name: 'Campera de cuero',
    description: 'Frena algunos mordiscos.',
    category: ItemCategory.armor,
    rarity: Rarity.uncommon,
    armor: ArmorStats(defense: 2),
    weight: 0,
  ),
  ItemId.scrapVest: ItemDef(
    id: ItemId.scrapVest,
    name: 'Chaleco de chapa',
    description: 'Ruidoso, incómodo y salvador.',
    category: ItemCategory.armor,
    rarity: Rarity.rare,
    armor: ArmorStats(defense: 4),
    weight: 0,
  ),
  ItemId.riotArmor: ItemDef(
    id: ItemId.riotArmor,
    name: 'Armadura antidisturbios',
    description: 'Equipo policial recuperado de un camión volcado.',
    category: ItemCategory.armor,
    rarity: Rarity.epic,
    armor: ArmorStats(defense: 7),
    weight: 0,
  ),
};

/// Puños: el arma por defecto cuando no hay nada equipado.
const WeaponStats fists = WeaponStats(damage: (min: 3, max: 6), accuracy: 0.9, critChance: 0.08, ammoPerShot: 0);

const Map<Rarity, String> rarityLabel = {
  Rarity.common: 'Común',
  Rarity.uncommon: 'Poco común',
  Rarity.rare: 'Raro',
  Rarity.epic: 'Épico',
  Rarity.legendary: 'Legendario',
};

const List<Rarity> rarityOrder = [Rarity.common, Rarity.uncommon, Rarity.rare, Rarity.epic, Rarity.legendary];

extension RarityLabel on Rarity {
  /// Nombre en español de la rareza.
  String get label => rarityLabel[this]!;
}

ItemDef getItem(ItemId id) => itemDefs[id]!;

extension ItemIdDef on ItemId {
  /// Definición del objeto (atajo de [getItem]).
  ItemDef get def => itemDefs[this]!;
}

bool isResource(ItemId id) => resourceIds.contains(id);

bool isConsumable(ItemId id) => itemDefs[id]!.effects != null;

bool isEquippable(ItemId id) {
  final c = itemDefs[id]!.category;
  return c == ItemCategory.weapon || c == ItemCategory.armor;
}
