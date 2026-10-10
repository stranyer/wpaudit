/// Motor de Zona Cero: lógica pura del juego (sin Flutter), portada de la
/// versión web (TypeScript) con el mismo comportamiento y balance.
///
/// Ojo: `package:maplibre_gl` también exporta `LatLng`. Si importás ambos, usá
/// un prefijo (`import 'package:maplibre_gl/maplibre_gl.dart' as ml;`) o `hide`.
library;

export 'balance.dart';
export 'combat.dart';
export 'crafting.dart';
export 'factions.dart';
export 'game_config.dart';
export 'geo.dart';
export 'interaction.dart';
export 'inventory.dart';
export 'items.dart';
export 'loot.dart';
export 'placement.dart';
export 'player.dart';
export 'privacy.dart';
export 'progression.dart';
export 'rng.dart';
export 'shelter.dart';
export 'smoothing.dart';
export 'spawns.dart';
export 'supplies.dart';
export 'types.dart';
export 'utils.dart' show jsNumToString, jsRound;
export 'zombies.dart';
