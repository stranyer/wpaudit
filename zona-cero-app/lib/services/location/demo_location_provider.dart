import 'dart:async';
import 'dart:math' as math;

import '../../core/core.dart';
import 'location_types.dart';

/// Ubicación simulada: joystick, caminata automática a un punto y teletransporte.
class DemoLocationProvider implements LocationProvider {
  DemoLocationProvider(LatLng start, {this.speedMps = 4.5}) : _position = start;

  final double speedMps;
  LatLng _position;
  double? _heading;
  double _vx = 0, _vy = 0; // -1..1 (x = este, y = norte)
  LatLng? _target;
  double _stopAtM = 12;
  Timer? _timer;
  DateTime _lastTick = DateTime.now();
  void Function(LocationFix)? _onFix;

  @override
  bool get isSimulated => true;

  LatLng get position => _position;
  bool get walking => _target != null;

  @override
  Future<void> start(void Function(LocationFix) onFix, void Function(LocationError) onError) async {
    _onFix = onFix;
    _emit();
  }

  @override
  void stop() {
    _apply(0, 0, 1);
    _onFix = null;
  }

  /// Dirección (pantalla ya convertida a este/norte); (0,0) detiene.
  void setVelocity(double x, double y, [double multiplier = 1]) {
    _target = null;
    _apply(x, y, multiplier);
  }

  void walkTo(LatLng p, {double stopAtM = 12}) {
    if (haversineM(_position, p) <= stopAtM) return;
    _target = p;
    _stopAtM = stopAtM;
    _steer();
  }

  void teleport(LatLng p) {
    _target = null;
    _apply(0, 0, 1);
    _heading = bearingDeg(_position, p);
    _position = p;
    _emit(jump: true);
  }

  void _steer() {
    final t = _target;
    if (t == null) return;
    final b = bearingDeg(_position, t) * math.pi / 180;
    _apply(math.sin(b), math.cos(b), 1.6);
  }

  void _apply(double x, double y, double multiplier) {
    final len = math.sqrt(x * x + y * y);
    final k = len > 1 ? 1 / len : 1.0;
    _vx = x * k * multiplier;
    _vy = y * k * multiplier;
    final moving = _vx != 0 || _vy != 0;
    if (moving && _timer == null) {
      _lastTick = DateTime.now();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    } else if (!moving) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _tick() {
    final now = DateTime.now();
    final dt = math.min(0.5, now.difference(_lastTick).inMicroseconds / 1e6);
    _lastTick = now;
    final north = _vy * speedMps * dt;
    final east = _vx * speedMps * dt;
    if (north == 0 && east == 0) return;
    _heading = (math.atan2(east, north) * 180 / math.pi + 360) % 360;
    _position = offsetM(_position, north, east);
    final t = _target;
    if (t != null) {
      if (haversineM(_position, t) <= _stopAtM) {
        _target = null;
        _apply(0, 0, 1);
      } else {
        _steer();
      }
    }
    _emit();
  }

  void _emit({bool jump = false}) {
    _onFix?.call(LocationFix(
      position: _position,
      accuracyM: 5,
      headingDeg: _heading,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      jump: jump,
    ));
  }
}
