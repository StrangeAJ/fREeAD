# FreeAd — RSS News & Blog Reader

A Flutter RSS/Atom reader for Android with a robust in-app article extractor, an AI reading assistant, and automatic feed categorisation.

## Features

### Reading
- **Three-tier full-article extraction**: sanitized RSS content when the feed already ships it, a Dart Readability-style HTTP extractor (JSON-LD, microdata, ~25 site-specific selectors, boilerplate scoring, lazy-image/srcset recovery) for the general web, and a headless-WebView + Mozilla Readability.js fallback for JS-rendered pages — selectable as Auto / Fast / Browser.
- Full HTML rendering (headings, lists, blockquotes, tables, images) via `flutter_widget_from_html_core` — not a plain-text strip.
- Font family (serif/sans), size and line-height controls; reading time estimate; scroll position remembered per article; text-selection toolbar (Highlight, Note, Ask AI, Copy, Share).
- AI summaries (brief / detailed / bullet styles), saved per article.

### Ask AI about an article
A streaming chat sheet grounded in the article's own text (RSS excerpt or extracted full content), with suggested prompts, "ask about this passage" from text selection, and a persisted per-article conversation. Works with OpenAI, Anthropic (Claude), Gemini, OpenRouter, Perplexity, NVIDIA NIM, or a local Ollama server — each with per-provider models fetched live from that provider's API (with a static fallback list if the fetch fails).

### Feeds & categories
- Feed discovery from a plain site URL (`<link rel=alternate>` + common feed paths), not just a direct feed URL.
- Automatic categorisation on add/import: an offline keyword/known-domain heuristic by default, or a one-shot AI pass that can also propose new categories — both previewed before applying.
- Parallel feed refresh with per-feed status/errors, unread counts per feed and category, OPML import/export, starter packs for quick setup.

### Design
A "quiet instrument" look: near-black/off-white surfaces, hairline borders instead of shadows, one user-selectable accent colour (plus optional Material You dynamic colour on Android 12+), pure-black (AMOLED) mode, and the Space Grotesk / Inter / Literata type system — bundled, not fetched. Card / List / Compact article layouts with swipe actions and date grouping.

## Building

Requires Flutter 3.32.8 (stable). If Flutter/the Android SDK aren't on `PATH`:

```powershell
$env:PATH = "D:\flutter\bin;D:\android-sdk\platform-tools;" + $env:PATH
```

On Windows, if the Gradle build fails with `Unable to establish loopback connection` (happens when the user's TEMP directory resolves to an 8.3 short path), set:

```powershell
$env:JAVA_TOOL_OPTIONS = "-Djdk.net.unixdomain.tmpdir=C:/gradle-home/tmp"
```

Then:

```powershell
flutter pub get
flutter build apk --release
```

`android/gradle.properties` also pins `kotlin.incremental=false` and a custom `org.gradle.user.home` — needed when the pub cache and the project checkout live on different drives. See `docs/V3_OVERHAUL_PLAN.md` for the full toolchain notes and architecture.

## Project layout

- `lib/services/rss/` — feed parsing, date parsing, feed discovery
- `lib/services/extraction/` — the three-tier article extractor
- `lib/services/ai/` — provider adapters, summarization, categorisation, chat
- `lib/theme/`, `lib/widgets/ui/` — the shared design system
- `lib/screens/reader/`, `lib/screens/home/`, `lib/screens/feeds/` — the screens
- `docs/V3_OVERHAUL_PLAN.md` — the design/architecture record for the v3 rewrite
- `docs/CHANGELOG.md` — release notes

## Not in scope (yet)

Background sync (WorkManager), push notifications, text-to-speech, iOS polish, desktop builds.
