import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/combat/cutout_rig.dart';
import 'package:zona_cero/combat/puppet.dart';
import 'package:zona_cero/combat/turn_plan.dart';

// Recorte de 600×1400 con el cuerpo en (100,20)–(500,1380) y la cabeza arriba al centro.
const rig = CutoutRig(
  size: Size(600, 1400),
  body: Rect.fromLTRB(100, 20, 500, 1380),
  head: Rect.fromLTRB(240, 20, 360, 240),
  feet: Offset(300, 1380),
  centroidX: 300,
);
const double bodyH = 1360;

/// Caja de la malla deformada (en px locales, escala 1, origen en los pies).
Rect boundsOf(Float32List pos) {
  var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
  for (var i = 0; i < pos.length; i += 2) {
    minX = math.min(minX, pos[i]);
    maxX = math.max(maxX, pos[i]);
    minY = math.min(minY, pos[i + 1]);
    maxY = math.max(maxY, pos[i + 1]);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

void main() {
  final mesh = PuppetMesh.grid(rig);
  final deformer = PuppetDeformer(rig);
  final out = Float32List(mesh.vertexCount * 2);

  group('malla', () {
    test('grilla de ≤ 200 vértices sobre la caja opaca, filas más densas arriba', () {
      expect(mesh.vertexCount, 11 * 17);
      expect(mesh.vertexCount, lessThanOrEqualTo(200));
      expect(mesh.indices.length, 10 * 16 * 6);
      expect(mesh.indices.reduce(math.max), mesh.vertexCount - 1);
      // UV: esquinas = caja opaca + margen, dentro de la imagen.
      expect(mesh.uv[0], 96);
      expect(mesh.uv[1], 16);
      expect(mesh.uv[mesh.uv.length - 2], 504);
      expect(mesh.uv[mesh.uv.length - 1], 1384);
      // Reposo relativo a los pies; h = 0 en los pies y ≈ 1 en la coronilla.
      final last = mesh.vertexCount - 1;
      expect(mesh.rest[last * 2 + 1], closeTo(4, 1e-3));
      expect(mesh.h[0], closeTo(1 + 4 / bodyH, 1e-6));
      expect(mesh.h[last], closeTo(-4 / bodyH, 1e-6));
      // Filas densas arriba (cabeza) y espaciadas abajo (piernas).
      final first = mesh.uv[mesh.cols * 2 + 1] - mesh.uv[1];
      final lastGap = mesh.uv[(mesh.rows - 1) * mesh.cols * 2 + 1] - mesh.uv[(mesh.rows - 2) * mesh.cols * 2 + 1];
      expect(first, lessThan(lastGap / 2));
      // Lateral normalizado y ruido 0…1.
      expect(mesh.side[0], closeTo(-204 / 200, 1e-6));
      expect(mesh.noise.every((n) => n >= 0 && n < 1), isTrue);
    });
  });

  group('deformación', () {
    test('pose neutra = reposo (pantalla = pies + reposo × escala)', () {
      deformer.deformMesh(PuppetPose(), mesh, out, 195, 734, 0.4);
      for (var i = 0; i < mesh.vertexCount; i++) {
        expect(out[i * 2], closeTo(195 + mesh.rest[i * 2] * 0.4, 1e-3));
        expect(out[i * 2 + 1], closeTo(734 + mesh.rest[i * 2 + 1] * 0.4, 1e-3));
      }
    });

    test('reposo animado: los pies no se mueven y nada se va más de un 5 % de H', () {
      final anim = PuppetAnimator(puppetStyles.values.first);
      final pose = PuppetPose();
      for (var k = 0; k < 120; k++) {
        anim.update(1 / 20);
        anim.evaluate(pose);
        deformer.deformMesh(pose, mesh, out, 0, 0, 1);
        for (var i = 0; i < mesh.vertexCount; i++) {
          final dx = out[i * 2] - mesh.rest[i * 2];
          final dy = out[i * 2 + 1] - mesh.rest[i * 2 + 1];
          final d = math.sqrt(dx * dx + dy * dy);
          expect(d, lessThan(bodyH * 0.05), reason: 'vértice $i');
          if (mesh.h[i] <= 0.005) expect(d, lessThan(1.5), reason: 'pie $i');
        }
      }
    });

    test('la cabeza rota alrededor del cuello; el resto queda quieto', () {
      final p = PuppetPose()..headAngle = 0.2;
      final neck = rig.neck - rig.feet;
      // Coronilla: rota (misma distancia al cuello, otro ángulo).
      deformer.apply(p, 0, rig.body.top - rig.feet.dy + 10);
      final before = Offset(0, rig.body.top - rig.feet.dy + 10) - neck;
      final after = Offset(deformer.outX, deformer.outY) - neck;
      expect(after.distance, closeTo(before.distance, 1e-6));
      expect((after.direction - before.direction).abs(), closeTo(0.2, 1e-6));
      // Cadera: sin cambios.
      deformer.apply(p, 0, -bodyH * 0.5);
      expect(deformer.outX, closeTo(0, 1e-9));
      expect(deformer.outY, closeTo(-bodyH * 0.5, 1e-9));
    });

    test('agacharse comprime y ensancha; las rodillas que ceden bajan la cadera', () {
      deformer.deformMesh(PuppetPose()..crouch = 1, mesh, out, 0, 0, 1);
      final c = boundsOf(out);
      deformer.deformMesh(PuppetPose(), mesh, out, 0, 0, 1);
      final r = boundsOf(out);
      expect(c.height, lessThan(r.height * 0.95));
      expect(c.width, greaterThan(r.width * 1.02));
      final p = PuppetPose()..buckle = 1;
      deformer.apply(p, 0, -bodyH * 0.5);
      expect(deformer.outY, greaterThan(-bodyH * 0.5 + bodyH * 0.15));
    });

    test('abolladura: tira de los vértices hacia el impacto, cae con la distancia', () {
      final p = PuppetPose()
        ..dent = 0.3
        ..dentX = 0
        ..dentY = -700
        ..dentR = 80;
      deformer.apply(p, 40, -700);
      expect(deformer.outX, lessThan(40));
      expect(deformer.outX, greaterThan(0));
      deformer.apply(p, 400, -700);
      expect(deformer.outX, closeTo(400, 1e-3));
    });
  });

  group('animador', () {
    test('duraciones y momentos clave coherentes con el plan del turno', () {
      for (final a in [ZombieAnim.attack, ZombieAnim.charge]) {
        final k = (PuppetAnimator.keyTimeOf(a) * 1000).round();
        expect(k, inInclusiveRange(TurnTiming.minWindup, TurnTiming.maxWindup), reason: '$a');
        expect(PuppetAnimator.keyTimeOf(a), lessThan(PuppetAnimator.durationOf(a)));
      }
      expect(PuppetAnimator.keyTimeOf(ZombieAnim.scream), lessThan(PuppetAnimator.durationOf(ZombieAnim.scream)));
    });

    test('embestida: 0 en la anticipación, 1 en el impacto, vuelve a 0', () {
      const a = ZombieAnim.attack;
      expect(PuppetAnimator.lungeEnvelope(a, 0.1), 0);
      expect(PuppetAnimator.lungeEnvelope(a, PuppetAnimator.keyTimeOf(a)), closeTo(1, 1e-9));
      expect(PuppetAnimator.lungeEnvelope(a, PuppetAnimator.durationOf(a)), closeTo(0, 1e-9));
      expect(PuppetAnimator.lungeEnvelope(ZombieAnim.idle, 0.4), 0);
    });

    test('en el impacto se agranda (hacia la cámara) y baja; hay desenfoque', () {
      final anim = PuppetAnimator(puppetStyles.values.first)..play(ZombieAnim.attack);
      anim.update(PuppetAnimator.keyTimeOf(ZombieAnim.attack));
      final pose = PuppetPose();
      anim.evaluate(pose);
      deformer.deformMesh(pose, mesh, out, 0, 0, 1);
      final lunge = boundsOf(out);
      expect(lunge.height, greaterThan(bodyH * 1.3));
      expect(pose.ty, greaterThan(0));
      expect(anim.motionBlur, greaterThan(0.9));
      // Fantasma 50 ms antes: más chico.
      anim.evaluate(pose, back: 0.05);
      deformer.deformMesh(pose, mesh, out, 0, 0, 1);
      expect(boundsOf(out).height, lessThan(lunge.height));
    });

    test('vuelve al reposo al terminar; la muerte se sostiene caída y disuelta', () {
      final anim = PuppetAnimator(puppetStyles.values.first);
      expect(anim.play(ZombieAnim.hit), PuppetAnimator.durationOf(ZombieAnim.hit));
      for (var i = 0; i < 20; i++) {
        anim.update(0.05);
      }
      expect(anim.anim, ZombieAnim.idle);
      anim.hitAt(80, -900, 90);
      expect(anim.flash, 1);
      expect(anim.fallDir, -1); // golpe a la derecha → cae a la izquierda
      anim.play(ZombieAnim.death);
      for (var i = 0; i < 60; i++) {
        anim.update(0.05);
      }
      expect(anim.anim, ZombieAnim.death);
      expect(anim.play(ZombieAnim.attack), 0); // muerta no reacciona
      final pose = PuppetPose();
      anim.evaluate(pose);
      expect(pose.rot, closeTo(-1.25, 0.01));
      expect(pose.buckle, 1);
      expect(pose.dissolve, 1);
      expect(pose.dark, greaterThan(0.7));
    });

    test('preparar la embestida: se agacha y queda agachado mientras carga', () {
      final anim = PuppetAnimator(puppetStyles.values.last)..crouchHold = true;
      anim.play(ZombieAnim.chargePrepare);
      for (var i = 0; i < 40; i++) {
        anim.update(0.05);
      }
      final pose = PuppetPose();
      anim.evaluate(pose);
      expect(pose.crouch, closeTo(1, 1e-9));
      anim.play(ZombieAnim.charge);
      expect(anim.crouchHold, isFalse);
    });
  });
}
