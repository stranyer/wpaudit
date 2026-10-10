import 'dart:convert';

/// Estilo de mapa ZONA CERO: "foto aérea nocturna" sobre los tiles vectoriales
/// gratuitos de OpenFreeMap (datos de OpenStreetMap).
///
/// Manzanas de techos oscuros (textura `map_roofs`), plazas de copas de árboles
/// (`map_canopy`), calles como bandas grises con cordón claro y línea central
/// punteada en avenidas, nombres de calle en mayúsculas espaciadas a lo largo de
/// la línea, nombres de plazas centrados y estaciones de subte con una "M".
///
/// Las capas con `fill-pattern`/íconos se agregan en tiempo de ejecución
/// (`GameMap._addBaseOverlays`), recién después de registrar las imágenes con
/// `addImage`: si una capa pide un patrón que todavía no existe, la tesela se
/// arma sin él y queda vacía hasta recargarse.
///
/// Rendimiento: pocas capas por source-layer del MVT (maplibre-native puede dejar
/// el mapa en blanco con muchas capas sobre el mismo source-layer, issue #881):
/// las calles se resuelven en tres capas (cordón, calzada y punteadas) con
/// colores/anchos por expresión.
abstract final class SuturaMapStyle {
  static const source = 'openmaptiles';

  // Capas base de referencia para insertar overlays.
  static const waterLayer = 'water';
  static const roadCasingLayer = 'road-casing';
  static const roadLayer = 'road';
  static const labelLayer = 'road-label';

  // Imágenes registradas en tiempo de ejecución.
  static const texRoofs = 'zc-tex-roofs';
  static const texCanopy = 'zc-tex-canopy';
  static const metroIcon = 'zc-metro';

  static const bg = '#151617';
  static const water = '#0B1114';
  static const coast = '#1F2B31';
  static const canopyFallback = '#141B16';
  static const buildingFallback = '#1E2022';
  static const casing = '#56595B';
  static const roadMinor = '#2F3234';
  static const roadMajor = '#3A3D3F';
  static const centerLine = '#A9ABAC';
  static const path = '#45484A';
  static const rail = '#5C5F61';
  static const label = '#C4C7C8';
  static const labelDim = '#9DA2A4';
  static const halo = '#111213';

  static const majorClasses = ['primary', 'secondary', 'trunk', 'motorway'];
  static const roadClasses = ['minor', 'service', 'tertiary', 'primary', 'secondary', 'trunk', 'motorway'];

  /// Clases de `landcover` que se dibujan como copas de árboles.
  static const greenClasses = ['grass', 'wood', 'forest', 'park', 'scrub', 'farmland'];

  static String build() => jsonEncode(style());

  /// Ancho de calle en píxeles a zoom 16 (escala ×2 por nivel de zoom, como el suelo).
  static Object _w16() => [
        'match',
        ['get', 'class'],
        ['motorway', 'trunk'], 16,
        'primary', 15,
        'secondary', 13.5,
        'tertiary', 11.5,
        'service', 5,
        9.5,
      ];

  static Object _scaled(Object w16, {double add = 0}) => [
        'interpolate',
        ['exponential', 2],
        ['zoom'],
        12,
        ['+', ['/', w16, 16], add * 0.5],
        16,
        ['+', w16, add],
        20,
        ['+', ['*', w16, 16], add],
      ];

  static const _notTunnel = ['!=', ['get', 'brunnel'], 'tunnel'];

  /// "Avenida Corrientes" → "Av. Corrientes" (el estilo lo pasa a mayúsculas).
  static const Object streetName = [
    'let',
    'n',
    ['coalesce', ['get', 'name:es'], ['get', 'name'], ''],
    [
      'case',
      ['==', ['slice', ['var', 'n'], 0, 8], 'Avenida '],
      ['concat', 'Av. ', ['slice', ['var', 'n'], 8]],
      ['==', ['slice', ['var', 'n'], 0, 9], 'Diagonal '],
      ['concat', 'Diag. ', ['slice', ['var', 'n'], 9]],
      ['var', 'n'],
    ],
  ];

  /// "Tribunales - Teatro Colón" → "Tribunales".
  static const Object stationName = [
    'let',
    'n',
    ['coalesce', ['get', 'name'], ''],
    'i',
    ['index-of', ' - ', ['coalesce', ['get', 'name'], '']],
    [
      'case',
      ['>', ['var', 'i'], 0],
      ['slice', ['var', 'n'], 0, ['var', 'i']],
      ['var', 'n'],
    ],
  ];

  static const Object isSubway = ['==', ['get', 'subclass'], 'subway'];

  /// Filtro de la capa de rótulos de `poi`: plazas con nombre y estaciones de subte.
  static const Object poiFilter = [
    'any',
    ['all', ['==', ['get', 'class'], 'park'], ['has', 'name']],
    ['all', ['==', ['get', 'class'], 'railway'], ['==', ['get', 'subclass'], 'subway']],
  ];

  static Map<String, dynamic> style() => {
        'version': 8,
        'name': 'Zona Cero',
        'glyphs': 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
        'sources': {
          source: {
            'type': 'vector',
            'url': 'https://tiles.openfreemap.org/planet',
            'attribution': '© OpenStreetMap · OpenFreeMap',
          },
        },
        'layers': [
          {'id': 'bg', 'type': 'background', 'paint': {'background-color': bg}},
          {
            'id': waterLayer,
            'type': 'fill',
            'source': source,
            'source-layer': 'water',
            'filter': _notTunnel,
            'paint': {'fill-color': water},
          },
          {
            'id': 'coast',
            'type': 'line',
            'source': source,
            'source-layer': 'water',
            'filter': _notTunnel,
            'paint': {'line-color': coast, 'line-width': 1.2, 'line-opacity': 0.8},
          },
          // Cordón: banda apenas más ancha y clara debajo de la calzada.
          {
            'id': roadCasingLayer,
            'type': 'line',
            'source': source,
            'source-layer': 'transportation',
            'filter': [
              'all',
              ['match', ['get', 'class'], roadClasses, true, false],
              _notTunnel,
            ],
            'layout': {'line-cap': 'round', 'line-join': 'round'},
            'paint': {
              'line-color': casing,
              'line-width': _scaled(_w16(), add: 2.2),
              'line-opacity': ['match', ['get', 'class'], 'service', 0.5, 0.9],
            },
          },
          {
            'id': roadLayer,
            'type': 'line',
            'source': source,
            'source-layer': 'transportation',
            'filter': [
              'all',
              ['match', ['get', 'class'], roadClasses, true, false],
              _notTunnel,
            ],
            'layout': {'line-cap': 'round', 'line-join': 'round'},
            'paint': {
              'line-color': ['match', ['get', 'class'], majorClasses, roadMajor, roadMinor],
              'line-width': _scaled(_w16()),
            },
          },
          // Punteadas: línea central de avenidas, senderos y vías de tren.
          {
            'id': 'road-dash',
            'type': 'line',
            'source': source,
            'source-layer': 'transportation',
            'minzoom': 14,
            'filter': [
              'all',
              ['match', ['get', 'class'], [...majorClasses, 'path', 'rail'], true, false],
              _notTunnel,
            ],
            'paint': {
              'line-color': [
                'match',
                ['get', 'class'],
                'path', path,
                'rail', rail,
                centerLine,
              ],
              'line-width': [
                'interpolate',
                ['linear'],
                ['zoom'],
                14,
                0.6,
                18,
                ['match', ['get', 'class'], 'path', 1.6, 1.4],
              ],
              'line-opacity': ['match', ['get', 'class'], 'path', 0.9, 'rail', 0.8, 0.5],
              'line-dasharray': [4, 3],
            },
          },
          {
            'id': labelLayer,
            'type': 'symbol',
            'source': source,
            'source-layer': 'transportation_name',
            'minzoom': 14.5,
            'filter': ['match', ['get', 'class'], roadClasses, true, false],
            'layout': {
              'symbol-placement': 'line',
              'symbol-spacing': 320,
              'text-field': streetName,
              'text-transform': 'uppercase',
              'text-font': ['Noto Sans Bold'],
              'text-size': ['interpolate', ['linear'], ['zoom'], 15, 9.5, 18, 12],
              'text-letter-spacing': 0.28,
              'text-max-angle': 28,
              'text-padding': 6,
            },
            'paint': {
              'text-color': ['match', ['get', 'class'], majorClasses, label, labelDim],
              'text-halo-color': halo,
              'text-halo-width': 1.6,
              'text-halo-blur': 0.5,
            },
          },
          // Barrios: solo con el mapa alejado.
          {
            'id': 'place-label',
            'type': 'symbol',
            'source': source,
            'source-layer': 'place',
            'maxzoom': 15,
            'filter': ['match', ['get', 'class'], ['suburb', 'neighbourhood', 'quarter'], true, false],
            'layout': {
              'text-field': ['coalesce', ['get', 'name:es'], ['get', 'name'], ''],
              'text-transform': 'uppercase',
              'text-font': ['Noto Sans Bold'],
              'text-size': 11,
              'text-letter-spacing': 0.4,
            },
            'paint': {'text-color': '#7E8487', 'text-halo-color': halo, 'text-halo-width': 1.5},
          },
        ],
      };
}
