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
import '../../ui/widgets/grit.dart';
import '../game_map.dart';
import '../map_math.dart';
import '../map_style.dart';
import '../weather.dart';

/// Borde de los controles del mapa (un poco más claro que el de los paneles).
const kMapControlBorder = Color(0xFF63676A);

/// Fondo de los controles y tarjetas sobre el mapa.
const kMapControlFill = Color(0xE00E1011);

/// Esquinas recortadas de los controles (como en la referencia).
const kMapCuts = Cuts(topLeft: 5, topRight: 5, bottomRight: 5, bottomLeft: 5);

/// Foto del Obelisco (encabezado y tarjeta de objetivo, muy tenue).
const _obelisco = 'assets/art/bg/obelisco.webp';

/// Desatura una imagen a gris.
const _greyscale = ColorFilter.matrix([
  0.25, 0.55, 0.12, 0, 0, //
  0.25, 0.55, 0.12, 0, 0,
  0.25, 0.55, 0.12, 0, 0,
  0, 0, 0, 1, 0,
]);

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
  List<String> _caption = regionCaption(null);

  ({String city, String region}) get labels => _labels;

  /// Pie junto al emblema ("CIUDAD AUTÓNOMA / DE BUENOS AIRES / ARG.").
  List<String> get caption => _caption;
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
    final p = app.location.position;
    final next = regionLabels(p, placeName: _place);
    final caption = regionCaption(p, placeName: _place);
    if (next != _labels || !listEquals(caption, _caption)) {
      _labels = next;
      _caption = caption;
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
    return LayoutBuilder(
      builder: (context, c) {
        // La nota a mano solo si entra (pantallas de 370 px o más).
        final note = c.maxWidth >= 340;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: IgnorePointer(
                child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topLeft, child: const ZcLogo(size: 27)),
              ),
            ),
            const SizedBox(width: 10),
            StatusCard(model: model),
            if (note)
              const IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.only(left: 2, top: 4),
                  child: SizedBox(
                    width: 42,
                    height: 52,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topLeft,
                      child: HandNote('Mismas\ncalles\notra\nhistoria', size: 11, angle: -0.22, color: Color(0xFF8A8781)),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// "BUENOS AIRES · SIMULACIÓN · 15:58 | DÍA 7 · ☁ 16°C", con el Obelisco tenue.
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
      listenable: Listenable.merge([app.location, widget.model, app]),
      builder: (context, _) {
        final loc = app.location;
        final (label, color) = switch (loc.mode) {
          LocationMode.demo => ('SIMULACIÓN', Sutura.textLow),
          _ when loc.position != null && loc.status != LocationStatus.error => ('EN LÍNEA', Sutura.textLow),
          _ => ('SIN SEÑAL', Sutura.danger),
        };
        final w = widget.model.reading;
        final city = widget.model.labels.city;
        final p = app.player;
        final day = p == null ? 1 : survivalDay(p.createdAt, t.millisecondsSinceEpoch);
        final small = SuturaText.label.copyWith(fontSize: 8.5, letterSpacing: 1.7, color: Sutura.textLow, height: 1.1);
        return Semantics(
          label: '$city, $label, $hhmm, día $day${w != null ? ', ${w.tempLabel}C' : ''}',
          child: IgnorePointer(
            child: SizedBox(
              width: 128,
              height: 54,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0x660B0C0D),
                        border: Border.all(color: const Color(0xFF3B3F42), width: 0.8),
                      ),
                    ),
                  ),
                  // Obelisco: silueta tenue a la derecha de la tarjeta.
                  Positioned(
                    right: 1,
                    top: -9,
                    bottom: 1,
                    width: 20,
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (r) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFFFFFF), Color(0xCCFFFFFF), Color(0x00FFFFFF)],
                        stops: [0, 0.7, 1],
                      ).createShader(r),
                      child: Opacity(
                        opacity: 0.55,
                        child: ColorFiltered(
                          colorFilter: _greyscale,
                          child: Image.asset(
                            _obelisco,
                            fit: BoxFit.fitHeight,
                            alignment: const Alignment(-0.08, -1),
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 22, 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                city,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SuturaText.label.copyWith(fontSize: 9.5, letterSpacing: 1.6, color: Sutura.textHi, height: 1.1),
                              ),
                            ),
                            if (w != null)
                              SizedBox(
                                width: 17,
                                height: 12,
                                child: CustomPaint(painter: WeatherGlyphPainter(w.kind, day: w.isDay)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(
                              child: Text(label, maxLines: 1, style: small.copyWith(color: color)),
                            ),
                            Text(
                              w != null ? '${w.tempC.round()}°C' : '—°C',
                              style: SuturaText.label.copyWith(
                                fontSize: 10,
                                letterSpacing: 0.6,
                                color: w != null ? Sutura.textHi : Sutura.textLow,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              hhmm,
                              style: SuturaText.number.copyWith(
                                fontSize: 20,
                                letterSpacing: 1.4,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFFD9D6CF),
                              ),
                            ),
                            Container(width: 1, height: 13, margin: const EdgeInsets.fromLTRB(6, 0, 5, 2), color: Sutura.lineStrong),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text('DÍA $day', style: small),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Glifo de clima de línea fina (nube con sol, sol, luna, lluvia, tormenta,
/// niebla, nieve), como el de la referencia.
class WeatherGlyphPainter extends CustomPainter {
  WeatherGlyphPainter(this.kind, {this.day = true});

  final WeatherKind kind;
  final bool day;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height / 14;
    canvas.save();
    canvas.scale(s);
    const grey = Color(0xFFCFD1D2);
    const dim = Color(0xFF9A9D9F);
    final line = Paint()
      ..color = grey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Path cloudPath(Offset o) {
      final p = Path()
        ..moveTo(o.dx - 6.5, o.dy + 4)
        ..arcToPoint(Offset(o.dx - 4.2, o.dy - 0.6), radius: const Radius.circular(2.6))
        ..arcToPoint(Offset(o.dx + 3.4, o.dy - 1), radius: const Radius.circular(4.2))
        ..arcToPoint(Offset(o.dx + 6.4, o.dy + 4), radius: const Radius.circular(2.8))
        ..close();
      return p;
    }

    void cloud(Offset o, [Color c = grey]) => canvas.drawPath(cloudPath(o), line..color = c);

    void sun(Offset o, double r) {
      canvas.drawCircle(o, r, line);
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final d = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(o + d * (r + 1.5), o + d * (r + 2.8), line);
      }
    }

    void moon(Offset o, double r) {
      final p = Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: o, radius: r)),
        Path()..addOval(Rect.fromCircle(center: o + Offset(r * 0.55, -r * 0.35), radius: r * 0.85)),
      );
      canvas.drawPath(p, line);
    }

    switch (kind) {
      case WeatherKind.clear:
        day ? sun(const Offset(9.5, 7), 3.2) : moon(const Offset(9.5, 7), 5);
      case WeatherKind.partly:
        // Sol (o luna) asomando detrás de la nube.
        canvas.save();
        canvas.clipPath(
          Path.combine(PathOperation.difference, Path()..addRect(const Rect.fromLTWH(0, 0, 20, 14)), cloudPath(const Offset(8, 8))),
        );
        day ? sun(const Offset(13.2, 4.6), 2.4) : moon(const Offset(13.5, 4.5), 3.4);
        canvas.restore();
        cloud(const Offset(8, 8));
      case WeatherKind.cloud:
        cloud(const Offset(9.5, 6.5));
      case WeatherKind.fog:
        for (final (i, y) in [3.5, 7.0, 10.5].indexed) {
          canvas.drawLine(Offset(2.5 + i * 1.5, y), Offset(16.5 - (2 - i) * 1.2, y), line);
        }
      case WeatherKind.drizzle || WeatherKind.rain:
        cloud(const Offset(9.5, 3.8));
        final drop = Paint()
          ..color = dim
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round;
        final n = kind == WeatherKind.rain ? 3 : 2;
        for (var i = 0; i < n; i++) {
          final x = 6.5 + i * (n == 3 ? 3.2 : 5.0);
          canvas.drawLine(Offset(x, 10.4), Offset(x - 1.1, 13), drop);
        }
      case WeatherKind.snow:
        cloud(const Offset(9.5, 3.8));
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(Offset(6.5 + i * 3.2, 11.8), 0.9, Paint()..color = dim);
        }
      case WeatherKind.storm:
        cloud(const Offset(9.5, 3.8), dim);
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
      final d = app.distanceToSpawn(sel) ?? 0;
      final inReach = app.isNearSpawn(sel);
      final text = switch (sel) {
        ZombieSpawn() => inReach ? 'Enfrentá al infectado' : 'Acercate al infectado · ${near(d)}',
        SupplySpawn() => inReach ? 'Recuperá el suministro' : 'Acercate al saqueo · ${near(d)}',
      };
      final color = inReach ? (sel is ZombieSpawn ? Sutura.danger : Sutura.amber) : Sutura.textHi;
      return MapObjective(text, color, target: w.positionAt(sel, now), targetId: sel.id);
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
          ? MapObjective('Abrí el nodo de relevo', Sutura.refuge, target: node.position, targetId: node.id)
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
      final d = haversineM(pos, w.positionAt(s, now));
      if (d < closestD) {
        closest = s;
        closestD = d;
      }
    }
    final nearestSignal = _nearest([for (final s in w.signals) (s.id, s.position)], pos);
    if (nearestSignal != null && app.isNear(nearestSignal.$2)) {
      return MapObjective('Respondé la señal de auxilio', Sutura.amber, target: nearestSignal.$2, targetId: nearestSignal.$1);
    }
    if (closest != null && app.isNearSpawn(closest)) {
      final at = w.positionAt(closest, now);
      return switch (closest) {
        ZombieSpawn() => MapObjective('Enfrentá al infectado', Sutura.danger, target: at, targetId: closest.id),
        SupplySpawn() => MapObjective('Recuperá el suministro', Sutura.amber, target: at, targetId: closest.id),
      };
    }
    if (closest != null) {
      return MapObjective('Acercate a un contacto', Sutura.textHi, target: w.positionAt(closest, now), targetId: closest.id);
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

/// Tarjeta "OBJETIVO ACTUAL" a todo el ancho, con una franja de foto a la
/// derecha ("ZONA CERO / SIGUE EN PIE"). Al tocarla, la cámara va al objetivo.
class ObjectiveCard extends StatelessWidget {
  const ObjectiveCard({super.key, required this.camera});

  final GameMapController camera;

  static const _cuts = Cuts(topLeft: 6, topRight: 9, bottomRight: 9, bottomLeft: 6);

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
            child: SizedBox(
              height: 50,
              child: CustomPaint(
                foregroundPainter: _FramePainter(_cuts, const Color(0xFF55595C)),
                child: ClipPath(
                  clipper: _CutsClip(_cuts),
                  child: Stack(
                    children: [
                      const Positioned.fill(child: ColoredBox(color: Color(0xD90B0C0D))),
                      // Franja de foto, desvanecida hacia la izquierda.
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: 190,
                        child: ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (r) => const LinearGradient(
                            colors: [Color(0x00FFFFFF), Color(0xB3FFFFFF), Color(0xFFFFFFFF)],
                            stops: [0, 0.55, 1],
                          ).createShader(r),
                          child: Opacity(
                            opacity: 0.72,
                            child: ColorFiltered(
                              colorFilter: _greyscale,
                              child: Image.asset(
                                _obelisco,
                                fit: BoxFit.cover,
                                alignment: const Alignment(0, 0.25),
                                filterQuality: FilterQuality.medium,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 7, 12, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      Container(width: 1, height: 9, color: Sutura.textLow),
                                      const SizedBox(width: 4),
                                      Text(
                                        'OBJETIVO ACTUAL',
                                        style: SuturaText.label.copyWith(fontSize: 8.5, letterSpacing: 2.6, color: Sutura.textLow),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(right: 9, left: 1),
                                        child: Icon(Icons.chevron_right, size: 17, color: Sutura.textMid),
                                      ),
                                      Expanded(
                                        child: AnimatedSwitcher(
                                          duration: Sutura.fast,
                                          layoutBuilder: (current, previous) =>
                                              Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
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
                                                fontSize: 17.5,
                                                letterSpacing: 0.9,
                                                height: 1.1,
                                                color: o.color == Sutura.textHi ? const Color(0xFFE2DFD8) : o.color,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const _StillStanding(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "ZONA CERO / SIGUE EN PIE" con un subrayado rojo a mano.
class _StillStanding extends StatelessWidget {
  const _StillStanding();

  @override
  Widget build(BuildContext context) {
    final style = SuturaText.label.copyWith(fontSize: 8, letterSpacing: 1.9, color: const Color(0xFFBDBAB3), height: 1.3);
    return IgnorePointer(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          Text('ZONA CERO', style: style),
          Text('SIGUE EN PIE', style: style),
          // Solo el trazo de HandNote (sin texto): un subrayado corto, rojo.
          Transform.translate(
            offset: const Offset(10, -9),
            child: const SizedBox(height: 10, child: HandNote('', size: 12, angle: -0.06, underline: Sutura.accent)),
          ),
        ],
      ),
    );
  }
}

class _CutsClip extends CustomClipper<Path> {
  const _CutsClip(this.cuts);
  final Cuts cuts;
  @override
  Path getClip(Size size) => cuts.path(size);
  @override
  bool shouldReclip(_CutsClip old) => old.cuts != cuts;
}

/// Marco fino con esquinas recortadas.
class _FramePainter extends CustomPainter {
  const _FramePainter(this.cuts, this.color);
  final Cuts cuts;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      cuts.path(size),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.color != color || old.cuts != cuts;
}

// -----------------------------------------------------------------------------
// Controles de cámara
// -----------------------------------------------------------------------------

/// Marco de los controles del mapa: borde fino y esquinas recortadas.
class MapControlFrame extends StatelessWidget {
  const MapControlFrame({super.key, required this.child, this.border = kMapControlBorder, this.background = kMapControlFill, this.glow});

  final Widget child;
  final Color border;
  final Color background;
  final Color? glow;

  @override
  Widget build(BuildContext context) =>
      GritPanel(padding: EdgeInsets.zero, background: background, border: border, corners: null, cuts: kMapCuts, glow: glow, child: child);
}

/// Botón cuadrado de los controles del mapa.
class MapControlButton extends StatelessWidget {
  const MapControlButton({
    super.key,
    required this.child,
    required this.label,
    this.onTap,
    this.onLongPress,
    this.width = 42,
    this.height = 42,
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
          child: MapControlFrame(
            border: active ? Sutura.signal.withValues(alpha: 0.8) : kMapControlBorder,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Indicador de norte, sin caja: "N" sobre una flecha; gira con el mapa.
/// Tocar = norte arriba; mantener = vista inclinada.
class NorthIndicator extends StatelessWidget {
  const NorthIndicator({super.key, required this.camera});

  final GameMapController camera;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Norte: tocá para poner el norte arriba',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          camera.resetNorth();
        },
        onLongPress: camera.togglePitch,
        child: SizedBox(
          width: 36,
          height: 52,
          child: ListenableBuilder(
            listenable: camera,
            builder: (context, _) => Transform.rotate(
              angle: -camera.bearing * math.pi / 180,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'N',
                    style: TextStyle(
                      fontFamily: Sutura.fUi,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      height: 1,
                      color: Color(0xFFD5D7D8),
                      shadows: [Shadow(color: Color(0xCC000000), blurRadius: 3)],
                    ),
                  ),
                  SizedBox(height: 6),
                  SizedBox(width: 18, height: 24, child: CustomPaint(painter: _ArrowPainter())),
                ],
              ),
            ),
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
    final notch = Offset(s.width / 2, s.height * 0.74);
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
    final shadow = Paint()
      ..color = const Color(0x99000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawPath(
      Path()
        ..addPath(left, Offset.zero)
        ..addPath(right, Offset.zero),
      shadow,
    );
    canvas.drawPath(left, Paint()..color = const Color(0xFFE1E3E4));
    canvas.drawPath(right, Paint()..color = const Color(0xFF9A9EA0));
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => false;
}

/// "+" / "−" en un mismo panel.
class ZoomButtons extends StatelessWidget {
  const ZoomButtons({super.key, required this.camera, this.width = 42});

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
          child: Icon(icon, size: 21, color: Sutura.textHi),
        ),
      ),
    );
    return SizedBox(
      width: width,
      child: MapControlFrame(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            btn(Icons.add, 'Acercar', camera.zoomIn),
            Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 8), color: kMapControlBorder.withValues(alpha: 0.7)),
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
          child: Icon(Icons.navigation, size: 19, color: camera.follow ? Sutura.textHi : Sutura.signal),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Pie del mapa: emblema y región, escala y créditos de los datos
// -----------------------------------------------------------------------------

class MapCaption extends StatelessWidget {
  const MapCaption({super.key, required this.model});

  final MapHudModel model;

  @override
  Widget build(BuildContext context) {
    final style = SuturaText.label.copyWith(fontSize: 7.5, letterSpacing: 2, color: const Color(0xFF8F9294), height: 1.45);
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(dimension: 30, child: CustomPaint(painter: SutureSealPainter())),
          const SizedBox(width: 9),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [for (final l in model.caption) Text(l, style: style)],
          ),
        ],
      ),
    );
  }
}

/// Emblema propio de la terminal (no es un escudo oficial): sello redondo con
/// un hexágono "suturado" y las iniciales ZC.
class SutureSealPainter extends CustomPainter {
  const SutureSealPainter({this.color = const Color(0xFF7D8183)});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 0.5;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = color;
    canvas.drawCircle(c, r, line);
    canvas.drawCircle(c, r - 2.6, line..strokeWidth = 0.6);
    // Corona de marcas finas entre los dos anillos.
    final tick = Paint()
      ..strokeWidth = 0.6
      ..color = color.withValues(alpha: 0.8);
    for (var i = 0; i < 36; i++) {
      final a = i * math.pi / 18;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r - 2.3), c + d * (r - 0.6), tick);
    }
    // Hexágono.
    final hr = r * 0.6;
    final hex = Path();
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + i * math.pi / 3;
      final v = c + Offset(math.cos(a), math.sin(a)) * hr;
      i == 0 ? hex.moveTo(v.dx, v.dy) : hex.lineTo(v.dx, v.dy);
    }
    hex.close();
    canvas.drawPath(
      hex,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = color,
    );
    // Sutura: costura en diagonal con puntadas.
    final a = c + Offset(-hr * 0.62, hr * 0.5);
    final b = c + Offset(hr * 0.62, -hr * 0.5);
    canvas.drawLine(
      a,
      b,
      Paint()
        ..strokeWidth = 0.8
        ..color = const Color(0xFF9C3A33),
    );
    final dir = (b - a) / (b - a).distance;
    final n = Offset(-dir.dy, dir.dx);
    for (var i = 1; i <= 4; i++) {
      final p = a + (b - a) * (i / 5);
      canvas.drawLine(
        p - n * 1.8,
        p + n * 1.8,
        Paint()
          ..strokeWidth = 0.8
          ..color = const Color(0xFF9C3A33),
      );
    }
    // "ZC".
    final tp = TextPainter(
      text: TextSpan(
        text: 'ZC',
        style: TextStyle(fontFamily: Sutura.fDisplay, fontWeight: FontWeight.w700, fontSize: r * 0.5, color: color, letterSpacing: 0.4),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(SutureSealPainter old) => old.color != color;
}

/// Escala táctica ("0  100  300 m") y créditos de los datos debajo.
class ScaleBar extends StatelessWidget {
  const ScaleBar({super.key, required this.camera, this.maxWidth = 92});

  final GameMapController camera;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final credit = SuturaText.label.copyWith(fontSize: 7.5, letterSpacing: 1.7, color: const Color(0xFF8F9294), height: 1.45);
    final satellite = SuturaMapStyle.satelliteTiles.isNotEmpty;
    return ListenableBuilder(
      listenable: camera,
      builder: (context, _) {
        final lat = camera.latitude ?? app.location.position?.lat ?? gameConfig.demo.start.lat;
        final spec = tacticalScaleFor(lat: lat, zoom: camera.zoom, maxPx: maxWidth);
        final style = SuturaText.label.copyWith(fontSize: 8, letterSpacing: 1, color: const Color(0xFFB9BCBD), height: 1);
        return Semantics(
          label: 'Escala: ${spec.labels.last}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: spec.px + 22,
                height: 20,
                child: CustomPaint(painter: _ScalePainter(spec, style)),
              ),
              const SizedBox(height: 9),
              Text(satellite ? 'DATOS SATELITALES  //  VITA-7' : 'CARTOGRAFÍA OSM  //  VITA-7', style: credit),
              Text('USO TÁCTICO ÚNICAMENTE', style: credit),
            ],
          ),
        );
      },
    );
  }
}

class _ScalePainter extends CustomPainter {
  _ScalePainter(this.spec, this.style);
  final TacticalScale spec;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final x0 = size.width - spec.px - 4;
    final y = size.height - 3;
    final line = Paint()
      ..color = const Color(0xFFB3B6B7)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(x0, y), Offset(x0 + spec.px, y), line);
    for (final (i, f) in spec.ticks.indexed) {
      final x = x0 + spec.px * f;
      canvas.drawLine(Offset(x, y - 4), Offset(x, y), line);
      final tp = TextPainter(
        text: TextSpan(text: spec.labels[i], style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = i == spec.ticks.length - 1 ? x - tp.width + 6 : x - tp.width / 2;
      tp.paint(canvas, Offset(dx.clamp(0, size.width - tp.width), y - 8 - tp.height));
    }
  }

  @override
  bool shouldRepaint(_ScalePainter old) => old.spec.px != spec.px || old.spec.meters != spec.meters;
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
// Entrada: rótulo mientras la cámara vuela hasta el jugador
// -----------------------------------------------------------------------------

class IntroCaption extends StatelessWidget {
  const IntroCaption({super.key, required this.camera});

  final GameMapController camera;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: camera,
        builder: (context, _) => AnimatedOpacity(
          opacity: camera.intro ? 1 : 0,
          duration: Sutura.heavy,
          child: Align(
            alignment: const Alignment(0, -0.3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ENLACE SATELITAL',
                  style: SuturaText.label.copyWith(
                    fontSize: 11,
                    letterSpacing: 4.4,
                    color: Sutura.textHi,
                    shadows: const [Shadow(color: Color(0xE6000000), blurRadius: 6)],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'VITA-7  //  TRIANGULANDO TU POSICIÓN',
                  style: SuturaText.label.copyWith(
                    fontSize: 8.5,
                    letterSpacing: 2.4,
                    color: Sutura.signal,
                    shadows: const [Shadow(color: Color(0xE6000000), blurRadius: 6)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
