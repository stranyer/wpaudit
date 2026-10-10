// Partículas con memoria preasignada: todo el estado vive en listas tipadas y
// se dibuja en un solo `drawRawAtlas` por grupo. Sin asignaciones por cuadro.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

class FxPool {
  FxPool(this.capacity, {BlendMode blend = BlendMode.srcOver})
    : _x = Float32List(capacity),
      _y = Float32List(capacity),
      _vx = Float32List(capacity),
      _vy = Float32List(capacity),
      _age = Float32List(capacity),
      _life = Float32List(capacity),
      _size = Float32List(capacity),
      _grow = Float32List(capacity),
      _rot = Float32List(capacity),
      _spin = Float32List(capacity),
      _drag = Float32List(capacity),
      _grav = Float32List(capacity),
      _fadeIn = Float32List(capacity),
      _align = Uint8List(capacity),
      _srcW = Float32List(capacity),
      _srcH = Float32List(capacity),
      _rgb = Int32List(capacity),
      _alpha = Float32List(capacity),
      _xf = Float32List(capacity * 4),
      _rects = Float32List(capacity * 4),
      _colors = Int32List(capacity),
      _paint = Paint()
        ..blendMode = blend
        ..filterQuality = FilterQuality.low {
    for (var i = 0; i < capacity; i++) {
      _life[i] = 0;
      _age[i] = 1;
      _xf[i * 4 + 2] = -9999;
      _xf[i * 4 + 3] = -9999;
    }
  }

  final int capacity;
  final Float32List _x, _y, _vx, _vy, _age, _life, _size, _grow, _rot, _spin, _drag, _grav, _fadeIn;
  final Uint8List _align;
  final Float32List _srcW, _srcH;
  final Int32List _rgb;
  final Float32List _alpha;
  final Float32List _xf;
  final Float32List _rects;
  final Int32List _colors;
  final Paint _paint;
  int _cursor = 0;
  int _alive = 0;

  bool get isEmpty => _alive == 0;

  /// Agrega una partícula (pisa la más vieja si el grupo está lleno).
  void spawn({
    required double x,
    required double y,
    double vx = 0,
    double vy = 0,
    required double life,
    required double size,
    required Rect src,
    required Color color,
    double grow = 0,
    double rot = 0,
    double spin = 0,
    double drag = 0,
    double gravity = 0,
    double fadeIn = 0,
    bool alignToVelocity = false,
  }) {
    final i = _cursor;
    _cursor = (_cursor + 1) % capacity;
    if (_age[i] >= _life[i]) _alive++;
    _x[i] = x;
    _y[i] = y;
    _vx[i] = vx;
    _vy[i] = vy;
    _age[i] = 0;
    _life[i] = life;
    _size[i] = size;
    _grow[i] = grow;
    _rot[i] = rot;
    _spin[i] = spin;
    _drag[i] = drag;
    _grav[i] = gravity;
    _fadeIn[i] = fadeIn;
    _align[i] = alignToVelocity ? 1 : 0;
    _srcW[i] = src.width;
    _srcH[i] = src.height;
    _rgb[i] = color.toARGB32() & 0x00FFFFFF;
    _alpha[i] = color.a;
    final r = i * 4;
    _rects[r] = src.left;
    _rects[r + 1] = src.top;
    _rects[r + 2] = src.right;
    _rects[r + 3] = src.bottom;
  }

  void update(double dt) {
    if (_alive == 0) return;
    var alive = 0;
    for (var i = 0; i < capacity; i++) {
      if (_age[i] >= _life[i]) continue;
      _age[i] += dt;
      if (_age[i] >= _life[i]) continue;
      alive++;
      final d = _drag[i];
      if (d > 0) {
        final k = math.max(0.0, 1 - d * dt);
        _vx[i] *= k;
        _vy[i] *= k;
      }
      _vy[i] += _grav[i] * dt;
      _x[i] += _vx[i] * dt;
      _y[i] += _vy[i] * dt;
      _rot[i] += _spin[i] * dt;
    }
    _alive = alive;
  }

  void render(Canvas canvas, ui.Image atlas) {
    if (_alive == 0) return;
    for (var i = 0; i < capacity; i++) {
      final o = i * 4;
      final age = _age[i];
      final life = _life[i];
      if (age >= life) {
        _xf[o] = 0;
        _xf[o + 1] = 0;
        _xf[o + 2] = -9999;
        _xf[o + 3] = -9999;
        _colors[i] = 0;
        continue;
      }
      final p = age / life;
      final fi = _fadeIn[i];
      final fade = (fi > 0 && p < fi ? p / fi : 1.0) * (1 - p) * (1 - p * 0.3);
      final a = (_alpha[i] * fade * 255).round().clamp(0, 255);
      _colors[i] = (a << 24) | _rgb[i];
      final sw = _srcW[i];
      final sh = _srcH[i];
      final scale = _size[i] * (1 + _grow[i] * age) / sw;
      final rot = _align[i] == 1 ? math.atan2(_vy[i], _vx[i]) : _rot[i];
      final sc = scale * math.cos(rot);
      final ss = scale * math.sin(rot);
      final ax = sw / 2;
      final ay = sh / 2;
      _xf[o] = sc;
      _xf[o + 1] = ss;
      _xf[o + 2] = _x[i] - sc * ax + ss * ay;
      _xf[o + 3] = _y[i] - ss * ax - sc * ay;
    }
    canvas.drawRawAtlas(atlas, _xf, _rects, _colors, BlendMode.modulate, null, _paint);
  }

  void clear() {
    for (var i = 0; i < capacity; i++) {
      _age[i] = 1;
      _life[i] = 0;
    }
    _alive = 0;
  }
}
