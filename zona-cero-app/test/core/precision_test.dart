// Extensión de la app: minijuego de precisión en Attack / Heavy / Shoot.
// Base: novato a puño limpio contra un Caminante de nivel 1
// (puños 0.9 de acierto - 0.05 de evasión = 0.85 de probabilidad de acertar).

import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';

import 'helpers.dart';

CombatState walkerFight({PlayerState? player}) => startCombat(
      spawnId: 's',
      zombieType: ZombieTypeId.walker,
      // 0.5 => intRange(-1, 1) = 0 => Caminante de nivel 1.
      player: player ?? createPlayer('p1', 'Tester', 0),
      rng: ScriptedRng([0.5]),
    );

PlayerHit? hitOf(CombatState s) => s.lastEvents.whereType<PlayerHit>().firstOrNull;

double winRate(CombatAction Function(CombatState s) choose, [int runs = 300]) {
  final novato = createPlayer('p', 'Novato', 0);
  var wins = 0;
  for (var i = 0; i < runs; i++) {
    final rng = createRng('precision:$i');
    var s = startCombat(spawnId: 'x', zombieType: ZombieTypeId.bloater, player: novato, rng: rng);
    for (var t = 0; t < 60 && s.status == CombatStatus.ongoing; t++) {
      s = resolveTurn(s, choose(s), rng);
    }
    if (s.status == CombatStatus.won) wins++;
  }
  return wins / runs;
}

void main() {
  group('precisión (minijuego)', () {
    test('sin precisión (null) el combate es idéntico a la versión web', () {
      for (var seed = 0; seed < 20; seed++) {
        final a = resolveTurn(walkerFight(), const Attack(), createRng(seed));
        final b = resolveTurn(walkerFight(), const Attack(precision: null), createRng(seed));
        expect(b.log.map((e) => e.toJson()).toList(), a.log.map((e) => e.toJson()).toList());
        expect(b.zombie.health, a.zombie.health);
        expect(b.player.health, a.player.health);
      }
    });

    test('precisión 0.5 es neutra', () {
      for (var seed = 0; seed < 20; seed++) {
        for (final pair in [
          (const Attack(), const Attack(precision: 0.5)),
          (const Heavy(), const Heavy(precision: 0.5)),
        ]) {
          final a = resolveTurn(walkerFight(), pair.$1, createRng(seed));
          final b = resolveTurn(walkerFight(), pair.$2, createRng(seed));
          expect(b.log.map((e) => e.toJson()).toList(), a.log.map((e) => e.toJson()).toList());
        }
      }
    });

    test('una precisión alta convierte un fallo en acierto', () {
      // Tirada 0.9: falla con 0.85 de acierto...
      final miss = resolveTurn(walkerFight(), const Attack(), ScriptedRng([0.9, 0.99, 0.99]));
      expect(miss.lastEvents.first, isA<PlayerMiss>());
      // ...pero con precisión 0.8 el acierto sube a 0.85 + 0.09 = 0.94.
      final hit = resolveTurn(walkerFight(), const Attack(precision: 0.8), ScriptedRng([0.9, 0.99, 0.0, 0.99]));
      expect(hitOf(hit), isNotNull);
      expect(hitOf(hit)!.crit, isFalse);
      expect(hitOf(hit)!.headshot, isFalse);
    });

    test('una precisión baja convierte un acierto en fallo', () {
      // Tirada 0.75: acierta con 0.85, falla con 0.85 - 0.15 = 0.70.
      final hit = resolveTurn(walkerFight(), const Attack(), ScriptedRng([0.75, 0.99, 0.0, 0.99]));
      expect(hitOf(hit), isNotNull);
      final miss = resolveTurn(walkerFight(), const Attack(precision: 0), ScriptedRng([0.75, 0.99]));
      expect(miss.lastEvents.first, isA<PlayerMiss>());
    });

    test('precisión >= 0.9 fuerza un crítico ("headshot") sin tirar por crítico', () {
      // Tiradas: 0.0 acierta, 0.0 daño mínimo (3), 0.99 el zombie falla.
      for (final precision in [0.9, 0.95, 1.0]) {
        final s = resolveTurn(walkerFight(), Attack(precision: precision), ScriptedRng([0.0, 0.0, 0.99]));
        final hit = hitOf(s)!;
        expect(hit.crit, isTrue);
        expect(hit.headshot, isTrue);
        expect(hit.damage, jsRound(3 * 1.75)); // 5
        expect(s.lastEvents.map((e) => e.kind), ['player_hit', 'zombie_miss']);
        expect(describeEvent(hit, s), '¡Golpe a la cabeza! −5');
      }
    });

    test('precisión 0.89 no fuerza el crítico (se tira normalmente)', () {
      // Tiradas: 0.0 acierta, 0.99 sin crítico, 0.0 daño mínimo, 0.99 el zombie falla.
      final s = resolveTurn(walkerFight(), const Attack(precision: 0.89), ScriptedRng([0.0, 0.99, 0.0, 0.99]));
      final hit = hitOf(s)!;
      expect(hit.crit, isFalse);
      expect(hit.headshot, isFalse);
      expect(hit.damage, 3);
    });

    test('la precisión se acota a [0, 1] y el acierto sigue con tope 0.98', () {
      // Precisión 5 => 1: acierto 0.85 + 0.15 = 1.0 => tope 0.98. Tirada 0.979 acierta, 0.981 falla.
      final hit = resolveTurn(walkerFight(), const Attack(precision: 5), ScriptedRng([0.979, 0.0, 0.99]));
      expect(hitOf(hit), isNotNull);
      final miss = resolveTurn(walkerFight(), const Attack(precision: 5), ScriptedRng([0.981, 0.99]));
      expect(miss.lastEvents.first, isA<PlayerMiss>());
      // Precisión -3 => 0: acierto 0.70.
      final low = resolveTurn(walkerFight(), const Attack(precision: -3), ScriptedRng([0.71, 0.99]));
      expect(low.lastEvents.first, isA<PlayerMiss>());
    });

    test('golpe fuerte con precisión', () {
      // Golpe fuerte: 0.9 - 0.15 - 0.05 = 0.70; con precisión 1 => 0.85 y crítico forzado.
      final miss = resolveTurn(walkerFight(), const Heavy(), ScriptedRng([0.8, 0.99]));
      expect(miss.lastEvents.first, isA<PlayerMiss>());
      final s = resolveTurn(walkerFight(), const Heavy(precision: 1), ScriptedRng([0.8, 0.0, 0.99]));
      final hit = hitOf(s)!;
      expect(hit.headshot && hit.crit, isTrue);
      expect(hit.damage, jsRound(3 * heavyMultiplier * 1.75)); // 9
      expect(s.player.stamina, 100 - GameStamina.heavy);
    });

    test('disparo a la cabeza con precisión', () {
      final p = equipItem(
        createPlayer('p1', 'Tester', 0).copyWith(inventory: {ItemId.pistol: 1, ItemId.ammo: 3}),
        ItemId.pistol,
      )!;
      // Pistola: 0.88 - 0.05 * 0.5 = 0.855. Tirada 0.97 falla sin precisión...
      final miss = resolveTurn(walkerFight(player: p), const Shoot(), ScriptedRng([0.97, 0.99]));
      expect(miss.lastEvents.first, isA<PlayerMiss>());
      expect(miss.consumed[ItemId.ammo], 1);
      // ...y con 0.95 acierta (0.855 + 0.135 = 0.99 => tope 0.98) con crítico: 18 x 1.75 = 31.5 => 32.
      final s = resolveTurn(walkerFight(player: p), const Shoot(precision: 0.95), ScriptedRng([0.97, 0.0, 0.99]));
      final hit = hitOf(s)!;
      expect(hit.ranged && hit.crit && hit.headshot, isTrue);
      expect(hit.damage, 32);
      expect(s.status, CombatStatus.won);
      expect(describeEvent(hit, s), '¡Disparo a la cabeza! −32');
      expect(s.consumed[ItemId.ammo], 1);
    });

    test('contra un zombie aturdido el texto sigue siendo el del aturdimiento', () {
      var s = walkerFight();
      s = s.copyWith(zombie: s.zombie.copyWith(stunned: true));
      final next = resolveTurn(s, const Attack(precision: 1), ScriptedRng([0.0, 0.0, 0.99]));
      final hit = hitOf(next)!;
      expect(hit.stunBonus && hit.crit, isTrue);
      expect(describeEvent(hit, next), startsWith('¡Golpe certero al Caminante aturdido!'));
    });

    test('el evento con headshot se serializa y se reconstruye', () {
      const e = PlayerHit(damage: 9, crit: true, ranged: false, stunBonus: false, headshot: true);
      expect(e.toJson()['headshot'], isTrue);
      final back = CombatEvent.fromJson(e.toJson()) as PlayerHit;
      expect(back.headshot, isTrue);
      // Sin headshot la forma es exactamente la de la web.
      expect(const PlayerHit(damage: 1, crit: false, ranged: true, stunBonus: false).toJson().containsKey('headshot'),
          isFalse);
    });

    test('la puntería cambia el resultado contra un Hinchado (novato a puño limpio)', () {
      CombatAction base(CombatState s, {double? precision}) {
        if (s.zombie.charging) return const Defend();
        if (s.player.stamina >= 15 && s.zombie.health > 12) return Heavy(precision: precision);
        return Attack(precision: precision);
      }

      final normal = winRate((s) => base(s));
      final sharp = winRate((s) => base(s, precision: 0.95));
      final clumsy = winRate((s) => base(s, precision: 0.1));
      // Medido: ~0.70 sin minijuego, ~1.00 con precisión 0.95 y ~0.40 con 0.1.
      expect(sharp, greaterThan(normal + 0.1));
      expect(clumsy, lessThan(normal - 0.1));
    });

    test('las fábricas de CombatAction producen las mismas acciones', () {
      expect(const CombatAction.attack(precision: 0.7), isA<Attack>());
      expect((const CombatAction.shoot(precision: 0.7) as Shoot).precision, 0.7);
      expect(const CombatAction.useItem(ItemId.medkit).type, 'use_item');
      expect(const CombatAction.flee().type, 'flee');
    });
  });
}
