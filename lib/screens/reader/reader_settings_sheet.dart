import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_tokens.dart';
import '../../theme/app_typography.dart';
import '../../widgets/ui/ui.dart';

/// Opens the reader's "Aa" sheet: typeface, size, line height, pure black,
/// auto-load and the extraction engine.
Future<void> showReaderSettingsSheet(BuildContext context) {
  return showAppBottomSheet<void>(
    context,
    title: 'Reading',
    builder: (BuildContext context) => const ReaderSettingsSheet(),
  );
}

/// Body of the reader text-settings sheet. Every control writes straight
/// through to [SettingsProvider], so the article behind the sheet updates live.
class ReaderSettingsSheet extends StatelessWidget {
  const ReaderSettingsSheet({super.key});

  static const String _previewText =
      'The quiet instrument reads best when the measure is short, the '
      'contrast is calm and nothing on the page competes with the words.';

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final SettingsProvider settings = context.watch<SettingsProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SurfaceCard(
          level: 2,
          padding: EdgeInsets.all(t.spaceL),
          child: Text(
            _previewText,
            style: AppTypography.readingBody(
              settings.readingFont,
              settings.fontSize,
              settings.lineHeight,
              color: t.textPrimary,
            ),
          ),
        ),
        SizedBox(height: t.spaceXl),

        SectionHeader(label: 'Typeface', padding: EdgeInsets.zero),
        SizedBox(height: t.spaceS),
        SegmentedPills<ReadingFont>(
          values: ReadingFont.values,
          selected: settings.readingFont,
          labelBuilder: (ReadingFont font) => font.label,
          onChanged: settings.setReadingFont,
        ),
        SizedBox(height: t.spaceL),

        _SliderRow(
          icon: Icons.format_size_rounded,
          label: 'Text size',
          value: settings.fontSize,
          min: 14,
          max: 26,
          divisions: 12,
          valueLabel: settings.fontSize.round().toString(),
          onChanged: settings.setFontSize,
        ),
        _SliderRow(
          icon: Icons.format_line_spacing_rounded,
          label: 'Line height',
          value: settings.lineHeight,
          min: 1.3,
          max: 2.0,
          divisions: 7,
          valueLabel: settings.lineHeight.toStringAsFixed(1),
          onChanged: settings.setLineHeight,
        ),
        SizedBox(height: t.spaceS),

        SectionHeader(label: 'Article', padding: EdgeInsets.zero),
        SwitchListTile(
          value: settings.pureBlack,
          onChanged: (bool value) => settings.setPureBlack(value),
          title: const Text('Pure black'),
          subtitle: const Text('AMOLED friendly background in dark mode'),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: settings.autoLoadFullArticle,
          onChanged: (bool value) => settings.setAutoLoadFullArticle(value),
          title: const Text('Auto-load full article'),
          subtitle: const Text('Fetch the full text when the feed is short'),
          contentPadding: EdgeInsets.zero,
        ),
        SizedBox(height: t.spaceS),

        SectionHeader(label: 'Extraction engine', padding: EdgeInsets.zero),
        SizedBox(height: t.spaceS),
        SegmentedPills<ExtractionEngine>(
          values: ExtractionEngine.values,
          selected: settings.extractionEngine,
          labelBuilder: (ExtractionEngine engine) => engine.label,
          onChanged: settings.setExtractionEngine,
        ),
        SizedBox(height: t.spaceS),
        Text(
          settings.extractionEngine.description,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: t.textTertiary),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: t.spaceS),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 16, color: t.textTertiary),
              SizedBox(width: t.spaceS),
              Expanded(
                child: Text(
                  label,
                  style: text.labelLarge?.copyWith(color: t.textSecondary),
                ),
              ),
              Text(
                valueLabel,
                style: text.labelLarge?.copyWith(color: t.accent),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
