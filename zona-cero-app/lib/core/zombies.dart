// Bestiario: tipos de infectados, sus estadísticas y su botín.

import 'types.dart';
import 'utils.dart';

const Map<ZombieTypeId, ZombieDef> zombieDefs = {
  ZombieTypeId.walker: ZombieDef(
    id: ZombieTypeId.walker,
    name: 'Caminante',
    description: 'Lento y torpe, pero nunca se cansa.',
    baseHealth: 30,
    damage: (min: 5, max: 9),
    accuracy: 0.68,
    evasion: 0.05,
    fleeChance: 0.85,
    xp: 20,
    ability: ZombieAbility.none,
    recommendedLevel: 1,
    spawnWeight: 50,
    loot: [
      LootEntry(itemId: ItemId.food, chance: 0.45, min: 1, max: 2),
      LootEntry(itemId: ItemId.water, chance: 0.35, min: 1, max: 2),
      LootEntry(itemId: ItemId.metal, chance: 0.3, min: 1, max: 2),
      LootEntry(itemId: ItemId.ammo, chance: 0.12, min: 1, max: 2),
      LootEntry(itemId: ItemId.leatherJacket, chance: 0.03, min: 1, max: 1),
    ],
  ),
  ZombieTypeId.runner: ZombieDef(
    id: ZombieTypeId.runner,
    name: 'Corredor',
    description: 'Infectado reciente. Rápido y a veces ataca dos veces.',
    baseHealth: 24,
    damage: (min: 5, max: 8),
    accuracy: 0.8,
    evasion: 0.15,
    fleeChance: 0.45,
    xp: 30,
    ability: ZombieAbility.doubleStrike,
    recommendedLevel: 2,
    spawnWeight: 22,
    loot: [
      LootEntry(itemId: ItemId.water, chance: 0.4, min: 1, max: 2),
      LootEntry(itemId: ItemId.medicine, chance: 0.25, min: 1, max: 1),
      LootEntry(itemId: ItemId.ammo, chance: 0.2, min: 1, max: 3),
      LootEntry(itemId: ItemId.pipe, chance: 0.05, min: 1, max: 1),
    ],
  ),
  ZombieTypeId.bloater: ZombieDef(
    id: ZombieTypeId.bloater,
    name: 'Hinchado',
    description: 'Lleno de gases tóxicos. Explota al morir: mejor rematarlo a distancia.',
    baseHealth: 50,
    damage: (min: 6, max: 11),
    accuracy: 0.6,
    evasion: 0,
    fleeChance: 0.9,
    xp: 40,
    ability: ZombieAbility.toxicBurst,
    recommendedLevel: 3,
    spawnWeight: 12,
    loot: [
      LootEntry(itemId: ItemId.medicine, chance: 0.45, min: 1, max: 2),
      LootEntry(itemId: ItemId.food, chance: 0.4, min: 1, max: 3),
      LootEntry(itemId: ItemId.adrenaline, chance: 0.04, min: 1, max: 1),
    ],
  ),
  ZombieTypeId.screamer: ZombieDef(
    id: ZombieTypeId.screamer,
    name: 'Chillón',
    description: 'Sus alaridos atraen a otros infectados que lo protegen.',
    baseHealth: 28,
    damage: (min: 4, max: 8),
    accuracy: 0.7,
    evasion: 0.1,
    fleeChance: 0.6,
    xp: 35,
    ability: ZombieAbility.callHorde,
    recommendedLevel: 3,
    spawnWeight: 11,
    loot: [
      LootEntry(itemId: ItemId.ammo, chance: 0.35, min: 1, max: 3),
      LootEntry(itemId: ItemId.metal, chance: 0.4, min: 1, max: 3),
      LootEntry(itemId: ItemId.medicine, chance: 0.2, min: 1, max: 1),
      LootEntry(itemId: ItemId.nailBat, chance: 0.05, min: 1, max: 1),
    ],
  ),
  ZombieTypeId.brute: ZombieDef(
    id: ZombieTypeId.brute,
    name: 'Bruto',
    description: 'Una montaña de carne. Prepara embestidas: defendete en el momento justo.',
    baseHealth: 110,
    damage: (min: 12, max: 18),
    accuracy: 0.72,
    evasion: 0,
    fleeChance: 0.7,
    xp: 75,
    ability: ZombieAbility.charge,
    recommendedLevel: 5,
    spawnWeight: 5,
    loot: [
      LootEntry(itemId: ItemId.metal, chance: 0.7, min: 2, max: 5),
      LootEntry(itemId: ItemId.ammo, chance: 0.5, min: 2, max: 5),
      LootEntry(itemId: ItemId.medkit, chance: 0.25, min: 1, max: 1),
      LootEntry(itemId: ItemId.fireAxe, chance: 0.06, min: 1, max: 1),
      LootEntry(itemId: ItemId.riotArmor, chance: 0.04, min: 1, max: 1),
      LootEntry(itemId: ItemId.shotgun, chance: 0.02, min: 1, max: 1),
    ],
  ),
};

/// Tipos de zombie en el orden de la versión web (afecta a la generación del mundo).
const List<ZombieTypeId> zombieTypes = [
  ZombieTypeId.walker,
  ZombieTypeId.runner,
  ZombieTypeId.bloater,
  ZombieTypeId.screamer,
  ZombieTypeId.brute,
];

extension ZombieTypeIdDef on ZombieTypeId {
  /// Definición del tipo de zombie.
  ZombieDef get def => zombieDefs[this]!;
}

/// Escala de un zombie según su nivel.
int zombieHealthForLevel(ZombieDef def, int level) => jsRound(def.baseHealth * (1 + 0.12 * (level - 1)));

IntRange zombieDamageForLevel(ZombieDef def, int level) {
  final k = 1 + 0.08 * (level - 1);
  return (min: jsRound(def.damage.min * k), max: jsRound(def.damage.max * k));
}

/// Nivel de amenaza relativo al jugador: 0 = fácil, 1 = parejo, 2 = peligroso, 3 = mortal.
int threatRating(ZombieDef def, int playerLevel) {
  final diff = def.recommendedLevel - playerLevel;
  if (diff <= -2) return 0;
  if (diff <= 0) return 1;
  if (diff <= 2) return 2;
  return 3;
}
