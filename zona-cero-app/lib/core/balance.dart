// Constantes de balance usadas por el motor (sin dependencias de entorno).

/// Costos de resistencia por acción.
abstract final class GameStamina {
  static const int attack = 6;
  static const int heavy = 16;
  static const int shoot = 2;
}

/// Multiplicador de daño del golpe fuerte.
const double heavyMultiplier = 1.7;

// --- Minijuego de precisión (extensión de la app Flutter) -------------------

/// Bonificación de acierto por precisión: `(precision - 0.5) * precisionAccuracyFactor`.
const double precisionAccuracyFactor = 0.3;

/// A partir de esta precisión el impacto es crítico garantizado ("headshot").
const double precisionCritThreshold = 0.9;
