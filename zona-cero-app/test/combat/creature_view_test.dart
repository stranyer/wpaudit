import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Directionality, SizedBox, TextDirection;
import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/combat/combat_art.dart';
import 'package:zona_cero/combat/combat_game.dart';
import 'package:zona_cero/combat/creature_view.dart';
import 'package:zona_cero/combat/fp_hand.dart';
import 'package:zona_cero/combat/puppet_view.dart';
import 'package:zona_cero/combat/stage_layout.dart';
import 'package:zona_cero/core/types.dart';

/// Sin arte: placa y silueta procedurales, sin manos ni relieve.
class _Empty extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => throw FlutterError('Unable to load asset: $key');
}

/// Vista falsa: anota qué le pidió la escena.
class _FakeView implements CreatureView {
  final List<String> calls = [];
  int updates = 0, renders = 0;
  bool _dead = false;
  bool crouch = false;

  @override
  bool get hasPose => true;
  @override
  bool get dead => _dead;
  @override
  Rect get bodyWorld => const Rect.fromLTRB(100, 200, 290, 640);
  @override
  Rect get headWorld => const Rect.fromLTRB(170, 200, 220, 250);
  @override
  double get lunge => 0;
  @override
  double get dissolve => 0;
  @override
  Offset? randomPoint(math.Random rnd, {required double minH, required double maxH, required double maxSide}) => const Offset(195, 400);
  @override
  set holdCrouch(bool value) => crouch = value;
  @override
  void update(double dt, CreatureStage stage) => updates++;
  @override
  void render(Canvas canvas, CreatureStage stage) => renders++;
  @override
  void dispose() => calls.add('dispose');
  @override
  void idle() => calls.add('idle');
  @override
  double attack() {
    calls.add('attack');
    return 0.7;
  }

  @override
  double chargePrepare() {
    calls.add('chargePrepare');
    return 0.5;
  }

  @override
  double charge() {
    calls.add('charge');
    return 0.9;
  }

  @override
  double scream() {
    calls.add('scream');
    return 1.2;
  }

  @override
  double die() {
    calls.add('die');
    _dead = true;
    return 2;
  }

  @override
  void flee() => calls.add('flee');
  @override
  void hit(Offset at, {bool strong = false, bool crit = false, bool headshot = false, bool lethal = false}) =>
      calls.add('hit${strong ? ':strong' : ''}${lethal ? ':lethal' : ''}');
  @override
  double keyTime(ZombieAnim a) => 0.333;
  @override
  double duration(ZombieAnim a) => 0.777;
}

class _Stage implements CreatureStage {
  _Stage(this.layout);
  @override
  final StageLayout? layout;
  @override
  double time = 0;
  @override
  bool charging = false;
  @override
  double get hudTop => 700;
  @override
  PlateLook get look => CombatPlate.colon.look;
  @override
  double get beacon => 0.5;
  @override
  double flashLight = 0;
}

void main() {
  testWidgets('la escena maneja a la criatura solo por CreatureView', (tester) async {
    final fake = _FakeView();
    final game = CombatStageGame(zombieType: ZombieTypeId.brute, bundle: _Empty(), hand: HandKind.fists, creatureFactory: (_) => fake);
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: GameWidget(game: game)));
    for (var i = 0; i < 30 && game.creature == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(game.creature, same(fake));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(fake.updates, greaterThan(0));
    expect(fake.renders, greaterThan(0));
    expect(game.art!.proceduralPlate, isTrue);

    // Animaciones por nombre → eventos de la vista; los tiempos salen de ella.
    expect(game.playZombie(ZombieAnim.attack), 0.7);
    expect(game.playZombie(ZombieAnim.chargePrepare), 0.5);
    expect(game.playZombie(ZombieAnim.charge), 0.9);
    expect(game.playZombie(ZombieAnim.scream), 1.2);
    expect(game.zombieKeyTime(ZombieAnim.attack), 0.333);
    expect(game.zombieDuration(ZombieAnim.death), 0.777);
    game.charging = true;
    await tester.pump(const Duration(milliseconds: 16));
    expect(fake.crouch, isTrue);
    game.impact(const Offset(195, 400), heavy: true);
    game.impact(const Offset(195, 400), lethal: true);
    expect(game.playZombie(ZombieAnim.death), 2);
    game.fleeOut();
    expect(fake.calls, ['attack', 'chargePrepare', 'charge', 'scream', 'hit:strong', 'hit:lethal', 'die', 'flee']);
    // La cabeza para la puntería sale de la vista (muerta: sin cabeza).
    expect(game.headRect, Rect.zero);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('títere: eventos, pose, golpe, muerte (sin relieve: luz de reserva)', (tester) async {
    final art = (await tester.runAsync(() => CombatArt.load(ZombieTypeId.walker, bundle: _Empty())))!;
    final view = PuppetCreatureView(art);
    expect(view.hasRelief, isFalse);
    final layout = StageLayout.compute(view: const Size(390, 844), plate: art.plateSize, rig: art.rig, profile: placementProfiles[ZombieTypeId.walker]!);
    final stage = _Stage(layout);
    expect(view.hasPose, isFalse);
    view.update(1 / 60, stage);
    expect(view.hasPose, isTrue);
    expect(view.bodyWorld.overlaps(layout.body), isTrue);
    expect(view.bodyWorld.inflate(4).contains(view.headWorld.center), isTrue);
    expect(view.randomPoint(math.Random(1), minH: 0, maxH: 1, maxSide: 2), isNotNull);

    expect(view.attack(), view.duration(ZombieAnim.attack));
    expect(view.keyTime(ZombieAnim.attack), lessThan(view.duration(ZombieAnim.attack)));
    for (var t = 0.0; t < view.keyTime(ZombieAnim.attack); t += 1 / 60) {
      view.update(1 / 60, stage);
    }
    expect(view.lunge, greaterThan(0.9));
    for (var i = 0; i < 60; i++) {
      view.update(1 / 60, stage);
    }
    expect(view.lunge, 0);

    view.hit(layout.body.center, strong: true);
    view.holdCrouch = true;
    // Pinta sin errores (con relieve ausente usa la pasada de luz de reserva).
    final rec = PictureRecorder();
    view.render(Canvas(rec), stage);
    rec.endRecording().dispose();

    expect(view.die(), view.duration(ZombieAnim.death));
    for (var i = 0; i < 150; i++) {
      view.update(1 / 60, stage);
    }
    expect(view.dead, isTrue);
    expect(view.dissolve, greaterThan(0.9));
    expect(view.headWorld, Rect.zero);
    expect(view.attack(), 0); // muerta no reacciona
    view.dispose();
    art.dispose();
  });
}
