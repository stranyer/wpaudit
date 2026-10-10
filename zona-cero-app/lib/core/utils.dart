// Utilidades internas para reproducir exactamente la aritmética de JavaScript.
//
// El motor original corre en JS, donde todos los números son `double` y algunas
// operaciones (Math.round, Math.imul, `${n}`) tienen semánticas propias. Para que
// el mundo y el combate sean idénticos en ambas plataformas, las emulamos acá.

const int _mask32 = 0xFFFFFFFF;

/// `Math.imul` de JavaScript: producto de enteros de 32 bits.
///
/// Devuelve los 32 bits bajos SIN signo (0..2^32-1). Se calcula partiendo los
/// operandos en mitades de 16 bits, así nunca se depende del desborde de `int`.
int imul32(int a, int b) {
  final ua = a & _mask32;
  final ub = b & _mask32;
  final aHi = ua >> 16;
  final aLo = ua & 0xFFFF;
  final bHi = ub >> 16;
  final bLo = ub & 0xFFFF;
  final cross = ((aHi * bLo + aLo * bHi) & 0xFFFF) << 16;
  return (aLo * bLo + cross) & _mask32;
}

/// Conversión `ToUint32` de JavaScript (lo que hace `x >>> 0`).
int toUint32(num x) {
  if (x is int) return x & _mask32;
  final d = x.toDouble();
  if (!d.isFinite) return 0;
  // `remainder` es exacto y evita valores fuera del rango de `int`.
  return d.remainder(4294967296.0).truncate() & _mask32;
}

/// `Math.round` de JavaScript: redondea .5 hacia +infinito (Math.round(-2.5) = -2).
int jsRound(num x) {
  if (x is int) return x;
  final d = x.toDouble();
  final f = d.floorToDouble();
  return (d - f >= 0.5 ? f + 1 : f).toInt();
}

/// Convierte un número a texto como lo hace JavaScript (`${n}`):
/// los enteros representados como double se escriben sin ".0".
String jsNumToString(num x) {
  if (x is int) return x.toString();
  final d = x.toDouble();
  if (d == 0) return '0';
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d > 0 ? 'Infinity' : '-Infinity';
  final s = d.toString();
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// Número listo para JSON: los double enteros se emiten como `int` (igual que JS).
num jsonNum(num x) {
  if (x is double && x.isFinite && x == x.truncateToDouble() && x.abs() < 9007199254740992) {
    return x.toInt();
  }
  return x;
}

/// `Math.max(min, Math.min(max, v))`: nunca lanza aunque `min > max`.
double clampDouble(num v, num min, num max) {
  final hi = v < max ? v : max;
  return (min > hi ? min : hi).toDouble();
}

/// Igualdad profunda de mapas (mismo contenido, sin importar el orden).
bool deepMapEquals<K, V>(Map<K, V>? a, Map<K, V>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (final e in a.entries) {
    if (!b.containsKey(e.key) || b[e.key] != e.value) return false;
  }
  return true;
}

/// Igualdad elemento a elemento de listas.
bool deepListEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Hash de un mapa independiente del orden de inserción.
int mapHash<K, V>(Map<K, V> m) => Object.hashAllUnordered(m.entries.map((e) => Object.hash(e.key, e.value)));
