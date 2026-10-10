// Silueta de reserva del zombie (si faltan las tiras): un humanoide oscuro
// dibujado con Canvas, con borde rojo de la luz de emergencia y animaciones
// por transformaciones. Las rutas y pinturas se crean una sola vez.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/rendering.dart';

import '../core/types.dart';
import 'combat_manifest.dart';

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
  ProceduralZombie(this.type, {this.groundInFrame = 0.92}) : _s = _shapes[type]! {
    _build();
  }

  final ZombieTypeId type;
  final double groundInFrame;
  final _Shape _s;

  static const double fw = 360;
  static const double fh = 480;
  static const double cx = 180;
  double get footY => fh * groundInFrame;

  late final Path _body;
  late final Path _arm;
  late final Path _armR;
  late final Offset _shoulderL;
  late final Offset _shoulderR;
  late final Offset _headC;
  late final Rect bodyBox;
  late final Rect headBox;

  final Paint _fill = Paint();
  final Paint _rimRed = Paint()
    ..color = const Color(0xC8EE3B45)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
  final Paint _rimCold = Paint()
    ..color = const Color(0x5A6ADBEA)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
  final Paint _eye = Paint()..color = const Color(0xB8D8E4DA);
  final Paint _shadow = Paint()
    ..color = const Color(0x99000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
  final Paint _overlay = Paint();

  static double durationOf(ZombieAnim a) => switch (a) {
    ZombieAnim.idle => 2.4,
    ZombieAnim.attack => 0.66,
    ZombieAnim.hit => 0.34,
    ZombieAnim.death => 1.1,
    ZombieAnim.chargePrepare => 0.6,
    ZombieAnim.charge => 0.6,
    ZombieAnim.scream => 0.9,
  };

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

    _fill.shader = ui.Gradient.linear(
      Offset(0, top),
      Offset(0, footY),
      const [Color(0xFF1B2125), Color(0xFF0C0F11), Color(0xFF050607)],
      const [0, 0.5, 1],
    );
  }

  /// Dibuja la silueta en `frameDst` (el rectángulo de pantalla del cuadro).
  ///
  /// `t` = segundos desde que empezó `anim`; `idleT` = reloj continuo.
  void render(
    Canvas c, {
    required Rect frameDst,
    required ZombieAnim anim,
    required double t,
    required double idleT,
    double flash = 0,
    bool flashRed = false,
    double glow = 0,
  }) {
    final d = durationOf(anim);
    final p = anim == ZombieAnim.idle ? 0.0 : (t / d).clamp(0.0, 1.0);
    // Pose base (reposo con balanceo).
    var lean = 0.025 * math.sin(idleT * 1.5);
    var squash = 1 + 0.012 * math.sin(idleT * 2.1);
    var lunge = 1.0;
    var dy = 0.0;
    var armL = 0.16 + 0.06 * math.sin(idleT * 1.3);
    var armR = -0.12 - 0.05 * math.sin(idleT * 1.1 + 1);
    var alpha = 1.0;
    switch (anim) {
      case ZombieAnim.idle:
        break;
      case ZombieAnim.attack:
      case ZombieAnim.charge:
        final big = anim == ZombieAnim.charge ? 1.25 : 1.13;
        final wind = _bump(p, 0, 0.35, 0.4, 0.5);
        final strike = _bump(p, 0.35, 0.5, 0.6, 1);
        lean += -0.05 * wind;
        lunge = 1 + (big - 1) * strike;
        armL = armL - 1.9 * wind + 0.4 * strike;
        armR = armR + 1.9 * wind - 0.4 * strike;
      case ZombieAnim.hit:
        final k = _bump(p, 0, 0.15, 0.3, 1);
        lean += -0.09 * k;
        dy = -8 * k;
        lunge = 1 - 0.035 * k;
      case ZombieAnim.death:
        final k = Curves.easeIn.transform(p);
        lean += 1.42 * k;
        dy = 14 * k;
        alpha = 1 - 0.25 * k;
        armL += 0.6 * k;
        armR -= 0.9 * k;
      case ZombieAnim.chargePrepare:
        final k = Curves.easeOut.transform(p);
        squash *= 1 - 0.07 * k;
        lunge = 1 + 0.03 * k;
        armL += 0.5 * k;
        armR -= 0.5 * k;
      case ZombieAnim.scream:
        final k = _bump(p, 0, 0.25, 0.7, 1);
        lunge = 1 + 0.06 * k + 0.015 * math.sin(t * 60) * k;
        armL -= 1.1 * k;
        armR += 1.1 * k;
    }

    c.save();
    c.translate(frameDst.left, frameDst.top);
    c.scale(frameDst.width / fw, frameDst.height / fh);
    // Sombra en el piso.
    c.drawOval(Rect.fromCenter(center: Offset(cx, footY), width: _s.shoulderW * 1.6, height: 22), _shadow);
    // Pose alrededor de los pies.
    c.translate(cx, footY + dy);
    c.rotate(lean);
    c.scale(lunge, lunge * squash);
    c.translate(-cx, -footY);

    if (alpha < 1) c.saveLayer(null, _overlay..color = Color.fromARGB((alpha * 255).round(), 255, 255, 255));
    _silhouette(c, _rimCold, armL, armR, dx: -2.5);
    _silhouette(c, _rimRed, armL, armR, dx: 3.5);
    if (glow > 0) {
      _rimRed.color = Color.fromARGB((120 * glow).round().clamp(0, 255), 238, 59, 69);
      _silhouette(c, _rimRed, armL, armR, dx: 0, grow: 3);
      _rimRed.color = const Color(0xC8EE3B45);
    }
    _silhouette(c, _fill, armL, armR);
    if (anim != ZombieAnim.death) {
      c.drawCircle(_headC.translate(-6, -1), 2.2, _eye);
      c.drawCircle(_headC.translate(6, 0), 1.8, _eye);
    }
    if (flash > 0) {
      final a = (flash.clamp(0.0, 1.0) * 150).round();
      _overlay.color = flashRed ? Color.fromARGB(a, 255, 70, 70) : Color.fromARGB(a, 240, 248, 250);
      _silhouette(c, _overlay, armL, armR);
    }
    if (alpha < 1) c.restore();
    c.restore();
  }

  void _silhouette(Canvas c, Paint paint, double armL, double armR, {double dx = 0, double grow = 0}) {
    c.save();
    if (dx != 0) c.translate(dx, 0);
    if (grow > 0) {
      final k = 1 + grow / 100;
      c.translate(cx, footY);
      c.scale(k, k);
      c.translate(-cx, -footY);
    }
    c.drawPath(_body, paint);
    c.save();
    c.translate(_shoulderL.dx, _shoulderL.dy);
    c.rotate(armL);
    c.drawPath(_arm, paint);
    c.restore();
    c.save();
    c.translate(_shoulderR.dx, _shoulderR.dy);
    c.rotate(armR);
    c.drawPath(_armR, paint);
    c.restore();
    c.restore();
  }

  static double _bump(double t, double a, double b, double c, double d) {
    if (t <= a || t >= d) return 0;
    if (t < b) return Curves.easeOut.transform((t - a) / (b - a));
    if (t <= c) return 1;
    return 1 - Curves.easeInOut.transform((t - c) / (d - c));
  }
}
