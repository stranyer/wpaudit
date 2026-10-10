import 'dart:convert';

/// Estilo de mapa SUTURA: topográfico oscuro sobre tiles vectoriales gratuitos
/// de OpenFreeMap (datos de OpenStreetMap).
///
/// Rendimiento: pocas capas por source-layer del MVT. maplibre-native con
/// Vulkan (issue #881) puede dejar el mapa en blanco cuando hay muchas capas
/// sobre el mismo source-layer, así que las calles se resuelven en dos capas
/// (sólidas y punteadas) con colores/anchos por expresión, y el agua en tres.
abstract final class SuturaMapStyle {
  static const source = 'openmaptiles';

  /// Capas base de referencia para insertar overlays por debajo.
  static const roadLayer = 'road';
  static const labelLayer = 'road-label';

  static const _bg = '#0A0E11';
  static const _block = '#0D1215';
  static const _building = '#111A1F';
  static const _buildingLine = '#1A262D';
  static const _park = '#0E1914';
  static const _parkLine = '#1D3529';
  static const _water = '#061017';
  static const _coast = '#13303C';
  static const _minor = '#1E292F';
  static const _major = '#47616C';
  static const _path = '#1C2C33';
  static const _rail = '#2A3A40';
  static const _label = '#62777E';
  static const _halo = '#0A0E11';

  static const _majorClasses = ['primary', 'secondary', 'trunk', 'motorway'];
  static const _roadClasses = ['minor', 'service', 'track', 'tertiary', 'primary', 'secondary', 'trunk', 'motorway'];

  static String build() => jsonEncode(style());

  static Map<String, dynamic> style() => {
        'version': 8,
        'name': 'Sutura',
        'glyphs': 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
        'sources': {
          source: {
            'type': 'vector',
            'url': 'https://tiles.openfreemap.org/planet',
            'attribution': '© OpenStreetMap · OpenFreeMap',
          },
        },
        'layers': [
          {'id': 'bg', 'type': 'background', 'paint': {'background-color': _bg}},
          {
            'id': 'landuse',
            'type': 'fill',
            'source': source,
            'source-layer': 'landuse',
            'paint': {'fill-color': _block},
          },
          {
            'id': 'park',
            'type': 'fill',
            'source': source,
            'source-layer': 'park',
            'paint': {'fill-color': _park, 'fill-outline-color': _parkLine},
          },
          {
            'id': 'water',
            'type': 'fill',
            'source': source,
            'source-layer': 'water',
            'paint': {'fill-color': _water},
          },
          // Isobatas: dos líneas de costa concéntricas hacia el agua.
          for (final (i, off) in const [(1, 3.0), (2, 12.0)])
            {
              'id': 'coast-$i',
              'type': 'line',
              'source': source,
              'source-layer': 'water',
              'paint': {
                'line-color': _coast,
                'line-width': 1,
                'line-offset': off,
                'line-opacity': i == 1 ? 0.8 : 0.4,
              },
            },
          {
            'id': 'building',
            'type': 'fill',
            'source': source,
            'source-layer': 'building',
            'minzoom': 14,
            'paint': {'fill-color': _building, 'fill-outline-color': _buildingLine},
          },
          // Calles: menores y principales en una sola capa.
          {
            'id': roadLayer,
            'type': 'line',
            'source': source,
            'source-layer': 'transportation',
            'filter': ['match', ['get', 'class'], _roadClasses, true, false],
            'layout': {'line-cap': 'round', 'line-join': 'round'},
            'paint': {
              'line-color': ['match', ['get', 'class'], _majorClasses, _major, _minor],
              'line-width': [
                'interpolate',
                ['exponential', 1.5],
                ['zoom'],
                12,
                ['match', ['get', 'class'], _majorClasses, 0.8, 0.5],
                18,
                ['match', ['get', 'class'], _majorClasses, 9, 6],
              ],
              'line-opacity': ['match', ['get', 'class'], _majorClasses, 0.8, 1],
            },
          },
          // Senderos y vías férreas: punteados, en una sola capa.
          {
            'id': 'path-rail',
            'type': 'line',
            'source': source,
            'source-layer': 'transportation',
            'minzoom': 13,
            'filter': ['match', ['get', 'class'], ['path', 'rail', 'transit'], true, false],
            'paint': {
              'line-color': ['match', ['get', 'class'], 'path', _path, _rail],
              'line-width': 1,
              'line-dasharray': [3, 2],
            },
          },
          {
            'id': labelLayer,
            'type': 'symbol',
            'source': source,
            'source-layer': 'transportation_name',
            'minzoom': 15.5,
            'layout': {
              'symbol-placement': 'line',
              'text-field': ['upcase', ['get', 'name']],
              'text-font': ['Noto Sans Regular'],
              'text-size': 10,
              'text-letter-spacing': 0.25,
            },
            'paint': {'text-color': _label, 'text-halo-color': _halo, 'text-halo-width': 1.5},
          },
          {
            'id': 'place-label',
            'type': 'symbol',
            'source': source,
            'source-layer': 'place',
            'filter': ['match', ['get', 'class'], ['suburb', 'neighbourhood', 'quarter'], true, false],
            'layout': {
              'text-field': ['upcase', ['get', 'name']],
              'text-font': ['Noto Sans Bold'],
              'text-size': 12,
              'text-letter-spacing': 0.5,
            },
            'paint': {'text-color': '#47616C', 'text-halo-color': _halo, 'text-halo-width': 1.5},
          },
        ],
      };
}
