import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/combat/combat_manifest.dart';

/// RGBA de una tira de `frames` cuadros de w×h con rectángulos opacos.
Uint8List strip(int frames, int w, int h, List<List<Rect>> opaque) {
  final out = Uint8List(frames * w * h * 4);
  for (var f = 0; f < frames; f++) {
    for (final r in opaque[f]) {
      for (var y = r.top.toInt(); y < r.bottom.toInt(); y++) {
        for (var x = r.left.toInt(); x < r.right.toInt(); x++) {
          out[(y * frames * w + f * w + x) * 4 + 3] = 255;
        }
      }
    }
  }
  return out;
}

void main() {
  group('CombatManifest.parse', () {
    test('lee el manifiesto real de assets/combat', () {
      final file = File('assets/combat/manifest.json');
      if (!file.existsSync()) return; // el arte puede no estar en otras ramas
      final m = CombatManifest.parse(file.readAsStringSync());
      expect(m.frameWidth, 360);
      expect(m.frameHeight, 480);
      expect(m.fps, 15);
      expect(m.background.file, 'bg_street.jpg');
      expect(m.background.foreground, 'bg_street_fg.webp');
      for (final t in ['walker', 'runner', 'bloater', 'screamer', 'brute']) {
        expect(m.hasSprites(t), isTrue, reason: t);
        final idle = m.animsFor(t)[ZombieAnim.idle]!;
        expect(idle.loop, isTrue);
        expect(m.animsFor(t)[ZombieAnim.death]!.holdLast, isTrue);
      }
      expect(m.animsFor('brute')[ZombieAnim.charge], isNotNull);
      expect(m.animsFor('brute')[ZombieAnim.chargePrepare]!.holdLast, isTrue);
      expect(m.animsFor('screamer')[ZombieAnim.scream]!.peakFrame, isNotNull);
      final w = m.placementFor('walker');
      expect(w.bgRect, const Rect.fromLTWH(0, 320, 720, 960));
      expect(w.groundBgY, closeTo(1203.2, 0.01));
      expect(w.groundInFrame, closeTo(0.92, 1e-6));
      // El bruto está más lejos: apoya más arriba en el fondo.
      expect(m.placementFor('brute').groundBgY, lessThan(w.groundBgY));
      // Cada tira existe y su grilla entra en una textura de 4096 px (GPUs de gama baja).
      for (final t in ['walker', 'runner', 'bloater', 'screamer', 'brute']) {
        for (final a in m.animsFor(t).values) {
          expect(File('assets/combat/${a.file}').existsSync(), isTrue, reason: a.file);
          final cols = a.columns ?? a.frames;
          expect(cols * m.frameWidth, lessThanOrEqualTo(4096), reason: a.file);
          expect((a.frames / cols).ceil() * m.frameHeight, lessThanOrEqualTo(4096), reason: a.file);
        }
      }
    });

    test('tolerante: anim inválida se descarta, números como texto, ancla en px', () {
      final m = CombatManifest.parse('''
        {"frameWidth": "200", "frameHeight": 300, "fps": 12,
         "anchor": {"x": 360, "y": 1139.2},
         "zombies": {"walker": {
            "idle": {"file": "w_idle.png", "frames": "4"},
            "attack": {"file": "w_attack.png", "frames": 6, "impactFrame": 2, "columns": 3},
            "hit": {"frames": 3},
            "dance": {"file": "x.png", "frames": 2}
         }}}''');
      expect(m.frameWidth, 200);
      expect(m.fps, 12);
      expect(m.anchor.dx, closeTo(0.5, 1e-9));
      expect(m.anchor.dy, closeTo(0.89, 1e-9));
      final anims = m.animsFor('walker');
      expect(anims.keys, containsAll([ZombieAnim.idle, ZombieAnim.attack]));
      expect(anims.containsKey(ZombieAnim.hit), isFalse); // sin archivo
      expect(anims[ZombieAnim.idle]!.loop, isTrue); // idle repite por defecto
      expect(anims[ZombieAnim.attack]!.loop, isFalse);
      // Grilla de 3 columnas: el cuadro 4 está en la 2.ª fila.
      expect(anims[ZombieAnim.attack]!.frameRect(4, 200, 300), const Rect.fromLTWH(200, 300, 200, 300));
      expect(anims[ZombieAnim.attack]!.keyTime(12), closeTo(2.5 / 12, 1e-9));
      expect(m.filesFor('walker'), containsAll(['w_idle.png', 'w_attack.png', 'bg_street.jpg']));
    });

    test('sin "placement": cuadro ×spriteScale apoyado en el ancla', () {
      final m = CombatManifest.parse('{"zombies": {}}');
      final p = m.placementFor('walker');
      expect(p.bgRect, const Rect.fromLTWH(0, 320, 720, 960));
      expect(p.groundInFrame, CombatManifest.defaultGroundInFrame);
      expect(p.groundBgY, closeTo(1280 - 960 * 0.08, 1e-9));
    });

    test('reserva cuando falta o está roto', () {
      expect(CombatManifest.tryParse(null), isNull);
      expect(CombatManifest.tryParse(''), isNull);
      expect(CombatManifest.tryParse('{nope'), isNull);
      expect(CombatManifest.tryParse('[1,2]'), isNull);
      const f = CombatManifest.fallback;
      expect(f.isFallback, isTrue);
      expect(f.hasSprites('walker'), isFalse);
      expect(f.placementFor('brute').bgRect.height, 960);
    });
  });

  group('StageLayout', () {
    const bg = Size(720, 1280);

    test('cubre la vista y apoya el fondo abajo en teléfonos altos', () {
      final l = StageLayout.compute(view: const Size(390, 844), bg: bg);
      expect(l.scale, closeTo(844 / 1280, 1e-9));
      final r = l.bgScreenRect;
      expect(r.left, lessThanOrEqualTo(0));
      expect(r.right, greaterThanOrEqualTo(390));
      expect(r.top, closeTo(0, 1e-9));
      expect(r.bottom, closeTo(844, 1e-9));
    });

    test('la línea de suelo queda a la misma altura relativa en distintas proporciones', () {
      for (final v in const [Size(360, 640), Size(390, 844), Size(412, 915), Size(360, 800)]) {
        final l = StageLayout.compute(view: v, bg: bg);
        final ground = l.toScreen(const Offset(360, 1203.2)).dy;
        expect(v.height - ground, closeTo((1280 - 1203.2) * l.scale, 1e-6), reason: '$v');
        expect(l.bgScreenRect.width, greaterThanOrEqualTo(v.width - 1e-6));
      }
    });

    test('vistas anchas: se recorta el cielo y se limita la escala', () {
      final l = StageLayout.compute(view: const Size(800, 900), bg: bg, frameBgHeight: 960);
      expect(l.bgScreenRect.bottom, closeTo(900, 1e-9));
      expect(960 * l.scale, lessThanOrEqualTo(900 * 0.82 + 1e-6));
    });

    test('frameBoxToScreen escala la caja del cuadro', () {
      final r = frameBoxToScreen(const Rect.fromLTWH(90, 120, 180, 240), const Size(360, 480), const Rect.fromLTWH(10, 20, 720, 960));
      expect(r, const Rect.fromLTWH(190, 260, 360, 480));
    });
  });

  group('cajas por alfa', () {
    // Humanoide: cabeza 20×20 en (40,10), mano suelta al lado de la cabeza,
    // hombros anchos desde y=34, piernas hasta y=90, reflejo débil abajo.
    List<Rect> body(double dx) => [
          Rect.fromLTWH(40 + dx, 10, 20, 22), // cabeza + cuello
          Rect.fromLTWH(75 + dx, 14, 8, 8), // mano levantada (separada)
          Rect.fromLTWH(25 + dx, 32, 50, 30), // torso
          Rect.fromLTWH(35 + dx, 62, 30, 28), // piernas
        ];

    test('alphaBodyBox une cuadros y recorta en la línea de suelo', () {
      final rgba = strip(2, 100, 100, [body(0), body(4)]);
      final box = alphaBodyBox(
        rgba: rgba,
        imageWidth: 200,
        frameWidth: 100,
        frameHeight: 100,
        frames: const [Rect.fromLTWH(0, 0, 100, 100), Rect.fromLTWH(100, 0, 100, 100)],
        step: 1,
        groundInFrame: 0.85,
      )!;
      expect(box.left, 25);
      expect(box.right, 83 + 4);
      expect(box.top, 10);
      expect(box.bottom, 85);
    });

    test('alphaHeadBox sigue la cabeza, ignora la mano y corta en los hombros', () {
      // Cuadro de 100×160: maxFrac (16 %) deja buscar hasta 26 filas.
      final rgba = strip(1, 100, 160, [body(0)]);
      final head = alphaHeadBox(
        rgba: rgba,
        imageWidth: 100,
        frameWidth: 100,
        frameHeight: 160,
        frame: const Rect.fromLTWH(0, 0, 100, 160),
      )!;
      expect(head.left, 40);
      expect(head.right, 60); // la mano en x=75 no cuenta
      expect(head.top, 10);
      // 22 filas (10..31) menos 12 % de cuello.
      expect(head.bottom, closeTo(10 + 22 * 0.88, 1e-9));
    });

    test('cuadro vacío → null', () {
      final rgba = Uint8List(100 * 100 * 4);
      expect(
        alphaHeadBox(rgba: rgba, imageWidth: 100, frameWidth: 100, frameHeight: 100, frame: const Rect.fromLTWH(0, 0, 100, 100)),
        isNull,
      );
      expect(
        alphaBodyBox(rgba: rgba, imageWidth: 100, frameWidth: 100, frameHeight: 100, frames: const [Rect.fromLTWH(0, 0, 100, 100)]),
        isNull,
      );
    });
  });
}
