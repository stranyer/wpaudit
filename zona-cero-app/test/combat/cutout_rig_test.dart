import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/combat/cutout_rig.dart';
import 'package:zona_cero/core/types.dart';

/// RGBA de `w × h` con los rectángulos dados opacos.
Uint8List alpha(int w, int h, List<ui.Rect> opaque) {
  final out = Uint8List(w * h * 4);
  for (final r in opaque) {
    for (var y = r.top.toInt(); y < r.bottom.toInt(); y++) {
      for (var x = r.left.toInt(); x < r.right.toInt(); x++) {
        out[(y * w + x) * 4 + 3] = 255;
      }
    }
  }
  return out;
}

void main() {
  // Humanoide en 200×400: cabeza 40×50 en (80,10), un mechón suelto, hombros
  // que asoman al final de la franja, torso, piernas y un pie más largo.
  const head = ui.Rect.fromLTWH(80, 10, 40, 50);
  final figure = [
    head,
    const ui.Rect.fromLTWH(60, 30, 4, 8), // mechón/mano suelto a la altura de la cabeza
    const ui.Rect.fromLTWH(40, 62, 120, 140), // hombros + torso
    const ui.Rect.fromLTWH(60, 202, 30, 188), // pierna izquierda
    const ui.Rect.fromLTWH(110, 202, 30, 188), // pierna derecha
  ];

  group('analyzeCutout', () {
    test('caja opaca, pies, centroide y cabeza angostada a la cabeza', () {
      final rig = analyzeCutout(alpha(200, 400, figure), 200, 400)!;
      expect(rig.body, const ui.Rect.fromLTRB(40, 10, 160, 390));
      expect(rig.size, const ui.Size(200, 400));
      expect(rig.feet.dy, 390);
      expect(rig.feet.dx, closeTo(100, 1)); // entre las dos piernas
      expect(rig.centroidX, closeTo(100, 2));
      // La franja (16 % de 380 = 61 filas) cubre cabeza y el arranque de los
      // hombros: solo las columnas de la cabeza la cubren casi entera.
      expect(rig.head.left, 80);
      expect(rig.head.right, 120);
      expect(rig.head.top, 10);
      expect(rig.head.bottom, closeTo(10 + 380 * 0.16, 1));
      expect(rig.neck, ui.Offset(100, rig.head.bottom));
    });

    test('ventana de búsqueda: cabeza hundida al costado de una masa más alta', () {
      // Masa (tumores) más alta a la izquierda; la cabeza asoma a la derecha.
      final brute = [
        const ui.Rect.fromLTWH(40, 10, 70, 120),
        const ui.Rect.fromLTWH(110, 30, 40, 60),
        const ui.Rect.fromLTWH(20, 90, 170, 300),
      ];
      final rgba = alpha(200, 400, brute);
      final plain = analyzeCutout(rgba, 200, 400)!;
      // Sin pista gana la masa (cubre más la franja).
      expect(plain.head.left, lessThan(110));
      final hinted = analyzeCutout(rgba, 200, 400, hints: const RigHints(headBandTop: 0.04, headBand: 0.2, headX0: 0.53, headX1: 0.8))!;
      expect(hinted.head.left, closeTo(110, 2));
      expect(hinted.head.right, closeTo(150, 2));
      expect(hinted.head.top, 30);
    });

    test('vacío → null; zona de reserva si la franja no tiene señal', () {
      expect(analyzeCutout(Uint8List(100 * 100 * 4), 100, 100), isNull);
      expect(analyzeCutout(Uint8List(10), 100, 100), isNull);
      final rgba = alpha(100, 100, [const ui.Rect.fromLTWH(10, 10, 80, 80)]);
      final h = detectHeadZone(rgba, 100, 100, const ui.Rect.fromLTWH(10, 10, 80, 80), hints: const RigHints(headX0: 0.95, headX1: 0.96));
      expect(h.isEmpty, isFalse);
    });
  });

  group('arte real', () {
    testWidgets('la cabeza detectada está arriba, adentro y es chica', (tester) async {
      for (final type in ZombieTypeId.values) {
        final file = File('assets/art/zombies/${type.key}.webp');
        if (!file.existsSync()) return;
        final rig = (await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
          final img = (await codec.getNextFrame()).image;
          final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
          final r = analyzeCutout(data!.buffer.asUint8List(), img.width, img.height, hints: rigHints[type]!);
          img.dispose();
          return r;
        }))!;
        final b = rig.body;
        final h = rig.head;
        expect(b.height, greaterThan(1300), reason: '$type');
        expect(b.inflate(1).contains(h.center), isTrue, reason: '$type $h');
        expect(h.top - b.top, lessThan(b.height * 0.06), reason: '$type');
        expect(h.height, inInclusiveRange(b.height * 0.1, b.height * 0.24), reason: '$type');
        expect(h.width, lessThan(b.width * 0.45), reason: '$type');
        expect(h.width, greaterThan(b.width * 0.12), reason: '$type');
        // Pies sobre el borde inferior y dentro de la caja.
        expect(rig.feet.dy, b.bottom);
        expect(rig.feet.dx, inInclusiveRange(b.left, b.right));
        if (type == ZombieTypeId.brute) {
          // La cara del Bruto está a la derecha de los tumores.
          expect(h.center.dx, greaterThan(b.center.dx));
        }
      }
    });
  });
}
