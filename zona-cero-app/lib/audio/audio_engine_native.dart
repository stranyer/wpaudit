// Motor nativo (Android / iOS / escritorio) sobre `audioplayers`.

import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'audio_engine.dart';
import 'sfx.dart';

SfxBackend createPlatformEngine() => NativeAudioEngine();

/// Contexto de audio: sonido de juego que se mezcla con la música del usuario
/// (sin pedir foco en Android; categoría "ambient" en iOS, que respeta el
/// interruptor de silencio).
AudioContext _gameAudioContext() => AudioContext(
      android: const AudioContextAndroid(
        isSpeakerphoneOn: false,
        stayAwake: false,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.game,
        audioFocus: AndroidAudioFocus.none,
      ),
      iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
    );

class NativeAudioEngine with WidgetsBindingObserver implements SfxBackend {
  NativeAudioEngine();

  final AudioCache _cache = AudioCache(prefix: 'assets/audio/');
  final Map<SfxId, _Pool> _pools = {};
  final Map<Ambience, _Loop> _loops = {};
  Future<void>? _initFuture;
  bool _observing = false;
  bool _backgrounded = false;
  bool _disposed = false;
  Timer? _ticker;
  int _tickCount = 0;

  static const _tick = Duration(milliseconds: 50);

  // ---------------------------------------------------------------------------
  // Init / precarga
  // ---------------------------------------------------------------------------

  @override
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    _observing = true;
    try {
      AudioLogger.logLevel = kDebugMode ? AudioLogLevel.error : AudioLogLevel.none;
      await AudioPlayer.global.setAudioContext(_gameAudioContext()).timeout(SfxTuning.loadTimeout);
    } catch (e) {
      debugPrint('[Zona Cero] Audio: sin contexto global ($e)');
    }
    // Precarga en tandas chicas para no saturar el canal de plataforma.
    const batch = 6;
    final ids = SfxId.values;
    for (var i = 0; i < ids.length && !_disposed; i += batch) {
      await Future.wait(ids.skip(i).take(batch).map(_preload));
    }
    final missing = _pools.values.where((p) => p.failed).map((p) => p.id.file).toList();
    if (missing.isNotEmpty) debugPrint('[Zona Cero] Audio: sin cargar ${missing.join(', ')}');
  }

  Future<void> _preload(SfxId id) async {
    final pool = _pools.putIfAbsent(id, () => _Pool(id, SfxTuning.voices(id)));
    final p = await _newVoice(id);
    if (p == null) {
      pool.failed = true;
      return;
    }
    pool.players.add(p);
  }

  /// Crea una voz de baja latencia lista para disparar (o null si no se pudo).
  Future<AudioPlayer?> _newVoice(SfxId id) async {
    AudioPlayer? p;
    try {
      p = AudioPlayer(playerId: 'zc_${id.name}_${DateTime.now().microsecondsSinceEpoch}')..audioCache = _cache;
      await p.setPlayerMode(PlayerMode.lowLatency);
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setSource(AssetSource('${id.file}.mp3')).timeout(SfxTuning.loadTimeout);
      return p;
    } catch (e) {
      debugPrint('[Zona Cero] Audio: no se pudo cargar ${id.file} ($e)');
      _safe(p?.dispose());
      return null;
    }
  }

  Future<void> _grow(_Pool pool) async {
    pool.growing = true;
    try {
      final p = await _newVoice(pool.id);
      if (p != null) {
        if (_disposed) {
          _safe(p.dispose());
        } else {
          pool.players.add(p);
        }
      }
    } finally {
      pool.growing = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Efectos
  // ---------------------------------------------------------------------------

  @override
  void play(SfxId id, {double volume = 1, double rate = 1}) {
    if (_disposed || _backgrounded) return;
    final pool = _pools[id];
    // Todavía cargando o archivo perdido: se omite (no tiene sentido sonar tarde).
    if (pool == null || pool.failed || pool.players.isEmpty) return;
    final p = pool.players[pool.cursor % pool.players.length];
    pool.cursor++;
    if (pool.players.length < pool.max && !pool.growing) unawaited(_grow(pool));
    unawaited(_trigger(p, volume, rate));
  }

  Future<void> _trigger(AudioPlayer p, double volume, double rate) async {
    try {
      // En baja latencia no hay aviso de fin: siempre se reinicia la voz.
      await p.stop();
      await p.setVolume(volume);
      await p.setPlaybackRate(rate);
      await p.resume();
    } catch (e) {
      if (kDebugMode) debugPrint('[Zona Cero] Audio: falló un efecto ($e)');
    }
  }

  // ---------------------------------------------------------------------------
  // Ambientes
  // ---------------------------------------------------------------------------

  @override
  void ambience(Ambience? a, {double volume = 0.5}) {
    if (_disposed) return;
    for (final l in _loops.values) {
      if (l.ambience != a && l.gain.target > 0) l.gain.to(0, SfxTuning.ambienceFade);
    }
    if (a != null) {
      final l = _loops.putIfAbsent(a, () => _Loop(a));
      final wasSilent = l.gain.target <= 0;
      l.gain.to(volume, wasSilent ? SfxTuning.ambienceFade : SfxTuning.ambienceLevelFade);
      if (!l.playing) unawaited(_start(l));
    }
    _ensureTicker();
  }

  Future<void> _start(_Loop l) async {
    if (l.starting) return;
    l.starting = true;
    try {
      if (!await _load(l)) return;
      if (_disposed || l.gain.target <= 0 || l.playing) return;
      final deck = l.decks[l.active];
      await deck.setVolume(0);
      l.sentVolumes = [0, 0];
      l.playing = true;
      if (!_backgrounded) await deck.resume();
      _ensureTicker();
    } catch (e) {
      debugPrint('[Zona Cero] Audio: no se pudo iniciar ${l.ambience.file} ($e)');
      l.playing = false;
    } finally {
      l.starting = false;
    }
  }

  Future<bool> _load(_Loop l) async {
    if (l.failed) return false;
    if (l.decks.length == 2) return true;
    try {
      for (var i = 0; i < 2; i++) {
        final p = AudioPlayer(playerId: 'zc_${l.ambience.name}_$i')..audioCache = _cache;
        l.decks.add(p);
        l.subs.add(p.onPlayerComplete.listen((_) => _onDeckComplete(l, i), onError: (Object _) {}));
        await p.setPlayerMode(PlayerMode.mediaPlayer);
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setSource(AssetSource('${l.ambience.file}.mp3')).timeout(SfxTuning.loadTimeout);
      }
      final d = await l.decks.first.getDuration();
      // Sin duración conocida (o archivo muy corto) se usa el loop nativo.
      if (d == null || d <= SfxTuning.loopOverlap * 2) {
        l.duration = null;
        await l.decks.first.setReleaseMode(ReleaseMode.loop);
      } else {
        l.duration = d;
      }
      return true;
    } catch (e) {
      debugPrint('[Zona Cero] Audio: ambiente ${l.ambience.file} no disponible ($e)');
      l.failed = true;
      for (final s in l.subs) {
        unawaited(s.cancel());
      }
      for (final p in l.decks) {
        _safe(p.dispose());
      }
      l.subs.clear();
      l.decks.clear();
      return false;
    }
  }

  void _ensureTicker() {
    if (_ticker != null || _disposed) return;
    _ticker = Timer.periodic(_tick, (_) => _onTick());
  }

  void _onTick() {
    if (_backgrounded) return;
    _tickCount++;
    final dt = _tick.inMicroseconds / 1e6;
    var busy = false;
    for (final l in _loops.values) {
      if (!l.playing) {
        if (l.starting) busy = true;
        continue;
      }
      busy = true;
      l.gain.tick(dt);
      // Punto de loop: solapar la otra pletina con un fundido de igual potencia.
      if (l.handover != null) {
        l.handover!.tick(dt);
        if (l.handover!.done) _finishHandover(l);
      } else if (l.duration != null && _tickCount % 5 == 0 && !l.polling) {
        unawaited(_pollLoop(l));
      }
      _pushVolumes(l);
      if (l.gain.done && l.gain.value <= 0) unawaited(_stopLoop(l));
    }
    if (!busy) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _pollLoop(_Loop l) async {
    l.polling = true;
    try {
      final pos = await l.decks[l.active].getCurrentPosition();
      final dur = l.duration;
      if (pos == null || dur == null || !l.playing || l.handover != null) return;
      if (dur - pos <= SfxTuning.loopOverlap) {
        final next = l.decks[1 - l.active];
        await next.setVolume(0);
        l.sentVolumes[1 - l.active] = 0;
        await next.resume();
        // El sondeo llega entre 0 y ~300 ms tarde: la rampa termina antes del final de la pletina saliente.
        l.handover = GainRamp(0)..to(1, SfxTuning.loopOverlap - const Duration(milliseconds: 400));
      }
    } catch (_) {
      // Una lectura fallida se reintenta en el próximo sondeo.
    } finally {
      l.polling = false;
    }
  }

  /// Red de seguridad: si la pletina activa terminó sin que el sondeo llegara a
  /// solaparla (p. ej. el sistema demoró los timers), se salta a la otra.
  void _onDeckComplete(_Loop l, int deck) {
    if (_disposed || !l.playing || _backgrounded || deck != l.active) return;
    if (l.handover != null) {
      _finishHandover(l);
      return;
    }
    if (l.duration == null) return; // loop nativo
    l.active = 1 - l.active;
    l.sentVolumes[l.active] = -1; // forzar el envío del volumen
    _pushVolumes(l);
    _safe(l.decks[l.active].resume());
  }

  void _finishHandover(_Loop l) {
    final old = l.decks[l.active];
    l.active = 1 - l.active;
    l.handover = null;
    // La pletina saliente ya terminó (o está por terminar): queda en 0 para el próximo loop.
    _safe(old.stop());
    l.sentVolumes[1 - l.active] = 0;
  }

  void _pushVolumes(_Loop l) {
    final h = l.handover?.value ?? 0;
    final g = l.gain.value.clamp(0.0, 1.0);
    final vols = [0.0, 0.0];
    vols[l.active] = g * math.cos(h * math.pi / 2);
    if (l.handover != null) vols[1 - l.active] = g * math.sin(h * math.pi / 2);
    for (var i = 0; i < 2 && i < l.decks.length; i++) {
      if ((vols[i] - l.sentVolumes[i]).abs() > 0.004 || (vols[i] == 0 && l.sentVolumes[i] != 0)) {
        l.sentVolumes[i] = vols[i];
        _safe(l.decks[i].setVolume(vols[i]));
      }
    }
  }

  Future<void> _stopLoop(_Loop l) async {
    if (!l.playing) return;
    l.playing = false;
    l.handover = null;
    l.active = 0;
    for (final p in l.decks) {
      _safe(p.stop());
    }
  }

  // ---------------------------------------------------------------------------
  // Ciclo de vida: los ambientes se pausan en segundo plano.
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (_backgrounded) return;
        _backgrounded = true;
        _ticker?.cancel();
        _ticker = null;
        for (final l in _loops.values) {
          if (!l.playing) continue;
          for (final p in l.decks) {
            _safe(p.pause());
          }
        }
      case AppLifecycleState.resumed:
        if (!_backgrounded) return;
        _backgrounded = false;
        for (final l in _loops.values) {
          if (!l.playing) continue;
          if (l.gain.target <= 0) {
            unawaited(_stopLoop(l));
            continue;
          }
          _safe(l.decks[l.active].resume());
          if (l.handover != null) _safe(l.decks[1 - l.active].resume());
        }
        _ensureTicker();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _ticker = null;
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    for (final pool in _pools.values) {
      for (final p in pool.players) {
        _safe(p.dispose());
      }
    }
    for (final l in _loops.values) {
      for (final s in l.subs) {
        unawaited(s.cancel());
      }
      for (final p in l.decks) {
        _safe(p.dispose());
      }
    }
    _pools.clear();
    _loops.clear();
  }

  static void _safe(Future<void>? f) {
    f?.catchError((Object _) {});
  }
}

class _Pool {
  _Pool(this.id, this.max);
  final SfxId id;
  final int max;
  final List<AudioPlayer> players = [];
  int cursor = 0;
  bool failed = false;
  bool growing = false;
}

class _Loop {
  _Loop(this.ambience);
  final Ambience ambience;
  final List<AudioPlayer> decks = [];
  final List<StreamSubscription<void>> subs = [];
  final GainRamp gain = GainRamp(0);
  List<double> sentVolumes = [0, 0];
  int active = 0;
  Duration? duration;
  GainRamp? handover;
  bool playing = false;
  bool starting = false;
  bool polling = false;
  bool failed = false;
}
