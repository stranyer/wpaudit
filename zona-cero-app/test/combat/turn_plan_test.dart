import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/combat/turn_plan.dart';
import 'package:zona_cero/core/core.dart';

void main() {
  const hit = PlayerHit(damage: 9, crit: false, ranged: false, stunBonus: false);
  const bite = ZombieHit(damage: 7, blocked: 0, charged: false);

  group('planTurn', () {
    test('turno típico: jugador → pausa → zombie, entre 1.0 y 1.4 s', () {
      for (final evs in [
        const [hit, bite],
        const [PlayerMiss(ranged: false), ZombieMiss(charged: false)],
        const [DefendEvent(stamina: 12), bite],
        [const Heal(itemId: ItemId.medkit, health: 30, stamina: 0), bite],
      ]) {
        final plan = planTurn(evs, windupMs: (_) => 233);
        expect(plan.endMs, inInclusiveRange(1000, 1400), reason: '$evs');
        final p = plan.events.firstWhere((e) => !isZombiePhase(e.event));
        final z = plan.events.firstWhere((e) => isZombiePhase(e.event));
        expect(z.atMs - p.atMs, greaterThanOrEqualTo(TurnTiming.pause));
        expect(z.impactMs, z.atMs + 233);
      }
    });

    test('la anticipación del ataque se acota', () {
      expect(planTurn(const [bite], windupMs: (_) => 2000).events.single.impactMs, TurnTiming.maxWindup);
      expect(planTurn(const [bite], windupMs: (_) => 10).events.single.impactMs, TurnTiming.minWindup);
    });

    test('golpe mortal: muerte poco después del impacto, sin fase del zombie', () {
      final plan = planTurn(const [hit, ZombieKilled()]);
      expect(plan.events.map((e) => e.atMs), [0, TurnTiming.killStep]);
      expect(plan.endMs, TurnTiming.killStep + TurnTiming.tail);
    });

    test('doble ataque del Corredor y caída del jugador van en orden', () {
      final plan = planTurn(const [hit, bite, bite, PlayerDown()], windupMs: (_) => 300);
      final at = plan.events.map((e) => e.atMs).toList();
      for (var i = 1; i < at.length; i++) {
        expect(at[i], greaterThan(at[i - 1]));
      }
      final second = plan.events[2];
      expect(second.atMs, plan.events[1].impactMs + TurnTiming.recover);
      expect(plan.events.last.event, isA<PlayerDown>());
      expect(plan.events.last.atMs, second.impactMs + TurnTiming.downDelay);
    });

    test('preparación de embestida (sin ataque) también se muestra después', () {
      final plan = planTurn(const [hit, ZombieChargePrepare()]);
      expect(plan.events[1].atMs, TurnTiming.pause);
      expect(plan.events[1].impactMs, plan.events[1].atMs);
    });
  });

  group('TurnSequencer', () {
    testWidgets('ejecuta en orden y respeta los tiempos', (tester) async {
      final seq = TurnSequencer();
      final log = <String>[];
      var done = false;
      seq.play([SeqCue(500, () => log.add('b')), SeqCue(0, () => log.add('a')), SeqCue(900, () => log.add('c'))], onDone: () => done = true);
      expect(log, ['a']);
      await tester.pump(const Duration(milliseconds: 499));
      expect(log, ['a']);
      await tester.pump(const Duration(milliseconds: 2));
      expect(log, ['a', 'b']);
      expect(seq.isPlaying, isTrue);
      await tester.pump(const Duration(milliseconds: 400));
      expect(log, ['a', 'b', 'c']);
      expect(done, isTrue);
      expect(seq.isPlaying, isFalse);
    });

    testWidgets('hurry acelera lo que falta', (tester) async {
      final seq = TurnSequencer();
      final log = <int>[];
      seq.play([for (final t in [0, 400, 800, 1200]) SeqCue(t, () => log.add(t))]);
      await tester.pump(const Duration(milliseconds: 10));
      seq.hurry(4);
      expect(seq.hurried, isTrue);
      await tester.pump(const Duration(milliseconds: 101));
      expect(log, [0, 400]);
      await tester.pump(const Duration(milliseconds: 200));
      expect(log, [0, 400, 800, 1200]);
    });

    testWidgets('cancel corta la reproducción', (tester) async {
      final seq = TurnSequencer();
      final log = <int>[];
      seq.play([SeqCue(0, () => log.add(0)), SeqCue(300, () => log.add(300))]);
      seq.cancel();
      await tester.pump(const Duration(seconds: 1));
      expect(log, [0]);
      expect(seq.isPlaying, isFalse);
    });
  });
}
