// Coreografía de un turno: en qué momento se muestra cada evento del motor.
// Secuencia: acción del jugador → pausa corta → respuesta del zombie.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show VoidCallback;

import '../core/types.dart';

/// Eventos que pertenecen a la respuesta del zombie (se muestran después).
bool isZombiePhase(CombatEvent e) => switch (e) {
  ZombieHit() || ZombieMiss() || ZombieChargePrepare() || ZombieStunned() || ZombieScream() || PlayerDown() => true,
  _ => false,
};

/// Ataques del zombie: tienen anticipación (animación) e impacto.
bool isZombieAttack(CombatEvent e) => e is ZombieHit || e is ZombieMiss;

class PlannedEvent {
  const PlannedEvent(this.event, this.atMs, this.impactMs);
  final CombatEvent event;

  /// Cuándo empieza (texto, animación).
  final int atMs;

  /// Cuándo "pega" (daño, temblor). Igual a [atMs] si no hay anticipación.
  final int impactMs;
}

class TurnPlan {
  const TurnPlan(this.events, this.endMs);
  final List<PlannedEvent> events;

  /// Fin del turno: se liberan los controles.
  final int endMs;
}

abstract final class TurnTiming {
  static const int playerStep = 300;
  static const int killStep = 240;
  static const int pause = 500;
  static const int minWindup = 200;
  static const int maxWindup = 480;
  static const int recover = 380;
  static const int zombieStep = 520;
  static const int downDelay = 260;
  static const int tail = 300;
}

/// Planifica un turno. `windupMs` devuelve cuánto tarda en pegar un ataque
/// del zombie (desde la animación); se acota a [TurnTiming.minWindup]…[TurnTiming.maxWindup].
TurnPlan planTurn(List<CombatEvent> events, {int Function(CombatEvent e)? windupMs}) {
  final out = <PlannedEvent>[];
  final player = [
    for (final e in events)
      if (!isZombiePhase(e)) e,
  ];
  final zombie = [
    for (final e in events)
      if (isZombiePhase(e)) e,
  ];

  var t = 0;
  for (var i = 0; i < player.length; i++) {
    final e = player[i];
    if (i > 0) t += e is ZombieKilled || e is ToxicBurst ? TurnTiming.killStep : TurnTiming.playerStep;
    out.add(PlannedEvent(e, t, t));
  }
  var last = t;
  var cursor = player.isEmpty ? 0 : t + TurnTiming.pause;
  for (final e in zombie) {
    if (isZombieAttack(e)) {
      final w = (windupMs?.call(e) ?? 380).clamp(TurnTiming.minWindup, TurnTiming.maxWindup);
      out.add(PlannedEvent(e, cursor, cursor + w));
      last = cursor + w;
      cursor = last + TurnTiming.recover;
    } else if (e is PlayerDown) {
      final at = last + TurnTiming.downDelay;
      out.add(PlannedEvent(e, at, at));
      last = at;
      cursor = at + TurnTiming.recover;
    } else {
      out.add(PlannedEvent(e, cursor, cursor));
      last = cursor;
      cursor += TurnTiming.zombieStep;
    }
  }
  return TurnPlan(out, math.max(last, 0) + TurnTiming.tail);
}

/// Una acción programada en milisegundos desde el inicio del turno.
class SeqCue {
  const SeqCue(this.atMs, this.run);
  final int atMs;
  final VoidCallback run;
}

/// Reproduce una lista de [SeqCue] con temporizadores. [hurry] acelera lo que
/// falta (tocar la pantalla durante la reproducción).
class TurnSequencer {
  final List<SeqCue> _cues = [];
  Timer? _timer;
  int _index = 0;
  int _virtualMs = 0;
  double _speed = 1;
  VoidCallback? _onDone;

  bool get isPlaying => _timer != null || _index < _cues.length;
  bool get hurried => _speed > 1;

  void play(List<SeqCue> cues, {VoidCallback? onDone}) {
    cancel();
    _cues
      ..clear()
      ..addAll(cues)
      ..sort((a, b) => a.atMs.compareTo(b.atMs));
    _index = 0;
    _virtualMs = 0;
    _speed = 1;
    _onDone = onDone;
    _next();
  }

  void hurry([double factor = 4]) {
    if (!isPlaying || _speed >= factor) return;
    _speed = factor;
    _timer?.cancel();
    _timer = null;
    _next();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _cues.clear();
    _index = 0;
    _onDone = null;
  }

  void _next() {
    // Ejecuta todo lo que ya venció y programa el siguiente.
    while (_index < _cues.length && _cues[_index].atMs <= _virtualMs) {
      final c = _cues[_index++];
      c.run();
      if (_cues.isEmpty) return; // cancelado desde la propia acción
    }
    if (_index >= _cues.length) {
      _timer = null;
      final done = _onDone;
      _onDone = null;
      done?.call();
      return;
    }
    final target = _cues[_index].atMs;
    final wait = ((target - _virtualMs) / _speed).round();
    _timer = Timer(Duration(milliseconds: wait), () {
      _timer = null;
      _virtualMs = target;
      _next();
    });
  }
}
