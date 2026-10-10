import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';
import 'package:zona_cero/map/map_events.dart';

const obelisco = LatLng(-34.60372, -58.38159);

void main() {
  group('programación de eventos ambientales', () {
    test('nada antes de arrancar ni antes del primer intervalo', () {
      final s = AmbientEventScheduler(random: math.Random(1));
      expect(s.poll(now: 0, player: obelisco), isNull);
      s.start(0);
      expect(s.nextAt, inInclusiveRange(s.firstMinMs, s.firstMaxMs));
      expect(s.poll(now: s.firstMinMs - 1, player: obelisco), isNull);
    });

    test('los intervalos quedan dentro del rango y los eventos caen cerca del jugador', () {
      final s = AmbientEventScheduler(random: math.Random(7));
      s.start(0);
      var now = 0;
      var last = -1;
      final events = <AmbientEvent>[];
      while (events.length < 30) {
        now = s.nextAt!;
        final e = s.poll(now: now, player: obelisco);
        expect(e, isNotNull);
        events.add(e!);
        if (last >= 0) {
          expect(now - last, inInclusiveRange(s.minGapMs, s.maxGapMs));
        }
        last = now;
        final d = haversineM(obelisco, e.position);
        expect(d, inInclusiveRange(s.minDistM * 0.8 - 1, s.maxDistM + 1));
        expect(e.until - e.at, s.pingMs);
      }
      // Variedad: varios tipos y nunca el mismo dos veces seguidas.
      expect(events.map((e) => e.kind).toSet().length, greaterThanOrEqualTo(4));
      for (var i = 1; i < events.length; i++) {
        expect(events[i].kind, isNot(events[i - 1].kind));
      }
    });

    test('con el mapa ocupado se posterga unos segundos', () {
      final s = AmbientEventScheduler(random: math.Random(3));
      s.start(0);
      final due = s.nextAt!;
      expect(s.poll(now: due, player: obelisco, busy: true), isNull);
      expect(s.nextAt! - due, inInclusiveRange(3000, 6000));
      expect(s.poll(now: s.nextAt!, player: obelisco), isNotNull);
    });

    test('sin posición no hay eventos', () {
      final s = AmbientEventScheduler(random: math.Random(3));
      s.start(0);
      expect(s.poll(now: s.nextAt!, player: null), isNull);
    });

    test('usa el punto en la calle y su nombre cuando los hay', () {
      final s = AmbientEventScheduler(random: math.Random(11));
      s.start(0);
      final street = offsetM(obelisco, 0, 300);
      AmbientEvent? e;
      // Buscar un tipo que nombre la calle.
      for (var i = 0; i < 40; i++) {
        e = s.poll(now: s.nextAt!, player: obelisco, pickPoint: (_, _, _, _) => street, streetAt: (_) => 'Avenida Corrientes');
        if (e!.text.contains('Corrientes')) break;
      }
      expect(e!.position, street);
      expect(e.text, contains('Av. Corrientes'));
      expect(e.detail, '300 m · E');
    });
  });

  group('textos', () {
    test('con calle o con rumbo', () {
      expect(ambientText(AmbientKind.smoke, street: 'Av. Corrientes', dir: 'N'), 'Humo en Av. Corrientes');
      expect(ambientText(AmbientKind.smoke, dir: 'NO'), 'Columna de humo al NO');
      expect(ambientText(AmbientKind.shots, street: 'Lavalle', dir: 'S'), 'Disparos a lo lejos');
      expect(ambientText(AmbientKind.movement, dir: 'E'), 'Movimiento detectado');
    });

    test('nombres de calle cortos', () {
      expect(shortStreetName('Avenida 9 de Julio'), 'Av. 9 de Julio');
      expect(shortStreetName('Diagonal Norte'), 'Diag. Norte');
      expect(shortStreetName('Tucumán'), 'Tucumán');
    });
  });

  test('punto al azar sobre las calles, dentro del anillo pedido', () {
    final a = offsetM(obelisco, 200, -400);
    final b = offsetM(obelisco, 200, 400);
    final rng = math.Random(5);
    for (var i = 0; i < 20; i++) {
      final p = pointOnStreets([(a, b)], obelisco, 220, 400, rng);
      if (p == null) continue;
      final d = haversineM(obelisco, p);
      expect(d, inInclusiveRange(220, 400));
    }
    expect(pointOnStreets(const [], obelisco, 100, 200, rng), isNull);
    // Calle fuera del anillo: no hay punto.
    expect(pointOnStreets([(a, b)], obelisco, 600, 700, rng), isNull);
  });
}
