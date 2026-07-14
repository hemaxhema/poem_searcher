import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/poem_detail_controller.dart';
import '../db/poem_repository.dart';
import '../models/poem.dart';
import '../models/poem_line.dart';
import '../services/url_opener.dart';
import '../widgets/common_app_bar_actions.dart';
import '../widgets/poem_display_settings_dialog.dart';
import 'kashida_display.dart';
import 'settings_page.dart';

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
  /// The poem's data and display settings; this widget renders it and keeps
  /// only visual concerns (scrolling, clipboard, kashida measurement).
  late final PoemDetailController _detail = PoemDetailController(
    repo: widget.repo,
    poemId: widget.poemId,
  );

  final ScrollController _scrollController = ScrollController();

  /// Attached to the bayt tile matching [PoemDetailPage.highlightLineId] so it
  /// can be centred in the viewport once laid out (see [_maybeAutoScroll]).
  final GlobalKey _highlightKey = GlobalKey();

  /// Guards the one-shot auto-scroll to the searched line so it doesn't fire
  /// again on later rebuilds (e.g. after prefs load or the user scrolls away).
  bool _didAutoScroll = false;

  /// Memoized kashida-justified display strings (see [KashidaDisplayCache]).
  final KashidaDisplayCache _kashidaCache = KashidaDisplayCache();

  @override
  void initState() {
    super.initState();
    _detail.load();
  }

  @override
  void dispose() {
    _detail.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Scrolls the searched line to the centre of the viewport, once, after it
  /// has been laid out. Called from a post-frame callback (so the tile's
  /// context/geometry exists) and is a no-op until then, or if there is no
  /// line to highlight.
  void _maybeAutoScroll() {
    if (_didAutoScroll || widget.highlightLineId == null) return;
    final ctx = _highlightKey.currentContext;
    if (ctx == null) return;
    _didAutoScroll = true;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Opens the consolidated Settings page; on return, reloads the poem
  /// display settings (font/size/spacing) since they may have changed there.
  Future<void> _openSettings() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsPage()));
    if (!mounted) return;
    await _detail.reloadDisplayPrefs();
  }

  /// Opens the poem display settings dialog directly (font/size/spacing),
  /// without navigating to the full Settings page.
  Future<void> _openDisplaySettings() async {
    final result = await showPoemDisplaySettingsDialog(context, _detail.display);
    if (result == null) return;
    await _detail.setDisplay(result);
  }

  Future<void> _copyPoem() async {
    final text = _detail.buildCopyText();
    if (text.isEmpty) return; // Lines still loading.
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ القصيدة')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _detail,
      builder: (context, _) {
        final Poem? poem = _detail.poem;
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
              CommonAppBarActions(onOpenSettings: _openSettings),
            ],
          ),
          body: SelectionArea(child: _buildBody(context, poem)),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, Poem? poem) {
    final lines = _detail.lines;
    if (lines == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final display = _detail.display;
    final theme = Theme.of(context);
    final verseStyle = theme.textTheme.titleLarge?.copyWith(
          height: 0.8,
          fontFamily: display.fontFamily,
          fontSize: display.fontSize,
        ) ??
        TextStyle(
          fontFamily: display.fontFamily,
          fontSize: display.fontSize,
        );
    final scaler = MediaQuery.textScalerOf(context);
    // Once the poem is laid out, bring the searched line to the centre
    // of the viewport. Scheduled after the frame so the target tile's
    // context/geometry exists; _maybeAutoScroll only fires once.
    if (widget.highlightLineId != null && !_didAutoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoScroll());
    }
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
        final displayText =
            _kashidaCache.displayFor(lines, verseStyle, scaler, available);
        // SingleChildScrollView + Column (rather than a lazy ListView)
        // so every bayt is laid out up front; this lets
        // Scrollable.ensureVisible centre the searched line even when
        // it starts far off-screen. Poems are bounded (tens of bayts),
        // so eager layout is cheap.
        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (poem != null)
                _PoemHeader(poem: poem, sources: _detail.sources),
              const SizedBox(height: 8),
              for (final group in _detail.lineGroups)
                _BaytTile(
                  key: group.any((l) => l.id == widget.highlightLineId)
                      ? _highlightKey
                      : null,
                  displayText:
                      displayText[group.first.id] ?? group.first.line,
                  highlighted:
                      group.any((l) => l.id == widget.highlightLineId),
                  primary: group.first,
                  fontSize: display.fontSize,
                  fontFamily: display.fontFamily,
                  lineSpacing: display.lineSpacing,
                  variants:
                      group.length > 1 ? group.sublist(1) : const <PoemLine>[],
                ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> _openSourceUrl(BuildContext context, String url) async {
  final ok = await openExternalUrl(url);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح الرابط')),
    );
  }
}

class _PoemHeader extends StatelessWidget {
  const _PoemHeader({required this.poem, required this.sources});

  final Poem poem;

  /// Every source the poem is available from (own + merged duplicates), each an
  /// optional-URL pair; rendered as chips, tappable when a URL is present.
  final List<({String name, String? url})> sources;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = <String>[
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
                  for (final source in sources) _SourceChip(source: source),
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

/// A source chip: tapping it opens that source's URL (with an open-in-new
/// affordance) when one is available; otherwise it's a plain label chip.
class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source});

  final ({String name, String? url}) source;

  @override
  Widget build(BuildContext context) {
    final url = source.url;
    if (url == null || url.isEmpty) {
      return Chip(
        label: Text(source.name),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }
    return ActionChip(
      avatar: const Icon(Icons.open_in_new, size: 16),
      label: Text(source.name),
      tooltip: 'فتح رابط المصدر',
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onPressed: () => _openSourceUrl(context, url),
    );
  }
}

class _BaytTile extends StatelessWidget {
  const _BaytTile({
    super.key,
    required this.displayText,
    required this.highlighted,
    required this.primary,
    required this.fontSize,
    required this.fontFamily,
    required this.lineSpacing,
    this.variants = const <PoemLine>[],
  });

  /// The Kashida-justified "sadr = ajz" text to render (see
  /// [computeKashidaDisplay]). Kept separate from [PoemLine.line]
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
      // The searched line is flagged simply by colouring its text with the
      // theme accent, avoiding any background/marker box that would have to
      // cover the Arabic tashkeel rendering outside the strut-clamped line box.
      color: highlighted ? theme.colorScheme.primary : null,
    );
    // Rendered as a single paragraph (rather than two side-by-side widgets)
    // so that RTL text selection/copy works correctly and always yields
    // "sadr = ajz" verbatim, matching the original source text.
    final text = displayText;

    return Container(
      margin: EdgeInsets.symmetric(vertical: lineSpacing / 2),
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
