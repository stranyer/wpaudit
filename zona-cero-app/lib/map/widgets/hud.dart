import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/core.dart';
import '../../services/location/location_types.dart';
import '../../state/app_state.dart';
import '../../state/location_controller.dart';
import '../../state/world_controller.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/ecg_monitor.dart';
import '../../ui/widgets/grit.dart';
import '../game_map.dart';
import '../map_math.dart';
import '../weather.dart';

/// Borde de los controles del mapa (un poco más claro que el de los paneles).
const kMapControlBorder = Color(0xFF575B5E);

/// Fondo de los controles y tarjetas sobre el mapa.
const kMapControlFill = Color(0xE8101213);

// -----------------------------------------------------------------------------
// Modelo del HUD: clima y región
// -----------------------------------------------------------------------------

/// Clima y rótulos de región del HUD. Lo crea la pantalla del mapa.
class MapHudModel extends ChangeNotifier {
  MapHudModel(this.camera) {
    app.location.addListener(_onLocation);
    weather.addListener(notifyListeners);
    _onLocation();
  }

  final GameMapController camera;
  final weather = WeatherController();
  String? _place;
  LatLng? _placeAt;
  int _placeQueriedAt = 0;
  ({String city, String region}) _labels = regionLabels(null);

  ({String city, String region}) get labels => _labels;
  WeatherReading? get reading => weather.reading;

  void _onLocation() {
    final p = app.location.position;
    weather.update(p);
    _relabel();
    if (p == null || kIsWeb || inBox(p, ambaBox)) return;
    // Fuera del AMBA: pedirle al mapa el lugar más cercano (cada 2 min o 2 km).
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _placeAt;
    if (now - _placeQueriedAt < 120000 && last != null && haversineM(last, p) < 2000) return;
    _placeQueriedAt = now;
    _placeAt = p;
    camera.nearestPlaceName().then((name) {
      if (name == null || name == _place) return;
      _place = name;
      _relabel();
    });
  }

  void _relabel() {
    final next = regionLabels(app.location.position, placeName: _place);
    if (next != _labels) {
      _labels = next;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    app.location.removeListener(_onLocation);
    weather.removeListener(notifyListeners);
    weather.dispose();
    super.dispose();
  }
}

// -----------------------------------------------------------------------------
// Encabezado: logo + tarjeta de estado
// -----------------------------------------------------------------------------

class MapHeader extends StatelessWidget {
  const MapHeader({super.key, required this.model});

  final MapHudModel model;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const GrungeTitle('ZONA CERO', size: 33, letterSpacing: 4.4, maxLines: 1),
                  const SizedBox(height: 5),
                  Text(
                    'VITA-7  //  PROTOCOLO SUTURA',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: SuturaText.label.copyWith(fontSize: 9.5, letterSpacing: 3.0, color: Sutura.signal),
                  ),
                ],
              ),
            ),
          ),
        ),
        StatusCard(model: model),
      ],
    );
  }
}

/// "SIMULACIÓN · 15:58 | ☁ 16° BUENOS AIRES".
class StatusCard extends StatefulWidget {
  const StatusCard({super.key, required this.model});

  final MapHudModel model;

  @override
  State<StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends State<StatusCard> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DateTime.now();
    final hhmm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return ListenableBuilder(
      listenable: Listenable.merge([app.location, widget.model]),
      builder: (context, _) {
        final loc = app.location;
        final (label, color) = switch (loc.mode) {
          LocationMode.demo => ('SIMULACIÓN', Sutura.textMid),
          _ when loc.position != null && loc.status != LocationStatus.error => ('EN LÍNEA', Sutura.textMid),
          _ => ('SIN SEÑAL', Sutura.danger),
        };
        final w = widget.model.reading;
        final city = widget.model.labels.city;
        return Semantics(
          label: '$label, $hhmm${w != null ? ', ${w.tempLabel}' : ''}, $city',
          child: GritPanel(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            background: kMapControlFill,
            border: Sutura.lineHair,
            corners: null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: SuturaText.label.copyWith(fontSize: 8, letterSpacing: 1.8, color: color)),
                    const SizedBox(height: 4),
                    Text(hhmm, style: SuturaText.number.copyWith(fontSize: 22, letterSpacing: 2.2, fontWeight: FontWeight.w500)),
                  ],
                ),
                Container(width: 1, height: 30, margin: const EdgeInsets.symmetric(horizontal: 8), color: Sutura.lineStrong),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 74),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (w != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 19,
                              height: 14,
                              child: CustomPaint(painter: WeatherGlyphPainter(w.kind, day: w.isDay)),
                            ),
                            const SizedBox(width: 5),
                            Text(w.tempLabel, style: SuturaText.number.copyWith(fontSize: 16.5, letterSpacing: 0.6)),
                          ],
                        ),
                      if (w != null) const SizedBox(height: 4),
                      Text(
                        city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SuturaText.label.copyWith(fontSize: 7, letterSpacing: 1.3, color: Sutura.textMid),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Glifo de clima dibujado (nube gris, sol, luna, lluvia, tormenta, niebla, nieve).
class WeatherGlyphPainter extends CustomPainter {
  WeatherGlyphPainter(this.kind, {this.day = true});

  final WeatherKind kind;
  final bool day;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height / 14;
    canvas.save();
    canvas.scale(s);
    const grey = Color(0xFFB9BBBC);
    const dim = Color(0xFF8D9092);
    final fill = Paint()..color = grey;
    final line = Paint()
      ..color = grey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;

    void cloud(Offset o, Color c) {
      final p = Paint()..color = c;
      canvas.drawCircle(o + const Offset(-4, 1.5), 3.2, p);
      canvas.drawCircle(o + const Offset(0.5, -0.8), 4.4, p);
      canvas.drawCircle(o + const Offset(4.6, 1.6), 3, p);
      canvas.drawRRect(RRect.fromLTRBR(o.dx - 7, o.dy + 0.5, o.dx + 7.6, o.dy + 4.6, const Radius.circular(2)), p);
    }

    void sun(Offset o, double r) {
      canvas.drawCircle(o, r, fill);
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final d = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(o + d * (r + 1.6), o + d * (r + 3.2), line);
      }
    }

    void moon(Offset o, double r) {
      final p = Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: o, radius: r)),
        Path()..addOval(Rect.fromCircle(center: o + Offset(r * 0.55, -r * 0.35), radius: r * 0.85)),
      );
      canvas.drawPath(p, fill);
    }

    const c = Offset(9.5, 6);
    switch (kind) {
      case WeatherKind.clear:
        day ? sun(const Offset(9.5, 7), 3.6) : moon(const Offset(9.5, 7), 5.2);
      case WeatherKind.partly:
        day ? sun(const Offset(13, 4.5), 2.6) : moon(const Offset(13.5, 4.5), 3.6);
        cloud(const Offset(8, 7.5), grey);
      case WeatherKind.cloud:
        cloud(c, grey);
      case WeatherKind.fog:
        for (final (i, y) in [3.5, 7.0, 10.5].indexed) {
          canvas.drawLine(Offset(2.5 + i * 1.5, y), Offset(16.5 - (2 - i) * 1.2, y), line);
        }
      case WeatherKind.drizzle || WeatherKind.rain:
        cloud(const Offset(9.5, 4), grey);
        final drop = Paint()
          ..color = dim
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round;
        final n = kind == WeatherKind.rain ? 3 : 2;
        for (var i = 0; i < n; i++) {
          final x = 6.5 + i * (n == 3 ? 3.2 : 5.0);
          canvas.drawLine(Offset(x, 10.2), Offset(x - 1.2, 13), drop);
        }
      case WeatherKind.snow:
        cloud(const Offset(9.5, 4), grey);
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(Offset(6.5 + i * 3.2, 11.8), 0.95, Paint()..color = dim);
        }
      case WeatherKind.storm:
        cloud(const Offset(9.5, 4), dim);
        canvas.drawPath(
          Path()
            ..moveTo(10.5, 8.2)
            ..lineTo(7.8, 11.4)
            ..lineTo(9.8, 11.4)
            ..lineTo(8.6, 14)
            ..lineTo(12.2, 10.2)
            ..lineTo(10.2, 10.2)
            ..lineTo(11.6, 8.2)
            ..close(),
          Paint()..color = Sutura.amber,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(WeatherGlyphPainter old) => old.kind != kind || old.day != day;
}

// -----------------------------------------------------------------------------
// Objetivo actual
// -----------------------------------------------------------------------------

/// Objetivo contextual y a dónde apunta (para centrar la cámara al tocarlo).
class MapObjective {
  const MapObjective(this.text, this.color, {this.target, this.targetId});

  final String text;
  final Color color;
  final LatLng? target;
  final String? targetId;

  static MapObjective compute() {
    final pos = app.location.position;
    if (pos == null) return const MapObjective('Buscando señal GNSS', Sutura.textMid);
    if (app.location.speedLocked) return const MapObjective('Bajá la velocidad', Sutura.danger);
    final p = app.player;
    if (p != null && p.health / maxHealth(p) < 0.25) return const MapObjective('Curate: signos vitales críticos', Sutura.caution2);
    final w = app.world;
    final now = DateTime.now().millisecondsSinceEpoch;
    String near(double d) => distanceLabel(d);

    // Lo seleccionado manda.
    final selId = w.selectedId;
    final sel = w.spawnById(selId);
    if (sel != null) {
      final d = app.distanceTo(sel.position) ?? 0;
      final inReach = app.isNear(sel.position);
      final text = switch (sel) {
        ZombieSpawn() => inReach ? 'Enfrentá al infectado' : 'Acercate al infectado · ${near(d)}',
        SupplySpawn() => inReach ? 'Recuperá el suministro' : 'Acercate al saqueo · ${near(d)}',
      };
      final color = inReach ? (sel is ZombieSpawn ? Sutura.danger : Sutura.amber) : Sutura.textHi;
      return MapObjective(text, color, target: sel.position, targetId: sel.id);
    }
    final sig = w.signalById(selId);
    if (sig != null) {
      return app.isNear(sig.position)
          ? MapObjective('Respondé la señal de auxilio', Sutura.amber, target: sig.position, targetId: sig.id)
          : MapObjective(
              'Acercate a la señal · ${near(app.distanceTo(sig.position) ?? 0)}',
              Sutura.textHi,
              target: sig.position,
              targetId: sig.id,
            );
    }
    final node = w.shelterById(selId);
    if (node != null) {
      return app.isNear(node.position)
          ? MapObjective('Abrí el nodo de relevo', Sutura.signal, target: node.position, targetId: node.id)
          : MapObjective(
              'Llegá al refugio · ${near(app.distanceTo(node.position) ?? 0)}',
              Sutura.textHi,
              target: node.position,
              targetId: node.id,
            );
    }

    // Algo al alcance.
    Spawn? closest;
    var closestD = double.infinity;
    for (final s in w.drawable) {
      if (w.visibilityOf(s, pos, now) == SpawnVisibility.hidden) continue;
      final d = haversineM(pos, s.position);
      if (d < closestD) {
        closest = s;
        closestD = d;
      }
    }
    final nearestSignal = _nearest([for (final s in w.signals) (s.id, s.position)], pos);
    if (nearestSignal != null && app.isNear(nearestSignal.$2)) {
      return MapObjective('Respondé la señal de auxilio', Sutura.amber, target: nearestSignal.$2, targetId: nearestSignal.$1);
    }
    if (closest != null && app.isNear(closest.position)) {
      return switch (closest) {
        ZombieSpawn() => MapObjective('Enfrentá al infectado', Sutura.danger, target: closest.position, targetId: closest.id),
        SupplySpawn() => MapObjective('Recuperá el suministro', Sutura.amber, target: closest.position, targetId: closest.id),
      };
    }
    if (closest != null) {
      return MapObjective('Acercate a un contacto', Sutura.textHi, target: closest.position, targetId: closest.id);
    }
    if (w.scanCooldownLeft(now) == 0) return const MapObjective('Escaneá la zona', Sutura.textHi);
    if (nearestSignal != null && haversineM(pos, nearestSignal.$2) < 1200) {
      return MapObjective('Rastreá la señal de auxilio', Sutura.textHi, target: nearestSignal.$2, targetId: nearestSignal.$1);
    }
    return const MapObjective('Explorá: caminá para encontrar contactos', Sutura.textHi);
  }

  static (String, LatLng)? _nearest(List<(String, LatLng)> items, LatLng from) {
    (String, LatLng)? best;
    var bestD = double.infinity;
    for (final it in items) {
      final d = haversineM(from, it.$2);
      if (d < bestD) {
        bestD = d;
        best = it;
      }
    }
    return best;
  }
}

/// Tarjeta "OBJETIVO ACTUAL": al tocarla, la cámara va hasta el objetivo.
class ObjectiveCard extends StatelessWidget {
  const ObjectiveCard({super.key, required this.camera});

  final GameMapController camera;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app.world, app.location, app]),
      builder: (context, _) {
        final o = MapObjective.compute();
        return Semantics(
          button: true,
          label: 'Objetivo actual: ${o.text}. Tocá para verlo en el mapa.',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              final t = o.target;
              if (t == null) {
                camera.recenter();
              } else {
                camera.focus(t, select: o.targetId);
              }
            },
            child: GritPanel(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 9),
              background: kMapControlFill,
              border: const Color(0xFF6A6E71),
              corners: null,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('OBJETIVO ACTUAL', style: SuturaText.label.copyWith(fontSize: 9.5, letterSpacing: 3.2)),
                        const SizedBox(height: 3),
                        AnimatedSwitcher(
                          duration: Sutura.fast,
                          layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                          child: FittedBox(
                            key: ValueKey(o.text),
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              o.text,
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: Sutura.fUi,
                                fontWeight: FontWeight.w500,
                                fontSize: 20,
                                letterSpacing: 1.1,
                                height: 1.15,
                                color: o.color,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 24, color: Sutura.textMid),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Controles de cámara
// -----------------------------------------------------------------------------

/// Botón cuadrado de los controles del mapa.
class MapControlButton extends StatelessWidget {
  const MapControlButton({
    super.key,
    required this.child,
    required this.label,
    this.onTap,
    this.onLongPress,
    this.width = 44,
    this.height = 44,
    this.active = false,
  });

  final Widget child;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double width;
  final double height;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        onLongPress: onLongPress,
        child: SizedBox(
          width: width,
          height: height,
          child: GritPanel(
            padding: EdgeInsets.zero,
            background: kMapControlFill,
            border: active ? Sutura.signal.withValues(alpha: 0.8) : kMapControlBorder,
            corners: null,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Brújula: "N" sobre una flecha; gira con el mapa. Tocar = norte arriba;
/// mantener = vista inclinada.
class CompassButton extends StatelessWidget {
  const CompassButton({super.key, required this.camera});

  final GameMapController camera;

  @override
  Widget build(BuildContext context) {
    return MapControlButton(
      label: 'Brújula: tocá para poner el norte arriba',
      width: 42,
      height: 42,
      onTap: camera.resetNorth,
      onLongPress: camera.togglePitch,
      child: ListenableBuilder(
        listenable: camera,
        builder: (context, _) => Transform.rotate(
          angle: -camera.bearing * math.pi / 180,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'N',
                style: TextStyle(fontFamily: Sutura.fUi, fontWeight: FontWeight.w600, fontSize: 11, height: 1, color: Sutura.textHi),
              ),
              SizedBox(height: 3),
              SizedBox(width: 14, height: 16, child: CustomPaint(painter: _ArrowPainter())),
            ],
          ),
        ),
      ),
    );
  }
}

/// Flecha de navegación con relieve (mitad clara, mitad oscura).
class _ArrowPainter extends CustomPainter {
  const _ArrowPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final tip = Offset(s.width / 2, 0);
    final notch = Offset(s.width / 2, s.height * 0.72);
    final left = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(0, s.height)
      ..lineTo(notch.dx, notch.dy)
      ..close();
    final right = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(s.width, s.height)
      ..lineTo(notch.dx, notch.dy)
      ..close();
    canvas.drawPath(left, Paint()..color = const Color(0xFFC9CCCD));
    canvas.drawPath(right, Paint()..color = const Color(0xFF7D8183));
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => false;
}

/// "+" / "−" en un mismo panel.
class ZoomButtons extends StatelessWidget {
  const ZoomButtons({super.key, required this.camera, this.width = 44});

  final GameMapController camera;
  final double width;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String label, VoidCallback onTap) => Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          width: width,
          height: 44,
          child: Icon(icon, size: 22, color: Sutura.textHi),
        ),
      ),
    );
    return SizedBox(
      width: width,
      child: GritPanel(
        padding: EdgeInsets.zero,
        background: kMapControlFill,
        border: kMapControlBorder,
        corners: null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            btn(Icons.add, 'Acercar', camera.zoomIn),
            Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 6), color: kMapControlBorder),
            btn(Icons.remove, 'Alejar', camera.zoomOut),
          ],
        ),
      ),
    );
  }
}

/// Volver a seguir al jugador.
class LocateButton extends StatelessWidget {
  const LocateButton({super.key, required this.camera});

  final GameMapController camera;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: camera,
      builder: (context, _) => MapControlButton(
        label: camera.follow ? 'Siguiendo tu posición' : 'Volver a mi posición',
        active: !camera.follow,
        onTap: camera.recenter,
        child: Transform.rotate(
          angle: math.pi / 4,
          child: Icon(Icons.navigation, size: 21, color: camera.follow ? Sutura.textHi : Sutura.signal),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Pie del mapa: región y escala
// -----------------------------------------------------------------------------

class MapCaption extends StatelessWidget {
  const MapCaption({super.key, required this.model});

  final MapHudModel model;

  @override
  Widget build(BuildContext context) {
    final low = SuturaText.label.copyWith(fontSize: 8.5, letterSpacing: 2.6, color: const Color(0xFF8C8F91), height: 1.35);
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(model.labels.region, style: low.copyWith(fontSize: 11, letterSpacing: 3, color: const Color(0xFFC4C6C7))),
          Text('MAPA DE EXPLORACIÓN', style: low),
          Text('V.1.3', style: low),
        ],
      ),
    );
  }
}

class ScaleBar extends StatelessWidget {
  const ScaleBar({super.key, required this.camera, this.maxWidth = 110});

  final GameMapController camera;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: camera,
      builder: (context, _) {
        final lat = camera.latitude ?? app.location.position?.lat ?? gameConfig.demo.start.lat;
        final spec = scaleBarFor(lat: lat, zoom: camera.zoom, maxPx: maxWidth);
        final style = SuturaText.label.copyWith(fontSize: 8.5, letterSpacing: 1.2, color: const Color(0xFFB3B6B7), height: 1);
        return Semantics(
          label: 'Escala: ${spec.labels.last}',
          child: SizedBox(
            width: spec.px + 26,
            height: 26,
            child: CustomPaint(painter: _ScalePainter(spec, style)),
          ),
        );
      },
    );
  }
}

class _ScalePainter extends CustomPainter {
  _ScalePainter(this.spec, this.style);
  final ScaleBarSpec spec;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final x0 = 4.0;
    final y = size.height - 4;
    final line = Paint()
      ..color = const Color(0xFFB3B6B7)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(x0, y), Offset(x0 + spec.px, y), line);
    for (final (i, f) in [0.0, 0.5, 1.0].indexed) {
      final x = x0 + spec.px * f;
      canvas.drawLine(Offset(x, y - 4), Offset(x, y + 3), line);
      final tp = TextPainter(
        text: TextSpan(text: spec.labels[i], style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = i == 2 ? x - 4 : x - tp.width / 2;
      tp.paint(canvas, Offset(dx.clamp(0, size.width - tp.width), y - 9 - tp.height));
    }
  }

  @override
  bool shouldRepaint(_ScalePainter old) => old.spec.px != spec.px || old.spec.meters != spec.meters;
}

// -----------------------------------------------------------------------------
// Panel ESTADO
// -----------------------------------------------------------------------------

class StatusPanel extends StatelessWidget {
  const StatusPanel({super.key, this.height = 96});

  final double height;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final p = app.player;
        final ratio = p == null ? 1.0 : (p.health / maxHealth(p)).clamp(0.0, 1.0);
        final stamina = p == null ? 1.0 : (p.stamina / maxStamina(p)).clamp(0.0, 1.0);
        final vital = vitalFor(ratio);
        final rowStyle = SuturaText.label.copyWith(fontSize: 10, letterSpacing: 1.8, color: Sutura.textMid);
        Widget row(String label, double v, Color c) => Row(
          children: [
            SizedBox(width: 74, child: Text(label, style: rowStyle)),
            Expanded(
              child: StatBar(ratio: v, color: c, height: 6),
            ),
          ],
        );
        return Semantics(
          label: 'Estado ${vitalLabel(vital)}. Salud ${(ratio * 100).round()} %. Resistencia ${(stamina * 100).round()} %.',
          child: GritPanel(
            padding: const EdgeInsets.fromLTRB(14, 8, 12, 10),
            accent: const Color(0xFF8E9295),
            child: SizedBox(
              height: height - 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('ESTADO', style: SuturaText.label.copyWith(fontSize: 11, letterSpacing: 2.6)),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) => Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: 0,
                            top: 2,
                            child: EcgMonitor(ratio: ratio, width: c.maxWidth * 0.82, height: c.maxHeight - 4, showLabel: false),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 1,
                            child: Text(
                              vitalLabel(vital),
                              style: SuturaText.label.copyWith(fontSize: 12.5, letterSpacing: 2.2, color: vitalColor(vital)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  row('SALUD', ratio, Sutura.fine),
                  const SizedBox(height: 6),
                  row('RESISTENCIA', stamina, Sutura.signal),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Bloqueo por velocidad
// -----------------------------------------------------------------------------

class SpeedLockBanner extends StatelessWidget {
  const SpeedLockBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.location,
      builder: (context, _) {
        if (!app.location.speedLocked) return const SizedBox.shrink();
        return GritPanel(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          background: const Color(0xEE2A0D0B),
          border: Sutura.accent,
          accent: Sutura.accent,
          corners: null,
          child: Row(
            children: [
              const Icon(Icons.speed, size: 17, color: Sutura.danger),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'VELOCIDAD EXCESIVA · INTERACCIONES EN PAUSA',
                  style: SuturaText.label.copyWith(fontSize: 10.5, letterSpacing: 1.8, color: const Color(0xFFF2C9C5)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Antes del primer fix
// -----------------------------------------------------------------------------

class GnssSearchOverlay extends StatefulWidget {
  const GnssSearchOverlay({super.key});

  @override
  State<GnssSearchOverlay> createState() => _GnssSearchOverlayState();
}

class _GnssSearchOverlayState extends State<GnssSearchOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

  @override
  void initState() {
    super.initState();
    app.location.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    app.location.removeListener(_sync);
    _c.dispose();
    super.dispose();
  }

  void _sync() {
    final searching = app.location.position == null;
    if (searching && !_c.isAnimating) _c.repeat();
    if (!searching && _c.isAnimating) _c.stop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.location,
      builder: (context, _) {
        final loc = app.location;
        final searching = loc.position == null;
        return IgnorePointer(
          ignoring: !searching,
          child: AnimatedOpacity(
            opacity: searching ? 1 : 0,
            duration: Sutura.heavy,
            child: ColoredBox(
              color: Sutura.void_.withValues(alpha: 0.82),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 120,
                      child: AnimatedBuilder(
                        animation: _c,
                        builder: (context, _) => CustomPaint(painter: _SearchPainter(_c.value)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const GrungeTitle('BUSCANDO SEÑAL GNSS…', size: 22, letterSpacing: 3, maxLines: 1),
                    const SizedBox(height: 8),
                    if (loc.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          locationErrorMessages[loc.error]!,
                          textAlign: TextAlign.center,
                          style: SuturaText.bodyMid.copyWith(fontSize: 14),
                        ),
                      )
                    else
                      Text(
                        'VITA-7  //  TRIANGULANDO SATÉLITES',
                        style: SuturaText.label.copyWith(fontSize: 10.5, letterSpacing: 3, color: Sutura.signal),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SearchPainter extends CustomPainter {
  _SearchPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    for (var i = 0; i < 3; i++) {
      final k = (t + i / 3) % 1.0;
      canvas.drawCircle(
        c,
        r * (0.25 + 0.75 * Sutura.scanCurve.transform(k)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Sutura.signal.withValues(alpha: (1 - k) * 0.7),
      );
    }
    canvas.drawCircle(c, 14, Paint()..color = Sutura.surface2);
    canvas.drawCircle(
      c,
      14,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFF2F4F5),
    );
    canvas.drawCircle(c, 5, Paint()..color = const Color(0xFFF2F4F5));
    final a = t * 2 * math.pi;
    canvas.drawLine(
      c,
      c + Offset(math.cos(a), math.sin(a)) * (r - 4),
      Paint()
        ..color = Sutura.signal.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_SearchPainter old) => old.t != t;
}
