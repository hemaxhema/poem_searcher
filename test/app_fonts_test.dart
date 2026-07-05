import 'package:flutter_test/flutter_test.dart';
import 'package:poem_searcher/services/app_fonts.dart';

void main() {
  group('AppFonts.familyIdFor', () {
    test('strips the extension from a fonts asset path', () {
      expect(AppFonts.familyIdFor('assets/fonts/amiri.ttf'), 'amiri');
      expect(AppFonts.familyIdFor('assets/fonts/Cairo.otf'), 'Cairo');
    });

    test('falls back to the whole filename if there is no extension', () {
      expect(AppFonts.familyIdFor('assets/fonts/mystery'), 'mystery');
    });
  });

  group('AppFonts.labelFor', () {
    test('uses the known Arabic/English label for shipped fonts', () {
      expect(AppFonts.labelFor('amiri'), contains('Amiri'));
      expect(AppFonts.labelFor('calibre'), contains('Calibre'));
    });

    test('title-cases an unknown filename as a fallback label', () {
      expect(AppFonts.labelFor('my_custom-font'), 'My Custom Font');
    });
  });
}
