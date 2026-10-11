import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../core/core.dart';
import 'map_style.dart';

/// Extrae de los tiles vectoriales ya cargados las calles y senderos públicos
/// (para ubicar spawns) y las zonas a evitar (agua, militares, vías,
/// aeropuertos). Misma lógica que `placementFromMap.ts` de la web.
///
/// En web, `querySourceFeatures` sobre tiles vectoriales puede no devolver nada:
/// en ese caso se devuelve null y el mundo usa las posiciones crudas.

const _walkableClasses = ['minor', 'tertiary', 'secondary', 'primary', 'path', 'pedestrian'];
const _blockedSubclasses = {'corridor', 'platform', 'steps', 'bridleway'};
const _blockedAccess = {'no', 'private', 'customers', 'delivery'};
const _excludedLanduse = ['military', 'railway', 'industrial', 'quarry', 'landfill', 'cemetery', 'prison'];

/// `around`/`radiusM`: solo se conservan segmentos y polígonos cercanos, así
/// el ajuste (lineal en la cantidad de segmentos) sigue siendo barato.
Future<PlacementData?> queryPlacementData(ml.MapLibreMapController map, {required LatLng around, double radiusM = 1600}) async {
  final roads = await _query(map, 'transportation', [
    'match',
    ['get', 'class'],
    _walkableClasses,
    true,
    false,
  ]);
  if (roads.isEmpty) return null;

  final near = _Near(around, radiusM);
  final walkable = <Segment>[];
  final seen = <int>{};
  for (final f in roads) {
    final p = _props(f);
    if (!_walkableClasses.contains('${p['class']}')) continue;
    if (p['brunnel'] == 'tunnel' || p['indoor'] == 1 || p['indoor'] == true) continue;
    if (_blockedSubclasses.contains('${p['subclass']}')) continue;
    if (_blockedAccess.contains('${p['access']}') || p['foot'] == 'no') continue;
    final g = _geometry(f);
    if (g == null) continue;
    final lines = switch (g.type) {
      'LineString' => [g.coords],
      'MultiLineString' => g.coords as List,
      _ => const [],
    };
    for (final line in lines) {
      final pts = _points(line);
      for (var i = 1; i < pts.length; i++) {
        final a = pts[i - 1];
        final b = pts[i];
        if (!near.test(a) && !near.test(b)) continue;
        // Los features se repiten entre tiles: deduplicar segmentos.
        final k = Object.hash((a.lat * 1e6).round(), (a.lng * 1e6).round(), (b.lat * 1e6).round(), (b.lng * 1e6).round());
        if (!seen.add(k)) continue;
        walkable.add((a, b));
      }
    }
  }
  if (walkable.isEmpty) return null;

  final excluded = <List<List<LatLng>>>[];
  void addPolygons(List f) {
    for (final feat in f) {
      final g = _geometry(feat);
      if (g == null) continue;
      final polys = switch (g.type) {
        'Polygon' => [g.coords],
        'MultiPolygon' => g.coords as List,
        _ => const [],
      };
      for (final poly in polys) {
        final rings = [for (final r in poly as List) _points(r)];
        if (rings.isEmpty || rings.first.isEmpty) continue;
        if (!rings.first.any(near.test)) continue;
        excluded.add(rings);
      }
    }
  }

  final water = await _query(map, 'water', null);
  addPolygons([
    for (final f in water)
      if (_props(f)['brunnel'] != 'tunnel') f,
  ]);
  addPolygons(
    await _query(map, 'landuse', [
      'match',
      ['get', 'class'],
      _excludedLanduse,
      true,
      false,
    ]),
  );
  addPolygons(await _query(map, 'aeroway', null));
  return PlacementData(walkable: walkable, excluded: excluded);
}

/// El estilo todavía está cargando tiles (en web `querySourceFeatures` lo
/// rechaza): conviene reintentar en un momento.
class PlacementNotReady implements Exception {
  const PlacementNotReady();
}

Future<List> _query(ml.MapLibreMapController map, String layer, List<Object>? filter) async {
  try {
    return await map.querySourceFeatures(SuturaMapStyle.source, layer, filter);
  } catch (e) {
    if ('$e'.contains('STYLE_NOT_READY')) throw const PlacementNotReady();
    if (filter == null) {
      debugPrint('[Zona Cero] querySourceFeatures($layer) falló: $e');
      return const [];
    }
    // Algunas plataformas no aceptan filtros: reintentar sin filtro.
    return _query(map, layer, null);
  }
}

Map _props(Object? f) => f is Map ? (f['properties'] as Map? ?? const {}) : const {};

({String type, Object coords})? _geometry(Object? f) {
  if (f is! Map) return null;
  final g = f['geometry'];
  if (g is! Map) return null;
  final type = g['type'];
  final coords = g['coordinates'];
  if (type is! String || coords == null) return null;
  return (type: type, coords: coords);
}

List<LatLng> _points(Object? line) {
  if (line is! List) return const [];
  final out = <LatLng>[];
  for (final p in line) {
    if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
      out.add(LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()));
    }
  }
  return out;
}

/// Filtro barato por distancia (equirectangular, sin trigonometría por punto).
class _Near {
  _Near(this.c, double radiusM) : _dLat = radiusM / 110574, _dLng = radiusM / (111320 * math.max(0.05, math.cos(c.lat * math.pi / 180)));
  final LatLng c;
  final double _dLat;
  final double _dLng;

  bool test(LatLng p) => (p.lat - c.lat).abs() <= _dLat && (p.lng - c.lng).abs() <= _dLng;
}

/// Nombre del lugar (ciudad, pueblo o barrio) más cercano según los rótulos
/// `place` de los tiles cargados. Prefiere ciudades/pueblos; si no hay ninguno
/// en los tiles, el barrio más cercano. En web suele devolver null.
Future<String?> queryNearestPlace(ml.MapLibreMapController map, LatLng around) async {
  final List feats;
  try {
    feats = await map.querySourceFeatures(SuturaMapStyle.source, 'place', null);
  } catch (e) {
    return null;
  }
  const towns = {'city', 'town', 'village'};
  String? best;
  var bestScore = double.infinity;
  for (final f in feats) {
    final p = _props(f);
    final name = (p['name:es'] ?? p['name'])?.toString();
    if (name == null || name.isEmpty) continue;
    final g = _geometry(f);
    if (g == null || g.type != 'Point') continue;
    final pts = _points([g.coords]);
    if (pts.isEmpty) continue;
    final d = haversineM(around, pts.first);
    // Una ciudad a 8 km pesa como un barrio a 2 km.
    final score = towns.contains('${p['class']}') ? d / 4 : d;
    if (score < bestScore) {
      bestScore = score;
      best = name;
    }
  }
  return best;
}

/// Tramo de calle con nombre (para los avisos ambientales: "Humo en Av. Corrientes").
typedef NamedSegment = ({String name, LatLng a, LatLng b});

/// Calles con nombre de los tiles cargados, cerca de `around`. En web suele
/// devolver una lista vacía (los avisos usan entonces solo el rumbo).
Future<List<NamedSegment>> queryStreetNames(ml.MapLibreMapController map, LatLng around, {double radiusM = 900}) async {
  final List feats;
  try {
    feats = await map.querySourceFeatures(SuturaMapStyle.source, 'transportation_name', null);
  } catch (_) {
    return const [];
  }
  final near = _Near(around, radiusM);
  final out = <NamedSegment>[];
  final seen = <int>{};
  for (final f in feats) {
    final p = _props(f);
    final name = (p['name:es'] ?? p['name'])?.toString().trim();
    if (name == null || name.isEmpty) continue;
    final g = _geometry(f);
    if (g == null) continue;
    final lines = switch (g.type) {
      'LineString' => [g.coords],
      'MultiLineString' => g.coords as List,
      _ => const [],
    };
    for (final line in lines) {
      final pts = _points(line);
      for (var i = 1; i < pts.length; i++) {
        final a = pts[i - 1];
        final b = pts[i];
        if (!near.test(a) && !near.test(b)) continue;
        final k = Object.hash(name, (a.lat * 1e6).round(), (a.lng * 1e6).round());
        if (!seen.add(k)) continue;
        out.add((name: name, a: a, b: b));
        if (out.length > 4000) return out;
      }
    }
  }
  return out;
}

/// Nombre de la calle más cercana a `p` (a menos de `maxM`), o null.
String? nearestStreetName(List<NamedSegment> streets, LatLng p, {double maxM = 60}) {
  String? best;
  var bestD = maxM;
  for (final s in streets) {
    final pa = toLocalXY(p, s.a);
    final pb = toLocalXY(p, s.b);
    final q = nearestPointOnSegment(const XY(0, 0), pa, pb);
    final d = math.sqrt(q.x * q.x + q.y * q.y);
    if (d < bestD) {
      bestD = d;
      best = s.name;
    }
  }
  return best;
}
