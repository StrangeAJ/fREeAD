class Category {
  final String id;
  final String name;
  final String description;
  final String? iconName;
  final String? color;
  final DateTime dateCreated;
  final int sortOrder;
  final bool isDefault;

  Category({
    required this.id,
    required this.name,
    required this.description,
    this.iconName,
    this.color,
    required this.dateCreated,
    this.sortOrder = 0,
    this.isDefault = false,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      iconName: json['iconName'],
      color: json['color'],
      dateCreated: DateTime.parse(json['dateCreated']),
      sortOrder: json['sortOrder'] ?? 0,
      isDefault: json['isDefault'] is int ? json['isDefault'] == 1 : (json['isDefault'] ?? false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'iconName': iconName,
      'color': color,
      'dateCreated': dateCreated.toIso8601String(),
      'sortOrder': sortOrder,
      'isDefault': isDefault ? 1 : 0,
    };
  }

  Category copyWith({
    String? id,
    String? name,
    String? description,
    String? iconName,
    String? color,
    DateTime? dateCreated,
    int? sortOrder,
    bool? isDefault,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      iconName: iconName ?? this.iconName,
      color: color ?? this.color,
      dateCreated: dateCreated ?? this.dateCreated,
      sortOrder: sortOrder ?? this.sortOrder,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Category && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Category(id: $id, name: $name)';
  }

  // Default categories that will be created on first app launch
  static List<Category> get defaultCategories {
    final now = DateTime.now();
    return [
      Category(
        id: 'general',
        name: 'General',
        description: 'General news and articles',
        iconName: 'newspaper',
        color: '#6750A4',
        dateCreated: now,
        sortOrder: 0,
        isDefault: true,
      ),
      Category(
        id: 'technology',
        name: 'Technology',
        description: 'Tech news and updates',
        iconName: 'computer',
        color: '#00BCD4',
        dateCreated: now,
        sortOrder: 1,
        isDefault: true,
      ),
      Category(
        id: 'sports',
        name: 'Sports',
        description: 'Sports news and updates',
        iconName: 'sports_soccer',
        color: '#FF9800',
        dateCreated: now,
        sortOrder: 2,
        isDefault: true,
      ),
      Category(
        id: 'entertainment',
        name: 'Entertainment',
        description: 'Entertainment and celebrity news',
        iconName: 'movie',
        color: '#E91E63',
        dateCreated: now,
        sortOrder: 3,
        isDefault: true,
      ),
      Category(
        id: 'business',
        name: 'Business',
        description: 'Business and finance news',
        iconName: 'business',
        color: '#4CAF50',
        dateCreated: now,
        sortOrder: 4,
        isDefault: true,
      ),
    ];
  }
}
