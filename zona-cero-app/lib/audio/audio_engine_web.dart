// Motor web sobre la Web Audio API (sin dependencias: `dart:js_interop`).
//
// - Un único AudioContext para todo el juego (los reproductores HTML <audio>
//   crean uno por sonido y no escalan a ~40 voces).
// - Los efectos se decodifican al iniciar con un OfflineAudioContext, que no está
//   sujeto a la política de autoplay: no hay avisos en consola antes del primer
//   gesto.
// - El AudioContext real se crea en el primer gesto del usuario (pointerup,
//   touchend, keydown…). Antes de eso los efectos se omiten y el ambiente pedido
//   queda pendiente hasta ese momento.
// - Ambientes: AudioBufferSourceNode en loop (sin cortes; se recortan los
//   silencios de relleno del MP3 en los extremos) con fundidos programados.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'audio_engine.dart';
import 'sfx.dart';

SfxBackend createPlatformEngine() => WebAudioEngine();

// ---------------------------------------------------------------------------
// Interop mínimo con la Web Audio API
// ---------------------------------------------------------------------------

extension type _BaseCtx._(JSObject _) implements JSObject {
  external JSPromise<_AudioBuf> decodeAudioData(JSArrayBuffer data);
}

@JS('AudioContext')
extension type _AudioCtx._(JSObject _) implements _BaseCtx {
  external _AudioCtx();
  external String get state;
  external double get currentTime;
  external _AudioNode get destination;
  external JSPromise<JSAny?> resume();
  external JSPromise<JSAny?> suspend();
  external JSPromise<JSAny?> close();
  external _GainNode createGain();
  external _BufferSource createBufferSource();
}

@JS('OfflineAudioContext')
extension type _OfflineCtx._(JSObject _) implements _BaseCtx {
  external _OfflineCtx(int numberOfChannels, int length, double sampleRate);
}

extension type _AudioNode._(JSObject _) implements JSObject {
  external void connect(_AudioNode destination);
  external void disconnect();
}

extension type _AudioParam._(JSObject _) implements JSObject {
  external double get value;
  external set value(double v);
  external void setValueAtTime(double value, double startTime);
  external void linearRampToValueAtTime(double value, double endTime);
  external void setTargetAtTime(double target, double startTime, double timeConstant);
  external void cancelScheduledValues(double startTime);
}

extension type _GainNode._(JSObject _) implements _AudioNode {
  external _AudioParam get gain;
}

extension type _BufferSource._(JSObject _) implements _AudioNode {
  external set buffer(_AudioBuf? value);
  external set loop(bool value);
  external set loopStart(double value);
  external set loopEnd(double value);
  external _AudioParam get playbackRate;
  external set onended(JSFunction? f);
  external void start(double when, double offset);
  external void stop(double when);
}

extension type _AudioBuf._(JSObject _) implements JSObject {
  external double get sampleRate;
  external int get length;
  external JSFloat32Array getChannelData(int channel);
}

extension type _EventTarget._(JSObject _) implements JSObject {
  external void addEventListener(String type, JSFunction listener, JSAny? options);
  external void removeEventListener(String type, JSFunction listener, JSAny? options);
}

extension type _Navigator._(JSObject _) implements JSObject {
  external _UserActivation? get userActivation;
}

extension type _UserActivation._(JSObject _) implements JSObject {
  external bool get isActive;
}

@JS('document')
external _EventTarget get _document;

@JS('navigator')
external _Navigator get _navigator;

// ---------------------------------------------------------------------------
// Motor
// ---------------------------------------------------------------------------

class WebAudioEngine with WidgetsBindingObserver implements SfxBackend {
  WebAudioEngine();

  static const _unlockEvents = ['pointerup', 'pointerdown', 'mousedown', 'touchend', 'keydown', 'click'];

  _AudioCtx? _ctx;
  _GainNode? _sfxBus;
  _GainNode? _ambBus;
  _BaseCtx? _decoder;
  final Map<SfxId, _AudioBuf> _buffers = {};
  final Map<Ambience, Future<_LoopData?>> _ambiences = {};
  final List<_Voice> _voices = [];
  Future<void>? _initFuture;
  bool _preloaded = false;
  bool _observing = false;
  bool _hidden = false;
  bool _disposed = false;
  JSFunction? _unlockFn;
  Ambience? _want;
  double _wantVolume = 0.5;
  _Voice? _amb;
  int _ambGen = 0;

  @override
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    if (!globalContext.has('AudioContext')) {
      debugPrint('[Zona Cero] Audio: el navegador no soporta Web Audio.');
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
    _listenForUnlock();
    if (globalContext.has('OfflineAudioContext')) {
      try {
        _decoder = _OfflineCtx(1, 1, 44100);
      } catch (_) {
        _decoder = null;
      }
    }
    // Sin OfflineAudioContext se decodifica al desbloquear (con el contexto real).
    if (_decoder != null) await _preloadAll();
  }

  Future<void> _preloadAll() async {
    if (_preloaded) return;
    _preloaded = true;
    const batch = 6;
    final ids = SfxId.values;
    for (var i = 0; i < ids.length && !_disposed; i += batch) {
      await Future.wait(ids.skip(i).take(batch).map((id) async {
        final b = await _decode(id.asset);
        if (b != null) _buffers[id] = b;
      }));
    }
  }

  Future<_AudioBuf?> _decode(String asset) async {
    final dec = _decoder ?? _ctx;
    if (dec == null) return null;
    try {
      final data = await rootBundle.load(asset);
      // Copia propia: decodeAudioData se queda con (y vacía) el ArrayBuffer.
      final bytes = Uint8List.fromList(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      return await dec.decodeAudioData(bytes.buffer.toJS).toDart;
    } catch (e) {
      debugPrint('[Zona Cero] Audio: no se pudo cargar $asset ($e)');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Desbloqueo por gesto (política de autoplay)
  // ---------------------------------------------------------------------------

  void _listenForUnlock() {
    final fn = ((JSAny? _) => _unlock()).toJS;
    _unlockFn = fn;
    for (final t in _unlockEvents) {
      _document.addEventListener(t, fn, true.toJS);
    }
  }

  void _stopListening() {
    final fn = _unlockFn;
    if (fn == null) return;
    _unlockFn = null;
    for (final t in _unlockEvents) {
      _document.removeEventListener(t, fn, true.toJS);
    }
  }

  void _unlock() {
    if (_disposed) return;
    try {
      // Solo dentro de un gesto válido: así el navegador no avisa ni lo bloquea.
      final ua = _navigator.userActivation;
      if (ua != null && !ua.isActive) return;
      var ctx = _ctx;
      if (ctx == null) {
        ctx = _AudioCtx();
        _ctx = ctx;
        final sfx = ctx.createGain()..connect(ctx.destination);
        final amb = ctx.createGain()..connect(ctx.destination);
        _sfxBus = sfx;
        _ambBus = amb;
        if (!_preloaded) unawaited(_preloadAll());
      }
      if (ctx.state == 'running') {
        _stopListening();
      } else if (!_hidden) {
        unawaited(ctx.resume().toDart.then((_) {
          if (_ctx?.state == 'running') _stopListening();
        }, onError: (Object _) {}));
      }
      _syncAmbience();
    } catch (e) {
      debugPrint('[Zona Cero] Audio: no se pudo iniciar Web Audio ($e)');
    }
  }

  // ---------------------------------------------------------------------------
  // Efectos
  // ---------------------------------------------------------------------------

  @override
  void play(SfxId id, {double volume = 1, double rate = 1}) {
    final ctx = _ctx;
    final bus = _sfxBus;
    final buf = _buffers[id];
    if (_disposed || _hidden || ctx == null || bus == null || buf == null) return;
    try {
      if (ctx.state == 'suspended') unawaited(ctx.resume().toDart.then((_) {}, onError: (Object _) {}));
      _voices.removeWhere((v) => v.ended);
      final same = _voices.where((v) => v.id == id).toList();
      if (same.length >= SfxTuning.voices(id)) _stopVoice(ctx, same.first);
      if (_voices.length >= SfxTuning.maxVoices) _stopVoice(ctx, _voices.first);
      final src = ctx.createBufferSource()..buffer = buf;
      src.playbackRate.value = rate;
      final g = ctx.createGain();
      g.gain.value = volume;
      src.connect(g);
      g.connect(bus);
      final v = _Voice(id, null, src, g);
      src.onended = ((JSAny? _) {
        v.ended = true;
        try {
          g.disconnect();
        } catch (_) {}
      }).toJS;
      src.start(0, 0);
      _voices.add(v);
    } catch (e) {
      if (kDebugMode) debugPrint('[Zona Cero] Audio: falló ${id.file} ($e)');
    }
  }

  void _stopVoice(_AudioCtx ctx, _Voice v) {
    v.ended = true;
    _voices.remove(v);
    try {
      final now = ctx.currentTime;
      v.gain.gain.setTargetAtTime(0, now, 0.012);
      v.src.stop(now + 0.06);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Ambientes
  // ---------------------------------------------------------------------------

  @override
  void ambience(Ambience? a, {double volume = 0.5}) {
    _want = a;
    _wantVolume = volume;
    // Adelantar la decodificación aunque todavía no haya contexto.
    if (a != null && _decoder != null) unawaited(_loadAmbience(a));
    _syncAmbience();
  }

  Future<_LoopData?> _loadAmbience(Ambience a) => _ambiences.putIfAbsent(a, () async {
        final buf = await _decode(a.asset);
        if (buf == null) return null;
        return _LoopData.of(buf);
      });

  void _syncAmbience() {
    final ctx = _ctx;
    final bus = _ambBus;
    if (_disposed || ctx == null || bus == null) return;
    try {
      final cur = _amb;
      if (cur != null && cur.ambience == _want) {
        _ramp(ctx, cur.gain, _wantVolume, SfxTuning.ambienceLevelFade);
        return;
      }
      if (cur != null) {
        _amb = null;
        _ramp(ctx, cur.gain, 0, SfxTuning.ambienceFade);
        cur.src.stop(ctx.currentTime + _secs(SfxTuning.ambienceFade) + 0.1);
      }
      final want = _want;
      if (want == null) return;
      final gen = ++_ambGen;
      unawaited(_loadAmbience(want).then((d) {
        final c = _ctx;
        final b = _ambBus;
        if (d == null || c == null || b == null || _disposed || gen != _ambGen || _amb != null || _want != want) return;
        final src = c.createBufferSource()
          ..buffer = d.buffer
          ..loop = true;
        if (d.loopEnd > d.loopStart) {
          src
            ..loopStart = d.loopStart
            ..loopEnd = d.loopEnd;
        }
        final g = c.createGain();
        g.gain.value = 0;
        src.connect(g);
        g.connect(b);
        src.start(0, d.loopStart);
        _ramp(c, g, _wantVolume, SfxTuning.ambienceFade);
        _amb = _Voice(null, want, src, g);
      }, onError: (Object _) {}));
    } catch (e) {
      debugPrint('[Zona Cero] Audio: falló el ambiente ($e)');
    }
  }

  static double _secs(Duration d) => d.inMicroseconds / 1e6;

  void _ramp(_AudioCtx ctx, _GainNode g, double target, Duration d) {
    final p = g.gain;
    final now = ctx.currentTime;
    p.cancelScheduledValues(now);
    p.setValueAtTime(p.value, now);
    p.linearRampToValueAtTime(target, now + _secs(d));
  }

  // ---------------------------------------------------------------------------
  // Ciclo de vida: pestaña oculta → contexto suspendido.
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctx = _ctx;
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _hidden = true;
        if (ctx != null && ctx.state == 'running') unawaited(ctx.suspend().toDart.then((_) {}, onError: (Object _) {}));
      case AppLifecycleState.resumed:
        _hidden = false;
        if (ctx != null && ctx.state == 'suspended') unawaited(ctx.resume().toDart.then((_) {}, onError: (Object _) {}));
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stopListening();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    final ctx = _ctx;
    _ctx = null;
    if (ctx != null) unawaited(ctx.close().toDart.then((_) {}, onError: (Object _) {}));
    _voices.clear();
    _buffers.clear();
    _ambiences.clear();
  }
}

class _Voice {
  _Voice(this.id, this.ambience, this.src, this.gain);
  final SfxId? id;
  final Ambience? ambience;
  final _BufferSource src;
  final _GainNode gain;
  bool ended = false;
}

/// Buffer de ambiente con puntos de loop que saltean el relleno del codificador
/// (silencio digital al principio/fin del MP3 que cortaría el loop).
class _LoopData {
  _LoopData(this.buffer, this.loopStart, this.loopEnd);

  final _AudioBuf buffer;
  final double loopStart;
  final double loopEnd;

  static _LoopData of(_AudioBuf b) {
    try {
      final data = b.getChannelData(0).toDart;
      final n = data.length;
      const scan = 16384;
      const floor = 1e-4;
      var a = 0;
      final aLim = math.min(n, scan);
      while (a < aLim && data[a].abs() < floor) {
        a++;
      }
      var z = n - 1;
      final zLim = math.max(0, n - scan);
      while (z > zLim && data[z].abs() < floor) {
        z--;
      }
      if (a >= aLim) a = 0;
      if (z <= zLim) z = n - 1;
      final sr = b.sampleRate;
      return _LoopData(b, a / sr, (z + 1) / sr);
    } catch (_) {
      return _LoopData(b, 0, 0);
    }
  }
}
