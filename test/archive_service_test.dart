import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import 'package:midad/data/models/book_model.dart';
import 'package:midad/data/services/archive_service.dart';
import 'package:midad/presentation/pages/online_search_page.dart';
import 'package:midad/state/library_store.dart';

void main() {
  group('ArchiveService — البحث', () {
    test('يبني الاستعلام (PDF فقط + NSFW) ويحلل النتائج ويفلتر برمجياً',
        () async {
      late Uri captured;
      final client = MockClient((req) async {
        captured = req.url;
        return http.Response(
          jsonEncode({
            'response': {
              'docs': [
                {
                  'identifier': 'good1',
                  'title': 'رياض الصالحين',
                  'creator': 'النووي',
                  'year': '1300',
                },
                {
                  'identifier': 'bad1',
                  'title': 'Erotica Collection',
                  'creator': null,
                },
                {
                  'identifier': 'bad2',
                  'title': 'كتاب إباحي ممنوع',
                },
                {
                  'identifier': 'empty',
                  'title': '',
                },
              ],
            }
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = ArchiveService(client: client);

      final results = await service.search('رياض');

      // فلترة الاستعلام: PDF فقط + موضوعات محجوبة
      final q = captured.queryParameters['q']!;
      expect(q, contains('(رياض)'));
      expect(q, contains('mediatype:texts'));
      expect(q, contains('format:PDF'));
      expect(q, contains('-subject:erotica'));
      expect(q, contains('-subject:pornography'));
      // الفلتر البرمجي: سقطت نتائج NSFW والفارغة
      expect(results, hasLength(1));
      expect(results.first.identifier, 'good1');
      expect(results.first.subtitle, 'النووي · 1300');
    });

    test('يرمي خطأ عند فشل الاتصال', () async {
      final client =
          MockClient((req) async => http.Response('oops', 500));
      final service = ArchiveService(client: client);
      await expectLater(
        service.search('رياض'),
        throwsA(isA<ArchiveException>()),
      );
    });
  });

  group('ArchiveService — ملف PDF الفعلي', () {
    test('يختار أكبر ملف PDF ويتجاهل نسخ النص المشتقة', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'files': [
              {'name': 'book_text.pdf', 'format': 'Text PDF', 'size': 100},
              {'name': 'book.pdf', 'format': 'PDF', 'size': 5000},
              {'name': 'book_djvu.txt', 'format': 'Djvu.txt', 'size': 999},
              {'name': 'small.pdf', 'format': 'PDF', 'size': 10},
            ]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = ArchiveService(client: client);
      expect(await service.fetchPdfFileName('x'), 'book.pdf');
    });

    test('يعيد null عندما لا يوجد PDF فعلي', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'files': [
              {'name': 'book_djvu.txt', 'format': 'Djvu.txt', 'size': 999},
            ]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = ArchiveService(client: client);
      expect(await service.fetchPdfFileName('x'), isNull);
    });
  });

  group('ArchiveService — التنزيل والتحقق', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('midad_dl');
    });

    tearDown(() async {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('ينزل ملفاً صالحاً (magic bytes %PDF) ويتتبع التقدم', () async {
      final pdfBytes = [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34];
      final client =
          MockClient((req) async => http.Response.bytes(pdfBytes, 200));
      final service = ArchiveService(client: client);
      final target = '${tempDir.path}/b.pdf';

      double? last;
      await service.downloadPdf(
        identifier: 'x',
        pdfName: 'b.pdf',
        targetPath: target,
        onProgress: (p) => last = p,
      );

      expect(await File(target).readAsBytes(), pdfBytes);
      expect(last, 1.0);
    });

    test('يرفض ملف HTML ويعيد رمز 200 (فخ الأرشيف) ويحذف الملف', () async {
      final client = MockClient(
          (req) async => http.Response('<html>cloudflare</html>', 200));
      final service = ArchiveService(client: client);
      final target = '${tempDir.path}/b.pdf';

      await expectLater(
        service.downloadPdf(identifier: 'x', pdfName: 'b.pdf', targetPath: target),
        throwsA(isA<ArchiveException>()),
      );
      expect(File(target).existsSync(), isFalse);
    });

    test('يرمي خطأ عند رمز غير 200', () async {
      final client =
          MockClient((req) async => http.Response('not found', 404));
      final service = ArchiveService(client: client);
      await expectLater(
        service.downloadPdf(identifier: 'x', pdfName: 'b.pdf', targetPath: '${tempDir.path}/b.pdf'),
        throwsA(isA<ArchiveException>()),
      );
    });

    test('ينزل غلافاً صالحاً (JPEG magic bytes) ويحفظه محلياً', () async {
      // FFD8FF = JPEG
      final jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
      final client =
          MockClient((req) async => http.Response.bytes(jpeg, 200));
      final service = ArchiveService(client: client);
      final target = '${tempDir.path}/cover.jpg';

      await service.downloadCover(identifier: 'x', targetPath: target);

      expect(await File(target).readAsBytes(), jpeg);
    });

    test('يرفض غلاف HTML ويعيد 200 (فخ الأرشيف) ويحذف الملف', () async {
      final client = MockClient(
          (req) async => http.Response('<html>cloudflare</html>', 200));
      final service = ArchiveService(client: client);
      final target = '${tempDir.path}/cover.jpg';

      await expectLater(
        service.downloadCover(identifier: 'x', targetPath: target),
        throwsA(isA<ArchiveException>()),
      );
      expect(File(target).existsSync(), isFalse);
    });
  });

  group('LibraryStore — الإضافة التلقائية', () {
    test('addDownloadedBook يضيف كتاباً ويمنع التكرار حسب العنوان', () async {
      final store = LibraryStore();

      final ok = await store.addDownloadedBook(
        title: 'رياض الصالحين',
        filePath: '/tmp/riyad.pdf',
        fileType: BookFileType.pdf,
      );
      expect(ok, isTrue);
      expect(store.books, hasLength(1));
      expect(store.books.first.id, startsWith('dl_'));

      final dup = await store.addDownloadedBook(
        title: 'رياض الصالحين',
        filePath: '/tmp/other.pdf',
        fileType: BookFileType.pdf,
      );
      expect(dup, isFalse);
      expect(store.books, hasLength(1));
    });

    test('addDownloadedBook يخزّن coverPath إذا مُرِّر', () async {
      final store = LibraryStore();

      await store.addDownloadedBook(
        title: 'بهجة السالكين',
        filePath: '/tmp/bahja.pdf',
        fileType: BookFileType.pdf,
        coverPath: '/tmp/bahja.jpg',
      );

      expect(store.books.first.coverPath, '/tmp/bahja.jpg');
    });
  });

  group('OnlineSearchPage — البحث التلقائي', () {
    testWidgets('كتابة اسم تعرض النتائج تلقائياً بلا زر بحث', (tester) async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'response': {
              'docs': [
                {
                  'identifier': 'riyad',
                  'title': 'رياض الصالحين',
                  'creator': 'النووي',
                  'year': '1300',
                  'description': 'كتاب في الحديث',
                },
              ],
            }
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = ArchiveService(client: client);
      final store = LibraryStore();

      await tester.pumpWidget(MaterialApp(
        home: OnlineSearchPage(store: store, service: service),
      ));

      // كتابة النص فقط — لا ضغطة زر — ثم تجاوز الـ debounce
      await tester.enterText(find.byType(TextField), 'رياض');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.text('رياض الصالحين'), findsOneWidget);
      expect(find.text('النووي · 1300'), findsOneWidget);
      expect(find.byTooltip('تنزيل PDF وإضافته للمكتبة'), findsOneWidget);
      // غلاف من الشبكة — في بيئة الاختبار يفشل التحميل فيظهر البديل
      expect(find.byIcon(LucideIcons.bookOpen), findsOneWidget);
    });

    testWidgets('كتابة أقل من 3 أحرف لا تطلق بحثاً، والمسح يعيد الحالة',
        (tester) async {
      var requests = 0;
      final client = MockClient((req) async {
        requests++;
        return http.Response(
          jsonEncode({
            'response': {
              'docs': [
                {'identifier': 'x1', 'title': 'كتاب عربي'},
              ],
            }
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = ArchiveService(client: client);
      final store = LibraryStore();

      await tester.pumpWidget(MaterialApp(
        home: OnlineSearchPage(store: store, service: service),
      ));

      await tester.enterText(find.byType(TextField), 'ري');
      await tester.pump(const Duration(milliseconds: 700));
      expect(requests, 0);
      expect(find.text('ابحث عن كتاب — النتائج PDF فقط'), findsOneWidget);

      // 3 أحرف تطلق البحث تلقائياً
      await tester.enterText(find.byType(TextField), 'رياض');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('كتاب عربي'), findsOneWidget);

      // زر المسح يعيد صفحة البداية ويمسح النتائج
      await tester.tap(find.byTooltip('مسح'));
      await tester.pumpAndSettle();
      expect(find.text('ابحث عن كتاب — النتائج PDF فقط'), findsOneWidget);
    });
  });
}
