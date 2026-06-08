import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import '../models/saved_object.dart';
import '../services/database_service.dart';
import '../services/compass_service.dart';
import '../widgets/ar_painter.dart';
import 'register_object_screen.dart';

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
  double _heading = 0;
  StreamSubscription<Position>? _positionSub;
  final CompassService _compassService = CompassService();
  StreamSubscription<double>? _headingSub;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
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
      _headingSub = _compassService.headingStream.listen((h) {
        if (mounted) setState(() => _heading = h);
      });

      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
        ),
      ).listen((pos) {
        if (mounted) setState(() => _currentPosition = pos);
      });

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _initialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  List<SavedObject> _sortedByDistance() {
    if (_currentPosition == null) return _objects;
    final sorted = List<SavedObject>.from(_objects);
    sorted.sort((a, b) {
      final da = Geolocator.distanceBetween(
        _currentPosition!.latitude, _currentPosition!.longitude,
        a.latitude, a.longitude,
      );
      final db = Geolocator.distanceBetween(
        _currentPosition!.latitude, _currentPosition!.longitude,
        b.latitude, b.longitude,
      );
      return da.compareTo(db);
    });
    return sorted;
  }

  String _formatDistance(double meters) {
    if (meters < 1) return '${(meters * 100).round()} cm';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  void dispose() {
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

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Realidad Aumentada')),
        body: const Center(child: Text('No se pudo acceder a la cámara')),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('${_heading.toStringAsFixed(0)}°'),
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Stack(
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
                    heading: _heading,
                    fov: 60,
                    screenSize: Size(constraints.maxWidth, constraints.maxHeight),
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

    final sorted = _sortedByDistance();
    return Container(
      height: 120,
      color: Colors.black54,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Objetos cercanos',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: sorted.length,
              itemBuilder: (context, index) {
                final obj = sorted[index];
                final dist = Geolocator.distanceBetween(
                  _currentPosition!.latitude, _currentPosition!.longitude,
                  obj.latitude, obj.longitude,
                );

                final typeEntry = objectTypes.cast<Map<String, dynamic>?>().firstWhere(
                  (t) => t?['name'] == obj.type,
                  orElse: () => null,
                );
                final color = typeEntry?['color'] as Color? ?? Colors.white;
                final icon = typeEntry?['icon'] as IconData? ?? Icons.place;

                return Container(
                  width: 100,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.4)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: color, size: 24),
                      const SizedBox(height: 2),
                      Text(
                        obj.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _formatDistance(dist),
                        style: TextStyle(
                          color: color.withOpacity(0.8),
                          fontSize: 10,
                        ),
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
