import 'dart:math' as math;

/// Campo escalar muestreado en una grilla regular (fila por fila, `y` hacia arriba).
class ScalarGrid {
  ScalarGrid(this.width, this.height, this.values) : assert(values.length == width * height);

  final int width;
  final int height;
  final List<double> values;

  double at(int i, int j) => values[j * width + i];
}

typedef GridPoint = math.Point<double>;

/// Línea de nivel en coordenadas de grilla (x = columna, y = fila).
class IsoLine {
  IsoLine(this.points, {required this.closed});
  final List<GridPoint> points;
  final bool closed;
}

/// Extrae las líneas de nivel `value == level` con marching squares.
/// "Adentro" es `value < level`. Los segmentos se encadenan en polilíneas
/// (cerradas cuando el contorno no toca el borde de la grilla).
List<IsoLine> isoLines(ScalarGrid g, double level) {
  final w = g.width;
  final h = g.height;
  if (w < 2 || h < 2) return const [];

  // Identificador de arista: horizontal (i,j)-(i+1,j) = 2k, vertical (i,j)-(i,j+1) = 2k+1.
  int hEdge(int i, int j) => (j * w + i) * 2;
  int vEdge(int i, int j) => (j * w + i) * 2 + 1;

  final edgePoint = <int, GridPoint>{};
  GridPoint pointOn(int edge) {
    final cached = edgePoint[edge];
    if (cached != null) return cached;
    final k = edge >> 1;
    final i = k % w;
    final j = k ~/ w;
    final va = g.at(i, j);
    final GridPoint p;
    if (edge.isEven) {
      final vb = g.at(i + 1, j);
      final t = _lerpT(va, vb, level);
      p = math.Point(i + t, j.toDouble());
    } else {
      final vb = g.at(i, j + 1);
      final t = _lerpT(va, vb, level);
      p = math.Point(i.toDouble(), j + t);
    }
    edgePoint[edge] = p;
    return p;
  }

  final segA = <int>[];
  final segB = <int>[];
  void seg(int a, int b) {
    segA.add(a);
    segB.add(b);
  }

  for (var j = 0; j < h - 1; j++) {
    for (var i = 0; i < w - 1; i++) {
      final bl = g.at(i, j);
      final br = g.at(i + 1, j);
      final tr = g.at(i + 1, j + 1);
      final tl = g.at(i, j + 1);
      final idx = (bl < level ? 1 : 0) | (br < level ? 2 : 0) | (tr < level ? 4 : 0) | (tl < level ? 8 : 0);
      if (idx == 0 || idx == 15) continue;
      final bottom = hEdge(i, j);
      final top = hEdge(i, j + 1);
      final left = vEdge(i, j);
      final right = vEdge(i + 1, j);
      switch (idx) {
        case 1 || 14:
          seg(left, bottom);
        case 2 || 13:
          seg(bottom, right);
        case 3 || 12:
          seg(left, right);
        case 4 || 11:
          seg(right, top);
        case 6 || 9:
          seg(bottom, top);
        case 7 || 8:
          seg(left, top);
        case 5:
          // Silla: bl y tr adentro.
          if ((bl + br + tr + tl) / 4 < level) {
            seg(bottom, right);
            seg(left, top);
          } else {
            seg(left, bottom);
            seg(right, top);
          }
        case 10:
          // Silla: br y tl adentro.
          if ((bl + br + tr + tl) / 4 < level) {
            seg(left, bottom);
            seg(right, top);
          } else {
            seg(bottom, right);
            seg(left, top);
          }
      }
    }
  }

  // Encadenar segmentos por aristas compartidas.
  final byEdge = <int, List<int>>{};
  for (var s = 0; s < segA.length; s++) {
    (byEdge[segA[s]] ??= []).add(s);
    (byEdge[segB[s]] ??= []).add(s);
  }
  final used = List<bool>.filled(segA.length, false);
  int? nextSeg(int edge) {
    final list = byEdge[edge];
    if (list == null) return null;
    for (final s in list) {
      if (!used[s]) return s;
    }
    return null;
  }

  final out = <IsoLine>[];
  for (var s0 = 0; s0 < segA.length; s0++) {
    if (used[s0]) continue;
    used[s0] = true;
    final chain = <int>[segA[s0], segB[s0]];
    var closed = false;
    // Hacia adelante.
    while (true) {
      final cur = chain.last;
      final s = nextSeg(cur);
      if (s == null) break;
      used[s] = true;
      final other = segA[s] == cur ? segB[s] : segA[s];
      if (other == chain.first) {
        closed = true;
        break;
      }
      chain.add(other);
    }
    // Hacia atrás (solo si quedó abierta).
    if (!closed) {
      while (true) {
        final cur = chain.first;
        final s = nextSeg(cur);
        if (s == null) break;
        used[s] = true;
        final other = segA[s] == cur ? segB[s] : segA[s];
        chain.insert(0, other);
      }
    }
    out.add(IsoLine([for (final e in chain) pointOn(e)], closed: closed));
  }
  return out;
}

double _lerpT(double a, double b, double level) {
  final d = b - a;
  if (d.abs() < 1e-12) return 0.5;
  return ((level - a) / d).clamp(0.0, 1.0);
}

/// Suavizado de Chaikin (una pasada) para anillos cerrados.
List<GridPoint> chaikinClosed(List<GridPoint> pts, {int iterations = 1}) {
  var cur = pts;
  for (var it = 0; it < iterations; it++) {
    if (cur.length < 3) return cur;
    final next = <GridPoint>[];
    for (var i = 0; i < cur.length; i++) {
      final a = cur[i];
      final b = cur[(i + 1) % cur.length];
      next
        ..add(math.Point(a.x * 0.75 + b.x * 0.25, a.y * 0.75 + b.y * 0.25))
        ..add(math.Point(a.x * 0.25 + b.x * 0.75, a.y * 0.25 + b.y * 0.75));
    }
    cur = next;
  }
  return cur;
}

bool pointInGridRing(GridPoint p, List<GridPoint> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i];
    final b = ring[j];
    if ((a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) inside = !inside;
  }
  return inside;
}

/// Agrupa anillos cerrados en polígonos con agujeros (por profundidad de anidamiento).
/// Devuelve listas `[exterior, ...agujeros]`.
List<List<List<GridPoint>>> ringsToPolygons(List<List<GridPoint>> rings) {
  final n = rings.length;
  final depth = List<int>.filled(n, 0);
  final parent = List<int>.filled(n, -1);
  for (var a = 0; a < n; a++) {
    final probe = rings[a].first;
    var bestArea = double.infinity;
    for (var b = 0; b < n; b++) {
      if (a == b) continue;
      if (pointInGridRing(probe, rings[b])) {
        depth[a]++;
        final area = _area(rings[b]).abs();
        if (area < bestArea) {
          bestArea = area;
          parent[a] = b;
        }
      }
    }
  }
  final polys = <int, List<List<GridPoint>>>{};
  for (var a = 0; a < n; a++) {
    if (depth[a].isEven) polys[a] = [rings[a]];
  }
  for (var a = 0; a < n; a++) {
    if (depth[a].isOdd && parent[a] >= 0) polys[parent[a]]?.add(rings[a]);
  }
  return polys.values.toList();
}

double _area(List<GridPoint> ring) {
  var s = 0.0;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    s += (ring[j].x - ring[i].x) * (ring[j].y + ring[i].y);
  }
  return s / 2;
}
