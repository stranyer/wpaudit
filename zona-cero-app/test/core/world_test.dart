import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';

const cfg = SpawnConfig(worldSeed: 'test', zombieWindowMs: 600000, supplyWindowMs: 1800000, infestedCellChance: 0.15);
const obelisco = LatLng(-34.60372, -58.38159);
const rules = InteractionRules(interactionRadiusM: 40, maxAccuracyBonusM: 15, maxAccuracyForInteractionM: 80);
const now = 1760000000000;

void main() {
  group('generación del mundo', () {
    test('es determinística: mismo lugar y hora = mismos spawns para todos', () {
      final a = generateWorld(obelisco, 2, now, cfg);
      final b = generateWorld(obelisco, 2, now + 1000, cfg);
      expect(a.spawns.map((s) => s.id).toList(), b.spawns.map((s) => s.id).toList());
      expect(a.zones, hasLength(25));
    });

    test('cambia al pasar a la siguiente ventana de tiempo', () {
      final cell = cellOf(obelisco);
      final a = generateCellSpawns(cell, now, cfg).map((s) => s.id).toList();
      final b = generateCellSpawns(cell, now + 2000000, cfg).map((s) => s.id).toList();
      expect(a, isNot(equals(b)));
      expect(nextWindowChange(now, cfg), greaterThan(now));
    });

    test('genera zombies y suministros en un área razonable', () {
      final w = generateWorld(obelisco, 2, now, cfg);
      expect(w.spawns.any((s) => s is ZombieSpawn), isTrue);
      expect(w.spawns.any((s) => s is SupplySpawn), isTrue);
      for (final s in w.spawns) {
        expect(haversineM(obelisco, s.position), lessThan(900));
      }
    });

    test('no hay zombies dentro del radio seguro de un refugio', () {
      final w = generateWorld(obelisco, 2, now, cfg);
      final zombie = w.spawns.firstWhere((s) => s is ZombieSpawn);
      final filtered = filterSafeZones(w.spawns, [zombie.position], 60);
      expect(filtered.where((s) => s.id == zombie.id), isEmpty);
    });

    test('mueve spawns a la calle y descarta los que caen en zonas excluidas', () {
      final Segment street = (offsetM(obelisco, 0, -300), offsetM(obelisco, 0, 300));
      final spawns = generateWorld(obelisco, 0, now, cfg).spawns;
      final placed = placeSpawns(spawns, PlacementData(walkable: [street], excluded: const []), 500);
      expect(placed.every((s) => s.placement == PlacementState.snapped), isTrue);
      for (final s in placed) {
        expect((s.position.lat - obelisco.lat).abs(), lessThan(0.0001));
      }
      final water = [
        [
          offsetM(obelisco, -400, -400),
          offsetM(obelisco, -400, 400),
          offsetM(obelisco, 400, 400),
          offsetM(obelisco, 400, -400),
        ],
      ];
      expect(placeSpawns(spawns, PlacementData(walkable: [street], excluded: [water]), 500), isEmpty);
    });
  });

  group('interacciones', () {
    InteractionRequest req(double meters, [double accuracy = 5]) => InteractionRequest(
          playerId: 'p',
          action: InteractionAction.scavenge,
          targetId: 't',
          targetPosition: obelisco,
          playerPosition: offsetM(obelisco, meters, 0),
          accuracyM: accuracy,
          timestamp: now,
        );
    const free = InteractionContext(speedLocked: false, depleted: false);

    test('valida alcance con tolerancia por precisión GPS', () {
      expect(validateInteraction(req(30), rules, free).ok, isTrue);
      expect(validateInteraction(req(50, 15), rules, free).ok, isTrue);
      expect(validateInteraction(req(80), rules, free).reason, InteractionRejection.outOfRange);
      expect(isWithinReach(obelisco, offsetM(obelisco, 39, 0), 0, rules), isTrue);
    });

    test('rechaza por velocidad, precisión, agotado o vencido', () {
      expect(
        validateInteraction(req(10), rules, const InteractionContext(speedLocked: true, depleted: false)).reason,
        InteractionRejection.tooFast,
      );
      expect(validateInteraction(req(10, 120), rules, free).reason, InteractionRejection.lowAccuracy);
      expect(
        validateInteraction(req(10), rules, const InteractionContext(speedLocked: false, depleted: true)).reason,
        InteractionRejection.depleted,
      );
      expect(
        validateInteraction(req(10), rules, const InteractionContext(speedLocked: false, depleted: false, expiresAt: now - 1))
            .reason,
        InteractionRejection.expired,
      );
      expect(InteractionRejection.tooFast.message, contains('rápido'));
    });

    test('bloquea al detectar velocidad de vehículo', () {
      var g = updateSpeedGuard(const SpeedGuardState(), const SpeedSample(position: obelisco, time: 0), 12, 30000);
      g = updateSpeedGuard(g, SpeedSample(position: offsetM(obelisco, 200, 0), time: 10000), 12, 30000);
      expect(g.lockedUntil, 40000);
      var w = updateSpeedGuard(const SpeedGuardState(), const SpeedSample(position: obelisco, time: 0), 12, 30000);
      w = updateSpeedGuard(w, SpeedSample(position: offsetM(obelisco, 15, 0), time: 10000), 12, 30000);
      expect(w.lockedUntil, 0);
    });
  });

  group('privacidad', () {
    test('difumina la posición de forma estable y a distancia acotada', () {
      final a = fuzzPosition(obelisco, 'jugador-1');
      final b = fuzzPosition(offsetM(obelisco, 3, 3), 'jugador-1');
      expect(a, b);
      expect(haversineM(obelisco, a), lessThan(300));
      expect(haversineM(obelisco, a), greaterThan(0));
      expect(approximateDistanceLabel(342), '~300 m');
    });
  });
}
