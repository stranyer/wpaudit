import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';

/// Estrategia simple de un jugador razonable.
CombatAction choose(CombatState s) {
  if (s.zombie.charging) return const Defend();
  final heal = usableItems(s).where((id) => id == ItemId.medicine || id == ItemId.medkit).firstOrNull;
  if (s.player.health < s.player.maxHealth * 0.3 && heal != null) return UseItem(heal);
  if (s.player.stamina >= 15 && s.zombie.health > 12) return const Heavy();
  return const Attack();
}

double winRate(PlayerState player, ZombieTypeId zombie, [int runs = 400]) {
  var wins = 0;
  for (var i = 0; i < runs; i++) {
    final rng = createRng('${zombie.key}:${player.level}:$i');
    var s = startCombat(spawnId: 'x', zombieType: zombie, player: player, rng: rng);
    for (var t = 0; t < 60 && s.status == CombatStatus.ongoing; t++) {
      s = resolveTurn(s, choose(s), rng);
    }
    if (s.status == CombatStatus.won) wins++;
  }
  return wins / runs;
}

void main() {
  group('balance del combate', () {
    final novato = createPlayer('p', 'Novato', 0);

    test('un novato a puño limpio le gana casi siempre a un Caminante', () {
      expect(winRate(novato, ZombieTypeId.walker), greaterThan(0.85));
    });

    test('un Bruto es una amenaza seria para un novato', () {
      expect(winRate(novato, ZombieTypeId.brute), lessThan(0.5));
    });

    test('con buen equipo y nivel, el Bruto se vuelve vencible', () {
      final veterano = equipItem(
        createPlayer('p', 'Vet', 0).copyWith(
          level: 6,
          health: 140,
          stamina: 120,
          inventory: {ItemId.machete: 1, ItemId.medicine: 2},
        ),
        ItemId.machete,
      )!;
      expect(winRate(veterano, ZombieTypeId.brute), greaterThan(0.7));
    });
  });
}
