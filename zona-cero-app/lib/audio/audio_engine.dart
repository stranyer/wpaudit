// Motor de audio real de Zona Cero.
//
// - Android / iOS / escritorio: `audioplayers` — efectos en modo de baja latencia
//   (SoundPool en Android) con un pequeño grupo de voces por sonido para que se
//   superpongan, y ambientes en MediaPlayer con doble "pletina" que se funden en
//   el punto de loop (sin el hueco típico del loop nativo) y entre ambientes.
// - Web: Web Audio API directa (un solo AudioContext, buffers decodificados,
//   loops sin cortes). El contexto se crea con el primer gesto del usuario, así
//   que antes de tocar la pantalla simplemente no suena nada.
//
// En ambos casos: precarga de todos los efectos en `init()`, nunca lanza si falta
// un archivo o no hay audio, y pausa los ambientes cuando la app pasa a segundo
// plano (observa el ciclo de vida de Flutter por su cuenta).

import 'dart:math' as math;

import 'audio_engine_stub.dart'
    if (dart.library.js_interop) 'audio_engine_web.dart'
    if (dart.library.io) 'audio_engine_native.dart' as impl;
import 'sfx.dart';

/// Crea el motor adecuado para la plataforma actual.
SfxBackend createAudioEngine() => impl.createPlatformEngine();

/// Ajustes de mezcla compartidos por las implementaciones.
abstract final class SfxTuning {
  /// Voces simultáneas por efecto (la más vieja se corta si se pasa).
  static int voices(SfxId id) => switch (id) {
        SfxId.tap || SfxId.tab || SfxId.contactPing => 4,
        SfxId.pistolShot ||
        SfxId.shotgunShot ||
        SfxId.meleeSwing ||
        SfxId.meleeImpact ||
        SfxId.headshot ||
        SfxId.zombieHurt ||
        SfxId.playerHurt ||
        SfxId.emptyClick =>
          3,
        _ => 2,
      };

  /// Límite global de voces de efectos sonando a la vez.
  static const maxVoices = 24;

  /// Fundido cruzado entre ambientes.
  static const ambienceFade = Duration(milliseconds: 1500);

  /// Cambio de nivel del mismo ambiente (p. ej. al cambiar de pestaña).
  static const ambienceLevelFade = Duration(milliseconds: 700);

  /// Solapamiento en el punto de loop de los ambientes (motor nativo).
  static const loopOverlap = Duration(milliseconds: 2000);

  /// Tiempo máximo para cargar un archivo antes de darlo por perdido.
  static const loadTimeout = Duration(seconds: 12);
}

/// Rampa de ganancia con curva de igual potencia: al subir sigue `sin`, al bajar
/// `cos`, de modo que dos rampas opuestas simultáneas (fundido cruzado) mantienen
/// la energía constante.
class GainRamp {
  GainRamp([double value = 0])
      : _value = value,
        _from = value,
        _to = value;

  double _value;
  double _from;
  double _to;
  double _t = 1;
  double _seconds = 1;

  double get value => _value;
  double get target => _to;
  bool get done => _t >= 1;

  /// Empieza una rampa desde el valor actual hasta [target].
  void to(double target, Duration duration) {
    _from = _value;
    _to = target;
    _seconds = math.max(duration.inMicroseconds / 1e6, 1e-3);
    _t = (target - _value).abs() < 1e-6 ? 1 : 0;
    if (_t >= 1) _value = target;
  }

  /// Fija el valor sin rampa.
  void set(double value) {
    _value = _from = _to = value;
    _t = 1;
  }

  /// Avanza [dt] segundos y devuelve el valor nuevo.
  double tick(double dt) {
    if (_t >= 1) return _value;
    _t = math.min(1, _t + dt / _seconds);
    if (_t > 1 - 1e-9) _t = 1; // sin residuos de coma flotante
    final rising = _to >= _from;
    final c = rising ? math.sin(_t * math.pi / 2) : 1 - math.cos(_t * math.pi / 2);
    _value = _from + (_to - _from) * c;
    if (_t >= 1) _value = _to;
    return _value;
  }
}
