import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the system browser. Returns false when the URL can't be
/// parsed or launched (the caller decides how to surface the failure).
Future<bool> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  return uri != null &&
      await launchUrl(uri, mode: LaunchMode.externalApplication);
}
