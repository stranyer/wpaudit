import 'dart:math' as math;

import '../core/core.dart';

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
  'geometry': {
    'type': 'Polygon',
    'coordinates': [for (final r in rings) _closedRing(r)],
  },
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

List<List<double>> _closedRing(List<LatLng> r) => [for (final p in r) lngLat(p), if (r.isNotEmpty && r.first != r.last) lngLat(r.first)];

/// Anillo aproximando un círculo de `radiusM` metros.
List<LatLng> circleRing(LatLng center, double radiusM, {int steps = 72}) => [
  for (var i = 0; i < steps; i++) offsetM(center, math.cos(i / steps * 2 * math.pi) * radiusM, math.sin(i / steps * 2 * math.pi) * radiusM),
];

Json circleCollection(LatLng center, double radiusM) => featureCollection([
  polygonFeature([circleRing(center, radiusM)], const {}),
]);

// ---------------------------------------------------------------------------
// Contagio: un punto por celda infestada (capa de calor = mancha roja difusa)
// ---------------------------------------------------------------------------

/// Clave estable del conjunto de celdas infestadas (para no reenviar lo mismo).
String contagionKey(List<Zone> zones) => ([
  for (final z in zones)
    if (z.threat == ZoneThreat.infested) z.cellId,
]..sort()).join(',');

/// Centros de las celdas infestadas a menos de `maxM` de `around` (si se da).
Json infestedHeatCollection(List<Zone> zones, {LatLng? around, double maxM = 2500}) {
  final feats = <Json>[];
  for (final z in zones) {
    if (z.threat != ZoneThreat.infested) continue;
    final c = cellCenter(parseCellId(z.cellId));
    if (around != null && haversineM(around, c) > maxM) continue;
    feats.add(pointFeature(c, const {}));
  }
  return featureCollection(feats);
}

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
    feats.add(
      polygonFeature(
        [
          [sw, LatLng(sw.lat, ne.lng), ne, LatLng(ne.lat, sw.lng)],
        ],
        {'st': e.value},
      ),
    );
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
