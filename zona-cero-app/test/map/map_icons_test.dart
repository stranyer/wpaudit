import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';
import 'package:zona_cero/map/map_icons.dart';
import 'package:zona_cero/map/widgets/scan_wave.dart';
import 'package:zona_cero/state/world_controller.dart';
import 'package:zona_cero/ui/theme/tokens.dart';

void main() {
  group('marcadores', () {
    test('colores por tipo: refugio verde, el propio ámbar, hostiles rojos', () {
      expect(markColor(MarkKind.node), Sutura.refuge);
      expect(markColor(MarkKind.node, own: true), Sutura.amber);
      expect(markColor(MarkKind.supply), Sutura.amber);
      expect(markColor(MarkKind.signal), Sutura.amber);
      expect(markColor(MarkKind.zombie), MapIcons.hostile);
      expect(markColor(MarkKind.zone), MapIcons.hostile);
    });

    test('color en formato de MapLibre', () {
      expect(hexColor(const Color(0xFF7FC46B)), '#7FC46B');
      expect(hexColor(const Color(0x80010203)), '#010203');
    });

    test('título horneado solo si lleva etiqueta', () {
      const on = MarkSpec(MarkKind.zone, MarkerState.on, title: 'Zona infectada', labelled: true);
      const off = MarkSpec(MarkKind.zone, MarkerState.on, title: 'Zona infectada');
      expect(on.lines, ['ZONA', 'INFECTADA']);
      expect(off.lines, isEmpty);
    });

    test('cada criatura, estado y etiqueta es una imagen distinta', () {
      const a = MarkSpec(MarkKind.zombie, MarkerState.on, title: 'Caminante', labelled: true, avatar: ZombieTypeId.walker);
      const b = MarkSpec(MarkKind.zombie, MarkerState.on, title: 'Bruto', labelled: true, avatar: ZombieTypeId.brute);
      const c = MarkSpec(MarkKind.zombie, MarkerState.echo, title: 'Caminante', labelled: true, avatar: ZombieTypeId.walker);
      const d = MarkSpec(MarkKind.zombie, MarkerState.on, title: 'Caminante', labelled: true, avatar: ZombieTypeId.walker);
      expect({a.name, b.name, c.name}, hasLength(3));
      expect(a.name, d.name);
    });

    test('la distancia va debajo del título (más abajo con dos líneas)', () {
      final one = MapIcons.distanceOffset(MarkKind.node, 1);
      final two = MapIcons.distanceOffset(MarkKind.zone, 2);
      expect(one.first, 0);
      expect(one.last, greaterThan(0));
      expect(two.last, greaterThan(one.last));
    });

    test('ancho de etiqueta según la línea más larga', () {
      expect(MapIcons.labelWidth('Señal de auxilio'), greaterThan(MapIcons.labelWidth('Refugio')));
      expect(MapIcons.labelWidth('Ok'), 46);
    });

    test('retratos de las criaturas', () {
      expect(MapIcons.avatarAsset(ZombieTypeId.brute), 'assets/art/avatars/brute.webp');
    });
  });

  group('onda del escáner', () {
    test('arranca con destello y radio cero', () {
      final f = ScanWaveFrame.at(0);
      expect(f.radius, 0);
      expect(f.flash, 1);
      expect(f.glitch, 1);
    });

    test('el frente avanza con la curva del escáner y se apaga al final', () {
      var prev = -1.0;
      for (var t = 0.0; t <= WorldController.scanDurationMs; t += 100) {
        final f = ScanWaveFrame.at(t);
        expect(f.radius, greaterThanOrEqualTo(prev));
        prev = f.radius;
      }
      final mid = ScanWaveFrame.at(WorldController.scanDurationMs / 2);
      expect(mid.radius, closeTo(Sutura.scanCurve.transform(0.5), 1e-9));
      expect(mid.strength, lessThan(mid.ring));
      final end = ScanWaveFrame.at(WorldController.scanDurationMs.toDouble());
      expect(end.ring, 0);
      expect(end.strength, 0);
      expect(end.radius, 1);
    });
  });
}
