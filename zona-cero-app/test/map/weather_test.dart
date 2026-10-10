import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';
import 'package:zona_cero/map/weather.dart';

void main() {
  test('códigos WMO → ícono', () {
    expect(weatherKindFor(0), WeatherKind.clear);
    expect(weatherKindFor(2), WeatherKind.partly);
    expect(weatherKindFor(3), WeatherKind.cloud);
    expect(weatherKindFor(45), WeatherKind.fog);
    expect(weatherKindFor(53), WeatherKind.drizzle);
    expect(weatherKindFor(63), WeatherKind.rain);
    expect(weatherKindFor(81), WeatherKind.rain);
    expect(weatherKindFor(75), WeatherKind.snow);
    expect(weatherKindFor(86), WeatherKind.snow);
    expect(weatherKindFor(95), WeatherKind.storm);
    expect(weatherKindFor(99), WeatherKind.storm);
    expect(weatherKindFor(1234), WeatherKind.cloud);
  });

  test('la consulta redondea la posición a 0,1° (privacidad)', () {
    final uri = weatherUri(const LatLng(-34.60372, -58.38159));
    expect(uri.host, 'api.open-meteo.com');
    expect(uri.queryParameters['latitude'], '-34.6');
    expect(uri.queryParameters['longitude'], '-58.4');
    expect(uri.queryParameters['current'], contains('temperature_2m'));
    expect(uri.queryParameters['current'], contains('weather_code'));
  });

  test('interpreta la respuesta de Open-Meteo', () {
    final r = parseWeather('{"current":{"time":"2026-10-10T18:45","temperature_2m":15.6,"weather_code":3,"is_day":0}}');
    expect(r, isNotNull);
    expect(r!.tempLabel, '16°');
    expect(r.kind, WeatherKind.cloud);
    expect(r.isDay, isFalse);
  });

  test('respuestas rotas o incompletas no muestran clima', () {
    expect(parseWeather('no es json'), isNull);
    expect(parseWeather('{"error":true,"reason":"rate limit"}'), isNull);
    expect(parseWeather('{"current":{"temperature_2m":"16"}}'), isNull);
  });
}
