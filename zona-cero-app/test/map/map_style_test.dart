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
    expect(
      ids,
      containsAll([
        SuturaMapStyle.waterLayer,
        SuturaMapStyle.roadCasingLayer,
        SuturaMapStyle.roadLayer,
        SuturaMapStyle.labelLayer,
        SuturaMapStyle.buildingEdgeLayer,
        'green-base',
      ]),
    );
  });

  group('imagen satelital', () {
    final sources = style['sources'] as Map<String, dynamic>;
    final ids = [for (final l in layers) l['id'] as String];

    test('fuente raster de Esri World Imagery (o la de SATELLITE_TILES)', () {
      final sat = sources[SuturaMapStyle.satelliteSource] as Map<String, dynamic>;
      expect(sat['type'], 'raster');
      expect(sat['tileSize'], 256);
      expect(sat['maxzoom'], 19);
      final url = (sat['tiles'] as List).single as String;
      expect(url, contains('{z}'));
      expect(url.indexOf('{y}'), lessThan(url.indexOf('{x}')), reason: 'Esri usa {z}/{y}/{x}');
      expect(sat['attribution'], contains('Esri'));
      // Se conserva la atribución de OpenStreetMap / OpenFreeMap.
      expect((sources[SuturaMapStyle.source] as Map)['attribution'], contains('OpenStreetMap'));
    });

    test('desaturada y oscura', () {
      final layer = layers.firstWhere((l) => l['id'] == SuturaMapStyle.satelliteLayer);
      final paint = layer['paint'] as Map;
      // Gris oscuro de la referencia: casi sin color y con el blanco recortado.
      expect(paint['raster-saturation'] as num, inInclusiveRange(-0.95, -0.75));
      expect(paint['raster-brightness-max'] as num, inInclusiveRange(0.3, 0.5));
      expect(paint['raster-contrast'] as num, inInclusiveRange(0, 0.15));
    });

    test('el respaldo vectorial queda debajo; cordones y rótulos, encima', () {
      final sat = ids.indexOf(SuturaMapStyle.satelliteLayer);
      for (final below in [
        'bg',
        'green-base',
        SuturaMapStyle.waterLayer,
        SuturaMapStyle.buildingEdgeLayer,
        SuturaMapStyle.roadLayer,
        'road-dash',
      ]) {
        expect(ids.indexOf(below), lessThan(sat), reason: below);
      }
      for (final above in [SuturaMapStyle.roadCasingLayer, SuturaMapStyle.labelLayer, 'poi-label']) {
        expect(ids.indexOf(above), greaterThan(sat), reason: above);
      }
    });

    test('los cordones son dos líneas finas a los lados de la calzada', () {
      final layer = layers.firstWhere((l) => l['id'] == SuturaMapStyle.roadCasingLayer);
      expect((layer['paint'] as Map).containsKey('line-gap-width'), isTrue);
    });

    test('rotula plazas y lugares destacados como el Teatro Colón', () {
      final layer = layers.firstWhere((l) => l['id'] == 'poi-label');
      final filter = jsonEncode(layer['filter']);
      expect(filter, contains('theatre'));
      expect(filter, contains('park'));
      expect(SuturaMapStyle.landmarkClasses, containsAll(['theatre', 'museum', 'monument']));
    });
  });
}
