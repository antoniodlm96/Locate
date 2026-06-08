import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

class CompassService {
  final _headingController = StreamController<double>.broadcast();
  StreamSubscription? _accSub;
  StreamSubscription? _magSub;
  StreamSubscription? _gyroSub;

  List<double> _acc = [0, 0, 9.8];
  List<double> _mag = [0, 0, 0];
  bool _hasAcc = false;
  bool _hasMag = false;

  double _heading = -1;
  double _lastEmitted = -1;
  DateTime _lastEmitTime = DateTime(2000);
  static const double _deadZone = 1.0;
  static const int _minIntervalMs = 80;

  int _lastGyroTime = 0;
  static const double _driftCorrection = 0.02;

  Stream<double> get headingStream => _headingController.stream;

  void start() {
    _accSub = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((event) {
      _acc = [event.x, event.y, event.z];
      _hasAcc = true;
      _tryComputeHeading();
    });

    _magSub = magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((event) {
      _mag = [event.x, event.y, event.z];
      _hasMag = true;
      _tryComputeHeading();
    });

    _gyroSub = gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval).listen((event) {
      if (_heading < 0) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      if (_lastGyroTime == 0) {
        _lastGyroTime = now;
        return;
      }
      final dt = (now - _lastGyroTime) / 1000.0;
      _lastGyroTime = now;
      if (dt <= 0 || dt > 0.1) return;

      // Project gyro angular velocity onto gravity direction to get heading change
      final normA = sqrt(_acc[0] * _acc[0] + _acc[1] * _acc[1] + _acc[2] * _acc[2]);
      if (normA < 0.001) return;
      final gx = _acc[0] / normA;
      final gy = _acc[1] / normA;
      final gz = _acc[2] / normA;

      final headingRate = event.x * gx + event.y * gy + event.z * gz;
      _heading += headingRate * dt * 180 / pi;
      _heading = (_heading + 360) % 360;

      _tryEmit(_heading);
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

    // Camera (-Z axis) heading - for vertical/AR mode
    final camSin = myn * gx - mxn * gy;
    final camCos = -mzn + gz * (mxn * gx + myn * gy + mzn * gz);

    // Y-axis (top of phone) heading - for horizontal/radar mode
    final ySin = mzn * gx - mxn * gz;
    final yCos = myn - gy * (mxn * gx + myn * gy + mzn * gz);

    // Blend based on tilt: gz² = 0 when vertical, = 1 when flat
    final flatness = (gz * gz).clamp(0.0, 1.0);
    final blend = flatness < 0.08 ? 0.0 : flatness > 0.85 ? 1.0 : flatness;

    final sinDeg = camSin * (1 - blend) + ySin * blend;
    final cosDeg = camCos * (1 - blend) + yCos * blend;

    var magHeading = atan2(sinDeg, cosDeg) * 180 / pi;
    magHeading = (magHeading + 360) % 360;

    if (_heading < 0) {
      _heading = magHeading;
      _tryEmit(_heading);
      return;
    }

    // Slow correction of gyro drift using magnetometer absolute heading
    var diff = magHeading - _heading;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    _heading += diff * _driftCorrection;
    if (_heading < 0) _heading += 360;
    if (_heading >= 360) _heading -= 360;
  }

  void _tryEmit(double heading) {
    if (_lastEmitted < 0) {
      _lastEmitted = heading;
      _lastEmitTime = DateTime.now();
      _headingController.add(heading);
      return;
    }

    if (DateTime.now().difference(_lastEmitTime).inMilliseconds < _minIntervalMs) return;

    var emitDiff = heading - _lastEmitted;
    if (emitDiff > 180) emitDiff -= 360;
    if (emitDiff < -180) emitDiff += 360;
    if (emitDiff.abs() < _deadZone) return;

    _lastEmitted = heading;
    _lastEmitTime = DateTime.now();
    _headingController.add(heading);
  }

  void stop() {
    _accSub?.cancel();
    _magSub?.cancel();
    _gyroSub?.cancel();
    _headingController.close();
  }
}
