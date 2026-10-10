import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/audio/audio_engine.dart';
import 'package:zona_cero/audio/sfx.dart';

void main() {
  test('la rampa llega exactamente al objetivo en el tiempo pedido', () {
    final r = GainRamp(0)..to(0.6, const Duration(milliseconds: 500));
    for (var i = 0; i < 9; i++) {
      r.tick(0.05);
    }
    expect(r.done, isFalse);
    expect(r.value, lessThan(0.6));
    r.tick(0.05);
    expect(r.done, isTrue);
    expect(r.value, 0.6);
  });

  test('dos rampas opuestas mantienen la potencia (fundido cruzado)', () {
    final out = GainRamp(1)..to(0, const Duration(seconds: 1));
    final inn = GainRamp(0)..to(1, const Duration(seconds: 1));
    for (var i = 0; i < 20; i++) {
      out.tick(0.05);
      inn.tick(0.05);
      final power = math.pow(out.value, 2) + math.pow(inn.value, 2);
      expect(power, closeTo(1, 1e-9));
    }
  });

  test('cambiar de objetivo a mitad de rampa parte del valor actual', () {
    final r = GainRamp(0)..to(1, const Duration(seconds: 1));
    r.tick(0.5);
    final mid = r.value;
    r.to(0, const Duration(seconds: 1));
    r.tick(0.0001);
    expect(r.value, closeTo(mid, 1e-3));
    r.tick(1);
    expect(r.value, 0);
  });

  test('objetivo igual al valor: rampa terminada', () {
    final r = GainRamp(0.3)..to(0.3, const Duration(seconds: 2));
    expect(r.done, isTrue);
    expect(r.tick(0.1), 0.3);
  });

  test('voces por sonido: los efectos rápidos de combate tienen más polifonía', () {
    for (final id in SfxId.values) {
      expect(SfxTuning.voices(id), inInclusiveRange(1, 4));
    }
    expect(SfxTuning.voices(SfxId.pistolShot), greaterThan(SfxTuning.voices(SfxId.victory)));
  });
}
