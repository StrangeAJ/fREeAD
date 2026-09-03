import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:url_launcher/url_launcher.dart';

import '../../models/app_settings.dart';
import '../../models/article.dart';
import '../../models/article_highlight.dart';
import '../../theme/app_tokens.dart';
import '../../theme/app_typography.dart';
import '../../utils/app_logger.dart';
import 'highlight_injector.dart';

/// Builds the widget shown in place of an `<img>` element.
typedef ReaderImageBuilder =
    Widget Function(BuildContext context, String url, String? alt);

/// Renders an article body as real HTML.
///
/// Before v3 the reader ran every body through a regex that stripped all tags,
/// so headings, lists and - most visibly - images never appeared even though
/// the extraction pipeline preserves them. This view hands the sanitized HTML
/// straight to [HtmlWidget] instead, with reader-specific styling for headings,
/// quotes, code, links and captions, and custom widgets for images and
/// highlight `<mark>`s.
///
/// ```dart
/// ReaderContentView(
///   article: article,
///   readingFont: settings.readingFont,
///   fontSize: settings.fontSize,
///   lineHeight: settings.lineHeight,
///   highlights: annotations.highlights,
/// )
/// ```
class ReaderContentView extends StatelessWidget {
  const ReaderContentView({
    super.key,
    required this.article,
    required this.readingFont,
    required this.fontSize,
    required this.lineHeight,
    this.showImages = true,
    this.showFullContent = true,
    this.highlights = const <ArticleHighlight>[],
    this.heroImageUrl,
    this.onHighlightTap,
    this.imageBuilder,
    this.maxWidth,
  });

  final Article article;

  final ReadingFont readingFont;
  final double fontSize;
  final double lineHeight;

  /// Hide every inline image (mirrors the "Show images" setting).
  final bool showImages;

  /// Prefer [Article.fullContent] when it is available.
  final bool showFullContent;

  final List<ArticleHighlight> highlights;

  /// Image already shown as the hero; the same image inside the body is
  /// dropped so it is not rendered twice.
  final String? heroImageUrl;

  /// Called with [ArticleHighlight.id] when a `<mark>` is tapped.
  final ValueChanged<String>? onHighlightTap;

  /// Overrides how `<img>` elements render (used by tests).
  final ReaderImageBuilder? imageBuilder;

  /// Measure for the text column. Defaults to `AppTokens.readingMaxWidth`.
  final double? maxWidth;

  /// The HTML this view will render for [article], before highlight injection.
  ///
  /// `fullContent` wins when present and [showFullContent] is on, then the RSS
  /// `content` HTML, then the description wrapped in a paragraph.
  static String htmlFor(Article article, {bool showFullContent = true}) {
    if (showFullContent && article.hasFullContent) {
      return article.fullContent!;
    }
    final String? content = article.content;
    if (content != null && content.trim().isNotEmpty) return content;
    final String description = article.description.trim();
    if (description.isEmpty) return '';
    return '<p>${_escape(description)}</p>';
  }

  /// Plain text projection of [htmlFor] - the coordinate space highlight
  /// offsets live in.
  static String plainTextFor(Article article, {bool showFullContent = true}) =>
      HighlightInjector.plainText(
        htmlFor(article, showFullContent: showFullContent),
      );

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String base = htmlFor(article, showFullContent: showFullContent);
    if (base.trim().isEmpty) return const SizedBox.shrink();

    final String html = HighlightInjector.apply(base, highlights);
    final TextStyle textStyle = AppTypography.readingBody(
      readingFont,
      fontSize,
      lineHeight,
      color: t.textPrimary,
    );

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? t.readingMaxWidth),
        child: HtmlWidget(
          html,
          key: ValueKey<String>('reader-html-${article.id}-${html.length}'),
          baseUrl: Uri.tryParse(article.url),
          textStyle: textStyle,
          renderMode: RenderMode.column,
          onTapUrl: _openLink,
          customStylesBuilder: (dom.Element element) =>
              _styles(t, textStyle, element),
          customWidgetBuilder: (dom.Element element) =>
              _customWidget(context, t, textStyle, element, nested: false),
          rebuildTriggers: <dynamic>[
            fontSize,
            lineHeight,
            readingFont,
            showImages,
            highlights.length,
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Styling
  // ---------------------------------------------------------------------------

  StylesMap? _styles(AppTokens t, TextStyle body, dom.Element element) {
    switch (element.localName?.toLowerCase()) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final int level = int.tryParse(element.localName!.substring(1)) ?? 2;
        final TextStyle heading = AppTypography.readingHeading(
          level,
          scale: fontSize / 17,
        );
        return <String, String>{
          'font-family': AppTypography.display,
          'font-size': '${heading.fontSize!.toStringAsFixed(1)}px',
          'font-weight': level <= 2 ? '700' : '600',
          'line-height': '1.22',
          'color': _cssColor(t.textPrimary),
          'margin-top': '${(t.space2xl).toStringAsFixed(0)}px',
          'margin-bottom': '${t.spaceS.toStringAsFixed(0)}px',
        };
      case 'blockquote':
        return <String, String>{
          'border-left': '3px solid ${_cssColor(t.accent)}',
          'padding-left': '${t.spaceL.toStringAsFixed(0)}px',
          'margin-left': '0px',
          'margin-right': '0px',
          'color': _cssColor(t.textSecondary),
          'font-style': 'italic',
        };
      case 'a':
        return <String, String>{
          'color': _cssColor(t.accent),
          'text-decoration': 'none',
        };
      case 'figcaption':
        return <String, String>{
          'font-family': AppTypography.ui,
          'font-size': '${(fontSize - 4).clamp(11, 16).toStringAsFixed(1)}px',
          'color': _cssColor(t.textTertiary),
          'line-height': '1.45',
        };
      case 'code':
        // `pre > code` is handled by the custom `pre` widget.
        if (element.parent?.localName?.toLowerCase() == 'pre') return null;
        return <String, String>{
          'font-family': AppTypography.mono,
          'font-size': '${(fontSize - 2).toStringAsFixed(1)}px',
          'background-color': _cssColor(t.surface2),
          'color': _cssColor(t.textPrimary),
        };
      case 'th':
      case 'td':
        return <String, String>{
          'font-family': AppTypography.ui,
          'font-size': '${(fontSize - 3).clamp(11, 18).toStringAsFixed(1)}px',
          'padding': '6px',
        };
      case 'hr':
        return <String, String>{
          'margin-top': '${t.space2xl.toStringAsFixed(0)}px',
          'margin-bottom': '${t.space2xl.toStringAsFixed(0)}px',
        };
      default:
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Custom widgets
  // ---------------------------------------------------------------------------

  Widget? _customWidget(
    BuildContext context,
    AppTokens t,
    TextStyle body,
    dom.Element element, {
    required bool nested,
  }) {
    switch (element.localName?.toLowerCase()) {
      case 'img':
        return _image(context, element);
      case 'mark':
        return _mark(t, body, element);
      case 'pre':
        return _preformatted(t, element);
      case 'table':
        return nested ? null : _table(t, body, element);
      default:
        return null;
    }
  }

  Widget _image(BuildContext context, dom.Element element) {
    if (!showImages) return const SizedBox.shrink();

    final String? src = _absoluteUrl(element.attributes['src']?.trim());
    if (src == null || src.isEmpty) return const SizedBox.shrink();
    if (heroImageUrl != null && _sameImage(src, heroImageUrl!)) {
      return const SizedBox.shrink();
    }

    final String? alt = element.attributes['alt']?.trim();
    final ReaderImageBuilder builder =
        imageBuilder ??
        (BuildContext context, String url, String? alt) =>
            ReaderImage(url: url, alt: alt);
    return builder(context, src, (alt?.isEmpty ?? true) ? null : alt);
  }

  Widget _mark(AppTokens t, TextStyle body, dom.Element element) {
    final String? id = element.attributes[HighlightInjector.idAttribute];
    final Color tint = _parseHexColor(
      element.attributes[HighlightInjector.colorAttribute],
      fallback: t.warning,
    );
    final bool dark = t.brightness == Brightness.dark;

    return InlineCustomWidget(
      child: GestureDetector(
        onTap: (id == null || onHighlightTap == null)
            ? null
            : () => onHighlightTap!(id),
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint.withValues(alpha: dark ? 0.30 : 0.42),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(element.text, style: body.copyWith(color: t.textPrimary)),
        ),
      ),
    );
  }

  Widget _preformatted(AppTokens t, dom.Element element) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: t.spaceM),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: t.borderRadiusS,
        border: Border.all(color: t.hairline),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.all(t.spaceM),
        child: Text(
          element.text.trimRight(),
          style: TextStyle(
            fontFamily: AppTypography.mono,
            fontSize: (fontSize - 3).clamp(11, 18),
            height: 1.45,
            color: t.textPrimary,
          ),
        ),
      ),
    );
  }

  /// Wide tables scroll sideways instead of squashing or overflowing.
  Widget _table(AppTokens t, TextStyle body, dom.Element element) {
    final String html = element.outerHtml;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.spaceM),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double available = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : t.readingMaxWidth;
          final double width = math.max(available, 560);
          final Widget table = HtmlWidget(
            html,
            baseUrl: Uri.tryParse(article.url),
            textStyle: body,
            onTapUrl: _openLink,
            customStylesBuilder: (dom.Element e) => _styles(t, body, e),
            customWidgetBuilder: (dom.Element e) =>
                _customWidget(context, t, body, e, nested: true),
          );
          if (width <= available) return table;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: width, child: table),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<bool> _openLink(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLog.w('Could not open $url', e);
      return false;
    }
  }

  String? _absoluteUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('data:')) return null;
    final Uri? parsed = Uri.tryParse(raw);
    if (parsed == null) return null;
    if (parsed.hasScheme) return raw;
    final Uri? base = Uri.tryParse(article.url);
    if (base == null || !base.hasScheme) return null;
    return base.resolveUri(parsed).toString();
  }

  static bool _sameImage(String a, String b) {
    String strip(String url) {
      final Uri? uri = Uri.tryParse(url);
      if (uri == null) return url;
      return '${uri.host}${uri.path}';
    }

    return strip(a) == strip(b);
  }

  static String _cssColor(Color color) {
    final int argb = color.toARGB32();
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }

  static Color _parseHexColor(String? raw, {required Color fallback}) {
    final String normalized = HighlightInjector.normalizeColor(raw);
    final int? value = int.tryParse(normalized.substring(1), radix: 16);
    if (value == null) return fallback;
    return Color(0xFF000000 | (value & 0xFFFFFF));
  }

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

/// An inline article image: rounded, tappable, with a soft placeholder.
class ReaderImage extends StatelessWidget {
  const ReaderImage({super.key, required this.url, this.alt});

  final String url;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.spaceM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          GestureDetector(
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (BuildContext context) =>
                    ReaderImageViewer(url: url, alt: alt),
              ),
            ),
            child: ClipRRect(
              borderRadius: t.borderRadiusS,
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                width: double.infinity,
                fadeInDuration: AppTokens.motionFast,
                placeholder: (BuildContext context, String _) => AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ColoredBox(color: t.surface2),
                ),
                errorWidget: (BuildContext context, String _, Object __) =>
                    const SizedBox.shrink(),
              ),
            ),
          ),
          if (alt != null && alt!.isNotEmpty) ...<Widget>[
            SizedBox(height: t.spaceS),
            Text(
              alt!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: t.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Full-screen pinch-to-zoom viewer for a tapped article image.
class ReaderImageViewer extends StatelessWidget {
  const ReaderImageViewer({super.key, required this.url, this.alt});

  final String url;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFFFFFFFF),
        elevation: 0,
        title: alt == null
            ? null
            : Text(alt!, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (BuildContext context, String _) =>
                CircularProgressIndicator(color: t.accent),
            errorWidget: (BuildContext context, String _, Object __) => Icon(
              Icons.broken_image_outlined,
              color: t.textTertiary,
              size: 48,
            ),
          ),
        ),
      ),
    );
  }
}
