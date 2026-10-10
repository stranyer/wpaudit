import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';
import 'package:zona_cero/ui/screens/case_screen.dart';
import 'package:zona_cero/ui/screens/profile_screen.dart';

void main() {
  group('packAttache', () {
    test('acomoda sin superposiciones y dentro de las columnas', () {
      final inv = <ItemId, int>{
        ItemId.food: 3, ItemId.water: 2, ItemId.medicine: 1, ItemId.wood: 9, ItemId.metal: 4, ItemId.ammo: 10,
        ItemId.nailBat: 1, ItemId.shotgun: 1, ItemId.pistol: 1, ItemId.riotArmor: 1, ItemId.scrapVest: 1, ItemId.medkit: 2,
      };
      final packed = packAttache(inv);
      expect(packed.items.length, inv.length);
      final cells = <int>{};
      for (final it in packed.items) {
        expect(it.x + it.w, lessThanOrEqualTo(6));
        for (var dy = 0; dy < it.h; dy++) {
          for (var dx = 0; dx < it.w; dx++) {
            expect(cells.add((it.y + dy) * 6 + it.x + dx), isTrue, reason: 'celda ocupada dos veces por ${it.id}');
          }
        }
        expect(it.y + it.h, lessThanOrEqualTo(packed.rows));
      }
    });

    test('las armas van primero y respetan su huella', () {
      final packed = packAttache({ItemId.food: 1, ItemId.machete: 1});
      expect(packed.items.first.id, ItemId.machete);
      expect((packed.items.first.w, packed.items.first.h), (3, 1));
    });

    test('maletín vacío', () {
      final packed = packAttache({});
      expect(packed.items, isEmpty);
      expect(packed.rows, 0);
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
