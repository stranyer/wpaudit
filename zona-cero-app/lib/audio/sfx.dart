// Sonidos del juego. API única para toda la app: `Sfx.play(SfxId.scanPulse)`.
// Los archivos viven en assets/audio/<nombre>.mp3 (ver [SfxId.file]).

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
}

/// Ambientes en loop.
enum Ambience {
  map('amb_city_rain'),
  combat('amb_combat'),
  shelter('amb_shelter');

  const Ambience(this.file);
  final String file;
}

/// Motor de audio intercambiable. Por defecto no suena nada (tests, web sin
/// interacción); `lib/audio/audio_engine.dart` registra la implementación real.
abstract class SfxBackend {
  Future<void> init();
  void play(SfxId id, {double volume = 1, double rate = 1});
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
abstract final class Sfx {
  static SfxBackend _backend = _SilentBackend();

  /// Sonido activado (preferencia del jugador).
  static bool enabled = true;

  /// Volumen general 0..1.
  static double master = 0.9;

  static void install(SfxBackend backend) => _backend = backend;

  static Future<void> init() => _backend.init();

  static void play(SfxId id, {double volume = 1, double rate = 1}) {
    if (!enabled) return;
    _backend.play(id, volume: (volume * master).clamp(0.0, 1.0), rate: rate);
  }

  static void ambience(Ambience? a, {double volume = 0.5}) => _backend.ambience(enabled ? a : null, volume: volume * master);
}
