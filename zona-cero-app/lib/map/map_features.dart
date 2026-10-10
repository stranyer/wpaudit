import 'dart:math' as math;

import '../core/core.dart';
import 'contour.dart';

/// Constructores de GeoJSON para los overlays del mapa. Funciones puras
/// (sin Flutter ni maplibre) para poder probarlas y reutilizarlas.

typedef Json = Map<String, dynamic>;

Json featureCollection(List<Json> features) => {'type': 'FeatureCollection', 'features': features};

Json emptyCollection() => featureCollection(const []);

List<double> lngLat(LatLng p) => [p.lng, p.lat];

Json pointFeature(LatLng p, Json props, {String? id}) => {
      'type': 'Feature',
      'id': ?id,
      'properties': props,
      'geometry': {'type': 'Point', 'coordinates': lngLat(p)},
    };

Json lineFeature(List<LatLng> pts, Json props) => {
      'type': 'Feature',
      'properties': props,
      'geometry': {
        'type': 'LineString',
        'coordinates': [for (final p in pts) lngLat(p)],
      },
    };

/// Polígono: [anillo exterior, ...agujeros]; cada anillo se cierra solo.
Json polygonFeature(List<List<LatLng>> rings, Json props) => {
      'type': 'Feature',
      'properties': props,
      'geometry': {'type': 'Polygon', 'coordinates': [for (final r in rings) _closedRing(r)]},
    };

Json multiPolygonFeature(List<List<List<LatLng>>> polygons, Json props) => {
      'type': 'Feature',
      'properties': props,
      'geometry': {
        'type': 'MultiPolygon',
        'coordinates': [
          for (final poly in polygons) [for (final r in poly) _closedRing(r)],
        ],
      },
    };

List<List<double>> _closedRing(List<LatLng> r) => [
      for (final p in r) lngLat(p),
      if (r.isNotEmpty && r.first != r.last) lngLat(r.first),
    ];

/// Anillo aproximando un círculo de `radiusM` metros.
List<LatLng> circleRing(LatLng center, double radiusM, {int steps = 72}) => [
      for (var i = 0; i < steps; i++)
        offsetM(center, math.cos(i / steps * 2 * math.pi) * radiusM, math.sin(i / steps * 2 * math.pi) * radiusM),
    ];

Json circleCollection(LatLng center, double radiusM) =>
    featureCollection([polygonFeature([circleRing(center, radiusM)], const {})]);

// ---------------------------------------------------------------------------
// Grilla de 100 m
// ---------------------------------------------------------------------------

/// Líneas cada `stepM` metros alrededor de la celda del jugador, ancladas a la
/// esquina SO de la celda (se regeneran al cambiar de celda).
Json gridCollection(LatLng player, {double stepM = 100, double extentM = 1300}) {
  final cell = cellOf(player);
  final anchor = cellBounds(cell).sw;
  final c = toLocalXY(anchor, cellCenter(cell));
  final feats = <Json>[];
  final k0 = ((c.y - extentM) / stepM).floor();
  final k1 = ((c.y + extentM) / stepM).ceil();
  for (var k = k0; k <= k1; k++) {
    final y = k * stepM;
    feats.add(lineFeature(
      [fromLocalXY(anchor, XY(c.x - extentM, y)), fromLocalXY(anchor, XY(c.x + extentM, y))],
      {'major': k % 5 == 0},
    ));
  }
  final m0 = ((c.x - extentM) / stepM).floor();
  final m1 = ((c.x + extentM) / stepM).ceil();
  for (var m = m0; m <= m1; m++) {
    final x = m * stepM;
    feats.add(lineFeature(
      [fromLocalXY(anchor, XY(x, c.y - extentM)), fromLocalXY(anchor, XY(x, c.y + extentM))],
      {'major': m % 5 == 0},
    ));
  }
  return featureCollection(feats);
}

// ---------------------------------------------------------------------------
// Contagio: curvas de nivel sobre las zonas infestadas
// ---------------------------------------------------------------------------

/// Niveles (metros de distancia con signo al borde del área infestada):
/// 0 = borde exterior, luego dos curvas internas cada vez más intensas.
const contagionLevels = [0.0, -30.0, -62.0];

/// Clave estable del conjunto de celdas infestadas (para no recalcular).
String contagionKey(List<Zone> zones) =>
    ([for (final z in zones) if (z.threat == ZoneThreat.infested) z.cellId]..sort()).join(',');

/// Campo escalar = distancia con signo a la unión suave de las celdas
/// infestadas (+ un ruido de baja frecuencia para que parezca terreno), y
/// tres isolíneas con marching squares. Devuelve una sola colección: líneas
/// (`k: 'line'`, `lvl: 0..2`) y el relleno del nivel exterior (`k: 'fill'`).
Json contagionCollection(List<Zone> zones, {double stepM = 10}) {
  final infested = [for (final z in zones) if (z.threat == ZoneThreat.infested) z];
  if (infested.isEmpty) return emptyCollection();

  var minLat = double.infinity, minLng = double.infinity;
  var maxLat = -double.infinity, maxLng = -double.infinity;
  for (final z in infested) {
    minLat = math.min(minLat, z.bounds.sw.lat);
    minLng = math.min(minLng, z.bounds.sw.lng);
    maxLat = math.max(maxLat, z.bounds.ne.lat);
    maxLng = math.max(maxLng, z.bounds.ne.lng);
  }
  const margin = 90.0;
  final origin = offsetM(LatLng(minLat, minLng), -margin, -margin);
  final ne = toLocalXY(origin, LatLng(maxLat, maxLng));
  final w = ((ne.x + margin) / stepM).ceil() + 1;
  final h = ((ne.y + margin) / stepM).ceil() + 1;

  // Rectángulos en metros (centro y semiejes).
  final rects = [
    for (final z in infested)
      () {
        final a = toLocalXY(origin, z.bounds.sw);
        final b = toLocalXY(origin, z.bounds.ne);
        return (cx: (a.x + b.x) / 2, cy: (a.y + b.y) / 2, bx: (b.x - a.x) / 2, by: (b.y - a.y) / 2);
      }(),
  ];

  // Origen absoluto para que el ruido sea estable entre regeneraciones.
  final ax = origin.lng * 111320 * math.cos(origin.lat * math.pi / 180);
  final ay = origin.lat * 110574;

  final values = List<double>.filled(w * h, 1e3);
  for (var j = 1; j < h - 1; j++) {
    final y = j * stepM;
    for (var i = 1; i < w - 1; i++) {
      final x = i * stepM;
      var d = double.infinity;
      for (final r in rects) {
        final sd = _rectSdf(x - r.cx, y - r.cy, r.bx, r.by);
        d = d == double.infinity ? sd : _smin(d, sd, 36);
      }
      values[j * w + i] = d + _noise(ax + x, ay + y) * 7;
    }
  }
  final grid = ScalarGrid(w, h, values);

  LatLng toLatLng(GridPoint p) => fromLocalXY(origin, XY(p.x * stepM, p.y * stepM));

  final lineFeats = <Json>[];
  var outerRings = <List<GridPoint>>[];
  for (final (lvl, level) in contagionLevels.indexed) {
    final lines = isoLines(grid, level);
    final rings = <List<GridPoint>>[];
    for (final l in lines) {
      if (l.points.length < 3) continue;
      final pts = l.closed ? chaikinClosed(l.points) : l.points;
      if (l.closed) rings.add(pts);
      final ll = [for (final p in pts) toLatLng(p)];
      if (l.closed) ll.add(ll.first);
      lineFeats.add(lineFeature(ll, {'k': 'line', 'lvl': lvl}));
    }
    if (lvl == 0) outerRings = rings;
  }

  final polys = ringsToPolygons(outerRings);
  return featureCollection([
    if (polys.isNotEmpty)
      multiPolygonFeature([
        for (final poly in polys) [for (final ring in poly) ring.map(toLatLng).toList()],
      ], const {'k': 'fill'}),
    ...lineFeats,
  ]);
}

/// Distancia con signo a un rectángulo centrado en el origen con semiejes (bx, by).
double _rectSdf(double px, double py, double bx, double by) {
  final qx = px.abs() - bx;
  final qy = py.abs() - by;
  final ox = math.max(qx, 0.0);
  final oy = math.max(qy, 0.0);
  final outside = math.sqrt(ox * ox + oy * oy);
  final inside = math.min(math.max(qx, qy), 0.0);
  return outside + inside;
}

/// Mínimo suave polinómico (une celdas vecinas sin inflar mucho el borde).
double _smin(double a, double b, double k) {
  final h = math.max(k - (a - b).abs(), 0.0) / k;
  return math.min(a, b) - h * h * k * 0.25;
}

/// Ruido determinístico de baja frecuencia en [-1, 1] (coordenadas en metros).
double _noise(double x, double y) =>
    0.55 * math.sin(x * 0.019 + 1.7 * math.sin(y * 0.011)) + 0.45 * math.sin(y * 0.023 + 1.3 * math.sin(x * 0.013 + 0.6));

// ---------------------------------------------------------------------------
// Celdas escaneadas (estado de "habitación" estilo survival horror)
// ---------------------------------------------------------------------------

/// `cells` = cellId -> 'loot' (quedan suministros revelados) | 'clear' (vacía).
Json cellsCollection(Map<String, String> cells) {
  final feats = <Json>[];
  for (final e in cells.entries) {
    final b = cellBounds(parseCellId(e.key));
    // Pequeño margen para que se lean como habitaciones separadas.
    final sw = offsetM(b.sw, 5, 5);
    final ne = offsetM(b.ne, -5, -5);
    feats.add(polygonFeature([
      [sw, LatLng(sw.lat, ne.lng), ne, LatLng(ne.lat, sw.lng)],
    ], {'st': e.value}));
  }
  return featureCollection(feats);
}

// ---------------------------------------------------------------------------
// Red de relevo (suturas entre nodos)
// ---------------------------------------------------------------------------

/// Une el nodo propio con los nodos a menos de `maxM` (trazo marcado) y cada
/// nodo ajeno con sus dos vecinos más cercanos dentro de `maxM` (trazo tenue).
Json suturesCollection(List<Shelter> shelters, String? ownId, {double maxM = 2500}) {
  final feats = <Json>[];
  final pairs = <String>{};
  String key(String a, String b) => a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
  Shelter? own;
  for (final s in shelters) {
    if (s.id == ownId) own = s;
  }
  if (own != null) {
    for (final s in shelters) {
      if (s.id == own.id || haversineM(own.position, s.position) > maxM) continue;
      pairs.add(key(own.id, s.id));
      feats.add(lineFeature([own.position, s.position], {'own': true}));
    }
  }
  for (final a in shelters) {
    if (a.id == ownId) continue;
    final near = [
      for (final b in shelters)
        if (b.id != a.id && b.id != ownId) (b, haversineM(a.position, b.position)),
    ]..sort((x, y) => x.$2.compareTo(y.$2));
    for (final (b, d) in near.take(2)) {
      if (d > maxM || !pairs.add(key(a.id, b.id))) continue;
      feats.add(lineFeature([a.position, b.position], {'own': false}));
    }
  }
  return featureCollection(feats);
}
