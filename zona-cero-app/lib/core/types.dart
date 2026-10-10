// Tipos centrales del motor de Zona Cero.
// Este módulo no depende de Flutter ni de librerías de render: todo lo que está
// en `lib/core` es lógica pura (solo `dart:*`) y testeable, reutilizable en un
// servidor.
//
// Convenciones:
// - Los enums exponen `key` con el identificador estable de la versión web
//   (p. ej. `ItemId.nailBat.key == 'nail_bat'`) y `fromKey`/`tryFromKey`.
// - Las clases son inmutables; `toJson`/`fromJson` producen exactamente la misma
//   forma que los objetos de TypeScript, así las partidas son compatibles con la
//   versión web y con el backend de Supabase.
// - En `copyWith`, los campos anulables se pueden borrar pasando `null`
//   explícitamente (se usa un valor centinela para distinguir "no pasado").

import 'utils.dart';

/// Enum con un identificador de texto estable para JSON.
abstract interface class KeyedEnum {
  String get key;
}

/// Centinela para distinguir "no se pasó el argumento" de `null` en `copyWith`.
const Object _unset = Object();

// ---------------------------------------------------------------------------
// Lectura defensiva de JSON (los números pueden llegar como texto, etc.)
// ---------------------------------------------------------------------------

num? _numOrNull(Object? v) {
  if (v is num) return v.isFinite ? v : null;
  if (v is String && v.trim().isNotEmpty) {
    final n = num.tryParse(v.trim());
    return n != null && n.isFinite ? n : null;
  }
  return null;
}

int _int(Object? v, int fallback) {
  final n = _numOrNull(v);
  return n == null ? fallback : jsRound(n);
}

double _dbl(Object? v, double fallback) => _numOrNull(v)?.toDouble() ?? fallback;

String _str(Object? v, String fallback) {
  if (v is String) return v;
  if (v is num && v.isFinite) return jsNumToString(v);
  return fallback;
}

String? _strOrNull(Object? v) => v is String ? v : null;

Map<String, dynamic>? _map(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

num _reqNum(Map<String, dynamic> json, String key) {
  final n = _numOrNull(json[key]);
  if (n == null) throw FormatException('Campo numérico inválido: $key', json);
  return n;
}

String _reqStr(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! String) throw FormatException('Campo de texto inválido: $key', json);
  return v;
}

/// Serializa un mapa enum → cantidad con las claves estables.
Map<String, int> keyedMapToJson<K extends KeyedEnum>(Map<K, int> m) => {
      for (final e in m.entries) e.key.key: e.value,
    };

/// Lee un mapa clave → cantidad; ignora claves desconocidas y valores no numéricos.
Map<K, int> keyedMapFromJson<K>(Object? json, K? Function(String key) parse) {
  final out = <K, int>{};
  final m = _map(json);
  if (m == null) return out;
  for (final e in m.entries) {
    final k = parse(e.key);
    final n = _numOrNull(e.value);
    if (k != null && n != null) out[k] = jsRound(n);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Coordenadas
// ---------------------------------------------------------------------------

/// Posición geográfica en grados.
///
/// Ojo: `package:maplibre_gl` también exporta una clase `LatLng`; importá uno de
/// los dos con prefijo o con `hide`.
class LatLng {
  const LatLng(this.lat, this.lng);

  final double lat;
  final double lng;

  factory LatLng.fromJson(Map<String, dynamic> json) =>
      LatLng(_reqNum(json, 'lat').toDouble(), _reqNum(json, 'lng').toDouble());

  Map<String, dynamic> toJson() => {'lat': jsonNum(lat), 'lng': jsonNum(lng)};

  LatLng copyWith({double? lat, double? lng}) => LatLng(lat ?? this.lat, lng ?? this.lng);

  @override
  bool operator ==(Object other) => other is LatLng && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'LatLng($lat, $lng)';
}

/// Esquinas SO y NE de un rectángulo (en TS: `[LatLng, LatLng]`).
typedef CellBounds = ({LatLng sw, LatLng ne});

/// Rango entero inclusivo (en TS: `[number, number]`).
typedef IntRange = ({int min, int max});

// ---------------------------------------------------------------------------
// Objetos e inventario
// ---------------------------------------------------------------------------

enum Rarity implements KeyedEnum {
  common('common'),
  uncommon('uncommon'),
  rare('rare'),
  epic('epic'),
  legendary('legendary');

  const Rarity(this.key);
  @override
  final String key;

  static final Map<String, Rarity> _byKey = {for (final v in values) v.key: v};
  static Rarity fromKey(String key) => _byKey[key] ?? (throw ArgumentError.value(key, 'key', 'Rarity desconocida'));
  static Rarity? tryFromKey(String? key) => key == null ? null : _byKey[key];
}

enum ItemCategory implements KeyedEnum {
  resource('resource'),
  consumable('consumable'),
  weapon('weapon'),
  armor('armor');

  const ItemCategory(this.key);
  @override
  final String key;

  static final Map<String, ItemCategory> _byKey = {for (final v in values) v.key: v};
  static ItemCategory fromKey(String key) =>
      _byKey[key] ?? (throw ArgumentError.value(key, 'key', 'ItemCategory desconocida'));
  static ItemCategory? tryFromKey(String? key) => key == null ? null : _byKey[key];
}

/// Identificador de objeto. Los seis primeros son los recursos básicos (`ResourceId` en TS).
enum ItemId implements KeyedEnum {
  food('food'),
  water('water'),
  medicine('medicine'),
  wood('wood'),
  metal('metal'),
  ammo('ammo'),
  medkit('medkit'),
  ration('ration'),
  adrenaline('adrenaline'),
  pipe('pipe'),
  nailBat('nail_bat'),
  machete('machete'),
  fireAxe('fire_axe'),
  pistol('pistol'),
  shotgun('shotgun'),
  leatherJacket('leather_jacket'),
  scrapVest('scrap_vest'),
  riotArmor('riot_armor');

  const ItemId(this.key);
  @override
  final String key;

  static final Map<String, ItemId> _byKey = {for (final v in values) v.key: v};
  static ItemId fromKey(String key) => _byKey[key] ?? (throw ArgumentError.value(key, 'key', 'ItemId desconocido'));
  static ItemId? tryFromKey(String? key) => key == null ? null : _byKey[key];
}

class ItemEffects {
  const ItemEffects({this.health, this.stamina});
  final int? health;
  final int? stamina;
}

class WeaponStats {
  const WeaponStats({
    required this.damage,
    required this.accuracy,
    required this.critChance,
    required this.ammoPerShot,
  });

  final IntRange damage;
  final double accuracy;
  final double critChance;

  /// Munición consumida por disparo. 0 = arma cuerpo a cuerpo.
  final int ammoPerShot;
}

class ArmorStats {
  const ArmorStats({required this.defense});
  final int defense;
}

class ItemDef {
  const ItemDef({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.rarity,
    this.effects,
    this.weapon,
    this.armor,
    required this.weight,
  });

  final ItemId id;
  final String name;
  final String description;
  final ItemCategory category;
  final Rarity rarity;

  /// Si tiene efectos, el objeto se puede consumir.
  final ItemEffects? effects;
  final WeaponStats? weapon;
  final ArmorStats? armor;

  /// Los objetos equipables no ocupan espacio en la mochila.
  final int weight;
}

/// Inventario: cantidad por objeto. Tratarlo como inmutable: las funciones de
/// `inventory.dart` siempre devuelven un mapa nuevo.
typedef Inventory = Map<ItemId, int>;

Map<String, int> inventoryToJson(Inventory inv) => keyedMapToJson(inv);

Inventory inventoryFromJson(Object? json) => keyedMapFromJson(json, ItemId.tryFromKey);

enum EquipmentSlot implements KeyedEnum {
  melee('melee'),
  firearm('firearm'),
  armor('armor');

  const EquipmentSlot(this.key);
  @override
  final String key;

  static final Map<String, EquipmentSlot> _byKey = {for (final v in values) v.key: v};
  static EquipmentSlot fromKey(String key) =>
      _byKey[key] ?? (throw ArgumentError.value(key, 'key', 'EquipmentSlot desconocido'));
  static EquipmentSlot? tryFromKey(String? key) => key == null ? null : _byKey[key];
}

class Equipment {
  const Equipment({this.melee, this.firearm, this.armor});

  static const Equipment empty = Equipment();

  /// Arma cuerpo a cuerpo (ataque y golpe fuerte).
  final ItemId? melee;

  /// Arma de fuego (disparo, consume munición).
  final ItemId? firearm;
  final ItemId? armor;

  ItemId? operator [](EquipmentSlot slot) => switch (slot) {
        EquipmentSlot.melee => melee,
        EquipmentSlot.firearm => firearm,
        EquipmentSlot.armor => armor,
      };

  /// Devuelve un equipo con `slot` reemplazado (o vaciado con `null`).
  Equipment withSlot(EquipmentSlot slot, ItemId? id) => switch (slot) {
        EquipmentSlot.melee => Equipment(melee: id, firearm: firearm, armor: armor),
        EquipmentSlot.firearm => Equipment(melee: melee, firearm: id, armor: armor),
        EquipmentSlot.armor => Equipment(melee: melee, firearm: firearm, armor: id),
      };

  Equipment copyWith({Object? melee = _unset, Object? firearm = _unset, Object? armor = _unset}) => Equipment(
        melee: identical(melee, _unset) ? this.melee : melee as ItemId?,
        firearm: identical(firearm, _unset) ? this.firearm : firearm as ItemId?,
        armor: identical(armor, _unset) ? this.armor : armor as ItemId?,
      );

  factory Equipment.fromJson(Map<String, dynamic> json) => Equipment(
        melee: ItemId.tryFromKey(_strOrNull(json['melee'])),
        firearm: ItemId.tryFromKey(_strOrNull(json['firearm'])),
        armor: ItemId.tryFromKey(_strOrNull(json['armor'])),
      );

  Map<String, dynamic> toJson() => {'melee': melee?.key, 'firearm': firearm?.key, 'armor': armor?.key};

  @override
  bool operator ==(Object other) =>
      other is Equipment && other.melee == melee && other.firearm == firearm && other.armor == armor;

  @override
  int get hashCode => Object.hash(melee, firearm, armor);

  @override
  String toString() => 'Equipment(melee: $melee, firearm: $firearm, armor: $armor)';
}

// ---------------------------------------------------------------------------
// Jugador
// ---------------------------------------------------------------------------

enum FactionId implements KeyedEnum {
  resistencia('resistencia'),
  guardia('guardia'),
  nomades('nomades');

  const FactionId(this.key);
  @override
  final String key;

  static final Map<String, FactionId> _byKey = {for (final v in values) v.key: v};
  static FactionId fromKey(String key) =>
      _byKey[key] ?? (throw ArgumentError.value(key, 'key', 'FactionId desconocida'));
  static FactionId? tryFromKey(String? key) => key == null ? null : _byKey[key];
}

class PlayerStats {
  const PlayerStats({
    this.zombiesKilled = const {},
    this.suppliesLooted = 0,
    this.itemsCrafted = 0,
    this.resourcesDonated = 0,
    this.distanceWalkedM = 0,
    this.encountersWon = 0,
    this.encountersFled = 0,
    this.deaths = 0,
    this.cellsExplored = 0,
  });

  final Map<ZombieTypeId, int> zombiesKilled;
  final int suppliesLooted;
  final int itemsCrafted;
  final int resourcesDonated;
  final double distanceWalkedM;
  final int encountersWon;
  final int encountersFled;
  final int deaths;
  final int cellsExplored;

  PlayerStats copyWith({
    Map<ZombieTypeId, int>? zombiesKilled,
    int? suppliesLooted,
    int? itemsCrafted,
    int? resourcesDonated,
    double? distanceWalkedM,
    int? encountersWon,
    int? encountersFled,
    int? deaths,
    int? cellsExplored,
  }) =>
      PlayerStats(
        zombiesKilled: zombiesKilled ?? this.zombiesKilled,
        suppliesLooted: suppliesLooted ?? this.suppliesLooted,
        itemsCrafted: itemsCrafted ?? this.itemsCrafted,
        resourcesDonated: resourcesDonated ?? this.resourcesDonated,
        distanceWalkedM: distanceWalkedM ?? this.distanceWalkedM,
        encountersWon: encountersWon ?? this.encountersWon,
        encountersFled: encountersFled ?? this.encountersFled,
        deaths: deaths ?? this.deaths,
        cellsExplored: cellsExplored ?? this.cellsExplored,
      );

  /// Lectura tolerante: los campos ausentes o inválidos toman el valor inicial.
  factory PlayerStats.fromJson(Map<String, dynamic> json) => PlayerStats(
        zombiesKilled: keyedMapFromJson(json['zombiesKilled'], ZombieTypeId.tryFromKey),
        suppliesLooted: _int(json['suppliesLooted'], 0),
        itemsCrafted: _int(json['itemsCrafted'], 0),
        resourcesDonated: _int(json['resourcesDonated'], 0),
        distanceWalkedM: _dbl(json['distanceWalkedM'], 0),
        encountersWon: _int(json['encountersWon'], 0),
        encountersFled: _int(json['encountersFled'], 0),
        deaths: _int(json['deaths'], 0),
        cellsExplored: _int(json['cellsExplored'], 0),
      );

  Map<String, dynamic> toJson() => {
        'zombiesKilled': keyedMapToJson(zombiesKilled),
        'suppliesLooted': suppliesLooted,
        'itemsCrafted': itemsCrafted,
        'resourcesDonated': resourcesDonated,
        'distanceWalkedM': jsonNum(distanceWalkedM),
        'encountersWon': encountersWon,
        'encountersFled': encountersFled,
        'deaths': deaths,
        'cellsExplored': cellsExplored,
      };

  @override
  bool operator ==(Object other) =>
      other is PlayerStats &&
      deepMapEquals(other.zombiesKilled, zombiesKilled) &&
      other.suppliesLooted == suppliesLooted &&
      other.itemsCrafted == itemsCrafted &&
      other.resourcesDonated == resourcesDonated &&
      other.distanceWalkedM == distanceWalkedM &&
      other.encountersWon == encountersWon &&
      other.encountersFled == encountersFled &&
      other.deaths == deaths &&
      other.cellsExplored == cellsExplored;

  @override
  int get hashCode => Object.hash(mapHash(zombiesKilled), suppliesLooted, itemsCrafted, resourcesDonated,
      distanceWalkedM, encountersWon, encountersFled, deaths, cellsExplored);
}

/// Inventario inicial de un jugador nuevo.
const Inventory starterInventory = {ItemId.food: 2, ItemId.water: 2, ItemId.medicine: 1, ItemId.wood: 2};

class PlayerState {
  const PlayerState({
    required this.id,
    required this.name,
    required this.level,
    required this.xp,
    required this.health,
    required this.stamina,
    required this.inventory,
    required this.equipment,
    required this.stats,
    required this.factionId,
    required this.lastRegenAt,
    required this.lastRestAt,
    required this.createdAt,
  });

  final String id;
  final String name;
  final int level;

  /// XP acumulada dentro del nivel actual.
  final int xp;

  /// Puede tener decimales (la regeneración pasiva es continua).
  final double health;
  final double stamina;
  final Inventory inventory;
  final Equipment equipment;
  final PlayerStats stats;
  final FactionId? factionId;

  /// Momento (ms) del último cálculo de regeneración.
  final int lastRegenAt;

  /// Último descanso en un refugio (ms), para el enfriamiento.
  final int lastRestAt;
  final int createdAt;

  /// `factionId` se puede borrar pasando `null` explícitamente.
  PlayerState copyWith({
    String? id,
    String? name,
    int? level,
    int? xp,
    double? health,
    double? stamina,
    Inventory? inventory,
    Equipment? equipment,
    PlayerStats? stats,
    Object? factionId = _unset,
    int? lastRegenAt,
    int? lastRestAt,
    int? createdAt,
  }) =>
      PlayerState(
        id: id ?? this.id,
        name: name ?? this.name,
        level: level ?? this.level,
        xp: xp ?? this.xp,
        health: health ?? this.health,
        stamina: stamina ?? this.stamina,
        inventory: inventory ?? this.inventory,
        equipment: equipment ?? this.equipment,
        stats: stats ?? this.stats,
        factionId: identical(factionId, _unset) ? this.factionId : factionId as FactionId?,
        lastRegenAt: lastRegenAt ?? this.lastRegenAt,
        lastRestAt: lastRestAt ?? this.lastRestAt,
        createdAt: createdAt ?? this.createdAt,
      );

  /// Lectura tolerante de una partida guardada (local o `player_saves.save`).
  /// Igual que `normalizePlayer` de la web: cada campo ausente o con tipo inválido
  /// toma el valor de un jugador nuevo creado en `now` (por defecto, ahora).
  factory PlayerState.fromJson(Map<String, dynamic> json, {int? now}) {
    final t = now ?? DateTime.now().millisecondsSinceEpoch;
    final inv = _map(json['inventory']);
    final eq = _map(json['equipment']);
    final st = _map(json['stats']);
    final fac = json['factionId'];
    return PlayerState(
      id: _str(json['id'], ''),
      name: _str(json['name'], ''),
      level: _int(json['level'], 1),
      xp: _int(json['xp'], 0),
      health: _dbl(json['health'], 100),
      stamina: _dbl(json['stamina'], 100),
      inventory: inv == null ? Map.of(starterInventory) : inventoryFromJson(inv),
      equipment: eq == null ? Equipment.empty : Equipment.fromJson(eq),
      stats: st == null ? const PlayerStats() : PlayerStats.fromJson(st),
      factionId: fac is String ? FactionId.tryFromKey(fac) : null,
      lastRegenAt: _int(json['lastRegenAt'], t),
      lastRestAt: _int(json['lastRestAt'], 0),
      createdAt: _int(json['createdAt'], t),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'level': level,
        'xp': xp,
        'health': jsonNum(health),
        'stamina': jsonNum(stamina),
        'inventory': inventoryToJson(inventory),
        'equipment': equipment.toJson(),
        'stats': stats.toJson(),
        'factionId': factionId?.key,
        'lastRegenAt': lastRegenAt,
        'lastRestAt': lastRestAt,
        'createdAt': createdAt,
      };

  @override
  bool operator ==(Object other) =>
      other is PlayerState &&
      other.id == id &&
      other.name == name &&
      other.level == level &&
      other.xp == xp &&
      other.health == health &&
      other.stamina == stamina &&
      deepMapEquals(other.inventory, inventory) &&
      other.equipment == equipment &&
      other.stats == stats &&
      other.factionId == factionId &&
      other.lastRegenAt == lastRegenAt &&
      other.lastRestAt == lastRestAt &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, name, level, xp, health, stamina, mapHash(inventory), equipment, stats,
      factionId, lastRegenAt, lastRestAt, createdAt);

  @override
  String toString() => 'PlayerState(${toJson()})';
}

// ---------------------------------------------------------------------------
// Zombies y combate
// ---------------------------------------------------------------------------

enum ZombieTypeId implements KeyedEnum {
  walker('walker'),
  runner('runner'),
  bloater('bloater'),
  screamer('screamer'),
  brute('brute');

  const ZombieTypeId(this.key);
  @override
  final String key;

  static final Map<String, ZombieTypeId> _byKey = {for (final v in values) v.key: v};
  static ZombieTypeId fromKey(String key) =>
      _byKey[key] ?? (throw ArgumentError.value(key, 'key', 'ZombieTypeId desconocido'));
  static ZombieTypeId? tryFromKey(String? key) => key == null ? null : _byKey[key];
}

enum ZombieAbility implements KeyedEnum {
  none('none'),
  doubleStrike('double_strike'),
  toxicBurst('toxic_burst'),
  callHorde('call_horde'),
  charge('charge');

  const ZombieAbility(this.key);
  @override
  final String key;

  static final Map<String, ZombieAbility> _byKey = {for (final v in values) v.key: v};
  static ZombieAbility fromKey(String key) =>
      _byKey[key] ?? (throw ArgumentError.value(key, 'key', 'ZombieAbility desconocida'));
  static ZombieAbility? tryFromKey(String? key) => key == null ? null : _byKey[key];
}

class LootEntry {
  const LootEntry({required this.itemId, required this.chance, required this.min, required this.max});

  final ItemId itemId;

  /// Probabilidad 0..1 de que aparezca esta entrada.
  final double chance;
  final int min;
  final int max;
}

class ZombieDef {
  const ZombieDef({
    required this.id,
    required this.name,
    required this.description,
    required this.baseHealth,
    required this.damage,
    required this.accuracy,
    required this.evasion,
    required this.fleeChance,
    required this.xp,
    required this.ability,
    required this.recommendedLevel,
    required this.spawnWeight,
    required this.loot,
  });

  final ZombieTypeId id;
  final String name;
  final String description;
  final int baseHealth;
  final IntRange damage;
  final double accuracy;
  final double evasion;

  /// Probabilidad base de huir con éxito de este zombie.
  final double fleeChance;
  final int xp;
  final ZombieAbility ability;

  /// Nivel recomendado; por debajo se marca como encuentro peligroso.
  final int recommendedLevel;
  final int spawnWeight;
  final List<LootEntry> loot;
}

/// Acción del jugador en un turno de combate.
///
/// `precision` (0..1, opcional) viene del minijuego de puntería/timing de la UI:
/// suma `(precision - 0.5) * 0.3` a la probabilidad de acertar y, si es >= 0.9,
/// el impacto es crítico garantizado ("headshot"). Con `null` el combate se
/// comporta exactamente como la versión web.
sealed class CombatAction {
  const CombatAction();

  const factory CombatAction.attack({double? precision}) = Attack;
  const factory CombatAction.heavy({double? precision}) = Heavy;
  const factory CombatAction.shoot({double? precision}) = Shoot;
  const factory CombatAction.defend() = Defend;
  const factory CombatAction.useItem(ItemId itemId) = UseItem;
  const factory CombatAction.flee() = Flee;

  /// Identificador de la acción en la versión web (`attack`, `use_item`...).
  String get type;
}

final class Attack extends CombatAction {
  const Attack({this.precision});
  final double? precision;
  @override
  String get type => 'attack';
}

final class Heavy extends CombatAction {
  const Heavy({this.precision});
  final double? precision;
  @override
  String get type => 'heavy';
}

final class Shoot extends CombatAction {
  const Shoot({this.precision});
  final double? precision;
  @override
  String get type => 'shoot';
}

final class Defend extends CombatAction {
  const Defend();
  @override
  String get type => 'defend';
}

final class UseItem extends CombatAction {
  const UseItem(this.itemId);
  final ItemId itemId;
  @override
  String get type => 'use_item';
}

final class Flee extends CombatAction {
  const Flee();
  @override
  String get type => 'flee';
}

/// Evento de combate (para animaciones, textos y registro).
///
/// Nota: el evento de defensa se llama [DefendEvent] para no chocar con la
/// acción [Defend].
sealed class CombatEvent {
  const CombatEvent();

  /// Identificador del evento en la versión web (`player_hit`, `zombie_miss`...).
  String get kind;

  Map<String, dynamic> toJson() => {'kind': kind};

  factory CombatEvent.fromJson(Map<String, dynamic> json) {
    bool b(String k) => json[k] == true;
    switch (json['kind']) {
      case 'player_hit':
        return PlayerHit(
          damage: _reqNum(json, 'damage').toInt(),
          crit: b('crit'),
          ranged: b('ranged'),
          stunBonus: b('stunBonus'),
          headshot: b('headshot'),
        );
      case 'player_miss':
        return PlayerMiss(ranged: b('ranged'));
      case 'exhausted':
        return const Exhausted();
      case 'no_ammo':
        return const NoAmmo();
      case 'defend':
        return DefendEvent(stamina: _reqNum(json, 'stamina').toDouble());
      case 'heal':
        return Heal(
          itemId: ItemId.fromKey(_reqStr(json, 'itemId')),
          health: _reqNum(json, 'health').toDouble(),
          stamina: _reqNum(json, 'stamina').toDouble(),
        );
      case 'flee_success':
        return const FleeSuccess();
      case 'flee_fail':
        return const FleeFail();
      case 'zombie_hit':
        return ZombieHit(
          damage: _reqNum(json, 'damage').toInt(),
          blocked: _reqNum(json, 'blocked').toInt(),
          charged: b('charged'),
        );
      case 'zombie_miss':
        return ZombieMiss(charged: b('charged'));
      case 'zombie_charge_prepare':
        return const ZombieChargePrepare();
      case 'zombie_stunned':
        return const ZombieStunned();
      case 'zombie_scream':
        return ZombieScream(healed: _reqNum(json, 'healed').toInt());
      case 'toxic_burst':
        return ToxicBurst(damage: _reqNum(json, 'damage').toDouble());
      case 'zombie_killed':
        return const ZombieKilled();
      case 'player_down':
        return const PlayerDown();
    }
    throw FormatException('Evento de combate desconocido', json);
  }

  @override
  String toString() => 'CombatEvent(${toJson()})';
}

final class PlayerHit extends CombatEvent {
  const PlayerHit({
    required this.damage,
    required this.crit,
    required this.ranged,
    required this.stunBonus,
    this.headshot = false,
  });

  final int damage;
  final bool crit;
  final bool ranged;
  final bool stunBonus;

  /// Crítico forzado por una precisión >= 0.9 del minijuego (extensión de la app).
  final bool headshot;

  @override
  String get kind => 'player_hit';

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'damage': damage,
        'crit': crit,
        'ranged': ranged,
        'stunBonus': stunBonus,
        if (headshot) 'headshot': true,
      };
}

final class PlayerMiss extends CombatEvent {
  const PlayerMiss({required this.ranged});
  final bool ranged;
  @override
  String get kind => 'player_miss';
  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'ranged': ranged};
}

final class Exhausted extends CombatEvent {
  const Exhausted();
  @override
  String get kind => 'exhausted';
}

final class NoAmmo extends CombatEvent {
  const NoAmmo();
  @override
  String get kind => 'no_ammo';
}

final class DefendEvent extends CombatEvent {
  const DefendEvent({required this.stamina});

  /// Resistencia recuperada al cubrirse.
  final double stamina;
  @override
  String get kind => 'defend';
  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'stamina': jsonNum(stamina)};
}

final class Heal extends CombatEvent {
  const Heal({required this.itemId, required this.health, required this.stamina});
  final ItemId itemId;
  final double health;
  final double stamina;
  @override
  String get kind => 'heal';
  @override
  Map<String, dynamic> toJson() =>
      {'kind': kind, 'itemId': itemId.key, 'health': jsonNum(health), 'stamina': jsonNum(stamina)};
}

final class FleeSuccess extends CombatEvent {
  const FleeSuccess();
  @override
  String get kind => 'flee_success';
}

final class FleeFail extends CombatEvent {
  const FleeFail();
  @override
  String get kind => 'flee_fail';
}

final class ZombieHit extends CombatEvent {
  const ZombieHit({required this.damage, required this.blocked, required this.charged});
  final int damage;
  final int blocked;
  final bool charged;
  @override
  String get kind => 'zombie_hit';
  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'damage': damage, 'blocked': blocked, 'charged': charged};
}

final class ZombieMiss extends CombatEvent {
  const ZombieMiss({required this.charged});
  final bool charged;
  @override
  String get kind => 'zombie_miss';
  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'charged': charged};
}

final class ZombieChargePrepare extends CombatEvent {
  const ZombieChargePrepare();
  @override
  String get kind => 'zombie_charge_prepare';
}

final class ZombieStunned extends CombatEvent {
  const ZombieStunned();
  @override
  String get kind => 'zombie_stunned';
}

final class ZombieScream extends CombatEvent {
  const ZombieScream({required this.healed});
  final int healed;
  @override
  String get kind => 'zombie_scream';
  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'healed': healed};
}

final class ToxicBurst extends CombatEvent {
  const ToxicBurst({required this.damage});
  final double damage;
  @override
  String get kind => 'toxic_burst';
  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'damage': jsonNum(damage)};
}

final class ZombieKilled extends CombatEvent {
  const ZombieKilled();
  @override
  String get kind => 'zombie_killed';
}

final class PlayerDown extends CombatEvent {
  const PlayerDown();
  @override
  String get kind => 'player_down';
}

enum CombatStatus implements KeyedEnum {
  ongoing('ongoing'),
  won('won'),
  lost('lost'),
  fled('fled');

  const CombatStatus(this.key);
  @override
  final String key;

  static final Map<String, CombatStatus> _byKey = {for (final v in values) v.key: v};
  static CombatStatus fromKey(String key) =>
      _byKey[key] ?? (throw ArgumentError.value(key, 'key', 'CombatStatus desconocido'));
  static CombatStatus? tryFromKey(String? key) => key == null ? null : _byKey[key];
}

class CombatZombie {
  const CombatZombie({
    required this.typeId,
    required this.name,
    required this.level,
    required this.health,
    required this.maxHealth,
    required this.damage,
    required this.accuracy,
    required this.evasion,
    required this.charging,
    required this.chargeIn,
    required this.stunned,
    required this.screamsLeft,
  });

  final ZombieTypeId typeId;
  final String name;
  final int level;
  final int health;
  final int maxHealth;
  final IntRange damage;
  final double accuracy;
  final double evasion;

  /// Prepara una embestida para el próximo turno (Bruto).
  final bool charging;

  /// Turnos propios que faltan para preparar la próxima embestida (Bruto).
  final int chargeIn;

  /// Aturdido: pierde su próximo turno y el siguiente golpe es crítico.
  final bool stunned;
  final int screamsLeft;

  CombatZombie copyWith({
    ZombieTypeId? typeId,
    String? name,
    int? level,
    int? health,
    int? maxHealth,
    IntRange? damage,
    double? accuracy,
    double? evasion,
    bool? charging,
    int? chargeIn,
    bool? stunned,
    int? screamsLeft,
  }) =>
      CombatZombie(
        typeId: typeId ?? this.typeId,
        name: name ?? this.name,
        level: level ?? this.level,
        health: health ?? this.health,
        maxHealth: maxHealth ?? this.maxHealth,
        damage: damage ?? this.damage,
        accuracy: accuracy ?? this.accuracy,
        evasion: evasion ?? this.evasion,
        charging: charging ?? this.charging,
        chargeIn: chargeIn ?? this.chargeIn,
        stunned: stunned ?? this.stunned,
        screamsLeft: screamsLeft ?? this.screamsLeft,
      );
}

class CombatPlayer {
  const CombatPlayer({
    required this.health,
    required this.maxHealth,
    required this.stamina,
    required this.maxStamina,
    required this.defending,
    required this.melee,
    required this.meleeName,
    required this.firearm,
    required this.firearmName,
    required this.defense,
  });

  final double health;
  final int maxHealth;
  final double stamina;
  final int maxStamina;
  final bool defending;
  final WeaponStats melee;
  final String meleeName;
  final WeaponStats? firearm;
  final String? firearmName;
  final int defense;

  CombatPlayer copyWith({
    double? health,
    int? maxHealth,
    double? stamina,
    int? maxStamina,
    bool? defending,
    WeaponStats? melee,
    String? meleeName,
    Object? firearm = _unset,
    Object? firearmName = _unset,
    int? defense,
  }) =>
      CombatPlayer(
        health: health ?? this.health,
        maxHealth: maxHealth ?? this.maxHealth,
        stamina: stamina ?? this.stamina,
        maxStamina: maxStamina ?? this.maxStamina,
        defending: defending ?? this.defending,
        melee: melee ?? this.melee,
        meleeName: meleeName ?? this.meleeName,
        firearm: identical(firearm, _unset) ? this.firearm : firearm as WeaponStats?,
        firearmName: identical(firearmName, _unset) ? this.firearmName : firearmName as String?,
        defense: defense ?? this.defense,
      );
}

class CombatState {
  const CombatState({
    required this.spawnId,
    required this.zombie,
    required this.player,
    required this.available,
    required this.consumed,
    required this.turn,
    required this.status,
    required this.lastEvents,
    required this.log,
    required this.xpMultiplier,
  });

  final String spawnId;
  final CombatZombie zombie;
  final CombatPlayer player;

  /// Copia de los objetos disponibles al iniciar (munición y consumibles).
  final Inventory available;

  /// Objetos gastados durante el combate; se descuentan al terminar.
  final Inventory consumed;
  final int turn;
  final CombatStatus status;

  /// Eventos del último turno (para animaciones y textos).
  final List<CombatEvent> lastEvents;

  /// Historial completo del encuentro.
  final List<CombatEvent> log;
  final double xpMultiplier;

  CombatState copyWith({
    String? spawnId,
    CombatZombie? zombie,
    CombatPlayer? player,
    Inventory? available,
    Inventory? consumed,
    int? turn,
    CombatStatus? status,
    List<CombatEvent>? lastEvents,
    List<CombatEvent>? log,
    double? xpMultiplier,
  }) =>
      CombatState(
        spawnId: spawnId ?? this.spawnId,
        zombie: zombie ?? this.zombie,
        player: player ?? this.player,
        available: available ?? this.available,
        consumed: consumed ?? this.consumed,
        turn: turn ?? this.turn,
        status: status ?? this.status,
        lastEvents: lastEvents ?? this.lastEvents,
        log: log ?? this.log,
        xpMultiplier: xpMultiplier ?? this.xpMultiplier,
      );
}

class Reward {
  const Reward({required this.xp, required this.items});
  final int xp;
  final Inventory items;
}

// ---------------------------------------------------------------------------
// Mundo, spawns y zonas
// ---------------------------------------------------------------------------

/// Tipos de suministro, en el mismo orden que el registro `SUPPLIES` de la web
/// (ese orden afecta a la generación determinística del mundo).
enum SupplyTypeId implements KeyedEnum {
  backpack('backpack'),
  car('car'),
  debris('debris'),
  grocery('grocery'),
  pharmacy('pharmacy'),
  hardware('hardware'),
  military('military');

  const SupplyTypeId(this.key);
  @override
  final String key;

  static final Map<String, SupplyTypeId> _byKey = {for (final v in values) v.key: v};
  static SupplyTypeId fromKey(String key) =>
      _byKey[key] ?? (throw ArgumentError.value(key, 'key', 'SupplyTypeId desconocido'));
  static SupplyTypeId? tryFromKey(String? key) => key == null ? null : _byKey[key];
}

class SupplyDef {
  const SupplyDef({
    required this.id,
    required this.name,
    required this.description,
    required this.rarity,
    required this.spawnWeight,
    required this.rolls,
    required this.loot,
    required this.staminaCost,
    required this.xp,
  });

  final SupplyTypeId id;
  final String name;
  final String description;
  final Rarity rarity;
  final int spawnWeight;

  /// Rolls de botín: cuántas pasadas por la tabla se sortean.
  final IntRange rolls;
  final List<LootEntry> loot;
  final int staminaCost;
  final int xp;
}

enum PlacementState implements KeyedEnum {
  raw('raw'),
  snapped('snapped');

  const PlacementState(this.key);
  @override
  final String key;

  static final Map<String, PlacementState> _byKey = {for (final v in values) v.key: v};
  static PlacementState fromKey(String key) =>
      _byKey[key] ?? (throw ArgumentError.value(key, 'key', 'PlacementState desconocido'));
  static PlacementState? tryFromKey(String? key) => key == null ? null : _byKey[key];
}

/// Punto del mapa: un zombie o un suministro.
sealed class Spawn {
  const Spawn({
    required this.id,
    required this.cellId,
    required this.position,
    required this.expiresAt,
    required this.placement,
  });

  final String id;
  final String cellId;
  final LatLng position;
  final int expiresAt;
  final PlacementState placement;

  /// `zombie` o `supply` (campo `kind` del JSON).
  String get kind;

  /// Copia con otra posición/estado de ubicación (lo usa `placeSpawns`).
  Spawn withPlacement(LatLng position, PlacementState placement);

  Map<String, dynamic> toJson();

  factory Spawn.fromJson(Map<String, dynamic> json) => switch (json['kind']) {
        'zombie' => ZombieSpawn.fromJson(json),
        'supply' => SupplySpawn.fromJson(json),
        _ => throw FormatException('Spawn desconocido', json),
      };
}

final class ZombieSpawn extends Spawn {
  const ZombieSpawn({
    required super.id,
    required super.cellId,
    required super.position,
    required this.zombieType,
    required super.expiresAt,
    required super.placement,
  });

  final ZombieTypeId zombieType;

  @override
  String get kind => 'zombie';

  ZombieSpawn copyWith({
    String? id,
    String? cellId,
    LatLng? position,
    ZombieTypeId? zombieType,
    int? expiresAt,
    PlacementState? placement,
  }) =>
      ZombieSpawn(
        id: id ?? this.id,
        cellId: cellId ?? this.cellId,
        position: position ?? this.position,
        zombieType: zombieType ?? this.zombieType,
        expiresAt: expiresAt ?? this.expiresAt,
        placement: placement ?? this.placement,
      );

  @override
  ZombieSpawn withPlacement(LatLng position, PlacementState placement) =>
      copyWith(position: position, placement: placement);

  factory ZombieSpawn.fromJson(Map<String, dynamic> json) => ZombieSpawn(
        id: _reqStr(json, 'id'),
        cellId: _reqStr(json, 'cellId'),
        position: LatLng.fromJson(_map(json['position']) ?? const {}),
        zombieType: ZombieTypeId.fromKey(_reqStr(json, 'zombieType')),
        expiresAt: _reqNum(json, 'expiresAt').toInt(),
        placement: PlacementState.tryFromKey(_strOrNull(json['placement'])) ?? PlacementState.raw,
      );

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'id': id,
        'cellId': cellId,
        'position': position.toJson(),
        'zombieType': zombieType.key,
        'expiresAt': expiresAt,
        'placement': placement.key,
      };

  @override
  bool operator ==(Object other) =>
      other is ZombieSpawn &&
      other.id == id &&
      other.cellId == cellId &&
      other.position == position &&
      other.zombieType == zombieType &&
      other.expiresAt == expiresAt &&
      other.placement == placement;

  @override
  int get hashCode => Object.hash(kind, id, cellId, position, zombieType, expiresAt, placement);

  @override
  String toString() => 'ZombieSpawn(${toJson()})';
}

final class SupplySpawn extends Spawn {
  const SupplySpawn({
    required super.id,
    required super.cellId,
    required super.position,
    required this.supplyType,
    required super.expiresAt,
    required super.placement,
  });

  final SupplyTypeId supplyType;

  @override
  String get kind => 'supply';

  SupplySpawn copyWith({
    String? id,
    String? cellId,
    LatLng? position,
    SupplyTypeId? supplyType,
    int? expiresAt,
    PlacementState? placement,
  }) =>
      SupplySpawn(
        id: id ?? this.id,
        cellId: cellId ?? this.cellId,
        position: position ?? this.position,
        supplyType: supplyType ?? this.supplyType,
        expiresAt: expiresAt ?? this.expiresAt,
        placement: placement ?? this.placement,
      );

  @override
  SupplySpawn withPlacement(LatLng position, PlacementState placement) =>
      copyWith(position: position, placement: placement);

  factory SupplySpawn.fromJson(Map<String, dynamic> json) => SupplySpawn(
        id: _reqStr(json, 'id'),
        cellId: _reqStr(json, 'cellId'),
        position: LatLng.fromJson(_map(json['position']) ?? const {}),
        supplyType: SupplyTypeId.fromKey(_reqStr(json, 'supplyType')),
        expiresAt: _reqNum(json, 'expiresAt').toInt(),
        placement: PlacementState.tryFromKey(_strOrNull(json['placement'])) ?? PlacementState.raw,
      );

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'id': id,
        'cellId': cellId,
        'position': position.toJson(),
        'supplyType': supplyType.key,
        'expiresAt': expiresAt,
        'placement': placement.key,
      };

  @override
  bool operator ==(Object other) =>
      other is SupplySpawn &&
      other.id == id &&
      other.cellId == cellId &&
      other.position == position &&
      other.supplyType == supplyType &&
      other.expiresAt == expiresAt &&
      other.placement == placement;

  @override
  int get hashCode => Object.hash(kind, id, cellId, position, supplyType, expiresAt, placement);

  @override
  String toString() => 'SupplySpawn(${toJson()})';
}

enum ZoneThreat implements KeyedEnum {
  calm('calm'),
  infested('infested');

  const ZoneThreat(this.key);
  @override
  final String key;

  static final Map<String, ZoneThreat> _byKey = {for (final v in values) v.key: v};
  static ZoneThreat fromKey(String key) =>
      _byKey[key] ?? (throw ArgumentError.value(key, 'key', 'ZoneThreat desconocida'));
  static ZoneThreat? tryFromKey(String? key) => key == null ? null : _byKey[key];
}

class Zone {
  const Zone({required this.cellId, required this.threat, required this.bounds});

  final String cellId;
  final ZoneThreat threat;

  /// Esquinas SO y NE de la celda.
  final CellBounds bounds;

  factory Zone.fromJson(Map<String, dynamic> json) {
    final b = json['bounds'];
    if (b is! List || b.length != 2) throw FormatException('Zona sin bounds', json);
    return Zone(
      cellId: _reqStr(json, 'cellId'),
      threat: ZoneThreat.fromKey(_reqStr(json, 'threat')),
      bounds: (sw: LatLng.fromJson(_map(b[0]) ?? const {}), ne: LatLng.fromJson(_map(b[1]) ?? const {})),
    );
  }

  Map<String, dynamic> toJson() => {
        'cellId': cellId,
        'threat': threat.key,
        'bounds': [bounds.sw.toJson(), bounds.ne.toJson()],
      };

  @override
  bool operator ==(Object other) =>
      other is Zone && other.cellId == cellId && other.threat == threat && other.bounds == bounds;

  @override
  int get hashCode => Object.hash(cellId, threat, bounds);
}

// ---------------------------------------------------------------------------
// Refugios y comunidad
// ---------------------------------------------------------------------------

class ShelterContribution {
  const ShelterContribution({required this.playerId, required this.playerName, required this.amount});

  final String playerId;
  final String playerName;
  final int amount;

  ShelterContribution copyWith({String? playerId, String? playerName, int? amount}) => ShelterContribution(
        playerId: playerId ?? this.playerId,
        playerName: playerName ?? this.playerName,
        amount: amount ?? this.amount,
      );

  factory ShelterContribution.fromJson(Map<String, dynamic> json) => ShelterContribution(
        playerId: _str(json['playerId'], ''),
        playerName: _str(json['playerName'], ''),
        amount: _int(json['amount'], 0),
      );

  Map<String, dynamic> toJson() => {'playerId': playerId, 'playerName': playerName, 'amount': amount};

  @override
  bool operator ==(Object other) =>
      other is ShelterContribution &&
      other.playerId == playerId &&
      other.playerName == playerName &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(playerId, playerName, amount);

  @override
  String toString() => 'ShelterContribution(${toJson()})';
}

class Shelter {
  const Shelter({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.ownerName,
    required this.factionId,
    required this.level,
    required this.position,
    required this.progress,
    required this.contributions,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String ownerId;
  final String ownerName;
  final FactionId? factionId;
  final int level;

  /// Posición PÚBLICA (ajustada a la grilla y a la calle); nunca la ubicación real del creador.
  final LatLng position;

  /// Recursos aportados hacia el próximo nivel (solo recursos básicos).
  final Inventory progress;
  final List<ShelterContribution> contributions;
  final int createdAt;

  /// `factionId` se puede borrar pasando `null` explícitamente.
  Shelter copyWith({
    String? id,
    String? name,
    String? ownerId,
    String? ownerName,
    Object? factionId = _unset,
    int? level,
    LatLng? position,
    Inventory? progress,
    List<ShelterContribution>? contributions,
    int? createdAt,
  }) =>
      Shelter(
        id: id ?? this.id,
        name: name ?? this.name,
        ownerId: ownerId ?? this.ownerId,
        ownerName: ownerName ?? this.ownerName,
        factionId: identical(factionId, _unset) ? this.factionId : factionId as FactionId?,
        level: level ?? this.level,
        position: position ?? this.position,
        progress: progress ?? this.progress,
        contributions: contributions ?? this.contributions,
        createdAt: createdAt ?? this.createdAt,
      );

  factory Shelter.fromJson(Map<String, dynamic> json) {
    final contribs = json['contributions'];
    return Shelter(
      id: _reqStr(json, 'id'),
      name: _str(json['name'], ''),
      ownerId: _str(json['ownerId'], ''),
      ownerName: _str(json['ownerName'], ''),
      factionId: FactionId.tryFromKey(_strOrNull(json['factionId'])),
      level: _int(json['level'], 1),
      position: LatLng.fromJson(_map(json['position']) ?? const {}),
      progress: inventoryFromJson(json['progress']),
      contributions: contribs is List
          ? [
              for (final c in contribs)
                if (_map(c) case final m?) ShelterContribution.fromJson(m),
            ]
          : const [],
      createdAt: _int(json['createdAt'], 0),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ownerId': ownerId,
        'ownerName': ownerName,
        'factionId': factionId?.key,
        'level': level,
        'position': position.toJson(),
        'progress': inventoryToJson(progress),
        'contributions': [for (final c in contributions) c.toJson()],
        'createdAt': createdAt,
      };

  @override
  bool operator ==(Object other) =>
      other is Shelter &&
      other.id == id &&
      other.name == name &&
      other.ownerId == ownerId &&
      other.ownerName == ownerName &&
      other.factionId == factionId &&
      other.level == level &&
      other.position == position &&
      deepMapEquals(other.progress, progress) &&
      deepListEquals(other.contributions, contributions) &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, name, ownerId, ownerName, factionId, level, position, mapHash(progress),
      Object.hashAll(contributions), createdAt);

  @override
  String toString() => 'Shelter(${toJson()})';
}

class Faction {
  const Faction({
    required this.id,
    required this.name,
    required this.motto,
    required this.color,
    required this.bonusDescription,
    required this.members,
    required this.totalContribution,
  });

  final FactionId id;
  final String name;
  final String motto;

  /// Color en hexadecimal CSS (`#c8742c`).
  final String color;
  final String bonusDescription;
  final int members;
  final int totalContribution;

  Faction copyWith({
    FactionId? id,
    String? name,
    String? motto,
    String? color,
    String? bonusDescription,
    int? members,
    int? totalContribution,
  }) =>
      Faction(
        id: id ?? this.id,
        name: name ?? this.name,
        motto: motto ?? this.motto,
        color: color ?? this.color,
        bonusDescription: bonusDescription ?? this.bonusDescription,
        members: members ?? this.members,
        totalContribution: totalContribution ?? this.totalContribution,
      );

  factory Faction.fromJson(Map<String, dynamic> json) => Faction(
        id: FactionId.fromKey(_reqStr(json, 'id')),
        name: _str(json['name'], ''),
        motto: _str(json['motto'], ''),
        color: _str(json['color'], ''),
        bonusDescription: _str(json['bonusDescription'], ''),
        members: _int(json['members'], 0),
        totalContribution: _int(json['totalContribution'], 0),
      );

  Map<String, dynamic> toJson() => {
        'id': id.key,
        'name': name,
        'motto': motto,
        'color': color,
        'bonusDescription': bonusDescription,
        'members': members,
        'totalContribution': totalContribution,
      };

  @override
  bool operator ==(Object other) =>
      other is Faction &&
      other.id == id &&
      other.name == name &&
      other.motto == motto &&
      other.color == color &&
      other.bonusDescription == bonusDescription &&
      other.members == members &&
      other.totalContribution == totalContribution;

  @override
  int get hashCode => Object.hash(id, name, motto, color, bonusDescription, members, totalContribution);
}

class PublicSurvivor {
  const PublicSurvivor({
    required this.id,
    required this.name,
    required this.level,
    required this.factionId,
    required this.approxPosition,
    required this.lastSeenAt,
  });

  final String id;
  final String name;
  final int level;
  final FactionId? factionId;

  /// Posición aproximada (difuminada) — nunca la exacta.
  final LatLng approxPosition;
  final int lastSeenAt;

  PublicSurvivor copyWith({
    String? id,
    String? name,
    int? level,
    Object? factionId = _unset,
    LatLng? approxPosition,
    int? lastSeenAt,
  }) =>
      PublicSurvivor(
        id: id ?? this.id,
        name: name ?? this.name,
        level: level ?? this.level,
        factionId: identical(factionId, _unset) ? this.factionId : factionId as FactionId?,
        approxPosition: approxPosition ?? this.approxPosition,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      );

  factory PublicSurvivor.fromJson(Map<String, dynamic> json) => PublicSurvivor(
        id: _reqStr(json, 'id'),
        name: _str(json['name'], ''),
        level: _int(json['level'], 1),
        factionId: FactionId.tryFromKey(_strOrNull(json['factionId'])),
        approxPosition: LatLng.fromJson(_map(json['approxPosition']) ?? const {}),
        lastSeenAt: _int(json['lastSeenAt'], 0),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'level': level,
        'factionId': factionId?.key,
        'approxPosition': approxPosition.toJson(),
        'lastSeenAt': lastSeenAt,
      };

  @override
  bool operator ==(Object other) =>
      other is PublicSurvivor &&
      other.id == id &&
      other.name == name &&
      other.level == level &&
      other.factionId == factionId &&
      other.approxPosition == approxPosition &&
      other.lastSeenAt == lastSeenAt;

  @override
  int get hashCode => Object.hash(id, name, level, factionId, approxPosition, lastSeenAt);
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.playerId,
    required this.playerName,
    required this.factionId,
    required this.level,
    required this.contribution,
  });

  final String playerId;
  final String playerName;
  final FactionId? factionId;
  final int level;
  final int contribution;

  LeaderboardEntry copyWith({
    String? playerId,
    String? playerName,
    Object? factionId = _unset,
    int? level,
    int? contribution,
  }) =>
      LeaderboardEntry(
        playerId: playerId ?? this.playerId,
        playerName: playerName ?? this.playerName,
        factionId: identical(factionId, _unset) ? this.factionId : factionId as FactionId?,
        level: level ?? this.level,
        contribution: contribution ?? this.contribution,
      );

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) => LeaderboardEntry(
        playerId: _reqStr(json, 'playerId'),
        playerName: _str(json['playerName'], ''),
        factionId: FactionId.tryFromKey(_strOrNull(json['factionId'])),
        level: _int(json['level'], 1),
        contribution: _int(json['contribution'], 0),
      );

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'playerName': playerName,
        'factionId': factionId?.key,
        'level': level,
        'contribution': contribution,
      };

  @override
  bool operator ==(Object other) =>
      other is LeaderboardEntry &&
      other.playerId == playerId &&
      other.playerName == playerName &&
      other.factionId == factionId &&
      other.level == level &&
      other.contribution == contribution;

  @override
  int get hashCode => Object.hash(playerId, playerName, factionId, level, contribution);
}

// ---------------------------------------------------------------------------
// Validación de interacciones (preparado para servidor)
// ---------------------------------------------------------------------------

/// Tipo de interacción: solo `scavenge` reclama el punto (lo agota para ese jugador).
enum InteractionAction implements KeyedEnum {
  scavenge('scavenge'),
  encounter('encounter'),
  shelter('shelter');

  const InteractionAction(this.key);
  @override
  final String key;

  static final Map<String, InteractionAction> _byKey = {for (final v in values) v.key: v};
  static InteractionAction fromKey(String key) =>
      _byKey[key] ?? (throw ArgumentError.value(key, 'key', 'InteractionAction desconocida'));
  static InteractionAction? tryFromKey(String? key) => key == null ? null : _byKey[key];
}

class InteractionRequest {
  const InteractionRequest({
    required this.playerId,
    required this.action,
    required this.targetId,
    this.targetExpiresAt,
    required this.targetPosition,
    required this.playerPosition,
    required this.accuracyM,
    required this.timestamp,
  });

  final String playerId;
  final InteractionAction action;
  final String targetId;

  /// Vencimiento del spawn (ms), si aplica.
  final int? targetExpiresAt;
  final LatLng targetPosition;
  final LatLng playerPosition;
  final double accuracyM;
  final int timestamp;

  InteractionRequest copyWith({
    String? playerId,
    InteractionAction? action,
    String? targetId,
    Object? targetExpiresAt = _unset,
    LatLng? targetPosition,
    LatLng? playerPosition,
    double? accuracyM,
    int? timestamp,
  }) =>
      InteractionRequest(
        playerId: playerId ?? this.playerId,
        action: action ?? this.action,
        targetId: targetId ?? this.targetId,
        targetExpiresAt: identical(targetExpiresAt, _unset) ? this.targetExpiresAt : targetExpiresAt as int?,
        targetPosition: targetPosition ?? this.targetPosition,
        playerPosition: playerPosition ?? this.playerPosition,
        accuracyM: accuracyM ?? this.accuracyM,
        timestamp: timestamp ?? this.timestamp,
      );

  factory InteractionRequest.fromJson(Map<String, dynamic> json) => InteractionRequest(
        playerId: _reqStr(json, 'playerId'),
        action: InteractionAction.fromKey(_reqStr(json, 'action')),
        targetId: _reqStr(json, 'targetId'),
        targetExpiresAt: _numOrNull(json['targetExpiresAt'])?.toInt(),
        targetPosition: LatLng.fromJson(_map(json['targetPosition']) ?? const {}),
        playerPosition: LatLng.fromJson(_map(json['playerPosition']) ?? const {}),
        accuracyM: _reqNum(json, 'accuracyM').toDouble(),
        timestamp: _reqNum(json, 'timestamp').toInt(),
      );

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'action': action.key,
        'targetId': targetId,
        if (targetExpiresAt != null) 'targetExpiresAt': targetExpiresAt,
        'targetPosition': targetPosition.toJson(),
        'playerPosition': playerPosition.toJson(),
        'accuracyM': jsonNum(accuracyM),
        'timestamp': timestamp,
      };

  @override
  bool operator ==(Object other) =>
      other is InteractionRequest &&
      other.playerId == playerId &&
      other.action == action &&
      other.targetId == targetId &&
      other.targetExpiresAt == targetExpiresAt &&
      other.targetPosition == targetPosition &&
      other.playerPosition == playerPosition &&
      other.accuracyM == accuracyM &&
      other.timestamp == timestamp;

  @override
  int get hashCode =>
      Object.hash(playerId, action, targetId, targetExpiresAt, targetPosition, playerPosition, accuracyM, timestamp);
}

enum InteractionRejection implements KeyedEnum {
  outOfRange('out_of_range'),
  tooFast('too_fast'),
  depleted('depleted'),
  expired('expired'),
  lowAccuracy('low_accuracy');

  const InteractionRejection(this.key);
  @override
  final String key;

  static final Map<String, InteractionRejection> _byKey = {for (final v in values) v.key: v};
  static InteractionRejection fromKey(String key) =>
      _byKey[key] ?? (throw ArgumentError.value(key, 'key', 'InteractionRejection desconocido'));
  static InteractionRejection? tryFromKey(String? key) => key == null ? null : _byKey[key];
}

class InteractionResult {
  const InteractionResult({required this.ok, this.reason, required this.distanceM});

  final bool ok;
  final InteractionRejection? reason;
  final double distanceM;

  factory InteractionResult.fromJson(Map<String, dynamic> json) => InteractionResult(
        ok: json['ok'] == true,
        reason: InteractionRejection.tryFromKey(_strOrNull(json['reason'])),
        distanceM: _dbl(json['distanceM'], 0),
      );

  Map<String, dynamic> toJson() => {
        'ok': ok,
        if (reason != null) 'reason': reason!.key,
        'distanceM': jsonNum(distanceM),
      };

  @override
  bool operator ==(Object other) =>
      other is InteractionResult && other.ok == ok && other.reason == reason && other.distanceM == distanceM;

  @override
  int get hashCode => Object.hash(ok, reason, distanceM);

  @override
  String toString() => 'InteractionResult(${toJson()})';
}
