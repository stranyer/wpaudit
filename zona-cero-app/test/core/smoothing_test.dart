import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';

const p = LatLng(-34.6, -58.38);
const cfg = ThrottleConfig(minMoveM: 3, minIntervalMs: 1000, maxAcceptedAccuracyM: 150);

void main() {
  group('suavizado GPS', () {
    test('reduce el ruido de lecturas imprecisas', () {
      final s = GpsSmoother();
      s.process(p, 5, 0);
      // Un salto de 60 m con precisión pésima apenas mueve la posición filtrada.
      final r = s.process(offsetM(p, 60, 0), 100, 1000);
      expect(haversineM(p, r.position), lessThan(10));
    });

    test('ignora movimientos mínimos y lecturas muy imprecisas', () {
      const last = GpsReading(position: p, timestamp: 0, accuracyM: 10);
      expect(shouldEmit(null, last, cfg), isTrue);
      expect(shouldEmit(last, GpsReading(position: offsetM(p, 1, 0), timestamp: 2000, accuracyM: 10), cfg), isFalse);
      expect(shouldEmit(last, GpsReading(position: offsetM(p, 10, 0), timestamp: 2000, accuracyM: 10), cfg), isTrue);
      expect(shouldEmit(last, GpsReading(position: offsetM(p, 10, 0), timestamp: 2000, accuracyM: 500), cfg), isFalse);
    });

    test('la configuración por defecto coincide con la web', () {
      expect(gameConfig.gps.throttle.minMoveM, 3);
      expect(gameConfig.gps.throttle.maxAcceptedAccuracyM, 150);
    });
  });
}
