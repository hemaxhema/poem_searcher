import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher.dart';

/// Shows the app's "About" dialog: name, version (read from the bundled
/// version.txt asset, kept in sync with the Inno Setup installer), and
/// tappable contact links.
void showAppAboutDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('حول البرنامج'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'باحث الشعر',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            FutureBuilder<String>(
              future: rootBundle.loadString('version.txt'),
              builder: (context, snapshot) {
                final version = snapshot.data?.trim();
                return Text(
                  version == null ? '' : 'الإصدار: $version',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                );
              },
            ),
            const SizedBox(height: 16),
            const _AboutLinkRow(
              label: 'البريد الإلكتروني:',
              display: 'ibraheemabdullatif25@gmail.com',
              url: 'mailto:ibraheemabdullatif25@gmail.com',
            ),
            const _AboutLinkRow(
              label: 'تيليجرام:',
              display: 'https://t.me/ibraheem_abdullatif',
              url: 'https://t.me/ibraheem_abdullatif',
            ),
            const _AboutLinkRow(
              label: 'GitHub:',
              display: 'https://github.com/hemaxhema/poem_searcher',
              url: 'https://github.com/hemaxhema/poem_searcher',
            ),
          ],
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

Future<void> _openLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  final ok =
      uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح الرابط')),
    );
  }
}

/// One RTL label/value row in the About dialog, with the value rendered as a
/// tappable link (e.g. an email, a Telegram or GitHub URL).
class _AboutLinkRow extends StatelessWidget {
  const _AboutLinkRow({
    required this.label,
    required this.display,
    required this.url,
  });

  final String label;
  final String display;
  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => _openLink(context, url),
              child: Text(
                display,
                textAlign: TextAlign.left,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
