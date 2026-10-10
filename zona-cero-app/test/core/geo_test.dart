import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';

const obelisco = LatLng(-34.60372, -58.38159);
const plazaDeMayo = LatLng(-34.6083, -58.3712);

void main() {
  group('geo', () {
    test('calcula distancias reales con haversine', () {
      final d = haversineM(obelisco, plazaDeMayo);
      expect(d, greaterThan(1000));
      expect(d, lessThan(1150));
    });

    test('offsetM desplaza la cantidad de metros pedida', () {
      final p = offsetM(obelisco, 100, 0);
      expect(haversineM(obelisco, p), closeTo(100, 0.5));
      final q = offsetM(obelisco, 0, -250);
      expect(haversineM(obelisco, q), closeTo(250, 0.5));
    });

    test('la grilla de celdas es determinística y vecina', () {
      final c = cellOf(obelisco);
      expect(cellId(cellOf(obelisco)), cellId(c));
      final around = cellsAround(obelisco, 2);
      expect(around, hasLength(25));
      expect(around.map(cellId), contains(cellId(c)));
      expect(parseCellId(cellId(c)), c);
    });

    test('ajusta un punto al segmento más cercano dentro del máximo', () {
      final a = offsetM(obelisco, 0, -100);
      final b = offsetM(obelisco, 0, 100);
      final raw = offsetM(obelisco, 30, 10);
      final snapped = snapToSegments(raw, [(a, b)], 50);
      expect(snapped, isNotNull);
      expect(snapped!.distanceM, closeTo(30, 0.5));
      expect(snapToSegments(offsetM(obelisco, 80, 0), [(a, b)], 50), isNull);
    });

    test('detecta puntos dentro de polígonos con agujeros', () {
      final outer = [
        offsetM(obelisco, -100, -100),
        offsetM(obelisco, -100, 100),
        offsetM(obelisco, 100, 100),
        offsetM(obelisco, 100, -100),
      ];
      final hole = [
        offsetM(obelisco, -20, -20),
        offsetM(obelisco, -20, 20),
        offsetM(obelisco, 20, 20),
        offsetM(obelisco, 20, -20),
      ];
      expect(pointInPolygon(offsetM(obelisco, 50, 50), [outer, hole]), isTrue);
      expect(pointInPolygon(obelisco, [outer, hole]), isFalse);
      expect(pointInPolygon(offsetM(obelisco, 200, 0), [outer]), isFalse);
    });

    test('formatea distancias en español', () {
      expect(formatDistance(35.4), '35 m');
      expect(formatDistance(1234), '1,2 km');
    });
  });
}
