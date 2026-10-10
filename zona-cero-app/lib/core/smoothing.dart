// Suavizado y filtrado de lecturas GPS.

import 'dart:math' as math;

import 'geo.dart';
import 'types.dart';

/// Resultado del filtro: posición suavizada y precisión estimada (m).
class SmoothedFix {
  const SmoothedFix({required this.position, required this.accuracyM});
  final LatLng position;
  final double accuracyM;
}

/// Filtro de Kalman simple para posiciones GPS.
/// Suaviza el "temblor" del GPS sin agregar mucho retraso, ponderando cada lectura
/// por su precisión. `qMps` es cuánto creemos que puede moverse el jugador por segundo.
class GpsSmoother {
  GpsSmoother({this.qMps = 3});

  final double qMps;
  double _lat = 0;
  double _lng = 0;
  double _variance = -1;
  int _lastTime = 0;

  void reset() {
    _variance = -1;
  }

  SmoothedFix process(LatLng p, num accuracyM, int timestamp) {
    final acc = math.max(1, accuracyM);
    if (_variance < 0) {
      _lat = p.lat;
      _lng = p.lng;
      _variance = (acc * acc).toDouble();
      _lastTime = timestamp;
    } else {
      final dt = timestamp - _lastTime;
      if (dt > 0) {
        _variance += (dt * qMps * qMps) / 1000;
        _lastTime = timestamp;
      }
      final k = _variance / (_variance + acc * acc);
      _lat += k * (p.lat - _lat);
      _lng += k * (p.lng - _lng);
      _variance = (1 - k) * _variance;
    }
    return SmoothedFix(position: LatLng(_lat, _lng), accuracyM: math.sqrt(_variance));
  }
}

class ThrottleConfig {
  const ThrottleConfig({required this.minMoveM, required this.minIntervalMs, required this.maxAcceptedAccuracyM});
  final double minMoveM;
  final int minIntervalMs;
  final double maxAcceptedAccuracyM;
}

/// Lectura de ubicación tal como la evalúa [shouldEmit].
class GpsReading {
  const GpsReading({required this.position, required this.timestamp, required this.accuracyM});
  final LatLng position;
  final int timestamp;
  final double accuracyM;
}

/// Decide si una nueva lectura merece actualizar el juego. Ahorra batería y renders:
/// ignora lecturas muy imprecisas (salvo la primera) y movimientos mínimos.
bool shouldEmit(GpsReading? last, GpsReading next, ThrottleConfig cfg) {
  if (last == null) return true;
  if (next.accuracyM > cfg.maxAcceptedAccuracyM) return false;
  final dt = next.timestamp - last.timestamp;
  if (dt < cfg.minIntervalMs) return false;
  final moved = haversineM(last.position, next.position);
  if (moved >= cfg.minMoveM) return true;
  // Refresco periódico o mejora notable de precisión aunque no se haya movido.
  return dt > 15000 || next.accuracyM < last.accuracyM * 0.6;
}
