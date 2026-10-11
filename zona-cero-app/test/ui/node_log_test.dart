import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';
import 'package:zona_cero/ui/screens/node_screen.dart';

Shelter _shelter() => Shelter(
      id: 'cm-test',
      name: 'Nodo Test',
      position: const LatLng(-34.6, -58.38),
      ownerId: 'x',
      ownerName: 'Rulo',
      factionId: null,
      level: 1,
      progress: const {},
      contributions: const [ShelterContribution(playerId: 'a', playerName: 'Tincho', amount: 12)],
      createdAt: 0,
    );

void main() {
  test('la bitácora del nodo no queda vacía después de medianoche', () {
    final justAfterMidnight = DateTime(2026, 10, 11, 0, 5).millisecondsSinceEpoch;
    final log = communityLog(_shelter(), justAfterMidnight);
    expect(log, isNotEmpty);
    expect(log.every((e) => e.at <= justAfterMidnight), isTrue);
  });

  test('los horarios son estables mientras pasa el tiempo', () {
    final t0 = DateTime(2026, 10, 11, 18, 0).millisecondsSinceEpoch;
    final a = communityLog(_shelter(), t0);
    final b = communityLog(_shelter(), t0 + 60000);
    for (final e in a) {
      expect(b.any((x) => x.at == e.at && x.text == e.text), isTrue);
    }
  });
}
