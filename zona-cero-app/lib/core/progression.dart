// Progresión: experiencia, niveles y atributos derivados.

import 'dart:math' as math;

import 'utils.dart';

const int maxLevel = 40;

/// XP necesaria para pasar del nivel `level` al siguiente.
int xpToNext(int level) => jsRound(80 + 60 * math.pow(level - 1, 1.3));

int maxHealthForLevel(int level) => 100 + 8 * (level - 1);

int maxStaminaForLevel(int level) => 100 + 4 * (level - 1);

class XpResult {
  const XpResult({required this.level, required this.xp, required this.levelsGained});
  final int level;
  final int xp;
  final int levelsGained;

  @override
  bool operator ==(Object other) =>
      other is XpResult && other.level == level && other.xp == xp && other.levelsGained == levelsGained;

  @override
  int get hashCode => Object.hash(level, xp, levelsGained);

  @override
  String toString() => 'XpResult(level: $level, xp: $xp, levelsGained: $levelsGained)';
}

/// Suma XP y resuelve las subidas de nivel (la XP guardada es la del nivel actual).
XpResult addXp(int level, int xp, num amount) {
  var lvl = level;
  var cur = xp + math.max<int>(0, jsRound(amount));
  var gained = 0;
  while (lvl < maxLevel && cur >= xpToNext(lvl)) {
    cur -= xpToNext(lvl);
    lvl++;
    gained++;
  }
  if (lvl >= maxLevel) cur = math.min(cur, xpToNext(maxLevel));
  return XpResult(level: lvl, xp: cur, levelsGained: gained);
}

/// Título de rango según nivel.
String rankTitle(int level) {
  if (level >= 30) return 'Leyenda de la Zona';
  if (level >= 20) return 'Comandante';
  if (level >= 12) return 'Veterano';
  if (level >= 7) return 'Saqueador';
  if (level >= 3) return 'Sobreviviente';
  return 'Novato';
}
