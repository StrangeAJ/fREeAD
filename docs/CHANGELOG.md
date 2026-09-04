# Changelog

## 3.0.0 — v3 overhaul

A ground-up rebuild of the reading experience, article extraction, and design system. Plan and rationale in `V3_OVERHAUL_PLAN.md`.

### Fixed
- **Full-article extraction was silently broken for most sites.** `element.querySelectorAll(':scope > div')` throws `UnimplementedError` in the Dart `html` package, so the readability scoring path failed and every article without JSON-LD/microdata fell back to nothing. Replaced with a correct Readability-style extractor (JSON-LD, microdata, ~25 site-specific selectors, scoring with sibling join, lazy-image/srcset recovery), plus an AMP fallback and a headless-WebView + Mozilla Readability.js fallback for JS-rendered pages.
- **The reader stripped all HTML**, including images, from full-article content before display. Now rendered with `flutter_widget_from_html_core`, preserving headings, lists, blockquotes, tables, and images.
- **RSS dates were wrong for most feeds.** Only ISO-8601 was parsed; RFC-822 `pubDate` (used by nearly all RSS 2.0 feeds) silently fell back to "now". Added a proper RFC-822/2822 + ISO-8601 date parser.
- **Adding a feed did nothing.** It inserted a "Loading…" placeholder row and never fetched the feed's title, description, or articles. `FeedProvider.addFeed` now discovers, fetches, categorises, and populates articles in one step.
- **The Feeds tab always showed empty lists** — it passed a feed id where a category id was expected, and articles never had a `categoryId` set. Categories are now a first-class, loaded, editable model.
- **Article reading screen content rendered behind the app bar** on articles without a hero image, and starring/saving an article intermittently didn't update the list on screen (a stale cached list in `ArticleListWidget` that a reference-identity check never invalidated once any filter/sort had been touched, since the provider mutates its lists in place). Both fixed in the Phase 2 screen rewrite.
- The bottom navigation bar used Material 2's `BottomNavigationBar`, which the new theme doesn't style, leaving icons low-contrast against the dark background. Replaced with a themed Material 3 `NavigationBar`.
- A URL-formatting bug in feed discovery (`Uri.replace(query: '', fragment: '')` leaves the empty markers in) left a stray `?#` on every discovered site URL.

### Added
- Three-tier article extractor with an engine setting (Auto / Fast / Browser).
- Ask AI about an article: streaming chat grounded in the article text, suggested prompts, ask-from-selection, persisted per-article conversation. Seven providers, each with live model fetching.
- Custom AI instructions (Settings → AI): free text appended to every Ask AI and summary system prompt.
- Saved prompt library (Settings → AI → Saved prompts): keep your own Ask AI prompts and send them from the chat sheet with one tap.
- New-article notifications (Settings → Notifications): background refresh via WorkManager with a 15 min – 6 h interval, quiet hours, per-feed mute, sound/vibration toggles, inbox-style digests with deep links, and a test button.
- Automatic feed categorisation (offline heuristic + optional AI pass) with a preview before applying.
- Feed discovery from a plain site URL, parallel refresh with per-feed status, unread counts, starter packs, search screen.
- New design system: accent colours, dynamic colour, pure-black mode, bundled Space Grotesk/Inter/Literata fonts, a full `widgets/ui/` component library.
- Reading customisation: font family/size/line-height, remembered scroll position, highlight/note annotations rendered as `<mark>` in the HTML (not a separate plain-text overlay).

### Changed
- Database schema v6 → v7 (new article/feed columns, `article_chats` table, default-category backfill).
- App icon, adaptive icon, and dark splash screen.
