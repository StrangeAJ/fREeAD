import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';

import '../../models/chat_message.dart';
import '../../models/saved_prompt.dart';
import '../../providers/ai_chat_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/ui/ui.dart';
import '../settings/ai_settings_screens.dart';

/// Opens the "Ask AI about this article" sheet.
///
/// [chat] is owned by the reader screen so the conversation survives closing
/// and reopening the sheet.
Future<void> showAskAiSheet(
  BuildContext context, {
  required AiChatProvider chat,
  String? initialPrompt,
}) {
  return showAppBottomSheet<void>(
    context,
    expand: true,
    title: 'Ask AI',
    builder: (BuildContext context) =>
        ChangeNotifierProvider<AiChatProvider>.value(
          value: chat,
          child: AskAiSheet(initialPrompt: initialPrompt),
        ),
  );
}

/// Streaming chat about the current article.
class AskAiSheet extends StatefulWidget {
  const AskAiSheet({super.key, this.initialPrompt});

  /// Pre-fills the composer, e.g. `About this passage: "..."`.
  final String? initialPrompt;

  @override
  State<AskAiSheet> createState() => _AskAiSheetState();
}

class _AskAiSheetState extends State<AskAiSheet> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    final String? prefill = widget.initialPrompt;
    if (prefill != null && prefill.isNotEmpty) {
      _controller.text = prefill;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      _canSend = true;
    }
    _controller.addListener(_onTextChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final AiChatProvider chat = context.read<AiChatProvider>();
      if (!chat.isLoaded) chat.load();
    });
  }

  void _onTextChanged() {
    final bool can = _controller.text.trim().isNotEmpty;
    if (can != _canSend) setState(() => _canSend = can);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: AppTokens.motionFast,
      curve: AppTokens.motionCurve,
    );
  }

  Future<void> _send([String? text]) async {
    final String message = (text ?? _controller.text).trim();
    if (message.isEmpty) return;
    final AiChatProvider chat = context.read<AiChatProvider>();
    _controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    await chat.send(message);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final AiChatProvider chat = context.watch<AiChatProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _header(t, chat),
        SizedBox(height: t.spaceM),
        Expanded(
          child: chat.isEmpty
              ? _suggestions(t, chat)
              : ListView(
                  controller: _scrollController,
                  padding: EdgeInsets.only(bottom: t.spaceM),
                  children: <Widget>[
                    for (final ChatMessage message in chat.messages)
                      _MessageBubble(
                        message: message,
                        onCopy: () => _copy(message.content),
                        onRegenerate: message.isAssistant
                            ? chat.regenerateLast
                            : null,
                      ),
                    if (chat.partialResponse.isNotEmpty)
                      _StreamingBubble(text: chat.partialResponse),
                    if (chat.isStreaming && chat.partialResponse.isEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: t.spaceM),
                        child: SkeletonGroup(child: Skeleton.lines(2)),
                      ),
                  ],
                ),
        ),
        if (chat.error != null) _errorBanner(t, chat),
        _composer(t, chat),
      ],
    );
  }

  Widget _header(AppTokens t, AiChatProvider chat) {
    final String provider = chat.providerLabel.isEmpty
        ? 'AI'
        : chat.providerLabel;
    return Row(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                PillChip(
                  dense: true,
                  icon: Icons.bolt_rounded,
                  label: chat.model.isEmpty
                      ? provider
                      : '$provider - ${chat.model}',
                ),
                SizedBox(width: t.spaceS),
                PillChip(
                  dense: true,
                  icon: Icons.article_outlined,
                  label: chat.contextInfo,
                ),
              ],
            ),
          ),
        ),
        if (!chat.isEmpty)
          IconButton(
            tooltip: 'Clear chat',
            onPressed: chat.clear,
            icon: const Icon(Icons.delete_sweep_outlined),
            iconSize: 20,
          ),
      ],
    );
  }

  /// Saved prompts from Settings (empty when the provider is unavailable,
  /// e.g. in widget tests that only supply a chat).
  List<SavedPrompt> _savedPrompts() {
    try {
      return context.watch<SettingsProvider>().savedPrompts;
    } catch (_) {
      return const <SavedPrompt>[];
    }
  }

  Widget _suggestions(AppTokens t, AiChatProvider chat) {
    final List<SavedPrompt> saved = _savedPrompts();
    return ListView(
      controller: _scrollController,
      children: <Widget>[
        SizedBox(height: t.spaceL),
        Icon(Icons.auto_awesome_rounded, size: 28, color: t.accent),
        SizedBox(height: t.spaceM),
        Text(
          'Ask anything about this article.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: t.textPrimary),
        ),
        SizedBox(height: t.spaceXl),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: t.spaceS,
          runSpacing: t.spaceS,
          children: <Widget>[
            for (final String prompt in AiChatProvider.suggestedPrompts)
              PillChip(label: prompt, onTap: () => _send(prompt)),
          ],
        ),
        if (saved.isNotEmpty) ...<Widget>[
          SizedBox(height: t.spaceXl),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                'Your prompts',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: t.textTertiary),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AiSavedPromptsScreen(),
                  ),
                ),
                child: const Text('Manage'),
              ),
            ],
          ),
          SizedBox(height: t.spaceS),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: t.spaceS,
            runSpacing: t.spaceS,
            children: <Widget>[
              for (final SavedPrompt prompt in saved)
                PillChip(
                  label: prompt.title,
                  icon: Icons.bookmark_outline_rounded,
                  onTap: () => _send(prompt.prompt),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _errorBanner(AppTokens t, AiChatProvider chat) {
    return Padding(
      padding: EdgeInsets.only(bottom: t.spaceS),
      child: SurfaceCard(
        level: 2,
        padding: EdgeInsets.all(t.spaceM),
        borderColor: t.danger.withValues(alpha: 0.35),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline_rounded, size: 18, color: t.danger),
            SizedBox(width: t.spaceM),
            Expanded(
              child: Text(
                chat.error!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: t.textSecondary),
              ),
            ),
            TextButton(
              onPressed: chat.isStreaming ? null : chat.regenerateLast,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(AppTokens t, AiChatProvider chat) {
    return Padding(
      padding: EdgeInsets.only(top: t.spaceS, bottom: t.spaceS),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Ask about this article...',
              ),
            ),
          ),
          SizedBox(width: t.spaceS),
          if (chat.isStreaming)
            IconButton.filled(
              tooltip: 'Stop',
              onPressed: chat.stop,
              icon: const Icon(Icons.stop_rounded),
            )
          else
            IconButton.filled(
              tooltip: 'Send',
              onPressed: _canSend ? () => _send() : null,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
        ],
      ),
    );
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    AppSnackBar.success(context, 'Copied');
  }
}

/// One stored turn of the conversation.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onCopy,
    this.onRegenerate,
  });

  final ChatMessage message;
  final VoidCallback onCopy;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    if (!message.isAssistant) {
      return Padding(
        padding: EdgeInsets.only(bottom: t.spaceM),
        child: Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.8,
            ),
            child: SurfaceCard(
              level: 3,
              radius: t.radiusM,
              padding: EdgeInsets.symmetric(
                horizontal: t.spaceL,
                vertical: t.spaceM,
              ),
              onLongPress: onCopy,
              child: Text(
                message.content,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: t.textPrimary),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: t.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MarkdownAnswer(text: message.content),
          SizedBox(height: t.spaceXs),
          Row(
            children: <Widget>[
              IconButton(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded),
                iconSize: 16,
                tooltip: 'Copy',
                visualDensity: VisualDensity.compact,
                color: t.textTertiary,
              ),
              if (onRegenerate != null)
                IconButton(
                  onPressed: onRegenerate,
                  icon: const Icon(Icons.refresh_rounded),
                  iconSize: 16,
                  tooltip: 'Regenerate',
                  visualDensity: VisualDensity.compact,
                  color: t.textTertiary,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StreamingBubble extends StatelessWidget {
  const _StreamingBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(bottom: t.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MarkdownAnswer(text: text),
          const _BlinkingCaret(),
        ],
      ),
    );
  }
}

/// A small blinking block cursor shown while a reply streams in.
class _BlinkingCaret extends StatefulWidget {
  const _BlinkingCaret();

  @override
  State<_BlinkingCaret> createState() => _BlinkingCaretState();
}

class _BlinkingCaretState extends State<_BlinkingCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return FadeTransition(
      opacity: _controller,
      child: Container(width: 8, height: 16, color: t.accent),
    );
  }
}

/// Renders an assistant answer: Markdown -> HTML -> [HtmlWidget], so lists,
/// code blocks and emphasis survive.
class MarkdownAnswer extends StatelessWidget {
  const MarkdownAnswer({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextStyle? base = Theme.of(context).textTheme.bodyMedium;
    final String html = md.markdownToHtml(
      text,
      extensionSet: md.ExtensionSet.gitHubWeb,
    );

    return HtmlWidget(
      html,
      textStyle: base?.copyWith(color: t.textPrimary, height: 1.55),
      renderMode: RenderMode.column,
      customStylesBuilder: (element) {
        switch (element.localName?.toLowerCase()) {
          case 'a':
            return <String, String>{'text-decoration': 'none'};
          case 'code':
            return <String, String>{'font-family': 'monospace'};
          default:
            return null;
        }
      },
    );
  }
}
