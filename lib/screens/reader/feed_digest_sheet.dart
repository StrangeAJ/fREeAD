import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/article.dart';
import '../../models/feed_summary.dart';
import '../../providers/article_provider.dart';
import '../../services/ai/feed_summary_service.dart';
import '../../theme/app_tokens.dart';
import '../../utils/app_logger.dart';
import '../../utils/text_utils.dart';
import '../../widgets/ui/ui.dart';
import 'ask_ai_sheet.dart' show MarkdownAnswer;

/// Feed id the "everything I have right now" digest is stored under.
const String kAllFeedsDigestId = 'all_feeds';

/// Opens the AI digest of the articles currently loaded.
Future<void> showFeedDigestSheet(BuildContext context, {String? feedId}) {
  return showAppBottomSheet<void>(
    context,
    title: 'Feed digest',
    builder: (BuildContext context) =>
        FeedDigestSheet(feedId: feedId ?? kAllFeedsDigestId),
  );
}

/// Summarises the current articles into one short digest, cached in the
/// `feed_summaries` table so reopening it is instant.
class FeedDigestSheet extends StatefulWidget {
  const FeedDigestSheet({super.key, this.feedId = kAllFeedsDigestId});

  final String feedId;

  @override
  State<FeedDigestSheet> createState() => _FeedDigestSheetState();
}

class _FeedDigestSheetState extends State<FeedDigestSheet> {
  final FeedSummaryService _service = FeedSummaryService();

  FeedSummary? _summary;
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final FeedSummary? existing = await _service.getFeedSummary(
        widget.feedId,
      );
      if (!mounted) return;
      setState(() {
        _summary = existing;
        _loading = false;
      });
    } catch (e, st) {
      AppLog.w('Could not read the stored digest', e, st);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not read the stored digest.';
      });
    }
  }

  Future<void> _generate({bool refresh = false}) async {
    if (_working) return;

    final List<Article> articles = context.read<ArticleProvider>().articles;
    if (articles.isEmpty) {
      setState(() => _error = 'There are no articles to summarize yet.');
      return;
    }

    setState(() {
      _working = true;
      _error = null;
    });

    try {
      final FeedSummary result = refresh
          ? await _service.refreshFeedSummary(widget.feedId, articles)
          : await _service.generateFeedSummary(widget.feedId, articles);
      if (!mounted) return;
      setState(() {
        _summary = result;
        _working = false;
      });
    } catch (e, st) {
      AppLog.w('Feed digest failed', e, st);
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = 'The digest could not be generated. Check Settings > AI.';
      });
    }
  }

  Future<void> _copy() async {
    final FeedSummary? summary = _summary;
    if (summary == null) return;
    await Clipboard.setData(ClipboardData(text: summary.summary));
    if (!mounted) return;
    AppSnackBar.success(context, 'Digest copied');
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final int articleCount = context.watch<ArticleProvider>().articles.length;

    if (_loading) {
      return SkeletonGroup(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: t.spaceM),
          child: Skeleton.lines(4),
        ),
      );
    }

    final FeedSummary? summary = _summary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.auto_awesome_rounded, size: 16, color: t.accent),
            SizedBox(width: t.spaceS),
            Expanded(
              child: Text(
                summary == null
                    ? '$articleCount articles loaded'
                    : 'Updated ${relativeTime(summary.updatedAt)}',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: t.textTertiary),
              ),
            ),
          ],
        ),
        SizedBox(height: t.spaceM),

        if (_working)
          SkeletonGroup(child: Skeleton.lines(4))
        else if (summary != null)
          SurfaceCard(
            level: 2,
            padding: EdgeInsets.all(t.spaceL),
            child: MarkdownAnswer(text: summary.summary),
          )
        else
          EmptyState(
            compact: true,
            icon: Icons.summarize_outlined,
            title: 'No digest yet',
            message:
                'Generate a short overview of the $articleCount articles you '
                'have right now.',
          ),

        if (_error != null) ...<Widget>[
          SizedBox(height: t.spaceM),
          Text(
            _error!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: t.danger),
          ),
        ],

        SizedBox(height: t.spaceL),
        Row(
          children: <Widget>[
            Expanded(
              child: GlowButton(
                expand: true,
                loading: _working,
                icon: summary == null
                    ? Icons.auto_awesome_rounded
                    : Icons.refresh_rounded,
                label: summary == null ? 'Generate' : 'Refresh',
                onPressed: _working
                    ? null
                    : () => _generate(refresh: summary != null),
              ),
            ),
            if (summary != null) ...<Widget>[
              SizedBox(width: t.spaceM),
              IconButton(
                onPressed: _copy,
                icon: const Icon(Icons.copy_rounded),
                tooltip: 'Copy',
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Compatibility shell so existing `showDialog(builder: ... FeedSummaryDialog())`
/// call sites keep working while Phase 2B rewrites the home shell.
///
/// New code should call [showFeedDigestSheet] instead.
class FeedSummaryDialog extends StatelessWidget {
  const FeedSummaryDialog({super.key, this.feedId = kAllFeedsDigestId});

  final String feedId;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    return Dialog(
      insetPadding: EdgeInsets.all(t.spaceL),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: EdgeInsets.all(t.spaceL),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Feed digest',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
              SizedBox(height: t.spaceM),
              Flexible(
                child: SingleChildScrollView(
                  child: FeedDigestSheet(feedId: feedId),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
