import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'db/poem_repository.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PoemSearcherApp());
}

class PoemSearcherApp extends StatelessWidget {
  const PoemSearcherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'البحث في الشعر',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF00695C),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF00695C),
        brightness: Brightness.dark,
      ),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Bootstrap(),
    );
  }
}

/// Opens the repository once and then shows the home page. All Arabic UI is
/// forced RTL regardless of platform locale.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<PoemRepository> _repoFuture = PoemRepository.open();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<PoemRepository>(
        future: _repoFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('تعذّر فتح قاعدة البيانات:\n${snapshot.error}'),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return HomePage(repo: snapshot.data!);
        },
      ),
    );
  }
}
