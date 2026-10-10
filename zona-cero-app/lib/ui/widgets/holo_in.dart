import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Entrada holográfica: parpadeo de opacidad 0 → .8 → .3 → 1 con temblor horizontal.
class HoloIn extends StatefulWidget {
  const HoloIn({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<HoloIn> createState() => _HoloInState();
}

class _HoloInState extends State<HoloIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _opacity(double t) {
    if (t < 0.35) return (t / 0.35) * 0.8;
    if (t < 0.55) return 0.8 - (t - 0.35) / 0.2 * 0.5;
    return 0.3 + (t - 0.55) / 0.45 * 0.7;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Sutura.easeIn.transform(_c.value);
        final dx = t < 1 ? (1 - t) * 2 * ((t * 40).floor().isEven ? 1 : -1) : 0.0;
        return Opacity(
          opacity: _opacity(_c.value).clamp(0, 1),
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      },
      child: widget.child,
    );
  }
}
