// Silueta de reserva de la criatura: si el recorte HD no carga, se dibuja un
// humanoide oscuro con Canvas (contorno rojo de la luz de emergencia, borde
// frío y ojos) y se rasteriza UNA vez a una imagen RGBA. Esa imagen pasa por
// el mismo títere de malla que el arte real (análisis de alfa, cabeza,
// animación), así que la escena funciona igual sin arte.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../core/types.dart';

class _Shape {
  const _Shape({
    required this.shoulderW,
    required this.waistW,
    required this.hipW,
    required this.legW,
    required this.armW,
    required this.armLen,
    required this.headR,
    this.hunch = 0,
    this.belly = 0,
    this.stance = 10,
    this.headDx = 0,
  });
  final double shoulderW, waistW, hipW, legW, armW, armLen, headR, hunch, belly, stance, headDx;
}

const Map<ZombieTypeId, _Shape> _shapes = {
  ZombieTypeId.walker: _Shape(shoulderW: 92, waistW: 62, hipW: 70, legW: 24, armW: 17, armLen: 138, headR: 21, headDx: -4),
  ZombieTypeId.runner: _Shape(shoulderW: 84, waistW: 54, hipW: 62, legW: 21, armW: 15, armLen: 132, headR: 19, stance: 22, hunch: 14),
  ZombieTypeId.bloater: _Shape(shoulderW: 104, waistW: 90, hipW: 92, legW: 30, armW: 20, armLen: 128, headR: 20, belly: 74),
  ZombieTypeId.screamer: _Shape(shoulderW: 78, waistW: 50, hipW: 58, legW: 19, armW: 13, armLen: 156, headR: 21, headDx: 3),
  ZombieTypeId.brute: _Shape(shoulderW: 158, waistW: 104, hipW: 104, legW: 38, armW: 34, armLen: 160, headR: 18, hunch: 26, stance: 18),
};

class ProceduralZombie {
  ProceduralZombie(this.type) : _s = _shapes[type]! {
    _build();
  }

  final ZombieTypeId type;
  final _Shape _s;

  static const double fw = 360;
  static const double fh = 480;
  static const double cx = 180;
  static const double footY = 470;

  late final Path _body;
  late final Path _arm;
  late final Path _armR;
  late final Offset _shoulderL;
  late final Offset _shoulderR;
  late final Offset _headC;
  late final Rect bodyBox;
  late final Rect headBox;

  void _build() {
    final s = _s;
    final top = footY - 350;
    final headCy = top + s.headR + 4 + s.hunch;
    _headC = Offset(cx + s.headDx, headCy);
    final shoulderY = headCy + s.headR + 16;
    final waistY = shoulderY + 112;
    final hipY = waistY + 26;
    final kneeY = hipY + (footY - hipY) * 0.48;

    final b = Path()..fillType = PathFillType.nonZero;
    b.addOval(Rect.fromCenter(center: _headC, width: s.headR * 1.8, height: s.headR * 2.25));
    b.addRect(Rect.fromLTRB(cx - 8 + s.headDx * 0.5, headCy + s.headR * 0.6, cx + 8 + s.headDx * 0.5, shoulderY + 8));
    final l = cx - s.shoulderW / 2;
    final r = cx + s.shoulderW / 2;
    b
      ..moveTo(l, shoulderY + 12)
      ..quadraticBezierTo(l, shoulderY - 4, l + 16, shoulderY - 6)
      ..lineTo(r - 16, shoulderY - 6)
      ..quadraticBezierTo(r, shoulderY - 4, r, shoulderY + 12)
      ..lineTo(cx + s.waistW / 2, waistY)
      ..lineTo(cx + s.hipW / 2, hipY)
      // Ruedo desgarrado.
      ..lineTo(cx + s.hipW * 0.32, hipY + 9)
      ..lineTo(cx + s.hipW * 0.18, hipY + 2)
      ..lineTo(cx + s.hipW * 0.02, hipY + 12)
      ..lineTo(cx - s.hipW * 0.16, hipY + 3)
      ..lineTo(cx - s.hipW * 0.34, hipY + 10)
      ..lineTo(cx - s.hipW / 2, hipY)
      ..lineTo(cx - s.waistW / 2, waistY)
      ..close();
    if (s.belly > 0) {
      b.addOval(Rect.fromCenter(center: Offset(cx + 4, waistY - 30), width: s.shoulderW + s.belly * 0.6, height: 130));
    }
    // Piernas (asimétricas: una arrastra).
    void leg(double dir, double stance, double drag) {
      final hipX = cx + dir * (s.hipW / 2 - s.legW / 2 - 2);
      final footX = cx + dir * (stance + s.legW / 2) + drag;
      final kneeX = (hipX + footX) / 2 + dir * 4;
      b
        ..moveTo(hipX - s.legW / 2 - 2, hipY - 6)
        ..lineTo(hipX + s.legW / 2 + 2, hipY - 6)
        ..lineTo(kneeX + s.legW / 2, kneeY)
        ..lineTo(footX + s.legW / 2 - 2, footY - 10)
        ..lineTo(footX + s.legW / 2 + dir * 6, footY)
        ..lineTo(footX - s.legW / 2 - 4, footY)
        ..lineTo(footX - s.legW / 2, footY - 12)
        ..lineTo(kneeX - s.legW / 2, kneeY)
        ..close();
    }

    leg(-1, s.stance, -4);
    leg(1, s.stance * 0.6, 6);
    _body = b;

    // Brazo en coordenadas locales (pivote en el hombro, cuelga hacia +y).
    Path arm(double len, double w) {
      final elbow = len * 0.48;
      return Path()
        ..moveTo(-w / 2, -4)
        ..quadraticBezierTo(0, -w * 0.7, w / 2, -4)
        ..lineTo(w * 0.42, elbow)
        ..lineTo(w * 0.36 + 4, len - 10)
        ..lineTo(w * 0.5 + 3, len + 6)
        ..lineTo(w * 0.2, len + 16)
        ..lineTo(-w * 0.1, len + 8)
        ..lineTo(-w * 0.35 - 2, len + 18)
        ..lineTo(-w * 0.5 - 2, len)
        ..lineTo(-w * 0.4, elbow)
        ..close();
    }

    _arm = arm(s.armLen, s.armW);
    _armR = arm(s.armLen * 0.92, s.armW);
    _shoulderL = Offset(l + 9, shoulderY + 4);
    _shoulderR = Offset(r - 9, shoulderY + 4);

    var box = _body.getBounds();
    for (final (p, a, path) in [(_shoulderL, 0.16, _arm), (_shoulderR, -0.12, _armR)]) {
      final m = Matrix4.identity()
        ..translateByDouble(p.dx, p.dy, 0, 1)
        ..rotateZ(a);
      box = box.expandToInclude(path.transform(m.storage).getBounds());
    }
    bodyBox = Rect.fromLTRB(box.left, box.top, box.right, footY);
    headBox = Rect.fromCenter(center: _headC.translate(0, -2), width: s.headR * 1.8, height: s.headR * 2.0);

  }

  /// Rasteriza la silueta en reposo a `scale ×` (fondo transparente).
  ui.Image toImage({double scale = 2}) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.scale(scale, scale);
    final rimRed = Paint()
      ..color = const Color(0xD0EE3B45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final rimCold = Paint()
      ..color = const Color(0x708DB4C9)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    final fill = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, footY - 350),
        const Offset(0, footY),
        const [Color(0xFF2A3034), Color(0xFF15191C), Color(0xFF0B0D0F)],
        const [0, 0.5, 1],
      );
    _silhouette(c, rimCold, dx: -2.5);
    _silhouette(c, rimRed, dx: 3);
    _silhouette(c, fill);
    final eye = Paint()..color = const Color(0xC8D8E4DA);
    c.drawCircle(_headC.translate(-6, -1), 2.2, eye);
    c.drawCircle(_headC.translate(6, 0), 1.8, eye);
    final pic = rec.endRecording();
    final img = pic.toImageSync((fw * scale).round(), (fh * scale).round());
    pic.dispose();
    return img;
  }

  void _silhouette(Canvas c, Paint paint, {double dx = 0}) {
    c.save();
    if (dx != 0) c.translate(dx, 0);
    c.drawPath(_body, paint);
    for (final (p, a, path) in [(_shoulderL, 0.16, _arm), (_shoulderR, -0.12, _armR)]) {
      c.save();
      c.translate(p.dx, p.dy);
      c.rotate(a);
      c.drawPath(path, paint);
      c.restore();
    }
    c.restore();
  }
}
