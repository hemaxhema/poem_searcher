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
