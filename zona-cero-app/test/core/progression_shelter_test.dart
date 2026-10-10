import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';

Shelter shelter() => const Shelter(
      id: 'sh1',
      name: 'Refugio Test',
      ownerId: 'p1',
      ownerName: 'Tester',
      factionId: null,
      level: 1,
      position: LatLng(-34.6, -58.38),
      progress: {},
      contributions: [],
      createdAt: 0,
    );

void main() {
  group('progresión', () {
    test('sube de nivel y conserva la XP sobrante', () {
      final r = addXp(1, 0, xpToNext(1) + 10);
      expect(r, const XpResult(level: 2, xp: 10, levelsGained: 1));
    });

    test('subir de nivel recupera salud y resistencia', () {
      final p = createPlayer('p', 'T', 0).copyWith(health: 10, stamina: 5);
      final g = grantXp(p, 1000);
      expect(g.levelsGained, greaterThan(1));
      expect(g.player.health, 100 + 8 * (g.player.level - 1));
    });

    test('títulos de rango', () {
      expect(rankTitle(1), 'Novato');
      expect(rankTitle(3), 'Sobreviviente');
      expect(rankTitle(30), 'Leyenda de la Zona');
    });
  });

  group('supervivencia', () {
    test('regenera resistencia con el tiempo y salud solo hasta el 50%', () {
      final p = createPlayer('p', 'T', 0).copyWith(health: 20, stamina: 0);
      final r = applyRegen(p, 60 * 60000, gameConfig.regen);
      expect(r.stamina, 100);
      expect(r.health, 50);
    });

    test('consumir comida suma resistencia y la descuenta', () {
      final p = createPlayer('p', 'T', 0).copyWith(stamina: 50);
      final r = consumeItem(p, ItemId.food)!;
      expect(r.stamina, 70);
      expect(r.inventory[ItemId.food], 1);
      expect(consumeItem(p.copyWith(inventory: {}), ItemId.food), isNull);
    });

    test('desequipa automáticamente lo que ya no está en el inventario', () {
      final p = equipItem(createPlayer('p', 'T', 0).copyWith(inventory: {ItemId.pipe: 1}), ItemId.pipe)!;
      expect(p.equipment.melee, ItemId.pipe);
      expect(takeItems(p, {ItemId.pipe: 1})!.equipment.melee, isNull);
    });

    test('caer en combate cuesta parte de los recursos', () {
      final p = createPlayer('p', 'T', 0).copyWith(inventory: {ItemId.wood: 10, ItemId.metal: 3, ItemId.machete: 1});
      final r = applyDeathPenalty(p, gameConfig.death);
      expect(r.lost, {ItemId.wood: 3});
      expect(r.player.inventory[ItemId.machete], 1);
      expect(r.player.stats.deaths, 1);
    });

    test('descansar en el refugio tiene enfriamiento', () {
      final p = createPlayer('p', 'T', 0).copyWith(health: 10);
      final first = restAtShelter(p, 2, 1000000);
      expect(first.ok, isTrue);
      expect(first.player.health, 50);
      expect(restAtShelter(first.player, 2, 1000000 + 60000).ok, isFalse);
    });
  });

  group('refugios', () {
    test('acepta solo lo que el próximo nivel necesita', () {
      final r = applyDonation(shelter(), 'p1', 'Tester', {ItemId.wood: 50, ItemId.food: 5});
      expect(r.accepted, {ItemId.wood: 20});
      expect(r.leveledUp, isFalse);
      expect(remainingRequirements(r.shelter), {ItemId.metal: 6});
      expect(upgradeProgress(r.shelter), closeTo(20 / 26, 0.005));
    });

    test('sube de nivel al completar los requisitos y registra aportes', () {
      var s = applyDonation(shelter(), 'p1', 'Tester', {ItemId.wood: 20}).shelter;
      final r = applyDonation(s, 'p2', 'Otra', {ItemId.metal: 6});
      expect(r.leveledUp, isTrue);
      expect(r.shelter.level, 2);
      expect(r.shelter.progress, isEmpty);
      s = r.shelter;
      expect(s.contributions.map((c) => c.playerId), ['p1', 'p2']);
    });

    test('resuelve ataques de hordas según la defensa', () {
      final rng = createRng('horda');
      final attack = planHordeAttack(shelter().copyWith(level: 3), 0, rng);
      final strong = resolveHordeAttack(shelter().copyWith(level: 3), attack, 100, rng);
      expect(strong.defended, isTrue);
      final weak = resolveHordeAttack(shelter(), attack.copyWith(strength: 999), 0, rng);
      expect(weak.defended, isFalse);
      expect(weak.progressLossRatio, greaterThan(0));
    });
  });
}
