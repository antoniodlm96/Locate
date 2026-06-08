import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:camera/camera.dart';
import '../services/database_service.dart';
import 'register_object_screen.dart';
import 'ar_view_screen.dart';
import 'manage_objects_screen.dart';
import 'map_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _objectCount = 0;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadCount();
  }

  Future<void> _requestPermissions() async {
    await Future.wait([
      _requestCamera(),
      _requestLocation(),
    ]);
  }

  Future<void> _requestCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final ctrl = CameraController(cameras.first, ResolutionPreset.low);
      await ctrl.initialize();
      await ctrl.dispose();
    } catch (_) {}
  }

  Future<void> _requestLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await Geolocator.requestPermission();
      }
    } catch (_) {}
  }

  Future<void> _loadCount() async {
    final count = await DatabaseService.instance.getObjectCount();
    if (mounted) setState(() => _objectCount = count);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Locate'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.explore, size: 80, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Objetos guardados: $_objectCount',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 80,
                child: ElevatedButton.icon(
                  onPressed: () => _navigate(context, const RegisterObjectScreen()),
                  icon: const Icon(Icons.add_location_alt, size: 32),
                  label: const Text('Registrar Objeto', style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 80,
                child: ElevatedButton.icon(
                  onPressed: _objectCount > 0
                      ? () => _navigate(context, const ARViewScreen())
                      : null,
                  icon: const Icon(Icons.view_in_ar, size: 32),
                  label: const Text('Ver en RA', style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 80,
                child: OutlinedButton.icon(
                  onPressed: () => _navigate(context, const MapScreen()),
                  icon: const Icon(Icons.map, size: 32),
                  label: const Text('Buscar en Mapa', style: TextStyle(fontSize: 18)),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 80,
                child: OutlinedButton.icon(
                  onPressed: _objectCount > 0
                      ? () => _navigate(context, const ManageObjectsScreen())
                      : null,
                  icon: const Icon(Icons.list_alt, size: 32),
                  label: const Text('Gestionar Objetos', style: TextStyle(fontSize: 18)),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigate(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    ).then((_) => _loadCount());
  }
}
