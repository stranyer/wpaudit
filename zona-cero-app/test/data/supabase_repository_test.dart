// SupabaseRepository de punta a punta contra un GoTrue/PostgREST falso en
// loopback: nombres de RPC, argumentos, sesión anónima, privacidad, errores y
// degradación de los pulsos. Sin red externa.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';
import 'package:zona_cero/data/game_repository.dart';
import 'package:zona_cero/data/storage.dart';
import 'package:zona_cero/data/supabase_repository.dart';

import 'fake_supabase.dart';

const _shelterA = '5e1e7000-0000-4000-8000-000000000001';
const _shelterB = '5e1e7000-0000-4000-8000-000000000002';
const _now = 1790000000000;

Map<String, dynamic> _shelterRow(String id, double lat, double lng, {String? ownerId}) => {
      'id': id,
      'name': 'Nodo $id',
      'owner_id': ownerId,
      'owner_name': ownerId == null ? 'Comunidad' : 'Ana',
      'faction_id': 'guardia',
      'level': 2,
      'lat': lat,
      'lng': lng,
      'progress': {'wood': 3},
      'contributions': [],
      'created_at': '2026-09-03T15:30:00+00:00',
    };

Matcher _throwsCode(String code) => throwsA(isA<SupabaseRepositoryException>().having((e) => e.code, 'code', code));

void main() {
  late FakeSupabase fake;
  late KeyValueStore store;

  SupabaseRepository newRepo({Duration timeout = const Duration(seconds: 5)}) =>
      SupabaseRepository(fake.client(), store: store, timeout: timeout, now: () => _now);

  setUp(() async {
    fake = await FakeSupabase.start();
    store = KeyValueStore.memory();
  });

  tearDown(() => fake.close());

  group('sesión', () {
    test('init: sesión anónima + perfil (sin pisar datos), una sola vez', () async {
      final repo = newRepo();
      expect(repo.kind, 'supabase');
      final ids = await Future.wait([repo.init(), repo.init()]);
      expect(ids, [fakeUid, fakeUid]);
      expect(await repo.init(), fakeUid);
      expect(fake.signups, 1);

      final profile = fake.requests.singleWhere((r) => r.path == '/rest/v1/profiles');
      expect(profile.method, 'POST');
      expect(profile.query['on_conflict'], 'id');
      expect(profile.prefer, contains('resolution=ignore-duplicates'));
      expect(profile.body, {'id': fakeUid});
      expect(profile.authorization, 'Bearer $fakeAccessToken');
    });

    test('proveedor anónimo deshabilitado → mensaje claro; se puede reintentar', () async {
      fake.anonymousEnabled = false;
      final repo = newRepo();
      await expectLater(repo.init(), _throwsCode('anonymous_disabled'));
      fake.anonymousEnabled = true;
      expect(await repo.init(), fakeUid);
    });

    test('sin servidor → error de red en español (la fábrica cae a modo local)', () async {
      final repo = newRepo();
      await fake.stopServer();
      await expectLater(
        repo.init(),
        throwsA(isA<SupabaseRepositoryException>()
            .having((e) => e.isNetwork, 'isNetwork', isTrue)
            .having((e) => e.message, 'message', contains('Sin conexión'))),
      );
    });
  });

  group('partida', () {
    final player = createPlayer('local-xyz', ' Ana\u0000 ', _now).copyWith(level: 4, xp: 33, factionId: FactionId.guardia);

    test('loadPlayer: sin partida → null; con partida → id = uid de la sesión', () async {
      final repo = newRepo();
      expect(await repo.loadPlayer(), isNull);
      fake.playerSave = player.toJson();
      expect(await repo.loadPlayer(), player.copyWith(id: fakeUid));
      final get = fake.requests.lastWhere((r) => r.path == '/rest/v1/player_saves');
      expect(get.method, 'GET');
      expect(get.query['player_id'], 'eq.$fakeUid');
      expect(get.query['select'], 'save');
    });

    test('savePlayer: guarda la partida con el uid y espeja solo columnas públicas', () async {
      final repo = newRepo();
      await repo.savePlayer(player);
      final save = fake.requests.singleWhere((r) => r.path == '/rest/v1/player_saves');
      expect(save.method, 'POST');
      expect(save.query['on_conflict'], 'player_id');
      expect(save.body, {'player_id': fakeUid, 'save': jsonDecode(jsonEncode(player.copyWith(id: fakeUid).toJson()))});

      final patch = fake.requests.singleWhere((r) => r.method == 'PATCH');
      expect(patch.path, '/rest/v1/profiles');
      expect(patch.query['id'], 'eq.$fakeUid');
      expect(patch.body, {'name': 'Ana', 'level': 4, 'xp': 33, 'faction_id': 'guardia'});
    });

    test('savePlayer: si falla el espejo público, la partida igual queda guardada', () async {
      fake.profilePatch = const FakeResponse(500, {'message': 'boom'});
      await newRepo().savePlayer(player);
      expect(fake.requests.where((r) => r.path == '/rest/v1/player_saves'), hasLength(1));
    });
  });

  group('validación en el servidor', () {
    const request = InteractionRequest(
      playerId: fakeUid,
      action: InteractionAction.encounter,
      targetId: 'z:1_2:2983333:0',
      targetPosition: LatLng(-34.6, -58.4),
      playerPosition: LatLng(-34.6002, -58.4001),
      accuracyM: 10,
      timestamp: _now,
    );

    test('validateInteraction manda la posición real solo a la RPC y mapea el rechazo', () async {
      fake.rpc['validate_interaction'] = (_) => const FakeResponse(200, {'ok': false, 'reason': 'too_fast', 'distance_m': 23.4});
      final result = await newRepo().validateInteraction(request);
      expect(result, const InteractionResult(ok: false, reason: InteractionRejection.tooFast, distanceM: 23.4));
      final call = fake.rpcCalls('validate_interaction').single;
      expect(call.body, SupabaseMapping.interactionParams(request));
      expect(call.authorization, 'Bearer $fakeAccessToken');
    });

    test('donateToShelter: id no-uuid → not_found sin red; uuid → RPC', () async {
      final repo = newRepo();
      final input = DonationInput(
        shelterId: 'cm-mayo',
        playerId: fakeUid,
        playerName: 'Ana',
        resources: const {ItemId.wood: 5},
        playerPosition: const LatLng(-34.6083, -58.3712),
        accuracyM: 9,
      );
      final local = await repo.donateToShelter(input);
      expect(local.ok, isFalse);
      expect(local.reason, DonationRejection.notFound);
      expect(fake.requests, isEmpty);

      fake.rpc['donate_to_shelter'] = (p) => FakeResponse(200, {
            'ok': true,
            'reason': null,
            'accepted': p['p_resources'],
            'leveled_up': false,
            'shelter': _shelterRow(_shelterA, -34.6083, -58.3712),
          });
      final res = await repo.donateToShelter(DonationInput(
        shelterId: _shelterA,
        playerId: fakeUid,
        playerName: 'Ana',
        resources: input.resources,
        playerPosition: input.playerPosition,
        accuracyM: input.accuracyM,
      ));
      expect(res.ok, isTrue);
      expect(res.accepted, {ItemId.wood: 5});
      expect(res.shelter!.id, _shelterA);
      expect(fake.rpcCalls('donate_to_shelter').single.body, {
        'p_shelter_id': _shelterA,
        'p_resources': {'wood': 5},
        'p_lat': -34.6083,
        'p_lng': -58.3712,
        'p_accuracy': 9.0,
      });
    });

    test('createShelter: errores del servidor en español', () async {
      fake.rpc['create_shelter'] = (_) => FakeResponse.raise('unsafe_location');
      await expectLater(
        newRepo().createShelter(const CreateShelterInput(
          name: 'Nodo',
          ownerId: fakeUid,
          ownerName: 'Ana',
          factionId: null,
          publicPosition: LatLng(-34.59, -58.33),
        )),
        throwsA(isA<SupabaseRepositoryException>()
            .having((e) => e.code, 'code', 'unsafe_location')
            .having((e) => '$e', 'toString', SupabaseMapping.serverErrors['unsafe_location'])),
      );
    });
  });

  group('comunidad', () {
    test('getNearbyShelters ordena por distancia y precarga los pulsos', () async {
      fake.rpc['nearby_shelters'] = (_) => FakeResponse(200, [
            _shelterRow(_shelterB, -34.62, -58.40),
            _shelterRow(_shelterA, -34.601, -58.40),
            {'id': 'roto'},
          ]);
      fake.rpc['shelter_pulse_totals'] = (p) => FakeResponse(200, [
            for (final id in p['p_shelter_ids'] as List) {'shelter_id': id, 'total': id == _shelterA ? 7 : 2},
          ]);
      final repo = newRepo();
      final shelters = await repo.getNearbyShelters(const LatLng(-34.6, -58.4), 20000);
      expect(shelters.map((s) => s.id), [_shelterA, _shelterB]);
      expect(shelters.first.ownerId, SupabaseMapping.systemOwnerId);
      expect(fake.rpcCalls('nearby_shelters').single.body, {'p_lat': -34.6, 'p_lng': -58.4, 'p_radius_m': 20000.0});

      await eventually(() => repo.pulsesOf(_shelterA) == 7);
      expect(repo.pulsesOf(_shelterB), 2);
      expect((fake.rpcCalls('shelter_pulse_totals').single.body as Map)['p_shelter_ids'], unorderedEquals([_shelterA, _shelterB]));
    });

    test('getShelter: id local → null sin red; uuid → get_shelter', () async {
      final repo = newRepo();
      expect(await repo.getShelter('cm-mayo'), isNull);
      expect(fake.requests, isEmpty);
      fake.rpc['get_shelter'] = (p) => p['p_shelter_id'] == _shelterA
          ? FakeResponse(200, _shelterRow(_shelterA, -34.6, -58.4, ownerId: fakeUid))
          : const FakeResponse(200);
      expect((await repo.getShelter(_shelterA))!.ownerId, fakeUid);
      expect(await repo.getShelter(_shelterB), isNull);
    });

    test('publishPresence: solo viaja la posición difuminada', () async {
      fake.rpc['publish_presence'] = (_) => const FakeResponse(204);
      final player = createPlayer(fakeUid, 'Ana', _now);
      const real = LatLng(-34.603722, -58.381592);
      await newRepo().publishPresence(player, real);
      final body = fake.rpcCalls('publish_presence').single.body as Map;
      final fuzzed = fuzzPosition(real, fakeUid);
      expect(body, {'p_lat': fuzzed.lat, 'p_lng': fuzzed.lng});
      expect(body['p_lat'], isNot(real.lat));
      expect(body['p_lng'], isNot(real.lng));
    });

    test('joinFaction: con facción → RPC; sin facción → limpia el perfil propio', () async {
      fake.rpc['join_faction'] = (_) => const FakeResponse(204);
      final repo = newRepo();
      await repo.joinFaction(fakeUid, FactionId.nomades);
      expect(fake.rpcCalls('join_faction').single.body, {'p_faction_id': 'nomades'});
      await repo.joinFaction(fakeUid, null);
      final patch = fake.requests.singleWhere((r) => r.method == 'PATCH');
      expect(patch.query['id'], 'eq.$fakeUid');
      expect(patch.body, {'faction_id': null});
    });

    test('getFactions sin datos → facciones del cliente; leaderboard acota el límite', () async {
      fake.rpc['factions_overview'] = (_) => const FakeResponse(200, []);
      fake.rpc['leaderboard'] = (_) => const FakeResponse(200, [
            {'player_id': 'a', 'player_name': 'Ana', 'faction_id': null, 'level': 2, 'contribution': 5},
          ]);
      final repo = newRepo();
      expect((await repo.getFactions()).map((f) => f.id), factionIds);
      expect((await repo.getLeaderboard(500)).single.playerName, 'Ana');
      expect(fake.rpcCalls('leaderboard').single.body, {'p_limit': 100});
    });

    test('getNearbySurvivors mapea y ordena por distancia', () async {
      fake.rpc['nearby_survivors'] = (_) => const FakeResponse(200, [
            {'player_id': 'lejos', 'name': 'B', 'level': 2, 'faction_id': null, 'lat': -34.63, 'lng': -58.4, 'last_seen_at': '2026-10-10T00:00:00+00:00'},
            {'player_id': 'cerca', 'name': 'A', 'level': 3, 'faction_id': 'guardia', 'lat': -34.601, 'lng': -58.4, 'last_seen_at': '2026-10-10T00:00:00+00:00'},
          ]);
      final survivors = await newRepo().getNearbySurvivors(const LatLng(-34.6, -58.4), 1500);
      expect(survivors.map((s) => s.id), ['cerca', 'lejos']);
    });
  });

  group('pulsos', () {
    test('sendPulse devuelve el total del servidor (y acota la cantidad por envío)', () async {
      fake.rpc['send_pulse'] = (p) => FakeResponse(200, 20 + (p['p_count'] as int));
      final repo = newRepo();
      expect(await repo.sendPulse(_shelterA, fakeUid, 1), 21);
      expect(repo.pulsesOf(_shelterA), 21);
      expect(await repo.sendPulse(_shelterA, fakeUid, 50), 30);
      expect(fake.rpcCalls('send_pulse').map((r) => r.body), [
        {'p_shelter_id': _shelterA, 'p_count': 1},
        {'p_shelter_id': _shelterA, 'p_count': SupabaseRepository.maxPulsesPerCall},
      ]);
      expect(await repo.sendPulse(_shelterA, fakeUid, 0), 30);
      expect(fake.rpcCalls('send_pulse'), hasLength(2));
    });

    test('límite de frecuencia y nodo propio → errores claros', () async {
      final repo = newRepo();
      fake.rpc['send_pulse'] = (_) => FakeResponse.raise('rate_limited');
      await expectLater(repo.sendPulse(_shelterA, fakeUid, 1), _throwsCode('rate_limited'));
      fake.rpc['send_pulse'] = (_) => FakeResponse.raise('own_shelter');
      await expectLater(
        repo.sendPulse(_shelterA, fakeUid, 1),
        throwsA(isA<SupabaseRepositoryException>().having((e) => e.message, 'message', contains('propio nodo'))),
      );
    });

    test('sin la migración de pulsos: cuenta en el dispositivo y no vuelve a llamar', () async {
      final repo = newRepo();
      expect(await repo.sendPulse(_shelterA, fakeUid, 1), 1);
      expect(repo.pulsesAvailable, isFalse);
      expect(await repo.sendPulse(_shelterA, fakeUid, 2), 3);
      expect(fake.rpcCalls('send_pulse'), hasLength(1));
      expect(await repo.fetchPulseTotals([_shelterA, _shelterB]), {_shelterA: 3, _shelterB: 0});
      expect(fake.rpcCalls('shelter_pulse_totals'), isEmpty);

      // Persisten en el dispositivo para la próxima sesión.
      final again = newRepo();
      expect(again.pulsesOf(_shelterA), 3);
    });

    test('fetchPulseTotals sin la RPC de totales → conteos locales', () async {
      fake.rpc['send_pulse'] = (_) => const FakeResponse(200, 4);
      final repo = newRepo();
      await repo.sendPulse(_shelterA, fakeUid, 1);
      expect(await repo.fetchPulseTotals([_shelterA, 'cm-mayo']), {_shelterA: 4});
      expect(repo.pulsesAvailable, isFalse);
    });
  });

  group('red', () {
    test('servidor que no responde a tiempo → timeout', () async {
      final repo = newRepo(timeout: const Duration(milliseconds: 300));
      await repo.init();
      fake.delay = const Duration(seconds: 2);
      fake.rpc['factions_overview'] = (_) => const FakeResponse(200, []);
      await expectLater(repo.getFactions(), _throwsCode('timeout'));
    });

    test('servidor caído después de iniciar → error de red en español', () async {
      final repo = newRepo();
      await repo.init();
      await fake.stopServer();
      await expectLater(repo.getNearbyShelters(const LatLng(-34.6, -58.4), 2000), _throwsCode('network'));
    });

    test('respuesta inválida de una RPC → invalid_response', () async {
      fake.rpc['validate_interaction'] = (_) => const FakeResponse(200, [1, 2]);
      await expectLater(
        newRepo().validateInteraction(const InteractionRequest(
          playerId: fakeUid,
          action: InteractionAction.scavenge,
          targetId: 's:1_1:1:1',
          targetPosition: LatLng(0, 0),
          playerPosition: LatLng(0, 0),
          accuracyM: 5,
          timestamp: _now,
        )),
        _throwsCode('invalid_response'),
      );
    });
  });
}
