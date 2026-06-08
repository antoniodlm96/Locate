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

  double _filteredHeading = -1;
  double _lastEmitted = -1;
  static const double _smoothing = 0.3;
  static const double _deadZone = 0.5;
  DateTime _lastEmitTime = DateTime(2000);

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

    final normA = sqrt(ax * ax + ay * ay + az * az);
    if (normA < 0.001) return;
    final gx = ax / normA;
    final gy = ay / normA;
    final gz = az / normA;

    final normM = sqrt(mx * mx + my * my + mz * mz);
    if (normM < 0.001) return;
    final mxn = mx / normM;
    final myn = my / normM;
    final mzn = mz / normM;

    // Heading of the camera direction (back camera = -Z device axis)
    // using rotation matrix: det(v,m,g) for sin, v·m - (v·g)(m·g) for cos
    // v = camera direction = [0, 0, -1]
    // sinTerm = myn*gx - mxn*gy = determinant(v, m, g)
    // cosTerm = -mzn + gz*(mxn*gx + myn*gy + mzn*gz) = v·m - (v·g)(m·g)
    final sinTerm = myn * gx - mxn * gy;
    final cosTerm = -mzn + gz * (mxn * gx + myn * gy + mzn * gz);

    // Fallback to Y-axis heading when camera direction is degenerate (phone flat)
    var sinDeg = sinTerm;
    var cosDeg = cosTerm;
    if (sinDeg * sinDeg + cosDeg * cosDeg < 0.001) {
      sinDeg = mzn * gx - mxn * gz;
      cosDeg = myn - gy * (mxn * gx + myn * gy + mzn * gz);
    }

    var rawHeading = atan2(sinDeg, cosDeg) * 180 / pi;
    rawHeading = (rawHeading + 360) % 360;

    if (_filteredHeading < 0) {
      _filteredHeading = rawHeading;
    } else {
      var diff = rawHeading - _filteredHeading;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;
      _filteredHeading += diff * _smoothing;
      if (_filteredHeading < 0) _filteredHeading += 360;
      if (_filteredHeading >= 360) _filteredHeading -= 360;
    }

    if (_lastEmitted < 0) {
      _lastEmitted = _filteredHeading;
      _lastEmitTime = DateTime.now();
      _headingController.add(_filteredHeading);
      return;
    }

    if (DateTime.now().difference(_lastEmitTime).inMilliseconds < 50) return;

    var emitDiff = _filteredHeading - _lastEmitted;
    if (emitDiff > 180) emitDiff -= 360;
    if (emitDiff < -180) emitDiff += 360;
    if (emitDiff.abs() < _deadZone) return;

    _lastEmitted = _filteredHeading;
    _lastEmitTime = DateTime.now();
    _headingController.add(_filteredHeading);
  }

  void stop() {
    _accSub?.cancel();
    _magSub?.cancel();
    _headingController.close();
  }
}
