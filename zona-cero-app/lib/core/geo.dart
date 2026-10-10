// Utilidades geográficas puras. Para distancias cortas (< 5 km) usamos una
// proyección equirectangular local, suficientemente precisa y muy barata.

import 'dart:math' as math;

import 'types.dart';
import 'utils.dart';

const double earthRadiusM = 6371008.8;
const double _deg = math.pi / 180;

double haversineM(LatLng a, LatLng b) {
  final dLat = (b.lat - a.lat) * _deg;
  final dLng = (b.lng - a.lng) * _deg;
  final sLat = math.sin(dLat / 2);
  final sLng = math.sin(dLng / 2);
  // Mismo orden de operaciones que la versión web (`x ** 2` == `x * x`).
  final s = sLat * sLat + math.cos(a.lat * _deg) * math.cos(b.lat * _deg) * (sLng * sLng);
  return 2 * earthRadiusM * math.asin(math.min(1, math.sqrt(s)));
}

/// Desplaza un punto `northM` metros al norte y `eastM` metros al este.
LatLng offsetM(LatLng origin, num northM, num eastM) {
  final lat = origin.lat + (northM / earthRadiusM) / _deg;
  final lng = origin.lng + (eastM / (earthRadiusM * math.cos(origin.lat * _deg))) / _deg;
  return LatLng(lat, normalizeLng(lng));
}

/// Normaliza una longitud a [-180, 180). Usa `remainder` para reproducir el `%` de JS.
double normalizeLng(double lng) => ((((lng + 180).remainder(360)) + 360).remainder(360)) - 180;

/// Rumbo inicial de `a` hacia `b`, en grados (0 = norte, sentido horario).
double bearingDeg(LatLng a, LatLng b) {
  final y = math.sin((b.lng - a.lng) * _deg) * math.cos(b.lat * _deg);
  final x = math.cos(a.lat * _deg) * math.sin(b.lat * _deg) -
      math.sin(a.lat * _deg) * math.cos(b.lat * _deg) * math.cos((b.lng - a.lng) * _deg);
  return (math.atan2(y, x) / _deg + 360).remainder(360);
}

/// Punto en metros sobre un plano local (x = este, y = norte).
class XY {
  const XY(this.x, this.y);
  final double x;
  final double y;

  @override
  bool operator ==(Object other) => other is XY && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'XY($x, $y)';
}

/// Proyecta a metros relativos a `origin` (x = este, y = norte).
XY toLocalXY(LatLng origin, LatLng p) => XY(
      (p.lng - origin.lng) * _deg * earthRadiusM * math.cos(origin.lat * _deg),
      (p.lat - origin.lat) * _deg * earthRadiusM,
    );

LatLng fromLocalXY(LatLng origin, XY xy) => offsetM(origin, xy.y, xy.x);

// ---------------------------------------------------------------------------
// Grilla de celdas del mundo
// ---------------------------------------------------------------------------
// Grilla fija en grados: ~200 m x ~220 m en Buenos Aires. Es determinística, así
// que todos los clientes (y el servidor) calculan las mismas celdas.

const double cellLatDeg = 0.0018;
const double cellLngDeg = 0.0024;

class CellCoord {
  const CellCoord(this.cx, this.cy);
  final int cx;
  final int cy;

  /// Identificador de la celda (`"cx_cy"`).
  String get id => cellId(this);

  @override
  bool operator ==(Object other) => other is CellCoord && other.cx == cx && other.cy == cy;

  @override
  int get hashCode => Object.hash(cx, cy);

  @override
  String toString() => 'CellCoord($cx, $cy)';
}

CellCoord cellOf(LatLng p) => CellCoord((p.lng / cellLngDeg).floor(), (p.lat / cellLatDeg).floor());

String cellId(CellCoord c) => '${c.cx}_${c.cy}';

CellCoord parseCellId(String id) {
  final parts = id.split('_');
  return CellCoord(int.parse(parts[0]), int.parse(parts[1]));
}

CellBounds cellBounds(CellCoord c) => (
      sw: LatLng(c.cy * cellLatDeg, c.cx * cellLngDeg),
      ne: LatLng((c.cy + 1) * cellLatDeg, (c.cx + 1) * cellLngDeg),
    );

LatLng cellCenter(CellCoord c) => LatLng((c.cy + 0.5) * cellLatDeg, (c.cx + 0.5) * cellLngDeg);

/// Celdas en un cuadrado de (2r+1)² alrededor del punto.
List<CellCoord> cellsAround(LatLng p, int radiusCells) {
  final c = cellOf(p);
  return [
    for (var dy = -radiusCells; dy <= radiusCells; dy++)
      for (var dx = -radiusCells; dx <= radiusCells; dx++) CellCoord(c.cx + dx, c.cy + dy),
  ];
}

// ---------------------------------------------------------------------------
// Geometría para ubicar spawns sobre calles y evitar zonas excluidas
// ---------------------------------------------------------------------------

/// Segmento de calle/sendero (en TS: `[LatLng, LatLng]`).
typedef Segment = (LatLng, LatLng);

XY nearestPointOnSegment(XY p, XY a, XY b) {
  final abx = b.x - a.x;
  final aby = b.y - a.y;
  final len2 = abx * abx + aby * aby;
  if (len2 == 0) return XY(a.x, a.y);
  final t = math.max(0.0, math.min(1.0, ((p.x - a.x) * abx + (p.y - a.y) * aby) / len2));
  return XY(a.x + abx * t, a.y + aby * t);
}

class SnapResult {
  const SnapResult({required this.position, required this.distanceM});
  final LatLng position;
  final double distanceM;
}

/// Ajusta `point` al punto más cercano de `segments` si está a menos de `maxDistM`.
/// Devuelve null si no hay ninguna calle/sendero suficientemente cerca.
SnapResult? snapToSegments(LatLng point, List<Segment> segments, num maxDistM) {
  XY? best;
  var bestD2 = (maxDistM * maxDistM).toDouble();
  final origin = point;
  for (final (a, b) in segments) {
    final pa = toLocalXY(origin, a);
    final pb = toLocalXY(origin, b);
    // Descarte rápido por caja envolvente.
    if (math.min(pa.x, pb.x) > maxDistM ||
        math.max(pa.x, pb.x) < -maxDistM ||
        math.min(pa.y, pb.y) > maxDistM ||
        math.max(pa.y, pb.y) < -maxDistM) {
      continue;
    }
    final q = nearestPointOnSegment(const XY(0, 0), pa, pb);
    final d2 = q.x * q.x + q.y * q.y;
    if (d2 <= bestD2) {
      bestD2 = d2;
      best = q;
    }
  }
  if (best == null) return null;
  return SnapResult(position: fromLocalXY(origin, best), distanceM: math.sqrt(bestD2));
}

/// Test punto-en-polígono (ray casting) sobre un anillo de coordenadas.
bool pointInRing(LatLng p, List<LatLng> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i];
    final b = ring[j];
    final intersects =
        (a.lat > p.lat) != (b.lat > p.lat) && p.lng < ((b.lng - a.lng) * (p.lat - a.lat)) / (b.lat - a.lat) + a.lng;
    if (intersects) inside = !inside;
  }
  return inside;
}

/// Polígono con agujeros: [anillo exterior, ...agujeros].
bool pointInPolygon(LatLng p, List<List<LatLng>> rings) {
  if (rings.isEmpty || !pointInRing(p, rings[0])) return false;
  for (var i = 1; i < rings.length; i++) {
    if (pointInRing(p, rings[i])) return false;
  }
  return true;
}

String formatDistance(num m) {
  if (m < 1000) return '${jsRound(m)} m';
  return '${(m / 1000).toStringAsFixed(1).replaceFirst('.', ',')} km';
}
