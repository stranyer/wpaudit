import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Almacenamiento clave/valor JSON sobre SharedPreferences, tolerante a fallos.
class KeyValueStore {
  KeyValueStore._(this._prefs);

  final SharedPreferences? _prefs;
  final Map<String, String> _memory = {};

  static Future<KeyValueStore> open() async {
    try {
      return KeyValueStore._(await SharedPreferences.getInstance());
    } catch (_) {
      return KeyValueStore._(null);
    }
  }

  /// Solo memoria (tests).
  factory KeyValueStore.memory() => KeyValueStore._(null);

  String? getString(String key) => _prefs?.getString(key) ?? _memory[key];

  Future<void> setString(String key, String value) async {
    _memory[key] = value;
    try {
      await _prefs?.setString(key, value);
    } catch (_) {
      // Sin espacio u otro error: el juego sigue en memoria.
    }
  }

  Future<void> remove(String key) async {
    _memory.remove(key);
    await _prefs?.remove(key);
  }

  T? readJson<T>(String key, T Function(Object? json) parse) {
    final raw = getString(key);
    if (raw == null) return null;
    try {
      return parse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJson(String key, Object? value) => setString(key, jsonEncode(value));
}
