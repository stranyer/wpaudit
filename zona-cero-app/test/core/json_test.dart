// Serialización: misma forma JSON que los objetos de la versión web.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';

/// Ida y vuelta por texto JSON real (como al guardar en disco o Supabase).
Map<String, dynamic> viaText(Map<String, dynamic> json) => jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

void main() {
  group('enums con claves estables', () {
    test('claves de la web', () {
      expect(ItemId.nailBat.key, 'nail_bat');
      expect(ItemId.fireAxe.key, 'fire_axe');
      expect(ItemId.leatherJacket.key, 'leather_jacket');
      expect(ItemId.scrapVest.key, 'scrap_vest');
      expect(ItemId.riotArmor.key, 'riot_armor');
      expect(ZombieAbility.doubleStrike.key, 'double_strike');
      expect(InteractionRejection.outOfRange.key, 'out_of_range');
      expect(ItemId.fromKey('nail_bat'), ItemId.nailBat);
      expect(ItemId.tryFromKey('bazooka'), isNull);
      expect(() => ItemId.fromKey('bazooka'), throwsArgumentError);
    });

    test('fromKey(key) es la inversa de key para todos los enums', () {
      void check<T extends KeyedEnum>(List<T> values, T Function(String) fromKey) {
        for (final v in values) {
          expect(fromKey(v.key), v);
        }
        expect(values.map((v) => v.key).toSet(), hasLength(values.length));
      }

      check(ItemId.values, ItemId.fromKey);
      check(Rarity.values, Rarity.fromKey);
      check(ItemCategory.values, ItemCategory.fromKey);
      check(ZombieTypeId.values, ZombieTypeId.fromKey);
      check(ZombieAbility.values, ZombieAbility.fromKey);
      check(SupplyTypeId.values, SupplyTypeId.fromKey);
      check(FactionId.values, FactionId.fromKey);
      check(EquipmentSlot.values, EquipmentSlot.fromKey);
      check(CombatStatus.values, CombatStatus.fromKey);
      check(InteractionAction.values, InteractionAction.fromKey);
      check(InteractionRejection.values, InteractionRejection.fromKey);
      check(ZoneThreat.values, ZoneThreat.fromKey);
      check(PlacementState.values, PlacementState.fromKey);
      check(CraftBlock.values, CraftBlock.fromKey);
    });

    test('todos los objetos, zombies y suministros tienen definición', () {
      for (final id in ItemId.values) {
        expect(itemDefs[id]!.id, id);
      }
      for (final id in ZombieTypeId.values) {
        expect(zombieDefs[id]!.id, id);
      }
      for (final id in SupplyTypeId.values) {
        expect(supplyDefs[id]!.id, id);
      }
      expect(resourceIds.every(isResource), isTrue);
      expect(isResource(ItemId.medkit), isFalse);
      expect(ItemId.machete.def.name, 'Machete');
      expect(Rarity.epic.label, 'Épico');
    });
  });

  group('PlayerState', () {
    test('forma JSON de la web', () {
      final p = equipItem(
        createPlayer('p1', 'Ana', 1000).copyWith(inventory: {ItemId.nailBat: 1, ItemId.food: 2}),
        ItemId.nailBat,
      )!;
      final json = p.toJson();
      expect(json.keys, [
        'id',
        'name',
        'level',
        'xp',
        'health',
        'stamina',
        'inventory',
        'equipment',
        'stats',
        'factionId',
        'lastRegenAt',
        'lastRestAt',
        'createdAt',
      ]);
      expect(json['inventory'], {'nail_bat': 1, 'food': 2});
      expect(json['equipment'], {'melee': 'nail_bat', 'firearm': null, 'armor': null});
      expect(json['health'], isA<int>()); // 100, no 100.0
      expect((json['stats'] as Map)['zombiesKilled'], <String, int>{});
      expect(json['factionId'], isNull);
      expect(PlayerState.fromJson(viaText(json)), p);
    });

    test('lectura tolerante de partidas viejas o incompletas', () {
      final p = PlayerState.fromJson({
        'id': 'x',
        'name': 'Viejo',
        'level': '3',
        'health': 55.5,
        'inventory': {'food': 3, 'bazooka': 1, 'ammo': '7'},
        'equipment': {'melee': 'bazooka'},
        'stats': {'deaths': 2, 'zombiesKilled': {'walker': 4, 'dragon': 1}},
        'factionId': 'piratas',
      }, now: 5000);
      expect(p.level, 3);
      expect(p.xp, 0);
      expect(p.health, 55.5);
      expect(p.stamina, 100);
      expect(p.inventory, {ItemId.food: 3, ItemId.ammo: 7});
      expect(p.equipment, Equipment.empty);
      expect(p.stats.deaths, 2);
      expect(p.stats.zombiesKilled, {ZombieTypeId.walker: 4});
      expect(p.factionId, isNull);
      expect(p.lastRegenAt, 5000);
      expect(p.createdAt, 5000);
      // Sin inventario se usa el inicial.
      expect(PlayerState.fromJson({'name': 'Nuevo'}, now: 0).inventory, starterInventory);
    });

    test('copyWith puede borrar campos anulables', () {
      final p = createPlayer('p', 'T', 0).copyWith(factionId: FactionId.guardia);
      expect(p.factionId, FactionId.guardia);
      expect(p.copyWith().factionId, FactionId.guardia);
      expect(p.copyWith(factionId: null).factionId, isNull);
      const eq = Equipment(melee: ItemId.pipe, armor: ItemId.scrapVest);
      expect(eq.copyWith(melee: null), const Equipment(armor: ItemId.scrapVest));
      expect(eq.withSlot(EquipmentSlot.firearm, ItemId.pistol)[EquipmentSlot.firearm], ItemId.pistol);
    });

    test('getters derivados', () {
      final p = createPlayer('p', 'T', 0).copyWith(level: 3);
      expect(p.maxHealth, 116);
      expect(p.maxStamina, 108);
      expect(p.capacity, 100);
      expect(createPlayer('p', 'T', 0).carried, 7);
    });
  });

  group('spawns y zonas', () {
    test('forma JSON', () {
      const z = ZombieSpawn(
        id: 'z:1_2:3:0',
        cellId: '1_2',
        position: LatLng(-34.5, -58.25),
        zombieType: ZombieTypeId.brute,
        expiresAt: 600000,
        placement: PlacementState.raw,
      );
      expect(z.toJson(), {
        'kind': 'zombie',
        'id': 'z:1_2:3:0',
        'cellId': '1_2',
        'position': {'lat': -34.5, 'lng': -58.25},
        'zombieType': 'brute',
        'expiresAt': 600000,
        'placement': 'raw',
      });
      expect(Spawn.fromJson(viaText(z.toJson())), z);
      const s = SupplySpawn(
        id: 's:1_2:1:0',
        cellId: '1_2',
        position: LatLng(1, 2),
        supplyType: SupplyTypeId.military,
        expiresAt: 1,
        placement: PlacementState.snapped,
      );
      expect(s.toJson()['supplyType'], 'military');
      expect(Spawn.fromJson(viaText(s.toJson())), s);
      expect(() => Spawn.fromJson({'kind': 'ovni'}), throwsFormatException);
    });

    test('zonas', () {
      final zone = Zone(cellId: '1_2', threat: ZoneThreat.infested, bounds: cellBounds(const CellCoord(1, 2)));
      final json = viaText(zone.toJson());
      expect(json['bounds'], hasLength(2));
      expect(Zone.fromJson(json), zone);
    });
  });

  group('comunidad e interacciones', () {
    test('Shelter', () {
      const sh = Shelter(
        id: 'sh',
        name: 'Base',
        ownerId: 'p1',
        ownerName: 'Ana',
        factionId: FactionId.nomades,
        level: 2,
        position: LatLng(-34.6, -58.4),
        progress: {ItemId.wood: 5},
        contributions: [ShelterContribution(playerId: 'p1', playerName: 'Ana', amount: 12)],
        createdAt: 99,
      );
      final json = sh.toJson();
      expect(json['progress'], {'wood': 5});
      expect(json['contributions'], [
        {'playerId': 'p1', 'playerName': 'Ana', 'amount': 12},
      ]);
      expect(Shelter.fromJson(viaText(json)), sh);
    });

    test('Faction, PublicSurvivor y LeaderboardEntry', () {
      final f = factionDefs[FactionId.guardia]!.toFaction(members: 3, totalContribution: 40);
      expect(Faction.fromJson(viaText(f.toJson())), f);
      expect(f.toJson()['color'], '#6f8a4a');

      const ps = PublicSurvivor(
        id: 'u',
        name: 'Beto',
        level: 4,
        factionId: null,
        approxPosition: LatLng(-34.61, -58.39),
        lastSeenAt: 123,
      );
      expect(PublicSurvivor.fromJson(viaText(ps.toJson())), ps);
      expect(ps.toJson().keys, ['id', 'name', 'level', 'factionId', 'approxPosition', 'lastSeenAt']);

      const le = LeaderboardEntry(
        playerId: 'u',
        playerName: 'Beto',
        factionId: FactionId.resistencia,
        level: 4,
        contribution: 77,
      );
      expect(LeaderboardEntry.fromJson(viaText(le.toJson())), le);
    });

    test('InteractionRequest e InteractionResult', () {
      const req = InteractionRequest(
        playerId: 'p',
        action: InteractionAction.scavenge,
        targetId: 's:1_1:0:0',
        targetPosition: LatLng(-34.6, -58.38),
        playerPosition: LatLng(-34.6001, -58.38),
        accuracyM: 5,
        timestamp: 1000,
      );
      expect(req.toJson().containsKey('targetExpiresAt'), isFalse);
      expect(req.toJson()['accuracyM'], 5);
      expect(InteractionRequest.fromJson(viaText(req.toJson())), req);
      final withExp = req.copyWith(targetExpiresAt: 2000);
      expect(withExp.toJson()['targetExpiresAt'], 2000);
      expect(InteractionRequest.fromJson(viaText(withExp.toJson())), withExp);
      expect(withExp.copyWith(targetExpiresAt: null).targetExpiresAt, isNull);

      const ok = InteractionResult(ok: true, distanceM: 12.5);
      expect(ok.toJson(), {'ok': true, 'distanceM': 12.5});
      const ko = InteractionResult(ok: false, reason: InteractionRejection.tooFast, distanceM: 3);
      expect(ko.toJson(), {'ok': false, 'reason': 'too_fast', 'distanceM': 3});
      expect(InteractionResult.fromJson(viaText(ko.toJson())), ko);
    });
  });

  group('eventos de combate', () {
    test('ida y vuelta de todos los tipos', () {
      const events = <CombatEvent>[
        PlayerHit(damage: 7, crit: true, ranged: false, stunBonus: false),
        PlayerMiss(ranged: true),
        Exhausted(),
        NoAmmo(),
        DefendEvent(stamina: 12),
        Heal(itemId: ItemId.medkit, health: 24.5, stamina: 0),
        FleeSuccess(),
        FleeFail(),
        ZombieHit(damage: 5, blocked: 2, charged: true),
        ZombieMiss(charged: false),
        ZombieChargePrepare(),
        ZombieStunned(),
        ZombieScream(healed: 9),
        ToxicBurst(damage: 2.5),
        ZombieKilled(),
        PlayerDown(),
      ];
      expect(events.map((e) => e.kind).toSet(), hasLength(16));
      for (final e in events) {
        final json = viaText(e.toJson());
        expect(json['kind'], e.kind);
        expect(CombatEvent.fromJson(json).toJson(), json);
      }
      expect(events[5].toJson(), {'kind': 'heal', 'itemId': 'medkit', 'health': 24.5, 'stamina': 0});
    });

    test('textos con decimales como en la web', () {
      final s = startCombat(
        spawnId: 's',
        zombieType: ZombieTypeId.walker,
        player: createPlayer('p', 'T', 0),
        rng: createRng(1),
      );
      expect(describeEvent(const Heal(itemId: ItemId.medicine, health: 24.5, stamina: 0), s),
          'Usás Medicamentos: +24.5 salud.');
      expect(describeEvent(const Heal(itemId: ItemId.food, health: 0, stamina: 0), s), 'Usás Comida enlatada: sin efecto.');
      expect(describeEvent(const DefendEvent(stamina: 12), s), 'Te cubrís y recuperás el aliento (+12 resistencia).');
      expect(describeEvent(const ZombieHit(damage: 4, blocked: 2, charged: false), s), 'El Caminante te muerde. −4 (bloqueado 2)');
    });
  });
}
