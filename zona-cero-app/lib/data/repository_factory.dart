import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart'
    show FlutterAuthClientOptions, SharedPreferencesLocalStorage, Supabase, SupabaseClient;

import 'game_repository.dart';
import 'local_repository.dart';
import 'storage.dart';
import 'supabase_repository.dart';

// Elección del repositorio de datos (igual que `getRepository()` de la web):
// con credenciales de Supabase se usa el backend real; sin ellas, o si falla la
// conexión, el juego sigue completo con LocalRepository (dispositivo + comunidad
// simulada).
//
//   flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
//               --dart-define=SUPABASE_ANON_KEY=<clave anon/publishable>

const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Clave (SharedPreferences) donde se guarda la sesión anónima. Igual que la web
/// (`storageKey: 'zc:supabase-auth'`); mantiene el mismo jugador entre aperturas.
const String supabaseAuthStorageKey = 'zc:supabase-auth';

/// true si la app se compiló con `SUPABASE_URL` y `SUPABASE_ANON_KEY`.
bool get hasSupabaseConfig => _supabaseUrl.trim().isNotEmpty && _supabaseAnonKey.trim().isNotEmpty;

/// Crea el cliente de Supabase a partir de la URL y la clave.
typedef SupabaseConnector = Future<SupabaseClient> Function(String url, String anonKey);

/// Devuelve el repositorio de datos según los `--dart-define` de compilación.
///
/// Con Supabase ya deja la sesión anónima iniciada (`init()`), así que un fallo
/// de red, de credenciales o del proveedor anónimo cae a [LocalRepository] (con
/// un `debugPrint`) en vez de romper el arranque.
Future<GameRepository> createRepository(KeyValueStore store) =>
    createRepositoryFromConfig(store, url: _supabaseUrl, anonKey: _supabaseAnonKey);

/// Igual que [createRepository] pero con la configuración explícita (tests).
@visibleForTesting
Future<GameRepository> createRepositoryFromConfig(
  KeyValueStore store, {
  required String url,
  required String anonKey,
  SupabaseConnector? connect,
  Duration timeout = const Duration(seconds: 12),
}) async {
  final cleanUrl = url.trim().replaceFirst(RegExp(r'/+$'), '');
  final key = anonKey.trim();
  if (cleanUrl.isEmpty || key.isEmpty) {
    if (cleanUrl.isNotEmpty || key.isNotEmpty) {
      debugPrint('[Zona Cero] Falta SUPABASE_URL o SUPABASE_ANON_KEY: usando datos locales.');
    }
    return LocalRepository(store);
  }
  final uri = Uri.tryParse(cleanUrl);
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http')) || uri.host.isEmpty) {
    debugPrint('[Zona Cero] SUPABASE_URL inválida ("$cleanUrl"): usando datos locales.');
    return LocalRepository(store);
  }

  try {
    final client = await (connect ?? initializeSupabaseClient)(cleanUrl, key).timeout(timeout);
    final repo = SupabaseRepository(client, store: store);
    await repo.init().timeout(timeout);
    return repo;
  } catch (e) {
    // Cualquier fallo (red, credenciales, proveedor anónimo deshabilitado…): modo local.
    debugPrint('[Zona Cero] Supabase no disponible, usando datos locales. $e');
    return LocalRepository(store);
  }
}

/// Inicializa `Supabase.instance` (una sola vez por proceso) y devuelve su cliente.
/// La sesión se persiste en SharedPreferences para conservar el uid anónimo.
Future<SupabaseClient> initializeSupabaseClient(String url, String anonKey) async {
  final supabase = await Supabase.initialize(
    url: url,
    publishableKey: anonKey,
    authOptions: FlutterAuthClientOptions(
      // Sin deep links de auth: la sesión es anónima (igual que detectSessionInUrl: false en la web).
      detectSessionInUri: false,
      localStorage: SharedPreferencesLocalStorage(persistSessionKey: supabaseAuthStorageKey),
    ),
  );
  return supabase.client;
}
