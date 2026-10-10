// [CreatureView] de hoy: el recorte HD de la criatura sobre una malla que se
// deforma (ver puppet.dart), dibujado con `Canvas.drawVertices`.
//
// Para que no parezca un recorte de papel pegado sobre la foto:
// - sombra de contacto doble (difusa + oclusión pegada a los pies) y reflejo
//   ondulado en el asfalto mojado;
// - sombreado "de volumen": el lado que se aleja al girar el torso se oscurece
//   (ver `PuppetPose.yaw`);
// - luz de linterna que barre el cuerpo lentamente, relleno cálido de los
//   faroles y luz de borde del lado que corresponde a la placa.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'combat_art.dart';
import 'creature_view.dart';
import 'puppet.dart';

final Float64List _identity = Float64List.fromList(const [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

class PuppetCreatureView implements CreatureView {
  PuppetCreatureView(this.art, {PuppetStyle? style})
    : style = style ?? puppetStyles[art.type] ?? const PuppetStyle(),
      mesh = PuppetMesh.grid(art.rig),
      anim = PuppetAnimator(style ?? puppetStyles[art.type] ?? const PuppetStyle(), seed: art.type.index * 7 + 3) {
    deformer = PuppetDeformer(art.rig, armInner: this.style.armInner);
    final n = mesh.vertexCount;
    _pos = Float32List(n * 2);
    _ghost = Float32List(n * 2);
    _refl = Float32List(n * 2);
    _cMain = Int32List(n);
    _cAux = Int32List(n);
    _theta = Float32List(n);
    for (var i = 0; i < n; i++) {
      _theta[i] = math.asin(mesh.side[i].clamp(-0.985, 0.985));
    }
    _shader = ImageShader(art.cutout, TileMode.clamp, TileMode.clamp, _identity, filterQuality: FilterQuality.medium);
    _main = Paint()..shader = _shader;
    _add = Paint()
      ..shader = _shader
      ..blendMode = BlendMode.plus;
    _white = Paint()
      ..shader = _shader
      ..colorFilter = const ColorFilter.mode(Color(0xFFF4F1EA), BlendMode.srcIn);
    _red = Paint()
      ..shader = _shader
      ..colorFilter = const ColorFilter.mode(Color(0xFFE2362C), BlendMode.srcIn);
    _glow = Paint()
      ..shader = _shader
      ..colorFilter = const ColorFilter.mode(Color(0xFFFF2A1E), BlendMode.srcIn);
  }

  final CombatArt art;
  final PuppetStyle style;
  final PuppetMesh mesh;
  late final PuppetDeformer deformer;

  /// Animador (reloj, animación en curso, impulsos). Público para los tests.
  final PuppetAnimator anim;
  final PuppetPose pose = PuppetPose();
  final PuppetPose _ghostPose = PuppetPose();

  late final Float32List _pos, _ghost, _refl, _theta;
  late final Int32List _cMain, _cAux;
  late final ImageShader _shader;
  late final Paint _main, _add, _white, _red, _glow;
  final Paint _blurLayer = Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 2.2, sigmaY: 4.5);
  final Paint _glowLayer = Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14);
  final Paint _shadow = Paint()
    ..shader = ui.Gradient.radial(Offset.zero, 1, const [Color(0xF0000000), Color(0x80000000), Color(0x00000000)], const [0, 0.45, 1]);

  bool _hasPose = false;
  double _ox = 0, _oy = 0, _scale = 1, _bodyH = 1;
  double _bx0 = 0, _by0 = 0, _bx1 = 0, _by1 = 0;
  double _hx0 = 0, _hy0 = 0, _hx1 = 0, _hy1 = 0;
  double _fleeT = -1;

  @override
  bool get hasPose => _hasPose;

  @override
  bool get dead => anim.dead;

  @override
  Rect get bodyWorld => _hasPose ? Rect.fromLTRB(_bx0, _by0, _bx1, _by1) : Rect.zero;

  @override
  Rect get headWorld => _hasPose && !anim.dead ? Rect.fromLTRB(_hx0, _hy0, _hx1, _hy1) : Rect.zero;

  @override
  double get lunge => PuppetAnimator.lungeEnvelope(anim.anim, anim.t);

  @override
  double get dissolve => pose.dissolve;

  @override
  set holdCrouch(bool value) => anim.crouchHold = value && !anim.dead;

  // ---------------------------------------------------------------------------
  // Eventos
  // ---------------------------------------------------------------------------

  @override
  void idle() {
    if (!anim.dead) anim.play(ZombieAnim.idle);
  }

  @override
  double attack() => anim.play(ZombieAnim.attack);

  @override
  double chargePrepare() => anim.play(ZombieAnim.chargePrepare);

  @override
  double charge() => anim.play(ZombieAnim.charge);

  @override
  double scream() => anim.play(ZombieAnim.scream);

  @override
  double die() => anim.play(ZombieAnim.death);

  @override
  void flee() => _fleeT = 0;

  @override
  void hit(Offset at, {bool strong = false, bool crit = false, bool headshot = false, bool lethal = false}) {
    if (anim.dead) return;
    if (!lethal) anim.play(ZombieAnim.hit);
    if (_scale <= 0) return;
    final lx = (at.dx - _ox) / _scale, ly = (at.dy - _oy) / _scale;
    anim.hitAt(lx, ly, art.rig.body.height * 0.07, crit: crit, headshot: headshot, strength: strong || crit ? 1.2 : 1);
  }

  @override
  double keyTime(ZombieAnim a) => PuppetAnimator.keyTimeOf(a);

  @override
  double duration(ZombieAnim a) => PuppetAnimator.durationOf(a);

  // ---------------------------------------------------------------------------
  // Ciclo
  // ---------------------------------------------------------------------------

  @override
  void dispose() => _shader.dispose();

  @override
  void update(double dt, CreatureStage stage) {
    anim.update(dt);
    if (_fleeT >= 0) _fleeT = math.min(1, _fleeT + dt / 0.8);
    final l = stage.layout;
    if (l == null) return;
    _ox = l.feet.dx;
    _oy = l.feet.dy;
    _scale = l.scale;
    _bodyH = l.body.height;
    anim.evaluate(pose);
    _applyFlee(pose);
    deformer.deformMesh(pose, mesh, _pos, _ox, _oy, _scale);
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final x = _pos[i * 2], y = _pos[i * 2 + 1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    _bx0 = minX;
    _by0 = minY;
    _bx1 = maxX;
    _by1 = maxY;
    // Cabeza en la pose actual (sus 4 esquinas por el mismo deformador).
    final h = art.rig.head;
    final fx = art.rig.feet.dx, fy = art.rig.feet.dy;
    _hx0 = _hy0 = double.infinity;
    _hx1 = _hy1 = -double.infinity;
    _headCorner(h.left - fx, h.top - fy);
    _headCorner(h.right - fx, h.top - fy);
    _headCorner(h.left - fx, h.bottom - fy);
    _headCorner(h.right - fx, h.bottom - fy);
    _hasPose = true;
  }

  /// Al huir el jugador, la criatura queda atrás: se achica y se apaga.
  void _applyFlee(PuppetPose p) {
    if (_fleeT <= 0) return;
    final e = _fleeT * _fleeT * (3 - 2 * _fleeT);
    p.scale *= 1 - 0.18 * e;
    p.pivotH = 0;
    p.dark = math.min(1, p.dark + 0.45 * e);
  }

  void _headCorner(double x, double y) {
    deformer.apply(pose, x, y);
    final sx = _ox + deformer.outX * _scale, sy = _oy + deformer.outY * _scale;
    if (sx < _hx0) _hx0 = sx;
    if (sx > _hx1) _hx1 = sx;
    if (sy < _hy0) _hy0 = sy;
    if (sy > _hy1) _hy1 = sy;
  }

  @override
  Offset? randomPoint(math.Random rnd, {required double minH, required double maxH, required double maxSide}) {
    if (!_hasPose) return null;
    for (var k = 0; k < 6; k++) {
      final i = rnd.nextInt(mesh.vertexCount);
      final h = mesh.h[i];
      if (h < minH || h > maxH || mesh.side[i].abs() > maxSide) continue;
      if (pose.dissolve > 0 && _vertexAlpha(i) < 0.15) continue;
      return Offset(_pos[i * 2], _pos[i * 2 + 1]);
    }
    return null;
  }

  double _vertexAlpha(int i) {
    var a = pose.alpha;
    final d = pose.dissolve;
    if (d > 0) {
      final hc = mesh.h[i].clamp(0.0, 1.0);
      final v = 0.6 * mesh.noise[i] + 0.4 * hc;
      final c = 1.12 - 1.24 * d;
      a *= 1 - smooth(c - 0.12, c + 0.12, v);
    }
    return a;
  }

  static int _argb(double a, double r, double g, double b) =>
      ((a.clamp(0.0, 1.0) * 255).round() << 24) | ((r.clamp(0.0, 1.0) * 255).round() << 16) | ((g.clamp(0.0, 1.0) * 255).round() << 8) | (b.clamp(0.0, 1.0) * 255).round();

  void _draw(Canvas canvas, Float32List pos, Int32List colors, Paint paint) {
    final v = ui.Vertices.raw(ui.VertexMode.triangles, pos, textureCoordinates: mesh.uv, colors: colors, indices: mesh.indices);
    canvas.drawVertices(v, BlendMode.modulate, paint);
    v.dispose();
  }

  @override
  void render(Canvas canvas, CreatureStage stage) {
    if (!_hasPose) return;
    final l = stage.layout;
    if (l == null) return;
    final look = stage.look;
    final t = stage.time;
    final n = mesh.vertexCount;
    final env = lunge;
    final fall = anim.dead ? smooth(0.2, 0.9, anim.t) : 0.0;
    final floor = l.floorY;
    final bodyH = _bodyH;
    final hidden = floor > stage.hudTop + 6;
    final alive = !anim.dead;

    // 1. Sombra de contacto: mancha difusa ancha + oclusión pegada a los pies.
    final shadowA = (1 - env * 0.7) * (1 - fall);
    if (shadowA > 0.02 && !hidden) {
      final w = l.body.width * (1 + 0.25 * pose.crouch);
      final cx = _ox + pose.tx * bodyH * 0.2;
      canvas.save();
      canvas.translate(cx, floor + 3);
      canvas.scale(w * 0.62, bodyH * 0.05);
      _shadow.color = Color.fromARGB((shadowA * 0.85 * 255).round(), 255, 255, 255);
      canvas.drawCircle(Offset.zero, 1, _shadow);
      canvas.restore();
      canvas.save();
      canvas.translate(cx, floor + 1);
      canvas.scale(w * 0.34, bodyH * 0.016);
      _shadow.color = Color.fromARGB((shadowA * 255).round(), 255, 255, 255);
      canvas.drawCircle(Offset.zero, 1, _shadow);
      canvas.restore();
    }

    // Colores base por vértice: gradación de la placa (piernas en sombra,
    // torso en luz), volumen por el giro y disolución.
    final dark = 1 - pose.dark;
    final sr = look.shadowTint.r, sg = look.shadowTint.g, sb = look.shadowTint.b;
    final lr = look.lightTint.r, lg = look.lightTint.g, lb = look.lightTint.b;
    final yaw = pose.yaw;
    for (var i = 0; i < n; i++) {
      final hc = mesh.h[i].clamp(0.0, 1.0);
      final k = smooth(0.0, 0.55, hc);
      // Lambert de un cilindro que gira: el lado que se aleja cae a la sombra.
      final a = _theta[i] + yaw * smooth(0.08, 0.55, hc) - 0.35 * look.fillSide;
      final vol = 0.74 + 0.26 * math.cos(a.clamp(-1.57, 1.57));
      final m = dark * vol;
      _cMain[i] = _argb(_vertexAlpha(i), (sr + (lr - sr) * k) * m, (sg + (lg - sg) * k) * m, (sb + (lb - sb) * k) * m);
    }

    // 2. Reflejo en el asfalto mojado (invertido, comprimido, ondulado, borroso).
    final reflA = 0.34 * (1 - env) * (1 - fall) * pose.alpha;
    if (reflA > 0.02 && !hidden) {
      var minX = double.infinity, maxX = -double.infinity, maxY = floor;
      for (var i = 0; i < n; i++) {
        final y = _pos[i * 2 + 1];
        final d = math.max(0.0, floor - y) * 0.36;
        final ry = floor + d;
        final x = _pos[i * 2] + math.sin(ry * 0.11 + t * 2.7) * (1.2 + d * 0.035);
        _refl[i * 2] = x;
        _refl[i * 2 + 1] = ry;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (ry > maxY) maxY = ry;
        final hc = mesh.h[i].clamp(0.0, 1.0);
        final a = reflA * (1 - smooth(0.0, 0.75, hc)) * _vertexAlpha(i);
        _cAux[i] = _argb(a, 0.52, 0.56, 0.64);
      }
      canvas.saveLayer(Rect.fromLTRB(minX - 20, floor - 6, maxX + 20, maxY + 20), _blurLayer);
      _draw(canvas, _refl, _cAux, _main);
      canvas.restore();
    }

    // 3. Resplandor rojo al preparar la embestida (silueta difusa detrás).
    final glow = stage.charging && alive ? 0.5 + 0.5 * math.sin(t * 9) : 0.0;
    if (glow > 0.01) {
      final c = _argb(0.16 + 0.24 * glow, 1, 1, 1);
      for (var i = 0; i < n; i++) {
        _cAux[i] = c;
      }
      canvas.saveLayer(Rect.fromLTRB(_bx0 - 40, _by0 - 40, _bx1 + 40, _by1 + 40), _glowLayer);
      _draw(canvas, _pos, _cAux, _glow);
      canvas.restore();
    }

    // 4. Cuerpo.
    _draw(canvas, _pos, _cMain, _main);

    // 5. Fantasmas del desenfoque de movimiento (embestida).
    final blur = anim.motionBlur;
    if (blur > 0.02) {
      const alphas = [0.3, 0.2, 0.12];
      for (var k = 0; k < alphas.length; k++) {
        anim.evaluate(_ghostPose, back: 0.026 * (k + 1));
        deformer.deformMesh(_ghostPose, mesh, _ghost, _ox, _oy, _scale);
        final a = blur * alphas[k];
        for (var i = 0; i < n; i++) {
          _cAux[i] = (_cMain[i] & 0x00FFFFFF) | ((a * 255).round() << 24);
        }
        _draw(canvas, _ghost, _cAux, _main);
      }
    }

    // 6. Luces aditivas en una sola pasada: borde (late con la baliza),
    //    relleno cálido de los faroles y la linterna que barre el cuerpo.
    final lit = dark * pose.alpha;
    if (lit > 0.02) {
      final beacon = look.emergency ? stage.beacon : 0.0;
      final rimK = (look.rimBase + look.rimBeacon * beacon) * lit;
      final fillK = look.fillAmount * lit;
      // Linterna: el centro deriva despacio de lado a lado y de arriba abajo.
      final bx = 0.55 * math.sin(t * 0.41) + 0.2 * math.sin(t * 1.07 + 1.3);
      final by = 0.62 + 0.16 * math.sin(t * 0.29 + 0.4);
      final torchK = (0.2 + 0.06 * math.sin(t * 2.3)) * lit * (1 - 0.6 * env);
      final rr = look.rim.r, rg = look.rim.g, rb = look.rim.b;
      final fr = look.fill.r, fg = look.fill.g, fb = look.fill.b;
      for (var i = 0; i < n; i++) {
        final va = _vertexAlpha(i);
        if (va < 0.5) {
          _cAux[i] = 0xFF000000;
          continue;
        }
        final hc = mesh.h[i].clamp(0.0, 1.0);
        final sd = mesh.side[i];
        final rim = rimK * smooth(-0.15, 1.0, sd * look.rimSide) * (0.35 + 0.65 * hc);
        final fill = fillK * smooth(-0.4, 1.0, sd * look.fillSide) * (0.25 + 0.75 * hc);
        final dx = sd - bx, dy = (hc - by) * 1.6;
        final torch = torchK * math.exp(-(dx * dx + dy * dy) / 0.32);
        _cAux[i] = _argb(1, rim * rr + fill * fr + torch * 0.86, rim * rg + fill * fg + torch * 0.92, rim * rb + fill * fb + torch);
      }
      _draw(canvas, _pos, _cAux, _add);
    }

    // 7. Destello del impacto: blanco → rojo.
    final f = anim.flash;
    if (f > 0.01) {
      final w = smooth(0.5, 0.95, f) * 0.8;
      final r = bump(f, 0.0, 0.5, 0.85) * (anim.flashCrit ? 0.75 : 0.55);
      if (w > 0.01) {
        for (var i = 0; i < n; i++) {
          _cAux[i] = _argb(w * _vertexAlpha(i), 1, 1, 1);
        }
        _draw(canvas, _pos, _cAux, _white);
      }
      if (r > 0.01) {
        for (var i = 0; i < n; i++) {
          _cAux[i] = _argb(r * _vertexAlpha(i), 1, 1, 1);
        }
        _draw(canvas, _pos, _cAux, _red);
      }
    }
  }
}
