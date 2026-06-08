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

class _ARViewScreenState extends State<ARViewScreen> {
  List<CameraDescription>? _cameras;
  CameraController? _cameraController;
  final List<SavedObject> _objects = [];
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSub;
  final CompassService _compassService = CompassService();
  StreamSubscription<double>? _headingSub;
  bool _initialized = false;
  List<_ObjectWithDistance> _sortedObjects = [];

  final ValueNotifier<double> _headingNotifier = ValueNotifier(0);

  double _gz = 0;
  bool _hasGravity = false;
  double _smoothedTilt = 0;
  final ValueNotifier<double> _tiltNotifier = ValueNotifier(0);
  StreamSubscription? _accSub;

  @override
  void initState() {
    super.initState();
    _accSub = accelerometerEventStream().listen((event) {
      final norm = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (norm > 0) {
        _gz = event.z / norm;
        _hasGravity = true;
        final rawTilt = (1.0 - _gz.abs()).clamp(0.0, 1.0);
        _smoothedTilt += (rawTilt - _smoothedTilt) * 0.06;
        final arOpacity = ((_smoothedTilt - 0.15) / 0.45).clamp(0.0, 1.0);
        if ((arOpacity - _tiltNotifier.value).abs() > 0.005) {
          _tiltNotifier.value = arOpacity;
        }
      }
    });
    _init();
  }

  void _onHeading(double h) {
    _headingNotifier.value = h;
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
    _headingNotifier.dispose();
    _tiltNotifier.dispose();
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
        title: ValueListenableBuilder<double>(
          valueListenable: _headingNotifier,
          builder: (_, h, __) => Text('${h.toStringAsFixed(0)}°'),
        ),
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          if (_currentPosition != null)
            ValueListenableBuilder<double>(
              valueListenable: _tiltNotifier,
              builder: (_, arOpacity, __) {
                final radarOpacity = 1.0 - arOpacity.clamp(0.0, 1.0);
                return Opacity(
                  opacity: radarOpacity,
                  child: _buildRadarView(),
                );
              },
            ),
          if (_cameraController != null && _cameraController!.value.isInitialized)
            ValueListenableBuilder<double>(
              valueListenable: _tiltNotifier,
              builder: (_, arOpacity, __) {
                return Opacity(
                  opacity: arOpacity.clamp(0.0, 1.0),
                  child: RepaintBoundary(
                    child: Stack(
                      children: [
                        CameraPreview(_cameraController!),
                        if (_currentPosition != null)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final topPad = MediaQuery.of(context).padding.top;
                              return ValueListenableBuilder<double>(
                                valueListenable: _headingNotifier,
                                builder: (_, heading, __) {
                                  return CustomPaint(
                                    size: Size(constraints.maxWidth, constraints.maxHeight),
                                    painter: ARPainter(
                                      objects: _objects,
                                      currentPosition: _currentPosition!,
                                      heading: heading,
                                      fov: 180,
                                      screenSize: Size(constraints.maxWidth, constraints.maxHeight),
                                      topPadding: topPad,
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
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
      child: ValueListenableBuilder<double>(
        valueListenable: _headingNotifier,
        builder: (_, heading, __) {
          return CustomPaint(
            size: Size.infinite,
            painter: RadarPainter(
              objects: _sortedObjects,
              heading: heading,
            ),
          );
        },
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
      height: 140,
      color: Colors.black54,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Objetos cercanos',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _sortedObjects.length,
              itemBuilder: (context, index) {
                final item = _sortedObjects[index];
                return Container(
                  width: 120,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: item.color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: item.color.withOpacity(0.4)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item.icon, color: item.color, size: 28),
                      const SizedBox(height: 4),
                      Text(
                        item.object.name,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        formatDistance(item.distance),
                        style: TextStyle(color: item.color.withOpacity(0.8), fontSize: 11),
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

class RadarPainter extends CustomPainter {
  final List<_ObjectWithDistance> objects;
  final double heading;

  RadarPainter({required this.objects, required this.heading});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.45);
    final radius = math.min(size.width, size.height) * 0.42;

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
      _drawText(canvas, entry.key, lx, ly, fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white70);
    }

    final headPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final headPath = Path()
      ..moveTo(center.dx, center.dy - radius - 10)
      ..lineTo(center.dx - 9, center.dy - radius + 5)
      ..lineTo(center.dx + 9, center.dy - radius + 5)
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
      _drawText(canvas, 'Sin objetos cerca', center.dx, center.dy + 35,
          fontSize: 16, color: Colors.white38);
      return;
    }

    final maxDist = objects.map((o) => o.distance).reduce(math.max);
    final radarMax = math.max(50.0, math.min(maxDist * 1.3, 500.0));

    for (final obj in objects) {
      final angleDiff = obj.bearing - heading;
      final angleRad = angleDiff * math.pi / 180;

      final distFactor = (obj.distance / radarMax).clamp(0.0, 1.0);
      final objR = distFactor * radius * 0.88;
      final ox = center.dx + objR * math.sin(angleRad);
      final oy = center.dy - objR * math.cos(angleRad);

      canvas.drawCircle(Offset(ox, oy), 7, Paint()..color = obj.color);
      canvas.drawCircle(Offset(ox, oy), 7, Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);

      final labelOffset = (objR < radius * 0.3) ? const Offset(12, -10) : const Offset(10, -8);
      _drawText(canvas, obj.object.name, ox + labelOffset.dx, oy + labelOffset.dy,
          fontSize: 13, fontWeight: FontWeight.w600, color: obj.color);
      _drawText(canvas, formatDistance(obj.distance), ox + labelOffset.dx, oy + labelOffset.dy + 16,
          fontSize: 11, color: Colors.white70);
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
  bool shouldRepaint(RadarPainter oldDelegate) {
    return (oldDelegate.heading - heading).abs() > 0.5 || oldDelegate.objects != objects;
  }
}
