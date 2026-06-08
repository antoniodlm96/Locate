import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/saved_object.dart';
import '../models/object_group.dart';
import '../services/database_service.dart';
import 'register_object_screen.dart';

class ManageObjectsScreen extends StatefulWidget {
  const ManageObjectsScreen({super.key});

  @override
  State<ManageObjectsScreen> createState() => _ManageObjectsScreenState();
}

class _ManageObjectsScreenState extends State<ManageObjectsScreen>
    with SingleTickerProviderStateMixin {
  List<SavedObject> _objects = [];
  List<ObjectGroup> _groups = [];
  Position? _currentPosition;
  bool _loading = true;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    try {
      final objects = await DatabaseService.instance.getAllObjects();
      final groups = await DatabaseService.instance.getAllGroups();
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
          _groups = groups;
          _currentPosition = pos;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _findTypeEntry(String type) {
    for (final t in objectTypes) {
      if (t['name'] == type) return t;
    }
    return null;
  }

  // --- Object actions ---

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

  // --- Group actions ---

  Future<void> _createGroup() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo grupo'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Nombre del grupo',
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

    final objects = await db.getAllObjects();
    if (!mounted || objects.isEmpty) {
      if (mounted) await _load();
      return;
    }

    final selected = <int>{};
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Añadir objetos'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: ListView.builder(
                itemCount: objects.length,
                itemBuilder: (context, index) {
                  final obj = objects[index];
                  return CheckboxListTile(
                    value: selected.contains(obj.id),
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
                child: const Text('Saltar'),
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
      var idx = 0;
      for (final obj in objects) {
        if (selected.contains(obj.id)) {
          await db.addMemberToGroup(groupId, obj.id!, idx++);
        }
      }
      if (result >= 3) {
        final typeDialog = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Tipo de grupo'),
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
        if (typeDialog == 'area' && mounted) {
          await db.updateGroup(groupId, name, 'area');
        }
      }
    }
    if (mounted) await _load();
  }

  Future<void> _editGroup(ObjectGroup group) async {
    if (group.members == null || group.members!.isEmpty) return;
    if (!mounted) return;

    final result = await showDialog(
      context: context,
      builder: (ctx) => _EditGroupDialog(group: group),
    );
    if (result == true && mounted) await _load();
  }

  Future<void> _deleteGroup(ObjectGroup group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar grupo'),
        content: Text('¿Eliminar "${group.name}"?'),
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
      await DatabaseService.instance.deleteGroup(group.id!);
      if (mounted) await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestionar'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.list), text: 'Objetos'),
            Tab(icon: Icon(Icons.group_work), text: 'Grupos'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildObjectsTab(cs),
                _buildGroupsTab(cs),
              ],
            ),
    );
  }

  Widget _buildObjectsTab(ColorScheme cs) {
    if (_objects.isEmpty) {
      return Center(
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
      );
    }

    return ListView.builder(
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
    );
  }

  Widget _buildGroupsTab(ColorScheme cs) {
    if (_groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_work, size: 80, color: cs.outline),
            const SizedBox(height: 16),
            Text(
              'No hay grupos',
              style: TextStyle(fontSize: 18, color: cs.onSurface.withOpacity(0.6)),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _createGroup,
              icon: const Icon(Icons.add, size: 22),
              label: const Text('Crear grupo'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _groups.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _createGroup,
                icon: const Icon(Icons.add),
                label: const Text('Crear grupo'),
              ),
            ),
          );
        }
        final group = _groups[index - 1];
        final memberCount = group.members?.length ?? 0;
        final icon = group.type == 'area' ? Icons.change_history : Icons.route;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: InkWell(
              onTap: () => _editGroup(group),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(icon, color: cs.onPrimaryContainer, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                              Text(
                                '${memberCount} objetos · ${group.type == 'area' ? 'Área' : 'Línea'}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurface.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, size: 22, color: Colors.red.withOpacity(0.7)),
                          onPressed: () => _deleteGroup(group),
                          tooltip: 'Eliminar grupo',
                        ),
                      ],
                    ),
                    if (memberCount > 0) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: group.members!.map((m) {
                          final typeEntry = _findTypeEntry(m.object!.type);
                          final color = typeEntry?['color'] as Color? ?? Colors.grey;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${m.orderIndex + 1}. ${m.object!.name}',
                              style: TextStyle(fontSize: 12, color: color),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1) return '${(meters * 100).round()} cm';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}

class _EditGroupDialog extends StatefulWidget {
  final ObjectGroup group;
  const _EditGroupDialog({required this.group});

  @override
  State<_EditGroupDialog> createState() => _EditGroupDialogState();
}

class _EditGroupDialogState extends State<_EditGroupDialog> {
  late String _name;
  late String _type;
  late List<ObjectGroupMember> _members;
  final db = DatabaseService.instance;

  @override
  void initState() {
    super.initState();
    _name = widget.group.name;
    _type = widget.group.type;
    _members = List.from(widget.group.members ?? []);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Nombre', prefixIcon: Icon(Icons.edit)),
              controller: TextEditingController(text: _name),
              textCapitalization: TextCapitalization.sentences,
              onChanged: (v) => _name = v,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Tipo: '),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Línea'),
                  selected: _type == 'line',
                  onSelected: _members.length >= 3 ? (v) => setState(() => _type = 'line') : null,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Área'),
                  selected: _type == 'area',
                  onSelected: _members.length >= 3 ? (v) => setState(() => _type = 'area') : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Miembros (${_members.length})',
                style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 8),
            if (_members.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('Sin miembros', style: TextStyle(color: cs.onSurface.withOpacity(0.5))),
                ),
              )
            else
              ...List.generate(_members.length, (i) {
                final m = _members[i];
                final obj = m.object;
                if (obj == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Text('${m.orderIndex + 1}.',
                          style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
                      const SizedBox(width: 8),
                      Icon(Icons.place, size: 18, color: cs.primary),
                      const SizedBox(width: 6),
                      Expanded(child: Text(obj.name, style: const TextStyle(fontSize: 14))),
                      IconButton(
                        icon: Icon(Icons.arrow_upward, size: 18),
                        onPressed: i == 0
                            ? null
                            : () async {
                                await db.reorderMember(m.id!, m.orderIndex - 1);
                                await db.reorderMember(_members[i - 1].id!, m.orderIndex);
                                setState(() {
                                  final temp = _members[i];
                                  _members[i] = _members[i - 1];
                                  _members[i - 1] = temp;
                                });
                              },
                      ),
                      IconButton(
                        icon: Icon(Icons.arrow_downward, size: 18),
                        onPressed: i == _members.length - 1
                            ? null
                            : () async {
                                await db.reorderMember(m.id!, m.orderIndex + 1);
                                await db.reorderMember(_members[i + 1].id!, m.orderIndex);
                                setState(() {
                                  final temp = _members[i];
                                  _members[i] = _members[i + 1];
                                  _members[i + 1] = temp;
                                });
                              },
                      ),
                      IconButton(
                        icon: Icon(Icons.remove_circle, size: 20, color: Colors.red.withOpacity(0.7)),
                        onPressed: () async {
                          await db.removeMember(m.id!);
                          setState(() => _members.removeAt(i));
                        },
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => _addMembers(),
                  child: const Text('Añadir objetos'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (_name.trim().isNotEmpty) {
                      await db.updateGroup(widget.group.id!, _name.trim(), _type);
                      if (context.mounted) Navigator.pop(context, true);
                    }
                  },
                  child: const Text('Guardar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addMembers() async {
    final available = await db.getObjectsNotInGroup(widget.group.id!);
    if (!mounted || available.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay objetos disponibles')),
        );
      }
      return;
    }
    final selected = <int>{};
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Añadir objetos'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: ListView.builder(
                itemCount: available.length,
                itemBuilder: (context, index) {
                  final obj = available[index];
                  return CheckboxListTile(
                    value: selected.contains(obj.id),
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
                onPressed: () => Navigator.pop(ctx),
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
      var orderIndex = _members.length;
      for (final obj in available) {
        if (selected.contains(obj.id)) {
          await db.addMemberToGroup(widget.group.id!, obj.id!, orderIndex++);
          setState(() {
            _members.add(ObjectGroupMember(
              groupId: widget.group.id!,
              objectId: obj.id!,
              orderIndex: orderIndex - 1,
              object: obj,
            ));
          });
        }
      }
    }
  }
}
