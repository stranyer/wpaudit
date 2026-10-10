// Ubicación segura de spawns.
// Los puntos generados al azar se mueven a la calle, vereda o sendero público más
// cercano. Si no hay ninguno cerca, o cae dentro de una zona excluida (agua,
// instalaciones militares, vías de tren, autopistas...), el spawn se descarta.

import 'geo.dart';
import 'types.dart';

class PlacementData {
  const PlacementData({required this.walkable, required this.excluded});

  /// Segmentos transitables a pie y de acceso público.
  final List<Segment> walkable;

  /// Polígonos excluidos ([anillo exterior, ...agujeros]).
  final List<List<List<LatLng>>> excluded;
}

LatLng? placePoint(LatLng raw, PlacementData data, num maxDistM) {
  final snapped = snapToSegments(raw, data.walkable, maxDistM);
  if (snapped == null) return null;
  if (data.excluded.any((poly) => pointInPolygon(snapped.position, poly))) return null;
  return snapped.position;
}

/// Ajusta spawns "raw"; descarta los que no tienen ubicación segura.
List<Spawn> placeSpawns(List<Spawn> spawns, PlacementData data, num maxDistM) {
  final out = <Spawn>[];
  for (final s in spawns) {
    if (s.placement == PlacementState.snapped) {
      out.add(s);
      continue;
    }
    final pos = placePoint(s.position, data, maxDistM);
    if (pos != null) out.add(s.withPlacement(pos, PlacementState.snapped));
  }
  return out;
}
