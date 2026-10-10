import 'package:flutter/foundation.dart';

import '../core/core.dart';

/// Visibilidad de un punto en el mapa (escáner estilo sonar).
enum SpawnVisibility { hidden, near, revealed, echo }

/// Mundo alrededor del jugador: spawns, zonas, nodos (refugios) y escáner.
class WorldController extends ChangeNotifier {
  String? centerCellId;
  List<Spawn> spawns = const [];
  List<Zone> zones = const [];
  List<Shelter> shelters = const [];
  bool placementAvailable = false;
  String? selectedId;
  int generatedAt = 0;

  // ---- Escáner ----
  static const scanRadiusM = 250.0;
  static const nearRadiusM = 70.0;
  static const revealMs = 120000;
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

  int scanCooldownLeft(int now) => (lastScanAt + scanCooldownMs - now).clamp(0, scanCooldownMs);

  SpawnVisibility visibilityOf(Spawn s, LatLng? player, int now) {
    if (player != null && haversineM(player, s.position) <= nearRadiusM) return SpawnVisibility.near;
    final until = _revealedUntil[s.id];
    if (until == null) return SpawnVisibility.hidden;
    return now < until ? SpawnVisibility.revealed : SpawnVisibility.echo;
  }

  /// Momento en que el frente de onda del último escaneo alcanza este punto (ms).
  int revealDelayOf(Spawn s) {
    final o = lastScanOrigin;
    if (o == null) return 0;
    final d = haversineM(o, s.position);
    return (d / scanRadiusM * scanDurationMs).round();
  }

  /// Dispara un pulso del escáner. Devuelve false si está recargando.
  bool scan(LatLng origin, int now) {
    if (scanCooldownLeft(now) > 0) return false;
    lastScanAt = now;
    lastScanOrigin = origin;
    for (final s in spawns) {
      if (haversineM(origin, s.position) <= scanRadiusM) _revealedUntil[s.id] = now + revealMs;
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
    centerCellId = cellId(cellOf(center));
    generatedAt = now;
    if (selectedId != null && !spawns.any((s) => s.id == selectedId) && !shelters.any((s) => s.id == selectedId)) {
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
        next.add(s.withPlacement(pos, PlacementState.snapped));
      } else {
        _discarded.add(s.id);
      }
    }
    if (changed || !placementAvailable) {
      spawns = filterSafeZones(next, [for (final s in shelters) s.position], gameConfig.shelterSafeRadiusM);
      placementAvailable = true;
      notifyListeners();
    }
  }

  void _applyPlacementIfPossible() {
    final data = placementSource?.call();
    if (data != null && data.walkable.isNotEmpty) applyPlacement(data);
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
    if (selectedId == id) selectedId = null;
    notifyListeners();
  }

  void select(String? id) {
    if (selectedId == id) return;
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

  Shelter? shelterById(String? id) {
    if (id == null) return null;
    for (final s in shelters) {
      if (s.id == id) return s;
    }
    return null;
  }
}
