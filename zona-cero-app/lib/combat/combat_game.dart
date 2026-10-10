// Escenario Flame del combate: placa de calle bajo la lluvia, la criatura HD
// animada como títere de malla, lluvia en dos profundidades, niebla baja,
// reflejo en el asfalto mojado, luz de emergencia, efectos, gradación de
// pantalla (viñeta fría, grano) y la retícula de puntería con su marco.
//
// Todo se dibuja en coordenadas de pantalla (dp). Las capas "de mundo" van
// dentro de un `_CameraRig` que aplica respiración, temblor y zoom; las de
// pantalla (luz, viñeta, grano, retícula) no se mueven con la cámara.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/rendering.dart' hide Matrix4;
import 'package:flutter/services.dart' show AssetBundle;

import '../core/types.dart';
import '../ui/theme/tokens.dart';
import 'aim.dart';
import 'combat_art.dart';
import 'fx_pool.dart';
import 'puppet.dart';
import 'stage_layout.dart';

/// Estilo de la retícula según el arma activa.
enum AimStyle { melee, firearm }

/// Verde tóxico de las ampollas del Hinchado.
const _toxic = Color(0xFF9BE04A);

final Float64List _identity = Float64List.fromList(const [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

class CombatStageGame extends FlameGame {
  CombatStageGame({required this.zombieType, this.bundle, this.onAimSignal, this.onReady})
    : puppet = PuppetAnimator(puppetStyles[zombieType] ?? const PuppetStyle(), seed: zombieType.index * 7 + 3);

  final ZombieTypeId zombieType;

  /// Bundle de assets (por defecto `rootBundle`; los tests pasan uno propio).
  final AssetBundle? bundle;

  /// Umbrales de la retícula (para hápticos): cerrada, cargada.
  final void Function(AimSignal signal)? onAimSignal;
  final VoidCallback? onReady;

  /// Animador del títere (reloj, animación en curso, impulsos).
  final PuppetAnimator puppet;

  CombatArt? _art;
  CombatArt? get art => _art;
  bool get artReady => _art != null;

  StageLayout? _layout;
  StageLayout? get layout => _layout;
  int _layoutVersion = 0;
  Offset _pivot = Offset.zero;

  // Reloj y cámara.
  double time = 0;
  double _trauma = 0;
  double _kick = 0;
  double _fleeT = -1;
  double _downT = -1;

  // Estado de escena que fija la UI.
  bool stunned = false;
  bool charging = false;
  double healthRatio = 1;

  /// Combate terminado (se apaga el marco de puntería).
  bool ended = false;

  /// Desde dónde (y, pantalla) el HUD inferior tapa la escena: el reflejo y la
  /// sombra de contacto no se dibujan si quedan enteros detrás.
  double hudTop = double.infinity;

  final AimState aim = AimState();
  AimStyle aimStyle = AimStyle.melee;

  late final _CreatureLayer _creature;
  late final _FxLayer _fx;
  late final _ScreenLayer _screen;
  double _vaporIn = 0;
  double _ashIn = 0;
  final math.Random _rnd = math.Random();

  @override
  Color backgroundColor() => Sutura.void_;

  @override
  Future<void> onLoad() async {
    final art = await CombatArt.load(zombieType, bundle: bundle);
    _art = art;
    _creature = _CreatureLayer(art, puppet, puppetStyles[zombieType] ?? const PuppetStyle());
    _fx = _FxLayer(art.fxAtlas);
    _screen = _ScreenLayer(art);
    final rig = _CameraRig();
    await rig.addAll([
      _Backdrop(art),
      _Rain(front: false, count: 150, seed: 2),
      _Fog(front: false, atlas: art.fxAtlas),
      _creature,
      _fx,
      _Fog(front: true, atlas: art.fxAtlas),
      _Rain(front: true, count: 64, seed: 9),
    ]);
    await add(rig);
    await add(_screen);
    await add(_ReticleLayer());
    _relayout();
    onReady?.call();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _relayout();
  }

  @override
  void onDispose() {
    _creature.disposeShader();
    _art?.dispose();
    _art = null;
    super.onDispose();
  }

  void _relayout() {
    final art = _art;
    if (art == null || size.x <= 0 || size.y <= 0) return;
    final view = Size(size.x, size.y);
    final l = StageLayout.compute(
      view: view,
      plate: art.plateSize,
      rig: art.rig,
      profile: placementProfiles[zombieType] ?? const PlacementProfile(),
      plateHorizon: art.plateHorizon,
    );
    _layout = l;
    _layoutVersion++;
    _pivot = Offset(view.width / 2, l.body.top + l.body.height * 0.32);
  }

  @override
  void update(double dt) {
    // Con cuadros lentos la animación sigue en tiempo real (los turnos se
    // cronometran con temporizadores reales): solo se recortan los tirones grandes.
    final d = dt.clamp(0.0, 0.2);
    time += d;
    _trauma = math.max(0, _trauma - d * 1.6);
    _kick = math.max(0, _kick - d * 3.5);
    if (_fleeT >= 0) _fleeT = math.min(1, _fleeT + d / 0.8);
    if (_downT >= 0) _downT = math.min(1, _downT + d / 1.1);
    puppet.crouchHold = charging && !puppet.dead;
    puppet.update(d);
    if (aim.active) {
      final s = aim.advance(dt.clamp(0.0, 0.25) * 1000);
      if (s != AimSignal.none) onAimSignal?.call(s);
    }
    if (_art != null && _layout != null) _emitAmbient(d);
    super.update(d);
  }

  /// Vapor tóxico del Hinchado y ceniza de la disolución.
  void _emitAmbient(double dt) {
    final c = _creature;
    if (!c.hasPose) return;
    if (zombieType == ZombieTypeId.bloater && !puppet.dead) {
      _vaporIn -= dt;
      if (_vaporIn <= 0) {
        _vaporIn = 0.07 + _rnd.nextDouble() * 0.06;
        final p = c.randomPoint(_rnd, minH: 0.25, maxH: 0.8, maxSide: 0.85);
        if (p != null) _fx.vapor(p);
      }
    }
    if (puppet.dead) {
      final pose = c.pose;
      if (pose.dissolve > 0.02 && pose.dissolve < 0.97) {
        _ashIn -= dt;
        while (_ashIn <= 0) {
          _ashIn += 0.018;
          final p = c.randomPoint(_rnd, minH: 0, maxH: 1, maxSide: 1.2);
          if (p != null) _fx.ash(p);
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Cámara y geometría en pantalla
  // ---------------------------------------------------------------------------

  double get _zoom => 1.012 + 0.006 * math.sin(time * 0.39) + _kick * 0.045 - (_fleeT > 0 ? 0.14 * _ease(_fleeT) : 0);
  double get _swayX => math.sin(time * 0.47) * 2.4;
  double get _swayY => math.sin(time * 0.83) * 1.6 + (_fleeT > 0 ? 40 * _ease(_fleeT) : 0) + (_downT > 0 ? 40 * _ease(_downT) : 0);

  /// Mundo → pantalla (sin el temblor, que es breve y de alta frecuencia).
  Offset toView(Offset p) {
    final z = _zoom;
    return Offset((p.dx - _pivot.dx) * z + _pivot.dx + _swayX, (p.dy - _pivot.dy) * z + _pivot.dy + _swayY);
  }

  /// Pantalla → mundo.
  Offset toWorld(Offset p) {
    final z = _zoom;
    return Offset((p.dx - _pivot.dx - _swayX) / z + _pivot.dx, (p.dy - _pivot.dy - _swayY) / z + _pivot.dy);
  }

  Rect rectToView(Rect r) => Rect.fromPoints(toView(r.topLeft), toView(r.bottomRight));

  /// Caja del cuerpo de la criatura en pantalla.
  Rect get bodyRect => _layout == null ? Rect.zero : rectToView(_layout!.body);

  /// Zona de la cabeza en pantalla (sigue la pose actual: agacharse, balanceo).
  Rect get headRect {
    if (_layout == null) return Rect.zero;
    if (puppet.dead) return Rect.zero;
    return rectToView(_creature.hasPose ? _creature.headWorld : _layout!.head);
  }

  /// Puntos de anclaje para números flotantes.
  Offset get headPoint {
    final h = headRect;
    return h.isEmpty ? bodyRect.topCenter : h.topCenter;
  }

  Offset get chestPoint {
    final b = bodyRect;
    return Offset(b.center.dx, b.top + b.height * 0.32);
  }

  /// Punto de impacto: el de la retícula, llevado dentro del cuerpo si quedó afuera.
  Offset impactPointFor(Offset aimed) {
    final b = bodyRect.deflate(6);
    if (b.isEmpty) return aimed;
    return Offset(aimed.dx.clamp(b.left, b.right), aimed.dy.clamp(b.top, b.bottom));
  }

  /// Marco de las esquinas de puntería (torso y cabeza).
  Rect get frameRect {
    final l = _layout;
    if (l == null) return Rect.zero;
    final b = l.body;
    final w = math.min(b.width * 0.86, l.view.width * 0.66);
    final top = math.min(l.head.top, b.top) - 16;
    return rectToView(Rect.fromLTRB(b.center.dx - w / 2, top, b.center.dx + w / 2, b.top + b.height * 0.66));
  }

  // ---------------------------------------------------------------------------
  // Puntería
  // ---------------------------------------------------------------------------

  void aimStart(Offset finger, {required bool canCharge, required AimStyle style}) {
    aimStyle = style;
    aim.start(finger, canCharge: canCharge);
  }

  void aimMove(Offset finger) => aim.move(finger);

  AimShot? aimRelease() => aim.active ? aim.release(bodyRect, headRect) : null;

  void aimCancel() => aim.cancel();

  // ---------------------------------------------------------------------------
  // Reacciones (las llama la pantalla al reproducir los eventos)
  // ---------------------------------------------------------------------------

  /// Reproduce una animación de la criatura; devuelve su duración en segundos.
  double playZombie(ZombieAnim a) {
    if (_art == null) return 0;
    final d = puppet.play(a);
    final l = _layout;
    if (l != null && a == ZombieAnim.chargePrepare) {
      _fx.dust(Offset(l.feet.dx, l.floorY), l.body.width);
      shake(0.18);
    }
    if (l != null && a == ZombieAnim.death && zombieType == ZombieTypeId.bloater) {
      _fx.toxic(Offset(l.body.center.dx, l.body.top + l.body.height * 0.45), big: true);
    }
    return d;
  }

  /// Segundos hasta el impacto/pico de una animación.
  double zombieKeyTime(ZombieAnim a) => PuppetAnimator.keyTimeOf(a);

  double zombieDuration(ZombieAnim a) => PuppetAnimator.durationOf(a);

  void shake(double amount) => _trauma = math.min(1, _trauma + amount);

  void punch(double k) => _kick = math.max(_kick, k);

  void impact(Offset at, {bool crit = false, bool heavy = false, bool ranged = false, bool headshot = false}) {
    final l = _layout;
    if (_art == null || l == null) return;
    _fx.impact(at, crit: crit, heavy: heavy, ranged: ranged);
    final local = l.toLocal(toWorld(at));
    puppet.hitAt(local.dx, local.dy, l.body.height / l.scale * 0.07, crit: crit, headshot: headshot, strength: heavy || crit ? 1.2 : 1);
    shake(crit ? 0.32 : (heavy ? 0.28 : 0.16));
  }

  void miss(Offset at, {bool ranged = false}) {
    if (_art == null) return;
    _fx.puff(at, ranged: ranged);
  }

  void muzzle(Offset target) {
    if (_art == null) return;
    _screen.muzzle(target);
    punch(0.35);
    shake(0.12);
  }

  void slash(Offset target, {bool heavy = false}) {
    if (_art == null) return;
    _fx.slash(target, heavy: heavy);
    punch(heavy ? 0.5 : 0.25);
  }

  /// El jugador recibe daño (en el momento del impacto de la embestida).
  void hurt({bool charged = false, bool toxic = false}) {
    if (_art == null) return;
    _screen.hurt(toxic: toxic, strong: charged);
    shake(charged ? 0.95 : 0.55);
    punch(charged ? 0.9 : 0.4);
  }

  /// El ataque falló o se cubrió: impacto suave contra la guardia.
  void blockedHit() {
    if (_art == null) return;
    shake(0.3);
    punch(0.3);
  }

  void dodge() => _screen.dodge();

  void shieldUp() {
    if (_art == null) return;
    _screen.shield();
  }

  void healPulse() {
    if (_art == null) return;
    _screen.heal();
    _fx.heal(Offset(size.x / 2, size.y * 0.86), size.x);
  }

  void toxicCloud() {
    if (_art == null) return;
    _fx.toxic(chestPoint, big: false);
    _screen.hurt(toxic: true, strong: false);
  }

  void screamWave() {
    if (_art == null) return;
    final h = headRect;
    final at = h.isEmpty ? headPoint : h.center.translate(0, h.height * 0.2);
    _fx.ring(at, Sutura.accent, 260, 0.9, width: 7);
    _fx.ring(at, const Color(0xFFE9E6DF), 200, 0.7, delay: 0.1, width: 2);
    _fx.ring(at, Sutura.accent, 150, 0.6, delay: 0.22, width: 4);
    _screen.distort(at);
    shake(0.5);
  }

  void fleeOut() => _fleeT = 0;

  void playerDown() {
    _downT = 0;
    shake(0.6);
  }

  double get fleeProgress => _fleeT < 0 ? 0 : _fleeT;
  double get downProgress => _downT < 0 ? 0 : _downT;

  static double _ease(double t) => Curves.easeInOut.transform(t.clamp(0.0, 1.0));
}

// -----------------------------------------------------------------------------
// Cámara
// -----------------------------------------------------------------------------

class _CameraRig extends Component with HasGameReference<CombatStageGame> {
  @override
  void renderTree(Canvas canvas) {
    final g = game;
    final t = g.time;
    final tr = g._trauma * g._trauma;
    final shx = tr * 16 * (math.sin(t * 61.3 + 0.7) * 0.7 + math.sin(t * 23.1) * 0.3);
    final shy = tr * 13 * (math.sin(t * 47.9 + 2.1) * 0.7 + math.sin(t * 17.3 + 1) * 0.3);
    final rot = tr * 0.02 * math.sin(t * 39.1) + (g._downT > 0 ? 0.09 * CombatStageGame._ease(g._downT) : 0);
    final z = g._zoom;
    final p = g._pivot;
    canvas.save();
    canvas.translate(p.dx + g._swayX + shx, p.dy + g._swayY + shy);
    if (rot != 0) canvas.rotate(rot);
    canvas.scale(z, z);
    canvas.translate(-p.dx, -p.dy);
    super.renderTree(canvas);
    canvas.restore();
  }
}

// -----------------------------------------------------------------------------
// Placa de fondo
// -----------------------------------------------------------------------------

class _Backdrop extends Component with HasGameReference<CombatStageGame> {
  _Backdrop(this.art)
    : _src = Rect.fromLTWH(0, 0, art.plate.width.toDouble(), art.plate.height.toDouble()),
      _skySrc = Rect.fromLTWH(0, 0, art.plate.width.toDouble(), 2),
      _groundSrc = Rect.fromLTWH(0, art.plate.height - 2.0, art.plate.width.toDouble(), 2),
      _leftSrc = Rect.fromLTWH(0, 0, 2, art.plate.height.toDouble()),
      _rightSrc = Rect.fromLTWH(art.plate.width - 2.0, 0, 2, art.plate.height.toDouble());

  final CombatArt art;
  final Rect _src, _skySrc, _groundSrc, _leftSrc, _rightSrc;
  // Un punto más oscura y fría que el arte original (clave baja, como la referencia).
  final Paint _paint = Paint()
    ..filterQuality = FilterQuality.medium
    ..colorFilter = const ColorFilter.mode(Color(0xFFBCC2C8), BlendMode.modulate);
  int _ver = -1;
  Rect _dst = Rect.zero, _sky = Rect.zero, _ground = Rect.zero, _left = Rect.zero, _right = Rect.zero;

  void _sync() {
    final l = game.layout;
    if (l == null) return;
    _ver = game._layoutVersion;
    _dst = l.plateRect;
    // Extensiones para que el temblor/zoom nunca muestre el vacío.
    _sky = Rect.fromLTRB(_dst.left, _dst.top - 300, _dst.right, _dst.top + 1);
    _ground = Rect.fromLTRB(_dst.left, _dst.bottom - 1, _dst.right, _dst.bottom + 300);
    _left = Rect.fromLTRB(_dst.left - 300, _dst.top - 300, _dst.left + 1, _dst.bottom + 300);
    _right = Rect.fromLTRB(_dst.right - 1, _dst.top - 300, _dst.right + 300, _dst.bottom + 300);
  }

  @override
  void render(Canvas canvas) {
    if (_ver != game._layoutVersion) _sync();
    if (_dst.isEmpty) return;
    final img = art.plate;
    canvas.drawImageRect(img, _leftSrc, _left, _paint);
    canvas.drawImageRect(img, _rightSrc, _right, _paint);
    canvas.drawImageRect(img, _skySrc, _sky, _paint);
    canvas.drawImageRect(img, _groundSrc, _ground, _paint);
    canvas.drawImageRect(img, _src, _dst, _paint);
  }
}

// -----------------------------------------------------------------------------
// Lluvia (dos profundidades) y salpicaduras en el piso
// -----------------------------------------------------------------------------

class _Rain extends Component with HasGameReference<CombatStageGame> {
  _Rain({required this.front, required this.count, required int seed})
    : _rnd = math.Random(seed),
      _x = Float32List(count),
      _y = Float32List(count),
      _v = Float32List(count),
      _len = Float32List(count),
      _pts = Float32List(count * 4),
      _sx = Float32List(_splashes),
      _sy = Float32List(_splashes),
      _sAge = Float32List(_splashes),
      _sPts = Float32List(_splashes * 8) {
    for (var i = 0; i < _splashes; i++) {
      _sAge[i] = 9;
    }
  }

  final bool front;
  final int count;
  final math.Random _rnd;
  final Float32List _x, _y, _v, _len, _pts;
  static const _splashes = 24;
  final Float32List _sx, _sy, _sAge, _sPts;
  int _sNext = 0;
  double _splashIn = 0;
  static const double _wind = 0.11;
  Size _view = Size.zero;

  late final Paint _paint = Paint()
    ..strokeWidth = front ? 1.35 : 0.9
    ..strokeCap = StrokeCap.round
    ..color = front ? const Color(0x33D6E2EC) : const Color(0x24B4C6D4);
  final Paint _splash = Paint()
    ..strokeWidth = 1
    ..color = const Color(0x40C8D6E0);

  void _seed(int i, {required bool initial}) {
    final w = _view.width, h = _view.height;
    _x[i] = -w * 0.15 + _rnd.nextDouble() * w * 1.3;
    _y[i] = initial ? _rnd.nextDouble() * h : -_rnd.nextDouble() * h * 0.25;
    _v[i] = front ? 1500 + _rnd.nextDouble() * 600 : 720 + _rnd.nextDouble() * 280;
    _len[i] = front ? 26 + _rnd.nextDouble() * 26 : 9 + _rnd.nextDouble() * 12;
  }

  @override
  void update(double dt) {
    final l = game.layout;
    if (l == null) return;
    if (_view != l.view) {
      _view = l.view;
      for (var i = 0; i < count; i++) {
        _seed(i, initial: true);
      }
    }
    final h = _view.height;
    for (var i = 0; i < count; i++) {
      _y[i] += _v[i] * dt;
      _x[i] += _v[i] * _wind * dt;
      if (_y[i] - _len[i] > h + 20) _seed(i, initial: false);
    }
    if (front) {
      _splashIn -= dt;
      while (_splashIn <= 0) {
        _splashIn += 0.035;
        final i = _sNext;
        _sNext = (_sNext + 1) % _splashes;
        _sAge[i] = 0;
        _sx[i] = _rnd.nextDouble() * _view.width;
        final g = math.pow(_rnd.nextDouble(), 0.7).toDouble();
        _sy[i] = l.plateRect.top + l.plateRect.height * (0.48 + 0.52 * g);
      }
      for (var i = 0; i < _splashes; i++) {
        if (_sAge[i] < 1) _sAge[i] += dt;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (_view.isEmpty) return;
    for (var i = 0; i < count; i++) {
      final o = i * 4;
      final len = _len[i];
      _pts[o] = _x[i];
      _pts[o + 1] = _y[i];
      _pts[o + 2] = _x[i] - len * _wind;
      _pts[o + 3] = _y[i] - len;
    }
    canvas.drawRawPoints(ui.PointMode.lines, _pts, _paint);
    if (!front) return;
    // Salpicaduras: dos rayitas que se abren y se apagan (las apagadas quedan
    // como segmentos nulos fuera de pantalla: un solo dibujo, sin copias).
    var n = 0;
    for (var i = 0; i < _splashes; i++) {
      final a = _sAge[i];
      if (a >= 0.16) {
        final o = i * 8;
        for (var k = 0; k < 8; k++) {
          _sPts[o + k] = -50;
        }
        continue;
      }
      final p = a / 0.16;
      final depth = ((_sy[i] - _view.height * 0.45) / (_view.height * 0.55)).clamp(0.2, 1.0);
      final r = (2 + 7 * p) * depth;
      final up = 3 * depth * (1 - p);
      final o = i * 8;
      _sPts[o] = _sx[i] - r;
      _sPts[o + 1] = _sy[i] - up;
      _sPts[o + 2] = _sx[i] - r * 0.4;
      _sPts[o + 3] = _sy[i];
      _sPts[o + 4] = _sx[i] + r * 0.4;
      _sPts[o + 5] = _sy[i];
      _sPts[o + 6] = _sx[i] + r;
      _sPts[o + 7] = _sy[i] - up;
      n++;
    }
    if (n > 0) canvas.drawRawPoints(ui.PointMode.lines, _sPts, _splash);
  }
}

// -----------------------------------------------------------------------------
// Niebla baja (bancos que derivan + banda de suelo)
// -----------------------------------------------------------------------------

class _Fog extends Component with HasGameReference<CombatStageGame> {
  _Fog({required this.front, required this.atlas}) : _pool = FxPool(front ? 8 : 6), _rnd = math.Random(front ? 4 : 8);

  final bool front;
  final ui.Image atlas;
  final FxPool _pool;
  final math.Random _rnd;
  final Paint _band = Paint();
  bool _seeded = false;
  double _spawnIn = 0;
  int _ver = -1;
  Rect _bandRect = Rect.zero;

  void _sync() {
    final l = game.layout;
    if (l == null) return;
    _ver = game._layoutVersion;
    final v = l.view;
    if (front) {
      // Neblina pegada al piso: tapa los pies y se aclara hacia abajo.
      final top = l.floorY - l.body.height * 0.16;
      _bandRect = Rect.fromLTRB(-200, top, v.width + 200, v.height + 200);
      _band.shader = ui.Gradient.linear(
        Offset(0, top),
        Offset(0, v.height + 40),
        const [Color(0x00202A31), Color(0x4A26313A), Color(0x3A1A2228), Color(0x22101519)],
        const [0, 0.42, 0.7, 1],
      );
    } else {
      final y = l.plateRect.top + l.plateRect.height * 0.42;
      _bandRect = Rect.fromLTRB(-200, y - v.height * 0.16, v.width + 200, y + v.height * 0.12);
      _band.shader = ui.Gradient.linear(
        _bandRect.topCenter,
        _bandRect.bottomCenter,
        const [Color(0x00334049), Color(0x30334049), Color(0x00334049)],
        const [0, 0.55, 1],
      );
    }
  }

  void _spawn({required bool initial}) {
    final l = game.layout;
    if (l == null) return;
    final v = l.view;
    final size = v.width * (0.6 + _rnd.nextDouble() * 0.6);
    final y = front ? l.floorY + v.height * (-0.06 + _rnd.nextDouble() * 0.16) : v.height * (0.34 + _rnd.nextDouble() * 0.26);
    final dir = _rnd.nextBool() ? 1.0 : -1.0;
    final x = initial ? _rnd.nextDouble() * v.width : (dir > 0 ? -size * 0.4 : v.width + size * 0.4);
    _pool.spawn(
      x: x,
      y: y,
      vx: dir * (6 + _rnd.nextDouble() * 10),
      vy: -0.5 - _rnd.nextDouble(),
      life: 18 + _rnd.nextDouble() * 10,
      size: size,
      src: FxAtlas.blob,
      color: front ? Color.fromARGB(40 + _rnd.nextInt(18), 146, 164, 176) : Color.fromARGB(24 + _rnd.nextInt(12), 136, 152, 164),
      grow: 0.01,
      rot: _rnd.nextDouble() * math.pi,
      spin: (_rnd.nextDouble() - 0.5) * 0.03,
      fadeIn: 0.25,
    );
  }

  @override
  void update(double dt) {
    if (game.layout == null) return;
    if (!_seeded) {
      _seeded = true;
      for (var i = 0; i < _pool.capacity; i++) {
        _spawn(initial: true);
      }
    }
    _spawnIn -= dt;
    if (_spawnIn <= 0) {
      _spawnIn = front ? 2.6 : 3.4;
      _spawn(initial: false);
    }
    _pool.update(dt);
  }

  @override
  void render(Canvas canvas) {
    if (_ver != game._layoutVersion) _sync();
    if (_bandRect.isEmpty) return;
    canvas.drawRect(_bandRect, _band);
    _pool.render(canvas, atlas);
  }
}

// -----------------------------------------------------------------------------
// Criatura: títere de malla con reflejo, sombra, fantasmas, luz y destellos
// -----------------------------------------------------------------------------

class _CreatureLayer extends Component with HasGameReference<CombatStageGame> {
  _CreatureLayer(this.art, this.anim, PuppetStyle style)
    : mesh = PuppetMesh.grid(art.rig),
      deformer = PuppetDeformer(art.rig, armInner: style.armInner) {
    final n = mesh.vertexCount;
    _pos = Float32List(n * 2);
    _ghost = Float32List(n * 2);
    _refl = Float32List(n * 2);
    _cMain = Int32List(n);
    _cAux = Int32List(n);
    _shader = ImageShader(art.cutout, TileMode.clamp, TileMode.clamp, _identity, filterQuality: FilterQuality.medium);
    _main = Paint()..shader = _shader;
    _rim = Paint()
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
  final PuppetAnimator anim;
  final PuppetMesh mesh;
  final PuppetDeformer deformer;
  final PuppetPose pose = PuppetPose();
  final PuppetPose _ghostPose = PuppetPose();

  late final Float32List _pos, _ghost, _refl;
  late final Int32List _cMain, _cAux;
  late final ImageShader _shader;
  late final Paint _main, _rim, _white, _red, _glow;
  final Paint _blurLayer = Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 2.2, sigmaY: 4.5);
  final Paint _glowLayer = Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14);
  final Paint _shadow = Paint()
    ..shader = ui.Gradient.radial(Offset.zero, 1, const [Color(0xC8000000), Color(0x66000000), Color(0x00000000)], const [0, 0.5, 1]);

  bool hasPose = false;
  double _ox = 0, _oy = 0, _scale = 1;

  void disposeShader() => _shader.dispose();

  @override
  void update(double dt) {
    final l = game.layout;
    if (l == null) return;
    _ox = l.feet.dx;
    _oy = l.feet.dy;
    _scale = l.scale;
    anim.evaluate(pose);
    deformer.deformMesh(pose, mesh, _pos, _ox, _oy, _scale);
    // Caja actual (para el desenfoque y los emisores).
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
    hasPose = true;
  }

  double _bx0 = 0, _by0 = 0, _bx1 = 0, _by1 = 0;
  double _hx0 = 0, _hy0 = 0, _hx1 = 0, _hy1 = 0;

  void _headCorner(double x, double y) {
    deformer.apply(pose, x, y);
    final sx = _ox + deformer.outX * _scale, sy = _oy + deformer.outY * _scale;
    if (sx < _hx0) _hx0 = sx;
    if (sx > _hx1) _hx1 = sx;
    if (sy < _hy0) _hy0 = sy;
    if (sy > _hy1) _hy1 = sy;
  }

  /// Caja de la cabeza en la pose actual (mundo).
  Rect get headWorld => Rect.fromLTRB(_hx0, _hy0, _hx1, _hy1);

  /// Punto (mundo) de un vértice al azar dentro de la franja pedida y aún visible.
  Offset? randomPoint(math.Random rnd, {required double minH, required double maxH, required double maxSide}) {
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

  ui.Vertices _vertices(Float32List pos, Int32List colors) =>
      ui.Vertices.raw(ui.VertexMode.triangles, pos, textureCoordinates: mesh.uv, colors: colors, indices: mesh.indices);

  void _draw(Canvas canvas, Float32List pos, Int32List colors, Paint paint) {
    final v = _vertices(pos, colors);
    canvas.drawVertices(v, BlendMode.modulate, paint);
    v.dispose();
  }

  @override
  void render(Canvas canvas) {
    if (!hasPose) return;
    final g = game;
    final l = g.layout!;
    final n = mesh.vertexCount;
    final env = PuppetAnimator.lungeEnvelope(anim.anim, anim.t);
    final fall = anim.dead ? smooth(0.2, 0.9, anim.t) : 0.0;
    final floor = l.floorY;
    final bodyH = l.body.height;
    final hidden = floor > g.hudTop + 6;

    // 1. Sombra de contacto.
    final shadowA = (1 - env * 0.7) * (1 - fall);
    if (shadowA > 0.02 && !hidden) {
      canvas.save();
      canvas.translate(_ox + pose.tx * bodyH * 0.2, floor + 2);
      canvas.scale(l.body.width * 0.48 * (1 + 0.25 * pose.crouch), bodyH * 0.035);
      _shadow.color = Color.fromARGB((shadowA * 255).round(), 255, 255, 255);
      canvas.drawCircle(Offset.zero, 1, _shadow);
      canvas.restore();
    }

    // Colores base por vértice: gradación fría, piernas en sombra, disolución.
    final dark = 1 - pose.dark;
    for (var i = 0; i < n; i++) {
      final hc = mesh.h[i].clamp(0.0, 1.0);
      final k = smooth(0.0, 0.5, hc);
      final r = (0.48 + 0.31 * k) * dark;
      final gg = (0.52 + 0.3 * k) * dark;
      final b = (0.6 + 0.28 * k) * dark;
      _cMain[i] = _argb(_vertexAlpha(i), r, gg, b);
    }

    // 2. Reflejo en el asfalto mojado (invertido, comprimido, ondulado, borroso).
    final reflA = 0.34 * (1 - env) * (1 - fall) * pose.alpha;
    if (reflA > 0.02 && !hidden) {
      var minX = double.infinity, maxX = -double.infinity, maxY = floor;
      final t = g.time;
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
        _cAux[i] = _argb(a, 0.52, 0.6, 0.72);
      }
      canvas.saveLayer(Rect.fromLTRB(minX - 20, floor - 6, maxX + 20, maxY + 20), _blurLayer);
      _draw(canvas, _refl, _cAux, _main);
      canvas.restore();
    }

    // 3. Resplandor rojo al preparar la embestida (silueta difusa detrás).
    final glow = g.charging && !anim.dead ? 0.5 + 0.5 * math.sin(g.time * 9) : 0.0;
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

    // 5. Fantasmas del desenfoque de movimiento (embestida): poses anteriores
    //    encima del cuerpo, como una exposición larga (zoom hacia la cámara).
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

    // 6. Luz de emergencia roja desde la derecha (aditiva, late con la baliza).
    final beacon = _ScreenLayer.beacon(g.time, g.charging);
    final rimK = (0.22 + 0.55 * beacon) * dark * pose.alpha;
    if (rimK > 0.02) {
      for (var i = 0; i < n; i++) {
        final hc = mesh.h[i].clamp(0.0, 1.0);
        final k = rimK * smooth(-0.15, 1.0, mesh.side[i]) * (0.35 + 0.65 * hc) * (_vertexAlpha(i) > 0.5 ? 1 : 0);
        _cAux[i] = _argb(1, k, k * 0.2, k * 0.14);
      }
      _draw(canvas, _pos, _cAux, _rim);
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

// -----------------------------------------------------------------------------
// Efectos de mundo: esquirlas, polvo, vapor, nube tóxica, ceniza, tajos, ondas
// -----------------------------------------------------------------------------

class _FxLayer extends Component with HasGameReference<CombatStageGame> {
  _FxLayer(this.atlas);

  final ui.Image atlas;
  final FxPool _dark = FxPool(110);
  final FxPool _bright = FxPool(90, blend: BlendMode.plus);
  final math.Random _rnd = math.Random();

  // Tajo cuerpo a cuerpo.
  Path? _slash;
  Offset _slashDir = Offset.zero;
  double _slashT = 1;
  bool _slashHeavy = false;
  final Paint _slashCore = Paint()..blendMode = BlendMode.plus;
  final Paint _slashGlow = Paint()
    ..blendMode = BlendMode.plus
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

  // Ondas (grito, crítico, tóxico).
  static const _rings = 8;
  final Float32List _rx = Float32List(_rings);
  final Float32List _ry = Float32List(_rings);
  final Float32List _rAge = Float32List(_rings);
  final Float32List _rLife = Float32List(_rings);
  final Float32List _rMax = Float32List(_rings);
  final Float32List _rW = Float32List(_rings);
  final List<Color> _rCol = List.filled(_rings, Sutura.accent);
  int _rNext = 0;
  final Paint _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
  final Paint _stunPaint = Paint()..color = Sutura.signal;
  final Paint _stunGlow = Paint()
    ..color = const Color(0x668DB4C9)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

  double _r(double a, double b) => a + _rnd.nextDouble() * (b - a);

  void impact(Offset at, {required bool crit, required bool heavy, required bool ranged}) {
    final n = crit ? 26 : (heavy ? 20 : 14);
    // Rocío oscuro (esquirlas y ceniza; sin sangre).
    for (var i = 0; i < n; i++) {
      final a = _r(-math.pi, math.pi);
      final sp = _r(140, crit ? 560 : 400);
      _dark.spawn(
        x: at.dx,
        y: at.dy,
        vx: math.cos(a) * sp,
        vy: math.sin(a) * sp - 90,
        life: _r(0.35, 0.8),
        size: _r(3.5, 8.5),
        src: FxAtlas.shard,
        color: Color.fromARGB(235, 16 + _rnd.nextInt(16), 14 + _rnd.nextInt(10), 16 + _rnd.nextInt(10)),
        rot: _r(0, 6),
        spin: _r(-14, 14),
        drag: 2.2,
        gravity: 950,
      );
    }
    for (var i = 0; i < 5; i++) {
      _dark.spawn(
        x: at.dx + _r(-8, 8),
        y: at.dy + _r(-8, 8),
        vx: _r(-50, 50),
        vy: _r(-60, -10),
        life: _r(0.6, 1.1),
        size: _r(40, 74),
        src: FxAtlas.blob,
        color: const Color(0x9C0A0C0E),
        grow: 1.2,
        drag: 2,
      );
    }
    // Chispas: frías en golpes, ámbar en críticos.
    final sparks = crit ? 16 : 9;
    for (var i = 0; i < sparks; i++) {
      final a = _r(-math.pi, math.pi);
      final sp = _r(260, 720);
      _bright.spawn(
        x: at.dx,
        y: at.dy,
        vx: math.cos(a) * sp,
        vy: math.sin(a) * sp,
        life: _r(0.12, 0.3),
        size: _r(14, 26),
        src: FxAtlas.streak,
        color: crit ? const Color(0xFFFFC768) : (ranged ? const Color(0xFFF2EEE6) : const Color(0xFFBFD6E4)),
        drag: 5,
        gravity: 300,
        alignToVelocity: true,
      );
    }
    _bright.spawn(
      x: at.dx,
      y: at.dy,
      life: 0.16,
      size: crit ? 130 : 84,
      src: FxAtlas.dot,
      color: crit ? const Color(0xC0FFC768) : const Color(0x90E8F0F4),
      grow: 2,
    );
    if (crit) ring(at, Sutura.amber, 96, 0.35, width: 4);
  }

  /// Golpe al aire: polvo y, con disparos, rebote de chispas.
  void puff(Offset at, {required bool ranged}) {
    for (var i = 0; i < 6; i++) {
      _dark.spawn(
        x: at.dx + _r(-10, 10),
        y: at.dy + _r(-6, 6),
        vx: _r(-60, 60),
        vy: _r(-60, -10),
        life: _r(0.5, 0.9),
        size: _r(26, 46),
        src: FxAtlas.blob,
        color: const Color(0x5C707C80),
        grow: 1.4,
        drag: 2.5,
      );
    }
    if (ranged) {
      for (var i = 0; i < 5; i++) {
        final a = _r(-math.pi, 0);
        _bright.spawn(
          x: at.dx,
          y: at.dy,
          vx: math.cos(a) * 300,
          vy: math.sin(a) * 300,
          life: 0.14,
          size: 14,
          src: FxAtlas.streak,
          color: const Color(0xFFFFE2A8),
          drag: 6,
          alignToVelocity: true,
        );
      }
    }
  }

  /// Polvo del piso (el Bruto se agacha para embestir).
  void dust(Offset at, double width) {
    for (var i = 0; i < 16; i++) {
      final dir = i.isEven ? 1.0 : -1.0;
      _dark.spawn(
        x: at.dx + _r(-width * 0.3, width * 0.3),
        y: at.dy + _r(-10, 6),
        vx: dir * _r(60, 220),
        vy: _r(-50, -8),
        life: _r(0.9, 1.6),
        size: _r(50, 110),
        src: FxAtlas.blob,
        color: const Color(0x52574E46),
        grow: 0.9,
        drag: 1.8,
        fadeIn: 0.08,
      );
    }
  }

  /// Vapor tóxico que sube de las ampollas (en reposo).
  void vapor(Offset at) {
    _bright.spawn(
      x: at.dx,
      y: at.dy,
      vx: _r(-10, 10),
      vy: _r(-34, -16),
      life: _r(1.6, 2.6),
      size: _r(32, 70),
      src: FxAtlas.blob,
      color: Color.fromARGB(40 + _rnd.nextInt(24), 120, 210, 70),
      grow: 0.7,
      drag: 0.4,
      fadeIn: 0.3,
    );
    if (_rnd.nextDouble() < 0.35) {
      _bright.spawn(
        x: at.dx + _r(-6, 6),
        y: at.dy,
        vx: _r(-8, 8),
        vy: _r(-50, -24),
        life: _r(0.8, 1.4),
        size: _r(3, 6),
        src: FxAtlas.dot,
        color: const Color(0xB0B8F070),
        drag: 0.3,
        fadeIn: 0.2,
      );
    }
  }

  /// Nube tóxica (explosión del Hinchado).
  void toxic(Offset at, {required bool big}) {
    final n = big ? 26 : 14;
    for (var i = 0; i < n; i++) {
      final a = _r(-math.pi, math.pi);
      final sp = _r(60, big ? 380 : 260);
      _bright.spawn(
        x: at.dx,
        y: at.dy,
        vx: math.cos(a) * sp,
        vy: math.sin(a) * sp * 0.6 - 30,
        life: _r(1.3, 2.3),
        size: _r(90, big ? 200 : 150),
        src: FxAtlas.blob,
        color: Color.fromARGB(44 + _rnd.nextInt(26), 110, 200, 60),
        grow: 1.1,
        drag: 1.5,
        fadeIn: 0.08,
      );
    }
    for (var i = 0; i < (big ? 10 : 5); i++) {
      _dark.spawn(
        x: at.dx + _r(-30, 30),
        y: at.dy + _r(-30, 30),
        vx: _r(-80, 80),
        vy: _r(-60, 20),
        life: _r(1.2, 2.0),
        size: _r(80, 150),
        src: FxAtlas.blob,
        color: const Color(0x66283A18),
        grow: 1.0,
        drag: 1.4,
      );
    }
    ring(at, _toxic, big ? 300 : 240, 0.7, width: 6);
  }

  /// Ceniza oscura de la disolución al morir.
  void ash(Offset at) {
    _dark.spawn(
      x: at.dx,
      y: at.dy,
      vx: _r(-30, 30),
      vy: _r(-90, -30),
      life: _r(0.7, 1.4),
      size: _r(3, 7),
      src: FxAtlas.shard,
      color: Color.fromARGB(220, 12 + _rnd.nextInt(10), 12 + _rnd.nextInt(8), 14 + _rnd.nextInt(8)),
      rot: _r(0, 6),
      spin: _r(-6, 6),
      drag: 1.2,
      gravity: -20,
    );
    if (_rnd.nextDouble() < 0.3) {
      _dark.spawn(
        x: at.dx,
        y: at.dy,
        vx: _r(-20, 20),
        vy: _r(-40, -10),
        life: _r(0.8, 1.3),
        size: _r(30, 60),
        src: FxAtlas.blob,
        color: const Color(0x55080A0C),
        grow: 0.8,
        drag: 1.5,
      );
    }
  }

  void heal(Offset at, double width) {
    for (var i = 0; i < 18; i++) {
      _bright.spawn(
        x: at.dx + _r(-width * 0.45, width * 0.45),
        y: at.dy + _r(-30, 40),
        vx: _r(-10, 10),
        vy: _r(-160, -70),
        life: _r(0.7, 1.2),
        size: _r(6, 12),
        src: FxAtlas.dot,
        color: const Color(0xB07DCB76),
        drag: 0.8,
      );
    }
  }

  /// Tajo en forma de media luna que cruza el objetivo (derecha → izquierda).
  void slash(Offset target, {required bool heavy}) {
    final s = heavy ? 1.3 : 1.0;
    final a = target.translate(118 * s, 64 * s);
    final b = target.translate(-112 * s, -46 * s);
    final d = b - a;
    final n = Offset(d.dy, -d.dx) / d.distance;
    final mid = Offset.lerp(a, b, 0.5)!;
    final outer = mid + n * (58 * s);
    final inner = mid + n * (30 * s);
    _slash = Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo(outer.dx, outer.dy, b.dx, b.dy)
      ..quadraticBezierTo(inner.dx, inner.dy, a.dx, a.dy)
      ..close();
    _slashDir = d / d.distance;
    _slashT = 0;
    _slashHeavy = heavy;
  }

  void ring(Offset at, Color color, double maxR, double life, {double delay = 0, double width = 5}) {
    final i = _rNext;
    _rNext = (_rNext + 1) % _rings;
    _rx[i] = at.dx;
    _ry[i] = at.dy;
    _rAge[i] = -delay;
    _rLife[i] = life;
    _rMax[i] = maxR;
    _rW[i] = width;
    _rCol[i] = color;
  }

  @override
  void update(double dt) {
    _dark.update(dt);
    _bright.update(dt);
    if (_slashT < 1) _slashT = math.min(1, _slashT + dt / 0.22);
    for (var i = 0; i < _rings; i++) {
      if (_rAge[i] < _rLife[i]) _rAge[i] += dt;
    }
  }

  @override
  void render(Canvas canvas) {
    _dark.render(canvas, atlas);
    final slash = _slash;
    if (slash != null && _slashT < 1) {
      final a = 1 - Curves.easeIn.transform(_slashT);
      final col = _slashHeavy ? Sutura.amber : const Color(0xFFE6EEF2);
      _slashGlow.color = col.withValues(alpha: 0.55 * a);
      _slashCore.color = col.withValues(alpha: 0.9 * a);
      canvas.save();
      canvas.translate(_slashDir.dx * 26 * _slashT, _slashDir.dy * 26 * _slashT);
      canvas.drawPath(slash, _slashGlow);
      canvas.drawPath(slash, _slashCore);
      canvas.restore();
    }
    for (var i = 0; i < _rings; i++) {
      final age = _rAge[i];
      if (age < 0 || age >= _rLife[i]) continue;
      final p = age / _rLife[i];
      final r = 26 + (_rMax[i] - 26) * Curves.easeOut.transform(p);
      _ringPaint
        ..strokeWidth = _rW[i] * (1 - p) + 1
        ..color = _rCol[i].withValues(alpha: 0.8 * (1 - p));
      canvas.drawCircle(Offset(_rx[i], _ry[i]), r, _ringPaint);
    }
    final g = game;
    if (g.stunned && !g.puppet.dead) {
      final h = g._creature.hasPose ? g._creature.headWorld : Rect.zero;
      final c = h.isEmpty ? Offset.zero : h.topCenter.translate(0, -10);
      if (c != Offset.zero) {
        for (var i = 0; i < 3; i++) {
          final a = g.time * 3.2 + i * math.pi * 2 / 3;
          final p = Offset(c.dx + math.cos(a) * 30, c.dy + math.sin(a) * 9);
          canvas.drawCircle(p, 6, _stunGlow);
          canvas.drawCircle(p, 2.6, _stunPaint);
        }
      }
    }
    _bright.render(canvas, atlas);
  }
}

// -----------------------------------------------------------------------------
// Capa de pantalla: luz de emergencia, viñeta fría, grano, golpes, fundidos
// -----------------------------------------------------------------------------

class _ScreenLayer extends Component with HasGameReference<CombatStageGame> {
  _ScreenLayer(this.art) {
    _grain.shader = ImageShader(art.grain, TileMode.repeated, TileMode.repeated, _identity);
  }

  final CombatArt art;
  Size _size = Size.zero;
  Rect _full = Rect.zero;
  int _ver = -1;
  final Paint _emergency = Paint()..blendMode = BlendMode.plus;
  final Paint _vignette = Paint();
  final Paint _edge = Paint();
  final Paint _flat = Paint();
  final Paint _grain = Paint();
  final Paint _muzzle = Paint()..blendMode = BlendMode.plus;
  final Paint _tracer = Paint()
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;
  final Paint _distort = Paint()
    ..style = PaintingStyle.stroke
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
  final Paint _distortHi = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
  final Paint _hex = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  Path? _hexes;

  double _hurt = 0;
  double _hitFlash = 0;
  bool _hurtToxic = false;
  double _muzzleT = 1;
  Offset _muzzleFrom = Offset.zero;
  Offset _muzzleTo = Offset.zero;
  double _shieldT = 1;
  double _healT = 1;
  double _dodgeT = 1;
  double _distortT = 1;
  Offset _distortAt = Offset.zero;
  double _grainT = 0;
  double _gx = 0, _gy = 0;
  final math.Random _rnd = math.Random(17);

  /// Baliza de emergencia (0…1): destellos cortos; más rápida si el Bruto carga.
  static double beacon(double t, bool charging) {
    final period = charging ? 0.55 : 1.7;
    final phase = (t / period) % 1.0;
    return math.pow(math.max(0.0, math.sin(phase * math.pi * 2)), 6).toDouble();
  }

  void _sync() {
    final l = game.layout;
    if (l == null) return;
    _ver = game._layoutVersion;
    final s = l.view;
    _size = s;
    _full = Offset.zero & s;
    final w = s.width;
    final h = s.height;
    _emergency.shader = ui.Gradient.radial(
      Offset(w * 1.12, h * 0.46),
      w * 1.05,
      const [Color(0xFFE0302A), Color(0x55E0302A), Color(0x00000000)],
      const [0, 0.38, 1],
    );
    // Viñeta fría.
    _vignette.shader = ui.Gradient.radial(
      Offset(w / 2, h * 0.46),
      math.max(w, h) * 0.72,
      const [Color(0x00000000), Color(0x10000000), Color(0xA0060B12), Color(0xF2030509)],
      const [0, 0.4, 0.76, 1],
    );
    _edge.shader = ui.Gradient.radial(
      Offset(w / 2, h / 2),
      math.max(w, h) * 0.62,
      const [Color(0x00FFFFFF), Color(0x00FFFFFF), Color(0xFFFFFFFF)],
      const [0, 0.55, 1],
    );
    // Hexágonos del escudo (abajo, en arco).
    final hx = Path();
    const r = 26.0;
    for (var row = 0; row < 3; row++) {
      for (var col = -1; col < (w / (r * 1.75)).ceil() + 1; col++) {
        final cx = col * r * 1.75 + (row.isOdd ? r * 0.87 : 0);
        final cy = h * 0.70 + row * r * 1.5;
        for (var k = 0; k < 6; k++) {
          final a = -math.pi / 2 + k * math.pi / 3;
          final px = cx + r * math.cos(a);
          final py = cy + r * math.sin(a);
          if (k == 0) {
            hx.moveTo(px, py);
          } else {
            hx.lineTo(px, py);
          }
        }
        hx.close();
      }
    }
    _hexes = hx;
  }

  void hurt({required bool toxic, required bool strong}) {
    _hurt = strong ? 1.3 : 1;
    _hitFlash = strong ? 1 : 0.7;
    _hurtToxic = toxic;
  }

  void muzzle(Offset target) {
    _muzzleT = 0;
    _muzzleFrom = Offset(_size.width * 0.74, _size.height * 0.80);
    _muzzleTo = target;
  }

  void shield() => _shieldT = 0;
  void heal() => _healT = 0;
  void dodge() => _dodgeT = 0;

  void distort(Offset at) {
    _distortT = 0;
    _distortAt = at;
  }

  @override
  void update(double dt) {
    _hurt = math.max(0, _hurt - dt / 0.6);
    _hitFlash = math.max(0, _hitFlash - dt / 0.18);
    if (_muzzleT < 1) _muzzleT = math.min(1, _muzzleT + dt / 0.14);
    if (_shieldT < 1) _shieldT = math.min(1, _shieldT + dt / 0.75);
    if (_healT < 1) _healT = math.min(1, _healT + dt / 0.9);
    if (_dodgeT < 1) _dodgeT = math.min(1, _dodgeT + dt / 0.5);
    if (_distortT < 1) _distortT = math.min(1, _distortT + dt / 0.75);
    _grainT += dt;
    if (_grainT > 1 / 24) {
      _grainT = 0;
      _gx = _rnd.nextDouble() * 96;
      _gy = _rnd.nextDouble() * 96;
    }
  }

  @override
  void render(Canvas canvas) {
    if (_ver != game._layoutVersion) _sync();
    if (_size.isEmpty) return;
    final g = game;
    final t = g.time;

    // Luz de emergencia desde la derecha.
    final b = beacon(t, g.charging);
    final em = ((g.charging ? 0.07 : 0.04) + b * (g.charging ? 0.2 : 0.12)).clamp(0.0, 1.0);
    _emergency.color = Color.fromARGB((em * 255).round(), 255, 255, 255);
    canvas.drawRect(_full, _emergency);

    // Onda del grito: anillo de "refracción" (oscuro difuso + filo brillante).
    if (_distortT < 1) {
      final p = Curves.easeOut.transform(_distortT);
      final r = 30 + p * _size.height * 0.75;
      final a = 1 - _distortT;
      _distort
        ..strokeWidth = 34 * a + 6
        ..color = Color.fromARGB((a * 110).round(), 0, 0, 0);
      canvas.drawCircle(_distortAt, r, _distort);
      _distortHi
        ..strokeWidth = 2.5 * a + 0.5
        ..color = Color.fromARGB((a * 150).round(), 255, 210, 200);
      canvas.drawCircle(_distortAt, r - 10, _distortHi);
    }

    // Viñeta fría y grano.
    canvas.drawRect(_full, _vignette);
    canvas.save();
    canvas.translate(-_gx, -_gy);
    _grain.color = const Color(0x22FFFFFF);
    canvas.drawRect(_full.translate(_gx, _gy).inflate(2), _grain);
    canvas.restore();

    // Salud baja: viñeta roja que late.
    if (g.healthRatio < 0.3 && g.downProgress <= 0) {
      final beat = 0.5 + 0.5 * math.sin(t * math.pi * 2 * 1.15);
      final k = (0.3 - g.healthRatio) / 0.3;
      _edge.colorFilter = const ColorFilter.mode(Color(0xFFB0121C), BlendMode.modulate);
      _edge.color = Color.fromARGB(((0.35 + 0.35 * k) * (0.55 + 0.45 * beat) * 255).round().clamp(0, 255), 255, 255, 255);
      canvas.drawRect(_full, _edge);
    }
    // Golpe recibido: destello rojo pleno + borde.
    if (_hitFlash > 0) {
      _flat.color = _hurtToxic
          ? Color.fromARGB((_hitFlash * 70).round(), 90, 170, 40)
          : Color.fromARGB((_hitFlash * 66).round(), 200, 24, 20);
      canvas.drawRect(_full, _flat);
    }
    if (_hurt > 0) {
      _edge.colorFilter = ColorFilter.mode(_hurtToxic ? const Color(0xFF5E9A2A) : const Color(0xFFE0202C), BlendMode.modulate);
      _edge.color = Color.fromARGB((math.min(1.0, _hurt) * 230).round(), 255, 255, 255);
      canvas.drawRect(_full, _edge);
    }
    if (_healT < 1) {
      _edge.colorFilter = const ColorFilter.mode(Color(0xFF7DCB76), BlendMode.modulate);
      _edge.color = Color.fromARGB(((1 - _healT) * 150).round(), 255, 255, 255);
      canvas.drawRect(_full, _edge);
    }
    // Esquiva perfecta (embestida): destello acero.
    if (_dodgeT < 1) {
      _edge.colorFilter = const ColorFilter.mode(Sutura.signal, BlendMode.modulate);
      _edge.color = Color.fromARGB(((1 - _dodgeT) * 170).round(), 255, 255, 255);
      canvas.drawRect(_full, _edge);
    }
    final hexes = _hexes;
    if (_shieldT < 1 && hexes != null) {
      final a = math.sin(_shieldT * math.pi);
      _hex.color = Sutura.signal.withValues(alpha: 0.5 * a);
      canvas.save();
      canvas.translate(0, 24 * (1 - a));
      canvas.drawPath(hexes, _hex);
      canvas.restore();
    }

    // Fogonazo del arma.
    if (_muzzleT < 1) {
      final a = 1 - _muzzleT;
      _flat.color = Color.fromARGB((a * 40).round(), 255, 226, 170);
      canvas.drawRect(_full, _flat);
      _tracer
        ..strokeWidth = 3 * a + 0.5
        ..color = Color.fromARGB((a * 200).round(), 255, 232, 190);
      canvas.drawLine(_muzzleFrom, Offset.lerp(_muzzleFrom, _muzzleTo, math.min(1, _muzzleT * 3 + 0.3))!, _tracer);
      _muzzle.color = Color.fromARGB((a * 255).round(), 255, 255, 255);
      _muzzle.colorFilter = const ColorFilter.mode(Color(0xFFFFD9A0), BlendMode.modulate);
      final r = 90 + 60 * _muzzleT;
      canvas.drawImageRect(art.fxAtlas, FxAtlas.blob, Rect.fromCircle(center: _muzzleFrom, radius: r), _muzzle);
      canvas.drawImageRect(art.fxAtlas, FxAtlas.dot, Rect.fromCircle(center: _muzzleFrom, radius: r * 0.35), _muzzle);
    }

    // Huida y caída: fundido.
    final flee = g.fleeProgress;
    if (flee > 0) {
      _flat.color = Color.fromARGB((Curves.easeIn.transform(flee) * 235).round(), 3, 5, 7);
      canvas.drawRect(_full, _flat);
    }
    final down = g.downProgress;
    if (down > 0) {
      _flat.color = Color.fromARGB((Curves.easeIn.transform(down) * 215).round(), 40, 2, 6);
      canvas.drawRect(_full, _flat);
    }
  }
}

// -----------------------------------------------------------------------------
// Marco de puntería y retícula
// -----------------------------------------------------------------------------

class _ReticleLayer extends Component with HasGameReference<CombatStageGame> {
  final Paint _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4;
  final Paint _glow = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
  final Paint _tick = Paint()
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.square;
  final Paint _dot = Paint();
  final Paint _bracket = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.square;
  final Paint _arc = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2;
  final Paint _finger = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final Map<String, TextPainter> _labels = {};
  double _frameA = 0;
  double _tight = 0;

  static const _white = Color(0xFFE9E6DF);
  static const _lock = Color(0xFFF0473C);

  TextPainter _label(String text, Color color, double size) {
    final key = '$text|${color.toARGB32()}|$size';
    return _labels.putIfAbsent(key, () {
      return TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: Sutura.fMono,
            fontSize: size,
            color: color,
            letterSpacing: 1.6,
            shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 4)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  @override
  void onRemove() {
    for (final l in _labels.values) {
      l.dispose();
    }
    _labels.clear();
    super.onRemove();
  }

  @override
  void update(double dt) {
    final g = game;
    final show = !g.ended && !g.puppet.dead && g.fleeProgress <= 0;
    _frameA += ((show ? 1.0 : 0.0) - _frameA) * math.min(1, dt * 6);
    final target = g.aim.active ? g.aim.tightness : 0.0;
    _tight += (target - _tight) * math.min(1, dt * 10);
  }

  void _corners(Canvas c, Rect r, double k, Paint p) {
    c.drawLine(r.topLeft, r.topLeft.translate(k, 0), p);
    c.drawLine(r.topLeft, r.topLeft.translate(0, k), p);
    c.drawLine(r.topRight, r.topRight.translate(-k, 0), p);
    c.drawLine(r.topRight, r.topRight.translate(0, k), p);
    c.drawLine(r.bottomLeft, r.bottomLeft.translate(k, 0), p);
    c.drawLine(r.bottomLeft, r.bottomLeft.translate(0, -k), p);
    c.drawLine(r.bottomRight, r.bottomRight.translate(-k, 0), p);
    c.drawLine(r.bottomRight, r.bottomRight.translate(0, -k), p);
  }

  @override
  void render(Canvas canvas) {
    final g = game;
    final aim = g.aim;

    // Marco fino alrededor de la criatura: se cierra mientras se apunta.
    if (_frameA > 0.01) {
      final f = g.frameRect;
      if (!f.isEmpty) {
        final inset = 14 * _tight;
        final r = Rect.fromLTRB(f.left + inset, f.top + inset * 0.6, f.right - inset, f.bottom - inset * 0.6);
        _bracket.color = _white.withValues(alpha: (0.45 + 0.45 * _tight) * _frameA);
        _corners(canvas, r, 18 - 6 * _tight, _bracket);
      }
    }

    if (!aim.active) return;
    final body = g.bodyRect;
    final head = g.headRect;
    final p = aim.point;
    final r = aim.radius;
    final tight = aim.tightness;
    final zone = zoneFor(p, body, head);
    final locked = tight >= AimTuning.headTightness;
    final onHead = zone == AimZone.head;

    final Color col;
    if (aim.charged) {
      col = Sutura.amber;
    } else if (zone == AimZone.off) {
      col = Sutura.textLow;
    } else if (onHead && locked) {
      col = _lock;
    } else {
      col = _white;
    }

    if (onHead) {
      _bracket.color = (locked ? _lock : _white).withValues(alpha: 0.9);
      _corners(canvas, head.inflate(4), 8, _bracket);
    }

    // Guía hasta el dedo.
    _finger.color = col.withValues(alpha: 0.22);
    canvas.drawLine(p.translate(0, r + 12), aim.finger.translate(0, -18), _finger);
    canvas.drawCircle(aim.finger, 16, _finger);

    // Anillo.
    _glow.color = col.withValues(alpha: locked ? 0.38 : 0.18);
    canvas.drawCircle(p, r, _glow);
    _ring
      ..color = col.withValues(alpha: 0.95)
      ..strokeWidth = aim.charged ? 2.2 : 1.4;
    canvas.drawCircle(p, r, _ring);
    _tick.color = col;
    final tk = locked ? 7.0 : 10.0;
    canvas.drawLine(p.translate(-r - 3 - tk, 0), p.translate(-r - 3, 0), _tick);
    canvas.drawLine(p.translate(r + 3, 0), p.translate(r + 3 + tk, 0), _tick);
    canvas.drawLine(p.translate(0, -r - 3 - tk), p.translate(0, -r - 3), _tick);
    canvas.drawLine(p.translate(0, r + 3), p.translate(0, r + 3 + tk), _tick);
    _arc.color = col.withValues(alpha: 0.6);
    final rot = g.time * (aim.charged ? 5 : 2.4);
    final arcRect = Rect.fromCircle(center: p, radius: r + 7);
    canvas.drawArc(arcRect, rot, 0.6, false, _arc);
    canvas.drawArc(arcRect, rot + math.pi, 0.6, false, _arc);
    _dot.color = col;
    canvas.drawCircle(p, locked ? 2.4 : 1.6, _dot);

    // Lectura: zona + precisión.
    final pct = (tight * 100).round();
    final zoneText = switch (zone) {
      AimZone.head => 'CABEZA',
      AimZone.body => 'TORSO',
      AimZone.off => 'SIN BLANCO',
    };
    final l1 = _label(zoneText, col, 10.5);
    final l2 = _label('${pct.toString().padLeft(2, '0')}%', col.withValues(alpha: 0.85), 10.5);
    final y = p.dy + r + 16;
    l1.paint(canvas, Offset(p.dx - (l1.width + 8 + l2.width) / 2, y));
    l2.paint(canvas, Offset(p.dx - (l1.width + 8 + l2.width) / 2 + l1.width + 8, y));
    if (aim.charged) {
      final l = _label('CARGADO', Sutura.amber, 11.5);
      l.paint(canvas, Offset(p.dx - l.width / 2, p.dy - r - 40));
    } else if (onHead && locked) {
      final l = _label(g.aimStyle == AimStyle.firearm ? 'TIRO LIMPIO' : 'GOLPE LIMPIO', _lock, 10.5);
      l.paint(canvas, Offset(p.dx - l.width / 2, p.dy - r - 40));
    }
  }
}
