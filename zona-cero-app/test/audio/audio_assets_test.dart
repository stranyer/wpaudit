import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/audio/sfx.dart';

/// Verifica un encabezado MP3 (ID3 o sincronismo de cuadro MPEG).
bool _looksLikeMp3(Uint8List b) {
  if (b.length < 4) return false;
  if (b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) return true; // "ID3"
  return b[0] == 0xFF && (b[1] & 0xE0) == 0xE0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final files = [...SfxId.values.map((e) => e.asset), ...Ambience.values.map((e) => e.asset)];

  test('cada SfxId y Ambience tiene su mp3 en el bundle', () async {
    for (final f in files) {
      final data = await rootBundle.load(f);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      expect(_looksLikeMp3(bytes), isTrue, reason: f);
    }
  });

  test('tamaños razonables: efectos chicos, ambientes < 1 MB, total < 6 MB', () {
    var total = 0;
    for (final f in files) {
      final size = File(f).lengthSync();
      total += size;
      final isAmbience = Ambience.values.any((a) => a.asset == f);
      expect(size, lessThan(isAmbience ? 1024 * 1024 : 160 * 1024), reason: f);
      expect(size, greaterThan(1024), reason: f);
    }
    expect(total, lessThan(6 * 1024 * 1024));
  });

  test('CREDITS.md documenta cada archivo', () {
    final credits = File('assets/audio/CREDITS.md').readAsStringSync();
    for (final f in files) {
      expect(credits, contains(f.split('/').last), reason: f);
    }
  });
}
