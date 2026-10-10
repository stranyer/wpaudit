import 'package:flutter/foundation.dart';

import '../core/core.dart';
import '../services/location/demo_location_provider.dart';
import '../services/location/gps_location_provider.dart';
import '../services/location/location_types.dart';

enum LocationMode { gps, demo }

enum LocationStatus { idle, requesting, active, error }

/// Ubicación del jugador (GPS real o simulación).
class LocationController extends ChangeNotifier {
  LocationMode? mode;
  LocationStatus status = LocationStatus.idle;
  LocationError? error;
  LatLng? position;
  double accuracyM = 0;
  double? headingDeg;

  /// Interacciones bloqueadas por velocidad excesiva hasta este momento (ms).
  int speedLockedUntil = 0;

  LocationProvider? _provider;
  DemoLocationProvider? get demo => _provider is DemoLocationProvider ? _provider as DemoLocationProvider : null;

  /// Se llama con cada nueva lectura (la sesión la usa para mundo, caminata, etc.).
  void Function(LocationFix fix)? onFix;
  void Function(LocationError error)? onError;

  bool get speedLocked => DateTime.now().millisecondsSinceEpoch < speedLockedUntil;

  Future<void> start(LocationMode m, {LatLng? demoStart}) async {
    _provider?.stop();
    mode = m;
    status = LocationStatus.requesting;
    error = null;
    notifyListeners();
    _provider = m == LocationMode.demo
        ? DemoLocationProvider(demoStart ?? gameConfig.demo.start, speedMps: gameConfig.demo.walkSpeedMps)
        : GpsLocationProvider();
    await _provider!.start(_handleFix, (e) {
      if (position != null && e == LocationError.unavailable) return;
      status = LocationStatus.error;
      error = e;
      notifyListeners();
      onError?.call(e);
    });
  }

  void _handleFix(LocationFix fix) {
    position = fix.position;
    accuracyM = fix.accuracyM;
    headingDeg = fix.headingDeg ?? headingDeg;
    status = LocationStatus.active;
    error = null;
    onFix?.call(fix);
    notifyListeners();
  }

  /// Pausa el GPS (app en segundo plano) para ahorrar batería.
  void pause() {
    if (mode == LocationMode.gps) _provider?.stop();
  }

  Future<void> resume() async {
    if (mode == LocationMode.gps) await start(LocationMode.gps);
  }

  void setSpeedLock(int until) {
    if (until == speedLockedUntil) return;
    speedLockedUntil = until;
    notifyListeners();
  }

  @override
  void dispose() {
    _provider?.stop();
    super.dispose();
  }
}
