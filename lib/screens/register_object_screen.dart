import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import '../models/saved_object.dart';
import '../models/object_group.dart';
import '../services/database_service.dart';

const List<Map<String, dynamic>> objectTypes = [
  {'name': 'Coche', 'icon': Icons.directions_car, 'color': Color(0xFF2196F3)},
  {'name': 'Moto', 'icon': Icons.motorcycle, 'color': Color(0xFFF44336)},
  {'name': 'Bici', 'icon': Icons.pedal_bike, 'color': Color(0xFF4CAF50)},
  {'name': 'Tienda', 'icon': Icons.store, 'color': Color(0xFFFF9800)},
  {'name': 'Casa', 'icon': Icons.home, 'color': Color(0xFF795548)},
  {'name': 'Trabajo', 'icon': Icons.work, 'color': Color(0xFF9C27B0)},
  {'name': 'Supermercado', 'icon': Icons.shopping_cart, 'color': Color(0xFF009688)},
  {'name': 'Gasolinera', 'icon': Icons.local_gas_station, 'color': Color(0xFFFBC02D)},
  {'name': 'Restaurante', 'icon': Icons.restaurant, 'color': Color(0xFFE91E63)},
  {'name': 'Parque', 'icon': Icons.park, 'color': Color(0xFF8BC34A)},
  {'name': 'Hospital', 'icon': Icons.local_hospital, 'color': Color(0xFFE57373)},
  {'name': 'Hotel', 'icon': Icons.hotel, 'color': Color(0xFF5C6BC0)},
  {'name': 'Ciudad', 'icon': Icons.location_city, 'color': Color(0xFF607D8B)},
  {'name': 'Pueblo', 'icon': Icons.store_mall_directory, 'color': Color(0xFF8D6E63)},
];

class RegisterObjectScreen extends StatefulWidget {
  final LatLng? preselectedLatLng;
  final String? preselectedName;

  const RegisterObjectScreen({super.key, this.preselectedLatLng, this.preselectedName});

  @override
  State<RegisterObjectScreen> createState() => _RegisterObjectScreenState();
}

class _RegisterObjectScreenState extends State<RegisterObjectScreen> {
  final TextEditingController _nameController = TextEditingController();
  String? _selectedType;
  Position? _currentPosition;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.preselectedName != null && widget.preselectedName!.isNotEmpty) {
      _nameController.text = widget.preselectedName!;
    }
    if (widget.preselectedLatLng != null) {
      _currentPosition = Position(
        longitude: widget.preselectedLatLng!.longitude,
        latitude: widget.preselectedLatLng!.latitude,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
      setState(() => _loading = false);
    } else {
      _getLocation();
    }
  }

  Future<void> _getLocation() async {
    setState(() => _loading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Activa el GPS para registrar objetos')),
          );
        }
        setState(() => _loading = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Permiso de ubicación denegado')),
            );
          }
          setState(() => _loading = false);
          return;
        }
      }

      var pos = await Geolocator.getLastKnownPosition();
      if (pos == null) {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        );
      }
      setState(() {
        _currentPosition = pos;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al obtener ubicación: $e')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (_selectedType == null || _currentPosition == null) return;

    final customName = _nameController.text.trim();
    final obj = SavedObject(
      name: customName.isNotEmpty ? customName : _selectedType!,
      type: _selectedType!,
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
    );

    final savedId = await DatabaseService.instance.insertObject(obj);

    if (mounted && savedId > 0) {
      await _showGroupingDialog(savedId, obj.name);
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${obj.name} guardado')),
        );
      }
    }
  }

  Future<void> _showGroupingDialog(int savedId, String objName) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => _GroupingSheet(savedId: savedId, objName: objName),
    );
    if (result == 'grouped' && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Grupo creado correctamente')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar Objeto')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _currentPosition == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_off, size: 64, color: cs.error),
                      const SizedBox(height: 16),
                      const Text('No se pudo obtener la ubicación'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _getLocation,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.location_on, color: cs.primary, size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Ubicación', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5))),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_currentPosition!.latitude.toStringAsFixed(6)}, '
                                      '${_currentPosition!.longitude.toStringAsFixed(6)}',
                                      style: TextStyle(fontSize: 14, fontFamily: 'monospace', color: cs.onSurface),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre',
                          hintText: 'Ej: Casa de la abuela',
                          prefixIcon: Icon(Icons.edit),
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Tipo',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: objectTypes.length,
                          itemBuilder: (context, index) {
                            final type = objectTypes[index];
                            final isSelected = _selectedType == type['name'];
                            return GestureDetector(
                              onTap: () => setState(() => _selectedType = type['name'] as String),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? type['color'] as Color
                                      : cs.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? type['color'] as Color
                                        : cs.outline.withOpacity(0.2),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      type['icon'] as IconData,
                                      size: 38,
                                      color: isSelected ? Colors.white : type['color'] as Color,
                                    ),
                                    const SizedBox(height: 4),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      child: Text(
                                        type['name'] as String,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                          color: isSelected ? Colors.white : cs.onSurface.withOpacity(0.7),
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton.icon(
                          onPressed: _selectedType != null ? _save : null,
                          icon: const Icon(Icons.save, size: 22),
                          label: const Text('Guardar'),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _GroupingSheet extends StatefulWidget {
  final int savedId;
  final String objName;
  const _GroupingSheet({required this.savedId, required this.objName});

  @override
  State<_GroupingSheet> createState() => _GroupingSheetState();
}

class _GroupingSheetState extends State<_GroupingSheet> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿Agrupar "${widget.objName}" con otros objetos?',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            'Podrás crear rutas y áreas visibles en el mapa y RA.',
            style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _createNewGroup(),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Crear grupo nuevo'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _addToExistingGroup(),
              icon: const Icon(Icons.playlist_add),
              label: const Text('Añadir a grupo existente'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('No, gracias'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createNewGroup() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nombre del grupo'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Ej: Ruta al trabajo',
            prefixIcon: Icon(Icons.edit),
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final db = DatabaseService.instance;
    final groupId = await db.insertGroup(ObjectGroup(name: name, type: 'line'));
    await db.addMemberToGroup(groupId, widget.savedId, 0);

    if (!mounted) return;
    final objects = await db.getActiveObjects();
    final available = objects.where((o) => o.id != widget.savedId).toList();
    if (available.isEmpty) {
      Navigator.pop(context, 'grouped');
      return;
    }

    final selected = await _showObjectPicker(available, db, groupId);
    if (selected > 0) {
      if (selected >= 3) {
        final isArea = await _askLineOrArea();
        if (mounted) {
          await db.updateGroup(groupId, name, isArea ? 'area' : 'line');
        }
      }
    }
    if (mounted) Navigator.pop(context, 'grouped');
  }

  Future<void> _addToExistingGroup() async {
    final db = DatabaseService.instance;
    final groups = await db.getAllGroups();
    if (!mounted || groups.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay grupos creados')),
        );
      }
      return;
    }

    final group = await showDialog<ObjectGroup>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Seleccionar grupo'),
        children: groups.map((g) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, g),
            child: Row(
              children: [
                Icon(g.type == 'area' ? Icons.change_history : Icons.route, size: 24),
                const SizedBox(width: 12),
                Text(g.name),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (group != null) {
      final nextIndex = (group.members?.length ?? 0);
      await db.addMemberToGroup(group.id!, widget.savedId, nextIndex);
      if (mounted) Navigator.pop(context, 'grouped');
    }
  }

  Future<int> _showObjectPicker(List<SavedObject> objects, DatabaseService db, int groupId) async {
    final selected = <int>{};
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Añadir objetos al grupo'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: ListView.builder(
                itemCount: objects.length,
                itemBuilder: (context, index) {
                  final obj = objects[index];
                  final isChecked = selected.contains(obj.id);
                  return CheckboxListTile(
                    value: isChecked,
                    onChanged: (v) {
                      setDialogState(() {
                        if (v == true) {
                          selected.add(obj.id!);
                        } else {
                          selected.remove(obj.id);
                        }
                      });
                    },
                    title: Text(obj.name),
                    subtitle: Text(obj.type),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, -1),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, selected.length),
                child: Text('Añadir (${selected.length})'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null && result > 0) {
      var orderIndex = (await db.getGroupMembers(groupId)).length;
      for (final obj in objects) {
        if (selected.contains(obj.id)) {
          await db.addMemberToGroup(groupId, obj.id!, orderIndex++);
        }
      }
    }
    return result ?? 0;
  }

  Future<bool> _askLineOrArea() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tipo de grupo'),
        content: const Text('¿Cómo quieres agrupar estos objetos?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'line'),
            child: const Text('Línea (ruta)'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'area'),
            child: const Text('Área (polígono)'),
          ),
        ],
      ),
    );
    return result == 'area';
  }
}
