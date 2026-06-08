import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import '../models/saved_object.dart';
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

    await DatabaseService.instance.insertObject(obj);

    if (mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${obj.name} guardado'),
        ),
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
