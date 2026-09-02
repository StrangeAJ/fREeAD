// Small enums used by SettingsProvider. They are persisted by `name`, so do not
// rename existing values without a migration.

/// How article rows are rendered in lists.
enum ArticleListStyle { card, list, compact }

/// Typeface used for the reading body.
enum ReadingFont { serif, sans }

/// Which extraction tiers `ArticleExtractor` is allowed to use.
enum ExtractionEngine {
  /// HTTP + readability, then AMP, then headless WebView.
  auto,

  /// HTTP + readability (+ AMP) only - never spins up a WebView.
  fast,

  /// Headless WebView first, HTTP as the fallback.
  browser,
}

/// Shape of AI generated summaries.
enum SummaryStyle { brief, detailed, bullets }

extension ArticleListStyleX on ArticleListStyle {
  String get label => switch (this) {
    ArticleListStyle.card => 'Card',
    ArticleListStyle.list => 'List',
    ArticleListStyle.compact => 'Compact',
  };
}

extension ReadingFontX on ReadingFont {
  String get label => switch (this) {
    ReadingFont.serif => 'Serif',
    ReadingFont.sans => 'Sans',
  };

  /// Bundled font family used for the reading body.
  String get fontFamily => switch (this) {
    ReadingFont.serif => 'Literata',
    ReadingFont.sans => 'Inter',
  };
}

extension ExtractionEngineX on ExtractionEngine {
  String get label => switch (this) {
    ExtractionEngine.auto => 'Auto',
    ExtractionEngine.fast => 'Fast',
    ExtractionEngine.browser => 'Browser',
  };

  String get description => switch (this) {
    ExtractionEngine.auto =>
      'Try a fast fetch first, fall back to a headless browser',
    ExtractionEngine.fast => 'Fetch only - fastest, fails on JavaScript sites',
    ExtractionEngine.browser => 'Always render the page in a headless browser',
  };
}

extension SummaryStyleX on SummaryStyle {
  String get label => switch (this) {
    SummaryStyle.brief => 'Brief',
    SummaryStyle.detailed => 'Detailed',
    SummaryStyle.bullets => 'Bullets',
  };
}

/// Parses an enum value by [name], returning [fallback] when unknown.
T enumFromName<T extends Enum>(List<T> values, String? name, T fallback) {
  if (name == null) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
