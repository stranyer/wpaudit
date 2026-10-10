// Refugios comunitarios: niveles, donaciones y ataques de hordas.

import 'dart:math' as math;

import 'rng.dart';
import 'types.dart';
import 'utils.dart';

class ShelterLevelDef {
  const ShelterLevelDef({
    required this.level,
    required this.name,
    required this.description,
    required this.requirements,
    required this.perks,
    required this.defense,
    required this.restHealth,
    required this.restStamina,
    required this.lootBonus,
  });

  final int level;
  final String name;
  final String description;

  /// Recursos necesarios para ALCANZAR este nivel desde el anterior.
  final Inventory requirements;
  final List<String> perks;

  /// Defensa contra hordas.
  final int defense;

  /// Curación y resistencia al descansar.
  final int restHealth;
  final int restStamina;

  /// Bonus de botín para miembros (multiplicador adicional).
  final double lootBonus;
}

const List<ShelterLevelDef> shelterLevels = [
  ShelterLevelDef(
    level: 1,
    name: 'Campamento improvisado',
    description: 'Una carpa, una fogata y mucha esperanza.',
    requirements: {},
    perks: ['Descansar recupera 25 de salud y resistencia'],
    defense: 5,
    restHealth: 25,
    restStamina: 25,
    lootBonus: 0,
  ),
  ShelterLevelDef(
    level: 2,
    name: 'Barricadas',
    description: 'Empalizadas de madera que frenan a los caminantes.',
    requirements: {ItemId.wood: 20, ItemId.metal: 6},
    perks: ['Descansar recupera 40', 'Desbloquea: Chaleco de chapa'],
    defense: 15,
    restHealth: 40,
    restStamina: 40,
    lootBonus: 0,
  ),
  ShelterLevelDef(
    level: 3,
    name: 'Taller',
    description: 'Un banco de trabajo para fabricar equipo serio.',
    requirements: {ItemId.wood: 30, ItemId.metal: 25, ItemId.food: 10},
    perks: ['Desbloquea: Machete y Botiquín', '+5% de botín'],
    defense: 28,
    restHealth: 55,
    restStamina: 55,
    lootBonus: 0.05,
  ),
  ShelterLevelDef(
    level: 4,
    name: 'Torre de vigilancia',
    description: 'Vigías que detectan hordas antes de que lleguen.',
    requirements: {ItemId.wood: 40, ItemId.metal: 40, ItemId.food: 20, ItemId.water: 20},
    perks: ['Desbloquea: Pistola 9 mm', '+10% de botín'],
    defense: 45,
    restHealth: 75,
    restStamina: 75,
    lootBonus: 0.1,
  ),
  ShelterLevelDef(
    level: 5,
    name: 'Fortaleza',
    description: 'Muros de chapa, generador y enfermería. Un faro en la Zona Cero.',
    requirements: {
      ItemId.wood: 60,
      ItemId.metal: 80,
      ItemId.food: 30,
      ItemId.water: 30,
      ItemId.medicine: 15,
      ItemId.ammo: 20,
    },
    perks: ['Descanso completo', '+15% de botín'],
    defense: 70,
    restHealth: 100,
    restStamina: 100,
    lootBonus: 0.15,
  ),
];

final int maxShelterLevel = shelterLevels.length;
const int restCooldownMs = 10 * 60 * 1000;

ShelterLevelDef shelterLevelDef(int level) => shelterLevels[math.max(1, math.min(maxShelterLevel, level)) - 1];

/// Requisitos del próximo nivel para un refugio de nivel `level`, o null si ya está al máximo.
Inventory? nextLevelRequirements(int level) {
  if (level >= maxShelterLevel) return null;
  return shelterLevels[level].requirements;
}

/// Cuánto falta de cada recurso para el próximo nivel.
Inventory remainingRequirements(Shelter shelter) {
  final req = nextLevelRequirements(shelter.level);
  if (req == null) return {};
  final out = <ItemId, int>{};
  for (final e in req.entries) {
    final left = e.value - (shelter.progress[e.key] ?? 0);
    if (left > 0) out[e.key] = left;
  }
  return out;
}

/// Progreso total 0..1 hacia el próximo nivel.
double upgradeProgress(Shelter shelter) {
  final req = nextLevelRequirements(shelter.level);
  if (req == null) return 1;
  var total = 0;
  var done = 0;
  for (final e in req.entries) {
    total += e.value;
    done += math.min(e.value, shelter.progress[e.key] ?? 0);
  }
  return total == 0 ? 1 : done / total;
}

class DonationOutcome {
  const DonationOutcome({
    required this.shelter,
    required this.accepted,
    required this.acceptedTotal,
    required this.leveledUp,
  });

  final Shelter shelter;
  final Inventory accepted;
  final int acceptedTotal;
  final bool leveledUp;
}

/// `Math.floor` tolerante: NaN o negativos no aportan; +infinito ofrece "todo".
int _offeredUnits(num raw) {
  if (raw is int) return raw;
  if (raw.isNaN) return 0;
  // Valor grande pero seguro también en web (ningún requisito se le acerca).
  if (raw.isInfinite) return raw > 0 ? 0x7FFFFFFF : 0;
  return raw.floor();
}

/// Aplica una donación. Solo se aceptan recursos que el próximo nivel necesita;
/// el excedente se devuelve al jugador. Si se completan los requisitos, sube de nivel.
/// Función pura: devuelve un refugio nuevo.
DonationOutcome applyDonation(Shelter shelter, String playerId, String playerName, Map<ItemId, num> offered) {
  final remaining = remainingRequirements(shelter);
  final accepted = <ItemId, int>{};
  final progress = Map<ItemId, int>.of(shelter.progress);
  var acceptedTotal = 0;

  for (final e in offered.entries) {
    final amount = _offeredUnits(e.value);
    if (amount <= 0) continue;
    final take = math.min(amount, remaining[e.key] ?? 0);
    if (take <= 0) continue;
    accepted[e.key] = take;
    progress[e.key] = (progress[e.key] ?? 0) + take;
    acceptedTotal += take;
  }

  var contributions = shelter.contributions;
  if (acceptedTotal > 0) {
    final exists = contributions.any((c) => c.playerId == playerId);
    contributions = exists
        ? [
            for (final c in contributions)
              c.playerId == playerId ? c.copyWith(playerName: playerName, amount: c.amount + acceptedTotal) : c,
          ]
        : [...contributions, ShelterContribution(playerId: playerId, playerName: playerName, amount: acceptedTotal)];
    contributions = _stableSortByAmountDesc(contributions);
  }

  var next = shelter.copyWith(progress: progress, contributions: contributions);
  var leveledUp = false;
  if (acceptedTotal > 0 && remainingRequirements(next).isEmpty && next.level < maxShelterLevel) {
    next = next.copyWith(level: next.level + 1, progress: {});
    leveledUp = true;
  }
  return DonationOutcome(shelter: next, accepted: accepted, acceptedTotal: acceptedTotal, leveledUp: leveledUp);
}

/// Orden estable (como `Array.prototype.sort` de JS): `List.sort` de Dart no lo garantiza.
List<ShelterContribution> _stableSortByAmountDesc(List<ShelterContribution> list) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final byAmount = b.$2.amount.compareTo(a.$2.amount);
    return byAmount != 0 ? byAmount : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

// ---------------------------------------------------------------------------
// Eventos cooperativos: ataques de hordas (arquitectura preparada)
// ---------------------------------------------------------------------------

class HordeAttack {
  const HordeAttack({required this.shelterId, required this.strength, required this.startsAt});

  final String shelterId;

  /// Fuerza de la horda; escala con el nivel del refugio.
  final int strength;
  final int startsAt;

  HordeAttack copyWith({String? shelterId, int? strength, int? startsAt}) => HordeAttack(
        shelterId: shelterId ?? this.shelterId,
        strength: strength ?? this.strength,
        startsAt: startsAt ?? this.startsAt,
      );
}

class HordeOutcome {
  const HordeOutcome({required this.defended, required this.progressLossRatio, required this.defenseRoll});

  final bool defended;

  /// Recursos perdidos si la horda rompe las defensas (fracción del progreso).
  final double progressLossRatio;
  final int defenseRoll;
}

/// Genera una horda proporcional al nivel del refugio.
HordeAttack planHordeAttack(Shelter shelter, int startsAt, Rng rng) {
  final base = shelterLevelDef(shelter.level).defense;
  return HordeAttack(shelterId: shelter.id, strength: jsRound(base * rng.range(0.7, 1.4)), startsAt: startsAt);
}

/// Resuelve un ataque: defensa del refugio + aportes de defensores conectados.
/// Pensado para correr en el servidor cuando exista backend (cron/edge function).
HordeOutcome resolveHordeAttack(Shelter shelter, HordeAttack attack, num defendersPower, Rng rng) {
  final defenseRoll = shelterLevelDef(shelter.level).defense * rng.range(0.85, 1.15) + defendersPower;
  final defended = defenseRoll >= attack.strength;
  return HordeOutcome(defended: defended, progressLossRatio: defended ? 0 : 0.25, defenseRoll: jsRound(defenseRoll));
}
