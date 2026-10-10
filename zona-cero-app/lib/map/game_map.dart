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
import 'map_style.dart';
import 'placement_query.dart';

/// Cámara por defecto: inclinada, cerca del suelo.
const kMapZoom = 16.6;
const kMapPitch = 45.0;

/// Estado de cámara que la interfaz necesita (seguir al jugador, inclinación,
/// rumbo para el joystick) y acciones (recentrar, alternar 3D).
class GameMapController extends ChangeNotifier {
  bool _follow = true;
  bool _pitched = true;
  double _bearing = 0;
  _GameMapState? _state;

  /// La cámara sigue al jugador. Se apaga al arrastrar el mapa.
  bool get follow => _follow;

  /// Vista inclinada (45°) o cenital (0°).
  bool get pitched => _pitched;

  /// Rumbo de la cámara en grados (0 = norte arriba, sentido horario).
  double get bearing => _bearing;

  void recenter() => _state?._recenter();
  void togglePitch() => _state?._togglePitch();

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
}

abstract final class _Src {
  static const grid = 'zc-grid';
  static const cells = 'zc-cells';
  static const contagion = 'zc-contagion';
  static const reach = 'zc-reach';
  static const sutures = 'zc-sutures';
  static const scan = 'zc-scan';
  static const nodes = 'zc-nodes';
  static const spawns = 'zc-spawns';
  static const player = 'zc-player';
  static const all = [grid, cells, contagion, reach, sutures, nodes, spawns, player];
}

abstract final class _Lyr {
  static const cellsFill = 'zc-cells-fill';
  static const cellsLine = 'zc-cells-line';
  static const grid = 'zc-grid-line';
  static const contagionFill = 'zc-contagion-fill';
  static const contagionLine = 'zc-contagion-line';
  static const reachFill = 'zc-reach-fill';
  static const reachLine = 'zc-reach-line';
  static const sutures = 'zc-sutures-line';
  static const scanA = 'zc-scan-a';
  static const scanB = 'zc-scan-b';
  static const nodes = 'zc-nodes-sym';
  static const spawns = 'zc-spawns-sym';
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

/// Mapa del juego: MapLibre con el estilo SUTURA y los overlays GeoJSON
/// (grilla, contagio, habitaciones escaneadas, alcance, red de relevo, pulso del
/// escáner, nodos, contactos y jugador). Escucha directamente a `app.location`,
/// `app.world` y `app`, y actualiza fuentes (máximo 10 por segundo) sin
/// reconstruir el widget del mapa.
class GameMap extends StatefulWidget {
  const GameMap({super.key, required this.controller});

  final GameMapController controller;

  @override
  State<GameMap> createState() => _GameMapState();
}

class _GameMapState extends State<GameMap> with SingleTickerProviderStateMixin {
  static const _markerRadiusM = 720.0;
  static const _pulseEchoDelayMs = 180;

  ml.MapLibreMapController? _map;
  bool _styleReady = false;
  int _styleGen = 0;
  double _iconBase = 1;
  late final String _style = SuturaMapStyle.build();

  // Cámara
  ml.CameraPosition? _camera;
  LatLng? _segA;
  LatLng? _segB;
  LatLng? _lastFix;
  Offset? _downAt;
  int _pointers = 0;

  // Fuentes
  final Map<String, String> _sig = {};
  final Set<String> _dirty = {};
  Timer? _flushTimer;
  int _lastFlushAt = 0;
  Set<String> _shownSpawns = {};
  Set<String> _shownCells = {};

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
    app.location.addListener(_onLocation);
    app.world.addListener(_onWorld);
    app.addListener(_onApp);
    app.world.placementSource = _placementFor;
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
    _map = null;
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Widget
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final start = app.location.position ?? app.demoPosition ?? gameConfig.demo.start;
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: ml.MapLibreMap(
        styleString: _style,
        initialCameraPosition: ml.CameraPosition(target: _ll(start), zoom: kMapZoom, tilt: kMapPitch),
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
        doubleClickZoomEnabled: false,
        minMaxZoomPreference: const ml.MinMaxZoomPreference(13, 19.5),
        annotationOrder: const [],
        logoEnabled: false,
        attributionButtonPosition: ml.AttributionButtonPosition.topLeft,
        attributionButtonMargins: const math.Point(6, 150),
        gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Estilo, fuentes y capas
  // ---------------------------------------------------------------------------

  Future<void> _onStyleLoaded() async {
    final c = _map;
    if (c == null || !mounted) return;
    final gen = ++_styleGen;
    _styleReady = false;
    _sig.clear();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    _iconBase = MapIcons.baseSize(dpr);
    try {
      await MapIcons.register(c, dpr);
      if (gen != _styleGen || !mounted) return;
      await _addOverlays(c);
    } catch (e, st) {
      debugPrint('[Zona Cero] No se pudieron crear los overlays del mapa: $e\n$st');
      return;
    }
    if (gen != _styleGen || !mounted) return;
    _styleReady = true;
    c.onFeatureTapped
      ..remove(_onFeatureTap)
      ..add(_onFeatureTap);
    _dirty.addAll(_Src.all);
    _flush();
    final p = app.location.position;
    if (p != null && widget.controller.follow) _moveCameraTo(p, animate: false);
    if (app.world.lastScanAt != _seenScanAt) _onWorld();
  }

  Future<void> _addOverlays(ml.MapLibreMapController c) async {
    for (final id in [..._Src.all, _Src.scan]) {
      await c.addGeoJsonSource(id, emptyCollection(), promoteId: id == _Src.spawns || id == _Src.nodes ? 'id' : null);
    }
    const road = SuturaMapStyle.roadLayer;
    const label = SuturaMapStyle.labelLayer;
    const signal = '#6ADBEA';
    const danger = '#EE3B45';

    // Habitaciones escaneadas (debajo de las calles).
    await c.addFillLayer(
      _Src.cells,
      _Lyr.cellsFill,
      const ml.FillLayerProperties(
        fillColor: ['match', ['get', 'st'], 'loot', '#5A2A2C', '#2F4A55'],
        fillOpacity: ['match', ['get', 'st'], 'loot', 0.45, 0.40],
      ),
      belowLayerId: road,
      enableInteraction: false,
    );
    await c.addLineLayer(
      _Src.cells,
      _Lyr.cellsLine,
      const ml.LineLayerProperties(
        lineColor: ['match', ['get', 'st'], 'loot', '#A3474D', '#4F7A8A'],
        lineWidth: 1,
        lineOpacity: 0.55,
      ),
      belowLayerId: road,
      enableInteraction: false,
    );

    // Grilla de 100 m.
    await c.addLineLayer(
      _Src.grid,
      _Lyr.grid,
      const ml.LineLayerProperties(
        lineColor: signal,
        lineWidth: 1,
        lineOpacity: ['case', ['get', 'major'], 0.075, 0.04],
      ),
      belowLayerId: label,
      enableInteraction: false,
    );

    // Contagio: relleno tenue + curvas de nivel.
    await c.addFillLayer(
      _Src.contagion,
      _Lyr.contagionFill,
      const ml.FillLayerProperties(fillColor: danger, fillOpacity: 0.06),
      belowLayerId: label,
      filter: ['==', ['get', 'k'], 'fill'],
      enableInteraction: false,
    );
    await c.addLineLayer(
      _Src.contagion,
      _Lyr.contagionLine,
      const ml.LineLayerProperties(
        lineColor: danger,
        lineWidth: ['match', ['get', 'lvl'], 2, 1.5, 1.1],
        lineOpacity: ['match', ['get', 'lvl'], 0, 0.32, 1, 0.55, 0.85],
        lineJoin: 'round',
        lineCap: 'round',
      ),
      belowLayerId: label,
      filter: ['==', ['get', 'k'], 'line'],
      enableInteraction: false,
    );

    // Alcance de interacción.
    await c.addFillLayer(
      _Src.reach,
      _Lyr.reachFill,
      const ml.FillLayerProperties(fillColor: signal, fillOpacity: 0.06),
      enableInteraction: false,
    );
    await c.addLineLayer(
      _Src.reach,
      _Lyr.reachLine,
      const ml.LineLayerProperties(lineColor: signal, lineWidth: 1, lineOpacity: 0.85, lineDasharray: [3, 2.5]),
      enableInteraction: false,
    );

    // Red de relevo.
    await c.addLineLayer(
      _Src.sutures,
      _Lyr.sutures,
      const ml.LineLayerProperties(
        lineColor: signal,
        lineWidth: 1,
        lineOpacity: ['case', ['get', 'own'], 0.8, 0.28],
        lineDasharray: [2, 3],
      ),
      enableInteraction: false,
    );

    // Pulso del escáner: dos anillos sobre el suelo.
    for (final id in [_Lyr.scanB, _Lyr.scanA]) {
      await c.addCircleLayer(
        _Src.scan,
        id,
        ml.CircleLayerProperties(
          circleRadius: 0,
          circleColor: signal,
          circleOpacity: 0,
          circleStrokeColor: signal,
          circleStrokeWidth: id == _Lyr.scanA ? 2.2 : 1.2,
          circleStrokeOpacity: 0,
          circlePitchAlignment: 'map',
          circlePitchScale: 'map',
        ),
        enableInteraction: false,
      );
    }

    // Marcadores.
    ml.SymbolLayerProperties markers({bool withOpacity = false}) => ml.SymbolLayerProperties(
          iconImage: ['get', 'icon'],
          iconSize: ['get', 'sz'],
          iconOpacity: withOpacity ? ['get', 'op'] : null,
          iconAnchor: 'bottom',
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconPitchAlignment: 'viewport',
          iconRotationAlignment: 'viewport',
          symbolSortKey: ['get', 'z'],
        );
    await c.addSymbolLayer(_Src.nodes, _Lyr.nodes, markers());
    await c.addSymbolLayer(_Src.spawns, _Lyr.spawns, markers(withOpacity: true));
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
    if (layerId != _Lyr.spawns && layerId != _Lyr.nodes) return;
    HapticFeedback.selectionClick();
    app.world.select(id);
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
        _Src.grid => _buildGrid(),
        _Src.contagion => _buildContagion(),
        _Src.cells => _buildCells(now),
        _Src.spawns => _buildSpawns(now),
        _Src.nodes => _buildNodes(),
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

  Json? _buildGrid() {
    final p = app.location.position;
    if (p == null) return null;
    final cell = cellId(cellOf(p));
    return _diff(_Src.grid, cell, () => gridCollection(p));
  }

  Json? _buildContagion() {
    final zones = app.world.zones;
    return _diff(_Src.contagion, contagionKey(zones), () => contagionCollection(zones));
  }

  Json? _buildSpawns(int now) {
    final w = app.world;
    final pos = app.location.position;
    final level = app.player?.level ?? 1;
    final sel = w.selectedId;
    final feats = <Json>[];
    final sig = StringBuffer();
    final shown = <String>{};
    for (final s in w.drawable) {
      if (pos != null && haversineM(pos, s.position) > _markerRadiusM) continue;
      final v = w.visibilityOf(s, pos, now);
      if (v == SpawnVisibility.hidden || _pendingSpawn(s, v, now)) continue;
      final selected = s.id == sel;
      final state = selected ? MarkerState.sel : (v == SpawnVisibility.echo ? MarkerState.echo : MarkerState.on);
      final icon = switch (s) {
        ZombieSpawn z => MapIcons.zombie(threatRating(zombieDefs[z.zombieType]!, level), state),
        SupplySpawn sp => MapIcons.supply(sp.supplyType, state),
      };
      final op = v == SpawnVisibility.echo ? 0.62 : 1.0;
      shown.add(s.id);
      sig
        ..write(s.id)
        ..write(icon)
        ..write(s.position.lat)
        ..write(s.position.lng)
        ..write(';');
      feats.add(pointFeature(
        s.position,
        {
          'id': s.id,
          'icon': icon,
          'op': op,
          'sz': selected ? _iconBase * 1.22 : _iconBase,
          'z': selected ? 100 : (s is ZombieSpawn ? 20 : 10),
        },
        id: s.id,
      ));
    }
    _shownSpawns = shown;
    return _diff(_Src.spawns, sig.toString(), () => featureCollection(feats));
  }

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

  Json? _buildNodes() {
    final w = app.world;
    final ownId = app.ownShelter?.id;
    final sel = w.selectedId;
    final feats = <Json>[];
    final sig = StringBuffer();
    for (final s in w.shelters) {
      final own = s.id == ownId;
      final selected = s.id == sel;
      final icon = MapIcons.node(own: own, level: s.level, selected: selected);
      sig
        ..write(s.id)
        ..write(icon)
        ..write(s.position.lat)
        ..write(s.position.lng)
        ..write(';');
      feats.add(pointFeature(
        s.position,
        {'id': s.id, 'icon': icon, 'sz': selected ? _iconBase * 1.2 : _iconBase, 'z': selected ? 100 : (own ? 50 : 40)},
        id: s.id,
      ));
    }
    return _diff(_Src.nodes, sig.toString(), () => featureCollection(feats));
  }

  Json? _buildSutures() {
    final w = app.world;
    final ownId = app.ownShelter?.id;
    final sig = '${[for (final s in w.shelters) '${s.id}@${s.position.lat},${s.position.lng}'].join(';')}|$ownId';
    return _diff(_Src.sutures, sig, () => suturesCollection(w.shelters, ownId));
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
      _markDirty(const [_Src.spawns, _Src.cells]);
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
      _markDirty(const [_Src.spawns, _Src.cells]);
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
    _markDirty(const [_Src.player, _Src.reach, _Src.spawns, _Src.cells, _Src.grid]);
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
    _markDirty(const [_Src.spawns, _Src.cells, _Src.nodes, _Src.sutures, _Src.contagion]);
    if (w.spawns.any((s) => s.placement == PlacementState.raw)) {
      _placeDebounce?.cancel();
      _placeDebounce = Timer(const Duration(milliseconds: 350), () => unawaited(_maybePlace(force: true)));
    }
  }

  void _onApp() => _markDirty(const [_Src.spawns, _Src.nodes, _Src.sutures]);

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
    widget.controller._bearing = cp.bearing;
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

  void _recenter() {
    widget.controller._setFollow(true);
    final c = _map;
    final p = app.location.position;
    if (c == null || p == null) return;
    final cam = _camera ?? c.cameraPosition;
    _segA = cam != null ? _core(cam.target) : p;
    _segB = p;
    c.animateCamera(
      ml.CameraUpdate.newCameraPosition(ml.CameraPosition(
        target: _ll(p),
        zoom: math.max(cam?.zoom ?? kMapZoom, 16),
        tilt: widget.controller.pitched ? kMapPitch : 0,
        bearing: cam?.bearing ?? 0,
      )),
      duration: const Duration(milliseconds: 500),
    );
  }

  void _togglePitch() {
    final next = !widget.controller.pitched;
    widget.controller._setPitched(next);
    final c = _map;
    if (c == null) return;
    final cam = _camera ?? c.cameraPosition;
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
        bearing: next ? (cam?.bearing ?? 0) : 0,
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
    final cam = _camera ?? c?.cameraPosition;
    if (c == null || !_styleReady || _placing || cam == null || cam.zoom < 14) return;
    final now = _now;
    final minGap = _emptyQueries >= 3 ? 10000 : 1500;
    if (!force && now - _lastPlaceAt < minGap) return;
    if (force && now - _lastPlaceAt < 400) return;
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
