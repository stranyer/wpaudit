import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/combat/combat_art.dart';
import 'package:zona_cero/combat/combat_manifest.dart';
import 'package:zona_cero/core/types.dart';

/// Bundle sin nada: simula que el arte todavía no llegó.
class EmptyBundle extends CachingAssetBundle {
  final List<String> requested = [];

  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    throw FlutterError('Unable to load asset: $key');
  }
}

/// Bundle con un manifiesto que referencia una tira que no existe.
class BrokenStripBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith('manifest.json')) {
      final bytes = Uint8List.fromList(
        '{"zombies":{"walker":{"idle":{"file":"missing.png","frames":4}}}}'.codeUnits,
      );
      return ByteData.sublistView(bytes);
    }
    throw FlutterError('Unable to load asset: $key');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sin arte: fondo y silueta procedurales', (tester) async {
    final bundle = EmptyBundle();
    final art = (await tester.runAsync(() => CombatArt.load(ZombieTypeId.brute, bundle: bundle)))!;
    expect(art.manifest.isFallback, isTrue);
    expect(art.hasSprites, isFalse);
    expect(art.proceduralBackground, isTrue);
    expect(art.background.width, 720);
    expect(art.background.height, 1280);
    expect(art.foreground, isNull);
    expect(art.procedural, isNotNull);
    expect(art.bodyInFrame.isEmpty, isFalse);
    expect(art.headsInFrame, hasLength(1));
    // La cabeza está dentro del cuerpo y arriba.
    final head = art.headsInFrame.single;
    expect(art.bodyInFrame.inflate(1).contains(head.center), isTrue);
    expect(head.center.dy, lessThan(art.bodyInFrame.center.dy));
    // Encuadre igual al arte real.
    expect(art.placement.bgRect, const Rect.fromLTWH(0, 320, 720, 960));
    expect(art.durationOf(ZombieAnim.death), greaterThan(0));
    expect(art.keyTimeOf(ZombieAnim.attack), lessThan(art.durationOf(ZombieAnim.attack)));
    expect(bundle.requested, contains('assets/combat/bg_street.jpg'));
    art.dispose();
  });

  testWidgets('manifiesto presente pero tira faltante → silueta procedural', (tester) async {
    final art = (await tester.runAsync(() => CombatArt.load(ZombieTypeId.walker, bundle: BrokenStripBundle())))!;
    expect(art.manifest.isFallback, isFalse);
    expect(art.hasSprites, isFalse);
    expect(art.procedural, isNotNull);
    art.dispose();
  });

  testWidgets('arte real: tiras, caja del cuerpo y cabeza por cuadro', (tester) async {
    if (!File('assets/combat/walker_idle.png').existsSync()) return;
    for (final type in ZombieTypeId.values) {
      final art = (await tester.runAsync(() => CombatArt.load(type, bundle: rootBundle)))!;
      expect(art.hasSprites, isTrue, reason: '$type');
      expect(art.proceduralBackground, isFalse);
      expect(art.foreground, isNotNull);
      final idle = art.strips[ZombieAnim.idle]!;
      expect(art.headsInFrame, hasLength(idle.spec.frames), reason: '$type');
      final body = art.bodyInFrame;
      for (final h in art.headsInFrame) {
        // Cabeza: arriba del cuerpo, chica (es difícil de acertar a propósito).
        expect(body.inflate(2).contains(h.center), isTrue, reason: '$type $h in $body');
        expect(h.width, lessThan(body.width * 0.5), reason: '$type');
        expect(h.height, inInclusiveRange(20, 0.16 * 480), reason: '$type');
        expect(h.top, closeTo(body.top, 12), reason: '$type');
      }
      if (type == ZombieTypeId.brute) {
        expect(art.strips[ZombieAnim.charge], isNotNull);
        // Al preparar la embestida esconde la cabeza: sin zona de cabeza.
        expect(art.headHoldInFrame, Rect.zero);
      }
      art.dispose();
    }
  });
}
