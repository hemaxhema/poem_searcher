@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:poem_searcher/db/search_index.dart';
import 'package:poem_searcher/models/source.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Exercises the full lean-ship / first-run-build round trip end-to-end
/// (mirrors tool/make_lean_db.dart + the app's first launch) against an
/// in-memory database with the production schema, so both tools are proven
/// correct without touching the real multi-GB asset.
void main() {
  setUpAll(() => sqfliteFfiInit());

  Future<Database> openSchema() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE poem (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        poet_id INTEGER, source_url TEXT UNIQUE, title TEXT,
        book TEXT, page TEXT, type TEXT,
        line_count INTEGER, source_id INTEGER
      )''');
    await db.execute('''
      CREATE TABLE lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        poem_id INTEGER NOT NULL REFERENCES poem(id),
        line TEXT, line_number INTEGER, line_type TEXT
      )''');
    await db.insert('poem', {
      'poet_id': 1,
      'source_url': '1',
      'title': 'قَالُوا',
      'source_id': Source.uqu.index,
    });
    await db.insert('poem', {
      'poet_id': 2,
      'source_url': '2',
      'title': 'بيت ثانٍ',
      'source_id': Source.aldiwan.index,
    });
    await db.insert('lines',
        {'poem_id': 1, 'line': 'قَالُوا لَهُ', 'line_number': 1});
    await db.insert('lines',
        {'poem_id': 1, 'line': 'وَذَهَبُوا', 'line_number': 2});
    await db.insert(
        'lines', {'poem_id': 2, 'line': 'بيت آخر', 'line_number': 1});
    return db;
  }

  Future<void> dropDerived(Database db) async {
    // Mirrors tool/make_lean_db.dart (minus the VACUUM, irrelevant in-memory).
    await db.execute('DROP TABLE IF EXISTS lines_fts');
    await db.execute('ALTER TABLE lines DROP COLUMN plain');
    await db.execute('ALTER TABLE poem DROP COLUMN title_plain');
    for (final idx in const [
      'idx_lines_poem',
      'idx_poem_poet_id',
      'idx_poem_source_id',
      'idx_poem_alias_poem',
      'idx_poem_alias_source',
    ]) {
      await db.execute('DROP INDEX IF EXISTS $idx');
    }
  }

  Future<bool> hasColumn(Database db, String table, String col) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((r) => r['name'] == col);
  }

  Future<bool> hasIndex(Database db, String name) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='index' AND name=?",
      [name],
    );
    return rows.isNotEmpty;
  }

  Future<void> expectFullyBuilt(Database db) async {
    expect(await hasColumn(db, 'lines', 'plain'), isTrue);
    expect(await hasColumn(db, 'poem', 'title_plain'), isTrue);
    expect(await hasColumn(db, 'poem', 'line_count'), isTrue);

    final plainRows = await db.rawQuery('SELECT plain FROM lines');
    expect(plainRows.every((r) => (r['plain'] as String).isNotEmpty), isTrue);
    final titleRows = await db.rawQuery('SELECT title_plain FROM poem');
    expect(
        titleRows.every((r) => (r['title_plain'] as String).isNotEmpty), isTrue);
    final counts = await db.rawQuery('SELECT id, line_count FROM poem');
    expect(counts.firstWhere((r) => r['id'] == 1)['line_count'], 2);
    expect(counts.firstWhere((r) => r['id'] == 2)['line_count'], 1);

    for (final idx in const [
      'idx_lines_poem',
      'idx_poem_poet_id',
      'idx_poem_source_id',
      'idx_poem_alias_poem',
      'idx_poem_alias_source',
    ]) {
      expect(await hasIndex(db, idx), isTrue, reason: '$idx missing');
    }

    // The trigram FTS index actually finds a substring match.
    final hit = await db.rawQuery(
        "SELECT l.line FROM lines_fts f JOIN lines l ON l.id = f.rowid "
        "WHERE f.plain LIKE '%قالوا%'");
    expect(hit, hasLength(1));
    expect(hit.first['line'], 'قَالُوا لَهُ');

    // `source` is populated with every Source value, keyed by its enum index.
    final sourceRows = await db.rawQuery('SELECT id, name, url_prefix FROM source');
    expect(sourceRows, hasLength(Source.values.length));
    for (final source in Source.values) {
      final row = sourceRows.firstWhere((r) => r['id'] == source.index);
      expect(row['name'], source.displayName);
      expect(row['url_prefix'], source.urlPrefix);
    }
  }

  test('buildSearchIndex fully builds a fresh lean database', () async {
    final db = await openSchema();
    await buildSearchIndex(db);
    await expectFullyBuilt(db);
    await db.close();
  });

  test('make_lean_db round trip: build -> lean -> rebuild reproduces the '
      'same index', () async {
    final db = await openSchema();
    await buildSearchIndex(db);
    await expectFullyBuilt(db);

    await dropDerived(db);
    expect(await hasColumn(db, 'lines', 'plain'), isFalse);
    expect(await hasColumn(db, 'poem', 'title_plain'), isFalse);
    // line_count is shipped in the lean asset (not dropped by make_lean_db).
    expect(await hasColumn(db, 'poem', 'line_count'), isTrue);

    await buildSearchIndex(db);
    await expectFullyBuilt(db);
    await db.close();
  });

  test('buildSearchIndex is idempotent (safe to run twice)', () async {
    final db = await openSchema();
    await buildSearchIndex(db);
    await buildSearchIndex(db);
    await expectFullyBuilt(db);
    await db.close();
  });

  test('poem_alias table/indexes are created empty for a pre-dedup lean DB',
      () async {
    final db = await openSchema();
    await buildSearchIndex(db);
    final rows = await db.rawQuery('SELECT COUNT(*) c FROM poem_alias');
    expect(rows.first['c'], 0);
    await db.close();
  });

  test('an existing poem_alias row survives buildSearchIndex untouched',
      () async {
    final db = await openSchema();
    await db.execute('''
      CREATE TABLE poem_alias (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        poem_id INTEGER NOT NULL REFERENCES poem(id),
        source_url TEXT, source_id INTEGER,
        poet TEXT, book TEXT, page TEXT, type TEXT
      )''');
    await db.insert('poem_alias', {
      'poem_id': 1,
      'source_url': 'old',
      'source_id': Source.dct.index,
    });
    await buildSearchIndex(db);
    final rows = await db.rawQuery('SELECT * FROM poem_alias');
    expect(rows, hasLength(1));
    expect(rows.first['source_id'], Source.dct.index);
    expect(await hasIndex(db, 'idx_poem_alias_poem'), isTrue);
    await db.close();
  });
}
