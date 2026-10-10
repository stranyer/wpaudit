// Escenario Flame del combate: placa de calle bajo la lluvia (con desenfoque
// de fondo), la criatura (detrás de [CreatureView]: hoy un títere de malla),
// lluvia en tres profundidades, niebla baja, efectos, la mano en primera
// persona con su arma, gradación de pantalla (viñeta, grano) y la retícula.
//
// Todo se dibuja en coordenadas de pantalla (dp). Las capas "de mundo" van
// dentro de un `_CameraRig` que aplica respiración, temblor y zoom; las de
// pantalla (mano, luz, viñeta, grano, retícula) no se mueven con la cámara.

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
import 'creature_view.dart';
import 'fp_hand.dart';
import 'fx_pool.dart';
import 'hand_layer.dart';
import 'puppet.dart' show PuppetAnimator;
import 'puppet_view.dart';
import 'stage_layout.dart';

/// Estilo de la retícula según el arma activa.
enum AimStyle { melee, firearm }

/// Crea el renderizador de la criatura a partir del arte cargado.
typedef CreatureViewFactory = CreatureView Function(CombatArt art);

/// Verde tóxico de las ampollas del Hinchado.
const _toxic = Color(0xFF9BE04A);

final Float64List _identity = Float64List.fromList(const [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

class CombatStageGame extends FlameGame implements CreatureStage, HandStage {
  CombatStageGame({
    required this.zombieType,
    this.bundle,
    this.onAimSignal,
    this.onReady,
    this.plate = CombatPlate.colon,
    HandKind hand = HandKind.pistol,
    CreatureViewFactory? creatureFactory,
  }) : _initialHand = hand,
       _factory = creatureFactory ?? ((art) => PuppetCreatureView(art));

  final ZombieTypeId zombieType;

  /// Placa pedida (si falta se usa la otra; ver [CombatArt.plateKind]).
  final CombatPlate plate;

  /// Bundle de assets (por defecto `rootBundle`; los tests pasan uno propio).
  final AssetBundle? bundle;

  /// Umbrales de la retícula (para hápticos): cerrada, cargada.
  final void Function(AimSignal signal)? onAimSignal;
  final VoidCallback? onReady;

  final CreatureViewFactory _factory;
  final HandKind _initialHand;

  CombatArt? _art;
  CombatArt? get art => _art;
  bool get artReady => _art != null;

  CreatureView? _view;

  /// Renderizador de la criatura (null hasta cargar el arte).
  CreatureView? get creature => _view;

  HandLayer? _hand;

  /// Capa de la mano en primera persona (null hasta cargar).
  HandLayer? get hand => _hand;

  StageLayout? _layout;
  @override
  StageLayout? get layout => _layout;
  int _layoutVersion = 0;
  Offset _pivot = Offset.zero;

  // Reloj y cámara.
  @override
  double time = 0;
  double _trauma = 0;
  double _kick = 0;
  double _fleeT = -1;
  double _downT = -1;

  // Estado de escena que fija la UI.
  bool stunned = false;
  @override
  bool charging = false;
  double healthRatio = 1;

  /// Combate terminado (se apaga el marco de puntería).
  bool ended = false;

  /// Desde dónde (y, pantalla) el HUD inferior tapa la escena: el reflejo y la
  /// sombra de contacto no se dibujan si quedan enteros detrás.
  @override
  double hudTop = double.infinity;

  /// y del borde superior de la botonera (la mano entra por debajo).
  @override
  double handBase = double.infinity;

  /// Guardia levantada (CUBRIRSE) mientras se reproduce el turno.
  set guard(bool v) => _hand?.rig.guard = v;

  final AimState aim = AimState();
  AimStyle aimStyle = AimStyle.melee;

  late final _FxLayer _fx;
  late final _ScreenLayer _screen;
  double _vaporIn = 0;
  double _ashIn = 0;
  final math.Random _rnd = math.Random();

  @override
  PlateLook get look => _art?.look ?? const PlateLook();

  @override
  double get beacon => _ScreenLayer.beacon(time, charging);

  @override
  double get flashLight => _hand?.rig.flash ?? 0;

  @override
  Size get viewSize => _layout?.view ?? Size(size.x, size.y);

  @override
  ui.Image? get fxAtlas => _art?.fxAtlas;

  @override
  Color backgroundColor() => Sutura.void_;

  @override
  Future<void> onLoad() async {
    final art = await CombatArt.load(zombieType, bundle: bundle, plate: plate);
    _art = art;
    final view = _factory(art);
    _view = view;
    _fx = _FxLayer(art.fxAtlas);
    _screen = _ScreenLayer(art);
    final hand = HandLayer(this, initial: _initialHand, bundle: bundle);
    _hand = hand;
    final rig = _CameraRig();
    await rig.addAll([
      _Backdrop(art),
      _Rain(mode: _RainMode.back, count: 150, seed: 2),
      _Fog(front: false, atlas: art.fxAtlas),
      _CreatureHost(view),
      _Rain(mode: _RainMode.body, count: 44, seed: 5),
      _fx,
      _Fog(front: true, atlas: art.fxAtlas),
    ]);
    await add(rig);
    await add(_ScreenUnder(_screen));
    await add(hand);
    await add(_Rain(mode: _RainMode.front, count: 70, seed: 9));
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
    _view?.dispose();
    _view = null;
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
      plateCover: art.plateCover,
      plateFocusX: art.plateFocusX,
      plateTopGap: art.plateTopGap,
      horizonAt: art.plateHorizonAt,
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
    final v = _view;
    if (v != null) v.holdCrouch = charging && !v.dead;
    if (aim.active) {
      final s = aim.advance(dt.clamp(0.0, 0.25) * 1000);
      if (s != AimSignal.none) onAimSignal?.call(s);
    }
    _hand?.rig.aiming = aim.active;
    if (_art != null && _layout != null) _emitAmbient(d);
    super.update(d);
  }

  /// Vapor tóxico del Hinchado y ceniza de la disolución.
  void _emitAmbient(double dt) {
    final c = _view;
    if (c == null || !c.hasPose) return;
    if (zombieType == ZombieTypeId.bloater && !c.dead) {
      _vaporIn -= dt;
      if (_vaporIn <= 0) {
        _vaporIn = 0.07 + _rnd.nextDouble() * 0.06;
        final p = c.randomPoint(_rnd, minH: 0.25, maxH: 0.8, maxSide: 0.85);
        if (p != null) _fx.vapor(p);
      }
    }
    if (c.dead) {
      final d = c.dissolve;
      if (d > 0.02 && d < 0.97) {
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
    final l = _layout;
    final v = _view;
    if (l == null || v == null || v.dead) return Rect.zero;
    final h = v.hasPose ? v.headWorld : l.head;
    return rectToView(h.isEmpty ? l.head : h);
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
  // Mano y arma
  // ---------------------------------------------------------------------------

  /// Cambia la mano que se ve (con la animación de bajar y subir).
  void setHand(HandKind kind) => _hand?.request(kind);

  /// Gatillo en seco.
  void dryFire() => _hand?.rig.click();

  /// Baja la mano (fin del combate).
  void lowerHand() => _hand?.rig.lowered = true;

  // ---------------------------------------------------------------------------
  // Reacciones (las llama la pantalla al reproducir los eventos)
  // ---------------------------------------------------------------------------

  /// Reproduce una animación de la criatura; devuelve su duración en segundos.
  double playZombie(ZombieAnim a) {
    final v = _view;
    if (_art == null || v == null) return 0;
    final d = switch (a) {
      ZombieAnim.idle => () {
        v.idle();
        return 0.0;
      }(),
      ZombieAnim.attack => v.attack(),
      ZombieAnim.charge => v.charge(),
      ZombieAnim.chargePrepare => v.chargePrepare(),
      ZombieAnim.scream => v.scream(),
      ZombieAnim.death => v.die(),
      // El retroceso lo dispara [impact] (necesita el punto).
      ZombieAnim.hit => v.duration(ZombieAnim.hit),
    };
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
  double zombieKeyTime(ZombieAnim a) => _view?.keyTime(a) ?? PuppetAnimator.keyTimeOf(a);

  double zombieDuration(ZombieAnim a) => _view?.duration(a) ?? PuppetAnimator.durationOf(a);

  void shake(double amount) => _trauma = math.min(1, _trauma + amount);

  void punch(double k) => _kick = math.max(_kick, k);

  /// Impacto sobre la criatura en `at` (pantalla). `lethal`: la mata (sin retroceso).
  void impact(Offset at, {bool crit = false, bool heavy = false, bool ranged = false, bool headshot = false, bool lethal = false}) {
    final l = _layout;
    final v = _view;
    if (_art == null || l == null || v == null) return;
    _fx.impact(at, crit: crit, heavy: heavy, ranged: ranged);
    v.hit(toWorld(at), strong: heavy, crit: crit, headshot: headshot, lethal: lethal);
    shake(crit ? 0.32 : (heavy ? 0.28 : 0.16));
  }

  void miss(Offset at, {bool ranged = false}) {
    if (_art == null) return;
    _fx.puff(at, ranged: ranged);
  }

  /// Disparo: retroceso de la mano, fogonazo en la boca del cañón y trazo.
  void muzzle(Offset target) {
    if (_art == null) return;
    _hand?.shoot(target);
    _screen.muzzle();
    punch(0.35);
    shake(0.12);
  }

  /// Golpe cuerpo a cuerpo: la mano barre (o el puño sale) y el tajo cruza.
  void slash(Offset target, {bool heavy = false}) {
    if (_art == null) return;
    _hand?.swing(target, heavy: heavy);
    _fx.slash(target, heavy: heavy);
    punch(heavy ? 0.5 : 0.25);
  }

  /// El jugador recibe daño (en el momento del impacto de la embestida).
  void hurt({bool charged = false, bool toxic = false}) {
    if (_art == null) return;
    _screen.hurt(toxic: toxic, strong: charged);
    _hand?.rig.dip();
    shake(charged ? 0.95 : 0.55);
    punch(charged ? 0.9 : 0.4);
  }

  /// El ataque falló o se cubrió: impacto suave contra la guardia.
  void blockedHit() {
    if (_art == null) return;
    _hand?.rig.dip();
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
    _hand?.rig.dip();
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

  void fleeOut() {
    _fleeT = 0;
    _view?.flee();
    lowerHand();
  }

  void playerDown() {
    _downT = 0;
    lowerHand();
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
      _leftSrc = Rect.fromLTWH(0, 0, 2, art.plate.height.toDouble()),
      _rightSrc = Rect.fromLTWH(art.plate.width - 2.0, 0, 2, art.plate.height.toDouble());

  final CombatArt art;
  final Rect _src, _skySrc, _leftSrc, _rightSrc;
  Rect _groundSrc = Rect.zero;
  // Un punto más oscura que el arte original (clave baja, como la referencia).
  late final Paint _paint = Paint()
    ..filterQuality = FilterQuality.medium
    ..colorFilter = ColorFilter.mode(art.plateTint, BlendMode.modulate);
  final Paint _groundShade = Paint();
  final Paint _skyShade = Paint();
  int _ver = -1;
  Rect _dst = Rect.zero, _sky = Rect.zero, _ground = Rect.zero, _left = Rect.zero, _right = Rect.zero;

  void _sync() {
    final l = game.layout;
    if (l == null) return;
    _ver = game._layoutVersion;
    _dst = l.plateRect;
    // Extensiones para que el temblor/zoom nunca muestre el vacío.
    _sky = Rect.fromLTRB(_dst.left, math.min(0, _dst.top) - 300, _dst.right, _dst.top + 1);
    // Cielo estirado (si la placa bajó): se oscurece hacia arriba.
    _skyShade.shader = ui.Gradient.linear(Offset(0, _dst.top), Offset(0, math.min(0.0, _dst.top - 40)), const [Color(0x00000000), Color(0xD0020304)]);
    _left = Rect.fromLTRB(_dst.left - 300, _dst.top - 300, _dst.left + 1, _dst.bottom + 300);
    _right = Rect.fromLTRB(_dst.right - 1, _dst.top - 300, _dst.right + 300, _dst.bottom + 300);
    // Piso: la franja de abajo de la placa, espejada (asfalto mojado que sigue).
    final ext = math.max(0.0, l.view.height - _dst.bottom) + 300;
    final k = _src.height / _dst.height;
    final srcH = math.min(_src.height * 0.45, ext * k);
    _groundSrc = Rect.fromLTWH(0, _src.height - srcH, _src.width, srcH);
    _ground = Rect.fromLTWH(_dst.left, _dst.bottom - 0.5, _dst.width, srcH / k);
    _groundShade.shader = ui.Gradient.linear(
      _ground.topCenter,
      _ground.topCenter.translate(0, math.min(_ground.height, l.view.height * 0.3)),
      const [Color(0x40000000), Color(0xB0000000)],
    );
  }

  @override
  void render(Canvas canvas) {
    if (_ver != game._layoutVersion) _sync();
    if (_dst.isEmpty) return;
    final img = art.plate;
    canvas.drawImageRect(img, _leftSrc, _left, _paint);
    canvas.drawImageRect(img, _rightSrc, _right, _paint);
    canvas.drawImageRect(img, _skySrc, _sky, _paint);
    if (_dst.top > 0) canvas.drawRect(_sky, _skyShade);
    // Piso espejado (sin costura: arranca en el borde inferior de la placa).
    canvas.save();
    canvas.translate(0, _ground.top);
    canvas.scale(1, -1);
    canvas.drawImageRect(img, _groundSrc, Rect.fromLTWH(_ground.left, -_ground.height, _ground.width, _ground.height), _paint);
    canvas.restore();
    canvas.drawRect(_ground, _groundShade);
    canvas.drawImageRect(img, _src, _dst, _paint);
  }
}

// -----------------------------------------------------------------------------
// Lluvia (tres profundidades) y salpicaduras en el piso
// -----------------------------------------------------------------------------

enum _RainMode {
  /// Fina y lenta, detrás de la criatura.
  back,

  /// Gotas que cruzan delante del cuerpo, encendidas por la linterna.
  body,

  /// Gruesas y rápidas, delante de todo (también de la mano).
  front,
}

class _Rain extends Component with HasGameReference<CombatStageGame> {
  _Rain({required this.mode, required this.count, required int seed})
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

  final _RainMode mode;
  final int count;
  final math.Random _rnd;
  final Float32List _x, _y, _v, _len, _pts;
  static const _splashes = 24;
  final Float32List _sx, _sy, _sAge, _sPts;
  int _sNext = 0;
  double _splashIn = 0;
  static const double _wind = 0.11;
  Size _view = Size.zero;
  Rect _zone = Rect.zero;

  bool get _front => mode == _RainMode.front;

  late final Paint _paint = Paint()
    ..strokeWidth = switch (mode) {
      _RainMode.front => 1.4,
      _RainMode.body => 1.15,
      _RainMode.back => 0.9,
    }
    ..strokeCap = StrokeCap.round
    ..color = switch (mode) {
      _RainMode.front => const Color(0x30D6E2EC),
      _RainMode.body => const Color(0x4CE4ECF2),
      _RainMode.back => const Color(0x24B4C6D4),
    };
  final Paint _splash = Paint()
    ..strokeWidth = 1
    ..color = const Color(0x40C8D6E0);

  void _seed(int i, {required bool initial}) {
    final w = _view.width, h = _view.height;
    if (mode == _RainMode.body) {
      final z = _zone;
      _x[i] = z.left + _rnd.nextDouble() * z.width;
      _y[i] = initial ? z.top + _rnd.nextDouble() * z.height : z.top - _rnd.nextDouble() * z.height * 0.3;
      _v[i] = 1050 + _rnd.nextDouble() * 400;
      _len[i] = 16 + _rnd.nextDouble() * 16;
      return;
    }
    _x[i] = -w * 0.15 + _rnd.nextDouble() * w * 1.3;
    _y[i] = initial ? _rnd.nextDouble() * h : -_rnd.nextDouble() * h * 0.25;
    _v[i] = _front ? 1500 + _rnd.nextDouble() * 600 : 720 + _rnd.nextDouble() * 280;
    _len[i] = _front ? 26 + _rnd.nextDouble() * 26 : 9 + _rnd.nextDouble() * 12;
  }

  @override
  void update(double dt) {
    final l = game.layout;
    if (l == null) return;
    if (_view != l.view) {
      _view = l.view;
      _zone = Rect.fromLTRB(l.body.left - l.body.width * 0.1, l.body.top - l.body.height * 0.15, l.body.right + l.body.width * 0.1, l.floorY);
      for (var i = 0; i < count; i++) {
        _seed(i, initial: true);
      }
    }
    final bottom = mode == _RainMode.body ? _zone.bottom : _view.height + 20;
    for (var i = 0; i < count; i++) {
      _y[i] += _v[i] * dt;
      _x[i] += _v[i] * _wind * dt;
      if (_y[i] - _len[i] > bottom) _seed(i, initial: false);
    }
    if (_front) {
      _splashIn -= dt;
      while (_splashIn <= 0) {
        _splashIn += 0.035;
        final i = _sNext;
        _sNext = (_sNext + 1) % _splashes;
        _sAge[i] = 0;
        _sx[i] = _rnd.nextDouble() * _view.width;
        final g = math.pow(_rnd.nextDouble(), 0.7).toDouble();
        final hz = l.plateRect.top + l.plateRect.height * ((game.art?.plateHorizon ?? 0.44) + 0.05);
        _sy[i] = hz + (l.view.height - hz) * g;
      }
      for (var i = 0; i < _splashes; i++) {
        if (_sAge[i] < 1) _sAge[i] += dt;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (_view.isEmpty) return;
    if (mode == _RainMode.body) {
      // Más visibles donde pega la linterna (sigue la luz que barre el cuerpo).
      final t = game.time;
      final k = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(t * 0.41 + 1.2));
      _paint.color = Color.fromARGB((0x4C * k).round(), 0xE4, 0xEC, 0xF2);
    }
    for (var i = 0; i < count; i++) {
      final o = i * 4;
      final len = _len[i];
      _pts[o] = _x[i];
      _pts[o + 1] = _y[i];
      _pts[o + 2] = _x[i] - len * _wind;
      _pts[o + 3] = _y[i] - len;
    }
    canvas.drawRawPoints(ui.PointMode.lines, _pts, _paint);
    if (!_front) return;
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
  _Fog({required this.front, required this.atlas}) : _pool = FxPool(front ? 12 : 6), _rnd = math.Random(front ? 4 : 8);

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
      // Neblina pegada al piso: se espesa justo en los pies (los "planta" en
      // la calle) y se aclara hacia abajo.
      final top = l.floorY - l.body.height * 0.2;
      _bandRect = Rect.fromLTRB(-200, top, v.width + 200, v.height + 200);
      _band.shader = ui.Gradient.linear(
        Offset(0, top),
        Offset(0, v.height + 40),
        const [Color(0x00262B30), Color(0x44303840), Color(0x62343C44), Color(0x3A1A2228), Color(0x22101519)],
        _stops((l.body.height * 0.2) / (v.height + 40 - top)),
      );
    } else {
      final y = l.plateRect.top + l.plateRect.height * ((game.art?.plateHorizon ?? 0.42) + 0.02);
      _bandRect = Rect.fromLTRB(-200, y - v.height * 0.16, v.width + 200, y + v.height * 0.12);
      _band.shader = ui.Gradient.linear(
        _bandRect.topCenter,
        _bandRect.bottomCenter,
        const [Color(0x00334049), Color(0x30334049), Color(0x00334049)],
        const [0, 0.55, 1],
      );
    }
  }

  static List<double> _stops(double feet) {
    final f = feet.clamp(0.1, 0.6);
    return [0, f * 0.7, f, math.min(0.9, f + 0.3), 1];
  }

  void _spawn({required bool initial}) {
    final l = game.layout;
    if (l == null) return;
    final v = l.view;
    final size = v.width * (0.6 + _rnd.nextDouble() * 0.6);
    final y = front ? l.floorY + v.height * (-0.05 + _rnd.nextDouble() * 0.12) : v.height * (0.34 + _rnd.nextDouble() * 0.26);
    final dir = _rnd.nextBool() ? 1.0 : -1.0;
    // La mitad de los bancos de adelante nacen sobre los pies.
    final feet = front && _rnd.nextBool();
    final x = feet
        ? l.feet.dx + (_rnd.nextDouble() - 0.5) * l.body.width
        : (initial ? _rnd.nextDouble() * v.width : (dir > 0 ? -size * 0.4 : v.width + size * 0.4));
    _pool.spawn(
      x: x,
      y: y,
      vx: dir * (6 + _rnd.nextDouble() * 10),
      vy: -0.5 - _rnd.nextDouble(),
      life: 18 + _rnd.nextDouble() * 10,
      size: size,
      src: FxAtlas.blob,
      color: front ? Color.fromARGB(46 + _rnd.nextInt(22), 150, 160, 168) : Color.fromARGB(24 + _rnd.nextInt(12), 136, 152, 164),
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
      _spawnIn = front ? 1.9 : 3.4;
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
// Criatura: delega en el [CreatureView] (hoy, el títere de malla)
// -----------------------------------------------------------------------------

class _CreatureHost extends Component with HasGameReference<CombatStageGame> {
  _CreatureHost(this.view);

  final CreatureView view;

  @override
  void update(double dt) => view.update(dt, game);

  @override
  void render(Canvas canvas) => view.render(canvas, game);
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
    final cv = g.creature;
    if (g.stunned && cv != null && !cv.dead) {
      final h = cv.hasPose ? cv.headWorld : Rect.zero;
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

  /// Fogonazo: destello cálido de toda la pantalla (el de la boca del cañón
  /// lo dibuja la mano).
  void muzzle() => _muzzleT = 0;

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

  /// Debajo de la mano: luz de emergencia y viñeta.
  void renderUnder(Canvas canvas) {
    if (_ver != game._layoutVersion) _sync();
    if (_size.isEmpty) return;
    final g = game;
    if (g.look.emergency) {
      final b = beacon(g.time, g.charging);
      final em = ((g.charging ? 0.07 : 0.04) + b * (g.charging ? 0.2 : 0.12)).clamp(0.0, 1.0);
      _emergency.color = Color.fromARGB((em * 255).round(), 255, 255, 255);
      canvas.drawRect(_full, _emergency);
    }
    canvas.drawRect(_full, _vignette);
  }

  /// Encima de la mano: grano, golpes, curas, fogonazo y fundidos.
  @override
  void render(Canvas canvas) {
    if (_ver != game._layoutVersion) _sync();
    if (_size.isEmpty) return;
    final g = game;
    final t = g.time;

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

    // Grano.
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

    // Fogonazo del arma: la escena se enciende un instante.
    if (_muzzleT < 1) {
      final a = 1 - _muzzleT;
      _flat.color = Color.fromARGB((a * 34).round(), 255, 226, 170);
      canvas.drawRect(_full, _flat);
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

/// Pinta la parte de [_ScreenLayer] que va debajo de la mano.
class _ScreenUnder extends Component {
  _ScreenUnder(this.screen);
  final _ScreenLayer screen;

  @override
  void render(Canvas canvas) => screen.renderUnder(canvas);
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
    final show = !g.ended && !(g.creature?.dead ?? false) && g.fleeProgress <= 0;
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
