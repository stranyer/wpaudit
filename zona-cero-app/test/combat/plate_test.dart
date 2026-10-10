import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/combat/combat_art.dart';
import 'package:zona_cero/combat/cutout_rig.dart';
import 'package:zona_cero/combat/stage_layout.dart';

const rig = CutoutRig(
  size: Size(640, 1400),
  body: Rect.fromLTRB(20, 20, 620, 1380),
  head: Rect.fromLTRB(250, 20, 370, 240),
  feet: Offset(330, 1380),
  centroidX: 310,
);

void main() {
  test('FNV-1a de 32 bits (valores de referencia, también en web)', () {
    expect(fnv1a32(''), 0x811C9DC5);
    expect(fnv1a32('a'), 0xE40C292C);
    expect(fnv1a32('foobar'), 0xBF9CF968);
  });

  test('placa por aparición: determinística, ~60 % Colón / ~40 % Obelisco', () {
    expect(plateForSpawn('z-123'), plateForSpawn('z-123'));
    var colon = 0;
    const n = 4000;
    for (var i = 0; i < n; i++) {
      if (plateForSpawn('cell-${i * 7919}-zombie-$i') == CombatPlate.colon) colon++;
    }
    expect(colon / n, inInclusiveRange(0.56, 0.64));
    expect(CombatPlate.colon.asset, 'assets/art/bg/combat_colon.webp');
    expect(CombatPlate.obelisco.asset, 'assets/art/bg/combat_street.webp');
  });

  test('Colón: placa más ancha que la vista, baja con cielo arriba, horizonte a la cintura', () {
    const view = Size(390, 844);
    const plate = Size(1024, 1536);
    final c = CombatPlate.colon;
    final l = StageLayout.compute(
      view: view,
      plate: plate,
      rig: rig,
      plateHorizon: c.horizon,
      horizonAt: c.horizonAt,
      plateCover: c.cover,
      plateFocusX: c.focusX,
      plateTopGap: c.topGap,
    );
    final p = l.plateRect;
    // Cubre el ancho (se ve más de la placa que con "cover" puro).
    expect(p.left, lessThanOrEqualTo(1e-6));
    expect(p.right, greaterThanOrEqualTo(view.width - 1e-6));
    expect(view.width / p.width, greaterThan(0.8));
    // Altura pedida y punto de fuga donde se lo quiere.
    expect(p.height, closeTo(view.height * c.cover, 1e-6));
    expect(p.top, inInclusiveRange(0, view.height * c.topGap + 1e-6));
    expect((p.top + p.height * c.horizon) / view.height, closeTo(c.horizonAt, 0.02));
    // El piso de la placa llega a los pies de la criatura.
    expect(p.bottom, greaterThan(l.floorY));
  });

  test('relieve: altura suavizada ponderada por alfa; afuera, la media', () {
    // 8×8, mitad izquierda opaca (altura 200), derecha transparente.
    final rgba = Uint8List(8 * 8 * 4);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final o = (y * 8 + x) * 4;
        if (x < 4) {
          rgba[o] = 200;
          rgba[o + 2] = 255;
        }
      }
    }
    final d = ReliefDepth(8, 8, rgba, cutoutWidth: 32, cutoutHeight: 32);
    expect(d.mean, closeTo(200 / 255, 1e-9));
    expect(d.heightAt(4, 4, radius: 1), closeTo(200 / 255, 1e-9));
    // Cerca del borde toma la de la silueta (no cae a 0).
    expect(d.heightAt(17, 16, radius: 1), closeTo(200 / 255, 1e-9));
    // Lejos de todo: la media.
    expect(d.heightAt(31, 31, radius: 1), closeTo(d.mean, 1e-9));
  });
}
