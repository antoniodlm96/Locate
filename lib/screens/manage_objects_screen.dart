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
        title: const Text('Renombrar'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nuevo nombre',
            prefixIcon: Icon(Icons.edit),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
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
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
          SnackBar(content: Text('"${obj.name}" eliminado')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Gestionar Objetos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _objects.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 80, color: cs.outline),
                      const SizedBox(height: 16),
                      Text(
                        'No hay objetos guardados',
                        style: TextStyle(fontSize: 18, color: cs.onSurface.withOpacity(0.6)),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegisterObjectScreen(),
                          ),
                        ).then((_) => _load()),
                        icon: const Icon(Icons.add, size: 22),
                        label: const Text('Registrar primero'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        color: obj.isActive ? null : cs.surfaceContainerLow,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: obj.isActive
                                      ? color.withOpacity(0.2)
                                      : color.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(icon, color: obj.isActive ? color : color.withOpacity(0.4), size: 26),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      obj.name,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: obj.isActive ? cs.onSurface : cs.onSurface.withOpacity(0.4),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      distanceText ?? 'Sin ubicación',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: obj.isActive
                                            ? cs.onSurface.withOpacity(0.5)
                                            : cs.onSurface.withOpacity(0.3),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.edit, size: 22),
                                onPressed: () => _rename(obj),
                                color: cs.onSurface.withOpacity(0.5),
                                tooltip: 'Renombrar',
                              ),
                              Switch(
                                value: obj.isActive,
                                onChanged: (_) => _toggleActive(obj),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete, size: 22, color: Colors.red.withOpacity(0.7)),
                                onPressed: () => _delete(obj),
                                tooltip: 'Eliminar',
                              ),
                            ],
                          ),
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
