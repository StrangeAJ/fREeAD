
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  // Add AI provider constants
  static const String providerNone = 'none';
  static const String providerOpenAI = 'openai';
  static const String providerOpenRouter = 'openrouter';
  static const String providerGemini = 'gemini';
  static const String providerClaude = 'claude';
  static const String providerPerplexity = 'perplexity';
  static const String providerNvidia = 'nvidia';
  static const String aiProviderKey = 'ai_provider';
  static const String preferredProviderKey = 'preferred_ai_provider'; // Add preferred provider
  static const String preferOnDeviceAiKey = 'preferOnDeviceAi';
  static const String enabledProvidersKey = 'enabled_ai_providers'; // Add enabled providers list
  static const String autoSaveSummariesKey = 'auto_save_summaries'; // Add auto save summaries setting
  static const String openaiKey = 'openai_api_key';
  static const String openrouterKey = 'openrouter_api_key';
  static const String geminiKey = 'gemini_api_key';
  static const String claudeKey = 'claude_api_key';
  static const String perplexityKey = 'perplexity_api_key';
  static const String nvidiaKey = 'nvidia_api_key';

  // Model selection keys
  static const String openaiModelKey = 'openai_model';
  static const String openrouterModelKey = 'openrouter_model';
  static const String geminiModelKey = 'gemini_model';
  static const String claudeModelKey = 'claude_model';
  static const String perplexityModelKey = 'perplexity_model';
  static const String nvidiaModelKey = 'nvidia_model';

  SharedPreferences? _prefs;
  final _secureStorage = const FlutterSecureStorage();
  
  ThemeMode _themeMode = ThemeMode.system;
  double _fontSize = 16.0;
  bool _autoRefresh = true;
  int _refreshInterval = 30; // minutes
  bool _notificationsEnabled = true;
  bool _markAsReadOnScroll = false;
  int _articleCleanupDays = 30;
  bool _imageLoadingEnabled = true;

  // Add fields
  String _aiProvider = providerNone;
  String _preferredProvider = providerNone;
  bool _preferOnDeviceAi = false; // Add preferred provider field
  List<String> _enabledProviders = []; // Add enabled providers list
  bool _autoSaveSummaries = true; // Add auto save summaries field (default on)
  String _openaiApiKey = '';
  String _openrouterApiKey = '';
  String _geminiApiKey = '';
  String _claudeApiKey = '';
  String _perplexityApiKey = '';
  String _nvidiaApiKey = '';

  // Model selection fields
  String _openaiModel = 'gpt-4o-mini';
  String _openrouterModel = 'google/gemini-flash-1.5-8b';
  String _geminiModel = 'gemini-1.5-flash';
  String _claudeModel = 'claude-3-5-haiku-20241022';
  String _perplexityModel = 'llama-3.1-8b-instruct';
  String _nvidiaModel = 'nvidia/llama-3.1-405b-instruct';

  // Getters
  ThemeMode get themeMode => _themeMode;
  double get fontSize => _fontSize;
  bool get autoRefresh => _autoRefresh;
  int get refreshInterval => _refreshInterval;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get markAsReadOnScroll => _markAsReadOnScroll;
  int get articleCleanupDays => _articleCleanupDays;
  bool get imageLoadingEnabled => _imageLoadingEnabled;
  String get aiProvider => _aiProvider;
  String get preferredProvider => _preferredProvider;
  bool get preferOnDeviceAi => _preferOnDeviceAi;
  List<String> get enabledProviders => _enabledProviders;
  bool get autoSaveSummaries => _autoSaveSummaries; // Add getter for auto save summaries
  String get openaiApiKey => _openaiApiKey;
  String get openrouterApiKey => _openrouterApiKey;
  String get geminiApiKey => _geminiApiKey;
  String get claudeApiKey => _claudeApiKey;
  String get perplexityApiKey => _perplexityApiKey;
  String get nvidiaApiKey => _nvidiaApiKey;

  // Model selection getters
  String get openaiModel => _openaiModel;
  String get openrouterModel => _openrouterModel;
  String get geminiModel => _geminiModel;
  String get claudeModel => _claudeModel;
  String get perplexityModel => _perplexityModel;
  String get nvidiaModel => _nvidiaModel;

  String getApiKeyForProvider(String provider) {
    switch (provider) {
      case providerOpenAI:
        return _openaiApiKey;
      case providerOpenRouter:
        return _openrouterApiKey;
      case providerGemini:
        return _geminiApiKey;
      case providerClaude:
        return _claudeApiKey;
      case providerPerplexity:
        return _perplexityApiKey;
      case providerNvidia:
        return _nvidiaApiKey;
      default:
        return '';
    }
  }

  String getModelForProvider(String provider) {
    switch (provider) {
      case providerOpenAI:
        return _openaiModel;
      case providerOpenRouter:
        return _openrouterModel;
      case providerGemini:
        return _geminiModel;
      case providerClaude:
        return _claudeModel;
      case providerPerplexity:
        return _perplexityModel;
      case providerNvidia:
        return _nvidiaModel;
      default:
        return '';
    }
  }

  Future<void> setModelForProvider(String provider, String model) async {
    switch (provider) {
      case providerOpenAI:
        await setOpenaiModel(model);
        break;
      case providerOpenRouter:
        await setOpenrouterModel(model);
        break;
      case providerGemini:
        await setGeminiModel(model);
        break;
      case providerClaude:
        await setClaudeModel(model);
        break;
      case providerPerplexity:
        await setPerplexityModel(model);
        break;
      case providerNvidia:
        await setNvidiaModel(model);
        break;
    }
  }

  // Check if a provider is configured (has API key)
  bool isProviderConfigured(String provider) {
    switch (provider) {
      case providerOpenAI:
        return _openaiApiKey.isNotEmpty;
      case providerOpenRouter:
        return _openrouterApiKey.isNotEmpty;
      case providerGemini:
        return _geminiApiKey.isNotEmpty;
      case providerClaude:
        return _claudeApiKey.isNotEmpty;
      case providerPerplexity:
        return _perplexityApiKey.isNotEmpty;
      case providerNvidia:
        return _nvidiaApiKey.isNotEmpty;
      default:
        return false;
    }
  }

  // Get list of configured providers
  List<String> get configuredProviders {
    return availableAiProviders
        .where((entry) => entry.key != providerNone && isProviderConfigured(entry.key))
        .map((entry) => entry.key)
        .toList();
  }

  // Get next available configured provider for fallback
  String? getNextAvailableProvider(String currentProvider) {
    final available = configuredProviders.where((p) => p != currentProvider).toList();
    if (available.isNotEmpty) {
      // Prefer the preferred provider if it's different and available
      if (_preferredProvider != currentProvider && available.contains(_preferredProvider)) {
        return _preferredProvider;
      }
      // Otherwise return first available
      return available.first;
    }
    return null;
  }

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

    // AI provider settings
    _aiProvider = _prefs!.getString(aiProviderKey) ?? providerNone;
    _preferredProvider = _prefs!.getString(preferredProviderKey) ?? providerNone;
    _preferOnDeviceAi = _prefs!.getBool(preferOnDeviceAiKey) ?? false;
    _autoSaveSummaries = _prefs!.getBool(autoSaveSummariesKey) ?? true; // Load auto save summaries setting

    // Load enabled providers list
    final enabledProvidersJson = _prefs!.getStringList(enabledProvidersKey) ?? [];
    _enabledProviders = enabledProvidersJson;

    _openaiApiKey = await _loadOrMigrateSecureKey(openaiKey);
    _openrouterApiKey = await _loadOrMigrateSecureKey(openrouterKey);
    _geminiApiKey = await _loadOrMigrateSecureKey(geminiKey);
    _claudeApiKey = await _loadOrMigrateSecureKey(claudeKey);
    _perplexityApiKey = await _loadOrMigrateSecureKey(perplexityKey);
    _nvidiaApiKey = await _loadOrMigrateSecureKey(nvidiaKey);

    // Load models
    _openaiModel = _prefs!.getString(openaiModelKey) ?? 'gpt-4o-mini';
    _openrouterModel = _prefs!.getString(openrouterModelKey) ?? 'google/gemini-flash-1.5-8b';
    _geminiModel = _prefs!.getString(geminiModelKey) ?? 'gemini-1.5-flash';
    _claudeModel = _prefs!.getString(claudeModelKey) ?? 'claude-3-5-haiku-20241022';
    _perplexityModel = _prefs!.getString(perplexityModelKey) ?? 'llama-3.1-8b-instruct';
    _nvidiaModel = _prefs!.getString(nvidiaModelKey) ?? 'nvidia/llama-3.1-405b-instruct';

    notifyListeners();
  }

  Future<String> _loadOrMigrateSecureKey(String key) async {
    // Try to read from secure storage
    String? secureValue = await _secureStorage.read(key: key);

    // If not in secure storage, check shared preferences for migration
    if (secureValue == null || secureValue.isEmpty) {
      final prefsValue = _prefs!.getString(key);
      if (prefsValue != null && prefsValue.isNotEmpty) {
        // Migrate to secure storage
        await _secureStorage.write(key: key, value: prefsValue);
        // Remove from shared preferences
        await _prefs!.remove(key);
        return prefsValue;
      }
    }
    return secureValue ?? '';
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

  // Set AI provider
  Future<void> setAiProvider(String provider) async {
    _aiProvider = provider;
    await _prefs?.setString(aiProviderKey, provider);
    notifyListeners();
  }

  Future<void> setPreferredProvider(String provider) async {
    _preferredProvider = provider;
    await _prefs?.setString(preferredProviderKey, provider);
    notifyListeners();
  }

  Future<void> setPreferOnDeviceAi(bool prefer) async {
    _preferOnDeviceAi = prefer;
    await _prefs?.setBool(preferOnDeviceAiKey, prefer);
    notifyListeners();
  }

  // API Key setters
  Future<void> setOpenaiApiKey(String key) async {
    _openaiApiKey = key;
    await _secureStorage.write(key: openaiKey, value: key);
    notifyListeners();
  }

  Future<void> setOpenrouterApiKey(String key) async {
    _openrouterApiKey = key;
    await _secureStorage.write(key: openrouterKey, value: key);
    notifyListeners();
  }

  Future<void> setGeminiApiKey(String key) async {
    _geminiApiKey = key;
    await _secureStorage.write(key: geminiKey, value: key);
    notifyListeners();
  }

  Future<void> setClaudeApiKey(String key) async {
    _claudeApiKey = key;
    await _secureStorage.write(key: claudeKey, value: key);
    notifyListeners();
  }

  Future<void> setPerplexityApiKey(String key) async {
    _perplexityApiKey = key;
    await _secureStorage.write(key: perplexityKey, value: key);
    notifyListeners();
  }

  Future<void> setNvidiaApiKey(String key) async {
    _nvidiaApiKey = key;
    await _secureStorage.write(key: nvidiaKey, value: key);
    notifyListeners();
  }

  // Model selection setters
  Future<void> setOpenaiModel(String model) async {
    _openaiModel = model;
    await _prefs?.setString(openaiModelKey, model);
    notifyListeners();
  }

  Future<void> setOpenrouterModel(String model) async {
    _openrouterModel = model;
    await _prefs?.setString(openrouterModelKey, model);
    notifyListeners();
  }

  Future<void> setGeminiModel(String model) async {
    _geminiModel = model;
    await _prefs?.setString(geminiModelKey, model);
    notifyListeners();
  }

  Future<void> setClaudeModel(String model) async {
    _claudeModel = model;
    await _prefs?.setString(claudeModelKey, model);
    notifyListeners();
  }

  Future<void> setPerplexityModel(String model) async {
    _perplexityModel = model;
    await _prefs?.setString(perplexityModelKey, model);
    notifyListeners();
  }

  Future<void> setNvidiaModel(String model) async {
    _nvidiaModel = model;
    await _prefs?.setString(nvidiaModelKey, model);
    notifyListeners();
  }

  // Set auto save summaries
  Future<void> setAutoSaveSummaries(bool enabled) async {
    _autoSaveSummaries = enabled;
    await _prefs?.setBool(autoSaveSummariesKey, enabled);
    notifyListeners();
  }

  // Toggle provider in enabled list
  Future<void> toggleProviderEnabled(String provider, bool enabled) async {
    if (enabled && !_enabledProviders.contains(provider)) {
      _enabledProviders.add(provider);
    } else if (!enabled && _enabledProviders.contains(provider)) {
      _enabledProviders.remove(provider);
    }
    await _prefs?.setStringList(enabledProvidersKey, _enabledProviders);
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

  // Get available AI providers
  List<MapEntry<String, String>> get availableAiProviders => [
    const MapEntry(providerNone, 'None (Local)'),
    const MapEntry(providerOpenAI, 'OpenAI'),
    const MapEntry(providerOpenRouter, 'OpenRouter'),
    const MapEntry(providerGemini, 'Gemini'),
    const MapEntry(providerClaude, 'Claude'),
    const MapEntry(providerPerplexity, 'Perplexity'),
    const MapEntry(providerNvidia, 'Nvidia NIM'),
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
    _aiProvider = providerNone;
    _preferredProvider = providerNone;
    _preferOnDeviceAi = false;
    _enabledProviders = [];
    _openaiApiKey = '';
    _openrouterApiKey = '';
    _geminiApiKey = '';
    _claudeApiKey = '';
    _perplexityApiKey = '';
    _nvidiaApiKey = '';

    await _secureStorage.delete(key: openaiKey);
    await _secureStorage.delete(key: openrouterKey);
    await _secureStorage.delete(key: geminiKey);
    await _secureStorage.delete(key: claudeKey);
    await _secureStorage.delete(key: perplexityKey);
    await _secureStorage.delete(key: nvidiaKey);

    _openaiModel = 'gpt-4o-mini';
    _openrouterModel = 'google/gemini-flash-1.5-8b';
    _geminiModel = 'gemini-1.5-flash';
    _claudeModel = 'claude-3-5-haiku-20241022';
    _perplexityModel = 'llama-3.1-8b-instruct';
    _nvidiaModel = 'nvidia/llama-3.1-405b-instruct';

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
      aiProviderKey: _aiProvider,
      preferredProviderKey: _preferredProvider,
      preferOnDeviceAiKey: _preferOnDeviceAi,
      enabledProvidersKey: _enabledProviders,
      openaiModelKey: _openaiModel,
      openrouterModelKey: _openrouterModel,
      geminiModelKey: _geminiModel,
      claudeModelKey: _claudeModel,
      perplexityModelKey: _perplexityModel,
      nvidiaModelKey: _nvidiaModel,
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
        // AI provider and API key entries
        case preferredProviderKey:
        case aiProviderKey:
        case openaiModelKey:
        case openrouterModelKey:
        case geminiModelKey:
        case claudeModelKey:
        case perplexityModelKey:
        case nvidiaModelKey:
          await _prefs!.setString(entry.key, entry.value);
          break;
        case openaiKey:
        case openrouterKey:
        case geminiKey:
        case claudeKey:
        case perplexityKey:
        case nvidiaKey:
          await _secureStorage.write(key: entry.key, value: entry.value);
          break;
        case enabledProvidersKey:
          await _prefs!.setStringList(entry.key, List<String>.from(entry.value));
          break;
        default:
          await _prefs!.setBool(entry.key, entry.value);
      }
    }

    await _loadSettings();
  }
}
