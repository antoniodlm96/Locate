class SavedObject {
  final int? id;
  final String name;
  final String type;
  final double latitude;
  final double longitude;
  final bool isActive;
  final DateTime createdAt;

  SavedObject({
    this.id,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.isActive = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  SavedObject copyWith({
    int? id,
    String? name,
    String? type,
    double? latitude,
    double? longitude,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return SavedObject(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'latitude': latitude,
      'longitude': longitude,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SavedObject.fromMap(Map<String, dynamic> map) {
    return SavedObject(
      id: map['id'] as int?,
      name: map['name'] as String,
      type: map['type'] as String,
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      isActive: (map['is_active'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
