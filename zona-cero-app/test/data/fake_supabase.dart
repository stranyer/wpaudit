// Servidor HTTP local (loopback) que imita lo justo de GoTrue + PostgREST para
// probar SupabaseRepository de punta a punta sin red externa ni paquetes extra.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart' show AuthClientOptions, SupabaseClient;

const fakeUid = '0a0b0c0d-1111-4222-8333-444455556666';
const fakeAccessToken = 'token-de-prueba';

class FakeResponse {
  const FakeResponse(this.status, [this.body]);

  /// Error como lo devuelve PostgREST para `raise exception '<code>'`.
  FakeResponse.raise(String code) : this(400, {'code': 'P0001', 'details': null, 'hint': null, 'message': code});

  /// RPC inexistente en el caché de esquema de PostgREST.
  FakeResponse.missing(String fn)
      : this(404, {
          'code': 'PGRST202',
          'details': 'Searched for the function public.$fn',
          'hint': null,
          'message': 'Could not find the function public.$fn in the schema cache',
        });

  final int status;
  final Object? body;
}

class RecordedRequest {
  RecordedRequest(this.method, this.path, this.query, this.body, this.headers);

  final String method;
  final String path;
  final Map<String, String> query;
  final Object? body;
  final HttpHeaders headers;

  String? get prefer => headers.value('prefer');
  String? get authorization => headers.value('authorization');

  @override
  String toString() => '$method $path $query ${jsonEncode(body)}';
}

class FakeSupabase {
  FakeSupabase._(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final List<RecordedRequest> requests = [];
  final List<SupabaseClient> _clients = [];

  bool anonymousEnabled = true;
  int signups = 0;

  /// Respuestas de `/rest/v1/rpc/<fn>`. Sin entrada: la RPC no existe (PGRST202).
  final Map<String, FakeResponse Function(Map<String, dynamic> params)> rpc = {};

  /// Contenido de `player_saves.save` del jugador (null = sin partida).
  Object? playerSave;

  /// Respuesta del PATCH a `profiles` (204 por defecto).
  FakeResponse profilePatch = const FakeResponse(204);

  /// Demora antes de responder (para probar tiempos límite).
  Duration delay = Duration.zero;

  static Future<FakeSupabase> start() async => FakeSupabase._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  String get url => 'http://${_server.address.address}:${_server.port}';

  /// Cliente apuntado a este servidor (se cierra en [close]).
  SupabaseClient client() {
    final c = SupabaseClient(url, 'anon-key', authOptions: const AuthClientOptions(autoRefreshToken: false));
    _clients.add(c);
    return c;
  }

  Iterable<RecordedRequest> rpcCalls(String fn) => requests.where((r) => r.path == '/rest/v1/rpc/$fn');

  Future<void> close() async {
    for (final c in _clients) {
      await c.dispose();
    }
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final raw = await utf8.decodeStream(req);
    final body = raw.isEmpty ? null : jsonDecode(raw);
    final path = req.uri.path;
    requests.add(RecordedRequest(req.method, path, req.uri.queryParameters, body, req.headers));
    if (delay > Duration.zero) await Future<void>.delayed(delay);

    final FakeResponse res;
    if (path == '/auth/v1/signup' && req.method == 'POST') {
      res = _signup();
    } else if (path == '/rest/v1/profiles') {
      res = req.method == 'PATCH' ? profilePatch : const FakeResponse(201);
    } else if (path == '/rest/v1/player_saves') {
      res = req.method == 'GET'
          ? FakeResponse(200, [
              if (playerSave != null) {'save': playerSave},
            ])
          : const FakeResponse(201);
    } else if (path.startsWith('/rest/v1/rpc/')) {
      final fn = path.substring('/rest/v1/rpc/'.length);
      final handler = rpc[fn];
      res = handler == null ? FakeResponse.missing(fn) : handler(body is Map ? body.cast<String, dynamic>() : const {});
    } else {
      res = const FakeResponse(404, {'message': 'not found'});
    }

    try {
      req.response
        ..statusCode = res.status
        ..headers.set('x-supabase-api-version', '2024-01-01');
      if (res.body != null) {
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(res.body));
      }
      await req.response.close();
    } on Object {
      // El cliente ya se fue (p. ej. por tiempo límite).
    }
  }

  FakeResponse _signup() {
    if (!anonymousEnabled) {
      return const FakeResponse(422, {'code': 'anonymous_provider_disabled', 'message': 'Anonymous sign-ins are disabled'});
    }
    signups++;
    return const FakeResponse(200, {
      'access_token': fakeAccessToken,
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': 'refresh-de-prueba',
      'user': {
        'id': fakeUid,
        'aud': 'authenticated',
        'role': 'authenticated',
        'is_anonymous': true,
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-10-10T00:00:00Z',
      },
    });
  }
}

/// Espera hasta que [condition] se cumpla (o falla a los 3 s).
Future<void> eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('la condición no se cumplió');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
