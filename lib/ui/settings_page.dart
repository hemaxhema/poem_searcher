import 'package:flutter/material.dart';

import '../db/memory_preset.dart';
import '../models/source.dart';
import '../search/search_sort.dart';
import '../services/app_fonts.dart';
import '../services/memory_preset_prefs.dart';
import '../services/poem_display_prefs.dart';
import '../services/results_display_prefs.dart';
import '../services/search_sort_prefs.dart';
import '../services/search_titles_prefs.dart';
import '../services/source_filter_prefs.dart';
import '../widgets/about_dialog.dart';
import '../widgets/common_app_bar_actions.dart';
import '../widgets/poem_display_settings_dialog.dart';
import '../widgets/results_display_settings_dialog.dart';
import '../widgets/section_header.dart';
import '../widgets/source_filter_dialog.dart';

/// One place gathering every user-adjustable setting: search sources, result
/// sort order, poem display (font/size/spacing), and the database memory
/// preset. Each section persists through the same prefs class the setting
/// always used; this page is just their shared home.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<Source> _sourceOrder = Source.values;
  SearchSort _sortMode = SearchSort.lineCountDesc;
  PoemDisplaySettings _display = PoemDisplaySettings.defaults;
  MemoryPreset _memoryPreset = MemoryPreset.balanced;
  ResultsDisplaySettings _resultsDisplay = ResultsDisplaySettings.defaults;
  bool _searchInTitles = SearchTitlesPrefs.defaultEnabled;

  @override
  void initState() {
    super.initState();
    SourceFilterPrefs.load().then((order) {
      if (mounted) setState(() => _sourceOrder = order);
    });
    SearchSortPrefs.load().then((sort) {
      if (mounted) setState(() => _sortMode = sort);
    });
    PoemDisplayPrefs.load().then((settings) {
      if (mounted) setState(() => _display = settings);
    });
    MemoryPresetPrefs.load().then((preset) {
      if (mounted) setState(() => _memoryPreset = preset);
    });
    ResultsDisplayPrefs.load().then((settings) {
      if (mounted) setState(() => _resultsDisplay = settings);
    });
    SearchTitlesPrefs.load().then((enabled) {
      if (mounted) setState(() => _searchInTitles = enabled);
    });
  }

  Future<void> _openSourceFilter() async {
    final result = await showSourceFilterDialog(context, _sourceOrder);
    if (result == null) return;
    setState(() => _sourceOrder = result);
    await SourceFilterPrefs.save(result);
  }

  Future<void> _setSortMode(SearchSort? mode) async {
    if (mode == null || mode == _sortMode) return;
    setState(() => _sortMode = mode);
    await SearchSortPrefs.save(mode);
  }

  Future<void> _openDisplaySettings() async {
    final result = await showPoemDisplaySettingsDialog(context, _display);
    if (result == null) return;
    setState(() => _display = result);
    await PoemDisplayPrefs.save(result);
    AppFonts.currentFamily.value = result.fontFamily;
  }

  Future<void> _setSearchInTitles(bool enabled) async {
    setState(() => _searchInTitles = enabled);
    await SearchTitlesPrefs.save(enabled);
  }

  Future<void> _openResultsDisplaySettings() async {
    final result =
        await showResultsDisplaySettingsDialog(context, _resultsDisplay);
    if (result == null) return;
    setState(() => _resultsDisplay = result);
    await ResultsDisplayPrefs.save(result);
    AppFonts.currentResultsFontSize.value = result.fontSize;
    AppFonts.currentResultsFamily.value = result.fontFamily;
  }

  Future<void> _setMemoryPreset(MemoryPreset? preset) async {
    if (preset == null || preset == _memoryPreset) return;
    setState(() => _memoryPreset = preset);
    await MemoryPresetPrefs.save(preset);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('سيسري تغيير إعداد الذاكرة عند إعادة تشغيل التطبيق'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
        actions: const [CommonAppBarActions(showSettings: false)],
      ),
      body: ListView(
        children: [
          const SectionHeader('المصادر'),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('ترتيب المصادر وتصفيتها'),
            subtitle: Text('${_sourceOrder.length} من ${Source.values.length}'),
            onTap: _openSourceFilter,
          ),
          const Divider(),
          const SectionHeader('ترتيب النتائج'),
          RadioGroup<SearchSort>(
            groupValue: _sortMode,
            onChanged: _setSortMode,
            child: Column(
              children: [
                for (final sort in SearchSort.values)
                  RadioListTile<SearchSort>(
                    value: sort,
                    title: Text(sort.label),
                  ),
              ],
            ),
          ),
          const Divider(),
          const SectionHeader('البحث في العناوين'),
          SwitchListTile(
            title: const Text('البحث في العناوين'),
            subtitle: const Text(
              'عند إيقافه لن تُبحث العناوين ولن يظهر قسم نتائجها',
            ),
            value: _searchInTitles,
            onChanged: _setSearchInTitles,
          ),
          const Divider(),
          const SectionHeader("إعدادات عرض القصائد"),
          ListTile(
            leading: const Icon(Icons.format_size),
            title: const Text('حجم الخط والمسافة والخط المستخدم'),
            subtitle: Text(
              '${_display.fontSize.round()} — ${AppFonts.labelFor(_display.fontFamily)}',
            ),
            onTap: _openDisplaySettings,
          ),
          const Divider(),
          const SectionHeader('إعدادات عرض نتائج البحث'),
          ListTile(
            leading: const Icon(Icons.format_size),
            title: const Text('حجم الخط والخط المستخدم لنتائج البحث'),
            subtitle: Text(
              '${_resultsDisplay.fontSize.round()} — '
              '${AppFonts.labelFor(_resultsDisplay.fontFamily)}',
            ),
            onTap: _openResultsDisplaySettings,
          ),
          const Divider(),
          const SectionHeader('استهلاك الذاكرة'),
          RadioGroup<MemoryPreset>(
            groupValue: _memoryPreset,
            onChanged: _setMemoryPreset,
            child: Column(
              children: [
                for (final preset in MemoryPreset.values)
                  RadioListTile<MemoryPreset>(
                    value: preset,
                    title: Text(preset.label),
                  ),
              ],
            ),
          ),
          const Divider(),
          const SectionHeader('حول البرنامج'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('حول البرنامج'),
            onTap: () => showAppAboutDialog(context),
          ),
        ],
      ),
    );
  }
}
