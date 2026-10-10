// Preferencia de sonido del jugador (encendido + volumen), guardada en la clave
// `zc:audio` del almacenamiento local: {"enabled": true, "master": 0.9}.

import '../data/storage.dart';
import 'sfx.dart';

abstract final class AudioPrefs {
  static const key = 'zc:audio';

  /// Aplica a [Sfx] lo guardado en [store] (si no hay nada, deja los valores por defecto).
  static void apply(KeyValueStore store) {
    final j = store.readJson(key, (j) => j is Map ? Map<String, dynamic>.from(j) : null);
    if (j == null) return;
    final enabled = j['enabled'];
    final master = j['master'];
    if (enabled is bool) Sfx.enabled = enabled;
    if (master is num && master.isFinite) Sfx.master = master.toDouble();
  }

  /// Abre el almacenamiento y aplica la preferencia (se usa al arrancar, antes
  /// de que exista `app.store`).
  static Future<void> restore() async {
    try {
      apply(await KeyValueStore.open());
    } catch (_) {
      // Sin almacenamiento: quedan los valores por defecto.
    }
  }

  static Future<void> save(KeyValueStore store) =>
      store.writeJson(key, {'enabled': Sfx.enabled, 'master': double.parse(Sfx.master.toStringAsFixed(2))});
}
