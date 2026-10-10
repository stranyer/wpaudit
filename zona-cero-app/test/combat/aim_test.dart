import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/combat/aim.dart';
import 'package:zona_cero/core/balance.dart';

void main() {
  const body = Rect.fromLTWH(100, 200, 160, 400);
  const head = Rect.fromLTWH(140, 200, 60, 60);

  group('retícula', () {
    test('se cierra de 64 a 16 dp en 700 ms y se mantiene un rato', () {
      expect(reticleRadius(0), AimTuning.maxRadius);
      var last = reticleRadius(0);
      for (var ms = 20.0; ms <= 700; ms += 20) {
        final r = reticleRadius(ms);
        expect(r, lessThanOrEqualTo(last + 1e-9), reason: 'ms=$ms');
        last = r;
      }
      expect(reticleRadius(700), closeTo(AimTuning.minRadius, 1e-6));
      expect(reticleRadius(700 + AimTuning.holdMs - 1), closeTo(AimTuning.minRadius, 1e-6));
    });

    test('el tiro limpio (≥ 0.9) no llega antes de ~400 ms', () {
      expect(tightnessFor(reticleRadius(300)), lessThan(AimTuning.headTightness));
      expect(tightnessFor(reticleRadius(520)), greaterThanOrEqualTo(AimTuning.headTightness));
    });

    test('si se mantiene demasiado, respira (se abre y se vuelve a cerrar)', () {
      final start = AimTuning.shrinkMs + AimTuning.holdMs;
      // Pico de la onda (medio período) ya con la rampa completa.
      final peak = reticleRadius(start + AimTuning.breathPeriodMs * 1.5);
      expect(peak, greaterThan(AimTuning.minRadius + 20));
      final trough = reticleRadius(start + AimTuning.breathPeriodMs * 2);
      expect(trough, closeTo(AimTuning.minRadius, 0.5));
    });
  });

  group('precisión', () {
    test('cabeza + retícula cerrada → crítico garantizado (≥ 0.9)', () {
      final p = precisionFor(tightness: 1, point: head.center, body: body, head: head);
      expect(p, greaterThanOrEqualTo(precisionCritThreshold));
      expect(p, closeTo(1, 1e-9));
      final edge = precisionFor(tightness: 0.9, point: head.center, body: body, head: head);
      expect(edge, closeTo(precisionCritThreshold, 1e-9));
    });

    test('torso: nunca alcanza el crítico garantizado', () {
      final p = precisionFor(tightness: 1, point: body.center, body: body, head: head);
      expect(p, AimTuning.bodyCap);
      expect(p, lessThan(precisionCritThreshold));
      // Cabeza pero retícula abierta: tampoco.
      expect(precisionFor(tightness: 0.8, point: head.center, body: body, head: head), lessThan(precisionCritThreshold));
    });

    test('fuera del cuerpo cae linealmente hasta 0', () {
      expect(onTargetFactor(body.center, body), 1);
      final half = Offset(body.right + AimTuning.offTargetFalloff / 2, body.center.dy);
      expect(onTargetFactor(half, body), closeTo(0.5, 1e-9));
      final far = Offset(body.right + AimTuning.offTargetFalloff * 2, body.center.dy);
      expect(onTargetFactor(far, body), 0);
      expect(precisionFor(tightness: 1, point: far, body: body, head: head), 0);
      expect(precisionFor(tightness: 0.5, point: half, body: body, head: head), closeTo(0.25, 1e-9));
    });

    test('zonas; cabeza oculta (Rect.zero) desactiva el tiro a la cabeza', () {
      expect(zoneFor(head.center, body, head), AimZone.head);
      expect(zoneFor(body.center, body, head), AimZone.body);
      expect(zoneFor(const Offset(0, 0), body, head), AimZone.off);
      expect(zoneFor(head.center, body, Rect.zero), AimZone.body);
      expect(precisionFor(tightness: 1, point: head.center, body: body, head: Rect.zero), AimTuning.bodyCap);
      // Sin caja de cabeza: franja superior centrada del cuerpo.
      expect(zoneFor(Offset(body.center.dx, body.top + 5), body), AimZone.head);
      expect(zoneFor(Offset(body.left + 2, body.top + 5), body), AimZone.body);
    });
  });

  group('AimState', () {
    test('señales: cerrada y cargada (solo cuerpo a cuerpo con resistencia)', () {
      final a = AimState()..start(const Offset(180, 500), canCharge: true);
      expect(a.point, const Offset(180, 500 - AimTuning.fingerOffset));
      final signals = <AimSignal>[];
      for (var ms = 0; ms < 1400; ms += 16) {
        final s = a.advance(16);
        if (s != AimSignal.none) signals.add(s);
      }
      expect(signals, [AimSignal.locked, AimSignal.charged]);
      expect(a.charged, isTrue);

      final b = AimState()..start(Offset.zero, canCharge: false);
      for (var ms = 0; ms < 2000; ms += 16) {
        b.advance(16);
      }
      expect(b.charged, isFalse);
    });

    test('la carga llega 450 ms después de cerrarse', () {
      final a = AimState()..start(Offset.zero, canCharge: true);
      a.advance(AimTuning.shrinkMs + AimTuning.chargeAfterMs - 20);
      a.advance(1); // consume la señal de cerrada
      expect(a.charged, isFalse);
      a.advance(25);
      expect(a.charged, isTrue);
    });

    test('soltar devuelve el disparo y desactiva', () {
      final a = AimState()..start(head.center.translate(0, AimTuning.fingerOffset), canCharge: false);
      a.advance(800);
      final shot = a.release(body, head);
      expect(shot.zone, AimZone.head);
      expect(shot.headshot, isTrue);
      expect(shot.heldMs, 800);
      expect(a.active, isFalse);
      a.start(body.center.translate(0, AimTuning.fingerOffset), canCharge: false);
      a.move(const Offset(5, 5));
      a.advance(100);
      final quick = a.release(body, head);
      expect(quick.zone, AimZone.off);
      expect(quick.precision, 0);
    });
  });
}
