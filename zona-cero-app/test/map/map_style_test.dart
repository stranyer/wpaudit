import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/map/map_style.dart';

void main() {
  final style = SuturaMapStyle.style();
  final layers = (style['layers'] as List).cast<Map<String, dynamic>>();

  test('el estilo se serializa a JSON válido', () {
    expect(() => jsonDecode(SuturaMapStyle.build()), returnsNormally);
  });

  test('pocas capas por source-layer (maplibre-native #881)', () {
    final count = <String, int>{};
    for (final l in layers) {
      final sl = l['source-layer'];
      if (sl is String) count[sl] = (count[sl] ?? 0) + 1;
    }
    // Más las capas con textura que se agregan en tiempo de ejecución (una por source-layer).
    for (final e in count.entries) {
      expect(e.value, lessThanOrEqualTo(3), reason: e.key);
    }
  });

  test('las source-layers que usan capas de tiempo de ejecución tienen un ancla en el estilo', () {
    final named = {for (final l in layers) l['source-layer']};
    expect(named, containsAll(['landcover', 'park', 'building', 'poi', 'transportation', 'water']));
  });

  test('solo usa fuentes que existen en el servidor de glifos de OpenFreeMap', () {
    for (final l in layers) {
      final font = (l['layout'] as Map?)?['text-font'];
      if (font == null) continue;
      for (final f in font as List) {
        expect(['Noto Sans Regular', 'Noto Sans Bold', 'Noto Sans Italic'], contains(f), reason: l['id'] as String);
      }
    }
  });

  test('las capas de referencia existen', () {
    final ids = {for (final l in layers) l['id']};
    expect(ids, containsAll([
      SuturaMapStyle.waterLayer,
      SuturaMapStyle.roadCasingLayer,
      SuturaMapStyle.roadLayer,
      SuturaMapStyle.labelLayer,
      SuturaMapStyle.buildingEdgeLayer,
      'green-base',
    ]));
  });
}
