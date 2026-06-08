import 'saved_object.dart';

class ObjectGroup {
  final int? id;
  final String name;
  final String type; // 'line' or 'area'
  final DateTime createdAt;
  List<ObjectGroupMember>? members;

  ObjectGroup({
    this.id,
    required this.name,
    required this.type,
    DateTime? createdAt,
    this.members,
  }) : createdAt = createdAt ?? DateTime.now();

  List<SavedObject> get sortedObjects {
    if (members == null) return [];
    final sorted = List<ObjectGroupMember>.from(members!)
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return sorted.map((m) => m.object!).toList();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ObjectGroup.fromMap(Map<String, dynamic> map) {
    return ObjectGroup(
      id: map['id'] as int?,
      name: map['name'] as String,
      type: map['type'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class ObjectGroupMember {
  final int? id;
  final int groupId;
  final int objectId;
  final int orderIndex;
  final DateTime createdAt;
  SavedObject? object;

  ObjectGroupMember({
    this.id,
    required this.groupId,
    required this.objectId,
    this.orderIndex = 0,
    DateTime? createdAt,
    this.object,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'group_id': groupId,
      'object_id': objectId,
      'order_index': orderIndex,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ObjectGroupMember.fromMap(Map<String, dynamic> map) {
    return ObjectGroupMember(
      id: map['id'] as int?,
      groupId: map['group_id'] as int,
      objectId: map['object_id'] as int,
      orderIndex: map['order_index'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      object: map['_object'] as SavedObject?,
    );
  }
}
