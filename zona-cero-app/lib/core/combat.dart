// Motor de combate por turnos. Puro y determinístico dado un RNG:
// el mismo RNG + mismas acciones = mismo resultado (útil para tests y para
// validarlo en un servidor en el futuro).

import 'dart:math' as math;

import 'balance.dart';
import 'factions.dart';
import 'inventory.dart';
import 'items.dart';
import 'loot.dart';
import 'player.dart';
import 'rng.dart';
import 'types.dart';
import 'utils.dart';
import 'zombies.dart';

const double _critMultiplier = 1.75;
const double _exhaustedDamage = 0.6;
const double _exhaustedAccuracy = 0.25;
const double _defendDamage = 0.4;
const int _defendStamina = 12;
const double _chargeMultiplier = 1.8;

/// Ataques normales del Bruto entre embestidas.
const int _chargeEvery = 3;

WeaponStats? _weaponOf(ItemId? id) => id == null ? null : itemDefs[id]!.weapon;

/// Inicia un encuentro contra un zombie del tipo `zombieType`.
CombatState startCombat({
  required String spawnId,
  required ZombieTypeId zombieType,
  required PlayerState player,
  required Rng rng,
}) {
  final def = zombieDefs[zombieType]!;
  // Los tipos avanzados nunca aparecen muy por debajo de su nivel recomendado:
  // un Bruto sigue siendo peligroso aunque el jugador sea novato.
  final roll = rng.intRange(-1, 1);
  final level = math.max(math.max(1, def.recommendedLevel - 1), player.level + roll);
  final hp = zombieHealthForLevel(def, level);
  final meleeId = player.equipment.melee;
  final firearmId = player.equipment.firearm;
  final available = <ItemId, int>{};
  for (final id in player.inventory.keys) {
    if (id == ItemId.ammo || itemDefs[id]!.effects != null) available[id] = countOf(player.inventory, id);
  }
  return CombatState(
    spawnId: spawnId,
    zombie: CombatZombie(
      typeId: zombieType,
      name: def.name,
      level: level,
      health: hp,
      maxHealth: hp,
      damage: zombieDamageForLevel(def, level),
      accuracy: def.accuracy,
      evasion: def.evasion,
      charging: false,
      chargeIn: _chargeEvery,
      stunned: false,
      screamsLeft: def.ability == ZombieAbility.callHorde ? 2 : 0,
    ),
    player: CombatPlayer(
      health: player.health,
      maxHealth: maxHealth(player),
      stamina: player.stamina,
      maxStamina: maxStamina(player),
      defending: false,
      melee: _weaponOf(meleeId) ?? fists,
      meleeName: meleeId != null ? itemDefs[meleeId]!.name : 'Puños',
      firearm: _weaponOf(firearmId),
      firearmName: firearmId != null ? itemDefs[firearmId]!.name : null,
      defense: armorDefense(player),
    ),
    available: available,
    consumed: const {},
    turn: 1,
    status: CombatStatus.ongoing,
    lastEvents: const [],
    log: const [],
    xpMultiplier: factionModifiers(player.factionId).combatXp,
  );
}

/// Cantidad disponible de un objeto descontando lo gastado en el combate.
int remainingInCombat(CombatState state, ItemId id) => countOf(state.available, id) - countOf(state.consumed, id);

bool canShoot(CombatState state) {
  final fa = state.player.firearm;
  return fa != null && remainingInCombat(state, ItemId.ammo) >= fa.ammoPerShot;
}

/// Objetos que se pueden usar durante el combate.
List<ItemId> usableItems(CombatState state) => [
      for (final id in state.available.keys)
        if (itemDefs[id]!.effects != null && remainingInCombat(state, id) > 0) id,
    ];

int _rollDamage(IntRange range, Rng rng) => rng.intRange(range.min, range.max);

/// Estado mutable de un turno en resolución (se vuelca a un [CombatState] nuevo al final).
class _Turn {
  _Turn(CombatState prev, this.rng)
      : def = zombieDefs[prev.zombie.typeId]!,
        zombie = prev.zombie,
        zHealth = prev.zombie.health,
        zCharging = prev.zombie.charging,
        zChargeIn = prev.zombie.chargeIn,
        zStunned = prev.zombie.stunned,
        zScreamsLeft = prev.zombie.screamsLeft,
        player = prev.player,
        pHealth = prev.player.health,
        pStamina = prev.player.stamina,
        consumed = Map.of(prev.consumed),
        available = prev.available,
        status = prev.status;

  final Rng rng;
  final ZombieDef def;
  final CombatZombie zombie;
  final CombatPlayer player;
  final Inventory available;
  final Inventory consumed;
  final List<CombatEvent> events = [];

  int zHealth;
  bool zCharging;
  int zChargeIn;
  bool zStunned;
  int zScreamsLeft;
  double pHealth;
  double pStamina;
  bool pDefending = false;
  CombatStatus status;
  bool killedByRanged = false;

  int remaining(ItemId id) => countOf(available, id) - countOf(consumed, id);

  void strike(
    WeaponStats weapon, {
    required bool ranged,
    required double multiplier,
    required double accuracyMod,
    required double critMod,
    double? precision,
  }) {
    final stunBonus = zStunned;
    var rawChance = weapon.accuracy + accuracyMod - zombie.evasion * (ranged ? 0.5 : 1) + (stunBonus ? 0.2 : 0);
    // Extensión: minijuego de precisión (sin precisión, idéntico a la web).
    final p = precision == null ? null : clampDouble(precision, 0, 1);
    if (p != null) rawChance += (p - 0.5) * precisionAccuracyFactor;
    final hitChance = clampDouble(rawChance, 0.05, 0.98);
    if (!rng.chance(hitChance)) {
      events.add(PlayerMiss(ranged: ranged));
      return;
    }
    final headshot = p != null && p >= precisionCritThreshold;
    final crit = stunBonus || headshot || rng.chance(weapon.critChance + critMod);
    final dmg = math.max(
      1,
      jsRound(_rollDamage(weapon.damage, rng) * multiplier * (crit ? _critMultiplier : 1)),
    );
    zHealth = math.max(0, zHealth - dmg);
    events.add(PlayerHit(damage: dmg, crit: crit, ranged: ranged, stunBonus: stunBonus, headshot: headshot));
    if (zHealth <= 0 && ranged) killedByRanged = true;
  }

  void zombieTurn({required bool fleeFailed}) {
    if (zStunned) {
      // Pierde el turno mientras se recupera.
      zStunned = false;
      events.add(const ZombieStunned());
      return;
    }

    // Bruto: tras algunos ataques normales prepara una embestida que se resuelve al turno siguiente.
    if (def.ability == ZombieAbility.charge) {
      if (zCharging) {
        zCharging = false;
        zChargeIn = _chargeEvery;
        if (pDefending) {
          zStunned = true;
          events.add(const ZombieMiss(charged: true));
          events.add(const ZombieStunned());
          return;
        }
        attack(multiplier: _chargeMultiplier, accuracyMod: 0.15, charged: true);
        return;
      }
      if (zChargeIn <= 0) {
        zCharging = true;
        events.add(const ZombieChargePrepare());
        return;
      }
      zChargeIn--;
    }

    // Chillón: si está herido, grita y llegan refuerzos que lo protegen.
    if (def.ability == ZombieAbility.callHorde &&
        zScreamsLeft > 0 &&
        zHealth < zombie.maxHealth * 0.6 &&
        rng.chance(0.5)) {
      zScreamsLeft--;
      final healed = math.min(zombie.maxHealth - zHealth, jsRound(zombie.maxHealth * 0.3));
      zHealth += healed;
      events.add(ZombieScream(healed: healed));
      return;
    }

    attack(multiplier: 1, accuracyMod: fleeFailed ? 0.1 : 0, charged: false);

    // Corredor: a veces ataca dos veces.
    if (def.ability == ZombieAbility.doubleStrike && status == CombatStatus.ongoing && rng.chance(0.3)) {
      attack(multiplier: 0.7, accuracyMod: 0, charged: false);
    }
  }

  void attack({required double multiplier, required double accuracyMod, required bool charged}) {
    final hitChance = clampDouble(zombie.accuracy + accuracyMod - (pDefending ? 0.15 : 0), 0.05, 0.95);
    if (!rng.chance(hitChance)) {
      events.add(ZombieMiss(charged: charged));
      return;
    }
    final raw = jsRound(_rollDamage(zombie.damage, rng) * multiplier * (pDefending ? _defendDamage : 1));
    final damage = math.max(1, raw - player.defense);
    final blocked = raw - damage;
    pHealth = math.max(0.0, pHealth - damage);
    events.add(ZombieHit(damage: damage, blocked: math.max(0, blocked), charged: charged));
    if (pHealth <= 0) {
      events.add(const PlayerDown());
      status = CombatStatus.lost;
    }
  }
}

/// Resuelve un turno completo: acción del jugador + respuesta del zombie.
CombatState resolveTurn(CombatState prev, CombatAction action, Rng rng) {
  if (prev.status != CombatStatus.ongoing) return prev;

  final t = _Turn(prev, rng);
  var zombieActs = true;
  var fleeFailed = false;

  // --- Turno del jugador --------------------------------------------------
  switch (action) {
    case Attack(:final precision):
    case Heavy(:final precision):
      final heavy = action is Heavy;
      final cost = heavy ? GameStamina.heavy : GameStamina.attack;
      final exhausted = t.pStamina < cost;
      if (exhausted) t.events.add(const Exhausted());
      t.pStamina = math.max(0.0, t.pStamina - cost);
      final multiplier = (heavy && !exhausted ? heavyMultiplier : 1.0) * (exhausted ? _exhaustedDamage : 1.0);
      t.strike(
        t.player.melee,
        ranged: false,
        multiplier: multiplier,
        accuracyMod: (heavy && !exhausted ? -0.15 : 0.0) - (exhausted ? _exhaustedAccuracy : 0.0),
        critMod: heavy && !exhausted ? 0.05 : 0.0,
        precision: precision,
      );
    case Shoot(:final precision):
      final fa = t.player.firearm;
      if (fa == null || t.remaining(ItemId.ammo) < fa.ammoPerShot) {
        // Sin munición no se pierde el turno: solo se avisa.
        const events = <CombatEvent>[NoAmmo()];
        return prev.copyWith(lastEvents: events, log: [...prev.log, ...events]);
      }
      t.consumed[ItemId.ammo] = countOf(t.consumed, ItemId.ammo) + fa.ammoPerShot;
      t.pStamina = math.max(0.0, t.pStamina - GameStamina.shoot);
      t.strike(fa, ranged: true, multiplier: 1, accuracyMod: 0, critMod: 0, precision: precision);
    case Defend():
      t.pDefending = true;
      final before = t.pStamina;
      t.pStamina = math.min(t.player.maxStamina.toDouble(), t.pStamina + _defendStamina);
      t.events.add(DefendEvent(stamina: t.pStamina - before));
    case UseItem(:final itemId):
      final effects = itemDefs[itemId]!.effects;
      if (effects == null || t.remaining(itemId) <= 0) return prev;
      t.consumed[itemId] = countOf(t.consumed, itemId) + 1;
      final hBefore = t.pHealth;
      final sBefore = t.pStamina;
      t.pHealth = math.min(t.player.maxHealth.toDouble(), t.pHealth + (effects.health ?? 0));
      t.pStamina = math.min(t.player.maxStamina.toDouble(), t.pStamina + (effects.stamina ?? 0));
      t.events.add(Heal(itemId: itemId, health: t.pHealth - hBefore, stamina: t.pStamina - sBefore));
    case Flee():
      final chance = clampDouble(
        t.def.fleeChance + (t.zStunned ? 0.15 : 0) - (t.zCharging ? 0.1 : 0),
        0.05,
        0.95,
      );
      if (rng.chance(chance)) {
        t.events.add(const FleeSuccess());
        t.status = CombatStatus.fled;
        zombieActs = false;
      } else {
        t.events.add(const FleeFail());
        fleeFailed = true;
      }
  }

  // --- ¿Murió el zombie? ----------------------------------------------------
  if (t.zHealth <= 0) {
    t.events.add(const ZombieKilled());
    t.status = CombatStatus.won;
    zombieActs = false;
    if (t.def.ability == ZombieAbility.toxicBurst && !t.killedByRanged) {
      // La explosión tóxica nunca remata: deja al jugador con al menos 1 de salud.
      final burst = rng.intRange(6, 10) + (t.zombie.level - 1);
      final dmg = math.min(burst.toDouble(), math.max(0.0, t.pHealth - 1));
      t.pHealth -= dmg;
      t.events.add(ToxicBurst(damage: dmg));
    }
  }

  // --- Turno del zombie -------------------------------------------------------
  if (zombieActs && t.status == CombatStatus.ongoing) {
    t.zombieTurn(fleeFailed: fleeFailed);
  }

  return CombatState(
    spawnId: prev.spawnId,
    zombie: t.zombie.copyWith(
      health: t.zHealth,
      charging: t.zCharging,
      chargeIn: t.zChargeIn,
      stunned: t.zStunned,
      screamsLeft: t.zScreamsLeft,
    ),
    player: t.player.copyWith(health: t.pHealth, stamina: t.pStamina, defending: t.pDefending),
    available: prev.available,
    consumed: t.consumed,
    turn: prev.turn + 1,
    status: t.status,
    lastEvents: List.unmodifiable(t.events),
    log: List.unmodifiable([...prev.log, ...t.events]),
    xpMultiplier: prev.xpMultiplier,
  );
}

/// Recompensa por ganar el encuentro.
Reward combatReward(CombatState state, Rng rng) {
  final def = zombieDefs[state.zombie.typeId]!;
  final xp = jsRound(def.xp * (1 + 0.15 * (state.zombie.level - 1)) * state.xpMultiplier);
  return Reward(xp: xp, items: rollLoot(def.loot, rng));
}

/// Texto en español para cada evento (registro de combate).
String describeEvent(CombatEvent e, CombatState state) {
  final zn = state.zombie.name;
  String n(num v) => jsNumToString(v);
  String blockedSuffix(int blocked) => blocked > 0 ? ' (bloqueado $blocked)' : '';
  switch (e) {
    case PlayerHit():
      if (e.stunBonus) return '¡Golpe certero al $zn aturdido! −${e.damage}';
      if (e.headshot) return e.ranged ? '¡Disparo a la cabeza! −${e.damage}' : '¡Golpe a la cabeza! −${e.damage}';
      if (e.ranged) return e.crit ? '¡Disparo a la cabeza! −${e.damage}' : 'Disparo certero. −${e.damage}';
      return e.crit ? '¡Golpe crítico! −${e.damage}' : 'Golpeás al $zn. −${e.damage}';
    case PlayerMiss():
      return e.ranged ? 'El disparo se pierde en la oscuridad.' : 'El $zn esquiva tu golpe.';
    case Exhausted():
      return 'Estás agotado: tus golpes pierden fuerza.';
    case NoAmmo():
      return 'Sin munición suficiente.';
    case DefendEvent():
      return 'Te cubrís y recuperás el aliento (+${n(e.stamina)} resistencia).';
    case Heal():
      final parts = [
        if (e.health > 0) '+${n(e.health)} salud',
        if (e.stamina > 0) '+${n(e.stamina)} resistencia',
      ];
      final text = parts.join(', ');
      return 'Usás ${itemDefs[e.itemId]!.name}: ${text.isEmpty ? 'sin efecto' : text}.';
    case FleeSuccess():
      return 'Lográs escapar entre los escombros.';
    case FleeFail():
      return '¡El $zn te corta el paso!';
    case ZombieHit():
      if (e.charged) return '¡EMBESTIDA! Recibís −${e.damage}${blockedSuffix(e.blocked)}';
      return 'El $zn te muerde. −${e.damage}${blockedSuffix(e.blocked)}';
    case ZombieMiss():
      return e.charged ? '¡Esquivás la embestida! Queda aturdido.' : 'El $zn falla el ataque.';
    case ZombieChargePrepare():
      return 'El $zn se prepara para embestir... ¡Cubrite!';
    case ZombieStunned():
      return 'El $zn está aturdido.';
    case ZombieScream():
      return '¡El $zn chilla! Llegan refuerzos (+${e.healed} vida).';
    case ToxicBurst():
      return '¡Explota en una nube tóxica! −${n(e.damage)}';
    case ZombieKilled():
      return '$zn eliminado.';
    case PlayerDown():
      return 'Caés al suelo...';
  }
}
