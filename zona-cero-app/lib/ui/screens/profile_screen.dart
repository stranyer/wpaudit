import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../../state/app_state.dart';
import '../../state/location_controller.dart';
import '../theme/tokens.dart';
import '../widgets/brackets.dart';
import '../widgets/caps_title.dart';
import '../widgets/chamfer_button.dart';
import '../widgets/ecg_monitor.dart';
import '../widgets/hexagon.dart';
import '../widgets/screen_frame.dart';
import '../widgets/seg_bar.dart';
import 'node_screen.dart' show factionColor;

/// Eje del radar de perfil: valor normalizado con escala logarítmica.
class RadarAxis {
  const RadarAxis(this.label, this.value, this.cap);
  final String label;
  final double value;
  final double cap;

  double get ratio => value <= 0 ? 0 : (math.log(1 + value) / math.log(1 + cap)).clamp(0.0, 1.0);
}

List<RadarAxis> radarAxesOf(PlayerState p) {
  final kills = p.stats.zombiesKilled.values.fold(0, (a, b) => a + b);
  return [
    RadarAxis('Combate', kills.toDouble(), 150),
    RadarAxis('Exploración', p.stats.cellsExplored.toDouble(), 250),
    RadarAxis('Recolección', p.stats.suppliesLooted.toDouble(), 200),
    RadarAxis('Taller', p.stats.itemsCrafted.toDouble(), 60),
    RadarAxis('Red', p.stats.resourcesDonated.toDouble(), 400),
    RadarAxis('Marcha', p.stats.distanceWalkedM / 1000, 60),
  ];
}

/// Pestaña PERFIL: credencial del Enlace, radar de aptitudes, registro y ajustes.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app, app.location]),
      builder: (context, _) {
        final p = app.player;
        if (p == null) return const SizedBox.shrink();
        final kills = p.stats.zombiesKilled.values.fold(0, (a, b) => a + b);
        return TabScreenFrame(
          title: 'Perfil',
          code: 'CREDENCIAL DE ENLACE // ${app.badge}',
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
            children: [
              _Credential(player: p),
              const SectionLabel('Aptitudes'),
              SizedBox(height: 250, child: _Radar(axes: radarAxesOf(p))),
              const SectionLabel('Registro de campo'),
              DataRow2('Infectados neutralizados', '$kills'),
              for (final t in zombieTypes)
                if ((p.stats.zombiesKilled[t] ?? 0) > 0) DataRow2('  · ${zombieDefs[t]!.name}', '${p.stats.zombiesKilled[t]}', valueColor: Sutura.textMid),
              DataRow2('Encuentros ganados', '${p.stats.encountersWon}'),
              DataRow2('Retiradas', '${p.stats.encountersFled}'),
              DataRow2('Caídas', '${p.stats.deaths}', valueColor: p.stats.deaths > 0 ? Sutura.danger : Sutura.textHi),
              DataRow2('Suministros recuperados', '${p.stats.suppliesLooted}'),
              DataRow2('Objetos fabricados', '${p.stats.itemsCrafted}'),
              DataRow2('Recursos aportados', '${p.stats.resourcesDonated}'),
              DataRow2('Distancia recorrida', '${(p.stats.distanceWalkedM / 1000).toStringAsFixed(2).replaceFirst('.', ',')} km'),
              DataRow2('Sectores explorados', '${p.stats.cellsExplored}'),
              const SectionLabel('Terminal'),
              const _Settings(),
              const SizedBox(height: 22),
              Center(child: MicroText('ZONA CERO · PROTOCOLO SUTURA · v0.3', color: Sutura.textLow.withValues(alpha: 0.7))),
            ],
          ),
        );
      },
    );
  }
}

class _Credential extends StatelessWidget {
  const _Credential({required this.player});

  final PlayerState player;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final need = xpToNext(p.level);
    return BracketPanel(
      color: Sutura.accent,
      background: Sutura.surface1Solid,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                height: 104,
                child: ClipPath(
                  clipper: _HexClipper(),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1B2A30), Color(0xFF0A0F12)]),
                    ),
                    child: Image.asset(
                      'assets/art/bg/portrait.webp',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.person_outline, size: 54, color: Sutura.textLow),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ENLACE REGISTRADO', style: SuturaText.label.copyWith(fontSize: 11.5, color: Sutura.accent)),
                    const SizedBox(height: 4),
                    CapsTitle(p.name, size: 20),
                    const SizedBox(height: 2),
                    Text(app.badge, style: SuturaText.mono.copyWith(color: Sutura.textMid, letterSpacing: 2)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        StatusChip('Grado ${p.level}', color: Sutura.accent, filled: true),
                        StatusChip(rankTitle(p.level)),
                        if (p.factionId != null) StatusChip(factionDefs[p.factionId]!.name, color: factionColor(p.factionId)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const MicroText('xp'),
              const SizedBox(width: 8),
              Expanded(child: SegBar(value: p.xp.toDouble(), max: need.toDouble(), segments: 24, height: 5)),
              const SizedBox(width: 8),
              Text('${p.xp}/$need', style: SuturaText.mono.copyWith(fontSize: 11, color: Sutura.textMid)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              EcgMonitor(ratio: p.health / maxHealth(p), width: 110),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${p.health.round()}/${maxHealth(p)} SALUD', style: SuturaText.mono.copyWith(fontSize: 11)),
                  const SizedBox(height: 3),
                  Text('${p.stamina.round()}/${maxStamina(p)} RESIST.', style: SuturaText.mono.copyWith(fontSize: 11, color: Sutura.textMid)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HexClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => hexPath(size.center(Offset.zero), size.height / 2);

  @override
  bool shouldReclip(_HexClipper oldClipper) => false;
}

class _Radar extends StatelessWidget {
  const _Radar({required this.axes});

  final List<RadarAxis> axes;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Sutura.scanCurve,
      builder: (context, t, _) => CustomPaint(painter: _RadarPainter(axes, t), size: Size.infinite),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.axes, this.t);
  final List<RadarAxis> axes;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 - 34;
    final n = axes.length;
    Offset at(int i, double k) {
      final a = -math.pi / 2 + i * 2 * math.pi / n;
      return c + Offset(math.cos(a), math.sin(a)) * r * k;
    }

    final ring = Paint()
      ..color = Sutura.lineHair
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final k in [0.25, 0.5, 0.75, 1.0]) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final v = at(i, k);
        i == 0 ? path.moveTo(v.dx, v.dy) : path.lineTo(v.dx, v.dy);
      }
      canvas.drawPath(path..close(), ring..color = k == 1 ? Sutura.lineStrong : Sutura.lineHair);
    }
    for (var i = 0; i < n; i++) {
      canvas.drawLine(c, at(i, 1), ring..color = Sutura.lineHair);
    }

    final shape = Path();
    for (var i = 0; i < n; i++) {
      final v = at(i, math.max(0.06, axes[i].ratio) * t);
      i == 0 ? shape.moveTo(v.dx, v.dy) : shape.lineTo(v.dx, v.dy);
    }
    shape.close();
    canvas.drawPath(shape, Paint()..color = Sutura.signal.withValues(alpha: 0.16));
    canvas.drawPath(
      shape,
      Paint()
        ..color = Sutura.signal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    for (var i = 0; i < n; i++) {
      final v = at(i, math.max(0.06, axes[i].ratio) * t);
      canvas.drawRect(Rect.fromCenter(center: v, width: 5, height: 5), Paint()..color = Sutura.signal);
    }

    for (var i = 0; i < n; i++) {
      final v = at(i, 1.18);
      final tp = TextPainter(
        text: TextSpan(children: [
          TextSpan(text: '${axes[i].label.toUpperCase()}\n', style: SuturaText.mono.copyWith(fontSize: 9.5, color: Sutura.textMid, letterSpacing: 1)),
          TextSpan(
            text: axes[i].label == 'Marcha' ? '${axes[i].value.toStringAsFixed(1).replaceFirst('.', ',')} km' : axes[i].value.round().toString(),
            style: SuturaText.mono.copyWith(fontSize: 11, color: Sutura.textHi),
          ),
        ]),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, v - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.t != t || old.axes != axes;
}

class _Settings extends StatefulWidget {
  const _Settings();

  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  bool _confirmReset = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: app.player?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      barrierColor: Sutura.void_.withValues(alpha: 0.75),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        child: BracketPanel(
          color: Sutura.signal,
          background: Sutura.surface1Solid,
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CapsTitle('Nombre de enlace', size: 18),
              const SizedBox(height: 4),
              Text('Así te ven los demás en la red. 2 a 20 caracteres.', style: SuturaText.bodyMid),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                autofocus: true,
                maxLength: 20,
                cursorColor: Sutura.signal,
                style: SuturaText.mono.copyWith(fontSize: 16),
                decoration: const InputDecoration(
                  counterStyle: TextStyle(color: Sutura.textLow),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Sutura.lineStrong)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Sutura.signal)),
                ),
                onSubmitted: (v) => Navigator.of(context).pop(v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: ChamferButton(label: 'Cancelar', tone: ChamferTone.ghost, expand: true, onPressed: () => Navigator.of(context).pop())),
                  const SizedBox(width: 8),
                  Expanded(child: ChamferButton(label: 'Guardar', tone: ChamferTone.primary, expand: true, onPressed: () => Navigator.of(context).pop(c.text))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (name != null) app.rename(name);
  }

  void _reset() {
    if (!_confirmReset) {
      setState(() => _confirmReset = true);
      _resetTimer?.cancel();
      _resetTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _confirmReset = false);
      });
      return;
    }
    _resetTimer?.cancel();
    setState(() => _confirmReset = false);
    unawaited(app.resetProgress());
  }

  @override
  Widget build(BuildContext context) {
    final mode = app.location.mode;
    final demo = mode == LocationMode.demo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DataRow2('Ubicación', demo ? 'SIMULACIÓN' : 'GPS REAL', valueColor: demo ? Sutura.amber : Sutura.signal),
        DataRow2('Datos', app.repo.kind == 'supabase' ? 'RED SUPABASE' : 'LOCAL · SIN CUENTA'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ChamferButton(
                label: demo ? 'Usar GPS' : 'Simulación',
                icon: demo ? Icons.satellite_alt_outlined : Icons.gamepad_outlined,
                tone: ChamferTone.neutral,
                dense: true,
                expand: true,
                onPressed: () => app.start(demo ? LocationMode.gps : LocationMode.demo),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: ChamferButton(label: 'Renombrar', icon: Icons.edit_outlined, dense: true, expand: true, onPressed: _rename)),
          ],
        ),
        const SizedBox(height: 8),
        ChamferButton(
          label: _confirmReset ? 'Tocá de nuevo para confirmar' : 'Reiniciar progreso',
          icon: Icons.restart_alt,
          tone: _confirmReset ? ChamferTone.danger : ChamferTone.ghost,
          dense: true,
          expand: true,
          onPressed: _reset,
        ),
        const SizedBox(height: 14),
        Text(
          'Privacidad: tu ubicación exacta nunca sale del teléfono. A la red solo llega una posición aproximada (grilla de 250 m) y los nodos se ubican en calles públicas.',
          style: SuturaText.caption.copyWith(color: Sutura.textLow, fontWeight: FontWeight.w500, height: 1.4),
        ),
      ],
    );
  }
}
