import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/saved_object.dart';
import '../services/database_service.dart';
import '../services/compass_service.dart';
import '../widgets/ar_painter.dart';
import 'register_object_screen.dart';

class _ObjectWithDistance {
  final SavedObject object;
  final double distance;
  final double bearing;
  final Color color;
  final IconData icon;

  _ObjectWithDistance({
    required this.object,
    required this.distance,
    required this.bearing,
    required this.color,
    required this.icon,
  });
}

String formatDistance(double meters) {
  if (meters < 1) return '${(meters * 100).round()} cm';
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

class ARViewScreen extends StatefulWidget {
  const ARViewScreen({super.key});

  @override
  State<ARViewScreen> createState() => _ARViewScreenState();
}

class _ARViewScreenState extends State<ARViewScreen>
    with SingleTickerProviderStateMixin {
  List<CameraDescription>? _cameras;
  CameraController? _cameraController;
  final List<SavedObject> _objects = [];
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSub;
  final CompassService _compassService = CompassService();
  StreamSubscription<double>? _headingSub;
  bool _initialized = false;
  List<_ObjectWithDistance> _sortedObjects = [];

  double _targetHeading = 0;
  double _displayHeading = 0;
  late final AnimationController _ticker;

  double _gz = 0;
  bool _hasGravity = false;
  double _smoothedTilt = 0;
  double _arOpacity = 0;
  double _radarOpacity = 1;
  StreamSubscription? _accSub;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_onTick);
    _ticker.repeat();
    _accSub = accelerometerEventStream().listen((event) {
      final norm = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (norm > 0) {
        _gz = event.z / norm;
        _hasGravity = true;
      }
    });
    _init();
  }

  void _onTick() {
    if (!mounted) return;
    var diff = _targetHeading - _displayHeading;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

    if (diff.abs() < 0.05) {
      _displayHeading = _targetHeading;
    } else {
      _displayHeading += diff * 0.25;
      if (_displayHeading < 0) _displayHeading += 360;
      if (_displayHeading >= 360) _displayHeading -= 360;
    }

    if (_hasGravity) {
      final rawTilt = (1.0 - _gz.abs()).clamp(0.0, 1.0);
      _smoothedTilt += (rawTilt - _smoothedTilt) * 0.06;
      _arOpacity = ((_smoothedTilt - 0.15) / 0.45).clamp(0.0, 1.0);
      _radarOpacity = 1.0 - _arOpacity;
    }

    setState(() {});
  }

  void _onHeading(double h) {
    _targetHeading = h;
  }

  Future<void> _init() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) return;

      _cameraController = CameraController(
        _cameras!.first,
        ResolutionPreset.medium,
      );
      await _cameraController!.initialize();

      final objects = await DatabaseService.instance.getActiveObjects();
      if (!mounted) return;

      setState(() => _objects.addAll(objects));

      _compassService.start();
      _headingSub = _compassService.headingStream.listen(_onHeading);

      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        ),
      ).listen((pos) {
        if (mounted) {
          setState(() {
            _currentPosition = pos;
            _updateSortedList();
          });
        }
      });

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );

      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _initialized = true;
          _updateSortedList();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _initialized = true);
      }
    }
  }

  void _updateSortedList() {
    if (_currentPosition == null) {
      _sortedObjects = [];
      return;
    }
    final list = <_ObjectWithDistance>[];
    for (final obj in _objects) {
      final dist = Geolocator.distanceBetween(
        _currentPosition!.latitude, _currentPosition!.longitude,
        obj.latitude, obj.longitude,
      );
      final bearing = Geolocator.bearingBetween(
        _currentPosition!.latitude, _currentPosition!.longitude,
        obj.latitude, obj.longitude,
      );
      final typeEntry = _findTypeEntry(obj.type);
      list.add(_ObjectWithDistance(
        object: obj,
        distance: dist,
        bearing: bearing,
        color: typeEntry?['color'] as Color? ?? Colors.white,
        icon: typeEntry?['icon'] as IconData? ?? Icons.place,
      ));
    }
    list.sort((a, b) => a.distance.compareTo(b.distance));
    _sortedObjects = list;
  }

  Map<String, dynamic>? _findTypeEntry(String type) {
    for (final t in objectTypes) {
      if (t['name'] == type) return t;
    }
    return null;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _accSub?.cancel();
    _cameraController?.dispose();
    _headingSub?.cancel();
    _positionSub?.cancel();
    _compassService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('${_displayHeading.toStringAsFixed(0)}°'),
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          if (_currentPosition != null)
            Opacity(
              opacity: _radarOpacity.clamp(0.0, 1.0),
              child: _buildRadarView(),
            ),
          if (_cameraController != null && _cameraController!.value.isInitialized)
            Opacity(
              opacity: _arOpacity.clamp(0.0, 1.0),
              child: RepaintBoundary(
                child: Stack(
                  children: [
                    CameraPreview(_cameraController!),
                    if (_currentPosition != null)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return CustomPaint(
                            size: Size(constraints.maxWidth, constraints.maxHeight),
                            painter: ARPainter(
                              objects: _objects,
                              currentPosition: _currentPosition!,
                              heading: _displayHeading,
                              fov: 180,
                              screenSize: Size(constraints.maxWidth, constraints.maxHeight),
                            ),
                          );
                        },
                      ),
                    if (_currentPosition != null && _arOpacity > 0.3)
                      Positioned(
                        bottom: 120,
                        left: 0,
                        right: 0,
                        height: 40,
                        child: Opacity(
                          opacity: ((_arOpacity - 0.3) / 0.7).clamp(0.0, 1.0),
                          child: _buildCompassArc(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (_currentPosition == null)
            const Center(
              child: Text(
                'Esperando señal GPS...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRadarView() {
    return Container(
      color: const Color(0xFF0D1117),
      child: CustomPaint(
        size: Size.infinite,
        painter: RadarPainter(
          objects: _sortedObjects,
          heading: _displayHeading,
        ),
      ),
    );
  }

  Widget _buildCompassArc() {
    if (_sortedObjects.isEmpty) return const SizedBox.shrink();
    return CustomPaint(
      size: const Size(double.infinity, 40),
      painter: CompassArcPainter(
        objects: _sortedObjects,
        heading: _displayHeading,
      ),
    );
  }

  Widget _buildBottomList() {
    if (_objects.isEmpty) {
      return Container(
        height: 60,
        alignment: Alignment.center,
        color: Colors.black54,
        child: TextButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RegisterObjectScreen()),
          ),
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text(
            'Registra tu primer objeto',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Container(
      height: 120,
      color: Colors.black54,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Objetos cercanos',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _sortedObjects.length,
              itemBuilder: (context, index) {
                final item = _sortedObjects[index];
                return Container(
                  width: 100,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: item.color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: item.color.withOpacity(0.4)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item.icon, color: item.color, size: 24),
                      const SizedBox(height: 2),
                      Text(
                        item.object.name,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        formatDistance(item.distance),
                        style: TextStyle(color: item.color.withOpacity(0.8), fontSize: 10),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CompassArcPainter extends CustomPainter {
  final List<_ObjectWithDistance> objects;
  final double heading;

  CompassArcPainter({required this.objects, required this.heading});

  @override
  void paint(Canvas canvas, Size size) {
    if (objects.isEmpty) return;
    final center = Offset(size.width / 2, size.height + 5);
    final radius = size.height * 1.5;
    final arcPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi,
      false,
      arcPaint,
    );

    final centerDot = Paint()..color = Colors.white70;
    canvas.drawCircle(Offset(size.width / 2, size.height), 2, centerDot);

    for (final obj in objects) {
      var angleDiff = obj.bearing - heading;
      while (angleDiff > 180) angleDiff -= 360;
      while (angleDiff < -180) angleDiff += 360;

      final angleRad = math.pi + angleDiff * math.pi / 180;
      final clamped = angleRad.clamp(0.0, math.pi).toDouble();
      final x = center.dx + radius * math.cos(clamped);
      final y = center.dy + radius * math.sin(clamped);

      canvas.drawCircle(
        Offset(x, y.clamp(0, size.height + 20).toDouble()),
        3,
        Paint()..color = obj.color,
      );
    }
  }

  @override
  bool shouldRepaint(CompassArcPainter oldDelegate) => true;
}

class RadarPainter extends CustomPainter {
  final List<_ObjectWithDistance> objects;
  final double heading;

  RadarPainter({required this.objects, required this.heading});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.42);
    final radius = math.min(size.width, size.height) * 0.35;

    final bgPaint = Paint()..color = const Color(0xFF0D1117);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final glow = Paint()
      ..color = const Color(0xFF1A1A3E).withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
    canvas.drawCircle(center, radius, glow);

    final ringPaint = Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * i / 4, ringPaint);
    }

    final crossPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(center.dx - radius, center.dy), Offset(center.dx + radius, center.dy), crossPaint);
    canvas.drawLine(Offset(center.dx, center.dy - radius), Offset(center.dx, center.dy + radius), crossPaint);

    final cardinals = <String, double>{
      'N': -heading,
      'E': 90 - heading,
      'S': 180 - heading,
      'O': 270 - heading,
    };
    for (final entry in cardinals.entries) {
      final angleRad = entry.value * math.pi / 180;
      final lx = center.dx + (radius + 18) * math.sin(angleRad);
      final ly = center.dy - (radius + 18) * math.cos(angleRad);
      _drawText(canvas, entry.key, lx, ly, fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white60);
    }

    final headPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final headPath = Path()
      ..moveTo(center.dx, center.dy - radius - 8)
      ..lineTo(center.dx - 7, center.dy - radius + 4)
      ..lineTo(center.dx + 7, center.dy - radius + 4)
      ..close();
    canvas.drawPath(headPath, headPaint);

    final hLinePaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(center.dx, center.dy - radius + 4),
      Offset(center.dx, center.dy - radius - 18),
      hLinePaint,
    );

    canvas.drawCircle(center, 3, Paint()..color = Colors.white70);

    if (objects.isEmpty) {
      _drawText(canvas, 'Sin objetos cerca', center.dx, center.dy + 30,
          fontSize: 14, color: Colors.white38);
      return;
    }

    final maxDist = objects.map((o) => o.distance).reduce(math.max);
    final radarMax = math.max(50.0, math.min(maxDist * 1.3, 500.0));

    if (maxDist > 0) {
      _drawText(canvas, '${radarMax.round()}m', center.dx, center.dy - radius - 26,
          fontSize: 10, color: Colors.white38);
    }

    for (final obj in objects) {
      final angleDiff = obj.bearing - heading;
      final angleRad = angleDiff * math.pi / 180;

      final distFactor = (obj.distance / radarMax).clamp(0.0, 1.0);
      final objR = distFactor * radius * 0.88;
      final ox = center.dx + objR * math.sin(angleRad);
      final oy = center.dy - objR * math.cos(angleRad);

      canvas.drawCircle(Offset(ox, oy), 5, Paint()..color = obj.color);

      final labelOffset = (objR < radius * 0.3) ? const Offset(10, -8) : const Offset(8, -6);
      _drawText(canvas, obj.object.name, ox + labelOffset.dx, oy + labelOffset.dy,
          fontSize: 11, fontWeight: FontWeight.w600, color: obj.color);
      _drawText(canvas, formatDistance(obj.distance), ox + labelOffset.dx, oy + labelOffset.dy + 14,
          fontSize: 10, color: Colors.white70);
    }
  }

  void _drawText(Canvas canvas, String text, double x, double y,
      {double fontSize = 12, FontWeight fontWeight = FontWeight.normal, Color color = Colors.white}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          shadows: const [Shadow(blurRadius: 6, color: Color(0xCC000000))],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y));
  }

  @override
  bool shouldRepaint(RadarPainter oldDelegate) => true;
}
