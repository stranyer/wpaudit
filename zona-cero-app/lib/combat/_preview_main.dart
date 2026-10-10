// TEMPORAL: banco de pruebas visual del combate (sin GPS ni mapa).
// Parámetros (web): ?type=walker|runner|bloater|screamer|brute
//                   &gear=1 (pistola + machete + munición + botiquines)
//                   &zhp=N (vida del zombie) &php=N (vida del jugador) &lvl=N &xp=N
//                   &noart=1 (simula que falta el arte → reserva procedural)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/core.dart';
import '../state/app_state.dart';
import '../ui/screens/encounter_screen.dart';
import '../ui/theme/theme.dart';
import '../ui/theme/tokens.dart';
import '../ui/widgets/chamfer_button.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await app.bootstrap();
  runApp(const _PreviewApp());
}

Map<String, String> get _q => Uri.base.queryParameters;

void _setupFight(ZombieTypeId type) {
  var p = app.player!;
  final lvl = int.tryParse(_q['lvl'] ?? '');
  if (lvl != null) p = p.copyWith(level: lvl);
  final xp = int.tryParse(_q['xp'] ?? '');
  if (xp != null) p = p.copyWith(xp: xp);
  if (_q['gear'] == '1') {
    p = p.copyWith(
      equipment: const Equipment(melee: ItemId.machete, firearm: ItemId.pistol, armor: ItemId.leatherJacket),
      inventory: {
        ...p.inventory,
        ItemId.ammo: 7,
        ItemId.medkit: 1,
        ItemId.medicine: 2,
        ItemId.food: 2,
        ItemId.water: 1,
        ItemId.ration: 1,
        ItemId.adrenaline: 1,
      },
    );
  }
  p = p.copyWith(health: double.tryParse(_q['php'] ?? '') ?? p.maxHealth.toDouble(), stamina: p.maxStamina.toDouble());
  app.player = p;
  var state = startCombat(spawnId: 'preview', zombieType: type, player: p, rng: randomRng());
  final zhp = int.tryParse(_q['zhp'] ?? '');
  if (zhp != null) state = state.copyWith(zombie: state.zombie.copyWith(health: zhp));
  app.combat = state;
  app.combatSpawn = ZombieSpawn(
    id: 'preview',
    cellId: 'preview',
    position: const LatLng(-34.6037, -58.3816),
    zombieType: type,
    expiresAt: DateTime.now().millisecondsSinceEpoch + 3600000,
    placement: PlacementState.raw,
  );
  app.outcome = null;
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(debugShowCheckedModeBanner: false, theme: buildSuturaTheme(), home: const _Launcher());
    return _q['noart'] == '1' ? DefaultAssetBundle(bundle: _NoArt(), child: app) : app;
  }
}

class _NoArt extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => throw FlutterError('sin arte: $key');
}

class _Launcher extends StatefulWidget {
  const _Launcher();

  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  @override
  void initState() {
    super.initState();
    final t = ZombieTypeId.tryFromKey(_q['type']);
    if (t != null) WidgetsBinding.instance.addPostFrameCallback((_) => _open(t));
  }

  void _open(ZombieTypeId t) {
    _setupFight(t);
    Navigator.of(context).push(PageRouteBuilder<void>(pageBuilder: (_, _, _) => const EncounterScreen(), transitionDuration: Duration.zero));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Sutura.void_,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in ZombieTypeId.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ChamferButton(label: zombieDefs[t]!.name, onPressed: () => _open(t)),
            ),
        ],
      ),
    ),
  );
}
