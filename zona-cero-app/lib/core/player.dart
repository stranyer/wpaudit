// Operaciones puras sobre el estado del jugador. Todas devuelven un estado nuevo.

import 'dart:math' as math;

import 'factions.dart';
import 'inventory.dart';
import 'items.dart';
import 'progression.dart';
import 'shelter.dart';
import 'types.dart';
import 'utils.dart';

PlayerState createPlayer(String id, String name, int now) => PlayerState(
      id: id,
      name: name,
      level: 1,
      xp: 0,
      health: maxHealthForLevel(1).toDouble(),
      stamina: maxStaminaForLevel(1).toDouble(),
      inventory: Map.of(starterInventory),
      equipment: Equipment.empty,
      stats: const PlayerStats(),
      factionId: null,
      lastRegenAt: now,
      lastRestAt: 0,
      createdAt: now,
    );

int maxHealth(PlayerState p) => maxHealthForLevel(p.level);
int maxStamina(PlayerState p) => maxStaminaForLevel(p.level);
int capacityOf(PlayerState p) => carryCapacity(p.level);

/// Atributos derivados del jugador, como getters (atajo para la UI).
extension PlayerDerived on PlayerState {
  int get maxHealth => maxHealthForLevel(level);
  int get maxStamina => maxStaminaForLevel(level);

  /// Capacidad de la mochila.
  int get capacity => carryCapacity(level);

  /// Peso que carga en la mochila.
  int get carried => carriedWeight(inventory);
}

class RegenConfig {
  const RegenConfig({required this.staminaPerMinute, required this.healthPerMinute, required this.healthPassiveCap});
  final double staminaPerMinute;
  final double healthPerMinute;

  /// La salud solo se regenera sola hasta esta fracción del máximo.
  final double healthPassiveCap;
}

/// Regeneración pasiva desde `lastRegenAt` (máximo 8 horas acumuladas).
PlayerState applyRegen(PlayerState p, int now, RegenConfig cfg) {
  final elapsedMin = math.min(8 * 60, math.max(0, now - p.lastRegenAt) / 60000);
  if (elapsedMin <= 0) return p;
  final mods = factionModifiers(p.factionId);
  final maxH = maxHealth(p);
  final maxS = maxStamina(p);
  final stamina = clampDouble(p.stamina + elapsedMin * cfg.staminaPerMinute * mods.staminaRegen, 0, maxS);
  final healthCap = math.max(p.health, maxH * cfg.healthPassiveCap);
  final health = clampDouble(p.health + elapsedMin * cfg.healthPerMinute, 0, healthCap);
  return p.copyWith(stamina: stamina, health: health, lastRegenAt: now);
}

class XpGain {
  const XpGain({required this.player, required this.levelsGained});
  final PlayerState player;
  final int levelsGained;
}

/// Suma XP; al subir de nivel se recupera toda la salud y resistencia.
XpGain grantXp(PlayerState p, num amount) {
  final r = addXp(p.level, p.xp, amount);
  if (r.levelsGained == 0) return XpGain(player: p.copyWith(xp: r.xp), levelsGained: 0);
  final leveled = p.copyWith(level: r.level, xp: r.xp);
  return XpGain(
    player: leveled.copyWith(
      health: maxHealth(leveled).toDouble(),
      stamina: maxStamina(leveled).toDouble(),
    ),
    levelsGained: r.levelsGained,
  );
}

class LootGain {
  const LootGain({required this.player, required this.added, required this.overflow});
  final PlayerState player;
  final Inventory added;
  final Inventory overflow;
}

LootGain giveItems(PlayerState p, Inventory items) {
  final r = addItems(p.inventory, items, capacity: capacityOf(p));
  return LootGain(player: p.copyWith(inventory: r.inventory), added: r.added, overflow: r.overflow);
}

PlayerState? takeItems(PlayerState p, Inventory items) {
  final inv = removeItems(p.inventory, items);
  if (inv == null) return null;
  return _unequipMissing(p.copyWith(inventory: inv));
}

/// Consume un objeto con efectos (comida, agua, medicina...).
PlayerState? consumeItem(PlayerState p, ItemId itemId) {
  final effects = itemDefs[itemId]!.effects;
  if (effects == null || countOf(p.inventory, itemId) <= 0) return null;
  final after = takeItems(p, {itemId: 1});
  if (after == null) return null;
  return after.copyWith(
    health: clampDouble(after.health + (effects.health ?? 0), 0, maxHealth(after)),
    stamina: clampDouble(after.stamina + (effects.stamina ?? 0), 0, maxStamina(after)),
  );
}

EquipmentSlot? slotFor(ItemId itemId) {
  final def = itemDefs[itemId]!;
  if (def.armor != null) return EquipmentSlot.armor;
  final weapon = def.weapon;
  if (weapon != null) return weapon.ammoPerShot > 0 ? EquipmentSlot.firearm : EquipmentSlot.melee;
  return null;
}

PlayerState? equipItem(PlayerState p, ItemId itemId) {
  final slot = slotFor(itemId);
  if (slot == null || countOf(p.inventory, itemId) <= 0) return null;
  return p.copyWith(equipment: p.equipment.withSlot(slot, itemId));
}

PlayerState unequipSlot(PlayerState p, EquipmentSlot slot) =>
    p.copyWith(equipment: p.equipment.withSlot(slot, null));

/// Si un objeto equipado ya no está en el inventario, se desequipa.
PlayerState _unequipMissing(PlayerState p) {
  var eq = p.equipment;
  for (final slot in EquipmentSlot.values) {
    final id = eq[slot];
    if (id != null && countOf(p.inventory, id) <= 0) eq = eq.withSlot(slot, null);
  }
  return identical(eq, p.equipment) ? p : p.copyWith(equipment: eq);
}

int armorDefense(PlayerState p) {
  final armor = p.equipment.armor;
  return armor == null ? 0 : (itemDefs[armor]!.armor?.defense ?? 0);
}

class DeathConfig {
  const DeathConfig({required this.healthRestoreRatio, required this.staminaRestore, required this.resourceLossRatio});
  final double healthRestoreRatio;
  final double staminaRestore;
  final double resourceLossRatio;
}

class DeathResult {
  const DeathResult({required this.player, required this.lost});
  final PlayerState player;
  final Inventory lost;
}

/// Al caer: se pierde una parte de cada recurso y se reaparece debilitado.
DeathResult applyDeathPenalty(PlayerState p, DeathConfig cfg) {
  final lost = <ItemId, int>{};
  for (final e in entries(p.inventory)) {
    if (!isResource(e.key)) continue;
    final loss = (e.value * cfg.resourceLossRatio).floor();
    if (loss > 0) lost[e.key] = loss;
  }
  final inventory = removeItems(p.inventory, lost) ?? p.inventory;
  return DeathResult(
    player: p.copyWith(
      inventory: inventory,
      health: jsRound(maxHealth(p) * cfg.healthRestoreRatio).toDouble(),
      stamina: math.min(maxStamina(p), cfg.staminaRestore).toDouble(),
      stats: p.stats.copyWith(deaths: p.stats.deaths + 1),
    ),
    lost: lost,
  );
}

class RestResult {
  const RestResult({required this.player, required this.ok, required this.cooldownLeftMs});
  final PlayerState player;
  final bool ok;
  final int cooldownLeftMs;
}

/// Descansar en un refugio: recupera según el nivel, con enfriamiento.
RestResult restAtShelter(PlayerState p, int shelterLevel, int now) {
  final left = p.lastRestAt + restCooldownMs - now;
  if (left > 0) return RestResult(player: p, ok: false, cooldownLeftMs: left);
  final def = shelterLevelDef(shelterLevel);
  return RestResult(
    player: p.copyWith(
      health: clampDouble(p.health + def.restHealth, 0, maxHealth(p)),
      stamina: clampDouble(p.stamina + def.restStamina, 0, maxStamina(p)),
      lastRestAt: now,
    ),
    ok: true,
    cooldownLeftMs: 0,
  );
}
