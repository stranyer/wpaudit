import 'dart:math' as math;

import '../core/core.dart';
import 'map_math.dart';

/// Eventos ambientales del mapa: la ciudad "respira" alrededor del jugador
/// (disparos a lo lejos, humo, movimiento, alarmas...). Son solo ambientación:
/// un aviso breve en el feed y un ping que late unos segundos en una calle
/// cercana. Lógica pura (sin Flutter ni maplibre) para poder probarla.

enum AmbientKind {
  shots(AmbientTone.hostile, 5),
  movement(AmbientTone.hostile, 5),
  screams(AmbientTone.hostile, 3),
  smoke(AmbientTone.hazard, 4),
  alarm(AmbientTone.hazard, 3),
  glass(AmbientTone.hazard, 3),
  radio(AmbientTone.signal, 3),
  rotor(AmbientTone.signal, 1);

  const AmbientKind(this.tone, this.weight);
  final AmbientTone tone;

  /// Frecuencia relativa.
  final int weight;
}

/// Color del aviso y del ping: rojo (hostil), ámbar (peligro) o azul acero (radio).
enum AmbientTone { hostile, hazard, signal }

class AmbientEvent {
  const AmbientEvent({
    required this.id,
    required this.kind,
    required this.position,
    required this.text,
    required this.detail,
    required this.at,
    required this.until,
  });

  final int id;
  final AmbientKind kind;
  final LatLng position;

  /// "Humo en Av. Corrientes".
  final String text;

  /// "320 m · NO".
  final String detail;
  final int at;

  /// Fin del ping en el mapa (ms).
  final int until;

  AmbientTone get tone => kind.tone;
}

/// Texto del aviso. Con `street` usa la calle; si no, solo el rumbo.
String ambientText(AmbientKind kind, {String? street, required String dir}) {
  final on = street == null || street.isEmpty ? null : street;
  return switch (kind) {
    AmbientKind.shots => 'Disparos a lo lejos',
    AmbientKind.movement => on != null ? 'Movimiento detectado en $on' : 'Movimiento detectado',
    AmbientKind.screams => on != null ? 'Gritos sobre $on' : 'Gritos hacia el $dir',
    AmbientKind.smoke => on != null ? 'Humo en $on' : 'Columna de humo al $dir',
    AmbientKind.alarm => on != null ? 'Alarma de auto en $on' : 'Alarma de auto al $dir',
    AmbientKind.glass => on != null ? 'Vidrios rotos en $on' : 'Vidrios rotos cerca',
    AmbientKind.radio => 'Interferencia en 7.3 MHz',
    AmbientKind.rotor => 'Rotor de helicóptero al $dir',
  };
}

/// "Avenida Corrientes" → "Av. Corrientes".
String shortStreetName(String name) {
  final n = name.trim();
  if (n.startsWith('Avenida ')) return 'Av. ${n.substring(8)}';
  if (n.startsWith('Diagonal ')) return 'Diag. ${n.substring(9)}';
  return n;
}

/// Programa los eventos ambientales con intervalos al azar.
///
/// - El primero llega `firstMinMs`..`firstMaxMs` después de [start].
/// - Los siguientes, cada `minGapMs`..`maxGapMs`.
/// - Si el mapa está ocupado (intro, pulso del escáner, ficha abierta) se
///   posterga unos segundos en vez de perderse.
class AmbientEventScheduler {
  AmbientEventScheduler({
    math.Random? random,
    this.firstMinMs = 9000,
    this.firstMaxMs = 16000,
    this.minGapMs = 24000,
    this.maxGapMs = 58000,
    this.pingMs = 9000,
    this.minDistM = 140,
    this.maxDistM = 460,
  }) : _rng = random ?? math.Random();

  final math.Random _rng;
  final int firstMinMs;
  final int firstMaxMs;
  final int minGapMs;
  final int maxGapMs;
  final int pingMs;
  final double minDistM;
  final double maxDistM;

  int? _nextAt;
  int _seq = 0;
  AmbientKind? _last;

  /// Momento del próximo evento (null antes de [start]).
  int? get nextAt => _nextAt;

  void start(int now) => _nextAt ??= now + _between(firstMinMs, firstMaxMs);

  int _between(int a, int b) => a + _rng.nextInt(math.max(1, b - a + 1));

  AmbientKind _pickKind() {
    final total = AmbientKind.values.fold(0, (a, k) => a + k.weight);
    for (var tries = 0; tries < 4; tries++) {
      var r = _rng.nextInt(total);
      for (final k in AmbientKind.values) {
        r -= k.weight;
        if (r < 0) {
          // Evita repetir el mismo tipo dos veces seguidas.
          if (k != _last || tries == 3) return k;
          break;
        }
      }
    }
    return AmbientKind.shots;
  }

  /// Devuelve un evento si ya es hora. `pickPoint` elige un punto (en una
  /// calle, si hay datos) a cierta distancia del jugador; `streetAt` devuelve
  /// el nombre de la calle más cercana a un punto, si se conoce.
  AmbientEvent? poll({
    required int now,
    required LatLng? player,
    bool busy = false,
    LatLng? Function(LatLng player, double minM, double maxM, math.Random rng)? pickPoint,
    String? Function(LatLng p)? streetAt,
  }) {
    final next = _nextAt;
    if (next == null || now < next || player == null) return null;
    if (busy) {
      _nextAt = now + _between(3000, 6000);
      return null;
    }
    _nextAt = now + _between(minGapMs, maxGapMs);
    final kind = _pickKind();
    _last = kind;
    final near = kind == AmbientKind.movement || kind == AmbientKind.glass;
    final lo = near ? minDistM * 0.8 : minDistM;
    final hi = near ? (minDistM + maxDistM) / 2 : maxDistM;
    final pos = pickPoint?.call(player, lo, hi, _rng) ?? _randomPoint(player, lo, hi);
    final d = haversineM(player, pos);
    final dir = compassLabel(bearingDeg(player, pos));
    final street = kind == AmbientKind.shots || kind == AmbientKind.radio || kind == AmbientKind.rotor ? null : streetAt?.call(pos);
    final text = ambientText(kind, street: street == null ? null : shortStreetName(street), dir: dir);
    final dist = distanceLabel((d / 10).round() * 10.0);
    return AmbientEvent(
      id: ++_seq,
      kind: kind,
      position: pos,
      text: text,
      // Si el texto ya dice el rumbo ("Gritos hacia el E"), solo la distancia.
      detail: text.endsWith(' $dir') ? dist : '$dist · $dir',
      at: now,
      until: now + pingMs,
    );
  }

  LatLng _randomPoint(LatLng p, double lo, double hi) {
    final a = _rng.nextDouble() * 2 * math.pi;
    final r = lo + _rng.nextDouble() * (hi - lo);
    return offsetM(p, math.cos(a) * r, math.sin(a) * r);
  }
}

/// Punto al azar sobre una calle (segmentos caminables) entre `lo` y `hi`
/// metros del jugador; null si no hay ninguno en ese anillo.
LatLng? pointOnStreets(List<Segment> walkable, LatLng player, double lo, double hi, math.Random rng) {
  if (walkable.isEmpty) return null;
  for (var i = 0; i < 24; i++) {
    final (a, b) = walkable[rng.nextInt(walkable.length)];
    final t = rng.nextDouble();
    final p = LatLng(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t);
    final d = haversineM(player, p);
    if (d >= lo && d <= hi) return p;
  }
  return null;
}
