// Capa de la mano en primera persona: encima de la criatura y debajo del HUD.
// Carga el recorte del arma activa a demanda (si falta usa el de reserva o no
// dibuja nada), aplica la pose de [HandRig] alrededor de la muñeca, estira los
// bordes cortados del brazo (para que al girar nunca se vea el corte) y dibuja
// el fogonazo en la boca del cañón, el trazo de la bala y el humo.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'combat_art.dart' show FxAtlas;
import 'creature_view.dart' show PlateLook;
import 'fp_hand.dart';
import 'fx_pool.dart';

/// Lo que la escena le ofrece a la mano.
abstract interface class HandStage {
  /// Tamaño de la vista (dp).
  Size get viewSize;

  /// y del borde superior de la botonera: la mano entra por debajo.
  double get handBase;
  PlateLook get look;
  double get beacon;
  ui.Image? get fxAtlas;
}

class HandLayer extends Component {
  HandLayer(this.stage, {HandKind initial = HandKind.pistol, AssetBundle? bundle})
    : _requested = initial,
      _bundle = bundle ?? rootBundle,
      rig = HandRig(initial) {
    rig.lowerK = 1; // entra subiendo
    _ensure(initial);
  }

  final HandStage stage;
  final AssetBundle _bundle;
  final HandRig rig;
  HandKind _requested;
  bool _shown = false;

  final Map<HandKind, ui.Image> _images = {};
  final Set<HandKind> _missing = {};
  final Set<HandKind> _loading = {};
  bool _disposed = false;

  final HandPose _pose = HandPose();
  double _restRot = 0;
  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;
  final Paint _add = Paint()
    ..filterQuality = FilterQuality.low
    ..blendMode = BlendMode.plus;
  final Paint _flash = Paint()..blendMode = BlendMode.plus;
  final Paint _tracer = Paint()
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;
  final FxPool _smoke = FxPool(16);
  final math.Random _rnd = math.Random(23);

  // Fogonazo/trazo del último disparo.
  Offset _tracerTo = Offset.zero;
  double _tracerT = 1;
  Offset _muzzleAt = Offset.zero;
  Offset _muzzleDir = const Offset(-1, 0);
  int _shots = 0;

  /// Recorte pedido (puede estar mostrándose otro mientras carga).
  HandKind get requested => _requested;

  /// Recorte en pantalla (null si todavía no hay ninguno cargado).
  HandKind? get shown => _shown ? rig.kind : null;

  /// Boca del cañón en pantalla en la pose actual (null sin arma de fuego).
  Offset? get muzzlePoint => _shown && rig.kind.firearm ? _muzzleAt : null;

  /// Cambia el arma que se ve.
  void request(HandKind kind) {
    _requested = kind;
    _ensure(kind);
  }

  void shoot(Offset target) {
    rig.shoot();
    _tracerTo = target;
    _tracerT = 0;
    _shots++;
    _puffs = 6;
  }

  int _puffs = 0;

  void swing(Offset target, {bool heavy = false}) {
    final v = stage.viewSize;
    final base = handRect(handSpecs[rig.kind]!, v, stage.handBase);
    final spec = handSpecs[rig.kind]!;
    // Desde el pivote de la mano que golpea (en puños, alternan) hacia el blanco.
    final side = rig.kind == HandKind.fists ? -rig.punchSide : 0;
    final pv = side < 0 || !spec.split ? spec.pivot : spec.pivotRight;
    final wrist = Offset(base.left + pv.dx * base.width, base.top + pv.dy * base.height);
    final d = (target - wrist) / math.max(1.0, v.width);
    rig.swing(d, heavy: heavy);
  }

  @override
  void onRemove() {
    _disposed = true;
    for (final img in _images.values) {
      img.dispose();
    }
    _images.clear();
    super.onRemove();
  }

  void _ensure(HandKind kind) {
    HandKind? k = kind;
    while (k != null) {
      if (!_images.containsKey(k) && !_missing.contains(k) && !_loading.contains(k)) {
        _load(k);
        return;
      }
      if (_images.containsKey(k) || _loading.contains(k)) return;
      k = k.fallback;
    }
  }

  Future<void> _load(HandKind k) async {
    _loading.add(k);
    try {
      final data = await _bundle.load(k.asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (_disposed) {
        frame.image.dispose();
        return;
      }
      _images[k] = frame.image;
    } catch (e) {
      debugPrint('[combate] sin recorte de mano ${k.asset}: $e');
      _missing.add(k);
      if (k.fallback != null) _ensure(k.fallback!);
    } finally {
      _loading.remove(k);
    }
  }

  /// El recorte disponible para `k` (o su reserva); null si todavía carga.
  HandKind? _resolve(HandKind k) {
    HandKind? c = k;
    while (c != null) {
      if (_images.containsKey(c)) return c;
      if (!_missing.contains(c)) return null;
      c = c.fallback;
    }
    return null;
  }

  @override
  void update(double dt) {
    final want = _resolve(_requested);
    if (want != null) {
      if (!_shown) {
        rig.snap(want);
        _shown = true;
      } else if (want != rig.kind) {
        rig.swap(want);
      }
    }
    rig.update(dt);
    if (_tracerT < 1) _tracerT = math.min(1, _tracerT + dt / 0.12);
    if (_puffs > 0 && rig.flash < 0.6) {
      for (; _puffs > 0; _puffs--) {
        _smoke.spawn(
          x: _muzzleAt.dx + _rnd.nextDouble() * 8 - 4,
          y: _muzzleAt.dy + _rnd.nextDouble() * 8 - 4,
          vx: _muzzleDir.dx * (30 + _rnd.nextDouble() * 50) + _rnd.nextDouble() * 20 - 10,
          vy: _muzzleDir.dy * (30 + _rnd.nextDouble() * 50) - 20 - _rnd.nextDouble() * 30,
          life: 0.9 + _rnd.nextDouble() * 0.8,
          size: 22 + _rnd.nextDouble() * 26,
          src: FxAtlas.blob,
          color: Color.fromARGB(34 + _rnd.nextInt(26), 150, 156, 160),
          grow: 1.4,
          drag: 1.6,
          fadeIn: 0.05,
        );
      }
    }
    _smoke.update(dt);
  }

  @override
  void render(Canvas canvas) {
    if (!_shown) return;
    final img = _images[rig.kind];
    if (img == null) return;
    final spec = handSpecs[rig.kind]!;
    final v = stage.viewSize;
    if (v.isEmpty) return;
    final r = handRect(spec, v, stage.handBase);
    final look = stage.look;
    final beacon = look.emergency ? stage.beacon : 0.0;
    final flash = rig.flash;
    // La mano está más cerca que la criatura: un punto más clara, pero
    // del mismo tono que la placa.
    _paint.colorFilter = ColorFilter.mode(Color.lerp(look.lightTint, const Color(0xFFFFFFFF), 0.25)!, BlendMode.modulate);

    final iw = img.width.toDouble(), ih = img.height.toDouble();
    _restRot = spec.restRot;
    final parts = spec.split ? const [-1, 1] : const [0];
    final speed = rig.swingSpeed;
    for (final side in parts) {
      final src = side == 0
          ? Rect.fromLTWH(0, 0, iw, ih)
          : (side < 0 ? Rect.fromLTWH(0, 0, iw / 2, ih) : Rect.fromLTWH(iw / 2, 0, iw / 2, ih));
      final dst = side == 0
          ? Rect.fromLTWH(r.left, r.top, r.width, r.height)
          : (side < 0 ? Rect.fromLTWH(r.left, r.top, r.width / 2, r.height) : Rect.fromLTWH(r.left + r.width / 2, r.top, r.width / 2, r.height));
      final pv = side > 0 ? spec.pivotRight : spec.pivot;
      final pivot = Offset(r.left + pv.dx * r.width, r.top + pv.dy * r.height);

      // Rastro del golpe (poses de un instante antes, tenues).
      if (speed > 0.05 && (side == 0 || side == rig.punchSide)) {
        for (final (k, a) in const [(1, 0.32), (2, 0.16)]) {
          rig.evaluate(_pose, side: side, back: 0.028 * k);
          _add.colorFilter = null;
          canvas.save();
          _transform(canvas, pivot, v.width);
          _paint.color = Color.fromARGB((a * speed * 255).round(), 255, 255, 255);
          canvas.drawImageRect(img, src, dst, _paint);
          canvas.restore();
        }
        _paint.color = const Color(0xFFFFFFFF);
      }

      rig.evaluate(_pose, side: side);
      canvas.save();
      _transform(canvas, pivot, v.width);
      _edges(canvas, img, src, dst, spec, side);
      canvas.drawImageRect(img, src, dst, _paint);
      // Baliza roja desde la derecha (las manos ya traen luz de borde).
      if (beacon > 0.05) {
        _add.colorFilter = ColorFilter.mode(look.rim, BlendMode.modulate);
        _add.color = Color.fromARGB((beacon * 0.35 * 255).round(), 255, 255, 255);
        canvas.drawImageRect(img, src, dst, _add);
      }
      // Fogonazo que ilumina la mano.
      if (flash > 0) {
        _add.colorFilter = const ColorFilter.mode(Color(0xFFFFC27A), BlendMode.modulate);
        _add.color = Color.fromARGB((flash * 0.85 * 255).round(), 255, 255, 255);
        canvas.drawImageRect(img, src, dst, _add);
      }
      canvas.restore();

      // Boca del cañón en pantalla.
      final mu = spec.muzzle;
      if (mu != null && side == 0) {
        final m = Offset(r.left + mu.dx * r.width, r.top + mu.dy * r.height);
        _muzzleAt = _apply(m, pivot, v.width);
        final c = math.cos(_pose.rot + _restRot), s = math.sin(_pose.rot + _restRot);
        final d = spec.muzzleDir;
        _muzzleDir = Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
      }
    }

    final atlas = stage.fxAtlas;
    if (atlas != null) {
      _smoke.render(canvas, atlas);
      if (rig.kind.firearm) _renderShot(canvas, atlas, v.width, flash);
    }
  }

  /// Muñeca + pose: traslada, gira y escala alrededor del pivote.
  void _transform(Canvas canvas, Offset pivot, double w) {
    canvas.translate(pivot.dx + _pose.dx * w, pivot.dy + _pose.dy * w);
    final rot = _pose.rot + _restRot;
    if (rot != 0) canvas.rotate(rot);
    if (_pose.scale != 1) canvas.scale(_pose.scale);
    canvas.translate(-pivot.dx, -pivot.dy);
  }

  Offset _apply(Offset p, Offset pivot, double w) {
    final c = math.cos(_pose.rot + _restRot), s = math.sin(_pose.rot + _restRot);
    final x = (p.dx - pivot.dx) * _pose.scale, y = (p.dy - pivot.dy) * _pose.scale;
    return Offset(pivot.dx + _pose.dx * w + x * c - y * s, pivot.dy + _pose.dy * w + x * s + y * c);
  }

  /// Estira la última fila/columna del recorte hacia afuera: el brazo sigue
  /// más allá del borde aunque la mano gire o suba.
  void _edges(Canvas canvas, ui.Image img, Rect src, Rect dst, HandSpec spec, int side) {
    const ext = 700.0;
    final kx = dst.width / src.width, ky = dst.height / src.height;
    canvas.drawImageRect(img, Rect.fromLTWH(src.left, src.bottom - 2, src.width, 2), Rect.fromLTWH(dst.left, dst.bottom - 2 * ky, dst.width, ext), _paint);
    if (side >= 0) {
      canvas.drawImageRect(img, Rect.fromLTWH(src.right - 2, src.top, 2, src.height), Rect.fromLTWH(dst.right - 2 * kx, dst.top, ext, dst.height), _paint);
      canvas.drawImageRect(img, Rect.fromLTWH(src.right - 2, src.bottom - 2, 2, 2), Rect.fromLTWH(dst.right - 2 * kx, dst.bottom - 2 * ky, ext, ext), _paint);
    }
    if (spec.extendLeft && side <= 0) {
      canvas.drawImageRect(img, Rect.fromLTWH(src.left, src.top, 2, src.height), Rect.fromLTWH(dst.left - ext, dst.top, ext + 2 * kx, dst.height), _paint);
      canvas.drawImageRect(img, Rect.fromLTWH(src.left, src.bottom - 2, 2, 2), Rect.fromLTWH(dst.left - ext, dst.bottom - 2 * ky, ext + 2 * kx, ext), _paint);
    }
  }

  static final Float32List _starAngles = Float32List.fromList(const [0, 0.55, -0.6, 1.9, -2.0, math.pi]);

  void _renderShot(Canvas canvas, ui.Image atlas, double w, double flash) {
    final at = _muzzleAt;
    // Trazo de la bala hacia el blanco.
    if (_tracerT < 1) {
      final a = 1 - _tracerT;
      _tracer
        ..strokeWidth = 2.6 * a + 0.6
        ..color = Color.fromARGB((a * 210).round(), 255, 232, 190);
      final from = Offset.lerp(at, _tracerTo, math.max(0, _tracerT * 2 - 0.6))!;
      canvas.drawLine(from, Offset.lerp(at, _tracerTo, math.min(1, _tracerT * 3 + 0.25))!, _tracer);
    }
    if (flash <= 0) return;
    final heavy = rig.kind == HandKind.shotgun ? 1.35 : 1.0;
    final big = w * 0.2 * heavy * (0.85 + 0.3 * flash);
    _flash
      ..colorFilter = const ColorFilter.mode(Color(0xFFFFB262), BlendMode.modulate)
      ..color = Color.fromARGB((flash * 255).round(), 255, 255, 255);
    canvas.drawImageRect(atlas, FxAtlas.blob, Rect.fromCircle(center: at, radius: big), _flash);
    _flash.colorFilter = const ColorFilter.mode(Color(0xFFFFF0C8), BlendMode.modulate);
    canvas.drawImageRect(atlas, FxAtlas.dot, Rect.fromCircle(center: at, radius: big * 0.32), _flash);
    // Estrella: rayos a lo largo del cañón y de costado (cambia en cada tiro).
    final base = math.atan2(_muzzleDir.dy, _muzzleDir.dx);
    final jitter = (_shots * 0.7) % 1.0;
    for (var i = 0; i < _starAngles.length; i++) {
      final ang = base + _starAngles[i] + (jitter - 0.5) * 0.3;
      final len = (i == 0 ? 0.26 : (i == _starAngles.length - 1 ? 0.06 : 0.12 + 0.05 * ((i * 37 + _shots * 13) % 7) / 7)) * w * heavy;
      canvas.save();
      canvas.translate(at.dx, at.dy);
      // El sprite es transparente a la izquierda y brillante a la derecha:
      // girado media vuelta, el brillo queda en la boca y se apaga hacia afuera.
      canvas.rotate(ang + math.pi);
      canvas.drawImageRect(atlas, FxAtlas.streak, Rect.fromLTWH(-len, -len * 0.09, len * 1.12, len * 0.18), _flash);
      canvas.restore();
    }
  }
}
