// Pantalla de encuentro: escenario Flame (criatura detrás de `CreatureView`,
// mano en primera persona con el arma activa) + HUD de campo como la
// referencia + minijuego de puntería + sonido.
//
// La abre el shell como ruta a pantalla completa después de que
// `app.engage(spawn)` devolvió true (así `app.combat` y `app.combatSpawn` ya
// están cargados). Al salir llama a `app.leaveCombat()` y hace `pop`.

import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../audio/sfx.dart';
import '../../combat/aim.dart';
import '../../combat/combat_art.dart' show plateForSpawn;
import '../../combat/combat_game.dart';
import '../../combat/combat_hud.dart';
import '../../combat/creature_view.dart' show ZombieAnim;
import '../../combat/fp_hand.dart' show handFor, HandKind;
import '../../combat/turn_plan.dart';
import '../../core/core.dart';
import '../../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/chamfer_button.dart';
import '../widgets/grit.dart' show ZcLogo;

class EncounterScreen extends StatefulWidget {
  const EncounterScreen({super.key});

  @override
  State<EncounterScreen> createState() => _EncounterScreenState();
}

class _CallOutSpec {
  const _CallOutSpec(this.id, this.text, this.color, this.sub, [this.icon = CallIcon.warning]);
  final int id;
  final String text;
  final Color color;
  final String? sub;
  final CallIcon icon;
}

class _EncounterScreenState extends State<EncounterScreen> {
  CombatState? _state;
  late CombatStageGame _game;
  bool _gameCreated = false;
  final TurnSequencer _seq = TurnSequencer();
  final List<Timer> _timers = [];
  final math.Random _rnd = math.Random();
  Timer? _heartbeat;

  bool _ready = false;
  bool _busy = false;
  bool _acted = false;
  bool _aiming = false;
  bool _itemsOpen = false;
  bool _showResult = false;
  bool _exiting = false;
  bool _hostile = true;
  int? _pointer;
  WeaponMode _mode = WeaponMode.melee;

  // Valores mostrados (se actualizan al ritmo de la reproducción).
  double _hp = 0;
  double _sta = 0;
  int _zHp = 0;
  bool _charging = false;
  bool _stunned = false;
  bool _screamed = false;

  final List<LogLine> _log = [];
  final List<FloatSpec> _floats = [];
  _CallOutSpec? _callout;
  int _ids = 1;
  int _fleeNudge = 0;
  int _shake = 0;
  int? _levelBefore;
  Offset _playerAnchor = const Offset(90, 160);
  late ZombieTypeId _zombieType;
  ItemId? _meleeId;
  ItemId? _firearmId;

  bool get _ended => _state == null || _state!.status != CombatStatus.ongoing;
  bool get _canAct => _ready && !_busy && !_ended && !_exiting;

  @override
  void initState() {
    super.initState();
    final s = app.combat;
    _state = s;
    _zombieType = s?.zombie.typeId ?? app.combatSpawn?.zombieType ?? ZombieTypeId.walker;
    _levelBefore = app.player?.level;
    final eq = app.player?.equipment;
    _meleeId = eq?.melee;
    _firearmId = s?.player.firearm == null ? null : eq?.firearm;
    if (s != null) {
      _hp = s.player.health;
      _sta = s.player.stamina;
      _zHp = s.zombie.health;
      _charging = s.zombie.charging;
      _stunned = s.zombie.stunned;
      // Con arma de fuego y munición se arranca apuntando con ella (como el HUD del mapa).
      if (canShoot(s)) _mode = WeaponMode.firearm;
      _addLog('Hostil detectado.', Sutura.textHi);
      _addLog('El ${s.zombie.name} se aproxima.', Sutura.textHi);
      final ability = zombieDefs[s.zombie.typeId]!.ability;
      switch (ability) {
        case ZombieAbility.toxicBurst:
          _addLog('Explota al morir: rematalo con un disparo.', const Color(0xFFA6D86A));
        case ZombieAbility.charge:
          _addLog('Prepara embestidas: cubrite a tiempo.', Sutura.caution);
        case ZombieAbility.callHorde:
          _addLog('Si grita, llegan refuerzos.', Sutura.caution);
        case ZombieAbility.doubleStrike:
          _addLog('Es rápido: puede atacar dos veces.', Sutura.caution);
        case ZombieAbility.none:
          break;
      }
    }
    _later(4800, () => setState(() => _hostile = false));
    // Sonido: ambiente de combate mientras dure la pantalla, gruñido de entrada
    // (el Corredor además gruñe con los dientes) y latido con la salud baja.
    Sfx.ambience(Ambience.combat);
    if (s != null) {
      Sfx.play(SfxId.zombieGroan, rate: _rate());
      if (_zombieType == ZombieTypeId.runner) _later(450, () => Sfx.play(SfxId.runnerSnarl, rate: _rate()));
    }
    _heartbeat = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      final st = _state;
      if (!mounted || st == null || _ended || _exiting || st.player.maxHealth <= 0) return;
      if (_hp / st.player.maxHealth < 0.3) Sfx.play(SfxId.heartbeat, volume: 0.85, rate: 0.97 + _rnd.nextDouble() * 0.06);
    });
  }

  /// Variación leve de tono para que los sonidos repetidos no suenen clonados.
  double _rate() => 0.9 + _rnd.nextDouble() * 0.2;

  HandKind get _handKind => handFor(_mode, firearm: _firearmId, melee: _meleeId);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_gameCreated) return;
    _gameCreated = true;
    // El bundle sale del contexto (los tests pueden inyectar uno sin arte
    // para ejercitar las reservas procedurales).
    _game = CombatStageGame(
      zombieType: _zombieType,
      bundle: DefaultAssetBundle.of(context),
      // Placa fija por aparición (Colón / Obelisco).
      plate: plateForSpawn(app.combatSpawn?.id ?? _state?.spawnId ?? ''),
      hand: _handKind,
      onAimSignal: _onAimSignal,
      onReady: () {
        if (mounted) setState(() => _ready = true);
      },
    );
    _syncGameFlags();
  }

  @override
  void dispose() {
    _seq.cancel();
    _heartbeat?.cancel();
    for (final t in _timers) {
      t.cancel();
    }
    Sfx.ambience(Ambience.map);
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Utilidades
  // ---------------------------------------------------------------------------

  void _later(int ms, VoidCallback fn) {
    late final Timer t;
    t = Timer(Duration(milliseconds: ms), () {
      _timers.remove(t);
      if (mounted) fn();
    });
    _timers.add(t);
  }

  void _addLog(String text, Color color) {
    _log.add(LogLine(_ids++, text, color));
    if (_log.length > 6) _log.removeAt(0);
  }

  void _float(FloatKind kind, String text, Offset at, {String? sub, int blocked = 0}) {
    final f = FloatSpec(id: _ids++, text: text, kind: kind, at: at.translate((_rnd.nextDouble() - 0.5) * 26, 0), sub: sub, blocked: blocked);
    _floats.add(f);
    if (_floats.length > 8) _floats.removeAt(0);
    _later(1350, () => setState(() => _floats.remove(f)));
  }

  void _call(String text, Color color, {String? sub, CallIcon icon = CallIcon.warning}) {
    final c = _CallOutSpec(_ids++, text, color, sub, icon);
    _callout = c;
    _later(1400, () {
      if (_callout == c) setState(() => _callout = null);
    });
  }

  void _syncGameFlags() {
    final s = _state;
    if (s == null) return;
    _game
      ..charging = _charging
      ..stunned = _stunned
      ..healthRatio = s.player.maxHealth <= 0 ? 0 : (_hp / s.player.maxHealth).clamp(0.0, 1.0);
  }

  Color _logColor(CombatEvent e) => switch (e) {
    PlayerHit(crit: true) => Sutura.amber,
    PlayerHit() => Sutura.textHi,
    PlayerMiss() || ZombieMiss() || ZombieStunned() => Sutura.textMid,
    Heal() || DefendEvent() || FleeSuccess() => Sutura.fine,
    ZombieHit() || ToxicBurst() || PlayerDown() || ZombieScream() || FleeFail() => hudRed,
    ZombieChargePrepare() || Exhausted() || NoAmmo() => Sutura.caution,
    ZombieKilled() => Sutura.signal,
  };

  // ---------------------------------------------------------------------------
  // Puntería
  // ---------------------------------------------------------------------------

  void _onAimSignal(AimSignal s) {
    switch (s) {
      case AimSignal.locked:
        HapticFeedback.lightImpact();
      case AimSignal.charged:
        HapticFeedback.selectionClick();
      case AimSignal.none:
        break;
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    if (_showResult || _exiting) return;
    if (_busy) {
      _seq.hurry();
      return;
    }
    if (_itemsOpen) {
      setState(() => _itemsOpen = false);
      return;
    }
    if (_pointer != null || !_canAct) return;
    _pointer = e.pointer;
    final melee = _mode == WeaponMode.melee;
    _game.aimStart(e.localPosition, canCharge: melee && _sta >= GameStamina.heavy, style: melee ? AimStyle.melee : AimStyle.firearm);
    setState(() => _aiming = true);
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer == _pointer) _game.aimMove(e.localPosition);
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final shot = _game.aimRelease();
    setState(() => _aiming = false);
    // Un toque muy corto no dispara (evita ataques accidentales).
    if (shot == null || shot.heldMs < 110) return;
    _fire(shot);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _game.aimCancel();
    setState(() => _aiming = false);
  }

  void _fire(AimShot shot) {
    final s = _state;
    if (s == null || !_canAct) return;
    final CombatAction action;
    if (_mode == WeaponMode.firearm) {
      if (!canShoot(s)) {
        _noAmmo();
        return;
      }
      action = CombatAction.shoot(precision: shot.precision);
      _game.muzzle(_game.impactPointFor(shot.point));
      Sfx.play(_firearmId == ItemId.shotgun ? SfxId.shotgunShot : SfxId.pistolShot, rate: _rate());
    } else {
      action = shot.charged ? CombatAction.heavy(precision: shot.precision) : CombatAction.attack(precision: shot.precision);
      _game.slash(shot.zone == AimZone.off ? shot.point : _game.impactPointFor(shot.point), heavy: shot.charged);
      Sfx.play(SfxId.meleeSwing, volume: shot.charged ? 1 : 0.85, rate: shot.charged ? 0.88 : _rate());
    }
    HapticFeedback.mediumImpact();
    _resolve(action, shot: shot);
  }

  void _noAmmo() {
    _game.dryFire();
    Sfx.play(SfxId.emptyClick, rate: _rate());
    setState(() {
      _mode = WeaponMode.melee;
      _call('SIN MUNICIÓN', hudRed, sub: 'Cambio a cuerpo a cuerpo');
    });
    _game.setHand(_handKind);
    HapticFeedback.selectionClick();
  }

  void _toggleMode() {
    final s = _state;
    if (s == null || s.player.firearm == null || !_canAct) return;
    if (_mode == WeaponMode.melee && !canShoot(s)) {
      _noAmmo();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _mode = _mode == WeaponMode.melee ? WeaponMode.firearm : WeaponMode.melee);
    _game.setHand(_handKind);
  }

  // ---------------------------------------------------------------------------
  // Turno
  // ---------------------------------------------------------------------------

  ZombieAnim _attackAnim(CombatEvent e) => switch (e) {
    ZombieHit(charged: true) || ZombieMiss(charged: true) => ZombieAnim.charge,
    _ => ZombieAnim.attack,
  };

  void _resolve(CombatAction action, {AimShot? shot}) {
    final prev = _state;
    if (prev == null || !_canAct) return;
    final next = app.combatAction(action);
    if (next == null || identical(next, prev)) return;
    final evs = next.lastEvents;
    if (evs.length == 1 && evs.first is NoAmmo) {
      _state = next;
      _noAmmo();
      return;
    }
    final healStamina = evs.whereType<Heal>().fold(0.0, (a, e) => a + e.stamina);
    setState(() {
      _state = next;
      _acted = true;
      _busy = true;
      _itemsOpen = false;
      _hostile = false;
      // La resistencia gastada en la acción se ve al instante.
      _sta = next.player.stamina - healStamina;
    });
    final kill = evs.any((e) => e is ZombieKilled);
    final plan = planTurn(evs, windupMs: (e) => (_game.zombieKeyTime(_attackAnim(e)) * 1000).round());
    final cues = <SeqCue>[];
    for (final p in plan.events) {
      cues.add(SeqCue(p.atMs, () => _onStart(p.event, next, action, shot, kill)));
      if (p.impactMs != p.atMs) cues.add(SeqCue(p.impactMs, () => _onImpact(p.event, next)));
    }
    cues.add(SeqCue(plan.endMs, () => _onTurnEnd(next)));
    _seq.play(cues);
  }

  void _onStart(CombatEvent e, CombatState st, CombatAction action, AimShot? shot, bool kill) {
    if (!mounted) return;
    var log = true;
    switch (e) {
      case PlayerHit():
        final at = shot != null ? _game.impactPointFor(shot.point) : _game.chestPoint;
        _game.impact(at, crit: e.crit, heavy: action is Heavy, ranged: e.ranged, headshot: e.headshot, lethal: kill);
        _zHp = math.max(0, _zHp - e.damage);
        if (e.ranged) {
          Sfx.play(SfxId.zombieHurt, rate: _rate());
        } else {
          Sfx.play(SfxId.meleeImpact, rate: _rate());
          Sfx.play(SfxId.zombieHurt, volume: 0.7, rate: _rate());
        }
        if (e.crit || e.headshot) Sfx.play(SfxId.headshot, rate: _rate());
        _float(
          e.crit ? FloatKind.crit : FloatKind.damage,
          '−${e.damage}',
          at.translate(0, -30),
          sub: e.headshot ? 'CABEZA' : (e.crit ? 'CRÍTICO' : null),
        );
        if (e.headshot && e.ranged) {
          _call('DISPARO A LA CABEZA', Sutura.amber, sub: 'Impacto crítico ×1,75', icon: CallIcon.crosshair);
        } else if (e.crit) {
          _call('GOLPE CRÍTICO', Sutura.amber, sub: e.stunBonus ? 'Objetivo aturdido' : (e.headshot ? 'A la cabeza' : null), icon: CallIcon.crosshair);
        }
      case PlayerMiss():
        final at = shot?.point ?? _game.chestPoint;
        _game.miss(at, ranged: e.ranged);
        _float(FloatKind.miss, 'FALLÓ', at.translate(0, -26));
      case Exhausted():
        _float(FloatKind.info, 'AGOTADO', _playerAnchor.translate(0, 30));
      case NoAmmo():
        _noAmmo();
      case DefendEvent():
        _game
          ..shieldUp()
          ..guard = true;
        Sfx.play(SfxId.defend, rate: _rate());
        _sta = math.min(st.player.maxStamina.toDouble(), _sta + e.stamina);
        final gained = e.stamina.round();
        _float(FloatKind.blocked, gained > 0 ? '+$gained RES' : 'CUBIERTO', _playerAnchor, sub: gained > 0 ? 'CUBIERTO' : null);
      case Heal():
        _game.healPulse();
        Sfx.play(SfxId.heal, rate: _rate());
        _hp = math.min(st.player.maxHealth.toDouble(), _hp + e.health);
        _sta = math.min(st.player.maxStamina.toDouble(), _sta + e.stamina);
        if (e.health > 0) _float(FloatKind.heal, '+${e.health.round()}', _playerAnchor, sub: itemDefs[e.itemId]!.name.toUpperCase());
        if (e.stamina > 0) _float(FloatKind.info, '+${e.stamina.round()} RES', _playerAnchor.translate(0, 44));
      case FleeSuccess():
        _game
          ..ended = true
          ..fleeOut();
        Sfx.play(SfxId.flee);
      case FleeFail():
        _game.shake(0.3);
        Sfx.play(SfxId.flee, volume: 0.6, rate: _rate());
        _call('¡TE CORTA EL PASO!', hudRed, sub: 'No pudiste escapar');
      case ZombieKilled():
        _game
          ..ended = true
          ..playZombie(ZombieAnim.death);
        _charging = false;
        Sfx.play(SfxId.zombieDeath, rate: _rate());
        if (_zombieType == ZombieTypeId.bloater) Sfx.play(SfxId.bloaterBurst);
        HapticFeedback.mediumImpact();
      case ToxicBurst():
        _game.toxicCloud();
        Sfx.play(SfxId.playerHurt, rate: _rate());
        _hp = math.max(0, _hp - e.damage);
        _float(FloatKind.hurt, '−${e.damage.round()}', _playerAnchor, sub: 'TÓXICO');
        HapticFeedback.heavyImpact();
      case ZombieHit():
        _game.playZombie(_attackAnim(e));
        Sfx.play(SfxId.zombieAttack, rate: _rate());
        log = false;
      case ZombieMiss():
        _game.playZombie(_attackAnim(e));
        Sfx.play(SfxId.zombieAttack, rate: _rate());
        log = false;
      case ZombieChargePrepare():
        _game.playZombie(ZombieAnim.chargePrepare);
        _charging = true;
        _addLog('Prepara una embestida.', Sutura.caution);
        _addLog('¡Cubrite!', hudRed);
        log = false;
        Sfx.play(SfxId.bruteRoar, rate: _rate());
        HapticFeedback.mediumImpact();
      case ZombieStunned():
        _stunned = st.zombie.stunned;
        // Tras esquivar la embestida el aviso central ya lo dice.
        if (!st.lastEvents.any((x) => x is ZombieMiss && x.charged)) {
          _float(FloatKind.info, 'ATURDIDO', _game.headPoint.translate(0, -16), sub: 'PIERDE EL TURNO');
        }
      case ZombieScream():
        _game.playZombie(ZombieAnim.scream);
        Sfx.play(SfxId.screamerScream, rate: _rate());
        _later((_game.zombieKeyTime(ZombieAnim.scream) * 1000).round(), () {
          _game.screamWave();
          setState(() => _shake++);
          HapticFeedback.heavyImpact();
        });
        _zHp = math.min(st.zombie.maxHealth, _zHp + e.healed);
        _screamed = true;
        _float(FloatKind.heal, '+${e.healed}', _game.headPoint.translate(0, -10), sub: 'REFUERZOS');
        _call('¡GRITO!', Sutura.caution2, sub: 'Llegan refuerzos');
      case PlayerDown():
        _game
          ..ended = true
          ..playerDown();
        HapticFeedback.heavyImpact();
    }
    if (log) _addLog(describeEvent(e, st), _logColor(e));
    _syncGameFlags();
    setState(() {});
  }

  void _onImpact(CombatEvent e, CombatState st) {
    if (!mounted) return;
    switch (e) {
      case ZombieHit():
        _game.hurt(charged: e.charged);
        Sfx.play(SfxId.playerHurt, rate: _rate());
        _hp = math.max(0, _hp - e.damage);
        _float(FloatKind.hurt, '−${e.damage}', _playerAnchor, blocked: e.blocked, sub: e.charged ? 'EMBESTIDA' : null);
        if (e.charged) {
          _charging = false;
          _shake++;
          _call('¡EMBESTIDA!', hudRed, sub: 'Te llevó por delante');
        }
        HapticFeedback.heavyImpact();
      case ZombieMiss():
        _game.blockedHit();
        if (e.charged) {
          _charging = false;
          _game.dodge();
          _float(FloatKind.info, '¡ESQUIVADA!', _playerAnchor);
          _call('¡ESQUIVADA!', Sutura.signal, sub: 'Queda aturdido', icon: CallIcon.shield);
        } else {
          _float(FloatKind.miss, 'ESQUIVÁS', _playerAnchor);
        }
      default:
        break;
    }
    _addLog(describeEvent(e, st), _logColor(e));
    _syncGameFlags();
    setState(() {});
  }

  void _onTurnEnd(CombatState st) {
    if (!mounted) return;
    _game.guard = false;
    setState(() {
      _busy = false;
      _hp = st.player.health;
      _sta = st.player.stamina;
      _zHp = st.zombie.health;
      _charging = st.zombie.charging;
      _stunned = st.zombie.stunned;
      _screamed = st.lastEvents.any((e) => e is ZombieScream);
      if (st.status == CombatStatus.ongoing && _mode == WeaponMode.firearm && !canShoot(st)) {
        _mode = WeaponMode.melee;
        _call('SIN MUNICIÓN', hudRed, sub: 'Cambio a cuerpo a cuerpo');
        _game.setHand(_handKind);
      }
    });
    _syncGameFlags();
    if (st.status != CombatStatus.ongoing) {
      _game.ended = true;
      final delay = switch (st.status) {
        CombatStatus.won => (_game.zombieDuration(ZombieAnim.death) * 1000).round() + 250,
        CombatStatus.lost => 1100,
        _ => 650,
      };
      _later(delay, () {
        setState(() => _showResult = true);
        _game.lowerHand();
        switch (st.status) {
          case CombatStatus.won:
            Sfx.play(SfxId.victory);
          case CombatStatus.lost:
            Sfx.play(SfxId.defeat);
          default:
            break;
        }
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Salida
  // ---------------------------------------------------------------------------

  void _exit() {
    if (_exiting) return;
    _exiting = true;
    _seq.cancel();
    app.leaveCombat();
    Navigator.of(context).pop();
  }

  void _onBack() {
    if (_ended) {
      if (_showResult) _exit();
      return;
    }
    setState(() {
      _fleeNudge++;
      _call('NO HAY SALIDA FÁCIL', Sutura.caution, sub: 'Usá HUIR para retirarte');
    });
  }

  double _fleeChance(CombatState s) {
    final def = zombieDefs[s.zombie.typeId]!;
    return (def.fleeChance + (s.zombie.stunned ? 0.15 : 0) - (s.zombie.charging ? 0.1 : 0)).clamp(0.05, 0.95);
  }

  // ---------------------------------------------------------------------------
  // Construcción
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = _state;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      // El HUD es denso: se acota el escalado de texto para que no se rompa.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: Scaffold(backgroundColor: Sutura.void_, body: s == null ? _noEncounter() : _stage(context, s)),
      ),
    );
  }

  Widget _noEncounter() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('SIN ENCUENTRO ACTIVO', style: SuturaText.label),
        const SizedBox(height: 16),
        ChamferButton(label: 'Volver al mapa', tone: ChamferTone.primary, onPressed: _exit),
      ],
    ),
  );

  Widget _stage(BuildContext context, CombatState s) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final w = size.width;
    final compact = size.height < 720;
    // Abajo: botonera, y encima registro (izq.) + arma (der., sobre la mano).
    final buttonsH = compact ? 52.0 : 58.0;
    final panelH = compact ? 58.0 : 66.0;
    final buttonsBottom = pad.bottom + 10;
    final rowBottom = buttonsBottom + buttonsH + 10;
    final bottomBlock = rowBottom + panelH;
    // Arriba: logo + signos vitales (izq.), objetivo (der.).
    final logoSize = compact ? 22.0 : 25.0;
    final topY = pad.top + 10;
    final leftW = math.min(196.0, (w - 24) * 0.52);
    final rightW = math.min(190.0, w - 24 - leftW - 8);
    final logoH = logoSize * 1.62;
    final vitalsTop = topY + logoH + 6;
    final vitalsH = compact ? 88.0 : 92.0;
    final hudBottom = vitalsTop + vitalsH;
    _playerAnchor = Offset(w * 0.26, hudBottom + 20);
    _game
      ..hudTop = size.height - bottomBlock
      ..handBase = size.height - buttonsBottom - buttonsH;
    final player = app.player;
    final threat = threatRating(zombieDefs[s.zombie.typeId]!, player?.level ?? 1);
    final items = usableItems(s);
    final controls = _canAct && !_aiming;
    final weaponW = math.min(164.0, w * 0.42);
    final firearm = _mode == WeaponMode.firearm;
    final callout = _callout ?? (_charging && !_ended ? const _CallOutSpec(0, '¡CUBRITE!', hudRed, 'Prepara una embestida') : null);
    // El chip de carga repite al aviso fijo: solo se ve si otro aviso lo tapa.
    final chargeChip = _charging && _callout != null;
    final hostile = _hostile && !_ended && callout == null;
    final chips = chargeChip || _stunned || _screamed;
    final calloutTop = hudBottom + (compact ? 4 : 10);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Escenario (con la mano en primera persona).
        Positioned.fill(
          child: GameWidget<CombatStageGame>(
            game: _game,
            loadingBuilder: (_) => ColoredBox(
              color: Sutura.void_,
              child: Center(child: Text('CALIBRANDO VISOR…', style: SuturaText.label.copyWith(color: Sutura.signal))),
            ),
          ),
        ),
        // Entrada de puntería (debajo del HUD: los botones tienen prioridad).
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
          ),
        ),
        // Velos para legibilidad.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: hudBottom + 50,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xC0030507), Color(0x66030507), Color(0x00030507)],
                  stops: [0, 0.6, 1],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: bottomBlock + 30,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00030507), Color(0x66030507), Color(0xD0030507)],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
          ),
        ),
        // Números flotantes.
        for (final f in _floats)
          Positioned(
            key: ValueKey(f.id),
            left: f.at.dx - 120,
            top: f.at.dy - 26,
            width: 240,
            child: IgnorePointer(
              child: Center(
                child: FittedBox(fit: BoxFit.scaleDown, child: FloatingNumber(spec: f)),
              ),
            ),
          ),
        // Aviso central.
        if (callout != null && !_showResult)
          Positioned(
            left: 8,
            right: 8,
            top: calloutTop,
            child: IgnorePointer(
              child: Center(
                child: CallOut(
                  key: ValueKey(callout.id),
                  text: callout.text,
                  color: callout.color,
                  sub: callout.sub,
                  icon: callout.icon,
                  sticky: callout.id == 0,
                ),
              ),
            ),
          ),
        // Indicación inicial.
        if (_ready && !_acted && !_aiming && !_itemsOpen && !_ended)
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomBlock + 12,
            child: IgnorePointer(
              child: Center(
                child: PulsingHint(text: firearm ? 'MANTENÉ PARA APUNTAR · SOLTÁ PARA DISPARAR' : 'MANTENÉ PARA APUNTAR · SOLTÁ PARA ATACAR'),
              ),
            ),
          ),
        if (_busy && !_ended)
          Positioned(
            left: 14,
            bottom: bottomBlock + 8,
            child: IgnorePointer(child: Text('TOCÁ PARA ACELERAR', style: SuturaText.label.copyWith(fontSize: 10, color: Sutura.textLow))),
          ),
        // HUD superior: logo + signos vitales | objetivo; etiquetas debajo.
        if (!_showResult) ...[
          Positioned(
            top: topY,
            left: 12,
            width: leftW,
            child: HudShake(
              trigger: _shake,
              // Aísla el ECG (repinta cada cuadro) del resto del HUD.
              child: RepaintBoundary(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: logoH,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: ZcLogo(size: logoSize),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: vitalsH,
                      child: VitalsPanel(
                        health: _hp,
                        maxHealth: s.player.maxHealth,
                        stamina: _sta,
                        maxStamina: s.player.maxStamina,
                        defending: _busy && s.player.defending,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 380),
                      child: hostile ? const HostileTag(key: ValueKey('hostil')) : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: topY + 4,
            right: 12,
            width: rightW,
            child: HudShake(
              trigger: _shake,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TargetPanel(name: s.zombie.name, level: s.zombie.level, threat: threat, health: _zHp, maxHealth: s.zombie.maxHealth, type: s.zombie.typeId),
                  if (chips) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      alignment: WrapAlignment.end,
                      children: [
                        if (chargeChip) const StatusChip('CARGANDO EMBESTIDA…', color: hudRed, blink: true, icon: Icons.warning_rounded),
                        if (_stunned) const StatusChip('ATURDIDO', color: Sutura.signal, icon: Icons.blur_on),
                        if (_screamed) const StatusChip('GRITO', color: Sutura.caution2, icon: Icons.campaign_outlined),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        // HUD inferior: registro + arma (el panel del arma pisa la mano).
        if (!_showResult)
          Positioned(
            left: 12,
            right: 12,
            bottom: rowBottom,
            height: panelH,
            child: HudShake(
              trigger: _shake,
              amplitude: 4,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: CombatLog(lines: _log)),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: weaponW,
                    child: _WeaponSwitch(
                      hasFirearm: _firearmId != null,
                      onTap: controls ? _toggleMode : null,
                      mode: _mode,
                      child: CombatWeaponPanel(
                        weapon: firearm ? _firearmId : _meleeId,
                        ammo: remainingInCombat(s, ItemId.ammo),
                        height: panelH,
                        swapLabel: _firearmId == null ? null : (firearm ? 'C/C' : 'FUEGO'),
                        swapColor: firearm ? Sutura.signal : Sutura.amber,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Botonera.
        if (!_showResult)
          Positioned(
            left: 12,
            right: 12,
            bottom: buttonsBottom,
            height: buttonsH,
            child: ActionBar(
              height: buttonsH,
              cover: ActionButton(
                icon: CrouchGlyph(size: compact ? 24 : 27, color: Sutura.textHi),
                label: 'Cubrirse',
                sub: '−60% daño',
                framed: true,
                highlight: _charging,
                height: buttonsH,
                onTap: controls ? () => _resolve(const CombatAction.defend()) : null,
              ),
              items: ActionButton(
                icon: const Icon(Icons.backpack_outlined),
                label: 'Objetos',
                sub: items.isEmpty ? 'Sin objetos' : '${items.length} disp.',
                active: _itemsOpen,
                height: buttonsH,
                onTap: controls && items.isNotEmpty ? () => setState(() => _itemsOpen = !_itemsOpen) : null,
              ),
              flee: _Nudge(
                key: ValueKey('flee-$_fleeNudge'),
                active: _fleeNudge > 0,
                child: ActionButton(
                  icon: const Icon(Icons.directions_run),
                  label: 'Huir',
                  sub: '${(_fleeChance(s) * 100).round()} %',
                  highlight: _fleeNudge > 0,
                  height: buttonsH,
                  onTap: controls ? () => _resolve(const CombatAction.flee()) : null,
                ),
              ),
            ),
          ),
        // Menú de objetos.
        if (_itemsOpen) ...[
          Positioned.fill(
            bottom: buttonsBottom + buttonsH + 4,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _itemsOpen = false),
              child: const ColoredBox(color: Color(0x99030507)),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: buttonsBottom + buttonsH + 10,
            child: ItemMenu(
              items: items,
              countOf: (id) => remainingInCombat(s, id),
              onPick: (id) => _resolve(CombatAction.useItem(id)),
              onClose: () => setState(() => _itemsOpen = false),
            ),
          ),
        ],
        // Resultado.
        if (_showResult && _ended)
          Positioned.fill(
            child: ResultOverlay(
              status: s.status,
              zombieName: s.zombie.name,
              zombieLevel: s.zombie.level,
              turns: math.max(1, s.turn - 1),
              xp: app.outcome?.reward?.xp ?? 0,
              added: app.outcome?.added ?? const {},
              overflow: app.outcome?.overflow ?? const {},
              lost: app.outcome?.lost ?? const {},
              levelsGained: app.outcome?.levelsGained ?? 0,
              newLevel: (app.outcome?.levelsGained ?? 0) > 0 ? app.player?.level : _levelBefore,
              onExit: _exit,
            ),
          ),
      ],
    );
  }
}

/// Panel del arma tocable: alterna cuerpo a cuerpo ⇄ arma de fuego.
class _WeaponSwitch extends StatelessWidget {
  const _WeaponSwitch({required this.mode, required this.hasFirearm, required this.onTap, required this.child});

  final WeaponMode mode;
  final bool hasFirearm;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!hasFirearm) return IgnorePointer(child: child);
    final other = mode == WeaponMode.melee ? 'arma de fuego' : 'cuerpo a cuerpo';
    return Semantics(
      button: true,
      label: 'Cambiar a $other',
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: child),
    );
  }
}

/// Sacudida corta para llamar la atención sobre un botón (HUIR al tocar atrás).
class _Nudge extends StatelessWidget {
  const _Nudge({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      builder: (context, t, child) => Transform.translate(offset: Offset(math.sin(t * math.pi * 6) * 6 * (1 - t), 0), child: child),
      child: child,
    );
  }
}
