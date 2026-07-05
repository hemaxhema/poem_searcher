import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db/poem_repository.dart';
import '../models/poem.dart';
import '../models/poem_line.dart';
import '../services/app_fonts.dart';
import '../services/poem_display_prefs.dart';
import '../util/kashida.dart';
import '../widgets/poem_display_settings_dialog.dart';

/// Shows a full poem: metadata header + every bayt, each rendered as a single
/// "sadr = ajz" line (matching the original source text) so RTL selection
/// and copy work correctly. Optionally scrolls to a specific line (e.g. the
/// one tapped in search results).
class PoemDetailPage extends StatefulWidget {
  const PoemDetailPage({
    super.key,
    required this.repo,
    required this.poemId,
    this.highlightLineId,
  });

  final PoemRepository repo;
  final int poemId;
  final int? highlightLineId;

  @override
  State<PoemDetailPage> createState() => _PoemDetailPageState();
}

class _PoemDetailPageState extends State<PoemDetailPage> {
  late Future<List<PoemLine>> _linesFuture;

  /// Poem metadata for the header/title, loaded on demand (the repository no
  /// longer preloads every poem into memory). Null until it resolves.
  Poem? _poem;

  final ScrollController _scrollController = ScrollController();

  /// User-adjustable verse font size and inter-bayt spacing, loaded from (and
  /// saved to) persisted prefs so the choice survives app restarts.
  PoemDisplaySettings _display = PoemDisplaySettings.defaults;

  // Cache of Kashida-justified display strings (keyed by line id), memoized so
  // the (moderately expensive) text measurement runs once per poem rather than
  // on every scroll rebuild. Recomputed only when the text scaler, available
  // width, or font size change.
  Map<int, String>? _displayCache;
  TextScaler? _cacheScaler;
  double? _cacheWidth;
  double? _cacheFontSize;

  @override
  void initState() {
    super.initState();
    _linesFuture = widget.repo.linesOfPoem(widget.poemId);
    widget.repo.poemById(widget.poemId).then((poem) {
      if (mounted) setState(() => _poem = poem);
    });
    PoemDisplayPrefs.load().then((settings) {
      if (mounted) setState(() => _display = settings);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Returns the Kashida-justified display string for every line, memoized on
  /// the [scaler], [available] width, and [style]'s font size so it is
  /// computed once per poem (and recomputed if the font size setting changes).
  Map<int, String> _displayFor(
    List<PoemLine> lines,
    TextStyle style,
    TextScaler scaler,
    double available,
  ) {
    if (_displayCache != null &&
        _cacheScaler == scaler &&
        _cacheWidth == available &&
        _cacheFontSize == style.fontSize) {
      return _displayCache!;
    }
    final map = _computeDisplay(lines, style, scaler, available);
    _displayCache = map;
    _cacheScaler = scaler;
    _cacheWidth = available;
    _cacheFontSize = style.fontSize;
    return map;
  }

  /// Builds the elongated "sadr = ajz" strings. Every hemistich is stretched to
  /// a single common half-width `H` (the widest natural hemistich in the poem,
  /// capped so the line still fits [available]), so all bayts end up the same
  /// width, sadr and ajz are equal, and the `=` aligns in one central column.
  ///
  /// Lines without a `=` (single hemistich) are stretched to the width of a whole
  /// normal verse: `2*H + separator` when the poem has two-hemistich lines, or —
  /// for a poem that has no `=` at all — the width of the widest single line.
  Map<int, String> _computeDisplay(
    List<PoemLine> lines,
    TextStyle style,
    TextScaler scaler,
    double available,
  ) {
    final sepWidth = measureTextWidth(' = ', style, scaler);

    var maxHalf = 0.0;
    var maxSingle = 0.0;
    var hasTwoHemistichs = false;
    for (final line in lines) {
      if (line.hasTwoHemistichs) {
        hasTwoHemistichs = true;
        maxHalf = max(maxHalf, measureTextWidth(line.sadr, style, scaler));
        maxHalf = max(maxHalf, measureTextWidth(line.ajz, style, scaler));
      } else {
        maxSingle = max(maxSingle, measureTextWidth(line.line, style, scaler));
      }
    }
    // Never let a justified line grow past the available width (else it wraps).
    final capHalf = (available - sepWidth) / 2;
    final halfTarget = min(maxHalf, capHalf);
    // Width of a whole normal verse. Single-hemistich lines are stretched to
    // this. When the poem has no `=` anywhere, the widest single line sets it.
    final fullTarget = hasTwoHemistichs
        ? min(2 * halfTarget + sepWidth, available)
        : min(maxSingle, available);

    final map = <int, String>{};
    for (final line in lines) {
      if (line.hasTwoHemistichs) {
        final sadr = kashidaJustify(line.sadr, style, halfTarget, scaler);
        final ajz = kashidaJustify(line.ajz, style, halfTarget, scaler);
        map[line.id] = '$sadr = $ajz';
      } else {
        map[line.id] = kashidaJustify(line.line, style, fullTarget, scaler);
      }
    }
    return map;
  }

  /// Groups consecutive rows sharing the same [PoemLine.lineNumber] (rows are
  /// already ordered by `line_number, id`), so alternate readings (riwayat)
  /// of the same bayt end up in one group instead of separate tiles.
  List<List<PoemLine>> _groupByLineNumber(List<PoemLine> lines) {
    final groups = <List<PoemLine>>[];
    for (final line in lines) {
      if (groups.isNotEmpty &&
          groups.last.first.lineNumber == line.lineNumber) {
        groups.last.add(line);
      } else {
        groups.add([line]);
      }
    }
    return groups;
  }

  Future<void> _copyPoem() async {
    final lines = await _linesFuture;
    final text = _groupByLineNumber(lines)
        .map((group) => group.first.line)
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ القصيدة')),
    );
  }

  Future<void> _openDisplaySettings() async {
    final result = await showPoemDisplaySettingsDialog(context, _display);
    if (result == null) return;
    setState(() {
      _displayCache = null;
      _display = result;
    });
    await PoemDisplayPrefs.save(result);
    AppFonts.currentFamily.value = result.fontFamily;
  }

  @override
  Widget build(BuildContext context) {
    final Poem? poem = _poem;
    return Scaffold(
      appBar: AppBar(
        title: Text(poem?.title ?? 'القصيدة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.format_size),
            tooltip: 'إعدادات العرض',
            onPressed: _openDisplaySettings,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'نسخ القصيدة',
            onPressed: _copyPoem,
          ),
        ],
      ),
      body: SelectionArea(
        child: FutureBuilder<List<PoemLine>>(
          future: _linesFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final lines = snapshot.data!;
            final theme = Theme.of(context);
            final verseStyle = theme.textTheme.titleLarge?.copyWith(
                  height: 0.8,
                  fontFamily: _display.fontFamily,
                  fontSize: _display.fontSize,
                ) ??
                TextStyle(
                  fontFamily: _display.fontFamily,
                  fontSize: _display.fontSize,
                );
            final scaler = MediaQuery.textScalerOf(context);
            return LayoutBuilder(
              builder: (context, constraints) {
                // Text width available inside a bayt tile: the viewport minus
                // the ListView's horizontal padding (8*2), the tile's own
                // horizontal padding (4*2), and room for the variants badge
                // + its margin so tiles with a badge never overflow.
                final available = constraints.maxWidth -
                    16 -
                    8 -
                    8 -
                    _BaytTile.reservedBadgeWidth;
                final display = _displayFor(lines, verseStyle, scaler, available);
                return ListView(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  children: [
                    if (poem != null) _PoemHeader(poem: poem),
                    const SizedBox(height: 8),
                    for (final group in _groupByLineNumber(lines))
                      _BaytTile(
                        displayText: display[group.first.id] ?? group.first.line,
                        highlighted:
                            group.any((l) => l.id == widget.highlightLineId),
                        primary: group.first,
                        fontSize: _display.fontSize,
                        fontFamily: _display.fontFamily,
                        lineSpacing: _display.lineSpacing,
                        variants: group.length > 1
                            ? group.sublist(1)
                            : const <PoemLine>[],
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

Future<void> _openSourceUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  final ok =
      uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح الرابط')),
    );
  }
}

class _PoemHeader extends StatelessWidget {
  const _PoemHeader({required this.poem});

  final Poem poem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = <String>[
      if (poem.source != null) poem.source!.displayName,
      if ((poem.book ?? '').isNotEmpty) poem.book!,
      if ((poem.page ?? '').isNotEmpty) poem.page!,
      if ((poem.type ?? '').isNotEmpty) poem.type!,
    ];
    // Align+min-sizing lets the card shrink to fit its content instead of
    // always spanning the full row width, which otherwise left a large,
    // pointless blank strip whenever the title/poet/chips were short.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  poem.title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if ((poem.sourceUrl ?? '').isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.open_in_new),
                  iconSize: 18,
                  tooltip: 'فتح رابط المصدر',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _openSourceUrl(context, poem.sourceUrl!),
                ),
              const SizedBox(width: 12),
              Wrap(
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    poem.poet,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                  for (final c in chips)
                    Chip(
                      label: Text(c),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BaytTile extends StatelessWidget {
  const _BaytTile({
    required this.displayText,
    required this.highlighted,
    required this.primary,
    required this.fontSize,
    required this.fontFamily,
    required this.lineSpacing,
    this.variants = const <PoemLine>[],
  });

  /// The Kashida-justified "sadr = ajz" text to render (see
  /// [_PoemDetailPageState._computeDisplay]). Kept separate from [PoemLine.line]
  /// so the clean source text is still used for the copy-all action.
  final String displayText;
  final bool highlighted;

  /// The row shown as this tile's text (the first reading in its group).
  final PoemLine primary;

  /// User-adjustable verse font size (see [PoemDisplaySettings]).
  final double fontSize;

  /// User-selected verse font family (see [PoemDisplaySettings]).
  final String fontFamily;

  /// User-adjustable vertical gap between this tile and its neighbors (see
  /// [PoemDisplaySettings]); split evenly above and below via the container's
  /// margin so the total gap between two adjacent tiles equals this value.
  final double lineSpacing;

  /// Other readings (riwayat) of this same bayt (same `line_number`), if
  /// any, shown behind a small badge beside the tile.
  final List<PoemLine> variants;

  /// Reserved so the shared kashida-justified width (computed once for the
  /// whole poem) leaves room for the badge + its margin on every tile.
  static const double reservedBadgeWidth = 28;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verseStyle = theme.textTheme.titleLarge?.copyWith(
      height: 1.0,
      fontFamily: fontFamily,
      fontSize: fontSize,
    );
    final color = highlighted
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
        : null;

    // Rendered as a single paragraph (rather than two side-by-side widgets)
    // so that RTL text selection/copy works correctly and always yields
    // "sadr = ajz" verbatim, matching the original source text.
    final text = displayText;

    return Container(
      margin: EdgeInsets.symmetric(vertical: lineSpacing / 2),
      padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // SelectionArea does not insert a line break between separate
          // Text widgets when copying, so a trailing "\n" is appended to
          // each bayt's own text (visually collapsed via near-zero font
          // size/height) to make sure multi-bayt selections copy as one
          // verse per line.
          Text.rich(
            TextSpan(
              style: verseStyle,
              children: [
                TextSpan(text: text),
                const TextSpan(
                  text: '\n',
                  style: TextStyle(fontSize: 0.01, height: 0.01),
                ),
              ],
            ),
            textAlign: TextAlign.center,
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
            // The font's own descent metric is much taller than its visible
            // glyphs, which otherwise leaves a large gap below every verse
            // (line height is normally the max of the natural font metrics
            // and the strut). Forcing the strut height clamps the line box
            // to the font size itself instead of that oversized descent.
            strutStyle: StrutStyle(
              fontFamily: verseStyle?.fontFamily,
              fontSize: verseStyle?.fontSize,
              height: 1.0,
              forceStrutHeight: true,
            ),
          ),
          // Placed as the last Row child so it lands at the end of the verse
          // (the left side, in this RTL layout) with a small gap.
          if (variants.isNotEmpty) ...[
            const SizedBox(width: 6),
            _VariantsBadge(
              count: variants.length,
              onTap: () => _showVariantsDialog(
                context,
                [primary, ...variants],
                fontFamily,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small tappable badge showing the number of other readings (riwayat) of a
/// bayt; opens a dialog listing them.
class _VariantsBadge extends StatelessWidget {
  const _VariantsBadge({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'روايات أخرى لهذا البيت',
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 24,
            height: 24,
            child: Center(
              child: Text(
                '+$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows every reading (riwaya) of a bayt — including the one already shown
/// in its tile — in a simple, large-print dialog.
void _showVariantsDialog(
  BuildContext context,
  List<PoemLine> lines,
  String fontFamily,
) {
  final theme = Theme.of(context);
  final labelStyle = theme.textTheme.titleSmall?.copyWith(
    color: theme.colorScheme.primary,
    fontWeight: FontWeight.bold,
  );
  final verseStyle = theme.textTheme.headlineSmall?.copyWith(
    height: 1.6,
    fontFamily: fontFamily,
  );

  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('الروايات'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final line in lines) ...[
                if (line != lines.first) const Divider(height: 24),
                if ((line.lineType ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      line.lineType!,
                      style: labelStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                Text(
                  line.hasTwoHemistichs
                      ? '${line.sadr} = ${line.ajz}'
                      : line.line,
                  style: verseStyle,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  );
}
