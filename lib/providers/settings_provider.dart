import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/saved_prompt.dart';
import '../theme/accent.dart';
import '../utils/app_logger.dart';

/// All user-facing settings. Values are persisted to [SharedPreferences]
/// (API keys go to secure storage) before listeners are notified.
class SettingsProvider with ChangeNotifier {
  // --- preference keys -------------------------------------------------------
  static const String _themeKey = 'theme_mode';
  static const String _fontSizeKey = 'font_size';

  static const String providerOpenAI = 'openai';
  static const String providerClaude = 'claude';
  static const String providerGemini = 'gemini';
  static const String providerOpenRouter = 'openrouter';
  static const String providerPerplexity = 'perplexity';
  static const String providerNvidia = 'nvidia';
  static const String providerOllama = 'ollama';
  static const String providerNone = 'none';

  static const String openaiKey = 'openai_api_key';
  static const String claudeKey = 'claude_api_key';
  static const String geminiKey = 'gemini_api_key';
  static const String openrouterKey = 'openrouter_api_key';
  static const String perplexityKey = 'perplexity_api_key';
  static const String nvidiaKey = 'nvidia_api_key';

  static const String openaiModelKey = 'openai_model';
  static const String claudeModelKey = 'claude_model';
  static const String geminiModelKey = 'gemini_model';
  static const String openrouterModelKey = 'openrouter_model';
  static const String perplexityModelKey = 'perplexity_model';
  static const String nvidiaModelKey = 'nvidia_model';
  static const String ollamaBaseUrlKey = 'ollama_base_url';
  static const String ollamaModelKey = 'ollama_model';

  static const String summarizationProviderKey = 'summarization_provider';
  static const String autoSaveSummariesKey = 'auto_save_summaries';
  static const String summaryStyleKey = 'summary_style';
  static const String customInstructionsKey = 'custom_instructions';
  static const String savedPromptsKey = 'saved_prompts';

  static const String notificationsEnabledKey = 'notifications_enabled';
  static const String notificationIntervalKey = 'notification_interval';
  static const String quietHoursEnabledKey = 'quiet_hours_enabled';
  static const String quietHoursStartKey = 'quiet_hours_start';
  static const String quietHoursEndKey = 'quiet_hours_end';
  static const String notificationSoundKey = 'notification_sound';
  static const String notificationVibrateKey = 'notification_vibrate';
  static const String mutedNotificationFeedsKey = 'muted_notification_feeds';

  static const String accentKey = 'accent';
  static const String dynamicColorKey = 'use_dynamic_color';
  static const String pureBlackKey = 'pure_black';
  static const String articleListStyleKey = 'article_list_style';
  static const String showImagesKey = 'image_loading';

  static const String readingFontKey = 'reading_font';
  static const String lineHeightKey = 'line_height';
  static const String autoLoadFullArticleKey = 'auto_load_full_article';
  static const String extractionEngineKey = 'extraction_engine';
  static const String markReadOnOpenKey = 'mark_read_on_open';
  static const String rememberScrollPositionKey = 'remember_scroll_position';

  static const String refreshOnLaunchKey = 'refresh_on_launch';
  static const String refreshIntervalKey = 'refresh_interval';
  static const String prefetchFullArticlesKey = 'prefetch_full_articles';
  static const String articleRetentionDaysKey = 'article_cleanup';
  static const String lastRefreshAtKey = 'last_refresh_at';

  // --- defaults --------------------------------------------------------------
  static const String defaultOpenaiModel = 'gpt-4o-mini';
  static const String defaultClaudeModel = 'claude-opus-5';
  static const String defaultGeminiModel = 'gemini-2.5-flash';
  static const String defaultOpenrouterModel = 'openai/gpt-4o-mini';
  static const String defaultPerplexityModel = 'sonar';
  static const String defaultNvidiaModel = 'meta/llama-3.1-8b-instruct';
  static const String defaultOllamaModel = 'llama3.2';
  static const String defaultOllamaBaseUrl = 'http://localhost:11434';

  /// Allowed values for [refreshIntervalMinutes] (0 = never).
  static const List<int> refreshIntervalOptions = <int>[15, 30, 60, 180, 0];

  /// Allowed values for [articleRetentionDays] (0 = forever).
  static const List<int> retentionOptions = <int>[7, 30, 90, 0];

  /// Allowed background-check intervals in minutes (WorkManager minimum).
  static const List<int> notificationIntervalOptions = <int>[
    15,
    30,
    60,
    180,
    360,
  ];

  /// Default quiet-hours window (22:00-07:00), minutes since midnight.
  static const int defaultQuietStartMinutes = 22 * 60;
  static const int defaultQuietEndMinutes = 7 * 60;

  SharedPreferences? _prefs;
  final _secureStorage = const FlutterSecureStorage();

  // --- appearance ------------------------------------------------------------
  ThemeMode _themeMode = ThemeMode.system;
  AppAccent _accent = AppAccent.emerald;
  bool _useDynamicColor = false;
  bool _pureBlack = false;
  ArticleListStyle _articleListStyle = ArticleListStyle.list;
  bool _showImages = true;

  // --- reading ---------------------------------------------------------------
  double _fontSize = 18.0;
  ReadingFont _readingFont = ReadingFont.serif;
  double _lineHeight = 1.6;
  bool _autoLoadFullArticle = true;
  ExtractionEngine _extractionEngine = ExtractionEngine.auto;
  bool _markReadOnOpen = true;
  bool _rememberScrollPosition = true;

  // --- feeds -----------------------------------------------------------------
  bool _refreshOnLaunch = true;
  int _refreshIntervalMinutes = 30;
  bool _prefetchFullArticles = false;
  int _articleRetentionDays = 30;
  DateTime? _lastRefreshAt;

  // --- notifications ---------------------------------------------------------
  bool _notificationsEnabled = false;
  int _notificationCheckIntervalMinutes = 60;
  bool _quietHoursEnabled = false;
  int _quietHoursStartMinutes = defaultQuietStartMinutes;
  int _quietHoursEndMinutes = defaultQuietEndMinutes;
  bool _notificationSound = true;
  bool _notificationVibrate = true;
  Set<String> _mutedNotificationFeeds = <String>{};

  // --- ai --------------------------------------------------------------------
  String _summarizationProvider = providerGemini;
  bool _autoSaveSummaries = true;
  SummaryStyle _summaryStyle = SummaryStyle.brief;
  String _customInstructions = '';
  List<SavedPrompt> _savedPrompts = <SavedPrompt>[];

  /// Hard caps so one runaway field cannot bloat preferences or model input.
  static const int maxCustomInstructionsChars = 2000;
  static const int maxSavedPrompts = 50;
  static const int maxPromptTitleChars = 80;
  static const int maxPromptChars = 2000;

  String _openaiApiKey = '';
  String _claudeApiKey = '';
  String _geminiApiKey = '';
  String _openrouterApiKey = '';
  String _perplexityApiKey = '';
  String _nvidiaApiKey = '';

  String _openaiModel = defaultOpenaiModel;
  String _claudeModel = defaultClaudeModel;
  String _geminiModel = defaultGeminiModel;
  String _openrouterModel = defaultOpenrouterModel;
  String _perplexityModel = defaultPerplexityModel;
  String _nvidiaModel = defaultNvidiaModel;
  String _ollamaBaseUrl = defaultOllamaBaseUrl;
  String _ollamaModel = defaultOllamaModel;

  // --- getters ---------------------------------------------------------------
  ThemeMode get themeMode => _themeMode;
  AppAccent get accent => _accent;
  bool get useDynamicColor => _useDynamicColor;
  bool get pureBlack => _pureBlack;
  ArticleListStyle get articleListStyle => _articleListStyle;
  bool get showImages => _showImages;

  double get fontSize => _fontSize;
  ReadingFont get readingFont => _readingFont;
  double get lineHeight => _lineHeight;
  bool get autoLoadFullArticle => _autoLoadFullArticle;
  ExtractionEngine get extractionEngine => _extractionEngine;
  bool get markReadOnOpen => _markReadOnOpen;
  bool get rememberScrollPosition => _rememberScrollPosition;

  bool get refreshOnLaunch => _refreshOnLaunch;
  int get refreshIntervalMinutes => _refreshIntervalMinutes;
  bool get prefetchFullArticles => _prefetchFullArticles;
  int get articleRetentionDays => _articleRetentionDays;
  DateTime? get lastRefreshAt => _lastRefreshAt;

  bool get notificationsEnabled => _notificationsEnabled;
  int get notificationCheckIntervalMinutes =>
      _notificationCheckIntervalMinutes;
  bool get quietHoursEnabled => _quietHoursEnabled;
  int get quietHoursStartMinutes => _quietHoursStartMinutes;
  int get quietHoursEndMinutes => _quietHoursEndMinutes;
  bool get notificationSound => _notificationSound;
  bool get notificationVibrate => _notificationVibrate;

  /// Feed ids excluded from new-article alerts (refresh still runs).
  Set<String> get mutedNotificationFeeds =>
      Set.unmodifiable(_mutedNotificationFeeds);

  bool isFeedMutedForNotifications(String feedId) =>
      _mutedNotificationFeeds.contains(feedId);

  String get summarizationProvider => _summarizationProvider;
  bool get autoSaveSummaries => _autoSaveSummaries;
  SummaryStyle get summaryStyle => _summaryStyle;

  /// Free-text instructions appended to every AI system prompt (Ask AI chats
  /// and summaries). Empty means "no extra instructions".
  String get customInstructions => _customInstructions;

  /// User-saved Ask AI prompts, oldest first.
  List<SavedPrompt> get savedPrompts => List.unmodifiable(_savedPrompts);

  String get openaiApiKey => _openaiApiKey;
  String get claudeApiKey => _claudeApiKey;
  String get geminiApiKey => _geminiApiKey;
  String get openrouterApiKey => _openrouterApiKey;
  String get perplexityApiKey => _perplexityApiKey;
  String get nvidiaApiKey => _nvidiaApiKey;

  String get openaiModel => _openaiModel;
  String get claudeModel => _claudeModel;
  String get geminiModel => _geminiModel;
  String get openrouterModel => _openrouterModel;
  String get perplexityModel => _perplexityModel;
  String get nvidiaModel => _nvidiaModel;
  String get ollamaBaseUrl => _ollamaBaseUrl;
  String get ollamaModel => _ollamaModel;

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e, st) {
      AppLog.e('Could not open shared preferences', e, st);
    }
    await _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = _prefs;

    _themeMode =
        ThemeMode.values[prefs?.getInt(_themeKey) ?? ThemeMode.system.index];
    _accent = enumFromName(
      AppAccent.values,
      prefs?.getString(accentKey),
      AppAccent.emerald,
    );
    _useDynamicColor = prefs?.getBool(dynamicColorKey) ?? false;
    _pureBlack = prefs?.getBool(pureBlackKey) ?? false;
    _articleListStyle = enumFromName(
      ArticleListStyle.values,
      prefs?.getString(articleListStyleKey),
      ArticleListStyle.list,
    );
    _showImages = prefs?.getBool(showImagesKey) ?? true;

    _fontSize = prefs?.getDouble(_fontSizeKey) ?? 18.0;
    _readingFont = enumFromName(
      ReadingFont.values,
      prefs?.getString(readingFontKey),
      ReadingFont.serif,
    );
    _lineHeight = (prefs?.getDouble(lineHeightKey) ?? 1.6).clamp(1.3, 2.0);
    _autoLoadFullArticle = prefs?.getBool(autoLoadFullArticleKey) ?? true;
    _extractionEngine = enumFromName(
      ExtractionEngine.values,
      prefs?.getString(extractionEngineKey),
      ExtractionEngine.auto,
    );
    _markReadOnOpen = prefs?.getBool(markReadOnOpenKey) ?? true;
    _rememberScrollPosition = prefs?.getBool(rememberScrollPositionKey) ?? true;

    _refreshOnLaunch = prefs?.getBool(refreshOnLaunchKey) ?? true;
    _refreshIntervalMinutes = prefs?.getInt(refreshIntervalKey) ?? 30;
    _prefetchFullArticles = prefs?.getBool(prefetchFullArticlesKey) ?? false;
    _articleRetentionDays = prefs?.getInt(articleRetentionDaysKey) ?? 30;
    final lastRefreshRaw = prefs?.getString(lastRefreshAtKey);
    _lastRefreshAt = lastRefreshRaw == null
        ? null
        : DateTime.tryParse(lastRefreshRaw);

    _notificationsEnabled =
        prefs?.getBool(notificationsEnabledKey) ?? false;
    final storedInterval = prefs?.getInt(notificationIntervalKey) ?? 60;
    _notificationCheckIntervalMinutes =
        notificationIntervalOptions.contains(storedInterval)
        ? storedInterval
        : 60;
    _quietHoursEnabled = prefs?.getBool(quietHoursEnabledKey) ?? false;
    _quietHoursStartMinutes =
        (prefs?.getInt(quietHoursStartKey) ?? defaultQuietStartMinutes).clamp(
          0,
          24 * 60 - 1,
        );
    _quietHoursEndMinutes =
        (prefs?.getInt(quietHoursEndKey) ?? defaultQuietEndMinutes).clamp(
          0,
          24 * 60 - 1,
        );
    _notificationSound = prefs?.getBool(notificationSoundKey) ?? true;
    _notificationVibrate = prefs?.getBool(notificationVibrateKey) ?? true;
    _mutedNotificationFeeds =
        prefs?.getStringList(mutedNotificationFeedsKey)?.toSet() ??
        <String>{};

    _summarizationProvider =
        prefs?.getString(summarizationProviderKey) ?? providerGemini;
    _autoSaveSummaries = prefs?.getBool(autoSaveSummariesKey) ?? true;
    _summaryStyle = enumFromName(
      SummaryStyle.values,
      prefs?.getString(summaryStyleKey),
      SummaryStyle.brief,
    );
    _customInstructions = prefs?.getString(customInstructionsKey)?.trim() ?? '';
    if (_customInstructions.length > maxCustomInstructionsChars) {
      _customInstructions = _customInstructions.substring(
        0,
        maxCustomInstructionsChars,
      );
    }
    _savedPrompts = _decodeSavedPrompts(prefs?.getString(savedPromptsKey));

    _openaiApiKey = await _loadOrMigrateSecureKey(openaiKey);
    _claudeApiKey = await _loadOrMigrateSecureKey(claudeKey);
    _geminiApiKey = await _loadOrMigrateSecureKey(geminiKey);
    _openrouterApiKey = await _loadOrMigrateSecureKey(openrouterKey);
    _perplexityApiKey = await _loadOrMigrateSecureKey(perplexityKey);
    _nvidiaApiKey = await _loadOrMigrateSecureKey(nvidiaKey);

    _openaiModel = prefs?.getString(openaiModelKey) ?? defaultOpenaiModel;
    _claudeModel = prefs?.getString(claudeModelKey) ?? defaultClaudeModel;
    _geminiModel = prefs?.getString(geminiModelKey) ?? defaultGeminiModel;
    _openrouterModel =
        prefs?.getString(openrouterModelKey) ?? defaultOpenrouterModel;
    _perplexityModel =
        prefs?.getString(perplexityModelKey) ?? defaultPerplexityModel;
    _nvidiaModel = prefs?.getString(nvidiaModelKey) ?? defaultNvidiaModel;
    _ollamaBaseUrl = prefs?.getString(ollamaBaseUrlKey) ?? defaultOllamaBaseUrl;
    _ollamaModel = prefs?.getString(ollamaModelKey) ?? defaultOllamaModel;

    notifyListeners();
  }

  Future<String> _loadOrMigrateSecureKey(String key) async {
    try {
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
    } catch (e) {
      AppLog.w('Could not read secure key $key', e);
      return '';
    }
  }

  // ---------------------------------------------------------------------------
  // Appearance setters
  // ---------------------------------------------------------------------------

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs?.setInt(_themeKey, mode.index);
    notifyListeners();
  }

  Future<void> setAccent(AppAccent accent) async {
    _accent = accent;
    await _prefs?.setString(accentKey, accent.name);
    notifyListeners();
  }

  Future<void> setUseDynamicColor(bool value) async {
    _useDynamicColor = value;
    await _prefs?.setBool(dynamicColorKey, value);
    notifyListeners();
  }

  Future<void> setPureBlack(bool value) async {
    _pureBlack = value;
    await _prefs?.setBool(pureBlackKey, value);
    notifyListeners();
  }

  Future<void> setArticleListStyle(ArticleListStyle style) async {
    _articleListStyle = style;
    await _prefs?.setString(articleListStyleKey, style.name);
    notifyListeners();
  }

  Future<void> setShowImages(bool value) async {
    _showImages = value;
    await _prefs?.setBool(showImagesKey, value);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Reading setters
  // ---------------------------------------------------------------------------

  Future<void> setFontSize(double size) async {
    _fontSize = size;
    await _prefs?.setDouble(_fontSizeKey, size);
    notifyListeners();
  }

  Future<void> setReadingFont(ReadingFont font) async {
    _readingFont = font;
    await _prefs?.setString(readingFontKey, font.name);
    notifyListeners();
  }

  Future<void> setLineHeight(double value) async {
    _lineHeight = value.clamp(1.3, 2.0);
    await _prefs?.setDouble(lineHeightKey, _lineHeight);
    notifyListeners();
  }

  Future<void> setAutoLoadFullArticle(bool value) async {
    _autoLoadFullArticle = value;
    await _prefs?.setBool(autoLoadFullArticleKey, value);
    notifyListeners();
  }

  Future<void> setExtractionEngine(ExtractionEngine engine) async {
    _extractionEngine = engine;
    await _prefs?.setString(extractionEngineKey, engine.name);
    notifyListeners();
  }

  Future<void> setMarkReadOnOpen(bool value) async {
    _markReadOnOpen = value;
    await _prefs?.setBool(markReadOnOpenKey, value);
    notifyListeners();
  }

  Future<void> setRememberScrollPosition(bool value) async {
    _rememberScrollPosition = value;
    await _prefs?.setBool(rememberScrollPositionKey, value);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Feed setters
  // ---------------------------------------------------------------------------

  Future<void> setRefreshOnLaunch(bool value) async {
    _refreshOnLaunch = value;
    await _prefs?.setBool(refreshOnLaunchKey, value);
    notifyListeners();
  }

  Future<void> setRefreshIntervalMinutes(int minutes) async {
    _refreshIntervalMinutes = minutes;
    await _prefs?.setInt(refreshIntervalKey, minutes);
    notifyListeners();
  }

  Future<void> setPrefetchFullArticles(bool value) async {
    _prefetchFullArticles = value;
    await _prefs?.setBool(prefetchFullArticlesKey, value);
    notifyListeners();
  }

  Future<void> setArticleRetentionDays(int days) async {
    _articleRetentionDays = days;
    await _prefs?.setInt(articleRetentionDaysKey, days);
    notifyListeners();
  }

  Future<void> setLastRefreshAt(DateTime? value) async {
    _lastRefreshAt = value;
    if (value == null) {
      await _prefs?.remove(lastRefreshAtKey);
    } else {
      await _prefs?.setString(lastRefreshAtKey, value.toIso8601String());
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Notification setters
  // ---------------------------------------------------------------------------

  Future<void> setNotificationsEnabled(bool value) async {
    _notificationsEnabled = value;
    await _prefs?.setBool(notificationsEnabledKey, value);
    notifyListeners();
  }

  Future<void> setNotificationCheckIntervalMinutes(int minutes) async {
    final valid = notificationIntervalOptions.contains(minutes)
        ? minutes
        : 60;
    _notificationCheckIntervalMinutes = valid;
    await _prefs?.setInt(notificationIntervalKey, valid);
    notifyListeners();
  }

  Future<void> setQuietHoursEnabled(bool value) async {
    _quietHoursEnabled = value;
    await _prefs?.setBool(quietHoursEnabledKey, value);
    notifyListeners();
  }

  Future<void> setQuietHoursStartMinutes(int minutes) async {
    _quietHoursStartMinutes = minutes.clamp(0, 24 * 60 - 1);
    await _prefs?.setInt(quietHoursStartKey, _quietHoursStartMinutes);
    notifyListeners();
  }

  Future<void> setQuietHoursEndMinutes(int minutes) async {
    _quietHoursEndMinutes = minutes.clamp(0, 24 * 60 - 1);
    await _prefs?.setInt(quietHoursEndKey, _quietHoursEndMinutes);
    notifyListeners();
  }

  Future<void> setNotificationSound(bool value) async {
    _notificationSound = value;
    await _prefs?.setBool(notificationSoundKey, value);
    notifyListeners();
  }

  Future<void> setNotificationVibrate(bool value) async {
    _notificationVibrate = value;
    await _prefs?.setBool(notificationVibrateKey, value);
    notifyListeners();
  }

  /// Mutes or unmutes new-article alerts for one feed.
  Future<void> setFeedMutedForNotifications(
    String feedId,
    bool muted,
  ) async {
    if (muted) {
      _mutedNotificationFeeds = {..._mutedNotificationFeeds, feedId};
    } else {
      _mutedNotificationFeeds = _mutedNotificationFeeds
          .where((id) => id != feedId)
          .toSet();
    }
    await _prefs?.setStringList(
      mutedNotificationFeedsKey,
      _mutedNotificationFeeds.toList(),
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // AI setters
  // ---------------------------------------------------------------------------

  Future<void> setSummarizationProvider(String provider) async {
    _summarizationProvider = provider;
    await _prefs?.setString(summarizationProviderKey, provider);
    notifyListeners();
  }

  Future<void> setAutoSaveSummaries(bool value) async {
    _autoSaveSummaries = value;
    await _prefs?.setBool(autoSaveSummariesKey, value);
    notifyListeners();
  }

  Future<void> setSummaryStyle(SummaryStyle style) async {
    _summaryStyle = style;
    await _prefs?.setString(summaryStyleKey, style.name);
    notifyListeners();
  }

  /// Saves the free-text instructions appended to AI system prompts.
  Future<void> setCustomInstructions(String value) async {
    var trimmed = value.trim();
    if (trimmed.length > maxCustomInstructionsChars) {
      trimmed = trimmed.substring(0, maxCustomInstructionsChars);
    }
    _customInstructions = trimmed;
    final prefs = _prefs;
    if (prefs != null) {
      if (trimmed.isEmpty) {
        await prefs.remove(customInstructionsKey);
      } else {
        await prefs.setString(customInstructionsKey, trimmed);
      }
    }
    notifyListeners();
  }

  /// Saves a new Ask AI prompt; returns null when the library is full.
  Future<SavedPrompt?> addSavedPrompt({
    required String title,
    required String prompt,
  }) async {
    final cleanTitle = title.trim();
    final cleanPrompt = prompt.trim();
    if (cleanTitle.isEmpty || cleanPrompt.isEmpty) return null;
    if (_savedPrompts.length >= maxSavedPrompts) return null;
    final entry = SavedPrompt(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: cleanTitle.length > maxPromptTitleChars
          ? cleanTitle.substring(0, maxPromptTitleChars)
          : cleanTitle,
      prompt: cleanPrompt.length > maxPromptChars
          ? cleanPrompt.substring(0, maxPromptChars)
          : cleanPrompt,
      createdAt: DateTime.now(),
    );
    _savedPrompts = <SavedPrompt>[..._savedPrompts, entry];
    await _persistSavedPrompts();
    notifyListeners();
    return entry;
  }

  /// Updates the title/prompt of an existing saved prompt. No-op when the id
  /// is unknown or the new values are blank.
  Future<void> updateSavedPrompt(SavedPrompt updated) async {
    final index = _savedPrompts.indexWhere((p) => p.id == updated.id);
    if (index == -1) return;
    final cleanTitle = updated.title.trim();
    final cleanPrompt = updated.prompt.trim();
    if (cleanTitle.isEmpty || cleanPrompt.isEmpty) return;
    final entry = SavedPrompt(
      id: updated.id,
      title: cleanTitle.length > maxPromptTitleChars
          ? cleanTitle.substring(0, maxPromptTitleChars)
          : cleanTitle,
      prompt: cleanPrompt.length > maxPromptChars
          ? cleanPrompt.substring(0, maxPromptChars)
          : cleanPrompt,
      createdAt: _savedPrompts[index].createdAt,
    );
    _savedPrompts = <SavedPrompt>[
      ..._savedPrompts.sublist(0, index),
      entry,
      ..._savedPrompts.sublist(index + 1),
    ];
    await _persistSavedPrompts();
    notifyListeners();
  }

  /// Deletes a saved prompt. No-op when the id is unknown.
  Future<void> deleteSavedPrompt(String id) async {
    if (!_savedPrompts.any((p) => p.id == id)) return;
    _savedPrompts = _savedPrompts.where((p) => p.id != id).toList();
    await _persistSavedPrompts();
    notifyListeners();
  }

  Future<void> _persistSavedPrompts() async {
    final prefs = _prefs;
    if (prefs == null) return;
    if (_savedPrompts.isEmpty) {
      await prefs.remove(savedPromptsKey);
      return;
    }
    try {
      await prefs.setString(
        savedPromptsKey,
        jsonEncode([for (final p in _savedPrompts) p.toJson()]),
      );
    } catch (e) {
      AppLog.w('Could not persist saved prompts', e);
    }
  }

  static List<SavedPrompt> _decodeSavedPrompts(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <SavedPrompt>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <SavedPrompt>[];
      final seen = <String>{};
      final result = <SavedPrompt>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final prompt = SavedPrompt.fromJson(Map<String, dynamic>.from(entry));
        if (prompt.id.isEmpty ||
            prompt.title.trim().isEmpty ||
            prompt.prompt.trim().isEmpty) {
          continue;
        }
        if (!seen.add(prompt.id)) continue;
        result.add(prompt);
        if (result.length >= maxSavedPrompts) break;
      }
      return result;
    } catch (e) {
      AppLog.w('Could not decode saved prompts', e);
      return <SavedPrompt>[];
    }
  }

  Future<void> setOpenaiApiKey(String key) =>
      _writeSecure(openaiKey, key, (v) => _openaiApiKey = v);
  Future<void> setClaudeApiKey(String key) =>
      _writeSecure(claudeKey, key, (v) => _claudeApiKey = v);
  Future<void> setGeminiApiKey(String key) =>
      _writeSecure(geminiKey, key, (v) => _geminiApiKey = v);
  Future<void> setOpenrouterApiKey(String key) =>
      _writeSecure(openrouterKey, key, (v) => _openrouterApiKey = v);
  Future<void> setPerplexityApiKey(String key) =>
      _writeSecure(perplexityKey, key, (v) => _perplexityApiKey = v);
  Future<void> setNvidiaApiKey(String key) =>
      _writeSecure(nvidiaKey, key, (v) => _nvidiaApiKey = v);

  Future<void> _writeSecure(
    String storageKey,
    String value,
    void Function(String) assign,
  ) async {
    assign(value);
    try {
      await _secureStorage.write(key: storageKey, value: value);
    } catch (e) {
      AppLog.w('Could not persist secure key $storageKey', e);
    }
    notifyListeners();
  }

  /// Sets an API key by provider id.
  Future<void> setApiKeyFor(String provider, String key) async {
    switch (provider) {
      case providerOpenAI:
        return setOpenaiApiKey(key);
      case providerClaude:
        return setClaudeApiKey(key);
      case providerGemini:
        return setGeminiApiKey(key);
      case providerOpenRouter:
        return setOpenrouterApiKey(key);
      case providerPerplexity:
        return setPerplexityApiKey(key);
      case providerNvidia:
        return setNvidiaApiKey(key);
      default:
        return;
    }
  }

  Future<void> setOpenaiModel(String model) =>
      _writeModel(openaiModelKey, model, (v) => _openaiModel = v);
  Future<void> setClaudeModel(String model) =>
      _writeModel(claudeModelKey, model, (v) => _claudeModel = v);
  Future<void> setGeminiModel(String model) =>
      _writeModel(geminiModelKey, model, (v) => _geminiModel = v);
  Future<void> setOpenrouterModel(String model) =>
      _writeModel(openrouterModelKey, model, (v) => _openrouterModel = v);
  Future<void> setPerplexityModel(String model) =>
      _writeModel(perplexityModelKey, model, (v) => _perplexityModel = v);
  Future<void> setNvidiaModel(String model) =>
      _writeModel(nvidiaModelKey, model, (v) => _nvidiaModel = v);
  Future<void> setOllamaModel(String model) =>
      _writeModel(ollamaModelKey, model, (v) => _ollamaModel = v);
  Future<void> setOllamaBaseUrl(String url) =>
      _writeModel(ollamaBaseUrlKey, url, (v) => _ollamaBaseUrl = v);

  Future<void> _writeModel(
    String prefKey,
    String value,
    void Function(String) assign,
  ) async {
    assign(value);
    await _prefs?.setString(prefKey, value);
    notifyListeners();
  }

  /// Sets the model for a provider id.
  Future<void> setModelForProvider(String provider, String model) async {
    switch (provider) {
      case providerOpenAI:
        return setOpenaiModel(model);
      case providerClaude:
        return setClaudeModel(model);
      case providerGemini:
        return setGeminiModel(model);
      case providerOpenRouter:
        return setOpenrouterModel(model);
      case providerPerplexity:
        return setPerplexityModel(model);
      case providerNvidia:
        return setNvidiaModel(model);
      case providerOllama:
        return setOllamaModel(model);
      default:
        return;
    }
  }

  /// Model string configured for [provider].
  String getModelForProvider(String provider) {
    switch (provider) {
      case providerOpenAI:
        return _openaiModel;
      case providerClaude:
        return _claudeModel;
      case providerGemini:
        return _geminiModel;
      case providerOpenRouter:
        return _openrouterModel;
      case providerPerplexity:
        return _perplexityModel;
      case providerNvidia:
        return _nvidiaModel;
      case providerOllama:
        return _ollamaModel;
      default:
        return 'default';
    }
  }

  /// API key configured for [provider] ('' when none / not applicable).
  String apiKeyFor(String provider) {
    switch (provider) {
      case providerOpenAI:
        return _openaiApiKey;
      case providerClaude:
        return _claudeApiKey;
      case providerGemini:
        return _geminiApiKey;
      case providerOpenRouter:
        return _openrouterApiKey;
      case providerPerplexity:
        return _perplexityApiKey;
      case providerNvidia:
        return _nvidiaApiKey;
      default:
        return '';
    }
  }

  /// True when [provider] can be used right now (Ollama needs no key).
  bool hasKeyFor(String provider) {
    if (provider == providerOllama) return true;
    return apiKeyFor(provider).isNotEmpty;
  }

  List<MapEntry<String, String>> get availableAiProviders => const [
    MapEntry(providerOpenAI, 'OpenAI'),
    MapEntry(providerClaude, 'Claude'),
    MapEntry(providerGemini, 'Gemini'),
    MapEntry(providerOpenRouter, 'OpenRouter'),
    MapEntry(providerPerplexity, 'Perplexity'),
    MapEntry(providerNvidia, 'NVIDIA NIM'),
    MapEntry(providerOllama, 'Ollama (Local)'),
  ];

  /// Display label for a provider id.
  String labelForProvider(String provider) {
    for (final entry in availableAiProviders) {
      if (entry.key == provider) return entry.value;
    }
    return provider;
  }

  /// Restores every setting to its default (keys are kept).
  Future<void> resetAllSettings() async {
    final prefs = _prefs;
    if (prefs != null) {
      for (final key in <String>[
        _themeKey,
        _fontSizeKey,
        accentKey,
        dynamicColorKey,
        pureBlackKey,
        articleListStyleKey,
        showImagesKey,
        readingFontKey,
        lineHeightKey,
        autoLoadFullArticleKey,
        extractionEngineKey,
        markReadOnOpenKey,
        rememberScrollPositionKey,
        refreshOnLaunchKey,
        refreshIntervalKey,
        prefetchFullArticlesKey,
        articleRetentionDaysKey,
        lastRefreshAtKey,
        notificationsEnabledKey,
        notificationIntervalKey,
        quietHoursEnabledKey,
        quietHoursStartKey,
        quietHoursEndKey,
        notificationSoundKey,
        notificationVibrateKey,
        mutedNotificationFeedsKey,
        summarizationProviderKey,
        autoSaveSummariesKey,
        summaryStyleKey,
        customInstructionsKey,
        savedPromptsKey,
        openaiModelKey,
        claudeModelKey,
        geminiModelKey,
        openrouterModelKey,
        perplexityModelKey,
        nvidiaModelKey,
        ollamaModelKey,
        ollamaBaseUrlKey,
      ]) {
        await prefs.remove(key);
      }
    }
    await _loadSettings();
  }
}
