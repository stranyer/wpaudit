// Paridad bit a bit del RNG y de la generación del mundo con la versión web.
// Los valores esperados se obtuvieron corriendo `src/core/rng.ts` y `spawns.ts`
// originales con Node (ver fixtures/gen_ts_parity.ts).

import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';

List<double> firstValues(Object seed, [int n = 10]) {
  final r = createRng(seed);
  return [for (var i = 0; i < n; i++) r.next()];
}

void main() {
  group('RNG idéntico a la web', () {
    test("semilla 'zona-cero-v1'", () {
      expect(firstValues('zona-cero-v1'), [
        0.6820650645531714,
        0.478285713121295,
        0.6637156440410763,
        0.5711206514388323,
        0.28474074858240783,
        0.220219892449677,
        0.3239197542425245,
        0.6176931012887508,
        0.8434238622430712,
        0.47196306474506855,
      ]);
    });

    test('semilla numérica 12345', () {
      expect(firstValues(12345), [
        0.9797282677609473,
        0.3067522644996643,
        0.484205421525985,
        0.817934412509203,
        0.5094283693470061,
        0.34747186047025025,
        0.07375754183158278,
        0.7663964673411101,
        0.9968264393974096,
        0.8250224851071835,
      ]);
    });

    test('hash FNV-1a de 32 bits', () {
      expect(hashString(''), 2166136261);
      expect(hashString('a'), 3826002220);
      expect(hashString('zona-cero-v1'), 2814964297);
      expect(hashString('Ñandú ¡é!'), 4136162104);
      expect(hashString('zona-cero-v1:z:-24326_-19225:2933333'), 3671481452);
    });

    test('semillas numéricas usan la semántica `>>> 0` de JS', () {
      // -1 >>> 0 == 4294967295; 4294967301 >>> 0 == 5; 3.7 >>> 0 == 3.
      expect(firstValues(-1), firstValues(4294967295));
      expect(firstValues(4294967301), firstValues(5));
      expect(firstValues(3.7), firstValues(3));
      expect(firstValues(-7.9), firstValues(4294967289));
    });

    test('todos los valores están en [0, 1)', () {
      final r = createRng('rango');
      for (var i = 0; i < 10000; i++) {
        final v = r.next();
        expect(v >= 0 && v < 1, isTrue);
      }
    });
  });

  group('mundo idéntico a la web', () {
    test('generateCellSpawns de la celda del Obelisco', () {
      const obelisco = LatLng(-34.60372, -58.38159);
      final cell = cellOf(obelisco);
      expect(cellId(cell), '-24326_-19225');
      final spawns = generateCellSpawns(cell, 1760000000000, gameConfig.spawn);
      final expected = [
        ('z:-24326_-19225:2933333:0', 'zombie', 'runner', -34.60453801692496, -58.380389383270085),
        ('z:-24326_-19225:2933333:1', 'zombie', 'walker', -34.60462031541943, -58.381488621828986),
        ('s:-24326_-19225:977777:0', 'supply', 'hardware', -34.60471537114263, -58.3811478013296),
      ];
      expect(spawns, hasLength(expected.length));
      for (var i = 0; i < expected.length; i++) {
        final (id, kind, type, lat, lng) = expected[i];
        final s = spawns[i];
        expect(s.id, id);
        expect(s.kind, kind);
        expect(s.cellId, '-24326_-19225');
        expect(s.expiresAt, 1760000400000);
        expect(s.placement, PlacementState.raw);
        expect(
          switch (s) {
            ZombieSpawn(:final zombieType) => zombieType.key,
            SupplySpawn(:final supplyType) => supplyType.key,
          },
          type,
        );
        expect(s.position.lat, closeTo(lat, 1e-9));
        expect(s.position.lng, closeTo(lng, 1e-9));
        // De hecho es bit a bit idéntico.
        expect(s.position, LatLng(lat, lng));
      }
    });
  });
}
