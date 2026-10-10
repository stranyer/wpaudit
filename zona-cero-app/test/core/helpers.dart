// Utilidades compartidas por los tests del motor.

import 'dart:convert';
import 'dart:io';

import 'package:zona_cero/core/core.dart';

/// RNG controlado: devuelve una secuencia fija de valores (cíclica).
class ScriptedRng extends Rng {
  ScriptedRng(this.values);
  final List<double> values;
  int _i = 0;

  @override
  double next() => values[_i++ % values.length];
}

Map<String, dynamic>? _parity;

/// Fixtures generados con la implementación TypeScript original
/// (ver `test/core/fixtures/gen_ts_parity.ts`).
Map<String, dynamic> loadParityFixture() =>
    _parity ??= jsonDecode(File('test/core/fixtures/ts_parity.json').readAsStringSync()) as Map<String, dynamic>;
