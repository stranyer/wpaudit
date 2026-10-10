import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';

import 'helpers.dart';

PlayerState player({int? level, double? health, Inventory? inventory, Equipment? equipment}) =>
    createPlayer('p1', 'Tester', 0).copyWith(level: level, health: health, inventory: inventory, equipment: equipment);

void main() {
  group('combate', () {
    test('inicia con estadísticas escaladas y armas equipadas', () {
      final p = player(
        inventory: {ItemId.pipe: 1, ItemId.pistol: 1, ItemId.ammo: 3},
        equipment: const Equipment(melee: ItemId.pipe, firearm: ItemId.pistol),
      );
      final s = startCombat(spawnId: 's', zombieType: ZombieTypeId.walker, player: p, rng: createRng(3));
      expect(s.zombie.health, greaterThan(0));
      expect(s.player.meleeName, 'Caño de plomo');
      expect(canShoot(s), isTrue);
      expect(s.available[ItemId.ammo], 3);
    });

    test('un ataque que acierta reduce la vida del zombie y consume resistencia', () {
      final s = startCombat(spawnId: 's', zombieType: ZombieTypeId.walker, player: player(), rng: ScriptedRng([0.5]));
      // 0.0 => acierta, sin crítico (0.99), daño mínimo; luego el zombie falla (0.99)
      final next = resolveTurn(s, const Attack(), ScriptedRng([0.0, 0.99, 0.0, 0.99]));
      expect(next.zombie.health, lessThan(s.zombie.health));
      expect(next.player.stamina, s.player.stamina - 6);
      expect(next.lastEvents.map((e) => e.kind), ['player_hit', 'zombie_miss']);
    });

    test('el combate termina en victoria y da recompensas', () {
      var s = startCombat(spawnId: 's', zombieType: ZombieTypeId.walker, player: player(), rng: createRng(7));
      s = s.copyWith(zombie: s.zombie.copyWith(health: 1));
      final next = resolveTurn(s, const Attack(), ScriptedRng([0.0, 0.99, 0.0]));
      expect(next.status, CombatStatus.won);
      final reward = combatReward(next, createRng(2));
      expect(reward.xp, greaterThan(0));
    });

    test('el jugador puede caer', () {
      var s = startCombat(spawnId: 's', zombieType: ZombieTypeId.walker, player: player(), rng: createRng(7));
      s = s.copyWith(player: s.player.copyWith(health: 1));
      // Falla el ataque (0.99), el zombie acierta (0.0)
      final next = resolveTurn(s, const Attack(), ScriptedRng([0.99, 0.0, 0.5]));
      expect(next.status, CombatStatus.lost);
      expect(next.lastEvents.last.kind, 'player_down');
    });

    test('defenderse frente a la embestida del Bruto lo aturde', () {
      var s = startCombat(spawnId: 's', zombieType: ZombieTypeId.brute, player: player(level: 6), rng: createRng(1));
      s = s.copyWith(zombie: s.zombie.copyWith(charging: true));
      final next = resolveTurn(s, const Defend(), ScriptedRng([0.5]));
      expect(next.zombie.stunned, isTrue);
      expect(next.player.health, s.player.health);
      // El siguiente golpe contra un aturdido es crítico garantizado.
      final after = resolveTurn(next, const Attack(), ScriptedRng([0.0, 0.5]));
      final hit = after.lastEvents.whereType<PlayerHit>().first;
      expect(hit.crit && hit.stunBonus, isTrue);
    });

    test('disparar sin munición no consume el turno', () {
      final p = player(inventory: {ItemId.pistol: 1}, equipment: const Equipment(firearm: ItemId.pistol));
      final s = startCombat(spawnId: 's', zombieType: ZombieTypeId.walker, player: p, rng: createRng(1));
      final next = resolveTurn(s, const Shoot(), createRng(5));
      expect(next.turn, s.turn);
      expect(next.lastEvents[0].kind, 'no_ammo');
    });

    test('usar un objeto lo descuenta del combate y cura', () {
      final p = player(health: 40, inventory: {ItemId.medicine: 1});
      final s = startCombat(spawnId: 's', zombieType: ZombieTypeId.walker, player: p, rng: createRng(1));
      final next = resolveTurn(s, const UseItem(ItemId.medicine), ScriptedRng([0.99]));
      expect(next.consumed[ItemId.medicine], 1);
      expect(next.player.health, 70);
    });

    test('el Hinchado explota al morir cuerpo a cuerpo pero nunca remata', () {
      var s = startCombat(spawnId: 's', zombieType: ZombieTypeId.bloater, player: player(level: 3), rng: createRng(1));
      s = s.copyWith(zombie: s.zombie.copyWith(health: 1), player: s.player.copyWith(health: 3));
      final next = resolveTurn(s, const Attack(), ScriptedRng([0.0, 0.99, 0.0, 0.99]));
      expect(next.status, CombatStatus.won);
      expect(next.player.health, 1);
      expect(next.lastEvents.map((e) => e.kind), contains('toxic_burst'));
    });

    test('todos los eventos tienen texto en español', () {
      var s = startCombat(spawnId: 's', zombieType: ZombieTypeId.runner, player: player(), rng: createRng(1));
      final rng = createRng(99);
      for (var i = 0; i < 30 && s.status == CombatStatus.ongoing; i++) {
        s = resolveTurn(s, i % 4 == 3 ? const Defend() : const Attack(), rng);
      }
      for (final e in s.log) {
        expect(describeEvent(e, s).length, greaterThan(3));
      }
    });
  });
}
