// Análisis del recorte HD de la criatura a partir del canal alfa: caja opaca
// del cuerpo, zona de la cabeza (para el tiro a la cabeza y el pivote del
// cuello), punto de apoyo de los pies y centroide. Lógica pura sobre bytes
// RGBA (sin Flame ni widgets) para poder testearla.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import '../core/types.dart';

/// Pistas por criatura para encontrar la cabeza (fracciones de la caja opaca).
///
/// Por defecto se busca en la franja superior ([headBandTop]…[headBand]) de
/// toda la caja; la ventana horizontal ([headX0]…[headX1]) sirve para arte en
/// el que la cabeza está hundida entre otras masas (el Bruto, con los tumores
/// del lomo más altos que la cabeza).
class RigHints {
  const RigHints({this.headBandTop = 0, this.headBand = 0.16, this.headX0 = 0, this.headX1 = 1, this.coverage = 0.72});

  final double headBandTop;
  final double headBand;
  final double headX0;
  final double headX1;

  /// Una columna de la franja cuenta como cabeza si su cobertura opaca es al
  /// menos `coverage ×` la de la columna más cubierta (descarta hombros que
  /// asoman recién al final de la franja y mechones o manos sueltas).
  final double coverage;
}

const Map<ZombieTypeId, RigHints> rigHints = {
  ZombieTypeId.walker: RigHints(),
  // Agachado: la cara llega más abajo y los hombros suben pronto.
  ZombieTypeId.runner: RigHints(headBand: 0.19, coverage: 0.8),
  ZombieTypeId.bloater: RigHints(),
  ZombieTypeId.screamer: RigHints(),
  // Encorvado: la cabeza asoma a la derecha, debajo de los tumores.
  ZombieTypeId.brute: RigHints(headBandTop: 0.035, headBand: 0.235, headX0: 0.53, headX1: 0.76),
};

/// Geometría del recorte, en píxeles de la imagen.
class CutoutRig {
  const CutoutRig({required this.size, required this.body, required this.head, required this.feet, required this.centroidX});

  final Size size;

  /// Caja de los píxeles opacos.
  final Rect body;

  /// Zona de la cabeza (dentro de [body]).
  final Rect head;

  /// Punto de apoyo: x media de lo opaco en las filas de abajo, y = pie de la caja.
  final Offset feet;

  /// Centro de masa horizontal de la silueta (para centrarla en pantalla).
  final double centroidX;

  double get height => body.height;

  /// Pivote del cuello: centro inferior de la cabeza.
  Offset get neck => Offset(head.center.dx, head.bottom);
}

/// Analiza el alfa de un recorte RGBA8 de `width × height`.
///
/// Devuelve `null` si no hay píxeles con alfa ≥ [threshold].
CutoutRig? analyzeCutout(Uint8List rgba, int width, int height, {RigHints hints = const RigHints(), int threshold = 96}) {
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) return null;
  bool on(int x, int y) => rgba[(y * width + x) * 4 + 3] >= threshold;

  // Caja opaca y centroide (el centroide se submuestrea: es solo para centrar).
  var minX = width, minY = height, maxX = -1, maxY = -1;
  var sumX = 0.0;
  var count = 0;
  for (var y = 0; y < height; y++) {
    final row = y * width;
    var rowMin = -1, rowMax = -1;
    for (var x = 0; x < width; x++) {
      if (rgba[(row + x) * 4 + 3] >= threshold) {
        if (rowMin < 0) rowMin = x;
        rowMax = x;
        if ((x | y) & 1 == 0) {
          sumX += x;
          count++;
        }
      }
    }
    if (rowMin < 0) continue;
    if (rowMin < minX) minX = rowMin;
    if (rowMax > maxX) maxX = rowMax;
    if (minY > y) minY = y;
    maxY = y;
  }
  if (maxX < 0) return null;
  final body = Rect.fromLTRB(minX.toDouble(), minY.toDouble(), maxX + 1.0, maxY + 1.0);
  final centroid = count == 0 ? body.center.dx : sumX / count;

  // Pies: x media de lo opaco en el 4 % inferior.
  final footTop = math.max(minY, (maxY - body.height * 0.04).floor());
  var fx = 0.0;
  var fn = 0;
  for (var y = footTop; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      if (on(x, y)) {
        fx += x;
        fn++;
      }
    }
  }
  final feet = Offset(fn == 0 ? body.center.dx : fx / fn, body.bottom);

  final head = detectHeadZone(rgba, width, height, body, hints: hints, threshold: threshold);
  return CutoutRig(size: Size(width.toDouble(), height.toDouble()), body: body, head: head, feet: feet, centroidX: centroid);
}

/// Zona de la cabeza: franja superior de la caja opaca, angostada al tramo de
/// columnas opacas más ancho que la cubre casi entera.
Rect detectHeadZone(Uint8List rgba, int width, int height, Rect body, {RigHints hints = const RigHints(), int threshold = 96}) {
  final top = (body.top + body.height * hints.headBandTop).floor().clamp(0, height - 1);
  final bottom = (body.top + body.height * hints.headBand).ceil().clamp(top + 1, height);
  final x0 = (body.left + body.width * hints.headX0).floor().clamp(0, width - 1);
  final x1 = (body.left + body.width * hints.headX1).ceil().clamp(x0 + 1, width);
  final rows = bottom - top;
  final cov = Float64List(x1 - x0);
  var best = 0.0;
  for (var x = x0; x < x1; x++) {
    var n = 0;
    for (var y = top; y < bottom; y++) {
      if (rgba[(y * width + x) * 4 + 3] >= threshold) n++;
    }
    final c = n / rows;
    cov[x - x0] = c;
    if (c > best) best = c;
  }
  Rect fallback() {
    // Sin señal clara: franja superior centrada (como la zona de reserva de aim.dart).
    final w = body.width * 0.3;
    return Rect.fromLTWH(body.center.dx - w / 2, body.top, w, body.height * hints.headBand);
  }

  if (best <= 0.05) return fallback();
  final cut = best * hints.coverage;
  final gap = math.max(1, (body.width * 0.015).round());
  var runStart = -1, runEnd = -1, miss = 0;
  var bestStart = -1, bestEnd = -1;
  void close() {
    if (runStart >= 0 && runEnd - runStart > bestEnd - bestStart) {
      bestStart = runStart;
      bestEnd = runEnd;
    }
    runStart = -1;
    miss = 0;
  }

  for (var i = 0; i < cov.length; i++) {
    if (cov[i] >= cut) {
      if (runStart < 0) runStart = i;
      runEnd = i + 1;
      miss = 0;
    } else if (runStart >= 0 && ++miss > gap) {
      close();
    }
  }
  close();
  if (bestStart < 0) return fallback();
  final hx0 = x0 + bestStart;
  final hx1 = x0 + bestEnd;
  var headTop = top;
  search:
  for (var y = top; y < bottom; y++) {
    for (var x = hx0; x < hx1; x++) {
      if (rgba[(y * width + x) * 4 + 3] >= threshold) {
        headTop = y;
        break search;
      }
    }
  }
  return Rect.fromLTRB(hx0.toDouble(), headTop.toDouble(), hx1.toDouble(), bottom.toDouble());
}
