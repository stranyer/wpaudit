import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/core.dart';
import 'signals.dart';

/// Visibilidad de un punto en el mapa (escáner estilo sonar).
enum SpawnVisibility { hidden, near, revealed, echo }

/// Mundo alrededor del jugador: spawns, zonas, nodos (refugios) y escáner.
class WorldController extends ChangeNotifier {
  String? centerCellId;
  List<Spawn> spawns = const [];
  List<Zone> zones = const [];
  List<Shelter> shelters = const [];

  /// Señales de auxilio activas (siempre visibles: emiten solas).
  List<DistressSignal> signals = const [];
  bool placementAvailable = false;
  String? selectedId;
  int generatedAt = 0;

  // ---- Escáner ----
  static const scanRadiusM = 250.0;
  static const nearRadiusM = 70.0;
  static const revealMs = 180000;
  static const scanCooldownMs = 45000;
  static const scanDurationMs = 1400;

  /// spawnId -> momento en que deja de estar revelado (luego queda como eco).
  final Map<String, int> _revealedUntil = {};

  /// cellId -> momento del último escaneo que la cubrió.
  final Map<String, int> scannedCells = {};
  int lastScanAt = -scanCooldownMs;
  LatLng? lastScanOrigin;

  /// Fuente de datos de calles (la registra el mapa) para ubicar spawns y nodos.
  PlacementData? Function()? placementSource;

  final Map<String, LatLng> _placed = {};
  final Set<String> _discarded = {};

  // ---- Deambular: los infectados caminan despacio por la calle ----
  final Map<String, ({double dx, double dy, double amp, double speed, double phase})> _wander = {};

  /// Posición actual de un spawn. Los infectados deambulan de ida y vuelta a lo
  /// largo de su calle (determinista: todos los jugadores lo ven igual).
  LatLng positionAt(Spawn s, int now) {
    if (s is! ZombieSpawn) return s.position;
    final w = _wander[s.id] ??= _wanderOf(s);
    final t = now / 1000.0;
    final period = 4 * w.amp / w.speed;
    final k = math.sin(2 * math.pi * (t / period + w.phase));
    return offsetM(s.position, w.dy * w.amp * k, w.dx * w.amp * k);
  }

  ({double dx, double dy, double amp, double speed, double phase}) _wanderOf(ZombieSpawn s) {
    final rng = createRng('wander:${s.id}');
    final speed = switch (s.zombieType) {
      ZombieTypeId.runner => rng.range(0.7, 1.1),
      ZombieTypeId.brute || ZombieTypeId.bloater => rng.range(0.18, 0.3),
      _ => rng.range(0.25, 0.45),
    };
    var angle = rng.range(0, 2 * math.pi);
    // Si hay calles, camina a lo largo del tramo más cercano.
    final data = placementSource?.call();
    if (data != null && data.walkable.isNotEmpty) {
      double best = double.infinity;
      for (final (a, b) in data.walkable) {
        final mid = LatLng((a.lat + b.lat) / 2, (a.lng + b.lng) / 2);
        final d = haversineM(mid, s.position);
        if (d < best) {
          best = d;
          final north = haversineM(LatLng(a.lat, a.lng), LatLng(b.lat, a.lng)) * (b.lat >= a.lat ? 1 : -1);
          final east = haversineM(LatLng(a.lat, a.lng), LatLng(a.lat, b.lng)) * (b.lng >= a.lng ? 1 : -1);
          angle = math.atan2(north, east);
        }
      }
    }
    return (dx: math.cos(angle), dy: math.sin(angle), amp: rng.range(14, 34), speed: speed, phase: rng.range(0, 1));
  }

  int scanCooldownLeft(int now) => (lastScanAt + scanCooldownMs - now).clamp(0, scanCooldownMs);

  SpawnVisibility visibilityOf(Spawn s, LatLng? player, int now) {
    if (player != null && haversineM(player, positionAt(s, now)) <= nearRadiusM) return SpawnVisibility.near;
    final until = _revealedUntil[s.id];
    if (until == null) return SpawnVisibility.hidden;
    return now < until ? SpawnVisibility.revealed : SpawnVisibility.echo;
  }

  /// Momento en que el frente de onda del último escaneo alcanza este punto (ms).
  int revealDelayOf(Spawn s) {
    final o = lastScanOrigin;
    if (o == null) return 0;
    final d = haversineM(o, positionAt(s, lastScanAt));
    return (d / scanRadiusM * scanDurationMs).round();
  }

  /// Dispara un pulso del escáner. Devuelve false si está recargando.
  bool scan(LatLng origin, int now) {
    if (scanCooldownLeft(now) > 0) return false;
    lastScanAt = now;
    lastScanOrigin = origin;
    for (final s in spawns) {
      if (haversineM(origin, positionAt(s, now)) <= scanRadiusM) _revealedUntil[s.id] = now + revealMs;
    }
    for (final z in zones) {
      final c = LatLng((z.bounds.sw.lat + z.bounds.ne.lat) / 2, (z.bounds.sw.lng + z.bounds.ne.lng) / 2);
      if (haversineM(origin, c) <= scanRadiusM + 120) scannedCells[z.cellId] = now;
    }
    notifyListeners();
    return true;
  }

  /// Cantidad de puntos que reveló el último escaneo.
  int revealedCount(int now) => spawns.where((s) => (_revealedUntil[s.id] ?? 0) > now).length;

  List<Spawn> _cleanup(List<Spawn> list, Map<String, int> depleted, int now) {
    final alive = list.where((s) => s.expiresAt > now && !depleted.containsKey(s.id) && !_discarded.contains(s.id)).toList();
    return filterSafeZones(alive, [for (final s in shelters) s.position], gameConfig.shelterSafeRadiusM);
  }

  void regenerate(LatLng center, int now, Map<String, int> depleted) {
    final world = generateWorld(center, gameConfig.spawnRadiusCells, now, gameConfig.spawn);
    final next = [
      for (final s in world.spawns)
        if (_placed[s.id] case final pos?) s.withPlacement(pos, PlacementState.snapped) else s,
    ];
    if (_placed.length > 5000) _placed.clear();
    if (_discarded.length > 5000) _discarded.clear();
    _revealedUntil.removeWhere((id, _) => !next.any((s) => s.id == id));
    spawns = _cleanup(next, depleted, now);
    zones = world.zones;
    signals = [
      for (final sig in generateSignals(world.zones, now, worldSeed: gameConfig.worldSeed))
        if (!depleted.containsKey(sig.id) && sig.expiresAt > now)
          if (_placed[sig.id] case final pos?) sig.withPosition(pos) else sig,
    ];
    centerCellId = cellId(cellOf(center));
    generatedAt = now;
    if (selectedId != null &&
        !spawns.any((s) => s.id == selectedId) &&
        !shelters.any((s) => s.id == selectedId) &&
        !signals.any((s) => s.id == selectedId)) {
      selectedId = null;
    }
    _applyPlacementIfPossible();
    notifyListeners();
  }

  /// Ajusta a la calle los spawns todavía "raw" usando los datos del mapa.
  void applyPlacement(PlacementData data, {bool Function(LatLng)? inView}) {
    var changed = false;
    final next = <Spawn>[];
    for (final s in spawns) {
      if (s.placement == PlacementState.snapped || (inView != null && !inView(s.position))) {
        next.add(s);
        continue;
      }
      changed = true;
      final pos = placePoint(s.position, data, gameConfig.snapMaxDistanceM);
      if (pos != null) {
        _placed[s.id] = pos;
        _wander.remove(s.id);
        next.add(s.withPlacement(pos, PlacementState.snapped));
      } else {
        _discarded.add(s.id);
      }
    }
    final nextSignals = <DistressSignal>[];
    for (final sig in signals) {
      if (sig.snapped || (inView != null && !inView(sig.position))) {
        nextSignals.add(sig);
        continue;
      }
      changed = true;
      final pos = placePoint(sig.position, data, gameConfig.snapMaxDistanceM * 2);
      if (pos != null) {
        _placed[sig.id] = pos;
        nextSignals.add(sig.withPosition(pos));
      } else {
        nextSignals.add(sig); // Sin calle cerca: queda donde está (es una transmisión).
      }
    }
    signals = nextSignals;
    if (changed || !placementAvailable) {
      spawns = filterSafeZones(next, [for (final s in shelters) s.position], gameConfig.shelterSafeRadiusM);
      placementAvailable = true;
      notifyListeners();
    }
  }

  void _applyPlacementIfPossible() {
    final data = placementSource?.call();
    if (data == null || data.walkable.isEmpty) return;
    // Solo se ubican los spawns dentro del área que cubren los datos de calles
    // (con margen); los de afuera esperan a la próxima consulta del mapa en vez
    // de descartarse por falta de datos.
    final box = _coverageOf(data);
    applyPlacement(data, inView: (p) => p.lat >= box.s && p.lat <= box.n && p.lng >= box.w && p.lng <= box.e);
  }

  PlacementData? _coverageData;
  ({double s, double w, double n, double e}) _coverage = (s: 0, w: 0, n: 0, e: 0);

  ({double s, double w, double n, double e}) _coverageOf(PlacementData data) {
    if (identical(data, _coverageData)) return _coverage;
    var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
    for (final (a, b) in data.walkable) {
      for (final p in [a, b]) {
        if (p.lat < s) s = p.lat;
        if (p.lat > n) n = p.lat;
        if (p.lng < w) w = p.lng;
        if (p.lng > e) e = p.lng;
      }
    }
    // Margen hacia adentro (~60 m): cerca del borde faltan calles vecinas.
    const m = 0.00055;
    _coverageData = data;
    return _coverage = (s: s + m, w: w + m, n: n - m, e: e - m);
  }

  /// Spawns que se dibujan: si hay datos de calles, solo los ya ubicados.
  List<Spawn> get drawable => placementAvailable ? spawns.where((s) => s.placement == PlacementState.snapped).toList() : spawns;

  void setShelters(List<Shelter> list) {
    shelters = list;
    spawns = filterSafeZones(spawns, [for (final s in list) s.position], gameConfig.shelterSafeRadiusM);
    notifyListeners();
  }

  void upsertShelter(Shelter shelter) {
    setShelters([...shelters.where((s) => s.id != shelter.id), shelter]);
  }

  void removeSpawn(String id) {
    spawns = spawns.where((s) => s.id != id).toList();
    signals = signals.where((s) => s.id != id).toList();
    if (selectedId == id) selectedId = null;
    notifyListeners();
  }

  /// Selecciona algo del mundo. Volver a seleccionar lo mismo vuelve a avisar
  /// (así "VER EN EL MAPA" centra la cámara aunque ya estuviera seleccionado).
  void select(String? id) {
    if (selectedId == id && id == null) return;
    selectedId = id;
    notifyListeners();
  }

  Spawn? spawnById(String? id) {
    if (id == null) return null;
    for (final s in spawns) {
      if (s.id == id) return s;
    }
    return null;
  }

  DistressSignal? signalById(String? id) {
    if (id == null) return null;
    for (final s in signals) {
      if (s.id == id) return s;
    }
    return null;
  }

  Shelter? shelterById(String? id) {
    if (id == null) return null;
    for (final s in shelters) {
      if (s.id == id) return s;
    }
    return null;
  }
}
