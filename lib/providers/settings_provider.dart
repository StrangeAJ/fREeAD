import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsProvider with ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  static const String _fontSizeKey = 'font_size';

  static const String providerOpenAI = 'openai';
  static const String providerClaude = 'claude';
  static const String providerGemini = 'gemini';
  static const String providerOpenRouter = 'openrouter';
  static const String providerPerplexity = 'perplexity';
  static const String providerNvidia = 'nvidia';
  static const String providerNone = 'none';

  static const String openaiKey = 'openai_api_key';
  static const String claudeKey = 'claude_api_key';
  static const String geminiKey = 'gemini_api_key';
  static const String openrouterKey = 'openrouter_api_key';
  static const String perplexityKey = 'perplexity_api_key';
  static const String nvidiaKey = 'nvidia_api_key';

  static const String openaiModelKey = 'openai_model';
  static const String nvidiaModelKey = 'nvidia_model';

  static const String aiProviderKey = 'ai_provider';
  static const String preferredProviderKey = 'preferred_provider';
  static const String preferOnDeviceAiKey = 'prefer_on_device_ai';
  static const String autoSaveSummariesKey = 'auto_save_summaries';
  static const String enabledProvidersKey = 'enabled_providers';
  static const String _imageLoadingKey = 'image_loading';
  static const String _autoRefreshKey = 'auto_refresh';
  static const String _refreshIntervalKey = 'refresh_interval';
  static const String _notificationsKey = 'notifications';
  static const String _markAsReadOnScrollKey = 'mark_as_read_on_scroll';
  static const String _articleCleanupKey = 'article_cleanup';

  SharedPreferences? _prefs;
  final _secureStorage = const FlutterSecureStorage();

  ThemeMode _themeMode = ThemeMode.system;
  double _fontSize = 18.0;
  String _summarizationProvider = providerGemini;

  bool _autoRefresh = true;
  int _refreshInterval = 30;
  bool _notificationsEnabled = true;
  bool _markAsReadOnScroll = false;
  int _articleCleanupDays = 30;
  bool _imageLoadingEnabled = true;
  String _aiProvider = providerNone;
  String _preferredProvider = providerNone;
  bool _preferOnDeviceAi = false;
  bool _autoSaveSummaries = true;
  List<String> _enabledProviders = [];

  String _openaiApiKey = '';
  String _claudeApiKey = '';
  String _geminiApiKey = '';
  String _openrouterApiKey = '';
  String _perplexityApiKey = '';
  String _nvidiaApiKey = '';

  String _openaiModel = 'gpt-4o-mini';
  String _nvidiaModel = 'nvidia/llama-3.1-405b-instruct';

  ThemeMode get themeMode => _themeMode;
  double get fontSize => _fontSize;
  String get summarizationProvider => _summarizationProvider;

  String get openaiApiKey => _openaiApiKey;
  String get claudeApiKey => _claudeApiKey;
  String get geminiApiKey => _geminiApiKey;
  String get openrouterApiKey => _openrouterApiKey;
  String get perplexityApiKey => _perplexityApiKey;
  String get nvidiaApiKey => _nvidiaApiKey;

  String get openaiModel => _openaiModel;
  String get nvidiaModel => _nvidiaModel;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadSettings();
  }

  Future<void> _loadSettings() async {
    _themeMode = ThemeMode.values[_prefs?.getInt(_themeKey) ?? ThemeMode.system.index];
    _fontSize = _prefs?.getDouble(_fontSizeKey) ?? 18.0;
    _summarizationProvider = _prefs?.getString('summarization_provider') ?? providerGemini;

    _autoRefresh = _prefs?.getBool(_autoRefreshKey) ?? true;
    _refreshInterval = _prefs?.getInt(_refreshIntervalKey) ?? 30;
    _notificationsEnabled = _prefs?.getBool(_notificationsKey) ?? true;
    _markAsReadOnScroll = _prefs?.getBool(_markAsReadOnScrollKey) ?? false;
    _articleCleanupDays = _prefs?.getInt(_articleCleanupKey) ?? 30;
    _imageLoadingEnabled = _prefs?.getBool(_imageLoadingKey) ?? true;

    _aiProvider = _prefs?.getString(aiProviderKey) ?? providerNone;
    _preferredProvider = _prefs?.getString(preferredProviderKey) ?? providerNone;
    _preferOnDeviceAi = _prefs?.getBool(preferOnDeviceAiKey) ?? false;
    _autoSaveSummaries = _prefs?.getBool(autoSaveSummariesKey) ?? true;
    _enabledProviders = _prefs?.getStringList(enabledProvidersKey) ?? [];

    _openaiApiKey = await _loadOrMigrateSecureKey(openaiKey);
    _claudeApiKey = await _loadOrMigrateSecureKey(claudeKey);
    _geminiApiKey = await _loadOrMigrateSecureKey(geminiKey);
    _openrouterApiKey = await _loadOrMigrateSecureKey(openrouterKey);
    _perplexityApiKey = await _loadOrMigrateSecureKey(perplexityKey);
    _nvidiaApiKey = await _loadOrMigrateSecureKey(nvidiaKey);

    _openaiModel = _prefs?.getString(openaiModelKey) ?? 'gpt-4o-mini';
    _nvidiaModel = _prefs?.getString(nvidiaModelKey) ?? 'nvidia/llama-3.1-405b-instruct';

    notifyListeners();
  }

  Future<String> _loadOrMigrateSecureKey(String key) async {
    String? secureValue = await _secureStorage.read(key: key);
    if (secureValue == null || secureValue.isEmpty) {
      final prefsValue = _prefs?.getString(key);
      if (prefsValue != null && prefsValue.isNotEmpty) {
        await _secureStorage.write(key: key, value: prefsValue);
        await _prefs?.remove(key);
        return prefsValue;
      }
    }
    return secureValue ?? '';
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs?.setInt(_themeKey, mode.index);
    notifyListeners();
  }

  void setFontSize(double size) {
    _fontSize = size;
    _prefs?.setDouble(_fontSizeKey, size);
    notifyListeners();
  }

  void setSummarizationProvider(String provider) {
    _summarizationProvider = provider;
    _prefs?.setString('summarization_provider', provider);
    notifyListeners();
  }

  Future<void> setOpenaiApiKey(String key) async { _openaiApiKey = key; await _secureStorage.write(key: openaiKey, value: key); notifyListeners(); }
  Future<void> setClaudeApiKey(String key) async { _claudeApiKey = key; await _secureStorage.write(key: claudeKey, value: key); notifyListeners(); }
  Future<void> setGeminiApiKey(String key) async { _geminiApiKey = key; await _secureStorage.write(key: geminiKey, value: key); notifyListeners(); }
  Future<void> setOpenrouterApiKey(String key) async { _openrouterApiKey = key; await _secureStorage.write(key: openrouterKey, value: key); notifyListeners(); }
  Future<void> setPerplexityApiKey(String key) async { _perplexityApiKey = key; await _secureStorage.write(key: perplexityKey, value: key); notifyListeners(); }
  Future<void> setNvidiaApiKey(String key) async { _nvidiaApiKey = key; await _secureStorage.write(key: nvidiaKey, value: key); notifyListeners(); }

  Future<void> setOpenaiModel(String model) async {
    _openaiModel = model;
    await _prefs?.setString(openaiModelKey, model);
    notifyListeners();
  }

  String getModelForProvider(String provider) {
    if (provider == providerOpenAI) return _openaiModel;
    if (provider == providerNvidia) return _nvidiaModel;
    return 'default';
  }

  List<MapEntry<String, String>> get availableAiProviders => [
    const MapEntry(providerOpenAI, 'OpenAI'),
    const MapEntry(providerGemini, 'Gemini'),
    const MapEntry(providerNvidia, 'Nvidia NIM'),
  ];
}
