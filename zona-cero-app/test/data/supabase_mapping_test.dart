// Mapeo fila ↔ modelo de SupabaseRepository (funciones puras, sin red).

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthApiException, AuthRetryableFetchException, PostgrestException;
import 'package:zona_cero/core/core.dart';
import 'package:zona_cero/data/game_repository.dart';
import 'package:zona_cero/data/supabase_repository.dart';

typedef M = SupabaseMapping;

const _uid = '0a0b0c0d-1111-4222-8333-444455556666';
const _shelterId = '5e1e7000-0000-4000-8000-000000000001';
const _now = 1790000000000;

/// Fila tal como la devuelve `nearby_shelters` vía PostgREST.
Map<String, dynamic> shelterRow({Map<String, dynamic> overrides = const {}}) => {
      'id': _shelterId,
      'name': 'Plaza de Mayo',
      'owner_id': null,
      'owner_name': 'Comunidad',
      'faction_id': 'resistencia',
      'level': 3,
      'lat': -34.6083,
      'lng': -58.3712,
      'progress': {'wood': 18, 'metal': 12, 'food': 6},
      'contributions': [
        {'player_id': 'p-b', 'player_name': 'Beto', 'amount': 5},
        {'player_id': 'p-a', 'player_name': 'Ana', 'amount': 30},
        {'player_id': 'p-c', 'player_name': 'Caro', 'amount': 5},
      ],
      'created_at': '2026-09-01T12:00:00+00:00',
      'distance_m': 812.4,
      ...overrides,
    };

void main() {
  group('normalización básica', () {
    test('isUuid acepta uuids (sin importar mayúsculas) y rechaza ids locales', () {
      expect(M.isUuid(_shelterId), isTrue);
      expect(M.isUuid(_shelterId.toUpperCase()), isTrue);
      expect(M.isUuid('cm-mayo'), isFalse);
      expect(M.isUuid('sh-local-abc'), isFalse);
      expect(M.isUuid(''), isFalse);
    });

    test('toNumber: números y texto numérico finitos; si no, el valor por defecto', () {
      expect(M.toNumber(3, 0), 3);
      expect(M.toNumber(2.5, 0), 2.5);
      expect(M.toNumber(' 12.5 ', 0), 12.5);
      expect(M.toNumber('1e3', 0), 1000);
      expect(M.toNumber('', 7), 7);
      expect(M.toNumber('abc', 7), 7);
      expect(M.toNumber(double.nan, 7), 7);
      expect(M.toNumber(double.infinity, 7), 7);
      expect(M.toNumber('Infinity', 7), 7);
      expect(M.toNumber(null, 7), 7);
      expect(M.toNumber(true, 7), 7);
    });

    test('clampInt redondea como Math.round y acota sin desbordar', () {
      expect(M.clampInt(2.5, 0, 10, 0), 3);
      expect(M.clampInt(-2.5, -10, 10, 0), -2);
      expect(M.clampInt('7', 0, 10, 0), 7);
      expect(M.clampInt(99, 0, 10, 0), 10);
      expect(M.clampInt(-5, 1, 10, 1), 1);
      expect(M.clampInt(1e300, 0, M.maxSafeInt, 0), M.maxSafeInt);
      expect(M.clampInt(null, 1, 100, 20), 20);
      expect(M.clampInt('x', 1, 100, 20), 20);
    });

    test('toBool acepta las formas de Postgres/JSON', () {
      for (final v in [true, 'true', 't', 1]) {
        expect(M.toBool(v), isTrue, reason: '$v');
      }
      for (final v in [false, 'false', 'f', 0, null, 'yes']) {
        expect(M.toBool(v), isFalse, reason: '$v');
      }
    });

    test('toTimeMs entiende timestamptz de Postgres, números y texto numérico', () {
      final expected = DateTime.utc(2026, 9, 1, 12).millisecondsSinceEpoch;
      expect(M.toTimeMs('2026-09-01T12:00:00+00:00', 0), expected);
      expect(M.toTimeMs('2026-09-01T12:00:00Z', 0), expected);
      expect(M.toTimeMs('2026-09-01 12:00:00+00', 0), expected);
      expect(M.toTimeMs('2026-09-01 09:00:00-03', 0), expected);
      expect(M.toTimeMs('2026-09-01T12:00:00.123456+00:00', 0), expected + 123);
      expect(M.toTimeMs(expected, 0), expected);
      expect(M.toTimeMs('$expected', 0), expected);
      expect(M.toTimeMs('ayer', 42), 42);
      expect(M.toTimeMs(null, 42), 42);
      expect(M.toTimeMs('', 42), 42);
    });

    test('toLatLng valida rangos y acepta texto', () {
      expect(M.toLatLng('-34.6', '-58.4'), const LatLng(-34.6, -58.4));
      expect(M.toLatLng(91, 0), isNull);
      expect(M.toLatLng(0, -181), isNull);
      expect(M.toLatLng(null, 0), isNull);
      expect(M.toLatLng(double.nan, 0), isNull);
    });

    test('toResourceMap: solo recursos básicos, enteros y positivos (también desde texto JSON)', () {
      expect(
        M.toResourceMap({'wood': 3.9, 'metal': '2', 'food': -1, 'water': 0, 'medkit': 4, 'gold': 9, 'ammo': 'x'}),
        {ItemId.wood: 3, ItemId.metal: 2},
      );
      expect(M.toResourceMap('{"water": 5}'), {ItemId.water: 5});
      expect(M.toResourceMap(null), isEmpty);
      expect(M.toResourceMap([1, 2]), isEmpty);
    });

    test('resourcesToJson: claves de la web, sin objetos que no son recursos ni cantidades <= 0', () {
      expect(
        M.resourcesToJson({ItemId.wood: 4, ItemId.metal: 0, ItemId.food: -2, ItemId.medkit: 3, ItemId.water: 1}),
        {'water': 1, 'wood': 4},
      );
      expect(M.resourcesToJson({ItemId.ammo: 2.7, ItemId.food: double.nan}), {'ammo': 2});
    });

    test('sanitizeName quita caracteres de control y recorta a 40', () {
      expect(M.sanitizeName('  Ana\u0000\n\tZ  '), 'AnaZ');
      expect(M.sanitizeName('\u0007  '), M.defaultPlayerName);
      expect(M.sanitizeName('x' * 60), 'x' * 40);
      expect(M.sanitizeName('ñandú' * 10).runes.length, 40);
    });

    test('stableSortDesc conserva el orden de los empates', () {
      final sorted = M.stableSortDesc(['a1', 'b3', 'c1', 'd3', 'e2'], (s) => int.parse(s.substring(1)));
      expect(sorted, ['b3', 'd3', 'e2', 'a1', 'c1']);
    });

    test('toRows acepta lista, objeto suelto, texto JSON y descarta lo demás', () {
      expect(M.toRows([{'a': 1}, 3, null, {'b': 2}]), [{'a': 1}, {'b': 2}]);
      expect(M.toRows({'a': 1}), [{'a': 1}]);
      expect(M.toRows('[{"a":1}]'), [{'a': 1}]);
      expect(M.toRows(null), isEmpty);
      expect(M.toRows('hola'), isEmpty);
    });
  });

  group('refugios', () {
    test('fila de nearby_shelters → Shelter (refugio comunitario)', () {
      final shelter = M.mapShelter(shelterRow(), now: _now)!;
      expect(shelter.id, _shelterId);
      expect(shelter.name, 'Plaza de Mayo');
      expect(shelter.ownerId, M.systemOwnerId);
      expect(shelter.ownerName, 'Comunidad');
      expect(shelter.factionId, FactionId.resistencia);
      expect(shelter.level, 3);
      expect(shelter.position, const LatLng(-34.6083, -58.3712));
      expect(shelter.progress, {ItemId.wood: 18, ItemId.metal: 12, ItemId.food: 6});
      expect(shelter.contributions.map((c) => c.playerId), ['p-a', 'p-b', 'p-c']);
      expect(shelter.createdAt, DateTime.utc(2026, 9, 1, 12).millisecondsSinceEpoch);
    });

    test('jsonb de get_shelter con números como texto y jsonb serializado', () {
      final row = shelterRow(overrides: {
        'owner_id': _uid,
        'owner_name': 'Ana',
        'faction_id': 'desconocida',
        'level': '9',
        'lat': '-34.6',
        'lng': '-58.4',
        'progress': '{"wood": "4"}',
        'contributions': jsonEncode([
          {'playerId': _uid, 'playerName': 'Ana', 'amount': '12'},
          {'player_name': 'sin id', 'amount': 99},
        ]),
        'created_at': null,
      });
      final shelter = M.mapShelter(jsonEncode(row), now: _now)!;
      expect(shelter.ownerId, _uid);
      expect(shelter.factionId, isNull);
      expect(shelter.level, maxShelterLevel);
      expect(shelter.position, const LatLng(-34.6, -58.4));
      expect(shelter.progress, {ItemId.wood: 4});
      expect(shelter.contributions, [const ShelterContribution(playerId: _uid, playerName: 'Ana', amount: 12)]);
      expect(shelter.createdAt, _now);
    });

    test('filas inválidas → null', () {
      expect(M.mapShelter(null, now: _now), isNull);
      expect(M.mapShelter('no es json', now: _now), isNull);
      expect(M.mapShelter(shelterRow(overrides: {'id': null}), now: _now), isNull);
      expect(M.mapShelter(shelterRow(overrides: {'lat': 200}), now: _now), isNull);
    });

    test('el Shelter mapeado sobrevive a toJson/fromJson (formato local)', () {
      final shelter = M.mapShelter(shelterRow(), now: _now)!;
      expect(Shelter.fromJson(jsonDecode(jsonEncode(shelter.toJson())) as Map<String, dynamic>), shelter);
    });

    test('createShelterParams usa la posición PÚBLICA del input', () {
      final params = M.createShelterParams(const CreateShelterInput(
        name: 'Nodo Ana',
        ownerId: _uid,
        ownerName: 'Ana',
        factionId: FactionId.guardia,
        publicPosition: LatLng(-34.61, -58.42),
      ));
      expect(params, {'p_name': 'Nodo Ana', 'p_lat': -34.61, 'p_lng': -58.42});
    });
  });

  group('donaciones', () {
    const input = DonationInput(
      shelterId: _shelterId,
      playerId: _uid,
      playerName: 'Ana',
      resources: {ItemId.wood: 5, ItemId.medkit: 1, ItemId.metal: 0},
      playerPosition: LatLng(-34.6084, -58.3713),
      accuracyM: 12.5,
    );

    test('donationParams: solo recursos, posición real únicamente para validar', () {
      expect(M.donationParams(input), {
        'p_shelter_id': _shelterId,
        'p_resources': {'wood': 5},
        'p_lat': -34.6084,
        'p_lng': -58.3713,
        'p_accuracy': 12.5,
      });
    });

    test('respuesta aceptada con subida de nivel', () {
      final result = M.mapDonationResult({
        'ok': true,
        'reason': null,
        'accepted': {'wood': 5, 'gold': 3},
        'leveled_up': true,
        'shelter': shelterRow(overrides: {'level': 4, 'progress': {}}),
        'distance_m': 10.2,
      }, now: _now);
      expect(result.ok, isTrue);
      expect(result.reason, isNull);
      expect(result.accepted, {ItemId.wood: 5});
      expect(result.leveledUp, isTrue);
      expect(result.shelter!.level, 4);
    });

    test('rechazos: motivo conocido, desconocido → invalid_amount, sin aceptados', () {
      final out = M.mapDonationResult(
        {'ok': false, 'reason': 'out_of_range', 'accepted': {'wood': 2}, 'leveled_up': true, 'shelter': null},
        now: _now,
      );
      expect(out.ok, isFalse);
      expect(out.reason, DonationRejection.outOfRange);
      expect(out.accepted, isEmpty);
      expect(out.leveledUp, isFalse);
      expect(out.shelter, isNull);

      expect(M.mapDonationResult({'ok': false, 'reason': 'not_found'}, now: _now).reason, DonationRejection.notFound);
      final weird = M.mapDonationResult({'ok': 'f', 'reason': '???', 'shelter': shelterRow()}, now: _now);
      expect(weird.reason, DonationRejection.invalidAmount);
      expect(weird.shelter, isNotNull);
    });

    test('respuesta que no es objeto → error claro', () {
      expect(
        () => M.mapDonationResult(null, now: _now),
        throwsA(isA<SupabaseRepositoryException>().having((e) => e.code, 'code', 'invalid_response')),
      );
    });
  });

  group('interacciones', () {
    const request = InteractionRequest(
      playerId: _uid,
      action: InteractionAction.scavenge,
      targetId: 's:10_20:999:1',
      targetExpiresAt: 1790000060000,
      targetPosition: LatLng(-34.6, -58.4),
      playerPosition: LatLng(-34.6001, -58.4001),
      accuracyM: 8,
      timestamp: 1790000000000,
    );

    test('interactionParams: mismos argumentos que la web', () {
      expect(M.interactionParams(request), {
        'p_spawn_id': 's:10_20:999:1',
        'p_target_lat': -34.6,
        'p_target_lng': -58.4,
        'p_lat': -34.6001,
        'p_lng': -58.4001,
        'p_accuracy': 8.0,
        'p_expires_at': DateTime.fromMillisecondsSinceEpoch(1790000060000, isUtc: true).toIso8601String(),
        'p_action': 'scavenge',
      });
      expect(M.interactionParams(request.copyWith(targetExpiresAt: null))['p_expires_at'], isNull);
      expect(M.interactionParams(request.copyWith(accuracyM: double.nan))['p_accuracy'], isNull);
    });

    test('respuestas ok / rechazo / motivo desconocido / sin distancia', () {
      expect(M.mapInteractionResult({'ok': true, 'reason': null, 'distance_m': 12.3}, request),
          const InteractionResult(ok: true, distanceM: 12.3));
      for (final r in InteractionRejection.values) {
        final out = M.mapInteractionResult({'ok': false, 'reason': r.key, 'distance_m': '50'}, request);
        expect(out, InteractionResult(ok: false, reason: r, distanceM: 50));
      }
      expect(M.mapInteractionResult({'ok': false, 'reason': 'hackeado'}, request).reason, InteractionRejection.outOfRange);
      final fallback = M.mapInteractionResult({'ok': 't', 'distance_m': null}, request);
      expect(fallback.ok, isTrue);
      expect(fallback.distanceM, closeTo(haversineM(request.playerPosition, request.targetPosition), 1e-9));
      expect(() => M.mapInteractionResult('[]', request), throwsA(isA<SupabaseRepositoryException>()));
    });
  });

  group('jugador', () {
    final player = createPlayer('local-abc', 'Ana', _now).copyWith(
      level: 7,
      xp: 120,
      factionId: FactionId.nomades,
      inventory: {ItemId.wood: 9, ItemId.pistol: 1},
    );

    test('normalizePlayer: ida y vuelta por jsonb con el id forzado al uid', () {
      final save = jsonDecode(jsonEncode(player.toJson()));
      final loaded = M.normalizePlayer(save, _uid, now: _now)!;
      expect(loaded, player.copyWith(id: _uid));
      expect(M.normalizePlayer(jsonEncode(player.toJson()), _uid, now: _now), player.copyWith(id: _uid));
    });

    test('normalizePlayer completa campos faltantes y descarta facciones desconocidas', () {
      final loaded = M.normalizePlayer({'name': 'Viejo', 'level': '3', 'factionId': 'piratas'}, _uid, now: _now)!;
      expect(loaded.id, _uid);
      expect(loaded.name, 'Viejo');
      expect(loaded.level, 3);
      expect(loaded.factionId, isNull);
      expect(loaded.inventory, starterInventory);
      expect(loaded.lastRegenAt, _now);
    });

    test('normalizePlayer → null si no hay partida reconocible', () {
      expect(M.normalizePlayer(null, _uid), isNull);
      expect(M.normalizePlayer({'level': 3}, _uid), isNull);
      expect(M.normalizePlayer([1, 2], _uid), isNull);
      expect(M.normalizePlayer('roto', _uid), isNull);
    });

    test('profileMirror: solo columnas públicas y saneadas', () {
      final mirror = M.profileMirror(player.copyWith(name: ' Ana\n', level: 5000, xp: -3));
      expect(mirror, {'name': 'Ana', 'level': 1000, 'xp': 0, 'faction_id': 'nomades'});
      expect(M.profileMirror(player.copyWith(factionId: null))['faction_id'], isNull);
    });
  });

  group('privacidad de la presencia', () {
    final player = createPlayer(_uid, 'Ana', _now);
    const real = LatLng(-34.603722, -58.381592);

    test('presenceParams nunca manda la posición real: siempre fuzzPosition(id del jugador)', () {
      final params = M.presenceParams(player, real)!;
      final fuzzed = fuzzPosition(real, _uid);
      expect(params, {'p_lat': fuzzed.lat, 'p_lng': fuzzed.lng});
      expect(params['p_lat'], isNot(real.lat));
      expect(params['p_lng'], isNot(real.lng));
      expect(haversineM(real, LatLng(params['p_lat'] as double, params['p_lng'] as double)), lessThan(400));
    });

    test('si el llamador ya difuminó (como AppState), difuminar otra vez no la mueve', () {
      final once = fuzzPosition(real, _uid);
      final params = M.presenceParams(player, once)!;
      expect(params['p_lat'], closeTo(once.lat, 1e-9));
      expect(params['p_lng'], closeTo(once.lng, 1e-9));
    });

    test('posiciones inválidas no se publican', () {
      expect(M.presenceParams(player, const LatLng(double.nan, 0)), isNull);
      expect(M.presenceParams(player, const LatLng(0, double.infinity)), isNull);
    });
  });

  group('comunidad', () {
    test('factions_overview → facciones con estadísticas; vacío → las del cliente sin datos', () {
      final factions = M.mapFactions([
        {'id': 'guardia', 'name': 'Guardia', 'motto': 'm', 'color': '#123456', 'bonus_description': 'b', 'members': '4', 'total_contribution': 99},
        {'id': 'piratas', 'name': 'X'},
        {'id': 'nomades', 'members': null},
      ]);
      expect(factions.map((f) => f.id), [FactionId.guardia, FactionId.nomades]);
      expect(factions.first, const Faction(
        id: FactionId.guardia,
        name: 'Guardia',
        motto: 'm',
        color: '#123456',
        bonusDescription: 'b',
        members: 4,
        totalContribution: 99,
      ));
      expect(factions.last.name, factionDefs[FactionId.nomades]!.name);
      expect(factions.last.members, 0);

      final fallback = M.mapFactions([]);
      expect(fallback.map((f) => f.id), factionIds);
      expect(fallback.every((f) => f.members == 0 && f.totalContribution == 0), isTrue);
    });

    test('leaderboard ordenado por aporte, con valores por defecto', () {
      final entries = M.mapLeaderboard([
        {'player_id': 'a', 'player_name': 'Ana', 'faction_id': 'guardia', 'level': 4, 'contribution': '10'},
        {'player_id': 'b', 'player_name': null, 'faction_id': null, 'level': 0, 'contribution': 50},
        {'player_name': 'sin id', 'contribution': 999},
      ]);
      expect(entries, const [
        LeaderboardEntry(playerId: 'b', playerName: M.defaultPlayerName, factionId: null, level: 1, contribution: 50),
        LeaderboardEntry(playerId: 'a', playerName: 'Ana', factionId: FactionId.guardia, level: 4, contribution: 10),
      ]);
    });

    test('nearby_survivors → posiciones aproximadas válidas', () {
      final survivors = M.mapSurvivors([
        {'player_id': 'p1', 'name': 'Ana', 'level': 3, 'faction_id': 'nomades', 'lat': -34.602, 'lng': -58.382, 'last_seen_at': '2026-09-01T12:00:00+00:00'},
        {'player_id': 'p2', 'name': 'X', 'lat': null, 'lng': -58.38},
        {'player_id': 'p3', 'lat': -34.6, 'lng': -58.38, 'last_seen_at': null},
      ], now: _now);
      expect(survivors.map((s) => s.id), ['p1', 'p3']);
      expect(survivors.first.approxPosition, const LatLng(-34.602, -58.382));
      expect(survivors.first.lastSeenAt, DateTime.utc(2026, 9, 1, 12).millisecondsSinceEpoch);
      expect(survivors.last.name, M.defaultPlayerName);
      expect(survivors.last.lastSeenAt, _now);
    });

    test('sortByDistance ordena de cerca a lejos (estable)', () {
      const center = LatLng(-34.6, -58.4);
      final points = [const LatLng(-34.62, -58.4), const LatLng(-34.601, -58.4), const LatLng(-34.61, -58.4)];
      expect(M.sortByDistance(points, center, (p) => p), [points[1], points[2], points[0]]);
    });

    test('shelter_pulse_totals → total por nodo', () {
      expect(
        M.mapPulseTotals([
          {'shelter_id': _shelterId, 'total': 30},
          {'shelter_id': 'otro', 'total': '4'},
          {'total': 9},
        ]),
        {_shelterId: 30, 'otro': 4},
      );
    });
  });

  group('errores', () {
    test('códigos de las RPC → mensajes en español (incluidos los de pulsos)', () {
      for (final code in ['not_authenticated', 'invalid_name', 'unsafe_location', 'invalid_faction', 'rate_limited', 'own_shelter', 'invalid_count', 'shelter_not_found']) {
        final e = M.describeError(PostgrestException(message: code, code: 'P0001'), 'Supabase (x)');
        expect(e.code, code);
        expect(e.message, M.serverErrors[code]);
        expect(e.toString(), e.message);
        expect(e.isNetwork, isFalse);
      }
    });

    test('RPC inexistente (migración sin aplicar) → missing_rpc', () {
      const missing = PostgrestException(
        message: 'Could not find the function public.send_pulse(p_count, p_shelter_id) in the schema cache',
        code: 'PGRST202',
      );
      final e = M.describeError(missing, 'Supabase (send_pulse)');
      expect(e.code, 'missing_rpc');
      expect(e.message, contains('supabase/migrations'));
      expect(M.isMissingFunctionError(missing), isTrue);
      expect(M.isMissingFunctionError(const PostgrestException(message: 'x', code: '42883')), isTrue);
      expect(M.isMissingFunctionError(const PostgrestException(message: 'rate_limited', code: 'P0001')), isFalse);
      expect(M.isMissingFunctionError(e), isTrue);
    });

    test('sesión, permisos, servidor caído y respuestas no JSON', () {
      expect(M.describeError(const PostgrestException(message: 'JWT expired', code: 'PGRST301'), 'c').code, 'session_expired');
      expect(M.describeError(const PostgrestException(message: 'permission denied for function x', code: '42501'), 'c').code,
          'permission_denied');
      expect(M.describeError(const PostgrestException(message: 'Bad gateway', code: '502'), 'c').code, 'server_unavailable');
      expect(M.describeError(const PostgrestException(message: 'Could not connect', code: 'PGRST001'), 'c').code,
          'server_unavailable');
      expect(M.describeError(const PostgrestException(message: '<html>proxy</html>', code: '200'), 'c').code, 'invalid_response');
      final other = M.describeError(const PostgrestException(message: 'duplicate key', code: '23505'), 'Supabase (x)');
      expect(other.code, '23505');
      expect(other.message, 'Supabase (x): duplicate key');
    });

    test('red: timeout, sin conexión y fallos de auth reintentables', () {
      final timeout = M.describeError(TimeoutException('lento'), 'c');
      expect(timeout.code, 'timeout');
      expect(timeout.isNetwork, isTrue);
      expect(timeout.message, contains('no respondió a tiempo'));

      final offline = M.describeError(Exception('SocketException: Failed host lookup'), 'c');
      expect(offline.code, 'network');
      expect(offline.isNetwork, isTrue);
      expect(offline.message, contains('Sin conexión'));

      expect(M.describeError(AuthRetryableFetchException(message: 'ClientException'), 'c').code, 'network');
      expect(M.describeError(const FormatException('x'), 'c').code, 'invalid_response');

      const same = SupabaseRepositoryException('ya traducido', code: 'x');
      expect(M.describeError(same, 'c'), same);
    });

    test('inicio de sesión anónimo deshabilitado → instrucciones para activarlo o usar modo local', () {
      final disabled = M.anonymousSignInError(
        const AuthApiException('Anonymous sign-ins are disabled', statusCode: '422', code: 'anonymous_provider_disabled'),
      );
      expect(disabled.code, 'anonymous_disabled');
      expect(disabled.message, contains('Allow anonymous sign-ins'));
      expect(disabled.message, contains('--dart-define'));

      final other = M.anonymousSignInError(const AuthApiException('Captcha failed', statusCode: '400', code: 'captcha_failed'));
      expect(other.code, 'captcha_failed');
      expect(other.message, contains('Captcha failed'));
    });
  });
}
