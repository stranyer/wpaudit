import '../../core/core.dart';

class LocationFix {
  const LocationFix({required this.position, required this.accuracyM, required this.headingDeg, required this.timestamp, this.jump = false});

  final LatLng position;
  final double accuracyM;
  final double? headingDeg;
  final int timestamp;

  /// Salto intencional (teletransporte del modo simulación).
  final bool jump;
}

enum LocationError { denied, deniedForever, disabled, unavailable }

const locationErrorMessages = {
  LocationError.denied: 'Permiso de ubicación denegado. Podés usar la simulación.',
  LocationError.deniedForever: 'La ubicación está bloqueada. Activala en Ajustes o usá la simulación.',
  LocationError.disabled: 'El GPS del teléfono está apagado. Encendelo para jugar caminando.',
  LocationError.unavailable: 'Sin señal de ubicación. Probá al aire libre o usá la simulación.',
};

abstract interface class LocationProvider {
  bool get isSimulated;
  Future<void> start(void Function(LocationFix fix) onFix, void Function(LocationError error) onError);
  void stop();
}
