// Tiradas de botín.

import 'dart:math' as math;

import 'inventory.dart';
import 'rng.dart';
import 'types.dart';

/// Escala una cantidad con redondeo probabilístico (1,15 x 3 = 3 o 4).
int _scaleQty(int qty, num multiplier, Rng rng) {
  final scaled = qty * multiplier;
  final base = scaled.floor();
  return math.max(1, base + (rng.chance(scaled - base) ? 1 : 0));
}

/// Tira cada entrada de la tabla de forma independiente.
Inventory rollLoot(List<LootEntry> entries, Rng rng, {num multiplier = 1}) {
  final out = <ItemId, int>{};
  for (final e in entries) {
    if (!rng.chance(e.chance)) continue;
    final qty = _scaleQty(rng.intRange(e.min, e.max), multiplier, rng);
    out[e.itemId] = (out[e.itemId] ?? 0) + qty;
  }
  return out;
}

/// Botín de un punto de suministros: varias pasadas por la tabla y, si no salió
/// nada, garantiza al menos la entrada más probable (nunca vuelve vacío).
Inventory rollSupplyLoot(SupplyDef def, Rng rng, {num multiplier = 1}) {
  var out = <ItemId, int>{};
  final passes = rng.intRange(def.rolls.min, def.rolls.max);
  for (var i = 0; i < passes; i++) {
    out = mergeInventory(out, rollLoot(def.loot, rng, multiplier: multiplier));
  }
  if (out.isEmpty) {
    final fallback = rng.weighted(def.loot, (e) => e.chance);
    out[fallback.itemId] = fallback.min;
  }
  return out;
}
