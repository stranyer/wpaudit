// Escenario Flame del combate: fondo, zombie animado, niebla, efectos,
// luz de emergencia, cámara con respiración/temblor y la retícula de puntería.
//
// Todo se dibuja en coordenadas de pantalla (dp). Las capas "de mundo" van
// dentro de un `_CameraRig` que aplica respiración, temblor y zoom; las de
// pantalla (luz, viñetas, retícula) no se mueven con la cámara.

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
import 'combat_manifest.dart';
import 'fx_pool.dart';

/// Estilo de la retícula según el arma activa.
enum AimStyle { melee, firearm }

class CombatStageGame extends FlameGame {
  CombatStageGame({required this.zombieType, this.bundle, this.onAimSignal, this.onReady});

  final ZombieTypeId zombieType;

  /// Bundle de assets (por defecto `rootBundle`; los tests pasan uno propio).
  final AssetBundle? bundle;

  /// Umbrales de la retícula (para hápticos): cerrada, cargada.
  final void Function(AimSignal signal)? onAimSignal;
  final VoidCallback? onReady;

  CombatArt? _art;
  CombatArt? get art => _art;
  bool get artReady => _art != null;

  StageLayout _layout = const StageLayout(view: Size.zero, bgSize: Size(720, 1280), scale: 1, offset: Offset.zero);
  StageLayout get layout => _layout;
  Rect _frame = Rect.zero;
  Rect _body = Rect.zero;
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

  final AimState aim = AimState();
  AimStyle aimStyle = AimStyle.melee;

  late final _ZombieLayer _zombie;
  late final _FxLayer _fx;
  late final _ScreenLayer _screen;

  @override
  Color backgroundColor() => Sutura.void_;

  @override
  Future<void> onLoad() async {
    final art = await CombatArt.load(zombieType, bundle: bundle);
    _art = art;
    _zombie = _ZombieLayer(art);
    _fx = _FxLayer(art.fxAtlas);
    _screen = _ScreenLayer(art.fxAtlas);
    final rig = _CameraRig();
    await rig.addAll([_Backdrop(art), _zombie, _Foreground(art), _fx]);
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
    _art?.dispose();
    _art = null;
    super.onDispose();
  }

  void _relayout() {
    final art = _art;
    if (art == null || size.x <= 0 || size.y <= 0) return;
    final view = Size(size.x, size.y);
    _layout = StageLayout.compute(view: view, bg: art.bgSize, frameBgHeight: art.placement.bgRect.height);
    _frame = _layout.rectToScreen(art.placement.bgRect);
    _body = frameBoxToScreen(art.bodyInFrame, art.frameSize, _frame);
    _pivot = Offset(view.width / 2, _body.center.dy);
    _screen.resize(view);
  }

  @override
  void update(double dt) {
    final d = dt.clamp(0.0, 0.05);
    time += d;
    _trauma = math.max(0, _trauma - d * 1.6);
    _kick = math.max(0, _kick - d * 3.5);
    if (_fleeT >= 0) _fleeT = math.min(1, _fleeT + d / 0.75);
    if (_downT >= 0) _downT = math.min(1, _downT + d / 1.1);
    if (aim.active) {
      // La retícula usa el tiempo real (aunque se pierdan cuadros, el ritmo
      // de cierre no cambia).
      final s = aim.advance(dt.clamp(0.0, 0.25) * 1000);
      if (s != AimSignal.none) onAimSignal?.call(s);
    }
    super.update(d);
  }

  // ---------------------------------------------------------------------------
  // Cámara y geometría en pantalla
  // ---------------------------------------------------------------------------

  double get _zoom => 1.014 + 0.006 * math.sin(time * 0.39) + _kick * 0.045 - (_fleeT > 0 ? 0.10 * _ease(_fleeT) : 0);
  double get _swayX => math.sin(time * 0.47) * 2.4;
  double get _swayY => math.sin(time * 0.83) * 1.6 + (_fleeT > 0 ? 70 * _ease(_fleeT) : 0) + (_downT > 0 ? 40 * _ease(_downT) : 0);

  /// Mundo → pantalla (sin el temblor, que es breve y de alta frecuencia).
  Offset toView(Offset p) {
    final z = _zoom;
    return Offset((p.dx - _pivot.dx) * z + _pivot.dx + _swayX, (p.dy - _pivot.dy) * z + _pivot.dy + _swayY);
  }

  Rect rectToView(Rect r) => Rect.fromPoints(toView(r.topLeft), toView(r.bottomRight));

  /// Caja del cuerpo del zombie en pantalla.
  Rect get bodyRect => rectToView(_body);

  /// Caja de la cabeza en pantalla para el cuadro que se ve ahora.
  Rect get headRect {
    final art = _art;
    if (art == null) return Rect.zero;
    final hf = _zombie.headInFrame();
    if (hf == null) return headRectOf(bodyRect);
    if (hf.isEmpty) return Rect.zero; // cabeza oculta: sin zona de cabeza
    return rectToView(frameBoxToScreen(hf, art.frameSize, _frame));
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

  /// Reproduce una animación del zombie; devuelve su duración en segundos.
  double playZombie(ZombieAnim a) => _art == null ? 0 : _zombie.play(a);

  /// Segundos hasta el impacto/pico de una animación.
  double zombieKeyTime(ZombieAnim a) => _art?.keyTimeOf(_zombie.resolve(a)) ?? 0.3;

  double zombieDuration(ZombieAnim a) => _art?.durationOf(_zombie.resolve(a)) ?? 0.6;

  void zombieFlash({bool red = false}) {
    if (_art != null) _zombie.flash(red: red);
  }

  void shake(double amount) => _trauma = math.min(1, _trauma + amount);

  void punch(double k) => _kick = math.max(_kick, k);

  void impact(Offset at, {bool crit = false, bool heavy = false, bool ranged = false}) {
    if (_art == null) return;
    _fx.impact(at, crit: crit, heavy: heavy, ranged: ranged);
    _zombie.flash(red: crit);
    _zombie.knock(heavy || crit ? 1 : 0.6);
    shake(crit ? 0.32 : (heavy ? 0.28 : 0.16));
  }

  void miss(Offset at, {bool ranged = false}) {
    if (_art == null) return;
    _fx.dust(at, ranged: ranged);
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

  /// El jugador recibe daño.
  void hurt({bool charged = false, bool toxic = false}) {
    if (_art == null) return;
    _screen.hurt(toxic: toxic, strong: charged);
    shake(charged ? 0.85 : 0.5);
    if (charged) punch(0.8);
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
    _fx.toxic(chestPoint);
    _screen.hurt(toxic: true, strong: false);
  }

  void screamWave() {
    if (_art == null) return;
    _fx.ring(headPoint.translate(0, headRect.height * 0.6), Sutura.danger, 240, 0.9);
    _fx.ring(headPoint.translate(0, headRect.height * 0.6), Sutura.danger, 170, 0.7, delay: 0.12);
    shake(0.45);
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
    final shx = tr * 15 * (math.sin(t * 61.3 + 0.7) * 0.7 + math.sin(t * 23.1) * 0.3);
    final shy = tr * 12 * (math.sin(t * 47.9 + 2.1) * 0.7 + math.sin(t * 17.3 + 1) * 0.3);
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
// Fondo
// -----------------------------------------------------------------------------

class _Backdrop extends Component with HasGameReference<CombatStageGame> {
  _Backdrop(this.art)
    : _src = Rect.fromLTWH(0, 0, art.background.width.toDouble(), art.background.height.toDouble()),
      _skySrc = Rect.fromLTWH(0, 0, art.background.width.toDouble(), 2),
      _groundSrc = Rect.fromLTWH(0, art.background.height - 2.0, art.background.width.toDouble(), 2);

  final CombatArt art;
  final Rect _src;
  final Rect _skySrc;
  final Rect _groundSrc;
  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;
  final Paint _void = Paint()..color = const Color(0xFF040607);

  Rect _dst = Rect.zero;
  Rect _sky = Rect.zero;
  Rect _ground = Rect.zero;
  Rect _left = Rect.zero;
  Rect _right = Rect.zero;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _sync();
  }

  @override
  void onMount() {
    super.onMount();
    _sync();
  }

  void _sync() {
    final l = game._layout;
    _dst = l.bgScreenRect;
    // Extensiones para que el temblor/zoom nunca muestre el vacío.
    _sky = Rect.fromLTRB(_dst.left, _dst.top - 400, _dst.right, _dst.top + 1);
    _ground = Rect.fromLTRB(_dst.left, _dst.bottom - 1, _dst.right, _dst.bottom + 400);
    _left = Rect.fromLTRB(-400, -400, _dst.left + 0.5, l.view.height + 400);
    _right = Rect.fromLTRB(_dst.right - 0.5, -400, l.view.width + 400, l.view.height + 400);
  }

  @override
  void render(Canvas canvas) {
    if (_dst != game._layout.bgScreenRect) _sync();
    final img = art.background;
    canvas.drawImageRect(img, _skySrc, _sky, _paint);
    canvas.drawImageRect(img, _groundSrc, _ground, _paint);
    canvas.drawImageRect(img, _src, _dst, _paint);
    if (_dst.left > -20) canvas.drawRect(_left, _void);
    if (_dst.right < game._layout.view.width + 20) canvas.drawRect(_right, _void);
  }
}

// -----------------------------------------------------------------------------
// Zombie
// -----------------------------------------------------------------------------

class _ZombieLayer extends Component with HasGameReference<CombatStageGame> {
  _ZombieLayer(this.art) {
    // Destello de impacto: tinte parcial (el detalle del sprite se sigue viendo).
    for (var i = 0; i < 8; i++) {
      final a = (i + 1) * 20; // hasta ~63 %
      _white.add(
        Paint()
          ..colorFilter = const ColorFilter.mode(Color(0xFFF2FAFB), BlendMode.srcIn)
          ..color = Color.fromARGB(a, 255, 255, 255)
          ..filterQuality = FilterQuality.medium,
      );
      _red.add(
        Paint()
          ..colorFilter = const ColorFilter.mode(Color(0xFFFF4A52), BlendMode.srcIn)
          ..color = Color.fromARGB((a * 0.85).round(), 255, 255, 255)
          ..filterQuality = FilterQuality.medium,
      );
      _glow.add(
        Paint()
          ..colorFilter = const ColorFilter.mode(Color(0xFFEE3B45), BlendMode.srcIn)
          ..color = Color.fromARGB((a * 0.55).round(), 255, 255, 255)
          ..filterQuality = FilterQuality.low,
      );
    }
  }

  final CombatArt art;
  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;
  final List<Paint> _white = [];
  final List<Paint> _red = [];
  final List<Paint> _glow = [];

  ZombieAnim _anim = ZombieAnim.idle;
  double _t = 0;
  double _idleT = 0;
  double _flash = 0;
  bool _flashRed = false;
  double _knock = 0;
  bool _dead = false;

  /// Animación pedida pero sin tira: se imita con transformaciones sobre idle.
  ZombieAnim? _emu;
  double _emuT = 0;

  ZombieAnim get anim => _anim;

  /// Animación que realmente se va a ver para `a`.
  ZombieAnim resolve(ZombieAnim a) {
    if (!art.hasSprites || art.strips.containsKey(a)) return a;
    if (a == ZombieAnim.charge && art.strips.containsKey(ZombieAnim.attack)) return ZombieAnim.attack;
    return ZombieAnim.idle;
  }

  double play(ZombieAnim a) {
    if (_dead) return 0;
    final r = resolve(a);
    if (r == ZombieAnim.idle && a != ZombieAnim.idle) {
      _emu = a;
      _emuT = 0;
      return _emuDuration(a);
    }
    _anim = r;
    _t = 0;
    _emu = null;
    if (r == ZombieAnim.death) _dead = true;
    return art.durationOf(r);
  }

  static double _emuDuration(ZombieAnim a) => switch (a) {
    ZombieAnim.attack || ZombieAnim.charge => 0.6,
    ZombieAnim.death => 1.0,
    _ => 0.5,
  };

  void flash({bool red = false}) {
    _flash = 1;
    _flashRed = red;
  }

  void knock(double k) => _knock = math.max(_knock, k);

  int get frameIndex {
    final s = art.strips[_anim];
    if (s == null) return 0;
    final spec = s.spec;
    final i = (_t * spec.fpsOr(art.manifest.fps)).floor();
    if (spec.loop) return i % spec.frames;
    return math.min(i, spec.frames - 1);
  }

  Rect? headInFrame() {
    if (!art.hasSprites) return art.headInFrame(0);
    if (_anim == ZombieAnim.idle) return art.headInFrame(frameIndex);
    if (_anim == ZombieAnim.chargePrepare && art.headHoldInFrame != null) return art.headHoldInFrame;
    return art.headInFrame(0);
  }

  @override
  void update(double dt) {
    _t += dt;
    _idleT += dt;
    _flash = math.max(0, _flash - dt / 0.11);
    _knock = math.max(0, _knock - dt / 0.22);
    if (_emu != null) {
      _emuT += dt;
      if (_emuT > _emuDuration(_emu!) && _emu != ZombieAnim.chargePrepare) _emu = null;
    }
    final s = art.strips[_anim];
    final dur = s != null ? s.spec.duration(art.manifest.fps) : art.durationOf(_anim);
    final hold = s?.spec.holdLast ?? (_anim == ZombieAnim.death || _anim == ZombieAnim.chargePrepare);
    final loop = s?.spec.loop ?? _anim == ZombieAnim.idle;
    if (!loop && !hold && _t >= dur) {
      _anim = ZombieAnim.idle;
      _t = 0;
    }
  }

  @override
  void render(Canvas canvas) {
    final g = game;
    final frame = g._frame;
    if (frame.isEmpty) return;
    final feet = Offset(frame.center.dx, frame.top + frame.height * art.placement.groundInFrame);
    // Reacciones procedurales encima de la animación.
    var k = 1.0 - 0.03 * _knock;
    var dy = -7.0 * _knock;
    var sq = 1.0;
    final emu = _emu;
    if (emu != null) {
      final p = (_emuT / _emuDuration(emu)).clamp(0.0, 1.0);
      final b = math.sin(p * math.pi);
      switch (emu) {
        case ZombieAnim.attack || ZombieAnim.charge:
          k += (emu == ZombieAnim.charge ? 0.22 : 0.12) * b;
        case ZombieAnim.hit:
          dy -= 6 * b;
        case ZombieAnim.chargePrepare:
          sq = 1 - 0.05 * Curves.easeOut.transform(p);
        case ZombieAnim.scream:
          k += 0.05 * b + 0.01 * math.sin(_emuT * 70) * b;
        default:
          break;
      }
    }
    final glow = g.charging && !_dead ? 0.55 + 0.45 * math.sin(g.time * 9) : 0.0;

    final proc = art.procedural;
    if (proc != null) {
      canvas.save();
      canvas.translate(feet.dx, feet.dy + dy);
      canvas.scale(k, k * sq);
      canvas.translate(-feet.dx, -feet.dy);
      proc.render(
        canvas,
        frameDst: frame,
        anim: emu ?? _anim,
        t: emu != null ? _emuT : _t,
        idleT: _idleT,
        flash: _flash,
        flashRed: _flashRed,
        glow: glow,
      );
      canvas.restore();
      return;
    }

    final strip = art.strips[_anim] ?? art.strips[ZombieAnim.idle]!;
    final src = strip.frames[frameIndex.clamp(0, strip.frames.length - 1)];
    canvas.save();
    canvas.translate(feet.dx, feet.dy + dy);
    canvas.scale(k, k * sq);
    canvas.translate(-feet.dx, -feet.dy);
    if (glow > 0) {
      canvas.save();
      canvas.translate(feet.dx, feet.dy);
      canvas.scale(1.025, 1.012);
      canvas.translate(-feet.dx, -feet.dy);
      canvas.drawImageRect(strip.image, src, frame, _glow[(glow * 7).round().clamp(0, 7)]);
      canvas.restore();
    }
    canvas.drawImageRect(strip.image, src, frame, _paint);
    if (_flash > 0) {
      final i = (_flash * 7).round().clamp(0, 7);
      canvas.drawImageRect(strip.image, src, frame, (_flashRed ? _red : _white)[i]);
    }
    canvas.restore();
  }
}

// -----------------------------------------------------------------------------
// Primer plano: niebla del arte + bancos de niebla fría procedurales
// -----------------------------------------------------------------------------

class _Foreground extends Component with HasGameReference<CombatStageGame> {
  // Con la niebla del arte alcanzan pocos bancos extra (cuidar el overdraw).
  _Foreground(this.art) : _fog = FxPool(art.foreground != null ? 5 : 9);

  final CombatArt art;
  final FxPool _fog;
  final Paint _fgPaint = Paint()..filterQuality = FilterQuality.medium;
  final math.Random _rnd = math.Random(3);
  Rect _fgSrc = Rect.zero;
  bool _seeded = false;
  double _spawnIn = 0;

  @override
  void onMount() {
    super.onMount();
    final fg = art.foreground;
    if (fg != null) _fgSrc = Rect.fromLTWH(0, 0, fg.width.toDouble(), fg.height.toDouble());
  }

  void _spawn({required bool initial}) {
    final v = game._layout.view;
    if (v.isEmpty) return;
    final low = _rnd.nextDouble() < 0.7;
    final size = v.width * (0.55 + _rnd.nextDouble() * 0.5);
    final y = low ? v.height * (0.62 + _rnd.nextDouble() * 0.3) : v.height * (0.3 + _rnd.nextDouble() * 0.3);
    final dir = _rnd.nextBool() ? 1.0 : -1.0;
    final x = initial ? _rnd.nextDouble() * v.width : (dir > 0 ? -size * 0.4 : v.width + size * 0.4);
    _fog.spawn(
      x: x,
      y: y,
      vx: dir * (5 + _rnd.nextDouble() * 9),
      vy: -1 - _rnd.nextDouble() * 2,
      life: 16 + _rnd.nextDouble() * 10,
      size: size,
      src: FxAtlas.blob,
      color: Color.fromARGB((low ? 34 : 22) + _rnd.nextInt(14), 150, 172, 182),
      grow: 0.012,
      rot: _rnd.nextDouble() * math.pi,
      spin: (_rnd.nextDouble() - 0.5) * 0.04,
      fadeIn: 0.3,
    );
  }

  @override
  void update(double dt) {
    if (!_seeded && !game._layout.view.isEmpty) {
      _seeded = true;
      for (var i = 0; i < _fog.capacity; i++) {
        _spawn(initial: true);
      }
    }
    _spawnIn -= dt;
    if (_spawnIn <= 0) {
      _spawnIn = 3.2;
      _spawn(initial: false);
    }
    _fog.update(dt);
  }

  @override
  void render(Canvas canvas) {
    final fg = art.foreground;
    if (fg != null) {
      final drift = math.sin(game.time * 0.21) * 5;
      canvas.save();
      canvas.translate(drift, 0);
      canvas.drawImageRect(fg, _fgSrc, game._layout.bgScreenRect, _fgPaint);
      canvas.restore();
    }
    _fog.render(canvas, art.fxAtlas);
  }
}

// -----------------------------------------------------------------------------
// Efectos de mundo: chispas, polvo, nube tóxica, tajos, ondas
// -----------------------------------------------------------------------------

class _FxLayer extends Component with HasGameReference<CombatStageGame> {
  _FxLayer(this.atlas);

  final ui.Image atlas;
  final FxPool _dark = FxPool(72);
  final FxPool _bright = FxPool(64, blend: BlendMode.plus);
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

  // Ondas (grito, aturdimiento).
  static const _rings = 6;
  final List<double> _rx = List.filled(_rings, 0);
  final List<double> _ry = List.filled(_rings, 0);
  final List<double> _rAge = List.filled(_rings, 9);
  final List<double> _rLife = List.filled(_rings, 1);
  final List<double> _rMax = List.filled(_rings, 100);
  final List<Color> _rCol = List.filled(_rings, Sutura.danger);
  int _rNext = 0;
  final Paint _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
  final Paint _stunPaint = Paint()..color = Sutura.signal;
  final Paint _stunGlow = Paint()
    ..color = const Color(0x666ADBEA)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

  double _r(double a, double b) => a + _rnd.nextDouble() * (b - a);

  void impact(Offset at, {required bool crit, required bool heavy, required bool ranged}) {
    final n = crit ? 22 : (heavy ? 18 : 12);
    // Esquirlas y ceniza oscura (sin sangre).
    for (var i = 0; i < n; i++) {
      final a = _r(-math.pi, math.pi);
      final sp = _r(120, crit ? 520 : 380);
      _dark.spawn(
        x: at.dx,
        y: at.dy,
        vx: math.cos(a) * sp,
        vy: math.sin(a) * sp - 80,
        life: _r(0.35, 0.8),
        size: _r(4, 9),
        src: FxAtlas.shard,
        color: Color.fromARGB(230, 18 + _rnd.nextInt(14), 20 + _rnd.nextInt(12), 22 + _rnd.nextInt(10)),
        rot: _r(0, 6),
        spin: _r(-14, 14),
        drag: 2.2,
        gravity: 900,
      );
    }
    for (var i = 0; i < 4; i++) {
      _dark.spawn(
        x: at.dx + _r(-8, 8),
        y: at.dy + _r(-8, 8),
        vx: _r(-40, 40),
        vy: _r(-50, -10),
        life: _r(0.6, 1.1),
        size: _r(40, 70),
        src: FxAtlas.blob,
        color: const Color(0x8C0B0E10),
        grow: 1.2,
        drag: 2,
      );
    }
    // Chispas frías (cian) y, en críticos, ámbar.
    final sparks = crit ? 16 : 9;
    for (var i = 0; i < sparks; i++) {
      final a = _r(-math.pi, math.pi);
      final sp = _r(260, 700);
      _bright.spawn(
        x: at.dx,
        y: at.dy,
        vx: math.cos(a) * sp,
        vy: math.sin(a) * sp,
        life: _r(0.12, 0.32),
        size: _r(14, 26),
        src: FxAtlas.streak,
        color: crit ? const Color(0xFFFFC768) : (ranged ? const Color(0xFFEAF4F5) : const Color(0xFF9FEAF3)),
        drag: 5,
        gravity: 300,
        alignToVelocity: true,
      );
    }
    _bright.spawn(
      x: at.dx,
      y: at.dy,
      life: 0.16,
      size: crit ? 120 : 80,
      src: FxAtlas.dot,
      color: crit ? const Color(0xC0FFC768) : const Color(0xA0D9F6FA),
      grow: 2,
    );
    if (crit) ring(at, Sutura.amber, 90, 0.35);
  }

  void dust(Offset at, {required bool ranged}) {
    for (var i = 0; i < 6; i++) {
      _dark.spawn(
        x: at.dx + _r(-10, 10),
        y: at.dy + _r(-6, 6),
        vx: _r(-60, 60),
        vy: _r(-60, -10),
        life: _r(0.5, 0.9),
        size: _r(26, 46),
        src: FxAtlas.blob,
        color: const Color(0x66707C80),
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

  void toxic(Offset at) {
    for (var i = 0; i < 14; i++) {
      final a = _r(-math.pi, math.pi);
      final sp = _r(60, 260);
      _dark.spawn(
        x: at.dx,
        y: at.dy,
        vx: math.cos(a) * sp,
        vy: math.sin(a) * sp * 0.6 - 30,
        life: _r(1.2, 2.0),
        size: _r(90, 160),
        src: FxAtlas.blob,
        color: const Color(0x8C6E4FA0),
        grow: 1.1,
        drag: 1.6,
        fadeIn: 0.1,
      );
    }
    ring(at, Sutura.toxin, 260, 0.6);
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
        color: const Color(0xB074C044),
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

  void ring(Offset at, Color color, double maxR, double life, {double delay = 0}) {
    final i = _rNext;
    _rNext = (_rNext + 1) % _rings;
    _rx[i] = at.dx;
    _ry[i] = at.dy;
    _rAge[i] = -delay;
    _rLife[i] = life;
    _rMax[i] = maxR;
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
      final col = _slashHeavy ? Sutura.amber : const Color(0xFFCFF4F8);
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
      final r = _rMax[i] * Curves.easeOut.transform(p);
      _ringPaint
        ..strokeWidth = 6 * (1 - p) + 1
        ..color = _rCol[i].withValues(alpha: 0.75 * (1 - p));
      canvas.drawCircle(Offset(_rx[i], _ry[i]), r, _ringPaint);
    }
    final g = game;
    if (g.stunned) {
      final h = g.headRect;
      final c = h.isEmpty ? g.bodyRect.topCenter : h.topCenter.translate(0, -10);
      for (var i = 0; i < 3; i++) {
        final a = g.time * 3.2 + i * math.pi * 2 / 3;
        final p = Offset(c.dx + math.cos(a) * 30, c.dy + math.sin(a) * 9);
        canvas.drawCircle(p, 6, _stunGlow);
        canvas.drawCircle(p, 2.6, _stunPaint);
      }
    }
    _bright.render(canvas, atlas);
  }
}

// -----------------------------------------------------------------------------
// Capa de pantalla: luz de emergencia, viñetas, fogonazo, desvanecidos
// -----------------------------------------------------------------------------

class _ScreenLayer extends Component with HasGameReference<CombatStageGame> {
  _ScreenLayer(this.atlas);

  static final Float64List _identity = Float64List.fromList(const [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

  final ui.Image atlas;
  Size _size = Size.zero;
  Rect _full = Rect.zero;
  final Paint _emergency = Paint()..blendMode = BlendMode.plus;
  final Paint _grade = Paint();
  final Paint _edge = Paint();
  final Paint _flat = Paint();
  final Paint _scan = Paint();
  final Paint _muzzle = Paint()..blendMode = BlendMode.plus;
  final Paint _tracer = Paint()
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;
  final Paint _hex = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  Path? _hexes;
  ui.Image? _scanImg;

  double _hurt = 0;
  bool _hurtToxic = false;
  double _muzzleT = 1;
  Offset _muzzleFrom = Offset.zero;
  Offset _muzzleTo = Offset.zero;
  double _shieldT = 1;
  double _healT = 1;
  double _dodgeT = 1;

  void resize(Size s) {
    if (s == _size || s.isEmpty) return;
    _size = s;
    _full = Offset.zero & s;
    final w = s.width;
    final h = s.height;
    _emergency.shader = ui.Gradient.radial(
      Offset(-w * 0.15, h * 0.42),
      w * 1.15,
      const [Color(0xFFEE3B45), Color(0x55EE3B45), Color(0x00000000)],
      const [0, 0.35, 1],
    );
    _grade.shader = ui.Gradient.radial(
      Offset(w / 2, h * 0.45),
      math.max(w, h) * 0.75,
      const [Color(0x00000000), Color(0x00000000), Color(0xB0000000)],
      const [0, 0.55, 1],
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
        final cy = h * 0.72 + row * r * 1.5;
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
    // Líneas de escaneo muy tenues (patrón de 1×4 repetido).
    if (_scanImg == null) {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint()..color = const Color(0x16000000));
      final pic = rec.endRecording();
      _scanImg = pic.toImageSync(1, 3);
      pic.dispose();
    }
    _scan.shader = ImageShader(_scanImg!, TileMode.repeated, TileMode.repeated, _identity);
  }

  @override
  void onRemove() {
    _scanImg?.dispose();
    super.onRemove();
  }

  void hurt({required bool toxic, required bool strong}) {
    _hurt = strong ? 1.25 : 1;
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

  @override
  void update(double dt) {
    _hurt = math.max(0, _hurt - dt / 0.6);
    if (_muzzleT < 1) _muzzleT = math.min(1, _muzzleT + dt / 0.14);
    if (_shieldT < 1) _shieldT = math.min(1, _shieldT + dt / 0.75);
    if (_healT < 1) _healT = math.min(1, _healT + dt / 0.9);
    if (_dodgeT < 1) _dodgeT = math.min(1, _dodgeT + dt / 0.5);
  }

  @override
  void render(Canvas canvas) {
    if (_size.isEmpty) return;
    final g = game;
    final t = g.time;

    // Baliza de emergencia: destellos cortos; más rápida si el Bruto carga.
    final period = g.charging ? 0.55 : 1.7;
    final phase = (t / period) % 1.0;
    final beacon = math.pow(math.max(0.0, math.sin(phase * math.pi * 2)), 6).toDouble();
    final base = g.charging ? 0.10 : 0.045;
    final em = (base + beacon * (g.charging ? 0.26 : 0.13)).clamp(0.0, 1.0);
    _emergency.color = Color.fromARGB((em * 255).round(), 255, 255, 255);
    canvas.drawRect(_full, _emergency);

    // Gradación cinematográfica + escaneo.
    canvas.drawRect(_full, _grade);
    canvas.drawRect(_full, _scan);

    // Salud baja: viñeta roja que late.
    if (g.healthRatio < 0.3 && g.downProgress <= 0) {
      final beat = 0.5 + 0.5 * math.sin(t * math.pi * 2 * 1.15);
      final k = (0.3 - g.healthRatio) / 0.3;
      _edge.colorFilter = const ColorFilter.mode(Color(0xFFB0121C), BlendMode.modulate);
      _edge.color = Color.fromARGB(((0.35 + 0.35 * k) * (0.55 + 0.45 * beat) * 255).round().clamp(0, 255), 255, 255, 255);
      canvas.drawRect(_full, _edge);
    }
    // Golpe recibido.
    if (_hurt > 0) {
      _edge.colorFilter = ColorFilter.mode(_hurtToxic ? const Color(0xFF7A3FD0) : const Color(0xFFE0202C), BlendMode.modulate);
      _edge.color = Color.fromARGB((math.min(1.0, _hurt) * 230).round(), 255, 255, 255);
      canvas.drawRect(_full, _edge);
    }
    // Curación.
    if (_healT < 1) {
      _edge.colorFilter = const ColorFilter.mode(Color(0xFF74C044), BlendMode.modulate);
      _edge.color = Color.fromARGB(((1 - _healT) * 150).round(), 255, 255, 255);
      canvas.drawRect(_full, _edge);
    }
    // Esquiva perfecta (embestida): destello cian.
    if (_dodgeT < 1) {
      _edge.colorFilter = const ColorFilter.mode(Color(0xFF6ADBEA), BlendMode.modulate);
      _edge.color = Color.fromARGB(((1 - _dodgeT) * 170).round(), 255, 255, 255);
      canvas.drawRect(_full, _edge);
    }
    // Escudo: panal de hexágonos que se desvanece.
    final hexes = _hexes;
    if (_shieldT < 1 && hexes != null) {
      final a = math.sin(_shieldT * math.pi);
      _hex.color = Sutura.signal.withValues(alpha: 0.55 * a);
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
      canvas.drawImageRect(atlas, FxAtlas.blob, Rect.fromCircle(center: _muzzleFrom, radius: r), _muzzle);
      canvas.drawImageRect(atlas, FxAtlas.dot, Rect.fromCircle(center: _muzzleFrom, radius: r * 0.35), _muzzle);
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
// Retícula
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
    ..strokeWidth = 1.3
    ..strokeCap = StrokeCap.square;
  final Paint _arc = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2;
  final Paint _finger = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final Map<String, TextPainter> _labels = {};

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
            letterSpacing: 1.4,
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
      col = Sutura.textMid;
    } else if (onHead && locked) {
      col = const Color(0xFFF4FDFF);
    } else {
      col = Sutura.signal;
    }

    // Marco del objetivo (cuerpo) y de la cabeza.
    final appear = math.min(1.0, aim.ms / 160);
    _bracket.color = Sutura.signal.withValues(alpha: 0.32 * appear);
    _corners(canvas, body.inflate(6), 14, _bracket);
    if (onHead) {
      _bracket.color = (locked ? const Color(0xFFF4FDFF) : Sutura.signal).withValues(alpha: 0.85);
      _corners(canvas, head.inflate(4), 7, _bracket);
    }

    // Guía hasta el dedo.
    _finger.color = col.withValues(alpha: 0.22);
    canvas.drawLine(p.translate(0, r + 12), aim.finger.translate(0, -18), _finger);
    canvas.drawCircle(aim.finger, 16, _finger);

    // Anillo.
    _glow.color = col.withValues(alpha: locked ? 0.35 : 0.18);
    canvas.drawCircle(p, r, _glow);
    _ring
      ..color = col.withValues(alpha: 0.95)
      ..strokeWidth = aim.charged ? 2.2 : 1.4;
    canvas.drawCircle(p, r, _ring);
    // Marcas exteriores.
    _tick.color = col;
    final tk = locked ? 7.0 : 10.0;
    canvas.drawLine(p.translate(-r - 3 - tk, 0), p.translate(-r - 3, 0), _tick);
    canvas.drawLine(p.translate(r + 3, 0), p.translate(r + 3 + tk, 0), _tick);
    canvas.drawLine(p.translate(0, -r - 3 - tk), p.translate(0, -r - 3), _tick);
    canvas.drawLine(p.translate(0, r + 3), p.translate(0, r + 3 + tk), _tick);
    // Arcos de escaneo que giran.
    _arc.color = col.withValues(alpha: 0.6);
    final rot = g.time * (aim.charged ? 5 : 2.4);
    final arcRect = Rect.fromCircle(center: p, radius: r + 7);
    canvas.drawArc(arcRect, rot, 0.6, false, _arc);
    canvas.drawArc(arcRect, rot + math.pi, 0.6, false, _arc);
    // Centro.
    _dot.color = col;
    canvas.drawCircle(p, locked ? 2.4 : 1.6, _dot);

    // Lectura: zona + precisión.
    final pct = (tight * 100).round();
    final zoneText = switch (zone) {
      AimZone.head => 'CABEZA',
      AimZone.body => 'TORSO',
      AimZone.off => 'SIN BLANCO',
    };
    final l1 = _label(zoneText, col, 10);
    final l2 = _label('${pct.toString().padLeft(2, '0')}%', col.withValues(alpha: 0.85), 10);
    final y = p.dy + r + 16;
    l1.paint(canvas, Offset(p.dx - (l1.width + 8 + l2.width) / 2, y));
    l2.paint(canvas, Offset(p.dx - (l1.width + 8 + l2.width) / 2 + l1.width + 8, y));
    if (aim.charged) {
      final l = _label('CARGADO', Sutura.amber, 11);
      l.paint(canvas, Offset(p.dx - l.width / 2, p.dy - r - 30));
    } else if (onHead && locked) {
      final l = _label(g.aimStyle == AimStyle.firearm ? 'TIRO LIMPIO' : 'GOLPE LIMPIO', const Color(0xFFF4FDFF), 10);
      l.paint(canvas, Offset(p.dx - l.width / 2, p.dy - r - 28));
    }
  }
}
