// Geometría del escenario: dónde va la placa de fondo (cubre la vista con el
// horizonte a ~40 % de la altura) y dónde y a qué escala se para la criatura.
// Lógica pura para poder testearla.

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import '../core/types.dart';
import 'cutout_rig.dart';

/// Encuadre de cada criatura (fracciones de la altura de la vista).
class PlacementProfile {
  const PlacementProfile({this.heightFrac = 0.5, this.feetFrac = 0.755, this.maxWidthFrac = 1.0});

  /// Alto del cuerpo en pantalla.
  final double heightFrac;

  /// Altura de los pies.
  final double feetFrac;

  /// Tope de ancho (fracción del ancho de la vista) para siluetas anchas.
  final double maxWidthFrac;
}

// Como en la referencia: cuerpo entero visible, con los pies apoyados en la
// calle justo encima de los paneles inferiores (~75 % de la altura).
const Map<ZombieTypeId, PlacementProfile> placementProfiles = {
  ZombieTypeId.walker: PlacementProfile(heightFrac: 0.5),
  ZombieTypeId.runner: PlacementProfile(heightFrac: 0.44, maxWidthFrac: 0.98),
  ZombieTypeId.bloater: PlacementProfile(heightFrac: 0.5, maxWidthFrac: 0.96),
  ZombieTypeId.screamer: PlacementProfile(heightFrac: 0.53),
  ZombieTypeId.brute: PlacementProfile(heightFrac: 0.52, feetFrac: 0.765, maxWidthFrac: 1.0),
};

class StageLayout {
  const StageLayout({
    required this.view,
    required this.plateRect,
    required this.scale,
    required this.feet,
    required this.rigFeet,
    required this.body,
    required this.head,
  });

  /// Calcula el encuadre. `plateHorizon` = altura del punto de fuga en la placa
  /// (fracción); `horizonAt` = dónde se lo quiere en pantalla. `plateCover` =
  /// fracción de la altura de la vista que la placa cubre como mínimo (con
  /// menos de 1 se ve más ancho de la placa; el hueco de abajo se completa con
  /// el piso espejado). `plateFocusX` = punto de la placa que se intenta centrar.
  factory StageLayout.compute({
    required Size view,
    required Size plate,
    required CutoutRig rig,
    PlacementProfile profile = const PlacementProfile(),
    double plateHorizon = 0.39,
    double horizonAt = 0.40,
    double plateCover = 1,
    double plateFocusX = 0.5,
  }) {
    if (view.isEmpty || plate.isEmpty || rig.body.isEmpty) {
      return StageLayout(view: view, plateRect: Offset.zero & view, scale: 1, feet: Offset.zero, rigFeet: rig.feet, body: Rect.zero, head: Rect.zero);
    }
    // Placa: cubre el ancho y `plateCover` de la altura; el horizonte lo más
    // cerca posible de `horizonAt` sin dejar huecos arriba ni a los costados.
    final s = math.max(view.width / plate.width, view.height * plateCover.clamp(0.3, 1.0) / plate.height);
    final pw = plate.width * s;
    final ph = plate.height * s;
    final double top = (view.height * horizonAt - plateHorizon * ph).clamp(math.min(0.0, view.height - ph), 0.0).toDouble();
    final left = (view.width / 2 - plateFocusX * pw).clamp(view.width - pw, 0.0);
    final plateRect = Rect.fromLTWH(left, top, pw, ph);

    // Criatura: alto pedido, con tope de ancho; centrada por su centro de masa.
    var k = profile.heightFrac * view.height / rig.body.height;
    k = math.min(k, profile.maxWidthFrac * view.width / rig.body.width);
    final feet = Offset(view.width / 2 + (rig.feet.dx - rig.centroidX) * k, view.height * profile.feetFrac);
    Rect map(Rect r) => Rect.fromLTRB(
      feet.dx + (r.left - rig.feet.dx) * k,
      feet.dy + (r.top - rig.feet.dy) * k,
      feet.dx + (r.right - rig.feet.dx) * k,
      feet.dy + (r.bottom - rig.feet.dy) * k,
    );
    return StageLayout(view: view, plateRect: plateRect, scale: k, feet: feet, rigFeet: rig.feet, body: map(rig.body), head: map(rig.head));
  }

  final Size view;

  /// Placa de fondo en pantalla.
  final Rect plateRect;

  /// Px de pantalla por px del recorte.
  final double scale;

  /// Pies de la criatura en pantalla (línea del piso).
  final Offset feet;

  /// Pies en px del recorte.
  final Offset rigFeet;

  /// Cuerpo y cabeza en reposo, en pantalla.
  final Rect body;
  final Rect head;

  double get floorY => feet.dy;

  /// Px del recorte → pantalla (pose de reposo).
  Offset toScreen(Offset imagePx) => Offset(feet.dx + (imagePx.dx - rigFeet.dx) * scale, feet.dy + (imagePx.dy - rigFeet.dy) * scale);

  /// Pantalla → coordenadas locales del títere (px del recorte relativos a los pies).
  Offset toLocal(Offset screen) => Offset((screen.dx - feet.dx) / scale, (screen.dy - feet.dy) / scale);
}
