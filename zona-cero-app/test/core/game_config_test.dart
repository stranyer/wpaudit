import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/core/core.dart';
import 'package:zona_cero/core/utils.dart';

void main() {
  group('configuración (mismos valores que GAME_CONFIG de la web)', () {
    test('mundo e interacción', () {
      expect(gameConfig.worldSeed, 'zona-cero-v1');
      expect(gameConfig.interactionRadiusM, 40);
      expect(gameConfig.maxAccuracyBonusM, 15);
      expect(gameConfig.maxAccuracyForInteractionM, 80);
      expect(gameConfig.maxInteractionSpeedMps, 12);
      expect(gameConfig.speedLockMs, 30000);
      expect(gameConfig.spawnRadiusCells, 2);
      expect(gameConfig.zombieWindowMs, 600000);
      expect(gameConfig.supplyWindowMs, 1800000);
      expect(gameConfig.snapMaxDistanceM, 70);
      expect(gameConfig.shelterSafeRadiusM, 60);
      expect(gameConfig.infestedCellChance, 0.15);
      expect(gameConfig.spawn.worldSeed, 'zona-cero-v1');
      expect(gameConfig.interactionRules.interactionRadiusM, 40);
    });

    test('gps, demo, regeneración, xp y muerte', () {
      expect(gameConfig.gps.minIntervalMs, 1000);
      expect(gameConfig.gps.maximumAgeMs, 5000);
      expect(gameConfig.gps.timeoutMs, 20000);
      expect(gameConfig.demo.start, const LatLng(-34.60372, -58.38159));
      expect(gameConfig.demo.walkSpeedMps, 4.5);
      expect(gameConfig.demo.runMultiplier, 2.2);
      expect(gameConfig.regen.staminaPerMinute, 3);
      expect(gameConfig.regen.healthPerMinute, 1);
      expect(gameConfig.regen.healthPassiveCap, 0.5);
      expect(gameConfig.xp.perCellExplored, 15);
      expect(gameConfig.xp.per250mWalked, 5);
      expect(gameConfig.xp.craft, 8);
      expect(gameConfig.xp.donatePerUnit, 1);
      expect(gameConfig.death.healthRestoreRatio, 0.3);
      expect(gameConfig.death.staminaRestore, 20);
      expect(gameConfig.death.resourceLossRatio, 0.3);
      expect(gameConfig.tickMs, 5000);
      expect(gameConfig.saveDebounceMs, 1500);
    });

    test('balance', () {
      expect(GameStamina.attack, 6);
      expect(GameStamina.heavy, 16);
      expect(GameStamina.shoot, 2);
      expect(heavyMultiplier, 1.7);
      expect(maxLevel, 40);
      expect(maxShelterLevel, 5);
      expect(restCooldownMs, 600000);
    });
  });

  group('aritmética de JavaScript', () {
    test('Math.round', () {
      expect(jsRound(2.5), 3);
      expect(jsRound(-2.5), -2);
      expect(jsRound(-2.6), -3);
      expect(jsRound(0.49999999999999994), 0);
      expect(jsRound(31.5), 32);
      expect(jsRound(7), 7);
    });

    test('Math.imul y >>> 0', () {
      expect(imul32(0xffffffff, 5), 4294967291); // Math.imul(-1, 5) >>> 0
      expect(imul32(0x811c9dc5, 0x01000193), (0x811c9dc5 * 0x01000193) & 0xFFFFFFFF);
      expect(imul32(123456789, 987654321), 4227814277); // Math.imul(123456789, 987654321) >>> 0
      expect(toUint32(-1), 4294967295);
      expect(toUint32(4294967301), 5);
      expect(toUint32(-7.9), 4294967289);
      expect(toUint32(double.nan), 0);
    });

    test('números como texto', () {
      expect(jsNumToString(375.0), '375');
      expect(jsNumToString(-125.0), '-125');
      expect(jsNumToString(24.5), '24.5');
      expect(jsNumToString(-0.0), '0');
      expect(jsNumToString(12), '12');
    });
  });
}
