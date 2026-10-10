// Tipos centrales del motor de Zona Cero.
// Este módulo no depende de React, del DOM ni de librerías de render:
// todo lo que está en `src/core` es lógica pura y testeable.

export interface LatLng {
  lat: number;
  lng: number;
}

// ---------------------------------------------------------------------------
// Objetos e inventario
// ---------------------------------------------------------------------------

export type ResourceId = 'food' | 'water' | 'medicine' | 'wood' | 'metal' | 'ammo';

export type Rarity = 'common' | 'uncommon' | 'rare' | 'epic' | 'legendary';

export type ItemCategory = 'resource' | 'consumable' | 'weapon' | 'armor';

export type ItemId =
  | ResourceId
  | 'medkit'
  | 'ration'
  | 'adrenaline'
  | 'pipe'
  | 'nail_bat'
  | 'machete'
  | 'fire_axe'
  | 'pistol'
  | 'shotgun'
  | 'leather_jacket'
  | 'scrap_vest'
  | 'riot_armor';

export interface ItemEffects {
  health?: number;
  stamina?: number;
}

export interface WeaponStats {
  damage: [number, number];
  accuracy: number;
  critChance: number;
  /** Munición consumida por disparo. 0 = arma cuerpo a cuerpo. */
  ammoPerShot: number;
}

export interface ItemDef {
  id: ItemId;
  name: string;
  description: string;
  category: ItemCategory;
  rarity: Rarity;
  /** Si tiene efectos, el objeto se puede consumir. */
  effects?: ItemEffects;
  weapon?: WeaponStats;
  armor?: { defense: number };
  /** Los objetos equipables no ocupan espacio en la mochila. */
  weight: number;
}

export type Inventory = Partial<Record<ItemId, number>>;

export interface Equipment {
  /** Arma cuerpo a cuerpo (ataque y golpe fuerte). */
  melee: ItemId | null;
  /** Arma de fuego (disparo, consume munición). */
  firearm: ItemId | null;
  armor: ItemId | null;
}

export type EquipmentSlot = keyof Equipment;

// ---------------------------------------------------------------------------
// Jugador
// ---------------------------------------------------------------------------

export type FactionId = 'resistencia' | 'guardia' | 'nomades';

export interface PlayerStats {
  zombiesKilled: Partial<Record<ZombieTypeId, number>>;
  suppliesLooted: number;
  itemsCrafted: number;
  resourcesDonated: number;
  distanceWalkedM: number;
  encountersWon: number;
  encountersFled: number;
  deaths: number;
  cellsExplored: number;
}

export interface PlayerState {
  id: string;
  name: string;
  level: number;
  xp: number;
  health: number;
  stamina: number;
  inventory: Inventory;
  equipment: Equipment;
  stats: PlayerStats;
  factionId: FactionId | null;
  /** Momento (ms) del último cálculo de regeneración. */
  lastRegenAt: number;
  /** Último descanso en un refugio (ms), para el enfriamiento. */
  lastRestAt: number;
  createdAt: number;
}

// ---------------------------------------------------------------------------
// Zombies y combate
// ---------------------------------------------------------------------------

export type ZombieTypeId = 'walker' | 'runner' | 'bloater' | 'screamer' | 'brute';

export type ZombieAbility = 'none' | 'double_strike' | 'toxic_burst' | 'call_horde' | 'charge';

export interface LootEntry {
  itemId: ItemId;
  /** Probabilidad 0..1 de que aparezca esta entrada. */
  chance: number;
  min: number;
  max: number;
}

export interface ZombieDef {
  id: ZombieTypeId;
  name: string;
  description: string;
  baseHealth: number;
  damage: [number, number];
  accuracy: number;
  evasion: number;
  /** Probabilidad base de huir con éxito de este zombie. */
  fleeChance: number;
  xp: number;
  ability: ZombieAbility;
  /** Nivel recomendado; por debajo se marca como encuentro peligroso. */
  recommendedLevel: number;
  spawnWeight: number;
  loot: LootEntry[];
}

export type CombatActionType = 'attack' | 'heavy' | 'shoot' | 'defend' | 'use_item' | 'flee';

export type CombatAction =
  | { type: 'attack' }
  | { type: 'heavy' }
  | { type: 'shoot' }
  | { type: 'defend' }
  | { type: 'use_item'; itemId: ItemId }
  | { type: 'flee' };

export type CombatEvent =
  | { kind: 'player_hit'; damage: number; crit: boolean; ranged: boolean; stunBonus: boolean }
  | { kind: 'player_miss'; ranged: boolean }
  | { kind: 'exhausted' }
  | { kind: 'no_ammo' }
  | { kind: 'defend'; stamina: number }
  | { kind: 'heal'; itemId: ItemId; health: number; stamina: number }
  | { kind: 'flee_success' }
  | { kind: 'flee_fail' }
  | { kind: 'zombie_hit'; damage: number; blocked: number; charged: boolean }
  | { kind: 'zombie_miss'; charged: boolean }
  | { kind: 'zombie_charge_prepare' }
  | { kind: 'zombie_stunned' }
  | { kind: 'zombie_scream'; healed: number }
  | { kind: 'toxic_burst'; damage: number }
  | { kind: 'zombie_killed' }
  | { kind: 'player_down' };

export type CombatStatus = 'ongoing' | 'won' | 'lost' | 'fled';

export interface CombatZombie {
  typeId: ZombieTypeId;
  name: string;
  level: number;
  health: number;
  maxHealth: number;
  damage: [number, number];
  accuracy: number;
  evasion: number;
  /** Prepara una embestida para el próximo turno (Bruto). */
  charging: boolean;
  /** Turnos propios que faltan para preparar la próxima embestida (Bruto). */
  chargeIn: number;
  /** Aturdido: pierde su próximo turno y el siguiente golpe es crítico. */
  stunned: boolean;
  screamsLeft: number;
}

export interface CombatPlayer {
  health: number;
  maxHealth: number;
  stamina: number;
  maxStamina: number;
  defending: boolean;
  melee: WeaponStats;
  meleeName: string;
  firearm: WeaponStats | null;
  firearmName: string | null;
  defense: number;
}

export interface CombatState {
  spawnId: string;
  zombie: CombatZombie;
  player: CombatPlayer;
  /** Copia de los objetos disponibles al iniciar (munición y consumibles). */
  available: Inventory;
  /** Objetos gastados durante el combate; se descuentan al terminar. */
  consumed: Inventory;
  turn: number;
  status: CombatStatus;
  /** Eventos del último turno (para animaciones y textos). */
  lastEvents: CombatEvent[];
  /** Historial completo del encuentro. */
  log: CombatEvent[];
  xpMultiplier: number;
}

export interface Reward {
  xp: number;
  items: Inventory;
}

// ---------------------------------------------------------------------------
// Mundo, spawns y zonas
// ---------------------------------------------------------------------------

export type SupplyTypeId = 'backpack' | 'car' | 'pharmacy' | 'grocery' | 'hardware' | 'debris' | 'military';

export interface SupplyDef {
  id: SupplyTypeId;
  name: string;
  description: string;
  rarity: Rarity;
  spawnWeight: number;
  /** Rolls de botín: cuántas entradas de la tabla se sortean. */
  rolls: [number, number];
  loot: LootEntry[];
  staminaCost: number;
  xp: number;
}

export type PlacementState = 'raw' | 'snapped';

interface BaseSpawn {
  id: string;
  cellId: string;
  position: LatLng;
  expiresAt: number;
  placement: PlacementState;
}

export interface ZombieSpawn extends BaseSpawn {
  kind: 'zombie';
  zombieType: ZombieTypeId;
}

export interface SupplySpawn extends BaseSpawn {
  kind: 'supply';
  supplyType: SupplyTypeId;
}

export type Spawn = ZombieSpawn | SupplySpawn;

export type ZoneThreat = 'calm' | 'infested';

export interface Zone {
  cellId: string;
  threat: ZoneThreat;
  /** Esquinas SO y NE de la celda. */
  bounds: [LatLng, LatLng];
}

// ---------------------------------------------------------------------------
// Refugios y comunidad
// ---------------------------------------------------------------------------

export interface ShelterContribution {
  playerId: string;
  playerName: string;
  amount: number;
}

export interface Shelter {
  id: string;
  name: string;
  ownerId: string;
  ownerName: string;
  factionId: FactionId | null;
  level: number;
  /** Posición PÚBLICA (ajustada a la grilla y a la calle); nunca la ubicación real del creador. */
  position: LatLng;
  /** Recursos aportados hacia el próximo nivel. */
  progress: Partial<Record<ResourceId, number>>;
  contributions: ShelterContribution[];
  createdAt: number;
}

export interface Faction {
  id: FactionId;
  name: string;
  motto: string;
  color: string;
  bonusDescription: string;
  members: number;
  totalContribution: number;
}

export interface PublicSurvivor {
  id: string;
  name: string;
  level: number;
  factionId: FactionId | null;
  /** Posición aproximada (difuminada) — nunca la exacta. */
  approxPosition: LatLng;
  lastSeenAt: number;
}

export interface LeaderboardEntry {
  playerId: string;
  playerName: string;
  factionId: FactionId | null;
  level: number;
  contribution: number;
}

// ---------------------------------------------------------------------------
// Validación de interacciones (preparado para servidor)
// ---------------------------------------------------------------------------

/** Tipo de interacción: solo `scavenge` reclama el punto (lo agota para ese jugador). */
export type InteractionAction = 'scavenge' | 'encounter' | 'shelter';

export interface InteractionRequest {
  playerId: string;
  action: InteractionAction;
  targetId: string;
  /** Vencimiento del spawn (ms), si aplica. */
  targetExpiresAt?: number;
  targetPosition: LatLng;
  playerPosition: LatLng;
  accuracyM: number;
  timestamp: number;
}

export type InteractionRejection = 'out_of_range' | 'too_fast' | 'depleted' | 'expired' | 'low_accuracy';

export interface InteractionResult {
  ok: boolean;
  reason?: InteractionRejection;
  distanceM: number;
}
