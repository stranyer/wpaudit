// Generación determinística del mundo.
// Cada celda de la grilla produce sus spawns a partir de (semilla, celda, ventana de tiempo),
// así que todos los jugadores ven lo mismo sin necesidad de un servidor, y un backend
// puede regenerar exactamente los mismos spawns para validar interacciones.
// Es bit a bit idéntica a la versión web: misma semilla = mismo mundo.

import 'dart:math' as math;

import 'geo.dart';
import 'rng.dart';
import 'supplies.dart';
import 'types.dart';
import 'zombies.dart';

class SpawnConfig {
  const SpawnConfig({
    required this.worldSeed,
    required this.zombieWindowMs,
    required this.supplyWindowMs,
    required this.infestedCellChance,
  });

  final String worldSeed;
  final int zombieWindowMs;
  final int supplyWindowMs;
  final double infestedCellChance;
}

/// Las zonas infestadas rotan cada 6 horas.
const int _threatWindowMs = 6 * 60 * 60 * 1000;

/// `Math.floor(now / windowMs)` (división real, como en JS).
int _window(int now, int windowMs) => (now / windowMs).floor();

ZoneThreat cellThreat(CellCoord cell, int now, SpawnConfig cfg) {
  final w = _window(now, _threatWindowMs);
  final rng = createRng('${cfg.worldSeed}:threat:${cellId(cell)}:$w');
  return rng.chance(cfg.infestedCellChance) ? ZoneThreat.infested : ZoneThreat.calm;
}

/// Punto aleatorio dentro de la celda, dejando un margen del 8% en los bordes.
LatLng _pointInCell(CellCoord cell, Rng rng) {
  final b = cellBounds(cell);
  const m = 0.08;
  final lat = b.sw.lat + (b.ne.lat - b.sw.lat) * rng.range(m, 1 - m);
  final lng = b.sw.lng + (b.ne.lng - b.sw.lng) * rng.range(m, 1 - m);
  return LatLng(lat, lng);
}

List<Spawn> generateCellSpawns(CellCoord cell, int now, SpawnConfig cfg) {
  final id = cellId(cell);
  final threat = cellThreat(cell, now, cfg);
  final infested = threat == ZoneThreat.infested;
  final out = <Spawn>[];

  // Zombies: rotan rápido (deambulan).
  final zw = _window(now, cfg.zombieWindowMs);
  final zr = createRng('${cfg.worldSeed}:z:$id:$zw');
  final zCount = infested ? zr.intRange(2, 4) : zr.intRange(0, 2);
  for (var i = 0; i < zCount; i++) {
    final type = zr.weighted(zombieTypes, (t) {
      final w = zombieDefs[t]!.spawnWeight;
      return infested && (t == ZombieTypeId.runner || t == ZombieTypeId.brute || t == ZombieTypeId.screamer)
          ? w * 2
          : w;
    });
    out.add(ZombieSpawn(
      id: 'z:$id:$zw:$i',
      cellId: id,
      position: _pointInCell(cell, zr),
      zombieType: type,
      expiresAt: (zw + 1) * cfg.zombieWindowMs,
      placement: PlacementState.raw,
    ));
  }

  // Suministros: duran más.
  final sw = _window(now, cfg.supplyWindowMs);
  final sr = createRng('${cfg.worldSeed}:s:$id:$sw');
  final sCount = sr.intRange(1, 3) + (infested ? 1 : 0);
  for (var i = 0; i < sCount; i++) {
    final type = sr.weighted(supplyTypes, (t) {
      if (t == SupplyTypeId.military) return infested ? supplyDefs[t]!.spawnWeight * 4 : 0;
      return supplyDefs[t]!.spawnWeight;
    });
    out.add(SupplySpawn(
      id: 's:$id:$sw:$i',
      cellId: id,
      position: _pointInCell(cell, sr),
      supplyType: type,
      expiresAt: (sw + 1) * cfg.supplyWindowMs,
      placement: PlacementState.raw,
    ));
  }
  return out;
}

class WorldSnapshot {
  const WorldSnapshot({required this.spawns, required this.zones});
  final List<Spawn> spawns;
  final List<Zone> zones;
}

WorldSnapshot generateWorld(LatLng center, int radiusCells, int now, SpawnConfig cfg) {
  final spawns = <Spawn>[];
  final zones = <Zone>[];
  for (final cell in cellsAround(center, radiusCells)) {
    spawns.addAll(generateCellSpawns(cell, now, cfg));
    zones.add(Zone(cellId: cellId(cell), threat: cellThreat(cell, now, cfg), bounds: cellBounds(cell)));
  }
  return WorldSnapshot(spawns: spawns, zones: zones);
}

/// Quita zombies dentro del radio seguro de los refugios.
List<Spawn> filterSafeZones(List<Spawn> spawns, List<LatLng> shelters, num safeRadiusM) {
  if (shelters.isEmpty) return spawns;
  return [
    for (final s in spawns)
      if (s is! ZombieSpawn || shelters.every((p) => haversineM(p, s.position) > safeRadiusM)) s,
  ];
}

/// Siguiente cambio de ventana: cuándo conviene regenerar el mundo.
int nextWindowChange(int now, SpawnConfig cfg) {
  final nz = (_window(now, cfg.zombieWindowMs) + 1) * cfg.zombieWindowMs;
  final ns = (_window(now, cfg.supplyWindowMs) + 1) * cfg.supplyWindowMs;
  return math.min(nz, ns);
}
