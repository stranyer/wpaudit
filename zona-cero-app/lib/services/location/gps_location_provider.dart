import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/core.dart';
import 'location_types.dart';

/// GPS real con geolocator: proveedor fusionado de Android, filtro de distancia,
/// suavizado de Kalman y descarte de lecturas imprecisas. Solo en primer plano
/// (no pide ubicación en segundo plano).
class GpsLocationProvider implements LocationProvider {
  StreamSubscription<Position>? _sub;
  final GpsSmoother _smoother = GpsSmoother();
  GpsReading? _last;

  @override
  bool get isSimulated => false;

  @override
  Future<void> start(void Function(LocationFix) onFix, void Function(LocationError) onError) async {
    stop();
    _smoother.reset();
    _last = null;
    try {
      if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
        onError(LocationError.disabled);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) {
        onError(LocationError.deniedForever);
        return;
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.unableToDetermine) {
        onError(LocationError.denied);
        return;
      }
    } catch (_) {
      onError(LocationError.unavailable);
      return;
    }

    final settings = switch (defaultTargetPlatform) {
      TargetPlatform.android when !kIsWeb => AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: gameConfig.gps.minMoveM.round(),
          intervalDuration: Duration(milliseconds: gameConfig.gps.minIntervalMs),
        ),
      _ => LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: gameConfig.gps.minMoveM.round()),
    };

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        final ts = pos.timestamp.millisecondsSinceEpoch;
        final smoothed = _smoother.process(LatLng(pos.latitude, pos.longitude), pos.accuracy, ts);
        final reading = GpsReading(position: smoothed.position, timestamp: ts, accuracyM: pos.accuracy);
        if (!shouldEmit(_last, reading, gameConfig.gps.throttle)) return;
        _last = reading;
        onFix(LocationFix(
          position: smoothed.position,
          accuracyM: pos.accuracy,
          headingDeg: pos.heading >= 0 && pos.speed > 0.5 ? pos.heading : null,
          timestamp: ts,
        ));
      },
      onError: (Object e) => onError(e is PermissionDeniedException ? LocationError.denied : LocationError.unavailable),
    );
  }

  @override
  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}
