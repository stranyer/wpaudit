import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/combat/fp_hand.dart';
import 'package:zona_cero/core/types.dart';

void main() {
  group('mano según el arma', () {
    test('fuego: pistola o escopeta; cuerpo a cuerpo: arma o puños', () {
      expect(handFor(WeaponMode.firearm, firearm: ItemId.pistol, melee: ItemId.nailBat), HandKind.pistol);
      expect(handFor(WeaponMode.firearm, firearm: ItemId.shotgun), HandKind.shotgun);
      expect(handFor(WeaponMode.melee, firearm: ItemId.pistol, melee: ItemId.nailBat), HandKind.melee);
      for (final m in [ItemId.pipe, ItemId.machete, ItemId.fireAxe, ItemId.nailBat]) {
        expect(handFor(WeaponMode.melee, melee: m), HandKind.melee, reason: '$m');
      }
      expect(handFor(WeaponMode.melee), HandKind.fists);
      expect(handFor(WeaponMode.melee, firearm: ItemId.pistol), HandKind.fists);
      // Modo fuego sin arma de fuego (no debería pasar): no se queda sin mano.
      expect(handFor(WeaponMode.firearm, melee: ItemId.pipe), HandKind.melee);
      expect(handFor(WeaponMode.firearm), HandKind.fists);
    });

    test('recortes y reservas', () {
      expect(HandKind.pistol.asset, 'assets/art/fp/fp_pistol.webp');
      expect(HandKind.fists.asset, 'assets/art/fp/fp_fists.webp');
      expect(HandKind.melee.fallback, HandKind.fists);
      expect(HandKind.shotgun.fallback, HandKind.pistol);
      expect(HandKind.fists.fallback, isNull);
      expect(HandKind.pistol.firearm && HandKind.shotgun.firearm, isTrue);
      expect(HandKind.melee.firearm || HandKind.fists.firearm, isFalse);
      for (final k in HandKind.values) {
        expect(handSpecs[k], isNotNull, reason: '$k');
        expect(handSpecs[k]!.muzzle != null, k.firearm, reason: '$k');
      }
      expect(handSpecs[HandKind.fists]!.split, isTrue);
      expect(handSpecs[HandKind.fists]!.aspect, 1.5);
    });

    test('encuadre: entra por abajo a la derecha, apoyada en la botonera', () {
      const view = Size(390, 844);
      for (final k in HandKind.values) {
        final spec = handSpecs[k]!;
        final r = handRect(spec, view, 776);
        expect(r.left + r.width, greaterThanOrEqualTo(view.width), reason: '$k: llega al borde derecho');
        expect(r.top + r.height, closeTo(776 + spec.overBottom * view.width, 1e-9), reason: '$k');
        expect(r.width / r.height, closeTo(spec.aspect, 1e-9));
        expect(r.top, greaterThan(view.height * 0.45), reason: '$k: no tapa la criatura entera');
      }
    });
  });

  group('animación de la mano', () {
    HandPose at(HandRig rig, double t, {int side = 0}) {
      rig.update(t);
      final p = HandPose();
      rig.evaluate(p, side: side);
      return p;
    }

    test('reposo: vaivén chico', () {
      final rig = HandRig(HandKind.pistol);
      for (var i = 0; i < 100; i++) {
        final p = at(rig, 0.05);
        expect(p.dx.abs(), lessThan(0.02));
        expect(p.dy.abs(), lessThan(0.02));
        expect(p.rot.abs(), lessThan(0.03));
      }
    });

    test('disparo: fogonazo corto, retroceso que sube y vuelve', () {
      final rig = HandRig(HandKind.pistol);
      final rest = at(rig, 0.5);
      rig.shoot();
      expect(rig.flash, 1);
      final kick = at(rig, 0.035);
      expect(rig.flash, greaterThan(0));
      expect(kick.rot - rest.rot, greaterThan(0.1));
      expect(kick.dy, greaterThan(rest.dy));
      at(rig, 0.1);
      expect(rig.flash, 0);
      final back = at(rig, 0.8);
      expect((back.rot - rest.rot).abs(), lessThan(0.03));
    });

    test('escopeta: retroceso más fuerte que la pistola', () {
      final p = HandRig(HandKind.pistol)..shoot();
      final s = HandRig(HandKind.shotgun)..shoot();
      expect(at(s, 0.035).rot, greaterThan(at(p, 0.035).rot));
    });

    test('cuerpo a cuerpo: el arma barre hacia la izquierda y vuelve; sin fogonazo', () {
      final rig = HandRig(HandKind.melee);
      rig.swing(const Offset(-0.3, -0.3));
      expect(rig.flash, 0);
      final strike = at(rig, HandRig.swingDur * 0.36);
      expect(strike.rot, lessThan(-0.6));
      expect(strike.dx, lessThan(-0.12));
      expect(rig.swingSpeed, greaterThan(0));
      final end = at(rig, HandRig.swingDur);
      expect(end.rot.abs(), lessThan(0.05));
    });

    test('puños: alternan; el que pega sale hacia el centro y se aleja (se achica)', () {
      final rig = HandRig(HandKind.fists);
      rig.swing(const Offset(-0.4, -0.5));
      final side = rig.punchSide;
      final hit = at(rig, HandRig.punchDur * 0.3, side: side);
      expect(hit.scale, lessThan(0.85));
      expect(hit.dy, lessThan(-0.08));
      // Gira desde el codo hacia adentro (la derecha a la izquierda y viceversa).
      expect(hit.rot * side, lessThan(-0.15));
      final other = HandPose();
      rig.evaluate(other, side: -side);
      expect(other.scale, greaterThan(0.95));
      rig.swing(const Offset(0, -0.4));
      expect(rig.punchSide, -side);
    });

    test('guardia (CUBRIRSE), sacudón al recibir y mano baja al final', () {
      final rig = HandRig(HandKind.pistol);
      final rest = at(rig, 0.2);
      rig.guard = true;
      final g = at(rig, 1);
      expect(g.dy, lessThan(rest.dy - 0.03));
      expect(g.scale, greaterThan(1.05));
      rig.guard = false;
      at(rig, 1);
      rig.dip();
      final d = at(rig, 0.05);
      expect(d.dy, greaterThan(0.05));
      rig.lowered = true;
      expect(at(rig, 2).dy, greaterThan(0.5));
    });

    test('cambio de arma: baja, cambia a mitad y vuelve a subir', () {
      final rig = HandRig(HandKind.pistol);
      rig.swap(HandKind.fists);
      expect(rig.kind, HandKind.pistol);
      final mid = at(rig, HandRig.swapDur * 0.55);
      expect(rig.kind, HandKind.fists);
      expect(mid.dy, greaterThan(0.4));
      at(rig, HandRig.swapDur);
      expect(rig.swapping, isFalse);
      rig.snap(HandKind.shotgun);
      expect(rig.kind, HandKind.shotgun);
    });
  });
}
