// Privacidad de ubicación.
// Regla del juego: la ubicación real del jugador NUNCA se comparte. Lo que otros ven
// (presencia, refugios) pasa por estas funciones antes de salir del dispositivo.

import 'geo.dart';
import 'rng.dart';
import 'types.dart';
import 'utils.dart';

/// Difumina una posición: la ajusta a una grilla de `gridM` metros y le suma un
/// desplazamiento estable (por `salt`) de hasta 1/3 de celda. Así no se puede
/// triangular la ubicación real promediando muestras.
LatLng fuzzPosition(LatLng p, String salt, {num gridM = 250}) {
  // Grilla en metros sobre la latitud local para que sea aproximadamente cuadrada.
  final origin = LatLng(jsRound(p.lat).toDouble(), jsRound(p.lng).toDouble());
  final local = toLocalXY(origin, p);
  final snapped = XY(
    ((local.x / gridM).floor() + 0.5) * gridM,
    ((local.y / gridM).floor() + 0.5) * gridM,
  );
  // La semilla usa el formato numérico de JS ("375", no "375.0") para coincidir con la web.
  final rng = createRng('$salt:${jsNumToString(snapped.x)}:${jsNumToString(snapped.y)}');
  final jitter = gridM / 3;
  final center = fromLocalXY(origin, snapped);
  final north = rng.range(-jitter, jitter);
  final east = rng.range(-jitter, jitter);
  return offsetM(center, north, east);
}

/// Distancia aproximada para mostrar a otros jugadores ("~300 m").
String approximateDistanceLabel(num m) {
  if (m < 150) return 'muy cerca';
  if (m < 1000) return '~${jsRound(m / 100) * 100} m';
  return '~${(jsRound(m / 500) * 0.5).toStringAsFixed(1).replaceFirst('.', ',')} km';
}
