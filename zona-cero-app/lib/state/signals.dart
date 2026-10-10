import '../core/core.dart';

/// Señal de auxilio: una transmisión de radio desde un punto de la ciudad.
/// No requiere escanear (emite sola); al responderla en el lugar se recupera
/// lo que dejaron y se avanza en las transmisiones del Archivo.
class DistressSignal {
  const DistressSignal({
    required this.id,
    required this.cellId,
    required this.position,
    required this.expiresAt,
    required this.message,
    this.snapped = false,
  });

  final String id;
  final String cellId;
  final LatLng position;
  final int expiresAt;

  /// Fragmento de la transmisión que se escucha al acercarse.
  final String message;
  final bool snapped;

  DistressSignal withPosition(LatLng p) =>
      DistressSignal(id: id, cellId: cellId, position: p, expiresAt: expiresAt, message: message, snapped: true);
}

/// Cada señal dura una ventana de 45 minutos.
const signalWindowMs = 45 * 60 * 1000;

/// Probabilidad de que una celda emita una señal en la ventana actual.
const signalCellChance = 0.22;

/// XP por responder una señal.
const signalXp = 35;

const _messages = [
  '…estamos en el tercer piso, la escalera está tapiada… si alguien escucha…',
  '…dejamos agua y vendas en la caja azul. No sigan por Corrientes…',
  '…somos dos, una nena con fiebre. Repito: una nena con fiebre…',
  '…la repetidora aguanta pocas horas más. Lo que encuentren, llévenlo…',
  '…no abran la puerta del subsuelo. No es gente. No es gente…',
  '…cambio de frecuencia a siete punto tres. Ferrán-Kessler sabía…',
  '…si alguien llega hasta acá, que sepa que lo intentamos…',
  '…hay provisiones en el kiosco de la esquina. Cuidado con el que grita…',
];

/// Genera las señales deterministas de las celdas visibles (como los spawns:
/// todos los jugadores de la zona ven las mismas en la misma ventana).
List<DistressSignal> generateSignals(List<Zone> zones, int now, {String worldSeed = 'zona-cero-v1'}) {
  final w = now ~/ signalWindowMs;
  final out = <DistressSignal>[];
  for (final z in zones) {
    final rng = createRng('$worldSeed:signal:${z.cellId}:$w');
    if (!rng.chance(signalCellChance)) continue;
    const m = 0.18;
    final b = z.bounds;
    final pos = LatLng(
      b.sw.lat + (b.ne.lat - b.sw.lat) * rng.range(m, 1 - m),
      b.sw.lng + (b.ne.lng - b.sw.lng) * rng.range(m, 1 - m),
    );
    out.add(DistressSignal(
      id: 'sig:${z.cellId}:$w',
      cellId: z.cellId,
      position: pos,
      expiresAt: (w + 1) * signalWindowMs,
      message: _messages[rng.intRange(0, _messages.length - 1)],
    ));
  }
  return out;
}
