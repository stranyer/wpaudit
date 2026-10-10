import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';
import 'package:zona_cero/data/game_repository.dart';
import 'package:zona_cero/data/local_repository.dart';
import 'package:zona_cero/data/storage.dart';

void main() {
  const obelisco = LatLng(-34.6037, -58.3816);
  late int clock;
  late LocalRepository repo;

  setUp(() {
    clock = DateTime.utc(2026, 10, 10, 12).millisecondsSinceEpoch;
    repo = LocalRepository(KeyValueStore.memory(), now: () => clock);
  });

  test('el id de jugador es estable entre inicios', () async {
    final a = await repo.init();
    final b = await repo.init();
    expect(a, b);
  });

  test('guarda y recupera al jugador', () async {
    final id = await repo.init();
    final p = createPlayer(id, 'Ceniza42', clock).copyWith(level: 3, xp: 40);
    await repo.savePlayer(p);
    final back = await repo.loadPlayer();
    expect(back?.name, 'Ceniza42');
    expect(back?.level, 3);
  });

  test('valida la distancia de interacción', () async {
    final id = await repo.init();
    InteractionRequest req(LatLng player, String target) => InteractionRequest(
          playerId: id,
          action: InteractionAction.scavenge,
          targetId: target,
          targetExpiresAt: clock + 60000,
          targetPosition: obelisco,
          playerPosition: player,
          accuracyM: 5,
          timestamp: clock,
        );
    expect((await repo.validateInteraction(req(offsetM(obelisco, 20, 0), 'a'))).ok, isTrue);
    // Dos minutos después (no dispara el control de velocidad).
    clock += 120000;
    final far = await repo.validateInteraction(req(offsetM(obelisco, 20, 400), 'b'));
    expect(far.ok, isFalse);
    expect(far.reason, InteractionRejection.outOfRange);
  });

  test('el mismo suministro no se puede saquear dos veces', () async {
    final id = await repo.init();
    final req = InteractionRequest(
      playerId: id,
      action: InteractionAction.scavenge,
      targetId: 'supply-1',
      targetExpiresAt: clock + 600000,
      targetPosition: obelisco,
      playerPosition: obelisco,
      accuracyM: 5,
      timestamp: clock,
    );
    expect((await repo.validateInteraction(req)).ok, isTrue);
    clock += 4000;
    final again = await repo.validateInteraction(req);
    expect(again.ok, isFalse);
    expect(again.reason, InteractionRejection.depleted);
  });

  test('crea un nodo y acepta donaciones solo en rango', () async {
    final id = await repo.init();
    final pos = offsetM(obelisco, 100, 100);
    final s = await repo.createShelter(CreateShelterInput(
      name: 'Nodo Test',
      ownerId: id,
      ownerName: 'Test',
      factionId: null,
      publicPosition: pos,
    ));
    expect(s.level, 1);
    final far = await repo.donateToShelter(DonationInput(
      shelterId: s.id,
      playerId: id,
      playerName: 'Test',
      resources: {ItemId.wood: 5},
      playerPosition: obelisco,
      accuracyM: 5,
    ));
    expect(far.ok, isFalse);
    expect(far.reason, DonationRejection.outOfRange);
    final near = await repo.donateToShelter(DonationInput(
      shelterId: s.id,
      playerId: id,
      playerName: 'Test',
      resources: {ItemId.wood: 5, ItemId.food: 3},
      playerPosition: pos,
      accuracyM: 5,
    ));
    expect(near.ok, isTrue);
    // El nivel 2 no pide comida: solo se acepta la madera.
    expect(near.accepted, {ItemId.wood: 5});
    expect(near.shelter!.progress[ItemId.wood], 5);
  });

  test('la comunidad simulada responde con presencia reciente', () async {
    final list = await repo.getNearbySurvivors(obelisco, 3000);
    expect(list, isNotEmpty);
    for (final s in list) {
      expect(s.lastSeenAt, lessThanOrEqualTo(clock));
      expect(haversineM(obelisco, s.approxPosition), lessThan(4000));
    }
  });

  test('un salto imposible bloquea por velocidad', () async {
    final id = await repo.init();
    InteractionRequest at(LatLng p, String t) => InteractionRequest(
          playerId: id,
          action: InteractionAction.scavenge,
          targetId: t,
          targetExpiresAt: clock + 600000,
          targetPosition: p,
          playerPosition: p,
          accuracyM: 5,
          timestamp: clock,
        );
    expect((await repo.validateInteraction(at(obelisco, 'x1'))).ok, isTrue);
    clock += 5000;
    final r = await repo.validateInteraction(at(offsetM(obelisco, 0, 600), 'x2'));
    expect(r.reason, InteractionRejection.tooFast);
  });

  test('los pulsos se acumulan por nodo', () async {
    final id = await repo.init();
    final shelters = await repo.getNearbyShelters(obelisco, 20000);
    final target = shelters.first;
    final before = repo.pulsesOf(target.id);
    final after = await repo.sendPulse(target.id, id, 1);
    expect(after, before + 1);
  });
}
