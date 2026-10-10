import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';
import 'package:zona_cero/map/map_math.dart';

const obelisco = LatLng(-34.60372, -58.38159);

Zone _zone(CellCoord c) => Zone(cellId: cellId(c), threat: ZoneThreat.infested, bounds: cellBounds(c));

void main() {
  group('escala', () {
    test('metros por píxel: zoom 16 en Buenos Aires ≈ 0,98 m', () {
      expect(metersPerPixel(-34.6, 16), closeTo(0.983, 0.005));
      // Cada nivel de zoom divide la escala por dos.
      expect(metersPerPixel(-34.6, 17), closeTo(metersPerPixel(-34.6, 16) / 2, 1e-9));
    });

    test('elige el mayor tramo redondo que entra en el ancho', () {
      final s = scaleBarFor(lat: -34.6, zoom: 16, maxPx: 110);
      expect(s.meters, 100);
      expect(s.px, closeTo(100 / metersPerPixel(-34.6, 16), 1e-9));
      expect(s.px, lessThanOrEqualTo(110));
      expect(s.labels, ['0', '50', '100 m']);
    });

    test('alejado pasa a kilómetros y acercado a tramos chicos', () {
      final far = scaleBarFor(lat: -34.6, zoom: 12.5, maxPx: 110);
      expect(far.meters, 1000);
      expect(far.labels, ['0', '0,5', '1 km']);
      final near = scaleBarFor(lat: -34.6, zoom: 19, maxPx: 110);
      expect(near.meters, 10);
      expect(near.labels.last, '10 m');
    });
  });

  group('escala táctica', () {
    test('tramo con marca a un tercio ("0  100  300 m")', () {
      final s = tacticalScaleFor(lat: -34.6, zoom: 14, maxPx: 96);
      expect(s.meters, 300);
      expect(s.labels, ['0', '100', '300 m']);
      expect(s.ticks, [0, 1 / 3, 1]);
      expect(s.px, lessThanOrEqualTo(96));
    });

    test('a zoom 16 entra un tramo corto y honesto', () {
      final s = tacticalScaleFor(lat: -34.6, zoom: 16, maxPx: 96);
      expect(s.meters, 75);
      expect(s.labels, ['0', '25', '75 m']);
      expect(s.px, closeTo(75 / metersPerPixel(-34.6, 16), 1e-9));
    });

    test('alejado pasa a kilómetros', () {
      final s = tacticalScaleFor(lat: -34.6, zoom: 11, maxPx: 96);
      expect(s.labels.last, endsWith('km'));
      expect(s.labels, ['0', '1', '3 km']);
    });
  });

  group('día de supervivencia', () {
    int at(int y, int m, int d, [int h = 12]) => DateTime(y, m, d, h).millisecondsSinceEpoch;

    test('el día de creación es el día 1', () {
      expect(survivalDay(at(2026, 10, 4, 9), at(2026, 10, 4, 23)), 1);
    });

    test('cuenta días de calendario, no bloques de 24 h', () {
      expect(survivalDay(at(2026, 10, 4, 23), at(2026, 10, 5, 1)), 2);
      expect(survivalDay(at(2026, 10, 4, 9), at(2026, 10, 10, 15)), 7);
    });

    test('nunca menos que 1 (reloj atrasado)', () {
      expect(survivalDay(at(2026, 10, 10), at(2026, 10, 1)), 1);
    });
  });

  group('rumbo', () {
    test('puntos cardinales en castellano', () {
      expect(compassLabel(0), 'N');
      expect(compassLabel(44), 'NE');
      expect(compassLabel(90), 'E');
      expect(compassLabel(225), 'SO');
      expect(compassLabel(270), 'O');
      expect(compassLabel(315), 'NO');
      expect(compassLabel(359), 'N');
      expect(compassLabel(-90), 'O');
    });
  });

  group('títulos de marcadores', () {
    test('cortan en dos líneas si son largos', () {
      expect(markTitleLines('Zona infectada'), ['ZONA', 'INFECTADA']);
      expect(markTitleLines('Señal de auxilio'), ['SEÑAL', 'DE AUXILIO']);
    });

    test('los cortos quedan en una línea', () {
      expect(markTitleLines('Refugio'), ['REFUGIO']);
      expect(markTitleLines('Caminante'), ['CAMINANTE']);
      expect(markTitleLines('Tu refugio'), ['TU REFUGIO']);
    });
  });

  group('región', () {
    test('pie del emblema: CABA, conurbano y afuera', () {
      expect(regionCaption(obelisco), ['CIUDAD AUTÓNOMA', 'DE BUENOS AIRES', 'ARG.']);
      expect(regionCaption(const LatLng(-34.75, -58.4)).first, 'GRAN BUENOS AIRES');
      expect(regionCaption(const LatLng(-31.42, -64.18), placeName: 'Córdoba').first, 'CÓRDOBA');
      expect(regionCaption(null).first, 'ZONA DESCONOCIDA');
    });

    test('CABA: Buenos Aires y C.A.B.A.', () {
      final r = regionLabels(obelisco);
      expect(r.city, 'BUENOS AIRES');
      expect(r.region, 'C.A.B.A.');
    });

    test('conurbano (AMBA fuera de CABA)', () {
      final r = regionLabels(const LatLng(-34.75, -58.4)); // Lomas de Zamora
      expect(r.city, 'BUENOS AIRES');
      expect(r.region, 'G.B.A.');
    });

    test('fuera del AMBA usa el lugar del mapa o "zona desconocida"', () {
      const cordoba = LatLng(-31.42, -64.18);
      expect(regionLabels(cordoba, placeName: 'Córdoba').city, 'CÓRDOBA');
      expect(regionLabels(cordoba).city, 'ZONA DESCONOCIDA');
      expect(regionLabels(null).city, 'ZONA DESCONOCIDA');
    });
  });

  group('etiquetas', () {
    final mpp = metersPerPixel(obelisco.lat, 16);

    test('lleva etiqueta lo más cercano, hasta el máximo', () {
      final c = [
        for (var i = 0; i < 8; i++) LabelCandidate('c$i', offsetM(obelisco, i * 150.0, 0), i * 150.0 + 10),
      ];
      final out = pickLabelled(c, metersPerPx: mpp, max: 3);
      expect(out, {'c0', 'c1', 'c2'});
    });

    test('saltea las que se pisarían en pantalla y prioriza la seleccionada', () {
      final a = LabelCandidate('a', obelisco, 10);
      final b = LabelCandidate('b', offsetM(obelisco, 5, 5), 12); // encima de "a"
      final c = LabelCandidate('c', offsetM(obelisco, -300, 0), 300);
      expect(pickLabelled([a, b, c], metersPerPx: mpp), {'a', 'c'});
      expect(pickLabelled([a, b, c], metersPerPx: mpp, selectedId: 'b'), {'b', 'c'});
    });

    test('las etiquetas angostas no chocan aunque estén cerca', () {
      final a = LabelCandidate('a', obelisco, 10, width: 40);
      final b = LabelCandidate('b', offsetM(obelisco, 0, 60), 12, width: 40); // 60 m al este ≈ 61 px
      expect(pickLabelled([a, b], metersPerPx: mpp), {'a', 'b'});
      final wide = LabelCandidate('a', obelisco, 10, width: 120);
      expect(pickLabelled([wide, b], metersPerPx: mpp), {'a'});
    });

    test('las etiquetas van centradas debajo del ícono: un vecino a la izquierda también choca', () {
      final a = LabelCandidate('a', obelisco, 10, width: 80);
      final left = LabelCandidate('l', offsetM(obelisco, 0, -50), 20, width: 80); // 50 m al oeste
      expect(pickLabelled([a, left], metersPerPx: mpp), {'a'});
      // Bien arriba (fuera de la caja vertical), no choca.
      final above = LabelCandidate('u', offsetM(obelisco, 90, 0), 20, width: 80);
      expect(pickLabelled([a, above], metersPerPx: mpp), {'a', 'u'});
    });

    test('las que ya tenían etiqueta la conservan ante un empate cercano', () {
      final a = LabelCandidate('a', obelisco, 100);
      final b = LabelCandidate('b', offsetM(obelisco, 400, 0), 95);
      expect(pickLabelled([a, b], metersPerPx: mpp, max: 1), {'b'});
      expect(pickLabelled([a, b], metersPerPx: mpp, max: 1, previous: {'a'}), {'a'});
    });
  });

  group('textos', () {
    test('nombre corto del refugio', () {
      expect(shelterShortName('Nodo Plaza Lavalle'), 'Plaza Lavalle');
      expect(shelterShortName('Refugio de la Boca'), 'La Boca');
      expect(shelterShortName('Bastión de Mayo'), 'Bastión de Mayo');
    });

    test('distancias', () {
      expect(distanceLabel(183.4), '183 m');
      expect(distanceLabel(1240), '1,2 km');
      expect(distanceLabel(double.infinity), '— m');
    });
  });

  group('zonas infestadas', () {
    test('un marcador por grupo de celdas contiguas, dentro del grupo', () {
      final base = cellOf(obelisco);
      final group = [base, CellCoord(base.cx + 1, base.cy), CellCoord(base.cx + 1, base.cy + 1)];
      final lonely = CellCoord(base.cx + 6, base.cy - 4);
      final zones = [for (final c in [...group, lonely]) _zone(c)];
      final centers = infestedClusterCenters(zones);
      expect(centers, hasLength(2));
      final groupCenters = {for (final c in group) cellCenter(c)};
      expect(centers.where(groupCenters.contains), hasLength(1));
      expect(centers, contains(cellCenter(lonely)));
    });

    test('el área roja cubre el grupo y tiene un mínimo', () {
      final base = cellOf(obelisco);
      final lonely = infestedClusters([_zone(base)]);
      expect(lonely.single.radiusM, minZoneRadiusM);
      expect(lonely.single.cells, 1);
      final row = [for (var i = 0; i < 4; i++) _zone(CellCoord(base.cx + i, base.cy))];
      final big = infestedClusters(row).single;
      expect(big.cells, 4);
      expect(big.radiusM, greaterThan(minZoneRadiusM));
    });

    test('ignora las zonas tranquilas', () {
      final c = cellOf(obelisco);
      final calm = Zone(cellId: cellId(c), threat: ZoneThreat.calm, bounds: cellBounds(c));
      expect(infestedClusterCenters([calm]), isEmpty);
    });
  });
}
