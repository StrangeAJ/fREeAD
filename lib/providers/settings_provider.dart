import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  static const String _fontSizeKey = 'font_size';
  static const String _autoRefreshKey = 'auto_refresh';
  static const String _refreshIntervalKey = 'refresh_interval';
  static const String _notificationsKey = 'notifications_enabled';
  static const String _markAsReadOnScrollKey = 'mark_as_read_on_scroll';
  static const String _articleCleanupKey = 'article_cleanup_days';
  static const String _imageLoadingKey = 'image_loading_enabled';

  SharedPreferences? _prefs;
  
  ThemeMode _themeMode = ThemeMode.system;
  double _fontSize = 16.0;
  bool _autoRefresh = true;
  int _refreshInterval = 30; // minutes
  bool _notificationsEnabled = true;
  bool _markAsReadOnScroll = false;
  int _articleCleanupDays = 30;
  bool _imageLoadingEnabled = true;

  // Getters
  ThemeMode get themeMode => _themeMode;
  double get fontSize => _fontSize;
  bool get autoRefresh => _autoRefresh;
  int get refreshInterval => _refreshInterval;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get markAsReadOnScroll => _markAsReadOnScroll;
  int get articleCleanupDays => _articleCleanupDays;
  bool get imageLoadingEnabled => _imageLoadingEnabled;

  // Initialize settings
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadSettings();
  }

  // Load settings from SharedPreferences
  Future<void> _loadSettings() async {
    if (_prefs == null) return;

    // Theme mode
    final themeIndex = _prefs!.getInt(_themeKey) ?? 0;
    _themeMode = ThemeMode.values[themeIndex];

    // Font size
    _fontSize = _prefs!.getDouble(_fontSizeKey) ?? 16.0;

    // Auto refresh
    _autoRefresh = _prefs!.getBool(_autoRefreshKey) ?? true;

    // Refresh interval
    _refreshInterval = _prefs!.getInt(_refreshIntervalKey) ?? 30;

    // Notifications
    _notificationsEnabled = _prefs!.getBool(_notificationsKey) ?? true;

    // Mark as read on scroll
    _markAsReadOnScroll = _prefs!.getBool(_markAsReadOnScrollKey) ?? false;

    // Article cleanup days
    _articleCleanupDays = _prefs!.getInt(_articleCleanupKey) ?? 30;

    // Image loading
    _imageLoadingEnabled = _prefs!.getBool(_imageLoadingKey) ?? true;

    notifyListeners();
  }

  // Set theme mode
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs?.setInt(_themeKey, mode.index);
    notifyListeners();
  }

  // Set font size
  Future<void> setFontSize(double size) async {
    _fontSize = size;
    await _prefs?.setDouble(_fontSizeKey, size);
    notifyListeners();
  }

  // Set auto refresh
  Future<void> setAutoRefresh(bool enabled) async {
    _autoRefresh = enabled;
    await _prefs?.setBool(_autoRefreshKey, enabled);
    notifyListeners();
  }

  // Set refresh interval
  Future<void> setRefreshInterval(int minutes) async {
    _refreshInterval = minutes;
    await _prefs?.setInt(_refreshIntervalKey, minutes);
    notifyListeners();
  }

  // Set notifications enabled
  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled = enabled;
    await _prefs?.setBool(_notificationsKey, enabled);
    notifyListeners();
  }

  // Set mark as read on scroll
  Future<void> setMarkAsReadOnScroll(bool enabled) async {
    _markAsReadOnScroll = enabled;
    await _prefs?.setBool(_markAsReadOnScrollKey, enabled);
    notifyListeners();
  }

  // Set article cleanup days
  Future<void> setArticleCleanupDays(int days) async {
    _articleCleanupDays = days;
    await _prefs?.setInt(_articleCleanupKey, days);
    notifyListeners();
  }

  // Set image loading enabled
  Future<void> setImageLoadingEnabled(bool enabled) async {
    _imageLoadingEnabled = enabled;
    await _prefs?.setBool(_imageLoadingKey, enabled);
    notifyListeners();
  }

  // Get available theme modes
  List<MapEntry<ThemeMode, String>> get availableThemes => [
    const MapEntry(ThemeMode.system, 'System'),
    const MapEntry(ThemeMode.light, 'Light'),
    const MapEntry(ThemeMode.dark, 'Dark'),
  ];

  // Get available font sizes
  List<MapEntry<double, String>> get availableFontSizes => [
    const MapEntry(12.0, 'Small'),
    const MapEntry(14.0, 'Normal'),
    const MapEntry(16.0, 'Medium'),
    const MapEntry(18.0, 'Large'),
    const MapEntry(20.0, 'Extra Large'),
  ];

  // Get available refresh intervals
  List<MapEntry<int, String>> get availableRefreshIntervals => [
    const MapEntry(15, '15 minutes'),
    const MapEntry(30, '30 minutes'),
    const MapEntry(60, '1 hour'),
    const MapEntry(120, '2 hours'),
    const MapEntry(240, '4 hours'),
    const MapEntry(480, '8 hours'),
    const MapEntry(720, '12 hours'),
    const MapEntry(1440, '24 hours'),
  ];

  // Get available cleanup periods
  List<MapEntry<int, String>> get availableCleanupPeriods => [
    const MapEntry(7, '1 week'),
    const MapEntry(14, '2 weeks'),
    const MapEntry(30, '1 month'),
    const MapEntry(60, '2 months'),
    const MapEntry(90, '3 months'),
    const MapEntry(180, '6 months'),
    const MapEntry(365, '1 year'),
    const MapEntry(0, 'Never'),
  ];

  // Reset all settings to default
  Future<void> resetToDefaults() async {
    await _prefs?.clear();
    
    _themeMode = ThemeMode.system;
    _fontSize = 16.0;
    _autoRefresh = true;
    _refreshInterval = 30;
    _notificationsEnabled = true;
    _markAsReadOnScroll = false;
    _articleCleanupDays = 30;
    _imageLoadingEnabled = true;
    
    notifyListeners();
  }

  // Export settings
  Map<String, dynamic> exportSettings() {
    return {
      _themeKey: _themeMode.index,
      _fontSizeKey: _fontSize,
      _autoRefreshKey: _autoRefresh,
      _refreshIntervalKey: _refreshInterval,
      _notificationsKey: _notificationsEnabled,
      _markAsReadOnScrollKey: _markAsReadOnScroll,
      _articleCleanupKey: _articleCleanupDays,
      _imageLoadingKey: _imageLoadingEnabled,
    };
  }

  // Import settings
  Future<void> importSettings(Map<String, dynamic> settings) async {
    if (_prefs == null) return;

    for (final entry in settings.entries) {
      switch (entry.key) {
        case _themeKey:
          await _prefs!.setInt(entry.key, entry.value);
          break;
        case _fontSizeKey:
          await _prefs!.setDouble(entry.key, entry.value);
          break;
        case _refreshIntervalKey:
        case _articleCleanupKey:
          await _prefs!.setInt(entry.key, entry.value);
          break;
        default:
          await _prefs!.setBool(entry.key, entry.value);
      }
    }

    await _loadSettings();
  }
}
