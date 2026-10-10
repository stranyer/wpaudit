import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/combat/combat_art.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sin arte: placa y silueta procedurales con su rig', (tester) async {
    for (final type in ZombieTypeId.values) {
      final bundle = EmptyBundle();
      final art = (await tester.runAsync(() => CombatArt.load(type, bundle: bundle)))!;
      expect(bundle.requested, containsAll([CombatArt.plateAsset, CombatArt.cutoutAsset(type)]));
      expect(art.proceduralPlate, isTrue);
      expect(art.fallbackCutout, isTrue, reason: '$type');
      expect(art.plateHorizon, 0.42);
      final rig = art.rig;
      expect(rig.size.width, art.cutout.width);
      expect(rig.body.isEmpty, isFalse);
      // Cabeza dentro del cuerpo, arriba; pies en el borde inferior.
      expect(rig.body.inflate(2).contains(rig.head.center), isTrue, reason: '$type');
      expect(rig.head.center.dy, lessThan(rig.body.top + rig.body.height * 0.2));
      expect(rig.feet.dy, rig.body.bottom);
      expect(art.fxAtlas.width, 160);
      expect(art.grain.width, 96);
      art.dispose();
    }
  });

  testWidgets('arte real: recorte HD analizado y placa de la calle', (tester) async {
    if (!File(CombatArt.cutoutAsset(ZombieTypeId.walker)).existsSync()) return;
    for (final type in ZombieTypeId.values) {
      final art = (await tester.runAsync(() => CombatArt.load(type, bundle: rootBundle)))!;
      expect(art.fallbackCutout, isFalse, reason: '$type');
      expect(art.proceduralPlate, isFalse);
      expect(art.plateSize, const Size(1024, 1536));
      expect(art.cutout.height, 1400);
      expect(art.rig.body.height, greaterThan(1300), reason: '$type');
      expect(art.rig.body.inflate(1).contains(art.rig.head.center), isTrue, reason: '$type');
      art.dispose();
    }
  });
}
