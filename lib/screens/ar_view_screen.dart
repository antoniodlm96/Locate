import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/saved_object.dart';
import '../models/object_group.dart';
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
  List<ObjectGroup> _groups = [];
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSub;
  final CompassService _compassService = CompassService();
  StreamSubscription<double>? _headingSub;
  bool _initialized = false;
  List<_ObjectWithDistance> _sortedObjects = [];

  final ValueNotifier<double> _headingNotifier = ValueNotifier(0);

  double _gz = 0;
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
      final groups = await DatabaseService.instance.getAllGroups();
      if (!mounted) return;

      setState(() {
        _objects.addAll(objects);
        _groups = groups;
      });

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
          builder: (_, h, __) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.35),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.navigation, size: 16, color: Colors.white70),
                const SizedBox(width: 6),
                Text(
                  '${h.toStringAsFixed(0)}°',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
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
                              final topPad = MediaQuery.of(context).padding.top + kToolbarHeight;
                              return ValueListenableBuilder<double>(
                                valueListenable: _headingNotifier,
                                builder: (_, heading, __) {
                                  return CustomPaint(
                                    size: Size(constraints.maxWidth, constraints.maxHeight),
                                    painter: ARPainter(
                                      objects: _objects,
                                      groups: _groups,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.satellite_alt, size: 48, color: Colors.white38),
                  SizedBox(height: 12),
                  Text(
                    'Esperando señal GPS...',
                    style: TextStyle(color: Colors.white60, fontSize: 15),
                  ),
                ],
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B0E1A), Color(0xFF141829)],
        ),
      ),
      child: ValueListenableBuilder<double>(
        valueListenable: _headingNotifier,
        builder: (_, heading, __) {
          return CustomPaint(
            size: Size.infinite,
            painter: RadarPainter(
              objects: _sortedObjects,
              groups: _groups,
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
        color: Colors.black.withOpacity(0.5),
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
      height: 150,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.0),
            Colors.black.withOpacity(0.85),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.radar, size: 14, color: Colors.white38),
                SizedBox(width: 6),
                Text(
                  'CERCANOS',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _sortedObjects.length,
              itemBuilder: (context, index) {
                final item = _sortedObjects[index];
                final isClosest = index == 0;
                return Container(
                  width: 100,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        item.color.withOpacity(0.25),
                        item.color.withOpacity(0.10),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: item.color.withOpacity(isClosest ? 0.5 : 0.2),
                      width: isClosest ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: item.color.withOpacity(0.2),
                          shape: BoxShape.circle,
                          border: Border.all(color: item.color.withOpacity(0.4), width: 1),
                        ),
                        child: Icon(item.icon, color: item.color, size: 18),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.object.name,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
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

class RadarPainter extends CustomPainter {
  final List<_ObjectWithDistance> objects;
  final List<ObjectGroup> groups;
  final double heading;
  final Map<int, Offset> _objectPositions = {};

  RadarPainter({required this.objects, required this.groups, required this.heading});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.45);
    final radius = math.min(size.width, size.height) * 0.42;

    // Subtle grid
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.03)
      ..strokeWidth = 0.5;
    for (int i = 0; i < 6; i++) {
      final angle = i * math.pi / 3;
      canvas.drawLine(
        center,
        Offset(center.dx + radius * math.cos(angle), center.dy + radius * math.sin(angle)),
        gridPaint,
      );
    }

    // Outer glow
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFF1A1A3E).withOpacity(0.25), Colors.transparent],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, glow);

    // Rings
    final ringColors = [Colors.white.withOpacity(0.06), Colors.white.withOpacity(0.04), Colors.white.withOpacity(0.03), Colors.white.withOpacity(0.02)];
    for (int i = 0; i < 4; i++) {
      canvas.drawCircle(
        center, radius * (i + 1) / 4,
        Paint()
          ..color = ringColors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // Cardinal points with nicer styling
    final cardinals = <String, double>{
      'N': -heading,
      'E': 90 - heading,
      'S': 180 - heading,
      'O': 270 - heading,
    };
    for (final entry in cardinals.entries) {
      final angleRad = entry.value * math.pi / 180;
      final lx = center.dx + (radius + 20) * math.sin(angleRad);
      final ly = center.dy - (radius + 20) * math.cos(angleRad);
      final isNorth = entry.key == 'N';
      _drawText(canvas, entry.key, lx, ly,
        fontSize: isNorth ? 19 : 15,
        fontWeight: isNorth ? FontWeight.bold : FontWeight.w500,
        color: isNorth ? Colors.white.withOpacity(0.9) : Colors.white.withOpacity(0.45),
      );
    }

    // Direction indicator - sleek arrow
    final arrowPaint = Paint()
      ..color = Colors.white.withOpacity(0.6);
    final arrowPath = Path()
      ..moveTo(center.dx, center.dy - radius - 14)
      ..lineTo(center.dx - 7, center.dy - radius + 2)
      ..lineTo(center.dx + 7, center.dy - radius + 2)
      ..close();
    canvas.drawPath(arrowPath, arrowPaint);
    canvas.drawCircle(center, 2.5, Paint()..color = Colors.white.withOpacity(0.5));

    if (objects.isEmpty) {
      _drawText(canvas, 'Sin objetos cerca', center.dx, center.dy + 35,
          fontSize: 15, color: Colors.white30);
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

      _objectPositions[obj.object.id!] = Offset(ox, oy);

      // Glow ring
      canvas.drawCircle(
        Offset(ox, oy), 12,
        Paint()
          ..shader = RadialGradient(
            colors: [obj.color.withOpacity(0.3), obj.color.withOpacity(0.0)],
          ).createShader(Rect.fromCircle(center: Offset(ox, oy), radius: 12)),
      );

      // Main dot
      canvas.drawCircle(Offset(ox, oy), 6, Paint()..color = obj.color);
      // White ring
      canvas.drawCircle(Offset(ox, oy), 6, Paint()
        ..color = Colors.white.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);

      // Labels
      final labelOffset = (objR < radius * 0.3) ? const Offset(14, -12) : const Offset(12, -10);
      _drawText(canvas, obj.object.name, ox + labelOffset.dx, oy + labelOffset.dy,
          fontSize: 12, fontWeight: FontWeight.w600, color: obj.color);
      _drawText(canvas, formatDistance(obj.distance), ox + labelOffset.dx, oy + labelOffset.dy + 15,
          fontSize: 10, color: Colors.white60);
    }

    _drawGroupsOnRadar(canvas, center, radius, radarMax);
  }

  void _drawGroupsOnRadar(Canvas canvas, Offset center, double radius, double radarMax) {
    for (final group in groups) {
      final members = group.sortedObjects;
      if (members.length < 2) continue;

      final positions = <Offset>[];
      for (final m in members) {
        final id = m.id;
        if (id == null) continue;
        if (_objectPositions.containsKey(id)) {
          positions.add(_objectPositions[id]!);
        } else {
          final distObj = objects.cast<_ObjectWithDistance?>().firstWhere(
            (o) => o!.object.id == id,
            orElse: () => null,
          );
          if (distObj != null) {
            final angleDiff = distObj.bearing - heading;
            final angleRad = angleDiff * math.pi / 180;
            final distFactor = (distObj.distance / radarMax).clamp(0.0, 1.0);
            final objR = distFactor * radius * 0.88;
            positions.add(Offset(
              center.dx + objR * math.sin(angleRad),
              center.dy - objR * math.cos(angleRad),
            ));
          }
        }
      }
      if (positions.length < 2) continue;

      final baseColor = group.type == 'area' ? Colors.green : Colors.cyan;

      if (group.type == 'area' && positions.length >= 3) {
        final fillPaint = Paint()..color = baseColor.withOpacity(0.08);
        final path = Path()..moveTo(positions[0].dx, positions[0].dy);
        for (int i = 1; i < positions.length; i++) {
          path.lineTo(positions[i].dx, positions[i].dy);
        }
        path.close();
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, Paint()
          ..color = baseColor.withOpacity(0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      } else {
        for (int i = 0; i < positions.length - 1; i++) {
          canvas.drawLine(positions[i], positions[i + 1], Paint()
            ..color = baseColor.withOpacity(0.35)
            ..strokeWidth = 2);

          final mid = Offset(
            (positions[i].dx + positions[i + 1].dx) / 2,
            (positions[i].dy + positions[i + 1].dy) / 2,
          );
          final segDist = Geolocator.distanceBetween(
            group.sortedObjects[i].latitude, group.sortedObjects[i].longitude,
            group.sortedObjects[i + 1].latitude, group.sortedObjects[i + 1].longitude,
          );
          _drawText(canvas, formatDistance(segDist), mid.dx, mid.dy - 8,
              fontSize: 9, color: Colors.white.withOpacity(0.5));
        }
      }

      double cx = 0, cy = 0;
      for (final p in positions) { cx += p.dx; cy += p.dy; }
      cx /= positions.length;
      cy /= positions.length;
      _drawText(canvas, group.name, cx, cy,
          fontSize: 10, fontWeight: FontWeight.bold,
          color: baseColor.withOpacity(0.8));
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
          shadows: const [Shadow(blurRadius: 8, color: Color(0xCC000000))],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y));
  }

  @override
  bool shouldRepaint(RadarPainter oldDelegate) {
    return (oldDelegate.heading - heading).abs() > 0.5 ||
        oldDelegate.objects != objects ||
        oldDelegate.groups != groups;
  }
}
