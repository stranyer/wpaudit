import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../core/core.dart';
import '../state/app_state.dart';
import '../state/location_controller.dart';
import '../state/world_controller.dart';
import '../ui/theme/tokens.dart';
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

/// Distancia (px lógicos) desde el borde inferior del mapa hasta la atribución
/// de OpenStreetMap: queda justo encima de la columna de controles de la derecha.
const kMapAttributionBottom = 392.0;

/// Estado de cámara que la interfaz necesita (seguir al jugador, rumbo para la
/// brújula y el joystick, zoom y latitud para la escala) y acciones (recentrar,
/// norte arriba, zoom, enfocar un objetivo).
class GameMapController extends ChangeNotifier {
  bool _follow = true;
  bool _pitched = false;
  double _bearing = 0;
  double _zoom = kMapZoom;
  double? _lat;
  _GameMapState? _state;

  /// La cámara sigue al jugador. Se apaga al arrastrar el mapa o al enfocar un objetivo.
  bool get follow => _follow;

  /// Vista inclinada (45°) o cenital (0°).
  bool get pitched => _pitched;

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

  void _setCamera(double bearing, double zoom, double lat) {
    final changed = (bearing - _bearing).abs() > 0.5 || (zoom - _zoom).abs() > 0.01 || _lat == null || (lat - _lat!).abs() > 0.002;
    _bearing = bearing;
    _zoom = zoom;
    _lat = lat;
    if (changed) notifyListeners();
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
  static const all = [cells, infect, reach, sutures, marks, player];
}

abstract final class _Lyr {
  static const bgTex = 'bg-tex';
  static const canopy = 'canopy';
  static const canopyPark = 'canopy-park';
  static const building = 'building';
  static const metro = 'metro-label';
  static const cellsFill = 'zc-cells-fill';
  static const cellsLine = 'zc-cells-line';
  static const infect = 'zc-infect-heat';
  static const reach = 'zc-reach-line';
  static const sutures = 'zc-sutures-line';
  static const scanA = 'zc-scan-a';
  static const scanB = 'zc-scan-b';
  static const pulse = 'zc-signal-pulse';
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
      {this.subtitle, this.echo = false, this.own = false, this.mortal = false, required this.z, this.weight = 1});
  final String id;
  final LatLng position;
  final MarkKind kind;
  final String title;
  final String? subtitle;
  final bool echo;
  final bool own;
  final bool mortal;
  final int z;
  final double weight;
}

/// Mapa del juego: MapLibre con el estilo ZONA CERO y los overlays GeoJSON
/// (habitaciones escaneadas, contagio, alcance, red de relevo, pulso del
/// escáner, marcadores y jugador). Escucha directamente a `app.location`,
/// `app.world` y `app`, y actualiza fuentes (máximo 10 por segundo) sin
/// reconstruir el widget del mapa.
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
  List<LatLng> _clusters = const [];

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
  double _ringLat = 0;

  // Latido de las señales de auxilio
  late final Ticker _pulseTicker = createTicker(_onPulse);
  int _lastPulsePush = 0;

  // Ubicación de spawns en calles
  PlacementData? _placement;
  LatLng? _placementCenter;
  int _lastPlaceAt = 0;
  int _emptyQueries = 0;
  bool _placing = false;
  Timer? _placeDebounce;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    _seenScanAt = app.world.lastScanAt;
    _lastFix = app.location.position;
    _lastSel = app.world.selectedId;
    app.location.addListener(_onLocation);
    app.world.addListener(_onWorld);
    app.addListener(_onApp);
    app.world.placementSource = _placementFor;
    installMapWebTweaks(kMapAttributionBottom);
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
    if (app.world.placementSource == _placementFor) app.world.placementSource = null;
    _flushTimer?.cancel();
    _placeDebounce?.cancel();
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
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: ml.MapLibreMap(
        styleString: _style,
        initialCameraPosition: ml.CameraPosition(target: _ll(start), zoom: kMapZoom),
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
        minMaxZoomPreference: const ml.MinMaxZoomPreference(13, 19.5),
        annotationOrder: const [],
        logoEnabled: false,
        // Atribución OSM a la derecha, justo encima de la columna de controles
        // (márgenes en píxeles físicos).
        attributionButtonPosition: ml.AttributionButtonPosition.bottomRight,
        attributionButtonMargins: math.Point((14 * dpr).round(), (kMapAttributionBottom * dpr).round()),
        gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Estilo, imágenes y capas
  // ---------------------------------------------------------------------------

  Future<void> _onStyleLoaded() async {
    final c = _map;
    if (c == null || !mounted) return;
    final gen = ++_styleGen;
    _styleReady = false;
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
    final p = app.location.position;
    if (p != null && widget.controller.follow) _moveCameraTo(p, animate: false);
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

  /// Capas del mapa base que usan imágenes: textura del suelo, copas de árboles
  /// en plazas, techos y estaciones de subte. Van sobre las anclas del estilo.
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
            iconImage: SuturaMapStyle.metroIcon,
            iconSize: _iconBase,
            textField: SuturaMapStyle.stationName,
            textFont: const ['Noto Sans Regular'],
            textSize: 11.5,
            textLetterSpacing: 0.06,
            textAnchor: 'top',
            textOffset: const [0, 1.05],
            textPadding: 4,
            textOptional: true,
            textColor: '#DDE0E1',
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
    const casing = SuturaMapStyle.roadCasingLayer;
    const label = SuturaMapStyle.labelLayer;
    const steel = '#8DB4C9';
    const amber = '#D9A233';
    final lat = app.location.position?.lat ?? gameConfig.demo.start.lat;

    // Habitaciones escaneadas (debajo de las calles, apenas teñidas).
    await c.addFillLayer(
      _Src.cells,
      _Lyr.cellsFill,
      const ml.FillLayerProperties(
        fillColor: ['match', ['get', 'st'], 'loot', amber, steel],
        fillOpacity: ['match', ['get', 'st'], 'loot', 0.045, 0.025],
      ),
      belowLayerId: casing,
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

    // Contagio: mancha roja difusa sobre las zonas infestadas.
    await c.addHeatmapLayer(
      _Src.infect,
      _Lyr.infect,
      ml.HeatmapLayerProperties(
        heatmapRadius: _metersToPx(lat, 165),
        heatmapWeight: 1,
        heatmapIntensity: 1.5,
        heatmapColor: const [
          'interpolate',
          ['linear'],
          ['heatmap-density'],
          0,
          'rgba(150,20,16,0)',
          0.12,
          'rgba(150,20,16,0)',
          0.22,
          'rgba(160,26,20,0.24)',
          0.38,
          'rgba(176,30,24,0.36)',
          0.7,
          'rgba(192,38,30,0.46)',
          1,
          'rgba(205,46,36,0.52)',
        ],
        heatmapOpacity: 1,
      ),
      belowLayerId: label,
    );

    // Alcance de interacción: círculo fino y claro.
    await c.addLineLayer(
      _Src.reach,
      _Lyr.reach,
      const ml.LineLayerProperties(lineColor: '#D8E0E4', lineWidth: 1.1, lineOpacity: 0.55),
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

    // Pulso del escáner: dos anillos sobre el suelo.
    for (final id in [_Lyr.scanB, _Lyr.scanA]) {
      await c.addCircleLayer(
        _Src.scan,
        id,
        ml.CircleLayerProperties(
          circleRadius: 0,
          circleColor: steel,
          circleOpacity: 0,
          circleStrokeColor: steel,
          circleStrokeWidth: id == _Lyr.scanA ? 2.2 : 1.2,
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

    // Marcadores: insignia + mástil + etiqueta horneada; la distancia, como texto.
    await c.addSymbolLayer(
      _Src.marks,
      _Lyr.marks,
      ml.SymbolLayerProperties(
        iconImage: ['get', 'icon'],
        iconSize: _iconBase,
        iconAnchor: 'bottom-left',
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
        textAnchor: 'bottom-left',
        textJustify: 'left',
        textOffset: ['get', 'toff'],
        textLetterSpacing: 0.06,
        textAllowOverlap: true,
        textIgnorePlacement: false,
        textOpacity: ['get', 'op'],
        textColor: '#E2DFD8',
        textHaloColor: '#0A0B0C',
        textHaloWidth: 1,
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

  Json? _buildInfect() {
    final zones = app.world.zones;
    return _diff(_Src.infect, contagionKey(zones), () => infestedHeatCollection(zones));
  }

  List<LatLng> _clusterCenters() {
    final key = contagionKey(app.world.zones);
    if (key != _clusterKey) {
      _clusterKey = key;
      _clusters = infestedClusterCenters(app.world.zones);
    }
    return _clusters;
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
    for (final s in w.drawable) {
      if (far(s.position, _markerRadiusM)) continue;
      final v = w.visibilityOf(s, pos, now);
      if (v == SpawnVisibility.hidden || _pendingSpawn(s, v, now)) continue;
      shown.add(s.id);
      final echo = v == SpawnVisibility.echo;
      switch (s) {
        case ZombieSpawn z:
          final def = zombieDefs[z.zombieType]!;
          marks.add(_Mark(s.id, s.position, MarkKind.zombie, echo ? 'Hostil' : def.name,
              echo: echo, mortal: threatRating(def, level) >= 3, z: 50));
        case SupplySpawn _:
          marks.add(_Mark(s.id, s.position, MarkKind.supply, 'Saqueo', echo: echo, z: 40));
      }
    }
    _shownSpawns = shown;
    for (final sig in w.signals) {
      if (far(sig.position, _signalRadiusM)) continue;
      marks.add(_Mark(sig.id, sig.position, MarkKind.signal, 'Señal de auxilio', z: 60, weight: 0.9));
    }
    for (final n in w.shelters) {
      final own = n.id == ownId;
      marks.add(_Mark(n.id, n.position, MarkKind.node, 'Refugio', subtitle: shelterShortName(n.name), own: own, z: own ? 35 : 30));
    }
    for (final c in _clusterCenters()) {
      if (far(c, _signalRadiusM)) continue;
      marks.add(_Mark('zone:${cellId(cellOf(c))}', c, MarkKind.zone, 'Zona infectada', z: 20, weight: 1.35));
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
            LabelCandidate(m.id, m.position, haversineM(pos, m.position), weight: m.weight, width: _labelWidth(m)),
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
    final sig = StringBuffer();
    var signals = false;
    for (final m in marks) {
      final isLabelled = labelled.contains(m.id);
      final state = m.id == sel ? MarkerState.sel : (m.echo ? MarkerState.echo : MarkerState.on);
      final spec = MarkSpec(
        m.kind,
        state,
        title: isLabelled ? m.title : '',
        subtitle: isLabelled ? m.subtitle : null,
        labelled: isLabelled,
        own: m.own,
        mortal: m.mortal,
      );
      if (!_ensureImage(spec)) continue;
      final icon = spec.name;
      final dist = isLabelled && pos != null ? distanceLabel(haversineM(pos, m.position)) : '';
      final op = m.echo ? 0.7 : 1.0;
      final z = m.id == sel ? 100 : m.z;
      if (m.kind == MarkKind.signal) signals = true;
      sig
        ..write(m.id)
        ..write(icon)
        ..write(dist)
        ..write(z)
        ..write(m.position.lat)
        ..write(m.position.lng)
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
          'toff': isLabelled ? MapIcons.distanceOffset(spec.bakedLines) : const [0.0, 0.0],
        },
        id: m.id,
      ));
    }
    _setPulse(signals);
    return _diff(_Src.marks, sig.toString(), () => featureCollection(feats));
  }

  /// Ancho aproximado (px) de la etiqueta de un marcador, para evitar choques.
  static double _labelWidth(_Mark m) =>
      22 + math.max(m.title.length * 7.6, math.max((m.subtitle?.length ?? 0) * 6.4, 46));

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

  // ---------------------------------------------------------------------------
  // Latido de las señales
  // ---------------------------------------------------------------------------

  void _setPulse(bool on) {
    if (on && !_pulseTicker.isActive) _pulseTicker.start();
    if (!on && _pulseTicker.isActive) {
      _pulseTicker.stop();
      _map?.setLayerProperties(_Lyr.pulse, const _RawProps({'circle-stroke-opacity': 0})).catchError((_) {});
    }
  }

  void _onPulse(Duration _) {
    final c = _map;
    final now = _now;
    // ~9 cuadros por segundo alcanzan para un latido suave (cada uno es una llamada al mapa).
    if (c == null || !_styleReady || now - _lastPulsePush < 110) return;
    _lastPulsePush = now;
    const period = 2000;
    final t = (now % period) / period;
    final k = Curves.easeOut.transform(t);
    c
        .setLayerProperties(
          _Lyr.pulse,
          _RawProps({
            'circle-radius': 4 + 26 * k,
            'circle-stroke-opacity': 0.75 * (1 - t),
          }),
        )
        .catchError((Object e) => debugPrint('[Zona Cero] latido: $e'));
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
    return dt < _ringReachMs(haversineM(o, s.position));
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
        if (haversineM(o, s.position) > WorldController.scanRadiusM) continue;
        if (_pendingSpawn(s, w.visibilityOf(s, pos, now), now)) spawns++;
      }
      for (final e in w.scannedCells.entries) {
        if (_pendingCell(e.key, e.value, cellCenter(parseCellId(e.key)), now)) cells++;
      }
    }
    if (spawns != _pendingSpawns || cells != _pendingCellsCount) {
      if (_pendingSpawns > spawns && now - _lastHaptic > 70) {
        _lastHaptic = now;
        HapticFeedback.selectionClick();
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
            'circle-opacity': 0.10 * strength * fade * appear,
            'circle-stroke-opacity': 0.95 * strength * fade * appear,
          }),
        )
        .catchError((Object e) => debugPrint('[Zona Cero] pulso: $e'));
  }

  static List<Object> _metersToPx(double lat, double meters) {
    final ground = 40075016.686 * math.cos(lat * math.pi / 180);
    double px(int z) => meters / (ground / (512 * math.pow(2, z)));
    return ['interpolate', ['exponential', 2], ['zoom'], 10, px(10), 22, px(22)];
  }

  // ---------------------------------------------------------------------------
  // Escuchas del estado
  // ---------------------------------------------------------------------------

  void _onLocation() {
    final p = app.location.position;
    _markDirty(const [_Src.player, _Src.reach, _Src.marks, _Src.cells]);
    if (p == null) return;
    final last = _lastFix;
    if (last == p) return;
    _lastFix = p;
    if (widget.controller.follow) {
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
    // Selección hecha desde afuera del mapa (p. ej. "VER EN EL MAPA" del nodo):
    // llevar la cámara hasta el objetivo.
    final sel = w.selectedId;
    if (sel != _lastSel) {
      final external = sel != null && sel != _selfSel;
      _lastSel = sel;
      _selfSel = null;
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
    return w.spawnById(id)?.position ?? w.shelterById(id)?.position ?? w.signalById(id)?.position;
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
    if (animate) {
      c.animateCamera(ml.CameraUpdate.newLatLng(_ll(p)), duration: const Duration(milliseconds: 650));
    } else {
      c.moveCamera(ml.CameraUpdate.newLatLng(_ll(p)));
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
    if (!widget.controller.follow) return;
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
      widget.controller._setFollow(false);
    }
  }

  void _onPointerEnd(PointerEvent e) {
    _pointers = math.max(0, _pointers - 1);
    if (_pointers == 0) _downAt = null;
  }

  ml.CameraPosition? get _cam => _camera ?? _map?.cameraPosition;

  void _recenter() {
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
    if (c == null || cam == null) return;
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
    c.animateCamera(ml.CameraUpdate.zoomBy(delta), duration: const Duration(milliseconds: 260));
  }

  void _togglePitch() {
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
    if (c == null || !_styleReady || _placing || cam == null || cam.zoom < 14) return;
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
