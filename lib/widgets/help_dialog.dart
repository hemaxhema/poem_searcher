import 'package:flutter/material.dart';

/// Shows a dialog explaining the search syntax (special symbols, quoting,
/// tashkeel matching) and keyboard shortcuts.
void showHelpDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('مساعدة البحث'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HelpSectionHeader('ملخص سريع لكل الرموز'),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'في المربع الرئيسي (بحث عادي):',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const _QuickRefTable([
                _QuickRef('*', 'إكمال جزء من كلمة (داخل الكلمة فقط)'),
                _QuickRef('? / ؟', 'حرف واحد مجهول'),
                _QuickRef('_', 'تجاوز كلمة كاملة أو أكثر'),
                _QuickRef('" "', 'مطابقة حرفية دقيقة (بلا إبدال ي/ى أو الهمزة)'),
              ]),
              const SizedBox(height: 10),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'في نافذة البحث المنطقي فقط:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const _QuickRefTable([
                _QuickRef('+', 'و (يجب وجود الطرفين)'),
                _QuickRef('|', 'أو (أحد الطرفين) — يمكن أيضًا استخدام , أو ،'),
                _QuickRef('-', 'بدون (نفي كلمة أو مجموعة كاملة)'),
                _QuickRef('( )', 'تجميع لتوضيح الأولوية'),
                _QuickRef('[ ]', 'بدائل داخل الكلمة، مع ! للاستبعاد وخانة فارغة للاختياري'),
              ]),
              const Divider(),
              const _HelpSectionHeader('أساسيات البحث'),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'التشكيل اختياري: اكتب الحرف مجردًا من الحركة فيُطابق '
                  'الحرف بأي حركة أو بدونها، أو أضف الحركة صراحة بعد الحرف '
                  'ليُطابق البحث تلك الحركة فقط. تُتجاهل علامات الترقيم '
                  'والتطويل (ـ) وعلامة (=) الفاصلة بين الشطرين. كما يُطابق '
                  'البحث حدود الكلمات: يجب أن يبدأ أول حرف تكتبه ببداية '
                  'كلمة في النص وأن ينتهي آخر حرف بنهاية كلمة، فلا تُطابَق '
                  'العبارة إذا وقعت في منتصف كلمة أطول.',
                ),
              ),
              const Divider(),
              const _HelpSymbolRow(
                symbol: '*',
                title: 'النجمة *: إكمال جزء من كلمة',
                body: 'تُطابق النجمة صفرًا أو أكثر من الحروف داخل نفس الكلمة '
                    'فقط، ولا تتخطى المسافة إلى كلمة أخرى — استخدمها '
                    'لإكمال بداية الكلمة أو نهايتها.',
                example: 'مثال: "فع*" تُطابق كل كلمة تبدأ بـ"فع" مثل "فعل" '
                    'أو "فعال". و"*لام" تُطابق كل كلمة تنتهي بـ"لام" مثل '
                    '"كلام" أو "سلام".',
              ),
              const Divider(),
              const _HelpSymbolRow(
                symbol: '?',
                title: 'علامة الاستفهام ? أو ؟: حرف واحد مجهول',
                body: 'تُطابق علامة الاستفهام حرفًا عربيًا واحدًا غير معروف، '
                    'بأي حركة أو بدونها، في مكانها من الكلمة.',
                example: 'مثال: "?لب" تُطابق أي كلمة على وزن حرف واحد ثم '
                    '"لب"، مثل "قلب" أو "طلب".',
              ),
              const Divider(),
              const _HelpSymbolRow(
                symbol: '_',
                title: 'الشرطة السفلية _: تجاوز كلمة أو أكثر',
                body: 'تُطابق الشرطة السفلية صفرًا أو أكثر من الكلمات '
                    'الكاملة المتتالية؛ وهي نظير النجمة على مستوى الكلمات '
                    'بدل الحروف، فاستخدمها لتخطي كلمة أو أكثر بين جزأين '
                    'من العبارة.',
                example: 'مثال: "قال _ الشعر" تُطابق "قال" يتبعها أي عدد '
                    'من الكلمات ثم "الشعر"، كما في "قال في وصف الشعر".',
              ),
              const Divider(),
              const _HelpSymbolRow(
                symbol: '" "',
                title: 'علامتا التنصيص "...": مطابقة حرفية دقيقة',
                body: 'بشكل افتراضي تُعامَل الحروف المتشابهة رسمًا معاملة '
                    'الحرف نفسه: الياء والألف المقصورة (ي/ى)، وجميع صور '
                    'الألف والهمزة (ا، أ، إ، آ، ؤ، ئ، ء). وضع جزء من '
                    'العبارة بين علامتي تنصيص يُلزم البحث بمطابقة الحروف '
                    'كما كُتبت تمامًا في ذلك الجزء، وتُحذف علامتا التنصيص '
                    'نفسهما من العبارة.',
                example: 'مثال: البحث عن إسلام بلا تنصيص يُطابق أيضًا '
                    '"اسلام" و"أسلام"، أما "إسلام" بالتنصيص فلا يُطابق '
                    'إلا الكتابة بالهمزة "إ" تحديدًا.',
              ),
              const Divider(),
              const _HelpSectionHeader('البحث المنطقي (و / أو / بدون)'),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'من زر «بحث منطقي» (⋮≡) في الأعلى تفتح نافذة تجمع فيها بين '
                  'الكلمات بعوامل بسيطة، وتظهر لك معنى ما كتبته بالعربية قبل '
                  'تنفيذ البحث. كل كلمة تحتفظ بكل مزايا البحث العادي أعلاه.',
                ),
              ),
              const _HelpSymbolRow(
                symbol: '+',
                title: 'زائد +: و (يجب وجود الطرفين)',
                body: 'يطابق البيت الذي يحتوي على الكلمتين معًا في أي موضع '
                    'وبأي ترتيب.',
                example: 'مثال: "محمد + رسول" يطابق الأبيات التي فيها محمد '
                    'ورسول معًا.',
              ),
              const Divider(),
              const _HelpSymbolRow(
                symbol: '|',
                title: 'العمود |: أو (أحد الطرفين)',
                body: 'يطابق البيت الذي يحتوي على أي من الكلمات المفصولة '
                    'بالعمود. يمكن استخدام الفاصلة , أو الفاصلة العربية ، '
                    'بدلًا منه، فكلها تعني الشيء نفسه.',
                example: 'مثال: "حب | هوى | شوق" يطابق أي بيت فيه واحدة من '
                    'هذه الكلمات.',
              ),
              const Divider(),
              const _HelpSymbolRow(
                symbol: '-',
                title: 'ناقص -: بدون (نفي)',
                body: 'يستبعد الأبيات التي تحتوي على الكلمة (أو المجموعة) '
                    'التي تلي علامة الناقص.',
                example: 'مثال: "حب - فراق" يطابق الأبيات التي فيها حب دون '
                    'فراق.',
              ),
              const Divider(),
              const _HelpSymbolRow(
                symbol: '( )',
                title: 'الأقواس ( ): تجميع',
                body: 'تجمع الأقواس جزءًا من التعبير لتوضيح الأولوية، ويمكن '
                    'نفي مجموعة كاملة بوضع ناقص قبلها.',
                example: 'مثال: "أ - (ب + ج)" يطابق ما فيه أ ولا يجتمع فيه '
                    'ب وج معًا.',
              ),
              const Divider(),
              const _HelpSymbolRow(
                symbol: '[ ]',
                title: 'الأقواس المربعة [ ]: بدائل داخل الكلمة',
                body: 'تضع داخل الكلمة عدة بدائل مفصولة بفاصلة، فيُطابق أيٌّ '
                    'منها في ذلك الموضع، ويمكن استبعاد صيغة بوضع علامة تعجّب '
                    '! قبلها. واترك الخانة الأخيرة فارغة (فاصلة في النهاية) '
                    'لتعني «أو لا شيء» فيصبح ذلك الجزء اختياريًّا. تخضع '
                    'البدائل لقواعد التشكيل والإبدال المعتادة. (متاحة في نافذة '
                    'البحث المنطقي فقط.)',
                example: 'مثال: "مسلم[ين,ون]" يطابق مسلمين أو مسلمون. '
                    'و"[و,ي]" يعني الحرف و أو ي، و"[!و]" يعني حرفًا ليس و. '
                    'و"[ين,ون,!يَن]" يطابق ين أو ون دون يَن. '
                    'و"مسلم[ين,ون,]" يطابق مسلم أو مسلمين أو مسلمون.',
              ),
              const Divider(),
              const _HelpSectionHeader('أمثلة مركّبة (نافذة البحث المنطقي)'),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'أمثلة كاملة تجمع عدة رموز معًا، لترى كيف تتعاون فيما بينها:',
                ),
              ),
              const _CompoundExample(
                query: 'مسلم[ين,ون] + (صادق | أمين) - كافر',
                meaning: 'الأبيات التي فيها «مسلمين» أو «مسلمون» (بفضل [ ])، '
                    'مع «صادق» أو «أمين» (بفضل الأقواس والعمود)، '
                    'بشرط ألا يرد فيها «كافر» (بفضل الناقص). لاحظ أن الفاصلة '
                    'داخل [ ] تفصل بدائل الحرف ولا علاقة لها بعامل «أو».',
              ),
              const _CompoundExample(
                query: 'حب - (فراق + بعاد)',
                meaning: 'فيها «حب»، لكن تُستبعد الأبيات التي يجتمع فيها '
                    '«فراق» و«بعاد» معًا (نفي مجموعة كاملة بعد الناقص). '
                    'بيت فيه حب وفراق فقط (بلا بعاد) يظهر.',
              ),
              const _CompoundExample(
                query: '"إسلام" + قو*',
                meaning: 'فيها كلمة «إسلام» بالهمزة تحديدًا (بفضل التنصيص، '
                    'فلا تُطابِق «اسلام» أو «أسلام»)، مع أي كلمة تبدأ بـ«قو» '
                    '(بفضل النجمة)، مثل «قوم» أو «قوة».',
              ),
              const _CompoundExample(
                query: 'قال[وا,] _ الشعر',
                meaning: 'القوس هنا اختياري بخانته الفارغة، فيطابق «قال» أو '
                    '«قالوا»، ثم أي عدد من الكلمات بفضل الشرطة السفلية، ثم '
                    '«الشعر» — مفيد لتغطية صيغتي الفعل في طلب واحد.',
              ),
              const Divider(),
              const _HelpSectionHeader('اختصارات لوحة المفاتيح'),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _KeyChip('Ctrl+F'),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'اضغط Ctrl+F في أي وقت للانتقال إلى مربع البحث '
                        'والتركيز عليه مباشرة.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
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

/// One row of the quick-reference table: a symbol paired with a one-line
/// meaning, without the fuller title/body/example of [_HelpSymbolRow].
class _QuickRef {
  const _QuickRef(this.symbol, this.meaning);
  final String symbol;
  final String meaning;
}

/// A compact scannable list of [_QuickRef] rows (symbol badge + meaning),
/// shown at the top of the dialog before the detailed per-symbol sections.
class _QuickRefTable extends StatelessWidget {
  const _QuickRefTable(this.rows);
  final List<_QuickRef> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    row.symbol,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(row.meaning, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A fully worked boolean-window example: the raw query text (monospace,
/// LTR-safe box) plus a plain-Arabic explanation of what it means, mirroring
/// the live preview shown inside the boolean search window itself.
class _CompoundExample extends StatelessWidget {
  const _CompoundExample({required this.query, required this.meaning});
  final String query;
  final String meaning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              query,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(meaning, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _HelpSectionHeader extends StatelessWidget {
  const _HelpSectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

/// A leading symbol badge + title/body/example, describing one search
/// syntax rule.
class _HelpSymbolRow extends StatelessWidget {
  const _HelpSymbolRow({
    required this.symbol,
    required this.title,
    required this.body,
    required this.example,
  });

  final String symbol;
  final String title;
  final String body;
  final String example;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SymbolBadge(symbol),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(body, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  example,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SymbolBadge extends StatelessWidget {
  const _SymbolBadge(this.symbol);
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        symbol,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _KeyChip extends StatelessWidget {
  const _KeyChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
      ),
    );
  }
}
