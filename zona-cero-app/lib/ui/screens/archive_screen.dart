import 'package:flutter/material.dart';

import '../../content/lore.dart';
import '../../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/holo_in.dart';
import '../widgets/screen_frame.dart';

/// Pestaña ARCHIVO: documentos recuperados (informes, diarios, transmisiones).
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  int _tab = 0;

  static const _cats = [null, LoreCategory.informe, LoreCategory.diario, LoreCategory.transmision, LoreCategory.corpus];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final unlocked = loreFiles.where(app.isLoreUnlocked).length;
        final cat = _cats[_tab];
        final files = loreFiles.where((f) => cat == null || f.category == cat).toList();
        final badges = <int, int>{
          for (final (i, c) in _cats.indexed)
            i: loreFiles.where((f) => (c == null || f.category == c) && app.isLoreUnlocked(f) && !app.readLore.contains(f.id)).length,
        };
        return TabScreenFrame(
          title: 'Archivo',
          code: 'DESAM  //  ARCHIVO',
          note: 'Que no se olvide',
          trailing: Text.rich(
            TextSpan(children: [
              TextSpan(text: unlocked.toString().padLeft(2, '0'), style: const TextStyle(color: Sutura.textHi)),
              TextSpan(text: ' / ${loreFiles.length.toString().padLeft(2, '0')}', style: const TextStyle(color: Sutura.textLow)),
            ]),
            style: SuturaText.mono.copyWith(fontSize: 16),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: SegmentTabs(
                  labels: [for (final c in _cats) c?.label ?? 'Todo'],
                  index: _tab,
                  badges: badges,
                  scrollable: true,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                  itemCount: files.length,
                  itemBuilder: (context, i) => _FileRow(file: files[i]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file});

  final LoreFile file;

  @override
  Widget build(BuildContext context) {
    final open = app.isLoreUnlocked(file);
    final unread = open && !app.readLore.contains(file.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: open
            ? () => Navigator.of(context).push(PageRouteBuilder<void>(
                  transitionDuration: Sutura.heavy,
                  reverseTransitionDuration: Sutura.base,
                  pageBuilder: (_, _, _) => LoreReader(file: file),
                  transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: CurvedAnimation(parent: a, curve: Sutura.easeIn), child: child),
                ))
            : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: open ? Sutura.surface1Solid : Sutura.void_,
            border: Border(
              left: BorderSide(color: unread ? Sutura.accent : (open ? Sutura.lineBright : Sutura.lineHair), width: 4),
              top: const BorderSide(color: Sutura.lineHair),
              right: const BorderSide(color: Sutura.lineHair),
              bottom: const BorderSide(color: Sutura.lineHair),
            ),
          ),
          child: Row(
            children: [
              Icon(
                open ? _icon(file.category) : Icons.lock_outline,
                size: 20,
                color: open ? (unread ? Sutura.textHi : Sutura.textMid) : Sutura.textLow,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(file.code, style: SuturaText.mono.copyWith(fontSize: 10.5, color: open ? Sutura.textLow : Sutura.lineStrong, letterSpacing: 1)),
                        const Spacer(),
                        if (unread) Text('NUEVO', style: SuturaText.label.copyWith(fontSize: 12, color: Sutura.accent, letterSpacing: 2.4)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      open ? file.title : '██████ ███ ████████',
                      style: SuturaText.body.copyWith(color: open ? Sutura.textHi : Sutura.textLow, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      open ? '${file.date} · ${file.author}' : 'BLOQUEADO · ${file.unlock.hint}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SuturaText.caption.copyWith(fontWeight: FontWeight.w500, color: open ? Sutura.textLow : Sutura.caution.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _icon(LoreCategory c) => switch (c) {
        LoreCategory.informe => Icons.description_outlined,
        LoreCategory.diario => Icons.menu_book_outlined,
        LoreCategory.transmision => Icons.settings_input_antenna,
        LoreCategory.corpus => Icons.biotech_outlined,
      };
}

/// Lector de documento: hoja mecanografiada con sello.
class LoreReader extends StatefulWidget {
  const LoreReader({super.key, required this.file});

  final LoreFile file;

  @override
  State<LoreReader> createState() => _LoreReaderState();
}

class _LoreReaderState extends State<LoreReader> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => app.markLoreRead(widget.file.id));
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.file;
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: Sutura.void_,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, pad.top + 10, 14, 10),
            child: Row(
              children: [
                SquareIconButton(icon: Icons.arrow_back, onPressed: () => Navigator.of(context).pop(), tooltip: 'Volver'),
                const SizedBox(width: 12),
                Expanded(child: Text('${f.category.label} // ${f.code}'.toUpperCase(), style: SuturaText.label.copyWith(fontSize: 12.5, color: Sutura.textMid))),
              ],
            ),
          ),
          const HairDivider(),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(14, 16, 14, pad.bottom + 30),
              child: HoloIn(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
                  decoration: BoxDecoration(
                    color: const Color(0xFF15140F),
                    border: Border.all(color: const Color(0xFF34302A)),
                    boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 10))],
                  ),
                  child: CustomPaint(
                    painter: const _RuledPainter(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(f.code, style: SuturaText.paper.copyWith(fontSize: 12, color: Sutura.textPaper.withValues(alpha: 0.6))),
                                  const SizedBox(height: 2),
                                  Text(f.date, style: SuturaText.paper.copyWith(fontSize: 12, color: Sutura.textPaper.withValues(alpha: 0.6))),
                                ],
                              ),
                            ),
                            if (f.stamp != null) _Stamp(f.stamp!),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          f.title.toUpperCase(),
                          style: SuturaText.paper.copyWith(fontSize: 18, fontWeight: FontWeight.w700, height: 1.3, color: const Color(0xFFEDE6D3)),
                        ),
                        const SizedBox(height: 4),
                        Text(f.author, style: SuturaText.paper.copyWith(fontSize: 12.5, fontStyle: FontStyle.italic, color: Sutura.textPaper.withValues(alpha: 0.7))),
                        const SizedBox(height: 18),
                        Text(f.body, style: SuturaText.paper.copyWith(fontSize: 14.5, height: 1.62)),
                        const SizedBox(height: 22),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text('— fin del registro —', style: SuturaText.paper.copyWith(fontSize: 12, color: Sutura.textPaper.withValues(alpha: 0.4))),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.14,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(border: Border.all(color: Sutura.danger.withValues(alpha: 0.75), width: 2)),
        child: Text(text.toUpperCase(), style: SuturaText.stamp.copyWith(color: Sutura.danger.withValues(alpha: 0.8), fontSize: 15)),
      ),
    );
  }
}

/// Renglones tenues y margen rojo de hoja de expediente.
class _RuledPainter extends CustomPainter {
  const _RuledPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = const Color(0x0FD8D2C2);
    for (double y = 30; y < size.height; y += 23.4) {
      canvas.drawLine(Offset(-20, y), Offset(size.width + 20, y), line);
    }
    canvas.drawLine(const Offset(-8, -22), Offset(-8, size.height + 28), Paint()..color = const Color(0x33EE3B45));
  }

  @override
  bool shouldRepaint(_RuledPainter oldDelegate) => false;
}
