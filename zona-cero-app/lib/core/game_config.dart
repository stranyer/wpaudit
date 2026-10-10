// Configuración de juego y balance. Todo lo ajustable vive acá.
// A diferencia de la web, no se lee de variables de entorno: son valores `const`.
// Para otro mundo/flavor se puede crear otra instancia (`GameConfig(worldSeed: ...)`).

import 'interaction.dart';
import 'player.dart';
import 'smoothing.dart';
import 'spawns.dart';
import 'types.dart';

/// GPS: filtrado para ahorrar batería y evitar saltos.
class GpsSettings {
  const GpsSettings({
    this.minMoveM = 3,
    this.minIntervalMs = 1000,
    this.maximumAgeMs = 5000,
    this.timeoutMs = 20000,
    this.maxAcceptedAccuracyM = 150,
  });

  final double minMoveM;
  final int minIntervalMs;
  final int maximumAgeMs;
  final int timeoutMs;
  final double maxAcceptedAccuracyM;

  /// Configuración para [shouldEmit].
  ThrottleConfig get throttle =>
      ThrottleConfig(minMoveM: minMoveM, minIntervalMs: minIntervalMs, maxAcceptedAccuracyM: maxAcceptedAccuracyM);
}

/// Modo demo.
class DemoSettings {
  const DemoSettings({
    this.start = const LatLng(-34.60372, -58.38159), // Obelisco, Buenos Aires
    this.walkSpeedMps = 4.5, // un poco más rápido que caminar para que la demo sea ágil
    this.runMultiplier = 2.2,
  });

  final LatLng start;
  final double walkSpeedMps;
  final double runMultiplier;
}

/// XP por acciones de exploración.
class XpSettings {
  const XpSettings({this.perCellExplored = 15, this.per250mWalked = 5, this.craft = 8, this.donatePerUnit = 1});

  final int perCellExplored;
  final int per250mWalked;
  final int craft;
  final int donatePerUnit;
}

class GameConfig {
  const GameConfig({
    this.worldSeed = 'zona-cero-v1',
    this.interactionRadiusM = 40,
    this.maxAccuracyBonusM = 15,
    this.maxAccuracyForInteractionM = 80,
    this.maxInteractionSpeedMps = 12,
    this.speedLockMs = 30000,
    this.spawnRadiusCells = 2,
    this.zombieWindowMs = 10 * 60 * 1000,
    this.supplyWindowMs = 30 * 60 * 1000,
    this.snapMaxDistanceM = 70,
    this.shelterSafeRadiusM = 60,
    this.infestedCellChance = 0.15,
    this.gps = const GpsSettings(),
    this.demo = const DemoSettings(),
    this.regen = const RegenConfig(staminaPerMinute: 3, healthPerMinute: 1, healthPassiveCap: 0.5),
    this.xp = const XpSettings(),
    this.death = const DeathConfig(healthRestoreRatio: 0.3, staminaRestore: 20, resourceLossRatio: 0.3),
    this.tickMs = 5000,
    this.saveDebounceMs = 1500,
  });

  /// Semilla compartida del mundo: misma semilla = mismos spawns para todos.
  final String worldSeed;

  /// Radio (m) dentro del cual se puede interactuar con un punto.
  final double interactionRadiusM;

  /// Tolerancia extra por imprecisión del GPS (se suma al radio, con tope).
  final double maxAccuracyBonusM;

  /// Por encima de esta precisión (m) no se permiten interacciones.
  final double maxAccuracyForInteractionM;

  /// Velocidad máxima (m/s) para interactuar: ~43 km/h. Más rápido = vehículo.
  final double maxInteractionSpeedMps;

  /// Tiempo de bloqueo tras detectar velocidad excesiva.
  final int speedLockMs;

  /// Celdas alrededor del jugador donde se generan spawns (radio en celdas).
  final int spawnRadiusCells;

  /// Ventanas de tiempo de los spawns: al cambiar de ventana aparecen nuevos.
  final int zombieWindowMs;
  final int supplyWindowMs;

  /// Distancia máxima para mover un spawn a la calle/sendero más cercano.
  final double snapMaxDistanceM;

  /// Radio alrededor de refugios donde no aparecen zombies.
  final double shelterSafeRadiusM;

  /// Probabilidad de que una celda sea "zona infestada".
  final double infestedCellChance;

  final GpsSettings gps;
  final DemoSettings demo;

  /// Regeneración pasiva.
  final RegenConfig regen;
  final XpSettings xp;

  /// Penalización al caer en combate.
  final DeathConfig death;

  /// Frecuencia de autoguardado y ticks de juego.
  final int tickMs;
  final int saveDebounceMs;

  /// Parámetros para [generateWorld] / [generateCellSpawns].
  SpawnConfig get spawn => SpawnConfig(
        worldSeed: worldSeed,
        zombieWindowMs: zombieWindowMs,
        supplyWindowMs: supplyWindowMs,
        infestedCellChance: infestedCellChance,
      );

  /// Parámetros para [validateInteraction] / [isWithinReach].
  InteractionRules get interactionRules => InteractionRules(
        interactionRadiusM: interactionRadiusM,
        maxAccuracyBonusM: maxAccuracyBonusM,
        maxAccuracyForInteractionM: maxAccuracyForInteractionM,
      );
}

/// Configuración por defecto del juego (equivale a `GAME_CONFIG` de la web).
const GameConfig gameConfig = GameConfig();
