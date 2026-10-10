import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';
import 'package:zona_cero/ui/screens/case_screen.dart';
import 'package:zona_cero/ui/screens/profile_screen.dart';

void main() {
  group('caseStacks', () {
    test('lo equipado no ocupa espacio en el inventario', () {
      final inv = <ItemId, int>{ItemId.food: 3, ItemId.pistol: 1, ItemId.nailBat: 2, ItemId.ammo: 12};
      const eq = Equipment(melee: ItemId.nailBat, firearm: ItemId.pistol);
      final stacks = {for (final e in caseStacks(inv, eq)) e.key: e.value};
      expect(stacks.containsKey(ItemId.pistol), isFalse);
      expect(stacks[ItemId.nailBat], 1);
      expect(stacks[ItemId.food], 3);
      expect(stacks[ItemId.ammo], 12);
    });

    test('ordena consumibles primero y equipo al final', () {
      final stacks = caseStacks({ItemId.riotArmor: 1, ItemId.wood: 2, ItemId.medkit: 1, ItemId.food: 1}, const Equipment());
      expect(stacks.first.key, ItemId.medkit);
      expect(stacks.last.key, ItemId.riotArmor);
    });
  });

  group('radar de perfil', () {
    test('escala logarítmica acotada entre 0 y 1', () {
      expect(const RadarAxis('x', 0, 100).ratio, 0);
      expect(const RadarAxis('x', 100, 100).ratio, closeTo(1, 1e-9));
      expect(const RadarAxis('x', 5000, 100).ratio, 1);
      final mid = const RadarAxis('x', 10, 100).ratio;
      expect(mid, greaterThan(0.4));
      expect(mid, lessThan(0.6));
    });

    test('un jugador nuevo tiene todos los ejes en cero', () {
      final p = createPlayer('t', 'Test', 0);
      expect(radarAxesOf(p).every((a) => a.ratio == 0), isTrue);
    });
  });
}
