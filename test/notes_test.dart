import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midad/data/datasources/book_database.dart';
import 'package:midad/data/models/book_model.dart';
import 'package:midad/data/models/note_model.dart';
import 'package:midad/presentation/pages/reader_screen.dart';
import 'package:midad/state/library_store.dart';
import 'package:midad/state/notes_store.dart';

/// EPUB صغير: فصلان عربيان.
Uint8List _epubFixture() {
  const containerXml =
      '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
      'version="1.0"><rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';
  const opfXml =
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>كتاب الاختبار</dc:title></metadata>'
      '<manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/></manifest>'
      '<spine><itemref idref="c1"/><itemref idref="c2"/></spine></package>';
  const c1 =
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>أول</title></head>'
      '<body><h1>أول</h1><p>نص الفصل الأول طويل بما يكفي ليملأ الشاشة.</p>'
      '<p>فقرات متعددة تساعد في قياس ارتفاع العنصر.</p></body></html>';
  const c2 =
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>ثاني</title></head>'
      '<body><h2>ثاني</h2><p>نص الفصل الثاني.</p></body></html>';

  final archive = Archive()
    ..addFile(ArchiveFile('mimetype', 20, utf8.encode('application/epub+zip')))
    ..addFile(ArchiveFile('META-INF/container.xml', containerXml.length,
        utf8.encode(containerXml)))
    ..addFile(
        ArchiveFile('OEBPS/content.opf', opfXml.length, utf8.encode(opfXml)))
    ..addFile(ArchiveFile('OEBPS/c1.xhtml', c1.length, utf8.encode(c1)))
    ..addFile(ArchiveFile('OEBPS/c2.xhtml', c2.length, utf8.encode(c2)));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

BookModel _book(String id, String path, BookFileType type, int currentPage) {
  final now = DateTime(2026, 1, 1);
  return BookModel(
    id: id,
    title: 'كتاب $id',
    filePath: path,
    fileType: type,
    currentPage: currentPage,
    totalPages: 0,
    progressPercentage: 0,
    isFavorite: false,
    isPinned: false,
    createdAt: now,
    lastReadAt: now,
  );
}

void main() {
  group('BookDatabase — الملاحظات (4.4)', () {
    late Directory tempDir;
    late BookDatabase db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('midad_notes_db_');
      db = await BookDatabase.open(
          overridePath: '${tempDir.path}/notes.db');
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('إضافة وقراءة ملاحظات كتاب — مرتبة حسب الصفحة ثم الأحدث', () async {
      final now = DateTime(2026, 1, 1);
      await db.insertNote(NoteModel(
          id: 'n1', bookId: 'b1', pageNumber: 3, content: 'ثالثة', createdAt: now));
      await db.insertNote(NoteModel(
          id: 'n2', bookId: 'b1', pageNumber: 1, content: 'أولى', createdAt: now));
      await db.insertNote(NoteModel(
          id: 'n3', bookId: 'b1', pageNumber: 2, content: 'ثانية', createdAt: now));
      await db.insertNote(NoteModel(
          id: 'nx', bookId: 'b2', pageNumber: 9, content: 'كتاب آخر', createdAt: now));

      final notes = await db.getNotesForBook('b1');
      expect(notes.map((n) => n.pageNumber).toList(), [1, 2, 3]);
      expect(notes.first.content, 'أولى');
      // كتاب آخر لا يختلط
      expect(await db.getNotesForBook('b2'), hasLength(1));
    });

    test('حذف ملاحظة وحذف كل ملاحظات كتاب', () async {
      final now = DateTime(2026, 1, 1);
      await db.insertNote(NoteModel(
          id: 'n1', bookId: 'b1', pageNumber: 1, content: 'واحدة', createdAt: now));
      await db.insertNote(NoteModel(
          id: 'n2', bookId: 'b1', pageNumber: 2, content: 'اثنتان', createdAt: now));

      await db.deleteNote('n1');
      var notes = await db.getNotesForBook('b1');
      expect(notes, hasLength(1));
      expect(notes.first.id, 'n2');

      await db.deleteNotesForBook('b1');
      notes = await db.getNotesForBook('b1');
      expect(notes, isEmpty);
    });
  });

  group('NotesStore — المنطق', () {
    test('يضيف ويحذف في الذاكرة ويحافظ على الترتيب', () async {
      final store = NotesStore();
      await store.loadForBook('b1');

      await store.addNote(pageNumber: 2, content: 'ثانية');
      await store.addNote(pageNumber: 1, content: 'أولى');
      expect(store.notes.map((n) => n.pageNumber).toList(), [1, 2]);
      expect(store.notes.first.content, 'أولى');

      await store.deleteNote(store.notes.first.id);
      expect(store.notes, hasLength(1));
      expect(store.notes.first.pageNumber, 2);
    });

    test('يرفض الملاحظة الفارغة وبلا كتاب', () async {
      final store = NotesStore();
      await store.addNote(pageNumber: 1, content: '   ');
      expect(store.notes, isEmpty);
    });

    test('مع قاعدة: يحفظ ويستعيد من SQLite', () async {
      final tempDir = await Directory.systemTemp.createTemp('midad_notes_');
      final db = await BookDatabase.open(
          overridePath: '${tempDir.path}/n.db');
      final store = NotesStore(database: db);
      await store.loadForBook('b1');
      await store.addNote(pageNumber: 5, content: 'خامسة');

      // مخزن جديد يقرأ من نفس القاعدة
      final store2 = NotesStore(database: db);
      await store2.loadForBook('b1');
      expect(store2.notes, hasLength(1));
      expect(store2.notes.first.content, 'خامسة');

      // حذف الكتاب يحذف ملاحظاته
      await store2.deleteForBook('b1');
      final store3 = NotesStore(database: db);
      await store3.loadForBook('b1');
      expect(store3.notes, isEmpty);

      await db.close();
      tempDir.deleteSync(recursive: true);
    });
  });

  group('ReaderScreen — القائمة الجانبية للملاحظات', () {
    late Directory tempDir;
    late File epubFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('midad_notes_ui_');
      epubFile = File('${tempDir.path}/book.epub');
      await epubFile.writeAsBytes(_epubFixture());
    });

    tearDown(() async {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    testWidgets('فتح الدرج + إضافة ملاحظة + ظهورها + حذفها', (tester) async {
      final store = LibraryStore(initialBooks: [
        _book('b1', epubFile.path, BookFileType.epub, 1),
      ]);
      final notes = NotesStore();
      await notes.loadForBook('b1');

      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: ReaderScreen(
              book: store.books.first, store: store, notesStore: notes),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 800));
      });
      await tester.pump();

      // فتح القائمة الجانبية من زر AppBar
      await tester.tap(find.byTooltip('الملاحظات'));
      await tester.pumpAndSettle();
      expect(find.text('الملاحظات'), findsOneWidget);
      expect(find.text('لا توجد ملاحظات بعد'), findsOneWidget);

      // إضافة ملاحظة على الصفحة الحالية (الفصل 1)
      await tester.tap(find.byTooltip('إضافة ملاحظة على الصفحة الحالية'));
      await tester.pumpAndSettle();
      expect(find.text('ملاحظة على صفحة 1'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'تذكير مهم');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();

      expect(find.text('تذكير مهم'), findsOneWidget);
      expect(find.text('صفحة 1'), findsOneWidget);

      // حذف الملاحظة
      await tester.tap(find.byTooltip('حذف الملاحظة'));
      await tester.pumpAndSettle();
      expect(find.text('لا توجد ملاحظات بعد'), findsOneWidget);
    });

    testWidgets('النقر على ملاحظة يقفز لصفحتها في الكتاب', (tester) async {
      final store = LibraryStore(initialBooks: [
        _book('b1', epubFile.path, BookFileType.epub, 1),
      ]);
      final notes = NotesStore(initialNotes: [
        NoteModel(
          id: 'n1',
          bookId: 'b1',
          pageNumber: 2,
          content: 'ملاحظة على الفصل الثاني',
          createdAt: DateTime(2026, 1, 1),
        ),
      ]);
      await notes.loadForBook('b1');

      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: ReaderScreen(
              book: store.books.first, store: store, notesStore: notes),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 800));
      });
      await tester.pump();

      // نبدأ في الفصل 1 ثم نقفز للفصل 2 عبر الملاحظة
      await tester.tap(find.byTooltip('الملاحظات'));
      await tester.pumpAndSettle();
      expect(find.text('ملاحظة على الفصل الثاني'), findsOneWidget);

      await tester.tap(find.text('ملاحظة على الفصل الثاني'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // الدرج أُغلق والقارئ قفز للفصل الثاني
      expect(find.text('فصل 2 من 2'), findsOneWidget);
      expect(find.text('الملاحظات'), findsNothing);
    });
  });
}
