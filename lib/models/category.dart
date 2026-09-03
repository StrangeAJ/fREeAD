import 'package:flutter/material.dart';

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
      isDefault: json['isDefault'] is int
          ? json['isDefault'] == 1
          : (json['isDefault'] ?? false),
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

  /// Number of feeds in this category (populated by FeedProvider).
  int feedsCount = 0;

  /// Returns an icon widget for this category.
  Widget iconWidget({double size = 24, Color? color}) {
    return Icon(icon, size: size, color: color ?? colorValue);
  }

  @override
  String toString() {
    return 'Category(id: $id, name: $name)';
  }

  /// Fallback colour used when [color] is missing or malformed.
  static const Color fallbackColor = Color(0xFF94A3B8);

  /// Material rounded icon for [iconName].
  IconData get icon => iconForName(iconName);

  /// Parsed `#RRGGBB` / `#AARRGGBB` colour, falling back to [fallbackColor].
  Color get colorValue => parseColor(color);

  static Color parseColor(String? value) {
    if (value == null) return fallbackColor;
    var hex = value.trim().replaceFirst('#', '').replaceFirst('0x', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return fallbackColor;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return fallbackColor;
    return Color(parsed);
  }

  static IconData iconForName(String? name) {
    if (name == null) return Icons.rss_feed_rounded;
    return _iconMap[name.trim().toLowerCase()] ?? Icons.rss_feed_rounded;
  }

  /// Icon names offered by the category manager.
  static List<String> get availableIconNames => _iconMap.keys.toList();

  static const Map<String, IconData> _iconMap = <String, IconData>{
    'newspaper': Icons.newspaper_rounded,
    'public': Icons.public_rounded,
    'memory': Icons.memory_rounded,
    'code': Icons.code_rounded,
    'science': Icons.science_rounded,
    'trending_up': Icons.trending_up_rounded,
    'sports_soccer': Icons.sports_soccer_rounded,
    'movie': Icons.movie_rounded,
    'sports_esports': Icons.sports_esports_rounded,
    'favorite': Icons.favorite_rounded,
    'palette': Icons.palette_rounded,
    'spa': Icons.spa_rounded,
    'rss_feed': Icons.rss_feed_rounded,
    'computer': Icons.computer_rounded,
    'business': Icons.business_rounded,
    'school': Icons.school_rounded,
    'music_note': Icons.music_note_rounded,
    'camera': Icons.photo_camera_rounded,
    'restaurant': Icons.restaurant_rounded,
    'flight': Icons.flight_rounded,
    'directions_car': Icons.directions_car_rounded,
    'pets': Icons.pets_rounded,
    'auto_stories': Icons.auto_stories_rounded,
    'bolt': Icons.bolt_rounded,
    'psychology': Icons.psychology_rounded,
    'account_balance': Icons.account_balance_rounded,
    'shopping_bag': Icons.shopping_bag_rounded,
    'terminal': Icons.terminal_rounded,
  };

  /// Default categories created on first launch (and back-filled by migrations).
  static List<Category> get defaultCategories {
    final now = DateTime.now();
    const seeds = <List<String>>[
      [
        'general',
        'General',
        'General news and articles',
        'newspaper',
        '#94A3B8',
      ],
      [
        'news',
        'News & Politics',
        'World news, politics and current affairs',
        'public',
        '#60A5FA',
      ],
      [
        'technology',
        'Technology',
        'Tech news, gadgets and industry updates',
        'memory',
        '#22D3EE',
      ],
      [
        'programming',
        'Programming',
        'Software development and engineering',
        'code',
        '#A78BFA',
      ],
      [
        'science',
        'Science',
        'Research, space and discovery',
        'science',
        '#34D399',
      ],
      [
        'business',
        'Business & Finance',
        'Markets, economy and startups',
        'trending_up',
        '#FBBF24',
      ],
      [
        'sports',
        'Sports',
        'Scores, analysis and sports news',
        'sports_soccer',
        '#FB923C',
      ],
      [
        'entertainment',
        'Entertainment',
        'Film, TV, music and celebrity news',
        'movie',
        '#F472B6',
      ],
      [
        'gaming',
        'Gaming',
        'Video games, reviews and esports',
        'sports_esports',
        '#C084FC',
      ],
      [
        'health',
        'Health',
        'Health, fitness and medicine',
        'favorite',
        '#F87171',
      ],
      [
        'culture',
        'Art & Design',
        'Art, design and architecture',
        'palette',
        '#E879F9',
      ],
      [
        'lifestyle',
        'Lifestyle',
        'Food, travel and everyday living',
        'spa',
        '#4ADE80',
      ],
    ];

    return [
      for (var i = 0; i < seeds.length; i++)
        Category(
          id: seeds[i][0],
          name: seeds[i][1],
          description: seeds[i][2],
          iconName: seeds[i][3],
          color: seeds[i][4],
          dateCreated: now,
          sortOrder: i,
          isDefault: true,
        ),
    ];
  }
}
