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
];

class RegisterObjectScreen extends StatefulWidget {
  final LatLng? preselectedLatLng;

  const RegisterObjectScreen({super.key, this.preselectedLatLng});

  @override
  State<RegisterObjectScreen> createState() => _RegisterObjectScreenState();
}

class _RegisterObjectScreenState extends State<RegisterObjectScreen> {
  String? _selectedType;
  Position? _currentPosition;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
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

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
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

    final obj = SavedObject(
      name: _selectedType!,
      type: _selectedType!,
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
    );

    await DatabaseService.instance.insertObject(obj);

    if (mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$_selectedType guardado en la ubicación actual'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar Objeto')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _currentPosition == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('No se pudo obtener la ubicación'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _getLocation,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ubicación actual:',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_currentPosition!.latitude.toStringAsFixed(6)}, '
                        '${_currentPosition!.longitude.toStringAsFixed(6)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '¿Qué quieres guardar?',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: objectTypes.length,
                          itemBuilder: (context, index) {
                            final type = objectTypes[index];
                            final isSelected = _selectedType == type['name'];
                            return GestureDetector(
                              onTap: () => setState(() => _selectedType = type['name'] as String),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? type['color'] as Color
                                      : (type['color'] as Color).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? type['color'] as Color
                                        : (type['color'] as Color).withOpacity(0.3),
                                    width: 2,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      type['icon'] as IconData,
                                      size: 36,
                                      color: isSelected ? Colors.white : type['color'] as Color,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      type['name'] as String,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: isSelected ? Colors.white : null,
                                      ),
                                      textAlign: TextAlign.center,
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
                        child: ElevatedButton(
                          onPressed: _selectedType != null ? _save : null,
                          child: const Text(
                            'Guardar en esta ubicación',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
