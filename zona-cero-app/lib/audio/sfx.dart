// Sonidos del juego. API única para toda la app: `Sfx.play(SfxId.scanPulse)`.
// Los archivos viven en assets/audio/<nombre>.mp3 (ver [SfxId.file]).

import 'package:flutter/foundation.dart';

/// Efectos de sonido.
enum SfxId {
  // Interfaz
  tap('ui_tap'),
  tab('ui_tab'),
  open('ui_open'),
  error('ui_error'),
  // Mapa
  scanCharge('scan_charge'),
  scanPulse('scan_pulse'),
  contactPing('contact_ping'),
  signal('signal_radio'),
  loot('loot'),
  deliver('deliver'),
  levelUp('level_up'),
  // Combate: criaturas
  zombieGroan('zombie_groan'),
  zombieAttack('zombie_attack'),
  zombieHurt('zombie_hurt'),
  zombieDeath('zombie_death'),
  screamerScream('screamer_scream'),
  bruteRoar('brute_roar'),
  bloaterBurst('bloater_burst'),
  runnerSnarl('runner_snarl'),
  // Combate: jugador
  pistolShot('pistol_shot'),
  shotgunShot('shotgun_shot'),
  meleeSwing('melee_swing'),
  meleeImpact('melee_impact'),
  headshot('headshot'),
  emptyClick('empty_click'),
  playerHurt('player_hurt'),
  heal('heal'),
  defend('defend'),
  flee('flee'),
  victory('victory'),
  defeat('defeat'),
  heartbeat('heartbeat');

  const SfxId(this.file);

  /// Nombre del archivo (sin extensión) en assets/audio/.
  final String file;

  /// Ruta del asset.
  String get asset => 'assets/audio/$file.mp3';
}

/// Ambientes en loop.
enum Ambience {
  map('amb_city_rain'),
  combat('amb_combat'),
  shelter('amb_shelter');

  const Ambience(this.file);
  final String file;

  /// Ruta del asset.
  String get asset => 'assets/audio/$file.mp3';
}

/// Motor de audio intercambiable. Por defecto no suena nada (tests, web sin
/// interacción); `lib/audio/audio_engine.dart` registra la implementación real.
///
/// Contrato: ningún método debe lanzar por un archivo faltante o un audio no
/// disponible (igual la fachada [Sfx] atrapa cualquier error).
abstract class SfxBackend {
  Future<void> init();

  /// [volume] ya viene multiplicado por [Sfx.master] (0..1); [rate] entre 0.5 y 2.
  void play(SfxId id, {double volume = 1, double rate = 1});

  /// `null` = silencio. Un ambiente nuevo hace fundido cruzado con el anterior;
  /// el mismo ambiente con otro [volume] solo ajusta el nivel.
  void ambience(Ambience? a, {double volume = 0.5});
  void dispose();
}

class _SilentBackend implements SfxBackend {
  @override
  Future<void> init() async {}
  @override
  void play(SfxId id, {double volume = 1, double rate = 1}) {}
  @override
  void ambience(Ambience? a, {double volume = 0.5}) {}
  @override
  void dispose() {}
}

/// Fachada estática de sonido.
///
/// [enabled] y [master] se pueden cambiar en caliente: el ambiente actual se
/// reaplica (se silencia, vuelve o cambia de nivel) sin que la pantalla que lo
/// pidió tenga que volver a llamarlo.
abstract final class Sfx {
  static SfxBackend _backend = _SilentBackend();
  static bool _enabled = true;
  static double _master = 0.9;
  static Ambience? _ambience;
  static double _ambienceVolume = 0.5;

  /// Sonido activado (preferencia del jugador).
  static bool get enabled => _enabled;
  static set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    _applyAmbience();
  }

  /// Volumen general 0..1.
  static double get master => _master;
  static set master(double value) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0).toDouble();
    if (v == _master) return;
    _master = v;
    _applyAmbience();
  }

  /// Último ambiente pedido (aunque el sonido esté apagado).
  static Ambience? get currentAmbience => _ambience;

  /// Volumen base (sin [master]) del último ambiente pedido.
  static double get currentAmbienceVolume => _ambienceVolume;

  static SfxBackend get backend => _backend;

  static void install(SfxBackend backend) => _backend = backend;

  static Future<void> init() async {
    try {
      await _backend.init();
    } catch (e) {
      debugPrint('[Zona Cero] Audio no disponible: $e');
    }
  }

  static void play(SfxId id, {double volume = 1, double rate = 1}) {
    if (!_enabled || _master <= 0) return;
    final v = (volume.isNaN ? 0.0 : volume * _master).clamp(0.0, 1.0).toDouble();
    if (v <= 0) return;
    final r = rate.isFinite ? rate.clamp(0.5, 2.0).toDouble() : 1.0;
    _guard(() => _backend.play(id, volume: v, rate: r));
  }

  static void ambience(Ambience? a, {double volume = 0.5}) {
    _ambience = a;
    _ambienceVolume = volume.isNaN ? 0.0 : volume.clamp(0.0, 1.0).toDouble();
    _applyAmbience();
  }

  static void _applyAmbience() {
    final on = _enabled && _master > 0;
    final v = (_ambienceVolume * _master).clamp(0.0, 1.0).toDouble();
    _guard(() => _backend.ambience(on ? _ambience : null, volume: v));
  }

  /// Un error de audio jamás debe tumbar la interfaz.
  static void _guard(void Function() fn) {
    try {
      fn();
    } catch (e) {
      debugPrint('[Zona Cero] Error de audio: $e');
    }
  }

  /// Solo para tests: vuelve al estado inicial (motor silencioso).
  @visibleForTesting
  static void resetForTest() {
    _backend = _SilentBackend();
    _enabled = true;
    _master = 0.9;
    _ambience = null;
    _ambienceVolume = 0.5;
  }
}
