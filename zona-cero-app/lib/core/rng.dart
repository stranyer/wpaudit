// Generador pseudoaleatorio determinístico (mulberry32) con semilla de texto.
// La misma semilla produce la misma secuencia en cualquier cliente o servidor,
// lo que permite que todos los jugadores vean el mismo mundo.
//
// La implementación es bit a bit idéntica a la versión TypeScript (FNV-1a de
// 32 bits + mulberry32 con la semántica de `Math.imul` y `>>> 0`).

import 'dart:math' as math;

import 'utils.dart';

/// Fuente de aleatoriedad del motor. Basta implementar [next]; el resto de los
/// métodos se derivan de él exactamente como en la versión web.
abstract class Rng {
  const Rng();

  /// Número en [0, 1).
  double next();

  /// Entero en [min, max] (ambos incluidos). Es `rng.int(min, max)` en TS.
  int intRange(int min, int max) => min + (next() * (max - min + 1)).floor();

  /// Real en [min, max).
  double range(num min, num max) => min + next() * (max - min);

  bool chance(num p) => next() < p;

  T pick<T>(List<T> items) => items[(next() * items.length).floor()];

  T weighted<T>(List<T> items, num Function(T item) weight) {
    var total = 0.0;
    for (final it in items) {
      total += math.max(0, weight(it));
    }
    var roll = next() * total;
    for (final it in items) {
      roll -= math.max(0, weight(it));
      if (roll < 0) return it;
    }
    return items[items.length - 1];
  }
}

/// Hash FNV-1a de 32 bits sobre las unidades UTF-16 del texto (igual que `charCodeAt`).
int hashString(String input) {
  var h = 0x811c9dc5;
  for (var i = 0; i < input.length; i++) {
    h ^= input.codeUnitAt(i);
    h = imul32(h, 0x01000193);
  }
  return h & 0xFFFFFFFF;
}

class _Mulberry32 extends Rng {
  _Mulberry32(this._state);

  /// Estado de 32 bits sin signo.
  int _state;

  @override
  double next() {
    _state = (_state + 0x6d2b79f5) & 0xFFFFFFFF;
    var t = _state;
    t = imul32(t ^ (t >> 15), t | 1);
    t ^= (t + imul32(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF;
    return ((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296;
  }
}

/// Crea un RNG determinístico. `seed` puede ser un texto (se hashea) o un número
/// (se convierte con la semántica `>>> 0` de JavaScript).
Rng createRng(Object seed) {
  final int state;
  if (seed is String) {
    state = hashString(seed);
  } else if (seed is num) {
    state = toUint32(seed);
  } else {
    throw ArgumentError.value(seed, 'seed', 'La semilla debe ser String o num');
  }
  return _Mulberry32(state);
}

final math.Random _random = math.Random();

/// RNG no determinístico para tiradas de combate/botín locales.
Rng randomRng() => createRng(_random.nextInt(0x100000000));
