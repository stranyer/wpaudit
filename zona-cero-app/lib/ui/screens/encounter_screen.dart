// Pantalla de encuentro: escenario Flame + HUD clínico + minijuego de puntería.
//
// La abre el shell como ruta a pantalla completa después de que
// `app.engage(spawn)` devolvió true (así `app.combat` y `app.combatSpawn` ya
// están cargados). Al salir llama a `app.leaveCombat()` y hace `pop`.

import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../combat/aim.dart';
import '../../combat/combat_game.dart';
import '../../combat/combat_hud.dart';
import '../../combat/combat_manifest.dart' show ZombieAnim;
import '../../combat/turn_plan.dart';
import '../../core/core.dart';
import '../../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/chamfer_button.dart';
import '../widgets/seg_bar.dart' show MicroText;

class EncounterScreen extends StatefulWidget {
  const EncounterScreen({super.key});

  @override
  State<EncounterScreen> createState() => _EncounterScreenState();
}

class _CallOutSpec {
  const _CallOutSpec(this.id, this.text, this.color, this.sub);
  final int id;
  final String text;
  final Color color;
  final String? sub;
}

class _EncounterScreenState extends State<EncounterScreen> {
  CombatState? _state;
  late CombatStageGame _game;
  bool _gameCreated = false;
  final TurnSequencer _seq = TurnSequencer();
  final List<Timer> _timers = [];
  final math.Random _rnd = math.Random();

  bool _ready = false;
  bool _busy = false;
  bool _acted = false;
  bool _aiming = false;
  bool _itemsOpen = false;
  bool _showResult = false;
  bool _exiting = false;
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
  int? _levelBefore;
  Offset _playerAnchor = const Offset(90, 160);

  bool get _ended => _state == null || _state!.status != CombatStatus.ongoing;
  bool get _canAct => _ready && !_busy && !_ended && !_exiting;

  @override
  void initState() {
    super.initState();
    final s = app.combat;
    _state = s;
    final type = s?.zombie.typeId ?? app.combatSpawn?.zombieType ?? ZombieTypeId.walker;
    _levelBefore = app.player?.level;
    _zombieType = type;
    if (s != null) {
      _hp = s.player.health;
      _sta = s.player.stamina;
      _zHp = s.zombie.health;
      _charging = s.zombie.charging;
      _stunned = s.zombie.stunned;
      _addLog('Un ${s.zombie.name} de nivel ${s.zombie.level} te bloquea el paso.', Sutura.textHi);
      final ability = zombieDefs[s.zombie.typeId]!.ability;
      if (ability == ZombieAbility.toxicBurst) {
        _addLog('Explota al morir: rematalo con un disparo.', Sutura.toxin);
      } else if (ability == ZombieAbility.charge) {
        _addLog('Prepara embestidas: cubrite en el momento justo.', Sutura.caution);
      }
    }
  }

  late ZombieTypeId _zombieType;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_gameCreated) return;
    _gameCreated = true;
    // El bundle sale del contexto (los tests y el banco de pruebas pueden
    // inyectar uno sin arte para ejercitar la reserva procedural).
    _game = CombatStageGame(
      zombieType: _zombieType,
      bundle: DefaultAssetBundle.of(context),
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
    for (final t in _timers) {
      t.cancel();
    }
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

  void _call(String text, Color color, {String? sub}) {
    final c = _CallOutSpec(_ids++, text, color, sub);
    _callout = c;
    _later(1200, () {
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
    ZombieHit() || ToxicBurst() || PlayerDown() || ZombieScream() || FleeFail() => const Color(0xFFFF7A80),
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
    } else {
      action = shot.charged ? CombatAction.heavy(precision: shot.precision) : CombatAction.attack(precision: shot.precision);
      _game.slash(shot.zone == AimZone.off ? shot.point : _game.impactPointFor(shot.point), heavy: shot.charged);
    }
    HapticFeedback.mediumImpact();
    _resolve(action, shot: shot);
  }

  void _noAmmo() {
    setState(() {
      _mode = WeaponMode.melee;
      _call('SIN MUNICIÓN', Sutura.danger, sub: 'CAMBIO A CUERPO A CUERPO');
    });
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
        if (!kill) _game.playZombie(ZombieAnim.hit);
        _game.impact(at, crit: e.crit, heavy: action is Heavy, ranged: e.ranged);
        _zHp = math.max(0, _zHp - e.damage);
        _float(
          e.crit ? FloatKind.crit : FloatKind.damage,
          '−${e.damage}',
          at.translate(0, -30),
          sub: e.headshot ? 'CABEZA' : (e.crit ? 'CRÍTICO' : null),
        );
        if (e.headshot && e.ranged) {
          _call('DISPARO A LA CABEZA', Sutura.amber, sub: 'IMPACTO CRÍTICO ×1,75');
        } else if (e.crit) {
          _call('GOLPE CRÍTICO', Sutura.amber, sub: e.stunBonus ? 'OBJETIVO ATURDIDO' : (e.headshot ? 'A LA CABEZA' : null));
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
        _game.shieldUp();
        _sta = math.min(st.player.maxStamina.toDouble(), _sta + e.stamina);
        final gained = e.stamina.round();
        _float(FloatKind.blocked, gained > 0 ? '+$gained RES' : 'CUBIERTO', _playerAnchor, sub: gained > 0 ? 'CUBIERTO' : null);
      case Heal():
        _game.healPulse();
        _hp = math.min(st.player.maxHealth.toDouble(), _hp + e.health);
        _sta = math.min(st.player.maxStamina.toDouble(), _sta + e.stamina);
        if (e.health > 0) _float(FloatKind.heal, '+${e.health.round()}', _playerAnchor, sub: itemDefs[e.itemId]!.name.toUpperCase());
        if (e.stamina > 0) _float(FloatKind.info, '+${e.stamina.round()} RES', _playerAnchor.translate(0, 44));
      case FleeSuccess():
        _game.fleeOut();
      case FleeFail():
        _game.shake(0.3);
        _call('¡TE CORTA EL PASO!', Sutura.danger);
      case ZombieKilled():
        _game.playZombie(ZombieAnim.death);
        HapticFeedback.mediumImpact();
      case ToxicBurst():
        _game.toxicCloud();
        _hp = math.max(0, _hp - e.damage);
        _float(FloatKind.hurt, '−${e.damage.round()}', _playerAnchor, sub: 'TÓXICO');
        HapticFeedback.heavyImpact();
      case ZombieHit():
        _game.playZombie(_attackAnim(e));
        log = false;
      case ZombieMiss():
        _game.playZombie(_attackAnim(e));
        log = false;
      case ZombieChargePrepare():
        _game.playZombie(ZombieAnim.chargePrepare);
        _charging = true;
        _call('¡CUBRITE!', Sutura.danger, sub: 'PREPARA UNA EMBESTIDA');
        HapticFeedback.mediumImpact();
      case ZombieStunned():
        _stunned = st.zombie.stunned;
        // Tras esquivar la embestida el aviso central ya lo dice.
        if (!st.lastEvents.any((x) => x is ZombieMiss && x.charged)) {
          _float(FloatKind.info, 'ATURDIDO', _game.headPoint.translate(0, -16), sub: 'PIERDE EL TURNO');
        }
      case ZombieScream():
        _game.playZombie(ZombieAnim.scream);
        _later((_game.zombieKeyTime(ZombieAnim.scream) * 1000).round(), _game.screamWave);
        _zHp = math.min(st.zombie.maxHealth, _zHp + e.healed);
        _screamed = true;
        _float(FloatKind.heal, '+${e.healed}', _game.headPoint.translate(0, -10), sub: 'REFUERZOS');
        _call('¡GRITO!', Sutura.caution2, sub: 'LLEGAN REFUERZOS');
      case PlayerDown():
        _game.playerDown();
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
        _hp = math.max(0, _hp - e.damage);
        _float(FloatKind.hurt, '−${e.damage}', _playerAnchor, blocked: e.blocked, sub: e.charged ? 'EMBESTIDA' : null);
        if (e.charged) {
          _charging = false;
          _call('¡EMBESTIDA!', Sutura.danger);
        }
        HapticFeedback.heavyImpact();
      case ZombieMiss():
        if (e.charged) {
          _charging = false;
          _game.dodge();
          _float(FloatKind.info, '¡ESQUIVADA!', _playerAnchor);
          _call('¡ESQUIVADA!', Sutura.signal, sub: 'QUEDA ATURDIDO');
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
        _call('SIN MUNICIÓN', Sutura.danger, sub: 'CAMBIO A CUERPO A CUERPO');
      }
    });
    _syncGameFlags();
    if (st.status != CombatStatus.ongoing) {
      final delay = switch (st.status) {
        CombatStatus.won => (_game.zombieDuration(ZombieAnim.death) * 1000).round() + 450,
        CombatStatus.lost => 1100,
        _ => 650,
      };
      _later(delay, () => setState(() => _showResult = true));
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
      _call('NO HAY SALIDA FÁCIL', Sutura.caution, sub: 'USÁ HUIR PARA RETIRARTE');
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
        maxScaleFactor: 1.2,
        child: Scaffold(backgroundColor: Sutura.void_, body: s == null ? _noEncounter() : _stage(context, s)),
      ),
    );
  }

  Widget _noEncounter() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const MicroText('SIN ENCUENTRO ACTIVO'),
        const SizedBox(height: 16),
        ChamferButton(label: 'Volver al mapa', tone: ChamferTone.primary, onPressed: _exit),
      ],
    ),
  );

  Widget _stage(BuildContext context, CombatState s) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final bottom = pad.bottom + 10;
    const buttonsH = 50.0;
    const rowH = 76.0;
    final bottomBlock = bottom + buttonsH + 8 + rowH;
    _playerAnchor = Offset(size.width * 0.26, pad.top + 128);
    final player = app.player;
    final threat = threatRating(zombieDefs[s.zombie.typeId]!, player?.level ?? 1);
    final items = usableItems(s);
    final controls = _canAct && !_aiming;
    final weaponW = math.min(200.0, size.width * 0.52);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Escenario.
        Positioned.fill(
          child: GameWidget<CombatStageGame>(
            game: _game,
            loadingBuilder: (_) => const ColoredBox(
              color: Sutura.void_,
              child: Center(child: MicroText('CALIBRANDO VISOR…', color: Sutura.signal)),
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
          height: pad.top + 150,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xCC030507), Color(0x00030507)]),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: bottomBlock + 70,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00030507), Color(0xB3030507), Color(0xF2030507)],
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
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: FloatingNumber(spec: f),
                ),
              ),
            ),
          ),
        // Aviso central.
        if (_callout != null)
          Positioned(
            left: 16,
            right: 16,
            top: pad.top + 132,
            child: IgnorePointer(
              child: Center(
                child: CallOut(key: ValueKey(_callout!.id), text: _callout!.text, color: _callout!.color, sub: _callout!.sub),
              ),
            ),
          ),
        // Indicación inicial.
        if (_ready && !_acted && !_aiming && !_itemsOpen && !_ended)
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomBlock + 16,
            child: IgnorePointer(
              child: Center(
                child: PulsingHint(
                  text: _mode == WeaponMode.firearm ? 'MANTENÉ PARA APUNTAR · SOLTÁ PARA DISPARAR' : 'MANTENÉ PARA APUNTAR · SOLTÁ PARA ATACAR',
                ),
              ),
            ),
          ),
        if (_busy && !_ended)
          Positioned(
            right: 14,
            bottom: bottomBlock + 14,
            child: const IgnorePointer(child: MicroText('TOCÁ PARA ACELERAR', color: Sutura.textLow)),
          ),
        // HUD superior.
        if (!_showResult)
          Positioned(
            top: pad.top + 8,
            left: 12,
            right: 12,
            // Aísla el ECG (repinta cada cuadro) del resto del HUD.
            child: RepaintBoundary(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: VitalsPanel(
                            health: _hp,
                            maxHealth: s.player.maxHealth,
                            stamina: _sta,
                            maxStamina: s.player.maxStamina,
                            defending: _busy && s.player.defending,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TargetPanel(name: s.zombie.name, level: s.zombie.level, threat: threat, health: _zHp, maxHealth: s.zombie.maxHealth),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      alignment: WrapAlignment.end,
                      children: [
                        if (_charging) const StatusChip('CARGANDO EMBESTIDA', color: Sutura.danger, blink: true, icon: Icons.warning_amber_rounded),
                        if (_stunned) const StatusChip('ATURDIDO', color: Sutura.signal, icon: Icons.blur_on),
                        if (_screamed) const StatusChip('GRITO', color: Sutura.caution2, icon: Icons.campaign_outlined),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        // HUD inferior: registro + arma (el panel del arma toma su alto natural).
        if (!_showResult)
          Positioned(
            left: 12,
            right: 12,
            bottom: bottom + buttonsH + 8,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: SizedBox(
                    height: rowH,
                    child: CombatLogTicker(lines: _log),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: weaponW,
                  child: WeaponPanel(
                    mode: _mode,
                    meleeName: s.player.meleeName,
                    meleeDamage: s.player.melee.damage,
                    firearmName: s.player.firearmName,
                    ammo: remainingInCombat(s, ItemId.ammo),
                    ammoPerShot: s.player.firearm?.ammoPerShot ?? 1,
                    onToggle: controls ? _toggleMode : null,
                  ),
                ),
              ],
            ),
          ),
        // Botonera.
        if (!_showResult)
          Positioned(
            left: 12,
            right: 12,
            bottom: bottom,
            height: buttonsH,
            child: Row(
              children: [
                Expanded(
                  child: ChamferButton(
                    label: 'Cubrirse',
                    sublabel: _charging ? '¡AHORA!' : '−60% DAÑO',
                    icon: Icons.shield_outlined,
                    dense: true,
                    height: buttonsH,
                    expand: true,
                    tone: _charging ? ChamferTone.primary : ChamferTone.neutral,
                    onPressed: controls ? () => _resolve(const CombatAction.defend()) : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChamferButton(
                    label: 'Objetos',
                    sublabel: items.isEmpty ? 'SIN OBJETOS' : '${items.length} DISP.',
                    icon: Icons.medical_services_outlined,
                    dense: true,
                    height: buttonsH,
                    expand: true,
                    tone: _itemsOpen ? ChamferTone.amber : ChamferTone.neutral,
                    onPressed: controls && items.isNotEmpty ? () => setState(() => _itemsOpen = !_itemsOpen) : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Nudge(
                    key: ValueKey('flee-$_fleeNudge'),
                    active: _fleeNudge > 0,
                    child: ChamferButton(
                      label: 'Huir',
                      sublabel: '${(_fleeChance(s) * 100).round()} %',
                      icon: Icons.directions_run,
                      dense: true,
                      height: buttonsH,
                      expand: true,
                      tone: _fleeNudge > 0 ? ChamferTone.danger : ChamferTone.ghost,
                      onPressed: controls ? () => _resolve(const CombatAction.flee()) : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Menú de objetos.
        if (_itemsOpen) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _itemsOpen = false),
              child: const ColoredBox(color: Color(0x99030507)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomBlock + 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MicroText('MALETÍN · USO RÁPIDO', color: Sutura.textMid),
                const SizedBox(height: 10),
                ItemCross(
                  items: items,
                  countOf: (id) => remainingInCombat(s, id),
                  onPick: (id) => _resolve(CombatAction.useItem(id)),
                  onClose: () => setState(() => _itemsOpen = false),
                ),
              ],
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
