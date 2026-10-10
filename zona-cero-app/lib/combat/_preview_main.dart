// ARNÉS TEMPORAL de vista previa del combate (se borra al terminar).
// ?type=brute|walker|runner|bloater|screamer  ?weapon=pistol|shotgun|bat|fists
// ?spawn=<id> (elige la placa)  ?hp=<salud>  ?lvl=<nivel>

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import 'package:flutter/services.dart';

import '../core/core.dart';
import '../state/app_state.dart';
import '../ui/screens/encounter_screen.dart';
import '../ui/theme/theme.dart';
import '../ui/widgets/grit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GritAssets.load();
  await app.bootstrap();
  final q = Uri.base.queryParameters;
  final type = ZombieTypeId.values.firstWhere((t) => t.key == q['type'], orElse: () => ZombieTypeId.brute);
  final weapon = q['weapon'] ?? 'pistol';
  final inv = <ItemId, int>{
    ItemId.ammo: 32,
    ItemId.medkit: 2,
    ItemId.medicine: 2,
    ItemId.water: 3,
    ItemId.food: 2,
    ItemId.adrenaline: 1,
    ItemId.pistol: 1,
    ItemId.shotgun: 1,
    ItemId.nailBat: 1,
  };
  final eq = switch (weapon) {
    'shotgun' => const Equipment(melee: ItemId.nailBat, firearm: ItemId.shotgun),
    'bat' => const Equipment(melee: ItemId.nailBat),
    'fists' => const Equipment(),
    _ => const Equipment(melee: ItemId.nailBat, firearm: ItemId.pistol),
  };
  final p = app.player!.copyWith(
    level: int.tryParse(q['lvl'] ?? '') ?? 4,
    health: double.tryParse(q['hp'] ?? '') ?? 78,
    stamina: 100,
    inventory: inv,
    equipment: eq,
  );
  app.player = p;
  final spawnId = q['spawn'] ?? 'preview-colon';
  var c = startCombat(spawnId: spawnId, zombieType: type, player: p, rng: createRng('preview-$spawnId'));
  if (q['charge'] == '1') c = c.copyWith(zombie: c.zombie.copyWith(chargeIn: 0));
  app.combat = c;
  final slow = double.tryParse(q['slow'] ?? '');
  if (slow != null) timeDilation = slow;
  app.combatSpawn = ZombieSpawn(
    id: spawnId,
    cellId: 'c',
    position: const LatLng(-34.6, -58.38),
    zombieType: type,
    expiresAt: 1 << 40,
    placement: PlacementState.raw,
  );
  app.outcome = null;
  final app0 = MaterialApp(debugShowCheckedModeBanner: false, theme: buildSuturaTheme(), home: const EncounterScreen());
  runApp(q['relief'] == '0' ? DefaultAssetBundle(bundle: _NoRelief(), child: app0) : app0);
}

/// Sin mapas de relieve (para comparar antes/después).
class _NoRelief extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key.contains('/relief/')) throw FlutterError('sin relieve: $key');
    return rootBundle.load(key);
  }
}
