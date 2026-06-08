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
    await _requestLocation();
    await _requestCamera();
  }

  Future<void> _requestLocation() async {
    try {
      var permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever && mounted) {
        _showPermissionDialog();
      }
    } catch (_) {}
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permiso de ubicación'),
        content: const Text(
          'La app necesita acceso a la ubicación para funcionar. '
          'Actívalo en los ajustes del sistema.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            child: const Text('Abrir ajustes'),
          ),
        ],
      ),
    );
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

  Future<void> _loadCount() async {
    final count = await DatabaseService.instance.getObjectCount();
    if (mounted) setState(() => _objectCount = count);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Locate'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [cs.primaryContainer, cs.primary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(Icons.explore, size: 60, color: cs.onPrimary),
                ),
                const SizedBox(height: 20),
                Text(
                  'Objetos guardados',
                  style: cs.onSurface.withOpacity(0.6) is Color
                      ? TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 14)
                      : TextStyle(color: cs.onSurface, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_objectCount',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 40),
                _MenuButton(
                  icon: Icons.add_location_alt,
                  label: 'Registrar Objeto',
                  onTap: () => _navigate(context, const RegisterObjectScreen()),
                  color: cs.primary,
                ),
                const SizedBox(height: 12),
                _MenuButton(
                  icon: Icons.view_in_ar,
                  label: 'Ver en RA',
                  onTap: _objectCount > 0
                      ? () => _navigate(context, const ARViewScreen())
                      : null,
                  color: cs.secondary,
                ),
                const SizedBox(height: 12),
                _MenuButton(
                  icon: Icons.map,
                  label: 'Buscar en Mapa',
                  onTap: () => _navigate(context, const MapScreen()),
                  color: cs.tertiary,
                ),
                const SizedBox(height: 12),
                _MenuButton(
                  icon: Icons.list_alt,
                  label: 'Gestionar Objetos',
                  onTap: _objectCount > 0
                      ? () => _navigate(context, const ManageObjectsScreen())
                      : null,
                  color: cs.error,
                ),
              ],
            ),
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

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disabled = onTap == null;
    final bgColor = disabled
        ? cs.surfaceContainerHighest
        : color.withOpacity(0.15);
    final fgColor = disabled
        ? cs.onSurface.withOpacity(0.3)
        : color;
    final iconColor = disabled
        ? cs.onSurface.withOpacity(0.3)
        : color;

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: fgColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: iconColor, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: fgColor,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: fgColor.withOpacity(0.5),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
