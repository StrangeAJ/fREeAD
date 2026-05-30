import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  SharedPreferences? _prefs;
  ThemeMode _themeMode = ThemeMode.system;
  double _fontSize = 18.0;
  String _summarizationProvider = providerGemini;

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
    _themeMode = ThemeMode.values[_prefs?.getInt(_themeKey) ?? ThemeMode.system.index];
    _fontSize = _prefs?.getDouble(_fontSizeKey) ?? 18.0;
    _summarizationProvider = _prefs?.getString('summarization_provider') ?? providerGemini;

    _openaiApiKey = _prefs?.getString(openaiKey) ?? '';
    _claudeApiKey = _prefs?.getString(claudeKey) ?? '';
    _geminiApiKey = _prefs?.getString(geminiKey) ?? '';
    _openrouterApiKey = _prefs?.getString(openrouterKey) ?? '';
    _perplexityApiKey = _prefs?.getString(perplexityKey) ?? '';
    _nvidiaApiKey = _prefs?.getString(nvidiaKey) ?? '';

    _openaiModel = _prefs?.getString(openaiModelKey) ?? 'gpt-4o-mini';
    _nvidiaModel = _prefs?.getString(nvidiaModelKey) ?? 'nvidia/llama-3.1-405b-instruct';

    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _prefs?.setInt(_themeKey, mode.index);
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

  void setOpenaiApiKey(String key) { _openaiApiKey = key; _prefs?.setString(openaiKey, key); notifyListeners(); }
  void setClaudeApiKey(String key) { _claudeApiKey = key; _prefs?.setString(claudeKey, key); notifyListeners(); }
  void setGeminiApiKey(String key) { _geminiApiKey = key; _prefs?.setString(geminiKey, key); notifyListeners(); }
  void setOpenrouterApiKey(String key) { _openrouterApiKey = key; _prefs?.setString(openrouterKey, key); notifyListeners(); }
  void setPerplexityApiKey(String key) { _perplexityApiKey = key; _prefs?.setString(perplexityKey, key); notifyListeners(); }
  void setNvidiaApiKey(String key) { _nvidiaApiKey = key; _prefs?.setString(nvidiaKey, key); notifyListeners(); }

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
