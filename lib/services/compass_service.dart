import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

class CompassService {
  final _headingController = StreamController<double>.broadcast();
  StreamSubscription? _accSub;
  StreamSubscription? _magSub;

  List<double> _acc = [0, 0, 9.8];
  List<double> _mag = [0, 0, 0];
  bool _hasAcc = false;
  bool _hasMag = false;

  Stream<double> get headingStream => _headingController.stream;

  void start() {
    _accSub = accelerometerEventStream().listen((event) {
      _acc = [event.x, event.y, event.z];
      _hasAcc = true;
      _tryComputeHeading();
    });

    _magSub = magnetometerEventStream().listen((event) {
      _mag = [event.x, event.y, event.z];
      _hasMag = true;
      _tryComputeHeading();
    });
  }

  void _tryComputeHeading() {
    if (!_hasAcc || !_hasMag) return;

    final ax = _acc[0];
    final ay = _acc[1];
    final az = _acc[2];
    final mx = _mag[0];
    final my = _mag[1];
    final mz = _mag[2];

    final invSqrt = (ax * ax + ay * ay + az * az);
    if (invSqrt == 0) return;
    final inv = 1.0 / sqrt(invSqrt);

    final gx = ax * inv;
    final gy = ay * inv;
    final gz = az * inv;

    final hx = mx * (gz * gz + gy * gy) - mz * gx * gy - my * gx * gz;
    final hy = my * (gz * gz + gx * gx) - mz * gy * gx - mx * gy * gz;

    var heading = atan2(hy, hx) * 180 / pi;
    heading = (heading + 360) % 360;

    _headingController.add(heading);
  }

  void stop() {
    _accSub?.cancel();
    _magSub?.cancel();
    _headingController.close();
  }
}
