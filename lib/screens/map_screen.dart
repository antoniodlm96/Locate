import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../models/saved_object.dart';
import '../services/database_service.dart';
import 'register_object_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  List<SavedObject> _objects = [];
  Position? _currentPosition;
  bool _loading = true;
  bool _mapReady = false;

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
            timeLimit: const Duration(seconds: 5),
          );
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _objects = objects;
          _currentPosition = pos;
          _loading = false;
        });
        if (pos != null) {
          _mapController.move(LatLng(pos.latitude, pos.longitude), 16);
        }
        _mapReady = true;
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchPlace() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    try {
      final locations = await locationFromAddress(query);
      if (locations.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se encontró el lugar')),
          );
        }
        return;
      }
      final loc = locations.first;
      _mapController.move(LatLng(loc.latitude, loc.longitude), 17);
      _searchController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error en la búsqueda: $e')),
        );
      }
    }
  }

  Future<void> _addObjectAtTap(LatLng pos) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RegisterObjectScreen(preselectedLatLng: pos),
      ),
    );
    if (result == true) {
      final objects = await DatabaseService.instance.getAllObjects();
      if (mounted) setState(() => _objects = objects);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscar en Mapa'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar lugar, calle...',
                prefixIcon: const Icon(Icons.search, size: 24),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                filled: true,
                fillColor: theme.colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _searchPlace(),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentPosition != null
                    ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                    : const LatLng(40.4168, -3.7038),
                initialZoom: _currentPosition != null ? 16 : 6,
                onTap: (tapPos, latlng) => _addObjectAtTap(latlng),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.antonio.locate',
                  maxZoom: 19,
                ),
                if (_currentPosition != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                        ),
                          width: 48,
                        height: 48,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.my_location, color: Colors.white, size: 24),
                        ),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: _buildMarkers(),
                ),
              ],
            ),
    );
  }

  List<Marker> _buildMarkers() {
    return _objects.map((obj) {
      final typeEntry = _findTypeEntry(obj.type);
      final color = typeEntry?['color'] as Color? ?? Colors.grey;
      final icon = typeEntry?['icon'] as IconData? ?? Icons.place;

      return Marker(
        point: LatLng(obj.latitude, obj.longitude),
        width: 100,
        height: 60,
        child: GestureDetector(
          onTap: () => _showObjectInfo(obj),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  obj.name,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: obj.isActive ? color : color.withOpacity(0.4),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Map<String, dynamic>? _findTypeEntry(String type) {
    for (final t in objectTypes) {
      if (t['name'] == type) return t;
    }
    return null;
  }

  void _showObjectInfo(SavedObject obj) {
    String? distText;
    if (_currentPosition != null) {
      final dist = Geolocator.distanceBetween(
        _currentPosition!.latitude, _currentPosition!.longitude,
        obj.latitude, obj.longitude,
      );
      distText = _formatDistance(dist);
    }

    final typeEntry = _findTypeEntry(obj.type);
    final color = typeEntry?['color'] as Color? ?? Colors.grey;
    final icon = typeEntry?['icon'] as IconData? ?? Icons.place;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              backgroundColor: color,
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(obj.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(obj.type, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
            if (distText != null) ...[
              const SizedBox(height: 8),
              Text('A $distText', style: Theme.of(context).textTheme.bodyLarge),
            ],
            const SizedBox(height: 4),
            Text(
              '${obj.latitude.toStringAsFixed(6)}, ${obj.longitude.toStringAsFixed(6)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),
            if (!obj.isActive)
              Text('Desactivado en RA',
                style: TextStyle(color: Colors.orange.shade700, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1) return '${(meters * 100).round()} cm';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}
