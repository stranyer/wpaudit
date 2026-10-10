// Paridad exhaustiva con la implementación TypeScript original.
// `fixtures/ts_parity.json` se genera con `fixtures/gen_ts_parity.ts` corriendo el
// código web; acá se repiten las mismas operaciones en Dart y se comparan.

import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';

import 'helpers.dart';

const now = 1760000000000;
const obelisco = LatLng(-34.60372, -58.38159);

LatLng latLngOf(Object? json) => LatLng.fromJson(json as Map<String, dynamic>);

Inventory invOf(Object? json) => inventoryFromJson(json);

Map<String, dynamic> weaponMap(WeaponStats w) => {
      'damage': [w.damage.min, w.damage.max],
      'accuracy': w.accuracy,
      'critChance': w.critChance,
      'ammoPerShot': w.ammoPerShot,
    };

Map<String, dynamic> zombieMap(CombatZombie z) => {
      'typeId': z.typeId.key,
      'name': z.name,
      'level': z.level,
      'health': z.health,
      'maxHealth': z.maxHealth,
      'damage': [z.damage.min, z.damage.max],
      'accuracy': z.accuracy,
      'evasion': z.evasion,
      'charging': z.charging,
      'chargeIn': z.chargeIn,
      'stunned': z.stunned,
      'screamsLeft': z.screamsLeft,
    };

Map<String, dynamic> combatPlayerMap(CombatPlayer p) => {
      'health': p.health,
      'maxHealth': p.maxHealth,
      'stamina': p.stamina,
      'maxStamina': p.maxStamina,
      'defending': p.defending,
      'melee': weaponMap(p.melee),
      'meleeName': p.meleeName,
      'firearm': p.firearm == null ? null : weaponMap(p.firearm!),
      'firearmName': p.firearmName,
      'defense': p.defense,
    };

Map<String, dynamic> actionMap(CombatAction a) => {
      'type': a.type,
      if (a is UseItem) 'itemId': a.itemId.key,
    };

/// Misma estrategia que el generador TS (cubre todas las ramas del combate).
CombatAction choose(CombatState s, int t) {
  if (s.zombie.charging) return const Defend();
  final heal = usableItems(s).where((id) => id == ItemId.medicine || id == ItemId.medkit).firstOrNull;
  if (s.player.health < s.player.maxHealth * 0.3 && heal != null) return UseItem(heal);
  if (t == 2 && s.player.firearm != null) return const Shoot();
  if (t == 3) return const UseItem(ItemId.adrenaline);
  if (t % 5 == 4 && canShoot(s)) return const Shoot();
  if (t == 9) return const Flee();
  if (t % 6 == 5) return const Defend();
  if (s.player.stamina >= 15 && s.zombie.health > 12) return const Heavy();
  return const Attack();
}

Map<String, PlayerState> combatPlayers() {
  final novato = createPlayer('p', 'Novato', 0);
  var gunner = createPlayer('g', 'Pistolera', 0).copyWith(
    level: 4,
    health: 120,
    stamina: 90.5,
    factionId: FactionId.resistencia,
    inventory: {
      ItemId.pistol: 1,
      ItemId.ammo: 5,
      ItemId.medicine: 2,
      ItemId.pipe: 1,
      ItemId.ration: 1,
      ItemId.leatherJacket: 1,
    },
  );
  gunner = equipItem(gunner, ItemId.pipe)!;
  gunner = equipItem(gunner, ItemId.pistol)!;
  gunner = equipItem(gunner, ItemId.leatherJacket)!;
  var vet = createPlayer('v', 'Vet', 0).copyWith(
    level: 6,
    health: 77.25,
    stamina: 33,
    factionId: FactionId.nomades,
    inventory: {ItemId.machete: 1, ItemId.medicine: 2, ItemId.medkit: 1, ItemId.scrapVest: 1, ItemId.food: 3},
  );
  vet = equipItem(vet, ItemId.machete)!;
  vet = equipItem(vet, ItemId.scrapVest)!;
  return {'novato': novato, 'gunner': gunner, 'vet': vet};
}

void main() {
  final f = loadParityFixture();

  group('paridad RNG', () {
    test('secuencias para semillas de texto y numéricas', () {
      for (final entry in f['rng']['seeds'] as List) {
        final seed = entry['seed'] as Object;
        final r = createRng(seed);
        final values = [for (var i = 0; i < 10; i++) r.next()];
        expect(values, entry['values'], reason: 'semilla $seed');
      }
    });

    test('hashes', () {
      for (final entry in f['rng']['hashes'] as List) {
        expect(hashString(entry['input'] as String), entry['hash'], reason: entry['input'] as String);
      }
    });

    test('int / range / chance / pick / weighted', () {
      final h = f['rng']['helpers'] as Map<String, dynamic>;
      final r = createRng('helpers');
      expect([for (var i = 0; i < 20; i++) r.intRange(-3, 7)], h['ints']);
      expect([for (var i = 0; i < 10; i++) r.range(0.08, 0.92)], h['ranges']);
      expect([for (var i = 0; i < 10; i++) r.chance(0.4)], h['chances']);
      expect([for (var i = 0; i < 10; i++) r.pick(const ['a', 'b', 'c', 'd'])], h['picks']);
      expect([for (var i = 0; i < 20; i++) r.weighted(const [1, 2, 3, 4], (x) => x == 3 ? 0 : x * 1.5)], h['weighted']);
    });
  });

  group('paridad progresión', () {
    test('xpToNext 1..40', () {
      expect([for (var l = 1; l <= 40; l++) xpToNext(l)], f['xpToNext']);
    });

    test('addXp', () {
      for (final e in f['addXp'] as List) {
        final args = e['args'] as List;
        final r = addXp(args[0] as int, args[1] as int, args[2] as num);
        expect({'level': r.level, 'xp': r.xp, 'levelsGained': r.levelsGained}, e['result']);
      }
    });
  });

  group('paridad mundo', () {
    const testCfg = SpawnConfig(worldSeed: 'test', zombieWindowMs: 600000, supplyWindowMs: 1800000, infestedCellChance: 0.15);

    test('generateWorld con la configuración por defecto (25 celdas)', () {
      final w = generateWorld(obelisco, 2, now, gameConfig.spawn);
      final expected = f['world']['defaultCfg'] as Map<String, dynamic>;
      expect(w.spawns.map((s) => s.toJson()).toList(), expected['spawns']);
      expect(w.zones.map((z) => z.toJson()).toList(), expected['zones']);
      // Ida y vuelta por JSON.
      expect((expected['spawns'] as List).map((j) => Spawn.fromJson(j as Map<String, dynamic>)).toList(), w.spawns);
      expect((expected['zones'] as List).map((j) => Zone.fromJson(j as Map<String, dynamic>)).toList(), w.zones);
    });

    test('generateWorld con otra semilla y hora', () {
      final w = generateWorld(obelisco, 1, now + 3600000, testCfg);
      final expected = f['world']['testCfg'] as Map<String, dynamic>;
      expect(w.spawns.map((s) => s.toJson()).toList(), expected['spawns']);
      expect(w.zones.map((z) => z.toJson()).toList(), expected['zones']);
    });

    test('generateCellSpawns en distintas ventanas de tiempo', () {
      for (final e in f['world']['cellAtTimes'] as List) {
        final spawns = generateCellSpawns(cellOf(obelisco), e['now'] as int, gameConfig.spawn);
        expect(spawns.map((s) => s.toJson()).toList(), e['spawns'], reason: 'now=${e['now']}');
      }
    });

    test('amenaza de celdas', () {
      for (final e in f['world']['threats'] as List) {
        final c = CellCoord(e['cell']['cx'] as int, e['cell']['cy'] as int);
        expect(cellThreat(c, now, gameConfig.spawn).key, e['threat']);
      }
    });
  });

  group('paridad botín', () {
    test('rollLoot y rollSupplyLoot', () {
      expect(inventoryToJson(rollLoot(supplyDefs[SupplyTypeId.car]!.loot, createRng('x'))), f['loot']['carX']);
      for (final e in f['loot']['supplies'] as List) {
        final type = SupplyTypeId.fromKey(e['type'] as String);
        final loot = rollSupplyLoot(supplyDefs[type]!, createRng('${type.key}:${e['seed']}'),
            multiplier: e['mult'] as num);
        expect(inventoryToJson(loot), e['loot'], reason: '${type.key}:${e['seed']}');
      }
    });
  });

  group('paridad combate', () {
    final players = combatPlayers();
    final fights = f['combat'] as List;

    test('hay combates ganados, perdidos y con huida en el fixture', () {
      final statuses = fights.map((c) => c['final']['status']).toSet();
      expect(statuses, containsAll(['won', 'lost', 'fled']));
    });

    for (final c in fights) {
      final name = '${c['player']} vs ${c['zombie']} #${c['seed']}';
      test(name, () {
        final player = players[c['player']]!;
        final zombie = ZombieTypeId.fromKey(c['zombie'] as String);
        final rng = createRng('${zombie.key}:${c['player']}:${c['seed']}');
        var s = startCombat(spawnId: 'sp${c['seed']}', zombieType: zombie, player: player, rng: rng);

        final start = c['start'] as Map<String, dynamic>;
        expect(zombieMap(s.zombie), start['zombie']);
        expect(combatPlayerMap(s.player), start['player']);
        expect(inventoryToJson(s.available), start['available']);
        expect(s.xpMultiplier, start['xpMultiplier']);

        final actions = <CombatAction>[];
        for (var t = 0; t < 60 && s.status == CombatStatus.ongoing; t++) {
          final a = choose(s, t);
          actions.add(a);
          s = resolveTurn(s, a, rng);
        }
        expect(actions.map(actionMap).toList(), c['actions']);
        expect(s.log.map((e) => e.toJson()).toList(), c['log']);
        expect(s.log.map((e) => describeEvent(e, s)).toList(), c['texts']);
        // Los eventos se pueden reconstruir desde el JSON de la web.
        expect(
          (c['log'] as List).map((j) => CombatEvent.fromJson(j as Map<String, dynamic>).toJson()).toList(),
          c['log'],
        );

        final fin = c['final'] as Map<String, dynamic>;
        expect(s.status.key, fin['status']);
        expect(s.turn, fin['turn']);
        expect(zombieMap(s.zombie), fin['zombie']);
        expect(combatPlayerMap(s.player), fin['player']);
        expect(inventoryToJson(s.consumed), fin['consumed']);

        if (c['reward'] != null) {
          final r = combatReward(s, createRng('reward:${zombie.key}:${c['seed']}'));
          expect({'xp': r.xp, 'items': inventoryToJson(r.items)}, c['reward']);
        } else {
          expect(s.status, isNot(CombatStatus.won));
        }
      });
    }
  });

  group('paridad jugador (forma JSON de la partida)', () {
    test('las operaciones producen el mismo JSON que la web', () {
      final steps = (f['player'] as List).cast<Map<String, dynamic>>();
      final got = <PlayerState>[];
      var p = createPlayer('p1', 'Ana', now).copyWith(factionId: FactionId.nomades, stamina: 10, health: 30);
      got.add(p);
      p = applyRegen(p, now + 37 * 60000 + 12345, gameConfig.regen);
      got.add(p);
      p = grantXp(p, 95).player;
      got.add(p);
      p = giveItems(p, {ItemId.machete: 1, ItemId.metal: 5, ItemId.ammo: 200}).player;
      got.add(p);
      p = equipItem(p, ItemId.machete)!;
      got.add(p);
      p = consumeItem(p, ItemId.food)!;
      got.add(p);
      p = applyDeathPenalty(p, gameConfig.death).player;
      got.add(p);
      p = restAtShelter(p, 3, now + 3600000).player;
      got.add(p);
      p = takeItems(p, {ItemId.machete: 1})!;
      got.add(p);
      p = p.copyWith(
        stats: p.stats.copyWith(zombiesKilled: {ZombieTypeId.walker: 3, ZombieTypeId.brute: 1}, distanceWalkedM: 1234.56),
      );
      p = applyRegen(p, now + 9 * 3600000, gameConfig.regen);
      got.add(p);

      expect(got, hasLength(steps.length));
      for (var i = 0; i < steps.length; i++) {
        expect(got[i].toJson(), steps[i], reason: 'paso $i');
        // Una partida guardada por la web se lee sin pérdidas.
        expect(PlayerState.fromJson(steps[i]), got[i], reason: 'fromJson paso $i');
      }
    });
  });

  group('paridad refugios', () {
    const base = Shelter(
      id: 'sh1',
      name: 'Refugio',
      ownerId: 'p1',
      ownerName: 'Ana',
      factionId: FactionId.guardia,
      level: 1,
      position: LatLng(-34.6, -58.38),
      progress: {},
      contributions: [],
      createdAt: now,
    );

    test('donaciones, subidas de nivel y ranking de aportes', () {
      var s = base;
      for (final step in (f['shelter']['steps'] as List).cast<Map<String, dynamic>>()) {
        final offered = <ItemId, num>{
          for (final e in (step['offered'] as Map<String, dynamic>).entries) ItemId.fromKey(e.key): e.value as num,
        };
        final contributor = (f['shelter']['steps'] as List).indexOf(step);
        const who = [('p1', 'Ana'), ('p2', 'Beto'), ('p3', 'Caro'), ('p2', 'Beto R.'), ('p3', 'Caro'), ('p1', 'Ana')];
        final (id, name) = who[contributor];
        final r = applyDonation(s, id, name, offered);
        final outcome = step['outcome'] as Map<String, dynamic>;
        expect(inventoryToJson(r.accepted), outcome['accepted']);
        expect(r.acceptedTotal, outcome['acceptedTotal']);
        expect(r.leveledUp, outcome['leveledUp']);
        expect(upgradeProgress(r.shelter), outcome['progress']);
        expect(r.shelter.toJson(), step['shelter']);
        expect(Shelter.fromJson(step['shelter'] as Map<String, dynamic>), r.shelter);
        s = r.shelter;
      }
    });

    test('ataques de hordas', () {
      final rng = createRng('horda');
      for (final h in (f['shelter']['hordes'] as List).cast<Map<String, dynamic>>()) {
        final level = h['level'] as int;
        final sh = base.copyWith(id: 'sh', level: level);
        final attack = planHordeAttack(sh, now, rng);
        final outcome = resolveHordeAttack(sh, attack, level * 3, rng);
        expect({'shelterId': attack.shelterId, 'strength': attack.strength, 'startsAt': attack.startsAt}, h['attack']);
        expect(
          {'defended': outcome.defended, 'progressLossRatio': outcome.progressLossRatio, 'defenseRoll': outcome.defenseRoll},
          h['outcome'],
        );
      }
    });
  });

  group('paridad geo, privacidad y suavizado', () {
    final pts = const [
      obelisco,
      LatLng(-34.6083, -58.3712),
      LatLng(40.4168, -3.7038),
      LatLng(0.0001, 179.9999),
      LatLng(-0.5, -179.99),
    ];
    final g = f['geo'] as Map<String, dynamic>;

    test('haversine y rumbo', () {
      for (var i = 0; i < pts.length; i++) {
        for (var j = 0; j < pts.length; j++) {
          // Las funciones trigonométricas pueden diferir en el último ulp entre libm y V8.
          final expectedD = g['haversine'][i][j] as num;
          expect(haversineM(pts[i], pts[j]), closeTo(expectedD, 1e-6 + expectedD * 1e-12));
          expect(bearingDeg(pts[i], pts[j]), closeTo(g['bearing'][i][j] as num, 1e-9));
        }
      }
    });

    test('offsetM y normalizeLng', () {
      for (var i = 0; i < pts.length; i++) {
        final a = offsetM(pts[i], 123.4, -567.8);
        final b = offsetM(pts[i], -1000, 2500);
        final ea = latLngOf(g['offset'][i][0]);
        final eb = latLngOf(g['offset'][i][1]);
        expect(a.lat, closeTo(ea.lat, 1e-12));
        expect(a.lng, closeTo(ea.lng, 1e-12));
        expect(b.lat, closeTo(eb.lat, 1e-12));
        expect(b.lng, closeTo(eb.lng, 1e-12));
      }
      for (final e in g['normalizeLng'] as List) {
        expect(normalizeLng((e[0] as num).toDouble()), e[1], reason: 'lng ${e[0]}');
      }
    });

    test('formatDistance', () {
      for (final e in g['formatDistance'] as List) {
        expect(formatDistance(e[0] as num), e[1]);
      }
    });

    test('snapToSegments', () {
      final a = offsetM(obelisco, 0, -100);
      final b = offsetM(obelisco, 0, 100);
      final r = snapToSegments(offsetM(obelisco, 30, 10), [(a, b)], 50)!;
      final e = latLngOf(g['snap']['position']);
      expect(r.position.lat, closeTo(e.lat, 1e-12));
      expect(r.position.lng, closeTo(e.lng, 1e-12));
      expect(r.distanceM, closeTo(g['snap']['distanceM'] as num, 1e-9));
    });

    test('fuzzPosition y etiquetas de distancia', () {
      for (final e in (f['privacy']['fuzz'] as List).cast<Map<String, dynamic>>()) {
        final out = fuzzPosition(latLngOf(e['p']), e['salt'] as String, gridM: e['gridM'] as num);
        final expected = latLngOf(e['out']);
        expect(out.lat, closeTo(expected.lat, 1e-9), reason: '$e');
        expect(out.lng, closeTo(expected.lng, 1e-9), reason: '$e');
      }
      for (final e in f['privacy']['labels'] as List) {
        expect(approximateDistanceLabel(e[0] as num), e[1]);
      }
    });

    test('GpsSmoother', () {
      final s = GpsSmoother();
      for (final e in (f['smoothing'] as List).cast<Map<String, dynamic>>()) {
        final input = e['input'] as Map<String, dynamic>;
        final r = s.process(latLngOf(input['p']), input['acc'] as num, input['t'] as int);
        final expected = latLngOf(e['out']['position']);
        expect(r.position.lat, closeTo(expected.lat, 1e-12));
        expect(r.position.lng, closeTo(expected.lng, 1e-12));
        expect(r.accuracyM, closeTo(e['out']['accuracyM'] as num, 1e-9));
      }
    });
  });
}
