import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:midad/data/models/book_model.dart';
import 'package:midad/data/services/book_import_service.dart';

void main() {
  group('BookImportService', () {
    late Directory tmp;
    late String libraryDir;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('midad_import_test');
      libraryDir = '${tmp.path}/library';
    });

    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    group('titleFromFile', () {
      test('يستخرج العنوان بدون الامتداد مع الحفاظ على العربية', () {
        expect(
          BookImportService.titleFromFile(File('/books/رياض الصالحين.pdf')),
          'رياض الصالحين',
        );
      });

      test('اسم بلا امتداد يُرجع كما هو', () {
        expect(
          BookImportService.titleFromFile(File('/books/no_extension')),
          'no_extension',
        );
      });
    });

    group('typeFromFile', () {
      test('epub → epub، pdf → pdf، غيره → pdf', () {
        expect(
          BookImportService.typeFromFile(File('/books/a.epub')),
          BookFileType.epub,
        );
        expect(
          BookImportService.typeFromFile(File('/books/a.pdf')),
          BookFileType.pdf,
        );
        expect(
          BookImportService.typeFromFile(File('/books/a.txt')),
          BookFileType.pdf,
        );
      });
    });

    group('safeFileName', () {
      test('يُزيل محارف المسار فقط ويبقي العربية', () {
        expect(BookImportService.safeFileName('سيرة/ابن هشام'), 'سيرة_ابن هشام');
        expect(
          BookImportService.safeFileName('سؤال: ما الجواب؟'),
          'سؤال_ ما الجواب؟',
        );
      });

      test('مسافات فقط → book', () {
        expect(BookImportService.safeFileName('   '), 'book');
      });
    });

    group('importFile', () {
      test('ينسخ ملف PDF ويبني نموذجاً سليماً', () async {
        final src = File('${tmp.path}/كتاب تجريبي.pdf')
          ..writeAsBytesSync([0x25, 0x50, 0x44, 0x46, 1, 2, 3]);

        final book = await BookImportService.importFile(
          src,
          libraryDir: libraryDir,
        );

        expect(book.title, 'كتاب تجريبي');
        expect(book.fileType, BookFileType.pdf);
        expect(book.filePath, '$libraryDir/كتاب تجريبي.pdf');
        expect(File(book.filePath).existsSync(), isTrue);
        expect(await File(book.filePath).length(), await src.length());
        expect(book.isFavorite, isFalse);
        expect(book.isPinned, isFalse);
        expect(book.totalPages, 0);
        expect(book.id, isNotEmpty);
      });

      test('ينسخ EPUB ويحدد نوعه', () async {
        final src = File('${tmp.path}/البداية والنهاية.epub')
          ..writeAsBytesSync([0x50, 0x4B, 0x03, 0x04]);

        final book = await BookImportService.importFile(
          src,
          libraryDir: libraryDir,
        );

        expect(book.fileType, BookFileType.epub);
        expect(book.filePath, '$libraryDir/البداية والنهاية.epub');
        expect(File(book.filePath).existsSync(), isTrue);
      });

      test('لا يمسّ الملف الأصلي (نسخ لا نقل)', () async {
        final src = File('${tmp.path}/أصل.pdf')
          ..writeAsBytesSync([0x25, 0x50, 0x44, 0x46]);

        await BookImportService.importFile(src, libraryDir: libraryDir);

        expect(src.existsSync(), isTrue);
      });

      test('إعادة استيراد نفس العنوان تستبدل الملف في المساحة الداخلية',
          () async {
        final src = File('${tmp.path}/same.pdf')
          ..writeAsBytesSync([1, 2, 3]);

        final b1 = await BookImportService.importFile(
          src,
          libraryDir: libraryDir,
        );
        final b2 = await BookImportService.importFile(
          src,
          libraryDir: libraryDir,
        );

        // نفس المسار (استبدال)، ومعرّفان مختلفان (إدراجان مستقلان)
        expect(b1.filePath, b2.filePath);
        expect(b1.id, isNot(b2.id));
      });
    });
  });
}
