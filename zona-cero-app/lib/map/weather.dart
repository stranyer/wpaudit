import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/core.dart';

/// Clima actual para la tarjeta de estado del mapa (Open-Meteo, sin clave).
///
/// Privacidad: las coordenadas se redondean a 0,1° (~10 km) antes de salir del
/// teléfono. Se consulta como máximo cada 30 minutos por zona; sin red, la
/// tarjeta simplemente no muestra el clima.

enum WeatherKind { clear, partly, cloud, fog, drizzle, rain, snow, storm }

/// Código WMO (`weather_code` de Open-Meteo) → tipo de ícono.
WeatherKind weatherKindFor(int code) => switch (code) {
      0 => WeatherKind.clear,
      1 || 2 => WeatherKind.partly,
      3 => WeatherKind.cloud,
      45 || 48 => WeatherKind.fog,
      >= 51 && <= 57 => WeatherKind.drizzle,
      >= 61 && <= 67 || >= 80 && <= 82 => WeatherKind.rain,
      >= 71 && <= 77 || 85 || 86 => WeatherKind.snow,
      >= 95 && <= 99 => WeatherKind.storm,
      _ => WeatherKind.cloud,
    };

class WeatherReading {
  const WeatherReading({required this.tempC, required this.kind, required this.isDay});
  final double tempC;
  final WeatherKind kind;
  final bool isDay;

  /// "16°".
  String get tempLabel => '${tempC.round()}°';
}

/// Redondeo a 0,1° (privacidad).
double roundCoord(double v) => (v * 10).round() / 10;

Uri weatherUri(LatLng p) => Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': roundCoord(p.lat).toStringAsFixed(1),
      'longitude': roundCoord(p.lng).toStringAsFixed(1),
      'current': 'temperature_2m,weather_code,is_day',
    });

/// Interpreta la respuesta JSON; null si no tiene lo necesario.
WeatherReading? parseWeather(String body) {
  try {
    final j = jsonDecode(body);
    if (j is! Map) return null;
    final c = j['current'];
    if (c is! Map) return null;
    final t = c['temperature_2m'];
    final code = c['weather_code'];
    if (t is! num || code is! num) return null;
    final day = c['is_day'];
    return WeatherReading(tempC: t.toDouble(), kind: weatherKindFor(code.toInt()), isDay: day is num ? day != 0 : true);
  } catch (_) {
    return null;
  }
}

/// Clima de la zona actual. Escucha cambios de zona (0,1°) y refresca cada 30 min.
class WeatherController extends ChangeNotifier {
  WeatherController([this._client]);

  static const refreshEvery = Duration(minutes: 30);
  static const _retryAfterError = Duration(minutes: 5);

  final http.Client? _client;
  WeatherReading? reading;
  String? _key;
  DateTime _fetchedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _failedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _loading = false;
  bool _disposed = false;

  /// Pide el clima si cambió la zona o pasó el intervalo. Barato de llamar seguido.
  void update(LatLng? p) {
    if (p == null || _loading) return;
    final key = '${roundCoord(p.lat)},${roundCoord(p.lng)}';
    final now = DateTime.now();
    final fresh = key == _key && now.difference(_fetchedAt) < refreshEvery;
    final backoff = now.difference(_failedAt) < _retryAfterError;
    if (fresh || backoff) return;
    unawaited(_fetch(p, key));
  }

  Future<void> _fetch(LatLng p, String key) async {
    _loading = true;
    try {
      final uri = weatherUri(p);
      final client = _client;
      final res = await (client != null ? client.get(uri) : http.get(uri)).timeout(const Duration(seconds: 8));
      final r = res.statusCode == 200 ? parseWeather(res.body) : null;
      if (_disposed) return;
      if (r == null) {
        _failedAt = DateTime.now();
        if (key != _key) reading = null;
      } else {
        reading = r;
        _key = key;
        _fetchedAt = DateTime.now();
      }
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      debugPrint('[Zona Cero] Clima no disponible: $e');
      _failedAt = DateTime.now();
      if (key != _key && reading != null) {
        reading = null;
        notifyListeners();
      }
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
