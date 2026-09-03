import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../services/ai/ai_models.dart';
import '../../services/ai/ai_service.dart';
import '../../theme/app_tokens.dart';
import '../../utils/app_logger.dart';
import '../../widgets/ui/ui.dart';

/// Builds an [AiService] from the current settings.
///
/// `main.dart` does not provide `Provider<AiService>` yet (Phase 3 may hoist
/// it), so every screen that needs one constructs it locally. It is cheap - a
/// Dio instance and three adapters.
AiService buildAiService(BuildContext context) => AiService(
  configSource: SettingsAiConfigSource(context.read<SettingsProvider>()),
);

// =============================================================================
// API keys
// =============================================================================

/// One secure field per provider, with show/hide, paste and a live "Test"
/// button that actually calls the provider.
class AiApiKeysScreen extends StatelessWidget {
  const AiApiKeysScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final SettingsProvider settings = context.watch<SettingsProvider>();

    return AppScaffold(
      appBar: const GlassAppBar(title: 'API keys'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          t.spaceL,
          t.spaceS,
          t.spaceL,
          t.space3xl * 2,
        ),
        children: <Widget>[
          Text(
            'Keys are stored in the device keystore, never in plain '
            'preferences, and are only sent to the provider they belong to.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: t.textTertiary),
          ),
          SizedBox(height: t.spaceL),
          for (final AiProvider provider in AiProvider.values)
            if (provider != AiProvider.ollama)
              _ApiKeyCard(
                key: ValueKey<String>('key-${provider.id}'),
                provider: provider,
                settings: settings,
              ),
          SizedBox(height: t.spaceM),
          SectionHeader(
            label: 'Ollama',
            padding: EdgeInsets.only(bottom: t.spaceS),
          ),
          _OllamaUrlCard(settings: settings),
        ],
      ),
    );
  }
}

class _ApiKeyCard extends StatefulWidget {
  const _ApiKeyCard({
    super.key,
    required this.provider,
    required this.settings,
  });

  final AiProvider provider;
  final SettingsProvider settings;

  @override
  State<_ApiKeyCard> createState() => _ApiKeyCardState();
}

class _ApiKeyCardState extends State<_ApiKeyCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.settings.apiKeyFor(widget.provider.id),
  );
  bool _obscure = true;
  bool _testing = false;
  AiTestResult? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.settings.setApiKeyFor(
      widget.provider.id,
      _controller.text.trim(),
    );
    if (!mounted) return;
    setState(() => _result = null);
    AppSnackBar.success(context, '${widget.provider.label} key saved');
  }

  Future<void> _paste() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (mounted) AppSnackBar.show(context, 'Clipboard is empty.');
      return;
    }
    setState(() => _controller.text = text);
  }

  Future<void> _test() async {
    // Persist first: testConnection reads the key back through settings.
    await widget.settings.setApiKeyFor(
      widget.provider.id,
      _controller.text.trim(),
    );
    if (!mounted) return;

    setState(() {
      _testing = true;
      _result = null;
    });
    final AiService service = buildAiService(context);
    AiTestResult result;
    try {
      result = await service.testConnection(widget.provider);
    } catch (e) {
      AppLog.w('Connection test failed for ${widget.provider.id}', e);
      result = AiTestResult(ok: false, message: 'Test failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final AiTestResult? result = _result;

    return SurfaceCard(
      margin: EdgeInsets.only(bottom: t.spaceM),
      padding: EdgeInsets.all(t.spaceM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.provider.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (widget.settings.hasKeyFor(widget.provider.id))
                PillChip(
                  label: 'Configured',
                  icon: Icons.check_rounded,
                  dense: true,
                  selected: true,
                ),
            ],
          ),
          SizedBox(height: t.spaceS),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              hintText: 'Paste your ${widget.provider.label} key',
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    tooltip: _obscure ? 'Show' : 'Hide',
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_paste_rounded, size: 20),
                    tooltip: 'Paste',
                    onPressed: _paste,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: t.spaceS),
          Row(
            children: <Widget>[
              TextButton(onPressed: _save, child: const Text('Save')),
              const Spacer(),
              if (_testing)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.accent,
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: _test,
                  icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                  label: const Text('Test'),
                ),
            ],
          ),
          if (result != null) ...<Widget>[
            SizedBox(height: t.spaceS),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  result.ok
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  size: 16,
                  color: result.ok ? t.success : t.danger,
                ),
                SizedBox(width: t.spaceS),
                Expanded(
                  child: Text(
                    result.message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: result.ok ? t.textSecondary : t.danger,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OllamaUrlCard extends StatefulWidget {
  const _OllamaUrlCard({required this.settings});

  final SettingsProvider settings;

  @override
  State<_OllamaUrlCard> createState() => _OllamaUrlCardState();
}

class _OllamaUrlCardState extends State<_OllamaUrlCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.settings.ollamaBaseUrl,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;

    return SurfaceCard(
      padding: EdgeInsets.all(t.spaceM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'http://localhost:11434',
            ),
            onSubmitted: (String value) =>
                widget.settings.setOllamaBaseUrl(value.trim()),
          ),
          SizedBox(height: t.spaceS),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () async {
                await widget.settings.setOllamaBaseUrl(_controller.text.trim());
                if (context.mounted) {
                  AppSnackBar.success(context, 'Ollama URL saved');
                }
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Models
// =============================================================================

/// Per-provider model selection.
///
/// Every provider gets a **Fetch models** button that calls
/// [AiService.fetchAvailableModels] and opens a searchable picker with what the
/// provider actually reports (falling back to a curated static list when the
/// endpoint is unreachable). The free-text field stays alongside it so a
/// self-hosted Ollama tag the listing misses can still be typed in by hand.
class AiModelsScreen extends StatelessWidget {
  const AiModelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final SettingsProvider settings = context.watch<SettingsProvider>();

    return AppScaffold(
      appBar: const GlassAppBar(title: 'Models'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          t.spaceL,
          t.spaceS,
          t.spaceL,
          t.space3xl * 2,
        ),
        children: <Widget>[
          Text(
            'Fetch the live model list from each provider, or type a model id '
            'by hand.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: t.textTertiary),
          ),
          SizedBox(height: t.spaceL),
          for (final AiProvider provider in AiProvider.values)
            _ModelCard(
              key: ValueKey<String>('model-${provider.id}'),
              provider: provider,
              settings: settings,
            ),
        ],
      ),
    );
  }
}

class _ModelCard extends StatefulWidget {
  const _ModelCard({super.key, required this.provider, required this.settings});

  final AiProvider provider;
  final SettingsProvider settings;

  @override
  State<_ModelCard> createState() => _ModelCardState();
}

class _ModelCardState extends State<_ModelCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.settings.getModelForProvider(widget.provider.id),
  );
  bool _fetching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save(String model) async {
    final String trimmed = model.trim();
    if (trimmed.isEmpty) return;
    await widget.settings.setModelForProvider(widget.provider.id, trimmed);
    if (!mounted) return;
    _controller.text = trimmed;
    AppSnackBar.success(context, '${widget.provider.label}: $trimmed');
  }

  /// Bug fix (v2): the model was a bare text field with no way to see what the
  /// provider offers. This asks the provider and shows the answer.
  Future<void> _fetchModels() async {
    setState(() => _fetching = true);

    final AiService service = buildAiService(context);
    List<String> models;
    try {
      models = await service.fetchAvailableModels(
        widget.provider,
        apiKey: widget.settings.apiKeyFor(widget.provider.id).isEmpty
            ? null
            : widget.settings.apiKeyFor(widget.provider.id),
      );
    } catch (e) {
      AppLog.w('Model listing failed for ${widget.provider.id}', e);
      models = AiService.fallbackModelsFor(widget.provider);
    }
    if (!mounted) return;
    setState(() => _fetching = false);

    if (models.isEmpty) {
      AppSnackBar.error(
        context,
        'No models returned for ${widget.provider.label}.',
      );
      return;
    }

    final String? picked = await showModelPicker(
      context,
      provider: widget.provider,
      models: models,
      current: _controller.text.trim(),
    );
    if (picked != null) await _save(picked);
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool needsKey =
        widget.provider.requiresApiKey &&
        !widget.settings.hasKeyFor(widget.provider.id);

    return SurfaceCard(
      margin: EdgeInsets.only(bottom: t.spaceM),
      padding: EdgeInsets.all(t.spaceM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.provider.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (needsKey)
                Text(
                  'No key - showing defaults',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: t.textTertiary),
                ),
            ],
          ),
          SizedBox(height: t.spaceS),
          TextField(
            controller: _controller,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Model id',
              helperText: 'Type one, or fetch the list',
            ),
            onSubmitted: _save,
          ),
          SizedBox(height: t.spaceS),
          Row(
            children: <Widget>[
              TextButton(
                onPressed: () => _save(_controller.text),
                child: const Text('Save'),
              ),
              const Spacer(),
              if (_fetching)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.accent,
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: _fetchModels,
                  icon: const Icon(Icons.cloud_download_outlined, size: 18),
                  label: const Text('Fetch models'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A searchable list of [models]; returns the chosen id, or null.
Future<String?> showModelPicker(
  BuildContext context, {
  required AiProvider provider,
  required List<String> models,
  String? current,
}) {
  return showAppBottomSheet<String>(
    context,
    title: '${provider.label} models',
    expand: models.length > 8,
    builder: (BuildContext context) =>
        _ModelPicker(models: models, current: current),
  );
}

class _ModelPicker extends StatefulWidget {
  const _ModelPicker({required this.models, this.current});

  final List<String> models;
  final String? current;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final String query = _query.trim().toLowerCase();
    final List<String> visible = query.isEmpty
        ? widget.models
        : widget.models
              .where((String m) => m.toLowerCase().contains(query))
              .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.models.length > 8)
          Padding(
            padding: EdgeInsets.only(bottom: t.spaceM),
            child: TextField(
              autofocus: false,
              onChanged: (String value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Filter models',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
        Flexible(
          child: visible.isEmpty
              ? Padding(
                  padding: EdgeInsets.all(t.spaceXl),
                  child: Text(
                    'No model matches "$_query".',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: t.textTertiary),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: visible.length,
                  itemBuilder: (BuildContext context, int index) {
                    final String model = visible[index];
                    final bool selected = model == widget.current;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 20,
                        color: selected ? t.accent : t.textTertiary,
                      ),
                      title: Text(
                        model,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: selected ? t.accent : t.textPrimary,
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(model),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
