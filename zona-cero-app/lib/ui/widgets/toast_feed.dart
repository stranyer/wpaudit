import 'package:flutter/widgets.dart';

import '../../state/ui_controller.dart';
import '../theme/tokens.dart';
import 'holo_in.dart';

/// Feed de avisos arriba a la izquierda, como el registro de una terminal de red.
class ToastFeed extends StatelessWidget {
  const ToastFeed({super.key, required this.ui});

  final UiController ui;

  static Color _color(ToastTone t) => switch (t) {
        ToastTone.good => Sutura.fine,
        ToastTone.loot => Sutura.amber,
        ToastTone.warn => Sutura.caution,
        ToastTone.bad => Sutura.danger,
        ToastTone.network => Sutura.signal,
        ToastTone.info => Sutura.textMid,
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ui,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in ui.toasts)
            HoloIn(
              key: ValueKey(t.id),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                  decoration: BoxDecoration(
                    color: Sutura.surface1,
                    border: Border(left: BorderSide(color: _color(t.tone), width: 2)),
                  ),
                  child: Text(
                    t.text,
                    style: SuturaText.caption.copyWith(color: _color(t.tone) == Sutura.textMid ? Sutura.textHi : _color(t.tone), letterSpacing: 0.6, fontSize: 12.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
