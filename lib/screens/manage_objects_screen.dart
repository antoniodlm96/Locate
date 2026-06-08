import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/saved_object.dart';
import '../services/database_service.dart';
import 'register_object_screen.dart';

class ManageObjectsScreen extends StatefulWidget {
  const ManageObjectsScreen({super.key});

  @override
  State<ManageObjectsScreen> createState() => _ManageObjectsScreenState();
}

class _ManageObjectsScreenState extends State<ManageObjectsScreen> {
  List<SavedObject> _objects = [];
  Position? _currentPosition;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final objects = await DatabaseService.instance.getAllObjects();
      Position? pos;
      try {
        pos = await Geolocator.getLastKnownPosition();
        if (pos == null) {
          pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 4),
          );
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _objects = objects;
          _currentPosition = pos;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _findTypeEntry(String type) {
    for (final t in objectTypes) {
      if (t['name'] == type) return t;
    }
    return null;
  }

  Future<void> _rename(SavedObject obj) async {
    final controller = TextEditingController(text: obj.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar objeto'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nuevo nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != obj.name) {
      await DatabaseService.instance.updateObjectName(obj.id!, newName);
      setState(() {
        final idx = _objects.indexWhere((o) => o.id == obj.id);
        if (idx != -1) _objects[idx] = obj.copyWith(name: newName);
      });
    }
  }

  Future<void> _toggleActive(SavedObject obj) async {
    final newActive = !obj.isActive;
    await DatabaseService.instance.updateObjectActive(obj.id!, newActive);
    setState(() {
      final idx = _objects.indexWhere((o) => o.id == obj.id);
      if (idx != -1) _objects[idx] = obj.copyWith(isActive: newActive);
    });
  }

  Future<void> _delete(SavedObject obj) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar objeto'),
        content: Text('¿Eliminar "${obj.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService.instance.deleteObject(obj.id!);
      setState(() => _objects.removeWhere((o) => o.id == obj.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${obj.name}" eliminado'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Gestionar Objetos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _objects.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(
                        'No hay objetos guardados',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegisterObjectScreen(),
                          ),
                        ).then((_) => _load()),
                        icon: const Icon(Icons.add),
                        label: const Text('Registrar primero'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _objects.length,
                  itemBuilder: (context, index) {
                    final obj = _objects[index];
                    final typeEntry = _findTypeEntry(obj.type);
                    final color = typeEntry?['color'] as Color? ?? Colors.grey;
                    final icon = typeEntry?['icon'] as IconData? ?? Icons.place;

                    String? distanceText;
                    if (_currentPosition != null) {
                      final dist = Geolocator.distanceBetween(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                        obj.latitude,
                        obj.longitude,
                      );
                      distanceText = _formatDistance(dist);
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: obj.isActive ? null : theme.colorScheme.surfaceContainerLow,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: obj.isActive ? color : color.withOpacity(0.3),
                          child: Icon(icon, color: Colors.white),
                        ),
                        title: Text(
                          obj.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: obj.isActive ? null : theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                        subtitle: Text(
                          distanceText ?? 'Sin ubicación',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => _rename(obj),
                              tooltip: 'Renombrar',
                            ),
                            Switch(
                              value: obj.isActive,
                              onChanged: (_) => _toggleActive(obj),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                              onPressed: () => _delete(obj),
                              tooltip: 'Eliminar',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1) return '${(meters * 100).round()} cm';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}
