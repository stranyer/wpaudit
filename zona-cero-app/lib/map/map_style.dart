import 'dart:convert';

/// Estilo de mapa ZONA CERO: imagen satelital oscura y desaturada con los
/// rótulos de los tiles vectoriales gratuitos de OpenFreeMap (OpenStreetMap).
///
/// Orden de abajo hacia arriba:
/// 1. Respaldo vectorial texturado (se ve si la imagen satelital no carga: sin
///    red, servidor bloqueado o fuera de cobertura): manzanas de techos oscuros
///    (textura `map_roofs`), plazas de copas de árboles (`map_canopy`), calles
///    grises con línea central punteada en avenidas.
/// 2. Imagen satelital ([satelliteTiles], Esri World Imagery por defecto),
///    desaturada y oscurecida (`raster-saturation`/`raster-brightness-max`).
///    Donde una tesela no llega, queda a la vista el respaldo.
/// 3. Cordones finos de las calles, nombres de calle en mayúsculas espaciadas a
///    lo largo de la línea, plazas y lugares destacados ("TEATRO COLÓN").
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

  static const satelliteSource = 'zc-sat';

  /// Teselas satelitales (`{z}/{y}/{x}`). Vacío = sin imagen satelital (solo el
  /// estilo vectorial). Se puede cambiar al compilar:
  /// `--dart-define=SATELLITE_TILES=https://.../{z}/{y}/{x}`.
  static const satelliteTiles = String.fromEnvironment(
    'SATELLITE_TILES',
    defaultValue: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  );
  static const satelliteAttribution = 'Imagery © Esri, Maxar, Earthstar Geographics';

  // Capas base de referencia para insertar overlays.
  static const waterLayer = 'water';
  static const buildingEdgeLayer = 'building-edge';
  static const roadLayer = 'road';
  static const satelliteLayer = 'satellite';

  /// Cordones: dos líneas finas a los lados de cada calle (`line-gap-width`),
  /// por encima de la imagen satelital. Las habitaciones escaneadas van debajo.
  static const roadCasingLayer = 'road-outline';
  static const labelLayer = 'road-label';

  // Imágenes registradas en tiempo de ejecución.
  static const texRoofs = 'zc-tex-roofs';
  static const texGround = 'zc-tex-ground';
  static const texCanopy = 'zc-tex-canopy';
  static const metroIcon = 'zc-metro';

  static const bg = '#151617';
  static const water = '#0B1114';
  static const coast = '#1F2B31';
  static const canopyFallback = '#141B16';
  static const buildingFallback = '#1E2022';
  static const roadMinor = '#2F3234';
  static const roadMajor = '#3A3D3F';
  static const centerLine = '#A9ABAC';
  static const path = '#45484A';
  static const rail = '#5C5F61';
  static const outline = '#B9BDBF';
  static const label = '#CFD2D3';
  static const labelDim = '#A9AEB0';
  static const halo = '#0E0F10';

  /// Clases de `poi` que se rotulan como lugares destacados ("TEATRO COLÓN").
  static const landmarkClasses = ['theatre', 'museum', 'attraction', 'monument', 'stadium', 'castle'];

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

  /// Filtro de las estaciones de subte en `poi`.
  static const Object subwayFilter = ['all', ['==', ['get', 'class'], 'railway'], ['==', ['get', 'subclass'], 'subway']];

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
          if (satelliteTiles.isNotEmpty)
            satelliteSource: {
              'type': 'raster',
              'tiles': [satelliteTiles],
              'tileSize': 256,
              'maxzoom': 19,
              'attribution': satelliteAttribution,
            },
        },
        'layers': [
          {'id': 'bg', 'type': 'background', 'paint': {'background-color': bg}},
          // Anclas de plazas (copas de árboles encima, en tiempo de ejecución).
          {
            'id': 'green-base',
            'type': 'fill',
            'source': source,
            'source-layer': 'landcover',
            'filter': ['match', ['get', 'class'], greenClasses, true, false],
            'paint': {'fill-color': canopyFallback},
          },
          {
            'id': 'park-base',
            'type': 'fill',
            'source': source,
            'source-layer': 'park',
            'paint': {'fill-color': canopyFallback},
          },
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
          // Bordes de edificios (los techos texturados van debajo).
          {
            'id': buildingEdgeLayer,
            'type': 'line',
            'source': source,
            'source-layer': 'building',
            'minzoom': 15,
            'paint': {'line-color': '#34383B', 'line-width': 0.8, 'line-opacity': 0.75},
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
          // Imagen satelital: tapa el respaldo vectorial donde carga.
          if (satelliteTiles.isNotEmpty)
            {
              'id': satelliteLayer,
              'type': 'raster',
              'source': satelliteSource,
              'paint': {
                'raster-saturation': -0.85,
                'raster-brightness-max': 0.45,
                'raster-contrast': 0.1,
                'raster-fade-duration': 250,
              },
            },
          // Cordones finos a ambos lados de la calzada (sobre la imagen).
          {
            'id': roadCasingLayer,
            'type': 'line',
            'source': source,
            'source-layer': 'transportation',
            'minzoom': 13,
            'filter': [
              'all',
              ['match', ['get', 'class'], roadClasses, true, false],
              _notTunnel,
            ],
            'layout': {'line-cap': 'butt', 'line-join': 'round'},
            'paint': {
              'line-color': outline,
              'line-width': ['interpolate', ['linear'], ['zoom'], 14, 0.5, 17, 1],
              'line-gap-width': _scaled(_w16()),
              'line-opacity': ['match', ['get', 'class'], majorClasses, 0.3, 'service', 0.1, 0.2],
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
              'text-font': ['Noto Sans Regular'],
              'text-size': ['interpolate', ['linear'], ['zoom'], 15, 10, 18, 12.5],
              'text-letter-spacing': 0.3,
              'text-max-angle': 28,
              'text-padding': 6,
            },
            'paint': {
              'text-color': ['match', ['get', 'class'], majorClasses, label, labelDim],
              'text-halo-color': halo,
              'text-halo-width': 1.4,
              'text-halo-blur': 0.6,
            },
          },
          // Plazas (centradas) y lugares destacados con un punto debajo
          // ("TEATRO / COLÓN / •"). Las estaciones de subte van aparte: usan un ícono.
          {
            'id': 'poi-label',
            'type': 'symbol',
            'source': source,
            'source-layer': 'poi',
            'minzoom': 15,
            'filter': [
              'all',
              ['has', 'name'],
              ['match', ['get', 'class'], ['park', ...landmarkClasses], true, false],
            ],
            'layout': {
              'text-field': [
                'let',
                'n',
                ['coalesce', ['get', 'name:es'], ['get', 'name'], ''],
                ['case', ['==', ['get', 'class'], 'park'], ['var', 'n'], ['concat', ['var', 'n'], '\n•']],
              ],
              'text-transform': 'uppercase',
              'text-font': ['Noto Sans Regular'],
              'text-size': ['match', ['get', 'class'], 'park', 10, 10.5],
              'text-letter-spacing': 0.32,
              'text-max-width': 6.5,
              'text-line-height': 1.35,
              'text-padding': 8,
              'symbol-sort-key': ['coalesce', ['get', 'rank'], 99],
            },
            'paint': {
              'text-color': ['match', ['get', 'class'], 'park', '#A9AEB1', '#BCC0C2'],
              'text-halo-color': halo,
              'text-halo-width': 1.4,
              'text-halo-blur': 0.6,
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
