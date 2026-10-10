import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../audio/sfx.dart';
import '../core/core.dart';
import '../state/app_state.dart';
import '../state/location_controller.dart';
import '../state/world_controller.dart';
import '../ui/theme/tokens.dart';
import 'map_events.dart';
import 'map_features.dart';
import 'map_icons.dart';
import 'map_math.dart';
import 'map_style.dart';
import 'placement_query.dart';
import 'widgets/web_tweaks.dart';

/// Cámara por defecto: cenital, a la altura de una foto aérea de barrio.
const kMapZoom = 16.0;

/// Inclinación de la vista 3D opcional (mantener presionada la brújula).
const kMapPitch = 45.0;

/// Entrada al mapa: la cámara arranca lejos sobre la ciudad, inclinada y
/// girada, y vuela hasta el jugador.
const kIntroZoom = 11.2;
const kIntroPitch = 52.0;
const kIntroBearing = -38.0;
const kIntroMs = 3100;

/// Distancia (px lógicos, sin contar el margen superior del sistema) desde el
/// borde superior del mapa hasta el botón (i) de atribución: a la derecha, en
/// la fila de la brújula, debajo de la tarjeta de objetivo.
const kMapAttributionTop = 128.0;

/// Estado de cámara que la interfaz necesita (seguir al jugador, rumbo para la
/// brújula y el joystick, zoom y latitud para la escala) y acciones (recentrar,
/// norte arriba, zoom, enfocar un objetivo). También publica los avisos
/// ambientales activos y si se está jugando la entrada.
class GameMapController extends ChangeNotifier {
  bool _follow = true;
  bool _pitched = false;
  bool _intro = false;
  double _bearing = 0;
  double _zoom = kMapZoom;
  double? _lat;
  _GameMapState? _state;

  /// Avisos ambientales recientes ("Disparos a lo lejos"), el último al final.
  final events = ValueNotifier<List<AmbientEvent>>(const []);

  /// La cámara sigue al jugador. Se apaga al arrastrar el mapa o al enfocar un objetivo.
  bool get follow => _follow;

  /// Vista inclinada (45°) o cenital (0°).
  bool get pitched => _pitched;

  /// La cámara está volando desde la vista de la ciudad hasta el jugador.
  bool get intro => _intro;

  /// Rumbo de la cámara en grados (0 = norte arriba, sentido horario).
  double get bearing => _bearing;

  /// Zoom actual de la cámara.
  double get zoom => _zoom;

  /// Latitud del centro de la cámara (null antes de crear el mapa).
  double? get latitude => _lat;

  void recenter() => _state?._recenter();
  void togglePitch() => _state?._togglePitch();
  void resetNorth() => _state?._resetNorth();
  void zoomIn() => _state?._zoomBy(1);
  void zoomOut() => _state?._zoomBy(-1);

  /// Lleva la cámara a `p` (deja de seguir al jugador hasta tocar "ubicar").
  /// Con `select`, además selecciona ese objetivo (sin volver a mover la cámara).
  void focus(LatLng p, {String? select}) => _state?._focus(p, select: select);

  /// Lugar más cercano según los rótulos del mapa (solo Android/iOS).
  Future<String?> nearestPlaceName() async => _state?._nearestPlace();

  /// Posición en pantalla (px lógicos, relativa al mapa de tamaño `size`) de
  /// un punto, según la última cámara conocida. Aproximada con la vista
  /// inclinada. null antes de crear el mapa.
  Offset? screenOffsetOf(LatLng p, Size size) {
    final cam = _state?._cam;
    if (cam == null) return null;
    final mpp = metersPerPixel(cam.target.latitude, cam.zoom);
    final xy = toLocalXY(_core(cam.target), p);
    final th = cam.bearing * math.pi / 180;
    final x = xy.x * math.cos(th) - xy.y * math.sin(th);
    final y = xy.x * math.sin(th) + xy.y * math.cos(th);
    final k = math.cos(cam.tilt * math.pi / 180);
    return Offset(size.width / 2 + x / mpp, size.height / 2 - y * k / mpp);
  }

  /// Metros por píxel en el centro de la cámara.
  double get metersPerPx => metersPerPixel(_lat ?? gameConfig.demo.start.lat, _zoom);

  /// Inclinación actual (grados).
  double get tilt => _state?._cam?.tilt ?? 0;

  void _setFollow(bool v) {
    if (_follow == v) return;
    _follow = v;
    notifyListeners();
  }

  void _setPitched(bool v) {
    if (_pitched == v) return;
    _pitched = v;
    notifyListeners();
  }

  void _setIntro(bool v) {
    if (_intro == v) return;
    _intro = v;
    notifyListeners();
  }

  void _setCamera(double bearing, double zoom, double lat) {
    final changed = (bearing - _bearing).abs() > 0.5 || (zoom - _zoom).abs() > 0.01 || _lat == null || (lat - _lat!).abs() > 0.002;
    _bearing = bearing;
    _zoom = zoom;
    _lat = lat;
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    events.dispose();
    super.dispose();
  }
}

abstract final class _Src {
  static const cells = 'zc-cells';
  static const infect = 'zc-infect';
  static const reach = 'zc-reach';
  static const sutures = 'zc-sutures';
  static const scan = 'zc-scan';
  static const marks = 'zc-marks';
  static const player = 'zc-player';
  static const events = 'zc-events';
  static const all = [cells, infect, reach, sutures, marks, player, events];
}

abstract final class _Lyr {
  static const bgTex = 'bg-tex';
  static const canopy = 'canopy';
  static const canopyPark = 'canopy-park';
  static const building = 'building';
  static const metro = 'metro-label';
  static const cellsFill = 'zc-cells-fill';
  static const cellsLine = 'zc-cells-line';
  static const zoneArea = 'zc-zone-area';
  static const zoneEdge = 'zc-zone-edge';
  static const reach = 'zc-reach-line';
  static const sutures = 'zc-sutures-line';
  static const scanA = 'zc-scan-a';
  static const scanB = 'zc-scan-b';
  static const pulse = 'zc-signal-pulse';
  static const ping = 'zc-event-ping';
  static const pingDot = 'zc-event-dot';
  static const marks = 'zc-marks-sym';
  static const player = 'zc-player-sym';
}

/// Propiedades crudas para `setLayerProperties`: solo se envían estas claves
/// (las clases tipadas mandan todas, y los null reinician el estilo).
class _RawProps implements ml.LayerProperties {
  const _RawProps(this.json);
  final Map<String, dynamic> json;
  @override
  Map<String, dynamic> toJson({bool skipNulls = true}) => json;
}

/// Un marcador antes de convertirse en feature.
class _Mark {
  const _Mark(this.id, this.position, this.kind, this.title,
      {this.echo = false, this.own = false, this.mortal = false, this.avatar, required this.z, this.weight = 1, this.radiusM});
  final String id;
  final LatLng position;
  final MarkKind kind;
  final String title;
  final bool echo;
  final bool own;
  final bool mortal;
  final ZombieTypeId? avatar;
  final int z;
  final double weight;

  /// Zona infectada: radio del área roja.
  final double? radiusM;
}

/// Mapa del juego: MapLibre con el estilo ZONA CERO (imagen satelital oscura
/// sobre un respaldo vectorial) y los overlays GeoJSON (habitaciones
/// escaneadas, zonas infectadas, alcance, red de relevo, pulso del escáner,
/// avisos ambientales, marcadores y jugador). Escucha directamente a
/// `app.location`, `app.world` y `app`, y actualiza fuentes (máximo 10 por
/// segundo) sin reconstruir el widget del mapa.
class GameMap extends StatefulWidget {
  const GameMap({super.key, required this.controller});

  final GameMapController controller;

  @override
  State<GameMap> createState() => _GameMapState();
}

class _GameMapState extends State<GameMap> with TickerProviderStateMixin {
  static const _markerRadiusM = 720.0;
  static const _signalRadiusM = 1500.0;
  static const _pulseEchoDelayMs = 180;
  static const _maxLabels = 5;
  static const _heartbeatMs = 150;
  static const _eventToastMs = 6500;

  /// La entrada se juega una vez por sesión (no al volver de otra pestaña).
  static bool _introDone = false;

  ml.MapLibreMapController? _map;
  bool _styleReady = false;
  int _styleGen = 0;
  double _iconBase = 1;
  double _dpr = 2;
  late final String _style = SuturaMapStyle.build();

  // Cámara
  ml.CameraPosition? _camera;
  LatLng? _segA;
  LatLng? _segB;
  LatLng? _lastFix;
  Offset? _downAt;
  int _pointers = 0;
  double _labelZoom = kMapZoom;
  double _labelBearing = 0;

  // Entrada y "golpe" de cámara del escáner
  bool _intro = false;
  Timer? _introTimer;
  Timer? _fadeTimer;
  Timer? _bumpTimer;
  double? _bumpZoom;
  int _bumpUntil = 0;

  /// Multiplicador de opacidad de los marcadores (aparecen después de la entrada).
  double _markFade = 1;

  // Selección: la que hace el propio mapa no mueve la cámara.
  String? _lastSel;
  String? _selfSel;

  // Fuentes
  final Map<String, String> _sig = {};
  final Set<String> _dirty = {};
  Timer? _flushTimer;
  int _lastFlushAt = 0;
  Set<String> _shownSpawns = {};
  Set<String> _shownCells = {};
  Set<String> _labelled = {};
  String? _clusterKey;
  List<InfestedCluster> _clusters = const [];
  bool _walkers = false;

  // Imágenes de marcadores (se registran a pedido).
  final Set<String> _images = {};
  final Set<String> _imagesPending = {};
  static final Map<String, Uint8List> _imageBytes = {};

  // Pulso del escáner
  late final Ticker _ticker = createTicker(_onFrame);
  int _seenScanAt = 0;
  int _lastRingPush = 0;
  Set<String> _preScanSpawns = {};
  Set<String> _preScanCells = {};
  int _pendingSpawns = -1;
  int _pendingCellsCount = -1;
  int _lastHaptic = 0;
  int _lastPing = 0;
  double _ringLat = 0;

  // Latido de las señales de auxilio y de los avisos ambientales
  late final Ticker _pulseTicker = createTicker(_onPulse);
  int _lastPulsePush = 0;
  bool _signalsOn = false;
  bool _pulseLit = false;
  bool _pingLit = false;

  // Pulso de vida: infectados que caminan y avisos ambientales.
  Timer? _heartbeat;
  ValueListenable<TickerModeData>? _tickerMode;
  final _ambient = AmbientEventScheduler();
  final List<AmbientEvent> _events = [];

  // Ubicación de spawns en calles
  PlacementData? _placement;
  LatLng? _placementCenter;
  List<NamedSegment> _streets = const [];
  int _lastPlaceAt = 0;
  int _emptyQueries = 0;
  bool _placing = false;
  Timer? _placeDebounce;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  bool get _visible => _tickerMode?.value.enabled ?? true;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    _seenScanAt = app.world.lastScanAt;
    _lastFix = app.location.position;
    _lastSel = app.world.selectedId;
    if (!_introDone) _markFade = 0;
    app.location.addListener(_onLocation);
    app.world.addListener(_onWorld);
    app.addListener(_onApp);
    app.world.placementSource = _placementFor;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mode = TickerMode.getValuesNotifier(context);
    if (mode != _tickerMode) {
      _tickerMode?.removeListener(_syncHeartbeat);
      _tickerMode = mode..addListener(_syncHeartbeat);
      _syncHeartbeat();
    }
  }

  @override
  void didUpdateWidget(GameMap old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller._state == this) old.controller._state = null;
      widget.controller._state = this;
    }
  }

  @override
  void dispose() {
    if (widget.controller._state == this) widget.controller._state = null;
    app.location.removeListener(_onLocation);
    app.world.removeListener(_onWorld);
    app.removeListener(_onApp);
    _tickerMode?.removeListener(_syncHeartbeat);
    if (app.world.placementSource == _placementFor) app.world.placementSource = null;
    _flushTimer?.cancel();
    _placeDebounce?.cancel();
    _introTimer?.cancel();
    _fadeTimer?.cancel();
    _bumpTimer?.cancel();
    _heartbeat?.cancel();
    _ticker.dispose();
    _pulseTicker.dispose();
    _map = null;
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Widget
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final start = app.location.position ?? app.demoPosition ?? gameConfig.demo.start;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final top = MediaQuery.paddingOf(context).top + kMapAttributionTop;
    installMapWebTweaks(top: top, right: 14);
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: ml.MapLibreMap(
        styleString: _style,
        initialCameraPosition: _introDone
            ? ml.CameraPosition(target: _ll(start), zoom: kMapZoom)
            : ml.CameraPosition(target: _ll(_introFrom(start)), zoom: kIntroZoom, tilt: kIntroPitch, bearing: kIntroBearing),
        onMapCreated: (c) => _map = c,
        onStyleLoadedCallback: _onStyleLoaded,
        onMapClick: (_, _) => app.world.select(null),
        onMapLongClick: _onLongPress,
        onCameraMove: _onCameraMove,
        onCameraIdle: () => unawaited(_maybePlace()),
        onMapIdle: () => unawaited(_maybePlace()),
        trackCameraPosition: true,
        compassEnabled: false,
        tiltGesturesEnabled: false,
        rotateGesturesEnabled: true,
        // En web el doble clic es el "mantener presionado" (teletransporte demo).
        doubleClickZoomEnabled: kIsWeb ? false : null,
        minMaxZoomPreference: const ml.MinMaxZoomPreference(10.5, 19.5),
        annotationOrder: const [],
        logoEnabled: false,
        // Atribución (OSM, OpenFreeMap, Esri) compacta: botón (i) arriba a la
        // derecha, debajo de la tarjeta de objetivo (márgenes en píxeles físicos).
        attributionButtonPosition: ml.AttributionButtonPosition.topRight,
        attributionButtonMargins: math.Point((14 * dpr).round(), (top * dpr).round()),
        gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
      ),
    );
  }

  /// Punto de partida de la entrada: un poco al noroeste, para que la cámara
  /// cruce la ciudad al acercarse.
  static LatLng _introFrom(LatLng p) => offsetM(p, 700, -1100);

  // ---------------------------------------------------------------------------
  // Estilo, imágenes y capas
  // ---------------------------------------------------------------------------

  Future<void> _onStyleLoaded() async {
    final c = _map;
    if (c == null || !mounted) return;
    final gen = ++_styleGen;
    _styleReady = false;
    _pulseLit = false;
    _pingLit = false;
    _sig.clear();
    _images.clear();
    _imagesPending.clear();
    _dpr = MediaQuery.devicePixelRatioOf(context);
    _iconBase = MapIcons.baseSize(_dpr);
    try {
      final patterns = await _registerImages(c);
      if (gen != _styleGen || !mounted) return;
      await _addBaseLayers(c, patterns);
      if (gen != _styleGen || !mounted) return;
      await _addOverlays(c);
    } catch (e, st) {
      debugPrint('[Zona Cero] No se pudieron crear los overlays del mapa: $e\n$st');
      return;
    }
    if (gen != _styleGen || !mounted) return;
    _styleReady = true;
    collapseMapAttribution();
    c.onFeatureTapped
      ..remove(_onFeatureTap)
      ..add(_onFeatureTap);
    _dirty.addAll(_Src.all);
    _flush();
    _syncHeartbeat();
    if (!_introDone) {
      _maybeIntro();
    } else {
      final p = app.location.position;
      if (p != null && widget.controller.follow) _moveCameraTo(p, animate: false);
    }
    if (app.world.lastScanAt != _seenScanAt) _onWorld();
  }

  /// Registra jugador, "M" de subte y patrones. Devuelve qué patrones quedaron.
  Future<({bool roofs, bool ground, bool canopy})> _registerImages(ml.MapLibreMapController c) async {
    final fixed = await MapIcons.renderStatic(_dpr);
    for (final e in fixed.entries) {
      await c.addImage(e.key, e.value);
      _images.add(e.key);
    }
    Future<bool> pattern(String name, String asset, double tileDp) async {
      try {
        final bytes = _imageBytes['$name@$_dpr'] ??= await MapIcons.pattern(asset, _dpr, tileDp: tileDp);
        await c.addImage(name, bytes);
        return true;
      } catch (e) {
        debugPrint('[Zona Cero] Textura $asset no disponible: $e');
        return false;
      }
    }

    // Techos y suelo con tamaños distintos para que la repetición no coincida.
    final roofs = await pattern(SuturaMapStyle.texRoofs, 'assets/art/tex/map_roofs.png', 224);
    final ground = await pattern(SuturaMapStyle.texGround, 'assets/art/tex/map_roofs.png', 352);
    final canopy = await pattern(SuturaMapStyle.texCanopy, 'assets/art/tex/map_canopy.png', 256);
    return (roofs: roofs, ground: ground, canopy: canopy);
  }

  /// Capas del respaldo vectorial que usan imágenes (textura del suelo, copas
  /// de árboles en plazas, techos) y las estaciones de subte. Van sobre las
  /// anclas del estilo; las primeras quedan debajo de la imagen satelital.
  Future<void> _addBaseLayers(ml.MapLibreMapController c, ({bool roofs, bool ground, bool canopy}) tex) async {
    const src = SuturaMapStyle.source;
    Future<void> guard(String what, Future<void> Function() add) async {
      try {
        await add();
      } catch (e) {
        debugPrint('[Zona Cero] Capa $what: $e');
      }
    }

    if (tex.ground) {
      await guard(_Lyr.bgTex, () => c.addBackgroundLayer(
            _Lyr.bgTex,
            const ml.BackgroundLayerProperties(backgroundPattern: SuturaMapStyle.texGround, backgroundOpacity: 0.5),
            belowLayerId: 'green-base',
          ));
    }
    if (tex.canopy) {
      const green = ml.FillLayerProperties(fillPattern: SuturaMapStyle.texCanopy, fillOpacity: 0.97, fillAntialias: false);
      await guard(_Lyr.canopy, () => c.addFillLayer(
            src,
            _Lyr.canopy,
            green,
            sourceLayer: 'landcover',
            filter: ['match', ['get', 'class'], SuturaMapStyle.greenClasses, true, false],
            belowLayerId: SuturaMapStyle.waterLayer,
            enableInteraction: false,
          ));
      await guard(_Lyr.canopyPark, () => c.addFillLayer(
            src,
            _Lyr.canopyPark,
            green,
            sourceLayer: 'park',
            belowLayerId: SuturaMapStyle.waterLayer,
            enableInteraction: false,
          ));
    }
    await guard(_Lyr.building, () => c.addFillLayer(
          src,
          _Lyr.building,
          ml.FillLayerProperties(
            fillPattern: tex.roofs ? SuturaMapStyle.texRoofs : null,
            fillColor: tex.roofs ? null : SuturaMapStyle.buildingFallback,
            fillOpacity: tex.roofs ? 0.95 : 1,
          ),
          sourceLayer: 'building',
          minzoom: 14,
          belowLayerId: SuturaMapStyle.buildingEdgeLayer,
          enableInteraction: false,
        ));
    await guard(_Lyr.metro, () => c.addSymbolLayer(
          src,
          _Lyr.metro,
          ml.SymbolLayerProperties(
            iconImage: MapIcons.metro,
            iconSize: _iconBase,
            textField: SuturaMapStyle.stationName,
            textFont: const ['Noto Sans Regular'],
            textSize: 11,
            textLetterSpacing: 0.06,
            textAnchor: 'top',
            textOffset: const [0, 1.05],
            textPadding: 4,
            textOptional: true,
            textColor: '#D5D8D9',
            textHaloColor: SuturaMapStyle.halo,
            textHaloWidth: 1.5,
          ),
          sourceLayer: 'poi',
          minzoom: 15,
          filter: SuturaMapStyle.subwayFilter,
          enableInteraction: false,
        ));
  }

  Future<void> _addOverlays(ml.MapLibreMapController c) async {
    for (final id in [..._Src.all, _Src.scan]) {
      await c.addGeoJsonSource(id, emptyCollection(), promoteId: id == _Src.marks ? 'id' : null);
    }
    const outline = SuturaMapStyle.roadCasingLayer;
    const label = SuturaMapStyle.labelLayer;
    const steel = '#8DB4C9';
    const amber = '#D9A233';
    const red = '#E0453A';
    final lat = app.location.position?.lat ?? gameConfig.demo.start.lat;

    // Habitaciones escaneadas (sobre la imagen, debajo de los cordones, apenas teñidas).
    await c.addFillLayer(
      _Src.cells,
      _Lyr.cellsFill,
      const ml.FillLayerProperties(
        fillColor: ['match', ['get', 'st'], 'loot', amber, steel],
        fillOpacity: ['match', ['get', 'st'], 'loot', 0.05, 0.03],
      ),
      belowLayerId: outline,
      enableInteraction: false,
    );
    await c.addLineLayer(
      _Src.cells,
      _Lyr.cellsLine,
      const ml.LineLayerProperties(
        lineColor: ['match', ['get', 'st'], 'loot', amber, steel],
        lineWidth: 1,
        lineOpacity: ['match', ['get', 'st'], 'loot', 0.32, 0.18],
        lineDasharray: [4, 3],
      ),
      belowLayerId: label,
      enableInteraction: false,
    );

    // Zonas infectadas: área roja suave con un borde fino (como en la referencia).
    await c.addCircleLayer(
      _Src.infect,
      _Lyr.zoneArea,
      ml.CircleLayerProperties(
        circleRadius: _metersToPxExpr(lat, ['get', 'rm']),
        circleColor: '#8A1610',
        circleOpacity: 0.32,
        circleBlur: 0.45,
        circlePitchAlignment: 'map',
        circlePitchScale: 'map',
      ),
      belowLayerId: label,
      enableInteraction: false,
    );
    await c.addCircleLayer(
      _Src.infect,
      _Lyr.zoneEdge,
      ml.CircleLayerProperties(
        circleRadius: _metersToPxExpr(lat, ['get', 'rm']),
        circleOpacity: 0,
        circleStrokeColor: red,
        circleStrokeWidth: 0.9,
        circleStrokeOpacity: 0.32,
        circlePitchAlignment: 'map',
        circlePitchScale: 'map',
      ),
      belowLayerId: label,
      enableInteraction: false,
    );

    // Alcance de interacción: círculo fino y claro.
    await c.addLineLayer(
      _Src.reach,
      _Lyr.reach,
      const ml.LineLayerProperties(lineColor: '#E4E8EA', lineWidth: 1.1, lineOpacity: 0.62),
      enableInteraction: false,
    );

    // Red de relevo: solo los enlaces del nodo propio (tenues).
    await c.addLineLayer(
      _Src.sutures,
      _Lyr.sutures,
      const ml.LineLayerProperties(
        lineColor: steel,
        lineWidth: 1,
        lineOpacity: 0.45,
        lineDasharray: [2, 3],
      ),
      filter: ['==', ['get', 'own'], true],
      enableInteraction: false,
    );

    // Pulso del escáner en el suelo: lavado interior y eco (el anillo
    // brillante y la distorsión los dibuja Flutter encima, ver ScanWave).
    for (final id in [_Lyr.scanB, _Lyr.scanA]) {
      await c.addCircleLayer(
        _Src.scan,
        id,
        ml.CircleLayerProperties(
          circleRadius: 0,
          circleColor: steel,
          circleOpacity: 0,
          circleStrokeColor: steel,
          circleStrokeWidth: id == _Lyr.scanA ? 1.6 : 1.1,
          circleStrokeOpacity: 0,
          circlePitchAlignment: 'map',
          circlePitchScale: 'map',
        ),
        enableInteraction: false,
      );
    }

    // Latido de las señales de auxilio (anillo ámbar en el punto del suelo).
    await c.addCircleLayer(
      _Src.marks,
      _Lyr.pulse,
      const ml.CircleLayerProperties(
        circleRadius: 4,
        circleColor: amber,
        circleOpacity: 0,
        circleStrokeColor: amber,
        circleStrokeWidth: 1.4,
        circleStrokeOpacity: 0,
        circlePitchAlignment: 'map',
      ),
      filter: ['==', ['get', 'k'], 'signal'],
      enableInteraction: false,
    );

    // Avisos ambientales: ping que late en una calle cercana.
    const toneColor = ['match', ['get', 't'], 'hostile', red, 'signal', steel, amber];
    await c.addCircleLayer(
      _Src.events,
      _Lyr.ping,
      const ml.CircleLayerProperties(
        circleRadius: 4,
        circleOpacity: 0,
        circleStrokeColor: toneColor,
        circleStrokeWidth: 1.3,
        circleStrokeOpacity: 0,
        circlePitchAlignment: 'map',
      ),
      enableInteraction: false,
    );
    await c.addCircleLayer(
      _Src.events,
      _Lyr.pingDot,
      const ml.CircleLayerProperties(
        circleRadius: 2.6,
        circleColor: toneColor,
        circleOpacity: ['get', 'op'],
        circleBlur: 0.3,
        circlePitchAlignment: 'map',
      ),
      enableInteraction: false,
    );

    // Marcadores: insignia y título horneados; la distancia, como texto
    // debajo, del color del tipo.
    await c.addSymbolLayer(
      _Src.marks,
      _Lyr.marks,
      ml.SymbolLayerProperties(
        iconImage: ['get', 'icon'],
        iconSize: _iconBase,
        iconAnchor: 'top',
        iconOffset: MapIcons.iconOffset(_iconBase),
        iconOpacity: ['get', 'op'],
        iconAllowOverlap: true,
        // Sin ignore-placement: los nombres de calle esquivan los marcadores.
        iconIgnorePlacement: false,
        iconPitchAlignment: 'viewport',
        iconRotationAlignment: 'viewport',
        symbolSortKey: ['get', 'z'],
        textField: ['get', 'dist'],
        textFont: const ['Noto Sans Regular'],
        textSize: MapIcons.distanceSize,
        textAnchor: 'top',
        textJustify: 'center',
        textOffset: ['get', 'toff'],
        textLetterSpacing: 0.12,
        textAllowOverlap: true,
        textIgnorePlacement: false,
        textOpacity: ['get', 'op'],
        textColor: ['get', 'dc'],
        textHaloColor: '#08090A',
        textHaloWidth: 1.2,
        textHaloBlur: 0.4,
      ),
    );

    await c.addSymbolLayer(
      _Src.player,
      _Lyr.player,
      ml.SymbolLayerProperties(
        iconImage: ['get', 'icon'],
        iconSize: _iconBase,
        iconRotate: ['get', 'rot'],
        iconRotationAlignment: 'map',
        iconPitchAlignment: 'map',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      enableInteraction: false,
    );
  }

  void _onFeatureTap(math.Point<double> point, ml.LatLng coordinates, String id, String layerId, ml.Annotation? annotation) {
    if (layerId != _Lyr.marks) return;
    HapticFeedback.selectionClick();
    if (id.startsWith('zone:')) {
      Sfx.play(SfxId.tap, volume: 0.6);
      app.ui.toast('Zona infectada: escaneá para revelar contactos.');
      return;
    }
    _selfSel = id;
    app.world.select(id);
  }

  /// Registra la imagen del marcador si falta. Devuelve false mientras tanto
  /// (el marcador aparece en la próxima actualización).
  bool _ensureImage(MarkSpec spec) {
    final name = spec.name;
    if (_images.contains(name)) return true;
    final c = _map;
    if (c == null || !_imagesPending.add(name)) return false;
    final gen = _styleGen;
    () async {
      try {
        final bytes = _imageBytes['$name@$_dpr'] ??= await MapIcons.renderMark(spec, _dpr);
        if (_imageBytes.length > 400) _imageBytes.clear();
        if (gen != _styleGen || !mounted) return;
        await c.addImage(name, bytes);
        if (gen != _styleGen) return;
        _images.add(name);
        _markDirty(const [_Src.marks]);
      } catch (e) {
        debugPrint('[Zona Cero] Ícono $name: $e');
      } finally {
        if (gen == _styleGen) _imagesPending.remove(name);
      }
    }();
    return false;
  }

  // ---------------------------------------------------------------------------
  // Actualización de fuentes (con límite de frecuencia)
  // ---------------------------------------------------------------------------

  void _markDirty(List<String> ids) {
    _dirty.addAll(ids);
    if (_flushTimer != null || !_styleReady) return;
    final wait = math.max(0, 100 - (_now - _lastFlushAt));
    _flushTimer = Timer(Duration(milliseconds: wait), _flush);
  }

  void _flush() {
    _flushTimer = null;
    final c = _map;
    if (c == null || !_styleReady || !mounted) return;
    _lastFlushAt = _now;
    final ids = _dirty.toList();
    _dirty.clear();
    final now = _now;
    for (final id in ids) {
      final Json? data = switch (id) {
        _Src.player => _buildPlayer(),
        _Src.reach => _buildReach(),
        _Src.infect => _buildInfect(),
        _Src.cells => _buildCells(now),
        _Src.marks => _buildMarks(now),
        _Src.sutures => _buildSutures(),
        _Src.events => _buildEvents(now),
        _ => null,
      };
      if (data != null) {
        c.setGeoJsonSource(id, data).catchError((Object e) => debugPrint('[Zona Cero] $id: $e'));
      }
    }
  }

  /// Devuelve los datos solo si la firma cambió (evita reenviar lo mismo).
  Json? _diff(String id, String sig, Json Function() build) {
    if (_sig[id] == sig) return null;
    _sig[id] = sig;
    return build();
  }

  Json? _buildPlayer() {
    final p = app.location.position;
    if (p == null) return _diff(_Src.player, '-', emptyCollection);
    final h = app.location.headingDeg;
    final icon = h == null ? MapIcons.playerIdle : MapIcons.player;
    return _diff(
      _Src.player,
      '${p.lat},${p.lng},${h?.round()}',
      () => featureCollection([pointFeature(p, {'icon': icon, 'rot': h ?? 0})]),
    );
  }

  Json? _buildReach() {
    final p = app.location.position;
    if (p == null) return _diff(_Src.reach, '-', emptyCollection);
    final r = effectiveRadius(gameConfig.interactionRules, app.location.accuracyM);
    return _diff(_Src.reach, '${p.lat},${p.lng},$r', () => circleCollection(p, r));
  }

  List<InfestedCluster> _zoneClusters() {
    final key = contagionKey(app.world.zones);
    if (key != _clusterKey) {
      _clusterKey = key;
      _clusters = infestedClusters(app.world.zones);
    }
    return _clusters;
  }

  Json? _buildInfect() {
    final pos = app.location.position;
    final zones = [
      for (final z in _zoneClusters())
        if (pos == null || haversineM(pos, z.center) < 2500) z,
    ];
    final sig = [for (final z in zones) '${z.center.lat},${z.center.lng},${z.radiusM.round()}'].join(';');
    return _diff(_Src.infect, sig, () => featureCollection([for (final z in zones) pointFeature(z.center, {'rm': z.radiusM})]));
  }

  Json? _buildMarks(int now) {
    final w = app.world;
    final pos = app.location.position;
    final level = app.player?.level ?? 1;
    final sel = w.selectedId;
    final ownId = app.ownShelter?.id;
    final marks = <_Mark>[];
    bool far(LatLng p, double maxM) => pos != null && haversineM(pos, p) > maxM;

    final shown = <String>{};
    var walkers = false;
    for (final s in w.drawable) {
      final at = w.positionAt(s, now);
      if (far(at, _markerRadiusM)) continue;
      final v = w.visibilityOf(s, pos, now);
      if (v == SpawnVisibility.hidden || _pendingSpawn(s, v, now)) continue;
      shown.add(s.id);
      final echo = v == SpawnVisibility.echo;
      switch (s) {
        case ZombieSpawn z:
          final def = zombieDefs[z.zombieType]!;
          walkers = true;
          marks.add(_Mark(s.id, at, MarkKind.zombie, echo ? 'Hostil' : def.name,
              echo: echo, mortal: threatRating(def, level) >= 3, avatar: z.zombieType, z: 50));
        case SupplySpawn _:
          marks.add(_Mark(s.id, at, MarkKind.supply, 'Saqueo', echo: echo, z: 40));
      }
    }
    _shownSpawns = shown;
    _walkers = walkers;
    for (final sig in w.signals) {
      if (far(sig.position, _signalRadiusM)) continue;
      marks.add(_Mark(sig.id, sig.position, MarkKind.signal, 'Señal de auxilio', z: 60, weight: 0.9));
    }
    for (final n in w.shelters) {
      final own = n.id == ownId;
      marks.add(_Mark(n.id, n.position, MarkKind.node, own ? 'Tu refugio' : 'Refugio', own: own, z: own ? 35 : 30));
    }
    for (final z in _zoneClusters()) {
      if (far(z.center, _signalRadiusM)) continue;
      marks.add(_Mark('zone:${cellId(cellOf(z.center))}', z.center, MarkKind.zone, 'Zona infectada', z: 20, weight: 1.35, radiusM: z.radiusM));
    }

    // Etiquetas: el seleccionado y los más cercanos que no se pisen.
    final cam = _camera;
    final zoom = cam?.zoom ?? kMapZoom;
    final bearing = cam?.bearing ?? 0;
    _labelZoom = zoom;
    _labelBearing = bearing;
    final Set<String> labelled;
    if (pos == null) {
      labelled = {?sel};
    } else {
      labelled = pickLabelled(
        [
          for (final m in marks)
            LabelCandidate(m.id, m.position, haversineM(pos, m.position), weight: m.weight, width: MapIcons.labelWidth(m.title)),
        ],
        metersPerPx: metersPerPixel(pos.lat, zoom),
        bearingDeg: bearing,
        max: _maxLabels,
        selectedId: sel,
        previous: _labelled,
      );
    }
    _labelled = labelled;

    final feats = <Json>[];
    final sig = StringBuffer()..write(_markFade.toStringAsFixed(2));
    var signals = false;
    for (final m in marks) {
      final isLabelled = labelled.contains(m.id);
      final state = m.id == sel ? MarkerState.sel : (m.echo ? MarkerState.echo : MarkerState.on);
      final spec = MarkSpec(
        m.kind,
        state,
        title: isLabelled ? m.title : '',
        labelled: isLabelled,
        own: m.own,
        mortal: m.mortal,
        avatar: m.avatar,
      );
      if (!_ensureImage(spec)) continue;
      final icon = spec.name;
      final dist = isLabelled && pos != null ? distanceLabel(haversineM(pos, m.position)) : '';
      final op = (m.echo ? 0.72 : 1.0) * _markFade;
      final z = m.id == sel ? 100 : m.z;
      if (m.kind == MarkKind.signal) signals = true;
      sig
        ..write(m.id)
        ..write(icon)
        ..write(dist)
        ..write(z)
        ..write(m.position.lat.toStringAsFixed(7))
        ..write(m.position.lng.toStringAsFixed(7))
        ..write(';');
      feats.add(pointFeature(
        m.position,
        {
          'id': m.id,
          'k': m.kind.name,
          'icon': icon,
          'op': op,
          'z': z,
          'dist': dist,
          'dc': hexColor(_distanceColor(m)),
          'toff': isLabelled ? MapIcons.distanceOffset(m.kind, spec.lines.length) : const [0.0, 0.0],
        },
        id: m.id,
      ));
    }
    _signalsOn = signals;
    _syncPulse();
    return _diff(_Src.marks, sig.toString(), () => featureCollection(feats));
  }

  static Color _distanceColor(_Mark m) => switch (m.kind) {
        MarkKind.zombie || MarkKind.zone => const Color(0xFFE5574C),
        _ => markColor(m.kind, own: m.own),
      };

  Json? _buildCells(int now) {
    final w = app.world;
    final pos = app.location.position;
    if (w.scannedCells.isEmpty) return _diff(_Src.cells, '-', emptyCollection);
    final loot = <String>{};
    for (final s in w.drawable) {
      if (s is! SupplySpawn) continue;
      final v = w.visibilityOf(s, pos, now);
      if (v == SpawnVisibility.hidden || _pendingSpawn(s, v, now)) continue;
      loot.add(cellId(cellOf(s.position)));
    }
    final cells = <String, String>{};
    for (final e in w.scannedCells.entries) {
      final center = cellCenter(parseCellId(e.key));
      if (pos != null && haversineM(pos, center) > 1800) continue;
      if (_pendingCell(e.key, e.value, center, now)) continue;
      cells[e.key] = loot.contains(e.key) ? 'loot' : 'clear';
    }
    _shownCells = cells.keys.toSet();
    final sig = ([for (final e in cells.entries) '${e.key}:${e.value}']..sort()).join(',');
    return _diff(_Src.cells, sig, () => cellsCollection(cells));
  }

  Json? _buildSutures() {
    final w = app.world;
    final ownId = app.ownShelter?.id;
    final sig = '${[for (final s in w.shelters) '${s.id}@${s.position.lat},${s.position.lng}'].join(';')}|$ownId';
    return _diff(_Src.sutures, sig, () => suturesCollection(w.shelters, ownId));
  }

  Json? _buildEvents(int now) {
    _events.removeWhere((e) => e.until <= now);
    final sig = [for (final e in _events) '${e.id}:${_eventOpacity(e, now).toStringAsFixed(1)}'].join(',');
    return _diff(
      _Src.events,
      sig,
      () => featureCollection([
        for (final e in _events) pointFeature(e.position, {'t': e.tone.name, 'op': _eventOpacity(e, now)}),
      ]),
    );
  }

  /// El punto del aviso se apaga en el último tramo de su vida.
  static double _eventOpacity(AmbientEvent e, int now) => ((e.until - now) / 1800).clamp(0.0, 1.0) * 0.95;

  // ---------------------------------------------------------------------------
  // Latidos: señales de auxilio y avisos ambientales
  // ---------------------------------------------------------------------------

  void _syncPulse() {
    final on = (_signalsOn || _events.isNotEmpty) && _styleReady;
    if (on && !_pulseTicker.isActive) _pulseTicker.start();
    if (!on && _pulseTicker.isActive) _pulseTicker.stop();
    final c = _map;
    if (c == null || !_styleReady) return;
    // Apagar los anillos solo al dejar de usarlos (cada llamada cruza al mapa).
    if (!_signalsOn && _pulseLit) {
      _pulseLit = false;
      c.setLayerProperties(_Lyr.pulse, const _RawProps({'circle-stroke-opacity': 0})).catchError((_) {});
    }
    if (_events.isEmpty && _pingLit) {
      _pingLit = false;
      c.setLayerProperties(_Lyr.ping, const _RawProps({'circle-stroke-opacity': 0})).catchError((_) {});
    }
  }

  void _onPulse(Duration _) {
    final c = _map;
    final now = _now;
    // ~9 cuadros por segundo alcanzan para un latido suave (cada uno es una llamada al mapa).
    if (c == null || !_styleReady || now - _lastPulsePush < 110) return;
    _lastPulsePush = now;
    if (_signalsOn) {
      _pulseLit = true;
      const period = 2000;
      final t = (now % period) / period;
      final k = Curves.easeOut.transform(t);
      c
          .setLayerProperties(_Lyr.pulse, _RawProps({'circle-radius': 4 + 26 * k, 'circle-stroke-opacity': 0.75 * (1 - t)}))
          .catchError((Object e) => debugPrint('[Zona Cero] latido: $e'));
    }
    if (_events.isNotEmpty) {
      _pingLit = true;
      const period = 1500;
      final t = (now % period) / period;
      final k = Curves.easeOut.transform(t);
      c
          .setLayerProperties(_Lyr.ping, _RawProps({'circle-radius': 3 + 20 * k, 'circle-stroke-opacity': 0.85 * (1 - t)}))
          .catchError((Object e) => debugPrint('[Zona Cero] ping: $e'));
    }
  }

  /// Pulso de vida del mapa (~7 por segundo, solo con el mapa a la vista): los
  /// infectados caminan por su calle y la ciudad emite avisos ambientales.
  void _syncHeartbeat() {
    final on = _visible && _styleReady && mounted;
    if (on && _heartbeat == null) {
      _heartbeat = Timer.periodic(const Duration(milliseconds: _heartbeatMs), (_) => _onHeartbeat());
    } else if (!on && _heartbeat != null) {
      _heartbeat?.cancel();
      _heartbeat = null;
    }
  }

  void _onHeartbeat() {
    if (!mounted || !_styleReady) return;
    final now = _now;
    if (_walkers) _markDirty(const [_Src.marks]);
    // Avisos ambientales.
    if (_introDone && !_intro) {
      _ambient.start(now);
      final busy = now - app.world.lastScanAt < WorldController.scanDurationMs + 600 || app.location.position == null;
      final e = _ambient.poll(
        now: now,
        player: app.location.position,
        busy: busy,
        pickPoint: (p, lo, hi, rng) {
          final w = _placement?.walkable;
          return w == null ? null : pointOnStreets(w, p, lo, hi, rng);
        },
        streetAt: (p) => _streets.isEmpty ? null : nearestStreetName(_streets, p),
      );
      if (e != null) {
        _events.add(e);
        if (_events.length > 4) _events.removeAt(0);
        _publishEvents(now);
        _syncPulse();
      }
    }
    if (_events.isNotEmpty) {
      _markDirty(const [_Src.events]);
      if (_events.every((e) => e.until <= now)) {
        _events.clear();
        _syncPulse();
      }
      _publishEvents(now);
    }
  }

  void _publishEvents(int now) {
    final toasts = [for (final e in _events) if (now - e.at < _eventToastMs) e];
    final cur = widget.controller.events.value;
    if (toasts.length != cur.length || !toasts.every(cur.contains)) {
      widget.controller.events.value = List.unmodifiable(toasts.length > 2 ? toasts.sublist(toasts.length - 2) : toasts);
    }
  }

  // ---------------------------------------------------------------------------
  // Escáner: pulso en el suelo y revelado escalonado
  // ---------------------------------------------------------------------------

  /// Tiempo (ms) que tarda el frente de onda en llegar a `d` metros, con la
  /// misma curva que el anillo (`Sutura.scanCurve`).
  static double _ringReachMs(double d) {
    final f = (d / WorldController.scanRadiusM).clamp(0.0, 1.0);
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 18; i++) {
      final mid = (lo + hi) / 2;
      if (Sutura.scanCurve.transform(mid) < f) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return hi * WorldController.scanDurationMs;
  }

  /// Un contacto recién revelado aparece cuando el frente de onda lo alcanza.
  bool _pendingSpawn(Spawn s, SpawnVisibility v, int now) {
    if (v != SpawnVisibility.revealed) return false;
    final w = app.world;
    final dt = now - w.lastScanAt;
    if (dt < 0 || dt >= WorldController.scanDurationMs) return false;
    if (_preScanSpawns.contains(s.id)) return false;
    final o = w.lastScanOrigin;
    if (o == null) return false;
    return dt < _ringReachMs(haversineM(o, w.positionAt(s, w.lastScanAt)));
  }

  bool _pendingCell(String id, int scannedAt, LatLng center, int now) {
    final w = app.world;
    if (scannedAt != w.lastScanAt) return false;
    final dt = now - scannedAt;
    if (dt < 0 || dt >= WorldController.scanDurationMs) return false;
    if (_preScanCells.contains(id)) return false;
    final o = w.lastScanOrigin;
    if (o == null) return false;
    // El anillo toca la habitación antes de llegar a su centro.
    return dt < _ringReachMs(math.max(0, haversineM(o, center) - 110));
  }

  void _startPulse() {
    final c = _map;
    final o = app.world.lastScanOrigin ?? app.location.position;
    if (c == null || !_styleReady || o == null) return;
    _preScanSpawns = Set.of(_shownSpawns);
    _preScanCells = Set.of(_shownCells);
    _pendingSpawns = -1;
    _pendingCellsCount = -1;
    _ringLat = o.lat;
    _lastRingPush = 0;
    c.setGeoJsonSource(_Src.scan, featureCollection([pointFeature(o, const {})]));
    if (!_ticker.isActive) _ticker.start();
    _bump();
  }

  void _onFrame(Duration _) {
    final c = _map;
    if (c == null || !_styleReady) return;
    final now = _now;
    final w = app.world;
    final dt = now - w.lastScanAt;
    const total = WorldController.scanDurationMs + _pulseEchoDelayMs + 40;
    if (dt < 0 || dt > total) {
      _setRing(_Lyr.scanA, -1, 0);
      _setRing(_Lyr.scanB, -1, 0);
      _ticker.stop();
      _markDirty(const [_Src.marks, _Src.cells]);
      return;
    }
    // ~30 fps para los anillos.
    if (now - _lastRingPush >= 33) {
      _lastRingPush = now;
      _setRing(_Lyr.scanA, dt, 1);
      _setRing(_Lyr.scanB, dt - _pulseEchoDelayMs, 0.45);
    }
    // Revelado escalonado: contar contactos/habitaciones todavía pendientes.
    final pos = app.location.position;
    final o = w.lastScanOrigin;
    var spawns = 0;
    var cells = 0;
    if (o != null) {
      for (final s in w.drawable) {
        if (haversineM(o, w.positionAt(s, w.lastScanAt)) > WorldController.scanRadiusM) continue;
        if (_pendingSpawn(s, w.visibilityOf(s, pos, now), now)) spawns++;
      }
      for (final e in w.scannedCells.entries) {
        if (_pendingCell(e.key, e.value, cellCenter(parseCellId(e.key)), now)) cells++;
      }
    }
    if (spawns != _pendingSpawns || cells != _pendingCellsCount) {
      if (_pendingSpawns > spawns) {
        if (now - _lastHaptic > 70) {
          _lastHaptic = now;
          HapticFeedback.selectionClick();
        }
        // El frente de onda alcanzó un contacto: ping suave (con límite).
        if (now - _lastPing > 140) {
          _lastPing = now;
          Sfx.play(SfxId.contactPing, volume: 0.35);
        }
      }
      _pendingSpawns = spawns;
      _pendingCellsCount = cells;
      _markDirty(const [_Src.marks, _Src.cells]);
    }
  }

  /// Anillo de `t` ms (negativo = oculto). Radio en metros convertido a píxeles
  /// con una interpolación exponencial base 2 sobre el zoom (exacta).
  void _setRing(String layer, int t, double strength) {
    final c = _map;
    if (c == null) return;
    final p = (t / WorldController.scanDurationMs).clamp(0.0, 1.0);
    final k = t <= 0 ? 0.0 : Sutura.scanCurve.transform(p);
    final meters = WorldController.scanRadiusM * k;
    final fade = t <= 0 ? 0.0 : math.pow(1 - p, 1.3).toDouble();
    final appear = (t / 90).clamp(0.0, 1.0);
    c
        .setLayerProperties(
          layer,
          _RawProps({
            'circle-radius': _metersToPx(_ringLat, meters),
            'circle-opacity': 0.09 * strength * fade * appear,
            'circle-stroke-opacity': 0.55 * strength * fade * appear,
          }),
        )
        .catchError((Object e) => debugPrint('[Zona Cero] pulso: $e'));
  }

  static List<Object> _metersToPx(double lat, double meters) {
    final ground = 40075016.686 * math.cos(lat * math.pi / 180);
    double px(int z) => meters / (ground / (512 * math.pow(2, z)));
    return ['interpolate', ['exponential', 2], ['zoom'], 10, px(10), 22, px(22)];
  }

  /// Igual que [_metersToPx] pero con los metros de una propiedad del feature.
  static List<Object> _metersToPxExpr(double lat, Object meters) {
    final ground = 40075016.686 * math.cos(lat * math.pi / 180);
    double k(int z) => 512 * math.pow(2, z) / ground;
    return ['interpolate', ['exponential', 2], ['zoom'], 10, ['*', meters, k(10)], 22, ['*', meters, k(22)]];
  }

  /// "Golpe" de cámara al disparar el pulso: un acercamiento breve y vuelta.
  void _bump() {
    final c = _map;
    final cam = _cam;
    if (c == null || cam == null || _intro || _pointers > 0) return;
    final z0 = _bumpZoom ?? cam.zoom;
    _bumpZoom = z0;
    _bumpUntil = _now + 700;
    _bumpTimer?.cancel();
    c.animateCamera(ml.CameraUpdate.zoomTo(z0 + 0.14), duration: const Duration(milliseconds: 110));
    _bumpTimer = Timer(const Duration(milliseconds: 140), () {
      _map?.animateCamera(ml.CameraUpdate.zoomTo(z0), duration: const Duration(milliseconds: 460));
      _bumpTimer = Timer(const Duration(milliseconds: 520), () => _bumpZoom = null);
    });
  }

  // ---------------------------------------------------------------------------
  // Escuchas del estado
  // ---------------------------------------------------------------------------

  void _onLocation() {
    final p = app.location.position;
    _markDirty(const [_Src.player, _Src.reach, _Src.marks, _Src.cells, _Src.infect]);
    if (p == null) return;
    if (!_introDone) {
      _maybeIntro();
      return;
    }
    final last = _lastFix;
    if (last == p) return;
    _lastFix = p;
    if (widget.controller.follow && !_intro) {
      final jump = last == null || haversineM(last, p) > 150;
      _moveCameraTo(p, animate: !jump && app.location.mode != LocationMode.demo);
    }
  }

  void _onWorld() {
    final w = app.world;
    if (w.lastScanAt != _seenScanAt) {
      _seenScanAt = w.lastScanAt;
      if (_now - w.lastScanAt < WorldController.scanDurationMs) _startPulse();
    }
    final sel = w.selectedId;
    if (sel != _lastSel) {
      final external = sel != null && sel != _selfSel;
      _lastSel = sel;
      _selfSel = null;
      if (sel != null) Sfx.play(w.signalById(sel) != null ? SfxId.signal : SfxId.open, volume: 0.8);
      // Selección hecha desde afuera del mapa (p. ej. "VER EN EL MAPA" del
      // nodo): llevar la cámara hasta el objetivo.
      if (external) {
        final p = _positionOf(sel);
        if (p != null) _focus(p);
      }
    }
    _markDirty(const [_Src.marks, _Src.cells, _Src.sutures, _Src.infect]);
    if (w.spawns.any((s) => s.placement == PlacementState.raw)) {
      _placeDebounce?.cancel();
      _placeDebounce = Timer(const Duration(milliseconds: 350), () => unawaited(_maybePlace(force: true)));
    }
  }

  void _onApp() => _markDirty(const [_Src.marks, _Src.sutures]);

  LatLng? _positionOf(String id) {
    final w = app.world;
    final s = w.spawnById(id);
    if (s != null) return w.positionAt(s, _now);
    return w.shelterById(id)?.position ?? w.signalById(id)?.position;
  }

  // ---------------------------------------------------------------------------
  // Entrada: de la ciudad al jugador
  // ---------------------------------------------------------------------------

  void _maybeIntro() {
    if (_introDone || _intro || !_styleReady) return;
    final p = app.location.position;
    final c = _map;
    if (p == null || c == null) return;
    _intro = true;
    _markFade = 0;
    _lastFix = p;
    widget.controller._setIntro(true);
    widget.controller._setFollow(true);
    c.moveCamera(ml.CameraUpdate.newCameraPosition(
      ml.CameraPosition(target: _ll(_introFrom(p)), zoom: kIntroZoom, tilt: kIntroPitch, bearing: kIntroBearing),
    ));
    // Un instante sobre la ciudad (cargan las teselas lejanas) y a volar.
    _introTimer = Timer(const Duration(milliseconds: 500), () {
      final to = app.location.position ?? p;
      _map?.animateCamera(
        ml.CameraUpdate.newCameraPosition(ml.CameraPosition(target: _ll(to), zoom: kMapZoom, tilt: 0, bearing: 0)),
        duration: const Duration(milliseconds: kIntroMs),
      );
      _introTimer = Timer(const Duration(milliseconds: kIntroMs + 150), () => _endIntro());
    });
  }

  void _endIntro({bool aborted = false}) {
    if (!_intro) return;
    _introTimer?.cancel();
    _intro = false;
    _introDone = true;
    widget.controller._setIntro(false);
    final p = app.location.position;
    if (!aborted && p != null) {
      widget.controller._setFollow(true);
      _lastFix = p;
      final cam = _cam;
      // Si el jugador se movió durante el vuelo, alcanzarlo.
      if (cam != null && haversineM(_core(cam.target), p) > 3) {
        _moveCameraTo(p, animate: true);
      } else {
        _segA = p;
        _segB = p;
      }
    }
    // Los marcadores aparecen después de llegar.
    _fadeTimer?.cancel();
    final t0 = _now;
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 90), (t) {
      _markFade = Curves.easeOut.transform(((_now - t0) / 750).clamp(0.0, 1.0));
      _markDirty(const [_Src.marks]);
      if (_markFade >= 1) t.cancel();
    });
    _ambient.start(_now);
  }

  // ---------------------------------------------------------------------------
  // Cámara
  // ---------------------------------------------------------------------------

  void _moveCameraTo(LatLng p, {required bool animate}) {
    final c = _map;
    if (c == null) return;
    final cam = _camera ?? c.cameraPosition;
    _segA = cam != null ? _core(cam.target) : p;
    _segB = p;
    // Durante el "golpe" del escáner, moverse también restituye el zoom.
    final z0 = _bumpZoom;
    final update = z0 != null && _now < _bumpUntil && cam != null
        ? ml.CameraUpdate.newCameraPosition(ml.CameraPosition(target: _ll(p), zoom: z0, tilt: cam.tilt, bearing: cam.bearing))
        : ml.CameraUpdate.newLatLng(_ll(p));
    if (animate) {
      c.animateCamera(update, duration: const Duration(milliseconds: 650));
    } else {
      c.moveCamera(update);
    }
  }

  void _onCameraMove(ml.CameraPosition cp) {
    _camera = cp;
    widget.controller._setCamera(cp.bearing, cp.zoom, cp.target.latitude);
    // Las etiquetas dependen de la escala y el rumbo: recalcular si cambiaron bastante.
    final db = ((cp.bearing - _labelBearing + 540) % 360 - 180).abs();
    if ((cp.zoom - _labelZoom).abs() > 0.4 || db > 15) {
      _labelZoom = cp.zoom;
      _labelBearing = cp.bearing;
      _markDirty(const [_Src.marks]);
    }
    if (_intro || !widget.controller.follow) return;
    final b = _segB;
    if (b == null) return;
    // Si la cámara se aparta del recorrido que le pedimos, la movió el usuario.
    if (_distToSegmentM(_core(cp.target), _segA ?? b, b) > 18) widget.controller._setFollow(false);
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers++;
    _downAt = _pointers == 1 ? e.position : null;
  }

  void _onPointerMove(PointerMoveEvent e) {
    final d = _downAt;
    if (d != null && (e.position - d).distance > 14) {
      _downAt = null;
      // Arrastrar durante la entrada la corta: el mapa queda donde lo dejó.
      if (_intro) _endIntro(aborted: true);
      widget.controller._setFollow(false);
    }
  }

  void _onPointerEnd(PointerEvent e) {
    _pointers = math.max(0, _pointers - 1);
    if (_pointers == 0) _downAt = null;
  }

  ml.CameraPosition? get _cam => _camera ?? _map?.cameraPosition;

  void _recenter() {
    if (_intro) _endIntro();
    widget.controller._setFollow(true);
    final c = _map;
    final p = app.location.position;
    if (c == null || p == null) return;
    final cam = _cam;
    _segA = cam != null ? _core(cam.target) : p;
    _segB = p;
    c.animateCamera(
      ml.CameraUpdate.newCameraPosition(ml.CameraPosition(
        target: _ll(p),
        zoom: math.max(cam?.zoom ?? kMapZoom, 15.5),
        tilt: widget.controller.pitched ? kMapPitch : 0,
        bearing: cam?.bearing ?? 0,
      )),
      duration: const Duration(milliseconds: 500),
    );
  }

  void _focus(LatLng p, {String? select}) {
    if (_intro) _endIntro(aborted: true);
    widget.controller._setFollow(false);
    if (select != null) {
      _selfSel = select;
      app.world.select(select);
    }
    final c = _map;
    if (c == null) return;
    final cam = _cam;
    final far = cam == null || haversineM(_core(cam.target), p) > 2500;
    c.animateCamera(
      ml.CameraUpdate.newCameraPosition(ml.CameraPosition(
        target: _ll(p),
        zoom: cam == null || far ? 15.8 : math.max(cam.zoom, 15.5),
        tilt: cam?.tilt ?? 0,
        bearing: cam?.bearing ?? 0,
      )),
      duration: Duration(milliseconds: far ? 1100 : 600),
    );
  }

  void _resetNorth() {
    final c = _map;
    final cam = _cam;
    if (c == null || cam == null || _intro) return;
    widget.controller._setPitched(false);
    final p = app.location.position;
    final target = widget.controller.follow && p != null ? _ll(p) : cam.target;
    _segA = _core(cam.target);
    _segB = _core(target);
    c.animateCamera(
      ml.CameraUpdate.newCameraPosition(ml.CameraPosition(target: target, zoom: cam.zoom, tilt: 0, bearing: 0)),
      duration: const Duration(milliseconds: 400),
    );
  }

  void _zoomBy(double delta) {
    final c = _map;
    if (c == null) return;
    if (_intro) _endIntro(aborted: true);
    c.animateCamera(ml.CameraUpdate.zoomBy(delta), duration: const Duration(milliseconds: 260));
  }

  void _togglePitch() {
    if (_intro) return;
    final next = !widget.controller.pitched;
    widget.controller._setPitched(next);
    final c = _map;
    if (c == null) return;
    final cam = _cam;
    final p = app.location.position;
    final target = widget.controller.follow && p != null ? p : (cam != null ? _core(cam.target) : p);
    if (target == null) return;
    _segA = cam != null ? _core(cam.target) : target;
    _segB = target;
    c.animateCamera(
      ml.CameraUpdate.newCameraPosition(ml.CameraPosition(
        target: _ll(target),
        zoom: cam?.zoom ?? kMapZoom,
        tilt: next ? kMapPitch : 0,
        bearing: cam?.bearing ?? 0,
      )),
      duration: const Duration(milliseconds: 500),
    );
  }

  void _onLongPress(math.Point<double> point, ml.LatLng ll) {
    final demo = app.location.demo;
    if (demo == null) return;
    HapticFeedback.mediumImpact();
    if (_intro) _endIntro();
    widget.controller._setFollow(true);
    demo.teleport(_core(ll));
  }

  Future<String?> _nearestPlace() async {
    final c = _map;
    final cam = _cam;
    final around = app.location.position ?? (cam != null ? _core(cam.target) : null);
    if (c == null || !_styleReady || around == null || kIsWeb) return null;
    return queryNearestPlace(c, around);
  }

  // ---------------------------------------------------------------------------
  // Ubicación de spawns sobre calles públicas
  // ---------------------------------------------------------------------------

  /// Fuente síncrona para el mundo: los últimos datos de calles, si siguen
  /// cubriendo la zona del jugador.
  PlacementData? _placementFor() {
    final data = _placement;
    final c = _placementCenter;
    final p = app.location.position;
    if (data == null || c == null || p == null || haversineM(c, p) > 250) return null;
    return data;
  }

  Future<void> _maybePlace({bool force = false}) async {
    final c = _map;
    final cam = _cam;
    if (c == null || !_styleReady || _placing || _intro || cam == null || cam.zoom < 14) return;
    final now = _now;
    final minGap = _emptyQueries >= 3 ? 10000 : 1500;
    if (!force && now - _lastPlaceAt < minGap) return;
    if (force && now - _lastPlaceAt < (_emptyQueries >= 3 ? 10000 : 400)) return;
    _placing = true;
    try {
      final region = await c.getVisibleRegion();
      bool inView(LatLng p) =>
          p.lat >= region.southwest.latitude &&
          p.lat <= region.northeast.latitude &&
          p.lng >= region.southwest.longitude &&
          p.lng <= region.northeast.longitude;
      final around = app.location.position ?? _core(cam.target);
      final needs = _placement == null ||
          _placementCenter == null ||
          haversineM(_placementCenter!, around) > 250 ||
          app.world.spawns.any((s) => s.placement == PlacementState.raw && inView(s.position));
      if (!needs) return;
      _lastPlaceAt = now;
      final data = await queryPlacementData(c, around: around);
      if (!mounted) return;
      if (data == null) {
        _emptyQueries++;
        return;
      }
      _emptyQueries = 0;
      _placement = data;
      _placementCenter = around;
      app.world.applyPlacement(data, inView: inView);
      // Nombres de calle para los avisos ambientales (solo Android/iOS).
      if (!kIsWeb) {
        final streets = await queryStreetNames(c, around);
        if (mounted && streets.isNotEmpty) _streets = streets;
      }
    } on PlacementNotReady {
      // Tiles todavía cargando: reintentar en un momento.
      _lastPlaceAt = 0;
      _placeDebounce?.cancel();
      _placeDebounce = Timer(const Duration(milliseconds: 1200), () => unawaited(_maybePlace(force: true)));
    } catch (e) {
      debugPrint('[Zona Cero] Ubicación en calles no disponible: $e');
    } finally {
      _placing = false;
    }
  }
}

// -----------------------------------------------------------------------------
// Utilidades
// -----------------------------------------------------------------------------

ml.LatLng _ll(LatLng p) => ml.LatLng(p.lat, p.lng);
LatLng _core(ml.LatLng p) => LatLng(p.latitude, p.longitude);

double _distToSegmentM(LatLng p, LatLng a, LatLng b) {
  final pa = toLocalXY(p, a);
  final pb = toLocalXY(p, b);
  final q = nearestPointOnSegment(const XY(0, 0), pa, pb);
  return math.sqrt(q.x * q.x + q.y * q.y);
}
