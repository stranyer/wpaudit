// Contrato entre el escenario del combate y quien dibuja a la criatura.
//
// Hoy la criatura es un títere de malla sobre un recorte HD
// ([PuppetCreatureView]); mañana puede ser un modelo 3D. El juego (cámara,
// efectos, puntería) y el HUD solo hablan con esta interfaz: reemplazar el
// renderizador no toca ni el flujo del turno ni la pantalla.

import 'dart:math' as math;
import 'dart:ui' show Canvas, Color, Offset, Rect;

import 'stage_layout.dart';

/// Animaciones que la escena sabe pedir.
enum ZombieAnim { idle, attack, hit, death, chargePrepare, charge, scream }

/// Luz de la placa de fondo: cómo se ilumina la criatura para "pertenecer" a
/// la calle (tinte frío/cálido, luz de borde y de qué lado viene).
class PlateLook {
  const PlateLook({
    this.shadowTint = const Color(0xFF7A8599),
    this.lightTint = const Color(0xFFC9D1E0),
    this.rim = const Color(0xFFFF3324),
    this.rimSide = 1,
    this.rimBase = 0.22,
    this.rimBeacon = 0.55,
    this.fill = const Color(0xFFFFB45E),
    this.fillSide = -1,
    this.fillAmount = 0,
    this.emergency = true,
  });

  /// Tinte multiplicativo de las piernas (sombra) y del torso (luz).
  final Color shadowTint;
  final Color lightTint;

  /// Luz de borde (aditiva) y lado del que entra (−1 izquierda, 1 derecha).
  final Color rim;
  final double rimSide;
  final double rimBase;

  /// Cuánto late el borde con la baliza de emergencia.
  final double rimBeacon;

  /// Luz de relleno cálida (faroles de sodio) y su lado.
  final Color fill;
  final double fillSide;
  final double fillAmount;

  /// Baliza roja de emergencia en pantalla.
  final bool emergency;
}

/// Lo que la escena le ofrece a la criatura en cada cuadro.
abstract interface class CreatureStage {
  /// Reloj de la escena (s).
  double get time;

  /// Encuadre actual (null hasta el primer `resize`).
  StageLayout? get layout;

  /// El Bruto tiene una embestida preparada.
  bool get charging;

  /// Desde dónde (y, mundo) el HUD inferior tapa la escena.
  double get hudTop;

  /// Luz de la placa.
  PlateLook get look;

  /// Baliza de emergencia (0…1).
  double get beacon;

  /// Luz frontal momentánea desde el lado del jugador (fogonazo), 0…1.
  double get flashLight;
}

/// Renderizador intercambiable de la criatura. Coordenadas de "mundo" = las
/// de pantalla antes de la cámara (respiración, temblor y zoom los aplica la
/// escena alrededor de [render]).
abstract class CreatureView {
  /// Ya tiene una pose (geometría válida para puntería y efectos).
  bool get hasPose;

  /// Murió (las reacciones se ignoran).
  bool get dead;

  /// Caja de la criatura en la pose actual (mundo).
  Rect get bodyWorld;

  /// Caja de la cabeza en la pose actual (mundo; vacía si no se conoce).
  Rect get headWorld;

  /// 0…1: cuánto se vino encima de la cámara (embestida).
  double get lunge;

  /// 0…1: disolución al morir (para la ceniza).
  double get dissolve;

  /// Punto (mundo) visible al azar dentro de la franja de altura pedida
  /// (0 pies … 1 coronilla) y a no más de `maxSide` del eje (fracción de media caja).
  Offset? randomPoint(math.Random rnd, {required double minH, required double maxH, required double maxSide});

  /// Sostiene la pose agachada mientras hay una embestida preparada.
  set holdCrouch(bool value);

  // --- Ciclo -----------------------------------------------------------------

  void update(double dt, CreatureStage stage);
  void render(Canvas canvas, CreatureStage stage);
  void dispose();

  // --- Eventos (devuelven la duración en s cuando corresponde) ---------------

  /// Vuelve al reposo (cancela la animación en curso).
  void idle();

  /// Zarpazo/mordida: se abalanza hacia la cámara.
  double attack();

  /// Se agacha para embestir.
  double chargePrepare();

  /// Embestida.
  double charge();

  /// Grito (pide refuerzos).
  double scream();

  /// Muere (cae y se disuelve).
  double die();

  /// El jugador escapa: la criatura queda atrás.
  void flee();

  /// Recibe un impacto en `at` (mundo). `strong` = golpe pesado o crítico;
  /// `lethal` = es el golpe que la mata (sin retroceso: sigue la muerte).
  void hit(Offset at, {bool strong = false, bool crit = false, bool headshot = false, bool lethal = false});

  // --- Tiempos -----------------------------------------------------------------

  /// Segundos hasta el impacto/pico de `a` (para sincronizar el daño).
  double keyTime(ZombieAnim a);

  /// Duración total de `a`.
  double duration(ZombieAnim a);
}
