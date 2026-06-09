import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../models/saved_object.dart';
import '../models/object_group.dart';
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
  List<ObjectGroup> _groups = [];
  Position? _currentPosition;
  bool _loading = true;
  String? _lastSearchQuery;

  @override
  void initState() {
    super.initState();
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
            timeLimit: const Duration(seconds: 5),
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
        if (pos != null) {
          _mapController.move(LatLng(pos.latitude, pos.longitude), 16);
        }
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
      setState(() => _lastSearchQuery = query);
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
        builder: (_) => RegisterObjectScreen(
          preselectedLatLng: pos,
          preselectedName: _lastSearchQuery,
        ),
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
                          setState(() => _lastSearchQuery = null);
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
                ..._buildGroupLayers(),
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
        width: 110,
        height: 80,
        child: GestureDetector(
          onTap: () => _showObjectInfo(obj),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 100),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  obj.name,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: obj.isActive ? color : color.withOpacity(0.4),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
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

  List<Widget> _buildGroupLayers() {
    if (_groups.isEmpty || _currentPosition == null) return [];

    final linePolylines = <Polyline>[];
    final areaPolygons = <Polygon>[];
    final markers = <Marker>[];

    for (final group in _groups) {
      final members = group.sortedObjects;
      if (members.length < 2) continue;

      final points = members.map((m) => LatLng(m.latitude, m.longitude)).toList();

      if (group.type == 'line') {
        linePolylines.add(Polyline(
          points: points,
          color: Colors.blue.withOpacity(0.5),
          strokeWidth: 3,
        ));

        // Segment distance labels
        for (int i = 0; i < points.length - 1; i++) {
          final mid = LatLng(
            (points[i].latitude + points[i + 1].latitude) / 2,
            (points[i].longitude + points[i + 1].longitude) / 2,
          );
          final segDist = Geolocator.distanceBetween(
            points[i].latitude, points[i].longitude,
            points[i + 1].latitude, points[i + 1].longitude,
          );
          markers.add(Marker(
            point: mid,
            width: 60,
            height: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatDistance(segDist),
                style: const TextStyle(color: Colors.white, fontSize: 9),
                textAlign: TextAlign.center,
              ),
            ),
          ));
        }
      } else if (group.type == 'area' && members.length >= 3) {
        areaPolygons.add(Polygon(
          points: points,
          color: Colors.green.withOpacity(0.12),
          borderColor: Colors.green.withOpacity(0.6),
          borderStrokeWidth: 2,
        ));

        // Individual side distances
        for (int i = 0; i < points.length; i++) {
          final next = (i + 1) % points.length;
          final mid = LatLng(
            (points[i].latitude + points[next].latitude) / 2,
            (points[i].longitude + points[next].longitude) / 2,
          );
          final segDist = Geolocator.distanceBetween(
            points[i].latitude, points[i].longitude,
            points[next].latitude, points[next].longitude,
          );
          markers.add(Marker(
            point: mid,
            width: 50,
            height: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.55),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatDistance(segDist),
                style: const TextStyle(color: Colors.white, fontSize: 8),
                textAlign: TextAlign.center,
              ),
            ),
          ));
        }

        final totalDist = _computePerimeter(points);
        final areaValue = _computeArea(points);
        final centroid = _computeCentroid(points);
        markers.add(Marker(
          point: centroid,
          width: 100,
          height: 34,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.7),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'P: ${_formatDistance(totalDist)}',
                  style: const TextStyle(color: Colors.white, fontSize: 9),
                  textAlign: TextAlign.center,
                ),
                Text(
                  _formatArea(areaValue),
                  style: const TextStyle(color: Colors.white70, fontSize: 8),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ));
      }

      // Group name label at centroid
      final centroid = _computeCentroid(points);
      final dist = Geolocator.distanceBetween(
        _currentPosition!.latitude, _currentPosition!.longitude,
        centroid.latitude, centroid.longitude,
      );
      final color = group.type == 'area' ? Colors.green : Colors.blue;
      markers.add(Marker(
        point: centroid,
        width: 120,
        height: 40,
        child: GestureDetector(
          onTap: () => _showGroupInfo(group, dist),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.85),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  group.name,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatDistance(dist),
                  style: const TextStyle(color: Colors.white70, fontSize: 9),
                ),
              ],
            ),
          ),
        ),
      ));
    }

    return [
      if (linePolylines.isNotEmpty) PolylineLayer(polylines: linePolylines),
      if (areaPolygons.isNotEmpty) PolygonLayer(polygons: areaPolygons),
      if (markers.isNotEmpty) MarkerLayer(markers: markers),
    ];
  }

  double _computePerimeter(List<LatLng> points) {
    double total = 0;
    for (int i = 0; i < points.length; i++) {
      final next = (i + 1) % points.length;
      total += Geolocator.distanceBetween(
        points[i].latitude, points[i].longitude,
        points[next].latitude, points[next].longitude,
      );
    }
    return total;
  }

  LatLng _computeCentroid(List<LatLng> points) {
    double lat = 0, lng = 0;
    for (final p in points) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / points.length, lng / points.length);
  }

  double _computeArea(List<LatLng> points) {
    if (points.length < 3) return 0;
    double area = 0;
    final n = points.length;
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      area += points[i].latitude * points[j].longitude;
      area -= points[j].latitude * points[i].longitude;
    }
    area = area.abs() / 2;
    final double latCenter = points.map((p) => p.latitude).reduce((a, b) => a + b) / n;
    final double metersPerDegree = 111320 * math.cos(latCenter * math.pi / 180);
    return area * (metersPerDegree * metersPerDegree);
  }

  void _showGroupInfo(ObjectGroup group, double dist) {
    String? areaText;
    if (group.type == 'area' && group.members != null && group.members!.length >= 3) {
      final points = group.sortedObjects
          .map((m) => LatLng(m.latitude, m.longitude))
          .toList();
      areaText = _formatArea(_computeArea(points));
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(group.type == 'area' ? Icons.change_history : Icons.route, color: Colors.blue),
                const SizedBox(width: 12),
                Text(group.name, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 8),
            Text('A ${_formatDistance(dist)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
            const SizedBox(height: 4),
            Text('${group.type == 'area' ? 'Área' : 'Línea'} · ${group.members?.length ?? 0} objetos',
                style: Theme.of(context).textTheme.bodySmall),
            if (areaText != null) ...[
              const SizedBox(height: 4),
              Text('Superficie: $areaText',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green)),
            ],
          ],
        ),
      ),
    );
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

  String _formatArea(double squareMeters) {
    if (squareMeters < 1) return '${(squareMeters * 10000).round()} cm²';
    if (squareMeters < 10000) return '${squareMeters.round()} m²';
    return '${(squareMeters / 10000).toStringAsFixed(2)} ha';
  }
}
