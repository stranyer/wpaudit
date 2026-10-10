// Operaciones puras sobre inventarios. Nunca modifican el mapa recibido:
// siempre devuelven uno nuevo (conservando el orden de inserción, como en JS).

import 'dart:math' as math;

import 'items.dart';
import 'types.dart';

int countOf(Inventory inv, ItemId id) => inv[id] ?? 0;

/// Entradas con cantidad positiva, en orden de inserción.
List<MapEntry<ItemId, int>> entries(Inventory inv) => [
      for (final e in inv.entries)
        if (e.value > 0) e,
    ];

Inventory mergeInventory(Inventory a, Inventory b) {
  final out = Map<ItemId, int>.of(a);
  for (final e in entries(b)) {
    out[e.key] = (out[e.key] ?? 0) + e.value;
  }
  return out;
}

bool hasItems(Inventory inv, Inventory required) => entries(required).every((e) => countOf(inv, e.key) >= e.value);

/// Lo que falta para cubrir `required` (vacío si alcanza).
Inventory missingItems(Inventory inv, Inventory required) {
  final out = <ItemId, int>{};
  for (final e in entries(required)) {
    final left = e.value - countOf(inv, e.key);
    if (left > 0) out[e.key] = left;
  }
  return out;
}

/// Quita objetos; devuelve null si no alcanzan.
Inventory? removeItems(Inventory inv, Inventory items) {
  if (!hasItems(inv, items)) return null;
  final out = Map<ItemId, int>.of(inv);
  for (final e in entries(items)) {
    final left = countOf(out, e.key) - e.value;
    if (left > 0) {
      out[e.key] = left;
    } else {
      out.remove(e.key);
    }
  }
  return out;
}

int carriedWeight(Inventory inv) => entries(inv).fold(0, (acc, e) => acc + itemDefs[e.key]!.weight * e.value);

/// Capacidad de la mochila según nivel.
int carryCapacity(int level) => 80 + 10 * (level - 1);

class AddResult {
  const AddResult({required this.inventory, required this.added, required this.overflow});
  final Inventory inventory;
  final Inventory added;
  final Inventory overflow;
}

/// Agrega objetos respetando la capacidad. Los objetos sin peso (equipo) siempre entran.
/// Lo que no entra se informa en `overflow` y se pierde.
AddResult addItems(Inventory inv, Inventory items, {num capacity = double.infinity}) {
  final out = Map<ItemId, int>.of(inv);
  final added = <ItemId, int>{};
  final overflow = <ItemId, int>{};
  var free = capacity - carriedWeight(inv);
  for (final e in entries(items)) {
    final id = e.key;
    final n = e.value;
    final w = itemDefs[id]!.weight;
    final int fit;
    if (w == 0 || free == double.infinity) {
      fit = n;
    } else {
      fit = math.max(0, math.min(n, (free / w).floor()));
    }
    if (fit > 0) {
      out[id] = countOf(out, id) + fit;
      added[id] = fit;
      free -= fit * w;
    }
    if (fit < n) overflow[id] = n - fit;
  }
  return AddResult(inventory: out, added: added, overflow: overflow);
}

/// ¿No hay ningún objeto con cantidad positiva? (`isEmpty` en la web; se renombró
/// porque `isEmpty` choca con el matcher homónimo de `package:test`/`flutter_test`).
bool isInventoryEmpty(Inventory inv) => entries(inv).isEmpty;
