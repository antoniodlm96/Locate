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
import '../widgets/unified_ar_painter.dart';
import 'register_object_screen.dart';

class ObjectWithDistance {
  final SavedObject object;
  final double distance;
  final double bearing;
  final Color color;
  final IconData icon;

  ObjectWithDistance({
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
  List<ObjectWithDistance> _sortedObjects = [];

  // Combined state: single repaint trigger
  double _heading = 0;
  double _tilt = 0;
  bool _needsRepaint = false;

  StreamSubscription? _accSub;

  @override
  void initState() {
    super.initState();
    // Tilt at game rate for smooth tracking
    _accSub = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen((event) {
      final norm = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (norm > 0) {
        final gz = event.z / norm;
        final rawTilt = (1.0 - gz.abs()).clamp(0.0, 1.0);
        final smoothed = _tilt + (rawTilt - _tilt) * 0.06;
        if ((smoothed - _tilt).abs() > 0.005) {
          _tilt = smoothed;
          _triggerRepaint();
        }
      }
    });
    _init();
  }

  void _onHeading(double h) {
    _heading = h;
    _triggerRepaint();
  }

  void _triggerRepaint() {
    if (!_needsRepaint) {
      _needsRepaint = true;
      // Schedule repaint on next frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _needsRepaint = false;
          setState(() {});
        }
      });
    }
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
    final list = <ObjectWithDistance>[];
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
      list.add(ObjectWithDistance(
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

    final topPad = MediaQuery.of(context).padding.top + kToolbarHeight;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Container(
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
                '${_heading.toStringAsFixed(0)}°',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Camera preview
          if (_cameraController != null && _cameraController!.value.isInitialized)
            RepaintBoundary(
              child: CameraPreview(_cameraController!),
            ),

          // Unified AR overlay (AR markers + ground radar in one CustomPaint)
          if (_currentPosition != null)
            RepaintBoundary(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: UnifiedARPainter(
                      objects: _sortedObjects,
                      groups: _groups,
                      currentPosition: _currentPosition!,
                      rawObjects: _objects,
                      heading: _heading,
                      tilt: _tilt,
                      fov: 180,
                      screenSize: Size(constraints.maxWidth, constraints.maxHeight),
                      topPadding: topPad,
                    ),
                  );
                },
              ),
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

          // Bottom list
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

    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      height: 140 + bottomPad,
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
      padding: EdgeInsets.fromLTRB(0, 24, 0, 8 + bottomPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.radar, size: 16, color: Colors.white70),
                SizedBox(width: 6),
                Text(
                  'CERCANOS',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
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
                  width: 110,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        item.color.withOpacity(0.35),
                        item.color.withOpacity(0.15),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: item.color.withOpacity(isClosest ? 0.7 : 0.35),
                      width: isClosest ? 2 : 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: item.color.withOpacity(0.3),
                          shape: BoxShape.circle,
                          border: Border.all(color: item.color.withOpacity(0.6), width: 1.5),
                        ),
                        child: Icon(item.icon, color: item.color, size: 20),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.object.name,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        formatDistance(item.distance),
                        style: TextStyle(color: item.color.withOpacity(0.9), fontSize: 11),
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
