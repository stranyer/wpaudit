import type { ItemDef, ItemId, Rarity, ResourceId, WeaponStats } from './types';

export const RESOURCE_IDS: ResourceId[] = ['food', 'water', 'medicine', 'wood', 'metal', 'ammo'];

export const ITEMS: Record<ItemId, ItemDef> = {
  // --- Recursos básicos ---------------------------------------------------
  food: {
    id: 'food',
    name: 'Comida enlatada',
    description: 'Latas abolladas pero selladas. Recupera resistencia.',
    category: 'resource',
    rarity: 'common',
    effects: { stamina: 20, health: 3 },
    weight: 1,
  },
  water: {
    id: 'water',
    name: 'Agua potable',
    description: 'Botellas sin abrir. Un lujo en la Zona Cero.',
    category: 'resource',
    rarity: 'common',
    effects: { stamina: 12, health: 2 },
    weight: 1,
  },
  medicine: {
    id: 'medicine',
    name: 'Medicamentos',
    description: 'Analgésicos y antibióticos. Cura heridas.',
    category: 'resource',
    rarity: 'uncommon',
    effects: { health: 30 },
    weight: 1,
  },
  wood: {
    id: 'wood',
    name: 'Madera',
    description: 'Tablones y muebles rotos. Sirve para barricadas y armas.',
    category: 'resource',
    rarity: 'common',
    weight: 1,
  },
  metal: {
    id: 'metal',
    name: 'Chatarra de metal',
    description: 'Chapas, caños y tornillos. Base de cualquier mejora.',
    category: 'resource',
    rarity: 'common',
    weight: 1,
  },
  ammo: {
    id: 'ammo',
    name: 'Munición',
    description: 'Balas sueltas. Cada disparo cuenta.',
    category: 'resource',
    rarity: 'uncommon',
    weight: 1,
  },

  // --- Consumibles --------------------------------------------------------
  medkit: {
    id: 'medkit',
    name: 'Botiquín',
    description: 'Vendas, antisépticos y suturas. Curación mayor.',
    category: 'consumable',
    rarity: 'rare',
    effects: { health: 70 },
    weight: 1,
  },
  ration: {
    id: 'ration',
    name: 'Ración de supervivencia',
    description: 'Comida y agua empaquetadas. Mucha resistencia.',
    category: 'consumable',
    rarity: 'uncommon',
    effects: { stamina: 50, health: 10 },
    weight: 1,
  },
  adrenaline: {
    id: 'adrenaline',
    name: 'Jeringa de adrenalina',
    description: 'Un pinchazo y volvés a estar al cien.',
    category: 'consumable',
    rarity: 'epic',
    effects: { stamina: 100, health: 15 },
    weight: 1,
  },

  // --- Armas --------------------------------------------------------------
  pipe: {
    id: 'pipe',
    name: 'Caño de plomo',
    description: 'Pesado y confiable.',
    category: 'weapon',
    rarity: 'uncommon',
    weapon: { damage: [5, 9], accuracy: 0.86, critChance: 0.1, ammoPerShot: 0 },
    weight: 0,
  },
  nail_bat: {
    id: 'nail_bat',
    name: 'Bate con clavos',
    description: 'Un clásico del fin del mundo.',
    category: 'weapon',
    rarity: 'uncommon',
    weapon: { damage: [7, 11], accuracy: 0.84, critChance: 0.12, ammoPerShot: 0 },
    weight: 0,
  },
  machete: {
    id: 'machete',
    name: 'Machete',
    description: 'Filo largo, cortes limpios.',
    category: 'weapon',
    rarity: 'rare',
    weapon: { damage: [9, 14], accuracy: 0.86, critChance: 0.16, ammoPerShot: 0 },
    weight: 0,
  },
  fire_axe: {
    id: 'fire_axe',
    name: 'Hacha de bombero',
    description: 'Parte cráneos y puertas por igual.',
    category: 'weapon',
    rarity: 'epic',
    weapon: { damage: [13, 19], accuracy: 0.8, critChance: 0.18, ammoPerShot: 0 },
    weight: 0,
  },
  pistol: {
    id: 'pistol',
    name: 'Pistola 9 mm',
    description: 'Ruidosa pero letal. Usa 1 munición por disparo.',
    category: 'weapon',
    rarity: 'epic',
    weapon: { damage: [18, 26], accuracy: 0.88, critChance: 0.15, ammoPerShot: 1 },
    weight: 0,
  },
  shotgun: {
    id: 'shotgun',
    name: 'Escopeta recortada',
    description: 'Devastadora a corta distancia. Usa 2 municiones.',
    category: 'weapon',
    rarity: 'legendary',
    weapon: { damage: [32, 44], accuracy: 0.78, critChance: 0.12, ammoPerShot: 2 },
    weight: 0,
  },

  // --- Protección ---------------------------------------------------------
  leather_jacket: {
    id: 'leather_jacket',
    name: 'Campera de cuero',
    description: 'Frena algunos mordiscos.',
    category: 'armor',
    rarity: 'uncommon',
    armor: { defense: 2 },
    weight: 0,
  },
  scrap_vest: {
    id: 'scrap_vest',
    name: 'Chaleco de chapa',
    description: 'Ruidoso, incómodo y salvador.',
    category: 'armor',
    rarity: 'rare',
    armor: { defense: 4 },
    weight: 0,
  },
  riot_armor: {
    id: 'riot_armor',
    name: 'Armadura antidisturbios',
    description: 'Equipo policial recuperado de un camión volcado.',
    category: 'armor',
    rarity: 'epic',
    armor: { defense: 7 },
    weight: 0,
  },
};

export const FISTS: WeaponStats = { damage: [3, 6], accuracy: 0.9, critChance: 0.08, ammoPerShot: 0 };

export const RARITY_LABEL: Record<Rarity, string> = {
  common: 'Común',
  uncommon: 'Poco común',
  rare: 'Raro',
  epic: 'Épico',
  legendary: 'Legendario',
};

export const RARITY_ORDER: Rarity[] = ['common', 'uncommon', 'rare', 'epic', 'legendary'];

export function getItem(id: ItemId): ItemDef {
  return ITEMS[id];
}

export function isResource(id: ItemId): id is ResourceId {
  return (RESOURCE_IDS as ItemId[]).includes(id);
}

export function isConsumable(id: ItemId): boolean {
  return ITEMS[id].effects !== undefined;
}

export function isEquippable(id: ItemId): boolean {
  const c = ITEMS[id].category;
  return c === 'weapon' || c === 'armor';
}
