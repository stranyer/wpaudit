import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/combat/cutout_rig.dart';
import 'package:zona_cero/combat/stage_layout.dart';
import 'package:zona_cero/core/types.dart';

const rig = CutoutRig(
  size: Size(640, 1400),
  body: Rect.fromLTRB(20, 20, 620, 1380),
  head: Rect.fromLTRB(250, 20, 370, 240),
  feet: Offset(330, 1380),
  centroidX: 310,
);
const plate = Size(1024, 1536);

void main() {
  test('la placa cubre la vista; horizonte a ~40 % sin dejar bordes', () {
    for (final v in const [Size(390, 844), Size(412, 915), Size(360, 640), Size(800, 900)]) {
      final l = StageLayout.compute(view: v, plate: plate, rig: rig);
      final p = l.plateRect;
      expect(p.left, lessThanOrEqualTo(1e-6), reason: '$v');
      expect(p.right, greaterThanOrEqualTo(v.width - 1e-6), reason: '$v');
      expect(p.top, lessThanOrEqualTo(1e-6), reason: '$v');
      expect(p.bottom, greaterThanOrEqualTo(v.height - 1e-6), reason: '$v');
      expect(p.width / p.height, closeTo(plate.width / plate.height, 1e-9));
      final horizon = p.top + p.height * 0.39;
      expect(horizon / v.height, inInclusiveRange(0.36, 0.42), reason: '$v');
    }
    // Vista ancha: hay margen para llevar el horizonte justo al 40 %.
    final wide = StageLayout.compute(view: const Size(800, 900), plate: plate, rig: rig);
    expect((wide.plateRect.top + wide.plateRect.height * 0.39) / 900, closeTo(0.40, 1e-9));
  });

  test('criatura: pies a la altura pedida, alto pedido, centrada por su masa', () {
    const v = Size(390, 844);
    const prof = PlacementProfile(heightFrac: 0.64, feetFrac: 0.87, maxWidthFrac: 2);
    final l = StageLayout.compute(view: v, plate: plate, rig: rig, profile: prof);
    expect(l.floorY, closeTo(844 * 0.87, 1e-9));
    expect(l.body.height, closeTo(844 * 0.64, 1e-6));
    expect(l.body.bottom, closeTo(l.floorY, 1e-6));
    // El centroide (no el pie ni la caja) queda en el centro de la pantalla.
    expect(l.toScreen(Offset(rig.centroidX, 0)).dx, closeTo(195, 1e-6));
    // Cabeza mapeada con la misma transformación, dentro del cuerpo.
    expect(l.body.contains(l.head.center), isTrue);
    expect(l.head.top, closeTo(l.body.top, 1e-6));
    // Ida y vuelta pantalla ↔ local.
    final s = l.toScreen(const Offset(400, 700));
    final back = l.toLocal(s);
    expect(back.dx, closeTo(400 - rig.feet.dx, 1e-6));
    expect(back.dy, closeTo(700 - rig.feet.dy, 1e-6));
  });

  test('siluetas anchas: tope de ancho', () {
    const wide = CutoutRig(
      size: Size(1000, 1400),
      body: Rect.fromLTRB(20, 20, 980, 1380),
      head: Rect.fromLTRB(500, 20, 640, 240),
      feet: Offset(500, 1380),
      centroidX: 500,
    );
    const prof = PlacementProfile(heightFrac: 0.75, maxWidthFrac: 1.0);
    final l = StageLayout.compute(view: const Size(390, 844), plate: plate, rig: wide, profile: prof);
    expect(l.body.width, closeTo(390, 1e-6));
    expect(l.body.height, lessThan(844 * 0.75));
  });

  test('perfiles: todos los tipos, pies abajo y el Bruto más grande', () {
    for (final t in ZombieTypeId.values) {
      final p = placementProfiles[t]!;
      expect(p.feetFrac, inInclusiveRange(0.73, 0.78), reason: '$t');
      expect(p.heightFrac, inInclusiveRange(0.42, 0.56), reason: '$t');
    }
    expect(placementProfiles[ZombieTypeId.brute]!.heightFrac, greaterThan(placementProfiles[ZombieTypeId.walker]!.heightFrac));
  });

  test('vista vacía → encuadre nulo', () {
    final l = StageLayout.compute(view: Size.zero, plate: plate, rig: rig);
    expect(l.body, Rect.zero);
  });
}
