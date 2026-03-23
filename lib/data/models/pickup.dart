// lib/data/models/pickup.dart
// Pickup entity — groups related measurements by guitar pickup.

class Pickup {
  /// UUID
  final String id;

  /// User-assigned, e.g. "PAF neck"
  final String name;

  final String? notes;
  final DateTime createdAt;

  /// Measurement UUIDs, ordered by date ascending.
  final List<String> measurementIds;

  const Pickup({
    required this.id,
    required this.name,
    this.notes,
    required this.createdAt,
    this.measurementIds = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'measurementIds': measurementIds,
      };

  factory Pickup.fromJson(Map<String, dynamic> json) => Pickup(
        id: json['id'] as String,
        name: json['name'] as String,
        notes: json['notes'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        measurementIds:
            (json['measurementIds'] as List?)?.cast<String>() ?? [],
      );

  Pickup copyWith({
    String? id,
    String? name,
    String? notes,
    DateTime? createdAt,
    List<String>? measurementIds,
  }) =>
      Pickup(
        id: id ?? this.id,
        name: name ?? this.name,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
        measurementIds: measurementIds ?? this.measurementIds,
      );
}
