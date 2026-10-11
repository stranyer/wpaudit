import 'package:flutter/material.dart';

import '../../ui/theme/tokens.dart';
import '../../ui/widgets/holo_in.dart';
import '../game_map.dart';
import '../map_events.dart';

/// Avisos ambientales del mapa ("Disparos a lo lejos · 420 m · NO"), como
/// intercepciones de radio: un punto que late, el texto y la distancia.
class MapEventFeed extends StatelessWidget {
  const MapEventFeed({super.key, required this.camera});

  final GameMapController camera;

  static Color colorOf(AmbientTone t) => switch (t) {
    AmbientTone.hostile => const Color(0xFFE5574C),
    AmbientTone.hazard => Sutura.amber,
    AmbientTone.signal => Sutura.signal,
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<AmbientEvent>>(
      valueListenable: camera.events,
      builder: (context, events, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in events)
            HoloIn(
              key: ValueKey('ev${e.id}'),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _EventRow(event: e, color: colorOf(e.tone)),
              ),
            ),
        ],
      ),
    );
  }
}

class _EventRow extends StatefulWidget {
  const _EventRow({required this.event, required this.color});

  final AmbientEvent event;
  final Color color;

  @override
  State<_EventRow> createState() => _EventRowState();
}

class _EventRowState extends State<_EventRow> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xE60B0C0D), Color(0x990B0C0D), Color(0x000B0C0D)], stops: [0, 0.75, 1]),
        border: Border(left: BorderSide(color: c, width: 2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.25, end: 1.0).animate(_blink),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: c.withValues(alpha: 0.7), blurRadius: 4)],
              ),
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: widget.event.text.toUpperCase()),
                  TextSpan(
                    text: '   ${widget.event.detail}',
                    style: const TextStyle(color: Sutura.textLow, fontSize: 9.5, letterSpacing: 1.2),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SuturaText.label.copyWith(fontSize: 10.5, letterSpacing: 1.5, color: Sutura.textHi),
            ),
          ),
        ],
      ),
    );
  }
}
