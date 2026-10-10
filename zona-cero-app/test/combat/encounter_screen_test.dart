import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zona_cero/combat/combat_hud.dart' show FloatingNumber;
import 'package:zona_cero/core/core.dart';
import 'package:zona_cero/state/app_state.dart';
import 'package:zona_cero/ui/screens/encounter_screen.dart';

/// Sin arte: la pantalla usa el fondo y la silueta procedurales.
class _NoArt extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => throw FlutterError('Unable to load asset: $key');
}

Future<void> _pumpFor(WidgetTester tester, int ms, {int step = 16}) async {
  for (var t = 0; t < ms; t += step) {
    await tester.pump(Duration(milliseconds: step));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await app.bootstrap();
  });

  setUp(() {
    final p = app.player!.copyWith(health: 100, stamina: 100);
    app.player = p;
    app.combat = startCombat(spawnId: 'test', zombieType: ZombieTypeId.walker, player: p, rng: createRng('encounter'));
    app.combatSpawn = const ZombieSpawn(
      id: 'test',
      cellId: 'c',
      position: LatLng(0, 0),
      zombieType: ZombieTypeId.walker,
      expiresAt: 1 << 40,
      placement: PlacementState.raw,
    );
    app.outcome = null;
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: _NoArt(),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EncounterScreen())),
                child: const Text('ABRIR'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ABRIR'));
    await _pumpFor(tester, 900);
  }

  testWidgets('HUD, cubrirse, objetos, puntería, atrás bloqueado y salida', (tester) async {
    await open(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('SIGNOS VITALES'), findsOneWidget);
    expect(find.text('CAMINANTE', findRichText: true), findsOneWidget);
    expect(find.text('MANTENÉ PARA APUNTAR · SOLTÁ PARA ATACAR'), findsOneWidget);
    expect(find.textContaining('te bloquea el paso'), findsOneWidget);

    // Atrás durante la pelea: no sale, sugiere HUIR.
    await tester.binding.handlePopRoute();
    await _pumpFor(tester, 100);
    expect(find.byType(EncounterScreen), findsOneWidget);
    expect(find.text('NO HAY SALIDA FÁCIL'), findsOneWidget);

    // Cubrirse: consume un turno y bloquea la entrada mientras se reproduce.
    await tester.tap(find.text('CUBRIRSE'));
    await _pumpFor(tester, 50);
    expect(app.combat!.turn, 2);
    expect(app.combat!.lastEvents.first, isA<DefendEvent>());
    expect(find.text('TOCÁ PARA ACELERAR'), findsOneWidget);
    Finder float(String text) => find.descendant(of: find.byType(FloatingNumber), matching: find.text(text));
    expect(float('CUBIERTO'), findsOneWidget); // número flotante del escudo
    final bite = app.combat!.lastEvents.whereType<ZombieHit>().firstOrNull;
    if (bite != null) {
      await _pumpFor(tester, 900);
      expect(float('−${bite.damage}'), findsOneWidget); // daño recibido
    }
    await _pumpFor(tester, 1500);
    expect(find.text('TOCÁ PARA ACELERAR'), findsNothing);

    // Menú rápido de objetos → usar Medicamentos.
    await tester.tap(find.text('OBJETOS'));
    await _pumpFor(tester, 400);
    expect(find.text('MALETÍN · USO RÁPIDO'), findsOneWidget);
    expect(find.text('Medicamentos'), findsOneWidget);
    await tester.tap(find.text('Medicamentos'));
    await _pumpFor(tester, 50);
    expect(app.combat!.lastEvents.first, isA<Heal>());
    await _pumpFor(tester, 1500);

    // Puntería: mantener ~650 ms sobre el zombie y soltar → ataque con precisión.
    if (app.combat!.status == CombatStatus.ongoing) {
      final turn = app.combat!.turn;
      final g = await tester.startGesture(const Offset(195, 520));
      await _pumpFor(tester, 650);
      await g.up();
      await _pumpFor(tester, 50);
      expect(app.combat!.turn, turn + 1);
      final first = app.combat!.lastEvents.first;
      expect(first is PlayerHit || first is PlayerMiss || first is Exhausted, isTrue);
      await _pumpFor(tester, 1600);
    }

    // Un toque corto no ataca.
    if (app.combat!.status == CombatStatus.ongoing) {
      final turn = app.combat!.turn;
      await tester.tapAt(const Offset(195, 520));
      await _pumpFor(tester, 100);
      expect(app.combat!.turn, turn);
    }

    // Huir hasta lograrlo (85 % contra el Caminante).
    for (var i = 0; i < 12 && app.combat!.status == CombatStatus.ongoing; i++) {
      await tester.tap(find.text('HUIR'));
      await _pumpFor(tester, 1600);
    }
    expect(app.combat!.status, isNot(CombatStatus.ongoing));
    await _pumpFor(tester, 2500);
    final title = switch (app.combat!.status) {
      CombatStatus.fled => 'ESCAPASTE',
      CombatStatus.won => 'NEUTRALIZADO',
      _ => 'CAÍSTE',
    };
    expect(find.text(title), findsOneWidget);
    expect(find.text('VOLVER AL MAPA'), findsOneWidget);

    await tester.tap(find.text('VOLVER AL MAPA'));
    await _pumpFor(tester, 1200);
    expect(app.combat, isNull);
    expect(find.byType(EncounterScreen), findsNothing);
    expect(find.text('ABRIR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
