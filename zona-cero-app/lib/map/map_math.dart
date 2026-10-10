import 'dart:math' as math;

import '../core/core.dart';

/// Cálculos puros del HUD del mapa (escala, región, etiquetas). Sin Flutter ni
/// maplibre para poder probarlos.

// ---------------------------------------------------------------------------
// Escala
// ---------------------------------------------------------------------------

/// Metros por píxel lógico en la latitud `lat` y el zoom `zoom` de MapLibre
/// (teselas de 512 px lógicos, cámara cenital).
double metersPerPixel(double lat, double zoom) =>
    40075016.686 * math.cos(lat * math.pi / 180).abs() / (512 * math.pow(2, zoom));

/// Barra de escala: largo total en metros, ancho en píxeles y rótulos
/// ("0", "100", "200 m").
class ScaleBarSpec {
  const ScaleBarSpec(this.meters, this.px, this.labels);
  final double meters;
  final double px;
  final List<String> labels;
}

const _scaleSteps = [10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0];

/// Elige el mayor tramo "redondo" que entra en `maxPx`.
ScaleBarSpec scaleBarFor({required double lat, required double zoom, double maxPx = 84}) {
  final mpp = metersPerPixel(lat, zoom);
  var meters = _scaleSteps.first;
  for (final s in _scaleSteps) {
    if (s / mpp <= maxPx) meters = s;
  }
  final km = meters >= 1000;
  String fmt(double m) {
    final v = km ? m / 1000 : m;
    final s = v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1).replaceFirst('.', ',');
    return s;
  }

  return ScaleBarSpec(meters, meters / mpp, ['0', fmt(meters / 2), '${fmt(meters)} ${km ? 'km' : 'm'}']);
}

// ---------------------------------------------------------------------------
// Región (rótulos de ciudad)
// ---------------------------------------------------------------------------

typedef GeoBox = ({double s, double n, double w, double e});

/// Área Metropolitana de Buenos Aires (aprox.).
const GeoBox ambaBox = (s: -35.0, n: -34.3, w: -58.9, e: -58.1);

/// Ciudad Autónoma de Buenos Aires (aprox.).
const GeoBox cabaBox = (s: -34.71, n: -34.53, w: -58.54, e: -58.33);

bool inBox(LatLng p, GeoBox b) => p.lat >= b.s && p.lat <= b.n && p.lng >= b.w && p.lng <= b.e;

/// `city`: rótulo del clima ("BUENOS AIRES"); `region`: primera línea del pie
/// del mapa ("C.A.B.A.").
({String city, String region}) regionLabels(LatLng? p, {String? placeName}) {
  const unknown = 'ZONA DESCONOCIDA';
  if (p == null) return (city: unknown, region: unknown);
  if (inBox(p, cabaBox)) return (city: 'BUENOS AIRES', region: 'C.A.B.A.');
  if (inBox(p, ambaBox)) return (city: 'BUENOS AIRES', region: 'G.B.A.');
  final name = placeName?.trim();
  final city = name == null || name.isEmpty ? unknown : name.toUpperCase();
  return (city: city, region: city);
}

// ---------------------------------------------------------------------------
// Etiquetas de marcadores
// ---------------------------------------------------------------------------

/// Candidato a llevar etiqueta (título + distancia) en el mapa.
class LabelCandidate {
  const LabelCandidate(this.id, this.position, this.distanceM, {this.weight = 1});
  final String id;
  final LatLng position;
  final double distanceM;

  /// Multiplicador de la distancia para ordenar (menor = más prioritario).
  final double weight;
}

/// Elige qué marcadores llevan etiqueta: el seleccionado siempre, después los
/// más cercanos, salteando los que pisarían una etiqueta ya elegida en
/// pantalla. Las etiquetas crecen hacia arriba y a la derecha del punto, con un
/// tamaño de `boxW` x `boxH` píxeles. `bearingDeg` es el rumbo de la cámara.
/// Los que ya tenían etiqueta (`previous`) tienen una pequeña ventaja para que
/// no parpadeen al moverse.
Set<String> pickLabelled(
  List<LabelCandidate> candidates, {
  required double metersPerPx,
  double bearingDeg = 0,
  int max = 5,
  String? selectedId,
  Set<String> previous = const {},
  double boxW = 112,
  double boxH = 64,
}) {
  if (candidates.isEmpty || max <= 0) return {};
  double score(LabelCandidate c) => c.distanceM * c.weight * (previous.contains(c.id) ? 0.8 : 1);
  final sorted = [...candidates]..sort((a, b) {
      if (a.id == selectedId) return -1;
      if (b.id == selectedId) return 1;
      return score(a).compareTo(score(b));
    });
  final origin = sorted.first.position;
  final th = bearingDeg * math.pi / 180;
  final cs = math.cos(th);
  final sn = math.sin(th);
  // Posición en pantalla (x derecha, y arriba) en píxeles.
  (double, double) screen(LatLng p) {
    final xy = toLocalXY(origin, p);
    final x = (xy.x * cs - xy.y * sn) / metersPerPx;
    final y = (xy.x * sn + xy.y * cs) / metersPerPx;
    return (x, y);
  }

  final out = <String>{};
  final boxes = <(double, double)>[];
  for (final c in sorted) {
    if (out.length >= max && c.id != selectedId) break;
    final (x, y) = screen(c.position);
    var clash = false;
    for (final (bx, by) in boxes) {
      if ((x - bx).abs() < boxW && (y - by).abs() < boxH) {
        clash = true;
        break;
      }
    }
    if (clash && c.id != selectedId) continue;
    out.add(c.id);
    boxes.add((x, y));
  }
  return out;
}

/// "Nodo Plaza Lavalle" → "Plaza Lavalle" (el rótulo ya dice REFUGIO).
String shelterShortName(String name) {
  final n = name.trim();
  final m = RegExp(r'^(nodo|refugio)\s+(de\s+)?', caseSensitive: false).firstMatch(n);
  if (m == null || m.end >= n.length) return n;
  final rest = n.substring(m.end);
  return rest.isEmpty ? n : rest[0].toUpperCase() + rest.substring(1);
}

/// "183 m" / "1,2 km".
String distanceLabel(double m) {
  if (!m.isFinite) return '— m';
  if (m < 1000) return '${m.round()} m';
  return '${(m / 1000).toStringAsFixed(1).replaceFirst('.', ',')} km';
}

// ---------------------------------------------------------------------------
// Zonas infestadas
// ---------------------------------------------------------------------------

/// Agrupa las celdas infestadas contiguas (8 vecinos) y devuelve un punto por
/// grupo: el centro de la celda más cercana al centroide del grupo (así el
/// marcador siempre cae dentro de la zona).
List<LatLng> infestedClusterCenters(List<Zone> zones) {
  final cells = <String, CellCoord>{
    for (final z in zones)
      if (z.threat == ZoneThreat.infested) z.cellId: parseCellId(z.cellId),
  };
  final seen = <String>{};
  final out = <LatLng>[];
  final ids = cells.keys.toList()..sort();
  for (final start in ids) {
    if (!seen.add(start)) continue;
    final group = <CellCoord>[];
    final stack = [start];
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      final c = cells[id]!;
      group.add(c);
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          if (dx == 0 && dy == 0) continue;
          final n = cellId(CellCoord(c.cx + dx, c.cy + dy));
          if (cells.containsKey(n) && seen.add(n)) stack.add(n);
        }
      }
    }
    var lat = 0.0, lng = 0.0;
    for (final c in group) {
      final p = cellCenter(c);
      lat += p.lat;
      lng += p.lng;
    }
    final centroid = LatLng(lat / group.length, lng / group.length);
    LatLng best = cellCenter(group.first);
    var bestD = double.infinity;
    for (final c in group) {
      final p = cellCenter(c);
      final d = haversineM(p, centroid);
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    out.add(best);
  }
  return out;
}
