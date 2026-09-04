import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../models/article.dart';
import '../../providers/article_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/ai/ai_models.dart';
import '../../services/ai/ai_service.dart';
import '../../services/database_service.dart';
import '../../theme/app_tokens.dart';
import '../../utils/app_logger.dart';
import '../../widgets/ui/ui.dart';

/// The AI summary block above the article body.
///
/// Collapsible, remembers nothing itself: an existing [Article.summary] is
/// shown immediately and a freshly generated one is written back through
/// `DatabaseService.updateArticleSummary` when "Auto-save summaries" is on.
class SummaryCard extends StatefulWidget {
  const SummaryCard({
    super.key,
    required this.article,
    required this.ai,
    this.onClose,
  });

  final Article article;
  final AiService ai;

  /// Called when the reader should hide the card again.
  final VoidCallback? onClose;

  @override
  State<SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<SummaryCard> {
  String? _summary;
  String? _error;
  bool _loading = false;
  bool _expanded = true;
  SummaryStyle? _style;

  @override
  void initState() {
    super.initState();
    final String? existing = widget.article.summary;
    _summary = (existing != null && existing.trim().isNotEmpty)
        ? existing.trim()
        : null;
    if (_summary == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
    }
  }

  SummaryStyle get _effectiveStyle =>
      _style ?? context.read<SettingsProvider>().summaryStyle;

  Future<void> _generate({SummaryStyle? style}) async {
    if (_loading) return;
    final SummaryStyle wanted = style ?? _effectiveStyle;

    final String text = widget.article.plainText;
    if (text.trim().length < 80) {
      setState(() {
        _error = 'There is not enough text in this article to summarize yet.';
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _style = wanted;
    });

    try {
      final String customInstructions = context
          .read<SettingsProvider>()
          .customInstructions;
      final String result = await widget.ai.summarize(
        text,
        style: wanted,
        customInstructions: customInstructions,
      );
      if (!mounted) return;
      setState(() {
        _summary = result.trim();
        _loading = false;
      });
      await _persist(result.trim());
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.userMessage;
        _loading = false;
      });
    } catch (e, st) {
      AppLog.e('Summary generation failed', e, st);
      if (!mounted) return;
      setState(() {
        _error = 'Could not generate a summary right now.';
        _loading = false;
      });
    }
  }

  Future<void> _persist(String summary) async {
    if (summary.isEmpty) return;
    if (!mounted) return;
    final SettingsProvider settings = context.read<SettingsProvider>();
    if (!settings.autoSaveSummaries) return;

    final ArticleProvider articles = context.read<ArticleProvider>();
    try {
      await DatabaseService().updateArticleSummary(widget.article.id, summary);
      await articles.refreshArticle(widget.article.id);
    } catch (e) {
      AppLog.w('Could not save the summary for ${widget.article.id}', e);
    }
  }

  Future<void> _copy() async {
    final String? summary = _summary;
    if (summary == null) return;
    await Clipboard.setData(ClipboardData(text: summary));
    if (!mounted) return;
    AppSnackBar.success(context, 'Summary copied');
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      level: 2,
      padding: EdgeInsets.all(t.spaceL),
      borderColor: t.accent.withValues(alpha: 0.22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.auto_awesome_rounded, size: 16, color: t.accent),
              SizedBox(width: t.spaceS),
              Expanded(
                child: Text(
                  'AI SUMMARY',
                  style: text.labelSmall?.copyWith(color: t.accent),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                ),
                iconSize: 20,
                tooltip: _expanded ? 'Collapse' : 'Expand',
                visualDensity: VisualDensity.compact,
              ),
              if (widget.onClose != null)
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded),
                  iconSize: 18,
                  tooltip: 'Hide summary',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (_expanded) ...<Widget>[
            SizedBox(height: t.spaceS),
            _body(t, text),
            SizedBox(height: t.spaceM),
            SegmentedPills<SummaryStyle>(
              values: SummaryStyle.values,
              selected: _effectiveStyle,
              dense: true,
              labelBuilder: (SummaryStyle style) => style.label,
              onChanged: (SummaryStyle style) => _generate(style: style),
            ),
            SizedBox(height: t.spaceS),
            Row(
              children: <Widget>[
                TextButton.icon(
                  onPressed: _loading ? null : () => _generate(),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Regenerate'),
                ),
                TextButton.icon(
                  onPressed: _summary == null ? null : _copy,
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _body(AppTokens t, TextTheme text) {
    if (_loading) {
      return SkeletonGroup(child: Skeleton.lines(3));
    }
    final String? error = _error;
    if (error != null) {
      return Text(error, style: text.bodyMedium?.copyWith(color: t.danger));
    }
    final String? summary = _summary;
    if (summary == null || summary.isEmpty) {
      return Text(
        'No summary yet.',
        style: text.bodyMedium?.copyWith(color: t.textTertiary),
      );
    }
    return Text(
      summary,
      style: text.bodyMedium?.copyWith(color: t.textPrimary, height: 1.55),
    );
  }
}
