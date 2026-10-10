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
Future<PlacementData?> queryPlacementData(
  ml.MapLibreMapController map, {
  required LatLng around,
  double radiusM = 1600,
}) async {
  final roads = await _query(map, 'transportation', ['match', ['get', 'class'], _walkableClasses, true, false]);
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
  addPolygons([for (final f in water) if (_props(f)['brunnel'] != 'tunnel') f]);
  addPolygons(await _query(map, 'landuse', ['match', ['get', 'class'], _excludedLanduse, true, false]));
  addPolygons(await _query(map, 'aeroway', null));
  return PlacementData(walkable: walkable, excluded: excluded);
}

Future<List> _query(ml.MapLibreMapController map, String layer, List<Object>? filter) async {
  try {
    return await map.querySourceFeatures(SuturaMapStyle.source, layer, filter);
  } catch (e) {
    if (filter == null || '$e'.contains('STYLE_NOT_READY')) {
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
  _Near(this.c, double radiusM)
      : _dLat = radiusM / 110574,
        _dLng = radiusM / (111320 * math.max(0.05, math.cos(c.lat * math.pi / 180)));
  final LatLng c;
  final double _dLat;
  final double _dLng;

  bool test(LatLng p) => (p.lat - c.lat).abs() <= _dLat && (p.lng - c.lng).abs() <= _dLng;
}
