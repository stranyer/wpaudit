import 'dart:math' as math;

import '../core/core.dart';

/// Cálculos puros del HUD del mapa (escala, región, etiquetas). Sin Flutter ni
/// maplibre para poder probarlos.

// ---------------------------------------------------------------------------
// Escala
// ---------------------------------------------------------------------------

/// Metros por píxel lógico en la latitud `lat` y el zoom `zoom` de MapLibre
/// (teselas de 512 px lógicos, cámara cenital).
double metersPerPixel(double lat, double zoom) => 40075016.686 * math.cos(lat * math.pi / 180).abs() / (512 * math.pow(2, zoom));

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

/// Barra de escala táctica: tramo total con una marca intermedia a un tercio
/// ("0  100  300 m"), como en las cartas militares.
class TacticalScale {
  const TacticalScale(this.meters, this.px, this.ticks, this.labels);

  /// Largo total en metros y en píxeles.
  final double meters;
  final double px;

  /// Posición de las marcas (0..1).
  final List<double> ticks;
  final List<String> labels;
}

const _tacticalSteps = [30.0, 75.0, 150.0, 300.0, 750.0, 1500.0, 3000.0, 7500.0, 15000.0];

/// Elige el mayor tramo (múltiplo de 3 de un número redondo) que entra en `maxPx`.
TacticalScale tacticalScaleFor({required double lat, required double zoom, double maxPx = 96}) {
  final mpp = metersPerPixel(lat, zoom);
  var meters = _tacticalSteps.first;
  for (final s in _tacticalSteps) {
    if (s / mpp <= maxPx) meters = s;
  }
  final km = meters >= 1500;
  String fmt(double m) {
    final v = km ? m / 1000 : m;
    return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1).replaceFirst('.', ',');
  }

  return TacticalScale(meters, meters / mpp, const [0, 1 / 3, 1], ['0', fmt(meters / 3), '${fmt(meters)} ${km ? 'km' : 'm'}']);
}

// ---------------------------------------------------------------------------
// Día de supervivencia
// ---------------------------------------------------------------------------

/// "DÍA 7": días de calendario (hora local) desde que se creó el jugador,
/// contando el primero como día 1.
int survivalDay(int createdAtMs, int nowMs) {
  final a = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  final b = DateTime.fromMillisecondsSinceEpoch(nowMs);
  // Fechas UTC sin hora: evita errores con los cambios de horario.
  final da = DateTime.utc(a.year, a.month, a.day);
  final db = DateTime.utc(b.year, b.month, b.day);
  return math.max(1, db.difference(da).inDays + 1);
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

/// Pie del mapa junto al emblema: tres líneas ("CIUDAD AUTÓNOMA", "DE BUENOS
/// AIRES", "ARG.").
List<String> regionCaption(LatLng? p, {String? placeName}) {
  if (p != null && inBox(p, cabaBox)) return const ['CIUDAD AUTÓNOMA', 'DE BUENOS AIRES', 'ARG.'];
  if (p != null && inBox(p, ambaBox)) return const ['GRAN BUENOS AIRES', 'PROV. DE BUENOS AIRES', 'ARG.'];
  final name = placeName?.trim();
  if (p == null) return const ['ZONA DESCONOCIDA', 'SIN POSICIÓN', 'VITA-7'];
  return [if (name == null || name.isEmpty) 'ZONA DESCONOCIDA' else name.toUpperCase(), 'SECTOR SIN CATALOGAR', 'VITA-7'];
}

// ---------------------------------------------------------------------------
// Rumbo
// ---------------------------------------------------------------------------

const _compass = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];

/// Punto cardinal (8 rumbos, en castellano: "O" = oeste) de un rumbo en grados.
String compassLabel(double bearingDeg) {
  final i = (((bearingDeg % 360) + 360) % 360 / 45).round() % 8;
  return _compass[i];
}

// ---------------------------------------------------------------------------
// Etiquetas de marcadores
// ---------------------------------------------------------------------------

/// Título de un marcador en una o dos líneas centradas ("ZONA / INFECTADA",
/// "SEÑAL / DE AUXILIO"). Corta en el primer espacio si el texto pasa de
/// `maxChars`.
List<String> markTitleLines(String title, {int maxChars = 10}) {
  final t = title.trim().toUpperCase();
  if (t.length <= maxChars || !t.contains(' ')) return [t];
  final i = t.indexOf(' ');
  return [t.substring(0, i), t.substring(i + 1)];
}

/// Candidato a llevar etiqueta (título + distancia) en el mapa.
class LabelCandidate {
  const LabelCandidate(this.id, this.position, this.distanceM, {this.weight = 1, this.width});
  final String id;
  final LatLng position;
  final double distanceM;

  /// Multiplicador de la distancia para ordenar (menor = más prioritario).
  final double weight;

  /// Ancho de la etiqueta en píxeles (null = `boxW`).
  final double? width;
}

/// Elige qué marcadores llevan etiqueta: el seleccionado siempre, después los
/// más cercanos, salteando los que pisarían una etiqueta ya elegida en
/// pantalla. Cada marcador ocupa una caja centrada en x de `width` (o `boxW`)
/// píxeles que va desde `boxAbove` px por encima del punto (el ícono) hasta
/// `boxH - boxAbove` px por debajo (título y distancia). `bearingDeg` es el
/// rumbo de la cámara.
/// Los que ya tenían etiqueta (`previous`) tienen una pequeña ventaja para que
/// no parpadeen al moverse.
Set<String> pickLabelled(
  List<LabelCandidate> candidates, {
  required double metersPerPx,
  double bearingDeg = 0,
  int max = 5,
  String? selectedId,
  Set<String> previous = const {},
  double boxW = 96,
  double boxH = 64,
  double boxAbove = 16,
}) {
  if (candidates.isEmpty || max <= 0) return {};
  double score(LabelCandidate c) => c.distanceM * c.weight * (previous.contains(c.id) ? 0.8 : 1);
  final sorted = [...candidates]
    ..sort((a, b) {
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
  // Cajas: (izquierda, derecha, arriba, abajo) con y hacia arriba.
  final boxes = <(double, double, double, double)>[];
  for (final c in sorted) {
    if (out.length >= max && c.id != selectedId) break;
    final (x, y) = screen(c.position);
    final w = c.width ?? boxW;
    final box = (x - w / 2, x + w / 2, y + boxAbove, y + boxAbove - boxH);
    var clash = false;
    for (final (l, r, t, b) in boxes) {
      if (box.$1 < r && l < box.$2 && box.$4 < t && b < box.$3) {
        clash = true;
        break;
      }
    }
    if (clash && c.id != selectedId) continue;
    out.add(c.id);
    boxes.add(box);
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
List<LatLng> infestedClusterCenters(List<Zone> zones) => [for (final c in infestedClusters(zones)) c.center];

/// Zona infestada para el mapa: centro (dentro del grupo) y radio del área roja
/// (cubre las celdas del grupo, con un mínimo de [minZoneRadiusM]).
typedef InfestedCluster = ({LatLng center, double radiusM, int cells});

const minZoneRadiusM = 95.0;

List<InfestedCluster> infestedClusters(List<Zone> zones) {
  final cells = <String, CellCoord>{
    for (final z in zones)
      if (z.threat == ZoneThreat.infested) z.cellId: parseCellId(z.cellId),
  };
  final seen = <String>{};
  final out = <InfestedCluster>[];
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
    var r = 0.0;
    for (final c in group) {
      r = math.max(r, haversineM(best, cellCenter(c)));
    }
    // Media celda (~100 m) alrededor de la celda más lejana, achicada para que
    // el área no tape media pantalla.
    out.add((center: best, radiusM: math.max(minZoneRadiusM, r * 0.8 + 70), cells: group.length));
  }
  return out;
}
