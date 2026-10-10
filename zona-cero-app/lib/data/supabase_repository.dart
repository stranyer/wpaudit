import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, AuthResponse, AuthRetryableFetchException, ErrorCode, PostgrestException, SupabaseClient, User;

import '../core/core.dart';
import 'game_repository.dart';
import 'storage.dart';

// Repositorio de producción contra Supabase (Postgres + PostGIS). Port de
// `src/services/data/SupabaseRepository.ts` de la versión web.
// El esquema y las RPC están en supabase/migrations/ (0001_init.sql es el mismo
// archivo que usa la web; 0002_pulses.sql agrega los pulsos).
//
// - Identidad: sesión anónima de Supabase (`auth.uid()`); el id del jugador es el uid.
// - Toda validación que importa (alcance, velocidad, reclamos, donaciones, pulsos)
//   la hace el servidor con funciones SECURITY DEFINER; acá solo se mapean las
//   respuestas.
// - Privacidad: la posición real solo viaja como argumento de las RPC de validación
//   (`validate_interaction`, `donate_to_shelter`). La presencia se difumina acá
//   (`fuzzPosition`) y el servidor la vuelve a engrosar; los refugios se crean con
//   la posición pública que arma el llamador y el servidor también la engrosa.

/// Error de la capa de datos con un mensaje en español listo para mostrar.
///
/// `toString()` devuelve solo [message], así que se puede interpolar en un toast.
class SupabaseRepositoryException implements Exception {
  const SupabaseRepositoryException(this.message, {required this.code, this.cause});

  /// Mensaje para el jugador (español).
  final String message;

  /// Código estable: el que lanza la RPC (`rate_limited`, `invalid_name`…) o uno
  /// del cliente: `network`, `timeout`, `invalid_response`, `missing_rpc`,
  /// `session_expired`, `permission_denied`, `server_unavailable`,
  /// `anonymous_disabled`, `auth`, `server_error`.
  final String code;

  /// Excepción original (para logs).
  final Object? cause;

  /// Falla de conectividad (sin red o sin respuesta a tiempo).
  bool get isNetwork => code == 'network' || code == 'timeout';

  @override
  String toString() => message;
}

/// Repositorio contra Supabase. Se construye con un [SupabaseClient] ya creado
/// (en la app, `Supabase.instance.client`; ver `repository_factory.dart`).
class SupabaseRepository implements GameRepository {
  /// [store] guarda los pulsos contados en el dispositivo si el servidor no
  /// tiene la RPC; [timeout] limita cada llamada de red.
  SupabaseRepository(
    this._client, {
    this._store,
    this._timeout = const Duration(seconds: 15),
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final SupabaseClient _client;
  final KeyValueStore? _store;
  final Duration _timeout;
  final int Function() _now;

  String? _userId;
  Future<String>? _initFuture;

  /// Totales de pulsos conocidos por nodo (del servidor o, sin RPC, locales).
  final Map<String, int> _pulseTotals = {};
  bool _pulsesAvailable = true;
  Map<String, int>? _localPulses;

  /// Pulsos contados en el dispositivo cuando el servidor no tiene `send_pulse`.
  static const _kLocalPulses = 'zc:sb-pulses';

  /// Máximo de pulsos por llamada que acepta `send_pulse` (ver 0002_pulses.sql).
  static const maxPulsesPerCall = 10;

  @override
  String get kind => 'supabase';

  /// Id del jugador (uid de la sesión) una vez inicializado.
  String? get userId => _userId;

  /// false si el servidor no tiene las RPC de pulsos (falta 0002_pulses.sql).
  bool get pulsesAvailable => _pulsesAvailable;

  // ---------------------------------------------------------------------------
  // Sesión y partida
  // ---------------------------------------------------------------------------

  @override
  Future<String> init() async {
    final uid = _userId;
    if (uid != null) return uid;
    final pending = _initFuture ??= _startSession();
    try {
      return await pending;
    } catch (_) {
      // Permite reintentar después de un error (p. ej. sin red al arrancar).
      if (identical(_initFuture, pending)) _initFuture = null;
      rethrow;
    }
  }

  Future<String> _startSession() async {
    final auth = _client.auth;
    User? user;
    try {
      // Restaura (y refresca si venció) la sesión guardada.
      user = (await auth.getSession().timeout(_timeout))?.user;
    } on AuthRetryableFetchException catch (e) {
      // Sin red para refrescar el token: NO se crea otro usuario anónimo
      // (se perdería la partida guardada en la nube).
      throw SupabaseMapping.describeError(e, 'Supabase: no se pudo restaurar la sesión');
    } on TimeoutException catch (e) {
      throw SupabaseMapping.describeError(e, 'Supabase: no se pudo restaurar la sesión');
    } on AuthException {
      // Token de refresco inválido o revocado: se empieza una sesión anónima nueva.
      user = null;
    } on Exception catch (e) {
      throw SupabaseMapping.describeError(e, 'Supabase: no se pudo restaurar la sesión');
    }

    if (user == null) {
      final AuthResponse response;
      try {
        response = await auth.signInAnonymously().timeout(_timeout);
      } on AuthRetryableFetchException catch (e) {
        throw SupabaseMapping.describeError(e, 'Supabase: no se pudo iniciar la sesión anónima');
      } on AuthException catch (e) {
        throw SupabaseMapping.anonymousSignInError(e);
      } on Exception catch (e) {
        throw SupabaseMapping.describeError(e, 'Supabase: no se pudo iniciar la sesión anónima');
      }
      user = response.user ?? response.session?.user;
      if (user == null) {
        throw const SupabaseRepositoryException(
          'Supabase: no se pudo crear la sesión anónima.',
          code: 'auth',
        );
      }
    }

    final uid = user.id;
    // Crea el perfil si no existe (INSERT … ON CONFLICT DO NOTHING; no pisa datos).
    await _call(
      'Supabase: no se pudo crear el perfil',
      () => _client.from('profiles').upsert({'id': uid}, onConflict: 'id', ignoreDuplicates: true),
    );
    _userId = uid;
    return uid;
  }

  Future<String> _requireUser() async => _userId ?? await init();

  @override
  Future<PlayerState?> loadPlayer() async {
    final uid = await _requireUser();
    final row = await _call(
      'Supabase: no se pudo cargar la partida',
      () => _client.from('player_saves').select('save').eq('player_id', uid).maybeSingle(),
    );
    if (row == null) return null;
    return SupabaseMapping.normalizePlayer(row['save'], uid, now: _now());
  }

  @override
  Future<void> savePlayer(PlayerState player) async {
    final uid = await _requireUser();
    // El id guardado siempre es el uid de la sesión.
    final save = player.copyWith(id: uid).toJson();
    await _call(
      'Supabase: no se pudo guardar la partida',
      () => _client.from('player_saves').upsert({'player_id': uid, 'save': save}, onConflict: 'player_id'),
    );

    // Espejo público (solo columnas seguras; RLS: solo el propio perfil).
    try {
      await _call(
        'Supabase: no se pudo actualizar el perfil público',
        () => _client.from('profiles').update(SupabaseMapping.profileMirror(player)).eq('id', uid),
      );
    } on SupabaseRepositoryException catch (e) {
      // La partida ya quedó guardada; el perfil público se reintenta en el próximo guardado.
      debugPrint('[SupabaseRepository] No se pudo actualizar el perfil público: ${e.message}');
    }
  }

  // ---------------------------------------------------------------------------
  // Interacciones (validadas por el servidor)
  // ---------------------------------------------------------------------------

  @override
  Future<InteractionResult> validateInteraction(InteractionRequest request) async {
    await _requireUser();
    final raw = await _rpc('validate_interaction', SupabaseMapping.interactionParams(request));
    return SupabaseMapping.mapInteractionResult(raw, request);
  }

  // ---------------------------------------------------------------------------
  // Refugios (nodos)
  // ---------------------------------------------------------------------------

  @override
  Future<List<Shelter>> getNearbyShelters(LatLng center, double radiusM) async {
    await _requireUser();
    final raw = await _rpc('nearby_shelters', {
      'p_lat': SupabaseMapping.finiteOrNull(center.lat),
      'p_lng': SupabaseMapping.finiteOrNull(center.lng),
      'p_radius_m': math.max(0.0, SupabaseMapping.toNumber(radiusM, 0)),
    });
    final shelters = SupabaseMapping.sortByDistance(
      [for (final row in SupabaseMapping.toRows(raw)) ?SupabaseMapping.mapShelter(row, now: _now())],
      center,
      (s) => s.position,
    );
    // Totales de pulsos en segundo plano (para `pulsesOf`); nunca rompe la carga.
    if (_pulsesAvailable && shelters.isNotEmpty) {
      unawaited(fetchPulseTotals(shelters.map((s) => s.id)).then<void>((_) {}, onError: (Object e) {
        debugPrint('[SupabaseRepository] No se pudieron cargar los pulsos: $e');
      }));
    }
    return shelters;
  }

  @override
  Future<Shelter?> getShelter(String id) async {
    if (!SupabaseMapping.isUuid(id)) return null;
    await _requireUser();
    return SupabaseMapping.mapShelter(await _rpc('get_shelter', {'p_shelter_id': id}), now: _now());
  }

  @override
  Future<Shelter> createShelter(CreateShelterInput input) async {
    // Dueño, nombre del dueño y facción los fija el servidor (auth.uid() + profiles).
    await _requireUser();
    final raw = await _rpc('create_shelter', SupabaseMapping.createShelterParams(input));
    final shelter = SupabaseMapping.mapShelter(raw, now: _now());
    if (shelter == null) {
      throw const SupabaseRepositoryException(
        'Supabase: respuesta inválida al crear el nodo.',
        code: 'invalid_response',
      );
    }
    return shelter;
  }

  @override
  Future<DonationResult> donateToShelter(DonationInput input) async {
    if (!SupabaseMapping.isUuid(input.shelterId)) {
      return const DonationResult(ok: false, reason: DonationRejection.notFound);
    }
    await _requireUser();
    final raw = await _rpc('donate_to_shelter', SupabaseMapping.donationParams(input));
    return SupabaseMapping.mapDonationResult(raw, now: _now());
  }

  // ---------------------------------------------------------------------------
  // Facciones, ranking y comunidad
  // ---------------------------------------------------------------------------

  @override
  Future<List<Faction>> getFactions() async {
    await _requireUser();
    return SupabaseMapping.mapFactions(await _rpc('factions_overview'));
  }

  @override
  Future<void> joinFaction(String playerId, FactionId? factionId) async {
    // El servidor usa auth.uid(); el id del jugador local coincide con el uid de la sesión.
    final uid = await _requireUser();
    if (factionId == null) {
      // `join_faction` no admite "sin facción": se limpia el perfil público
      // (columna editable por el dueño; la presencia la toma en el próximo envío).
      await _call(
        'Supabase: no se pudo dejar la facción',
        () => _client.from('profiles').update({'faction_id': null}).eq('id', uid),
      );
      return;
    }
    await _rpc('join_faction', {'p_faction_id': factionId.key});
  }

  @override
  Future<List<LeaderboardEntry>> getLeaderboard(int limit) async {
    await _requireUser();
    final raw = await _rpc('leaderboard', {'p_limit': SupabaseMapping.clampInt(limit, 1, 100, 20)});
    return SupabaseMapping.mapLeaderboard(raw);
  }

  @override
  Future<List<PublicSurvivor>> getNearbySurvivors(LatLng center, double radiusM) async {
    await _requireUser();
    final raw = await _rpc('nearby_survivors', {
      'p_lat': SupabaseMapping.finiteOrNull(center.lat),
      'p_lng': SupabaseMapping.finiteOrNull(center.lng),
      'p_radius_m': math.max(0.0, SupabaseMapping.toNumber(radiusM, 0)),
    });
    return SupabaseMapping.sortByDistance(
      SupabaseMapping.mapSurvivors(raw, now: _now()),
      center,
      (s) => s.approxPosition,
    );
  }

  @override
  Future<void> publishPresence(PlayerState player, LatLng approxPosition) async {
    // Difuminado en el cliente (estable por jugador); el servidor vuelve a engrosar
    // a grilla. Nombre, nivel y facción salen del perfil público (espejado en savePlayer).
    final params = SupabaseMapping.presenceParams(player, approxPosition);
    if (params == null) return;
    await _requireUser();
    await _rpc('publish_presence', params);
  }

  // ---------------------------------------------------------------------------
  // Pulsos (0002_pulses.sql)
  // ---------------------------------------------------------------------------

  /// Envía [count] pulsos al nodo y devuelve su total. El servidor valida que el
  /// nodo exista y no sea propio, y limita la frecuencia (lanza
  /// [SupabaseRepositoryException] con código `rate_limited`, `own_shelter`…).
  /// Si el servidor no tiene la RPC (falta la migración), cuenta en el dispositivo.
  @override
  Future<int> sendPulse(String shelterId, String playerId, int count) async {
    if (count <= 0) return pulsesOf(shelterId);
    final n = math.min(count, maxPulsesPerCall);
    if (!_pulsesAvailable || !SupabaseMapping.isUuid(shelterId)) return _localPulse(shelterId, n);
    await _requireUser();
    try {
      final raw = await _rpc('send_pulse', {'p_shelter_id': shelterId, 'p_count': n});
      final total = SupabaseMapping.clampInt(raw, -1, SupabaseMapping.maxSafeInt, -1);
      if (total < 0) {
        throw const SupabaseRepositoryException(
          'Supabase: respuesta inválida de send_pulse.',
          code: 'invalid_response',
        );
      }
      _pulseTotals[shelterId] = total;
      return total;
    } on SupabaseRepositoryException catch (e) {
      if (e.code != 'missing_rpc') rethrow;
      _markPulsesUnavailable(e);
      return _localPulse(shelterId, n);
    }
  }

  /// Total de pulsos conocido de un nodo (sin red): lo último que informó el
  /// servidor (`sendPulse`, `fetchPulseTotals`, `getNearbyShelters`) o, si el
  /// servidor no tiene pulsos, lo contado en el dispositivo.
  int pulsesOf(String shelterId) => _pulseTotals[shelterId] ?? _readLocalPulses()[shelterId] ?? 0;

  /// Pide al servidor los totales de pulsos de varios nodos (máx. 200) y los
  /// guarda para [pulsesOf]. Sin la RPC, devuelve los conteos locales.
  Future<Map<String, int>> fetchPulseTotals(Iterable<String> shelterIds) async {
    final ids = shelterIds.where(SupabaseMapping.isUuid).toSet().take(200).toList();
    if (ids.isEmpty || !_pulsesAvailable) return {for (final id in shelterIds) id: pulsesOf(id)};
    await _requireUser();
    try {
      final totals = SupabaseMapping.mapPulseTotals(await _rpc('shelter_pulse_totals', {'p_shelter_ids': ids}));
      for (final id in ids) {
        _pulseTotals[id] = totals[id] ?? 0;
      }
      return {for (final id in ids) id: _pulseTotals[id]!};
    } on SupabaseRepositoryException catch (e) {
      if (e.code != 'missing_rpc') rethrow;
      _markPulsesUnavailable(e);
      return {for (final id in ids) id: pulsesOf(id)};
    }
  }

  void _markPulsesUnavailable(SupabaseRepositoryException e) {
    if (!_pulsesAvailable) return;
    _pulsesAvailable = false;
    debugPrint('[SupabaseRepository] El servidor no tiene pulsos (aplicá supabase/migrations/0002_pulses.sql). '
        'Se cuentan en el dispositivo. ${e.cause ?? e.message}');
  }

  Map<String, int> _readLocalPulses() => _localPulses ??= _store?.readJson(
            _kLocalPulses,
            (j) => {
              for (final e in (j as Map).entries)
                if (e.value is num) '${e.key}': (e.value as num).toInt(),
            },
          ) ??
          {};

  Future<int> _localPulse(String shelterId, int count) async {
    final stored = _readLocalPulses();
    final total = math.max(_pulseTotals[shelterId] ?? 0, stored[shelterId] ?? 0) + count;
    stored[shelterId] = total;
    _pulseTotals[shelterId] = total;
    await _store?.writeJson(_kLocalPulses, stored);
    return total;
  }

  // ---------------------------------------------------------------------------

  Future<Object?> _rpc(String fn, [Map<String, dynamic> params = const {}]) =>
      _call<Object?>('Supabase ($fn)', () => _client.rpc<Object?>(fn, params: params));

  /// Ejecuta una llamada de red con tiempo límite y traduce los errores a
  /// [SupabaseRepositoryException] (los `Error` de programación no se tocan).
  Future<T> _call<T>(String context, Future<T> Function() run) async {
    try {
      return await run().timeout(_timeout);
    } on Exception catch (e) {
      throw SupabaseMapping.describeError(e, context);
    }
  }
}

/// Mapeo fila ↔ modelo y normalización defensiva (los números pueden llegar como
/// texto, el jsonb como string…). Funciones puras, sin red: se testean aparte.
abstract final class SupabaseMapping {
  /// Dueño de los refugios comunitarios (owner_id NULL en la base).
  static const systemOwnerId = 'comunidad';
  static const systemOwnerName = 'Comunidad';
  static const defaultPlayerName = 'Superviviente';
  static const maxNameLength = 40;

  /// `Number.MAX_SAFE_INTEGER` (también representable en web).
  static const maxSafeInt = 9007199254740991;

  static final RegExp _uuidRe = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);
  static final RegExp _controlChars = RegExp(r'[\u0000-\u001f\u007f]');
  static final RegExp _numericRe = RegExp(r'^\d+(\.\d+)?$');

  /// Mensajes para los errores que lanzan las RPC (`raise exception '<código>'`).
  static const Map<String, String> serverErrors = {
    'not_authenticated': 'No hay sesión iniciada con el servidor.',
    'invalid_name': 'El nombre del nodo debe tener entre 2 y 40 caracteres.',
    'invalid_position': 'La posición no es válida.',
    'unsafe_location': 'Ese lugar no es un espacio público seguro (zona excluida). Probá en una plaza o un parque.',
    'invalid_faction': 'Facción desconocida.',
    'invalid_action': 'Tipo de interacción inválido.',
    'invalid_spawn_id': 'Identificador de punto inválido.',
    // 0002_pulses.sql
    'invalid_count': 'Cantidad de pulsos inválida (de 1 a 10 por envío).',
    'shelter_not_found': 'No se encontró el nodo.',
    'own_shelter': 'No podés mandarle pulsos a tu propio nodo.',
    'rate_limited': 'Demasiados pulsos seguidos. Esperá un momento antes de volver a pulsar.',
  };

  // ---------------------------------------------------------------------------
  // Errores
  // ---------------------------------------------------------------------------

  /// Traduce cualquier excepción de red/servidor a un mensaje claro en español.
  static SupabaseRepositoryException describeError(Object error, String context) {
    if (error is SupabaseRepositoryException) return error;
    if (error is TimeoutException) {
      return SupabaseRepositoryException(
        'El servidor de Zona Cero no respondió a tiempo. Revisá tu conexión.',
        code: 'timeout',
        cause: error,
      );
    }
    if (error is PostgrestException) return _describePostgrest(error, context);
    if (error is AuthRetryableFetchException) return _network(error);
    if (error is AuthException) {
      return SupabaseRepositoryException('$context: ${error.message}', code: error.code ?? 'auth', cause: error);
    }
    if (error is FormatException) {
      return SupabaseRepositoryException('$context: respuesta inválida del servidor.', code: 'invalid_response', cause: error);
    }
    // ClientException, SocketException, HandshakeException…: no hubo respuesta.
    return _network(error);
  }

  static SupabaseRepositoryException _network(Object error) => SupabaseRepositoryException(
        'Sin conexión con el servidor de Zona Cero. Revisá tu conexión a internet.',
        code: 'network',
        cause: error,
      );

  static SupabaseRepositoryException _describePostgrest(PostgrestException error, String context) {
    final message = error.message.trim();
    final code = error.code ?? '';
    final friendly = serverErrors[message];
    if (friendly != null) return SupabaseRepositoryException(friendly, code: message, cause: error);
    if (isMissingFunctionError(error)) {
      return SupabaseRepositoryException(
        '$context: el servidor no tiene esta función. Aplicá las migraciones de supabase/migrations '
        "(y ejecutá `notify pgrst, 'reload schema';`).",
        code: 'missing_rpc',
        cause: error,
      );
    }
    if (code == 'PGRST301' || code == 'PGRST303' || code == '401') {
      return SupabaseRepositoryException(
        'La sesión con el servidor venció o no es válida. Reiniciá el juego.',
        code: 'session_expired',
        cause: error,
      );
    }
    if (code == '42501' || code == '403') {
      return SupabaseRepositoryException(
        '$context: el servidor rechazó la operación (permiso denegado).',
        code: 'permission_denied',
        cause: error,
      );
    }
    // Sin JSON de error, postgrest usa el estado HTTP (3 dígitos) como código;
    // los SQLSTATE de Postgres tienen 5 caracteres (p. ej. '23505').
    final status = code.length == 3 ? int.tryParse(code) : null;
    if (code.startsWith('PGRST00') || (status != null && status >= 500)) {
      return SupabaseRepositoryException(
        'El servidor de Zona Cero no está disponible en este momento. Probá más tarde.',
        code: 'server_unavailable',
        cause: error,
      );
    }
    if (message.isEmpty || message.startsWith('<')) {
      // Un proxy o gateway devolvió HTML o un cuerpo vacío.
      return SupabaseRepositoryException('$context: respuesta inválida del servidor.', code: 'invalid_response', cause: error);
    }
    return SupabaseRepositoryException('$context: $message', code: code.isEmpty ? 'server_error' : code, cause: error);
  }

  /// La RPC (o su tabla) no existe en el servidor: falta aplicar una migración.
  static bool isMissingFunctionError(Object error) {
    if (error is SupabaseRepositoryException) return error.code == 'missing_rpc';
    if (error is! PostgrestException) return false;
    const codes = {'PGRST202', 'PGRST205', '42883', '42P01'};
    return codes.contains(error.code) || error.message.toLowerCase().contains('could not find the function');
  }

  static SupabaseRepositoryException anonymousSignInError(AuthException error) {
    final disabled =
        error.code == ErrorCode.anonymousProviderDisabled.code || error.message.toLowerCase().contains('anonymous');
    if (disabled) {
      return SupabaseRepositoryException(
        'Supabase: el inicio de sesión anónimo está deshabilitado. Activalo en el Dashboard → '
        'Authentication → Providers → Anonymous ("Allow anonymous sign-ins"), o quitá '
        '--dart-define=SUPABASE_URL / SUPABASE_ANON_KEY para jugar en modo local.',
        code: 'anonymous_disabled',
        cause: error,
      );
    }
    return SupabaseRepositoryException(
      'Supabase: no se pudo iniciar la sesión anónima (${error.message}).',
      code: error.code ?? 'auth',
      cause: error,
    );
  }

  // ---------------------------------------------------------------------------
  // Normalización
  // ---------------------------------------------------------------------------

  static bool isUuid(String id) => _uuidRe.hasMatch(id);

  /// Si es texto, intenta decodificarlo como JSON (jsonb que llega serializado).
  static Object? parseJsonish(Object? value) {
    if (value is! String) return value;
    try {
      return jsonDecode(value);
    } on FormatException {
      return value;
    }
  }

  /// Objeto JSON (o texto con un objeto JSON) como mapa; null si no lo es.
  static Map<String, dynamic>? asRecord(Object? value) {
    final parsed = parseJsonish(value);
    if (parsed is! Map) return null;
    return {for (final e in parsed.entries) '${e.key}': e.value};
  }

  /// Filas de una RPC `returns table` (o un objeto suelto como una fila).
  static List<Map<String, dynamic>> toRows(Object? value) {
    final parsed = parseJsonish(value);
    if (parsed is Map) return [asRecord(parsed)!];
    if (parsed is! List) return const [];
    return [
      for (final item in parsed)
        if (item is Map) asRecord(item)!,
    ];
  }

  /// Número finito (también desde texto numérico) o [fallback].
  static double toNumber(Object? value, double fallback) {
    double? n;
    if (value is num) {
      n = value.toDouble();
    } else if (value is String && value.trim().isNotEmpty) {
      n = num.tryParse(value.trim())?.toDouble();
    }
    return n != null && n.isFinite ? n : fallback;
  }

  /// `Math.min(max, Math.max(min, Math.round(n)))` sin desbordes.
  static int clampInt(Object? value, int min, int max, int fallback) {
    final n = toNumber(value, fallback.toDouble());
    return jsRound(n.clamp(min.toDouble(), max.toDouble())).clamp(min, max);
  }

  static double? finiteOrNull(double value) => value.isFinite ? value : null;

  static String toStr(Object? value, String fallback) {
    if (value is String) return value;
    if (value is num && value.isFinite) return jsNumToString(value);
    return fallback;
  }

  static bool toBool(Object? value) => value == true || value == 'true' || value == 't' || value == 1;

  /// Epoch en ms desde ISO (con microsegundos de Postgres), número o texto numérico.
  static int toTimeMs(Object? value, int fallback) {
    if (value is num) return value.isFinite ? jsRound(value) : fallback;
    if (value is! String || value.trim().isEmpty) return fallback;
    final trimmed = value.trim();
    if (_numericRe.hasMatch(trimmed)) return jsRound(toNumber(trimmed, fallback.toDouble()));
    final iso = trimmed
        .replaceFirst(' ', 'T')
        .replaceFirstMapped(RegExp(r'(\.\d{3})\d+'), (m) => m[1]!)
        // Desfase solo en horas (`+00`, como lo escribe Postgres) → `+00:00`.
        .replaceFirstMapped(RegExp(r'(T[\d:.]+[+-]\d{2})$'), (m) => '${m[1]}:00');
    return DateTime.tryParse(iso)?.millisecondsSinceEpoch ?? fallback;
  }

  static FactionId? toFactionId(Object? value) => value is String ? FactionId.tryFromKey(value) : null;

  static LatLng? toLatLng(Object? lat, Object? lng) {
    final la = toNumber(lat, double.nan);
    final ln = toNumber(lng, double.nan);
    if (!la.isFinite || !ln.isFinite || la.abs() > 90 || ln.abs() > 180) return null;
    return LatLng(la, ln);
  }

  /// Solo recursos básicos conocidos, enteros y positivos.
  static Inventory toResourceMap(Object? value) {
    final src = asRecord(value);
    final out = <ItemId, int>{};
    if (src == null) return out;
    for (final id in resourceIds) {
      final n = toNumber(src[id.key], 0).floor();
      if (n > 0) out[id] = n;
    }
    return out;
  }

  /// Recursos a enviar (claves estables de la web, solo recursos y cantidades > 0).
  static Map<String, int> resourcesToJson(Map<ItemId, num> resources) => {
        for (final id in resourceIds)
          if (resources[id] case final n? when n.isFinite && n.floor() > 0) id.key: n.floor(),
      };

  /// Nombre público: sin caracteres de control, recortado a 40 (como el trigger de `profiles`).
  static String sanitizeName(String name) {
    var clean = name.replaceAll(_controlChars, '').trim();
    if (clean.runes.length > maxNameLength) clean = String.fromCharCodes(clean.runes.take(maxNameLength)).trim();
    return clean.isEmpty ? defaultPlayerName : clean;
  }

  /// Orden estable por un entero, de mayor a menor (como `Array.prototype.sort`).
  static List<T> stableSortDesc<T>(Iterable<T> items, int Function(T) key) {
    final indexed = items.indexed.toList()
      ..sort((a, b) {
        final c = key(b.$2).compareTo(key(a.$2));
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return [for (final e in indexed) e.$2];
  }

  /// Orden estable por distancia a [center] (igual que LocalRepository).
  static List<T> sortByDistance<T>(List<T> items, LatLng center, LatLng Function(T) position) {
    final indexed = [for (final (i, item) in items.indexed) (i, haversineM(center, position(item)), item)]
      ..sort((a, b) {
        final c = a.$2.compareTo(b.$2);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return [for (final e in indexed) e.$3];
  }

  // ---------------------------------------------------------------------------
  // Filas → modelos
  // ---------------------------------------------------------------------------

  static List<ShelterContribution> mapContributions(Object? value) {
    final parsed = parseJsonish(value);
    if (parsed is! List) return const [];
    final out = <ShelterContribution>[];
    for (final item in parsed) {
      final row = asRecord(item);
      if (row == null) continue;
      final playerId = toStr(row['player_id'] ?? row['playerId'], '');
      if (playerId.isEmpty) continue;
      out.add(ShelterContribution(
        playerId: playerId,
        playerName: toStr(row['player_name'] ?? row['playerName'], defaultPlayerName),
        amount: clampInt(row['amount'], 0, maxSafeInt, 0),
      ));
    }
    return stableSortDesc(out, (c) => c.amount);
  }

  /// Fila de `nearby_shelters` o jsonb de `get_shelter`/`create_shelter` (mismas claves).
  static Shelter? mapShelter(Object? value, {required int now}) {
    final row = asRecord(value);
    if (row == null) return null;
    final id = toStr(row['id'], '');
    final position = toLatLng(row['lat'], row['lng']);
    if (id.isEmpty || position == null) return null;
    final ownerId = toStr(row['owner_id'], '');
    return Shelter(
      id: id,
      name: toStr(row['name'], 'Refugio'),
      ownerId: ownerId.isEmpty ? systemOwnerId : ownerId,
      ownerName: toStr(row['owner_name'], systemOwnerName),
      factionId: toFactionId(row['faction_id']),
      level: clampInt(row['level'], 1, maxShelterLevel, 1),
      position: position,
      progress: toResourceMap(row['progress']),
      contributions: mapContributions(row['contributions']),
      createdAt: toTimeMs(row['created_at'], now),
    );
  }

  /// Reconstruye un [PlayerState] desde el jsonb guardado (`player_saves.save`).
  /// Igual que `normalizePlayer` de la web: null si no es un objeto con nombre;
  /// los campos que falten o tengan otro tipo toman el valor de un jugador nuevo.
  /// El id siempre es el uid de la sesión.
  static PlayerState? normalizePlayer(Object? save, String uid, {int? now}) {
    final json = asRecord(save);
    if (json == null || json['name'] is! String) return null;
    try {
      return PlayerState.fromJson(json, now: now).copyWith(id: uid);
    } on Exception {
      return null;
    }
  }

  static InteractionResult mapInteractionResult(Object? raw, InteractionRequest request) {
    final row = asRecord(raw);
    if (row == null) {
      throw const SupabaseRepositoryException(
        'Supabase: respuesta inválida de validate_interaction.',
        code: 'invalid_response',
      );
    }
    final distanceM = toNumber(row['distance_m'], haversineM(request.playerPosition, request.targetPosition));
    if (toBool(row['ok'])) return InteractionResult(ok: true, distanceM: distanceM);
    final reason = row['reason'];
    return InteractionResult(
      ok: false,
      reason: (reason is String ? InteractionRejection.tryFromKey(reason) : null) ?? InteractionRejection.outOfRange,
      distanceM: distanceM,
    );
  }

  static DonationRejection? toDonationRejection(Object? value) => switch (value) {
        'out_of_range' => DonationRejection.outOfRange,
        'not_found' => DonationRejection.notFound,
        'invalid_amount' => DonationRejection.invalidAmount,
        _ => null,
      };

  static DonationResult mapDonationResult(Object? raw, {required int now}) {
    final row = asRecord(raw);
    if (row == null) {
      throw const SupabaseRepositoryException(
        'Supabase: respuesta inválida de donate_to_shelter.',
        code: 'invalid_response',
      );
    }
    final ok = toBool(row['ok']);
    return DonationResult(
      ok: ok,
      reason: ok ? null : (toDonationRejection(row['reason']) ?? DonationRejection.invalidAmount),
      shelter: mapShelter(row['shelter'], now: now),
      accepted: ok ? toResourceMap(row['accepted']) : const {},
      leveledUp: ok && toBool(row['leveled_up']),
    );
  }

  /// Filas de `factions_overview`. Base sin datos de referencia: las facciones
  /// del cliente sin estadísticas (igual que la web).
  static List<Faction> mapFactions(Object? raw) {
    final out = <Faction>[];
    for (final row in toRows(raw)) {
      final id = toFactionId(row['id']);
      if (id == null) continue;
      final def = factionDefs[id]!;
      out.add(Faction(
        id: id,
        name: toStr(row['name'], def.name),
        motto: toStr(row['motto'], def.motto),
        color: toStr(row['color'], def.color),
        bonusDescription: toStr(row['bonus_description'], def.bonusDescription),
        members: clampInt(row['members'], 0, maxSafeInt, 0),
        totalContribution: clampInt(row['total_contribution'], 0, maxSafeInt, 0),
      ));
    }
    if (out.isEmpty) return [for (final id in factionIds) factionDefs[id]!.toFaction()];
    return out;
  }

  static List<LeaderboardEntry> mapLeaderboard(Object? raw) {
    final out = <LeaderboardEntry>[];
    for (final row in toRows(raw)) {
      final playerId = toStr(row['player_id'], '');
      if (playerId.isEmpty) continue;
      out.add(LeaderboardEntry(
        playerId: playerId,
        playerName: toStr(row['player_name'], defaultPlayerName),
        factionId: toFactionId(row['faction_id']),
        level: clampInt(row['level'], 1, 1000, 1),
        contribution: clampInt(row['contribution'], 0, maxSafeInt, 0),
      ));
    }
    return stableSortDesc(out, (e) => e.contribution);
  }

  static List<PublicSurvivor> mapSurvivors(Object? raw, {required int now}) {
    final out = <PublicSurvivor>[];
    for (final row in toRows(raw)) {
      final id = toStr(row['player_id'], '');
      final approxPosition = toLatLng(row['lat'], row['lng']);
      if (id.isEmpty || approxPosition == null) continue;
      out.add(PublicSurvivor(
        id: id,
        name: toStr(row['name'], defaultPlayerName),
        level: clampInt(row['level'], 1, 1000, 1),
        factionId: toFactionId(row['faction_id']),
        approxPosition: approxPosition,
        lastSeenAt: toTimeMs(row['last_seen_at'], now),
      ));
    }
    return out;
  }

  /// Filas de `shelter_pulse_totals` → total por nodo.
  static Map<String, int> mapPulseTotals(Object? raw) => {
        for (final row in toRows(raw))
          if (toStr(row['shelter_id'], '') case final id when id.isNotEmpty) id: clampInt(row['total'], 0, maxSafeInt, 0),
      };

  // ---------------------------------------------------------------------------
  // Modelos → parámetros / columnas
  // ---------------------------------------------------------------------------

  static String? _isoOrNull(int? ms) => ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

  /// Argumentos de `validate_interaction`. Única RPC (con `donate_to_shelter`) que
  /// recibe la posición REAL, solo para medir la distancia.
  static Map<String, dynamic> interactionParams(InteractionRequest request) => {
        'p_spawn_id': request.targetId,
        'p_target_lat': finiteOrNull(request.targetPosition.lat),
        'p_target_lng': finiteOrNull(request.targetPosition.lng),
        'p_lat': finiteOrNull(request.playerPosition.lat),
        'p_lng': finiteOrNull(request.playerPosition.lng),
        'p_accuracy': finiteOrNull(request.accuracyM),
        'p_expires_at': _isoOrNull(request.targetExpiresAt),
        'p_action': request.action.key,
      };

  /// Argumentos de `donate_to_shelter` (la posición real solo valida el alcance).
  static Map<String, dynamic> donationParams(DonationInput input) => {
        'p_shelter_id': input.shelterId,
        'p_resources': resourcesToJson(input.resources),
        'p_lat': finiteOrNull(input.playerPosition.lat),
        'p_lng': finiteOrNull(input.playerPosition.lng),
        'p_accuracy': finiteOrNull(input.accuracyM),
      };

  /// Argumentos de `create_shelter`: la posición PÚBLICA ya ajustada por el
  /// llamador (el servidor la vuelve a engrosar a una grilla de 0,001°).
  static Map<String, dynamic> createShelterParams(CreateShelterInput input) => {
        'p_name': input.name,
        'p_lat': finiteOrNull(input.publicPosition.lat),
        'p_lng': finiteOrNull(input.publicPosition.lng),
      };

  /// Argumentos de `publish_presence`: siempre la posición DIFUMINADA
  /// (`fuzzPosition` con el id del jugador, igual que la web). null si no es válida.
  static Map<String, dynamic>? presenceParams(PlayerState player, LatLng approxPosition) {
    if (!approxPosition.lat.isFinite || !approxPosition.lng.isFinite) return null;
    final fuzzed = fuzzPosition(approxPosition, player.id);
    return {'p_lat': fuzzed.lat, 'p_lng': fuzzed.lng};
  }

  /// Columnas públicas de `profiles` que espeja cada guardado.
  static Map<String, dynamic> profileMirror(PlayerState player) => {
        'name': sanitizeName(player.name),
        'level': clampInt(player.level, 1, 1000, 1),
        'xp': clampInt(player.xp, 0, maxSafeInt, 0),
        'faction_id': player.factionId?.key,
      };
}
