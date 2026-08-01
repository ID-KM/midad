import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:midad/data/models/book_model.dart';
import 'package:midad/presentation/pages/reader_screen.dart';
import 'package:midad/presentation/widgets/epub_view.dart';
import 'package:midad/state/library_store.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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

/// PDF صفحتان — عبر حزمة pdf (dev dependency).
Future<Uint8List> _pdfFixture() async {
  final doc = pw.Document();
  for (var i = 1; i <= 2; i++) {
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Center(child: pw.Text('Page $i')),
    ));
  }
  return doc.save();
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

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  late Directory tempDir;
  late File epubFile;
  late File pdfFile;
  late File missingFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('midad_reader_test_');
    epubFile = File('${tempDir.path}/book.epub');
    await epubFile.writeAsBytes(_epubFixture());
    pdfFile = File('${tempDir.path}/book.pdf');
    await pdfFile.writeAsBytes(await _pdfFixture());
    missingFile = File('${tempDir.path}/missing.pdf');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // النمط المعتمد: pumpWidget داخل runAsync — بدونه يعلّق I/O الحقيقي
  // الذي يبدأه initState في الزمن الوهمي ولا يكتمل أبداً.
  testWidgets('EPUB: يفتح الكتاب ويعرض عدّاد الفصول ويحفظ التقدم', (tester) async {
    final store = LibraryStore(
        initialBooks: [_book('e1', epubFile.path, BookFileType.epub, 1)]);

    await tester.runAsync(() async {
      await tester.pumpWidget(
          _wrap(ReaderScreen(book: store.books.first, store: store)));
      // انتظار قراءة الملف وتحليله (I/O حقيقي)
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pump();

    // الفصل الأول ظاهر + العدّاد
    expect(find.text('نص الفصل الأول طويل بما يكفي ليملأ الشاشة.'), findsOneWidget);
    expect(find.text('فصل 1 من 2'), findsOneWidget);

    // الانتقال للفصل التالي عبر زر التنقل
    await tester.tap(find.byTooltip('التالي'));
    await tester.pump();

    expect(find.text('فصل 2 من 2'), findsOneWidget);
    // الحفظ التلقائي: الموضع كُتب في المخزن
    expect(store.books.first.currentPage, 2);
    expect(store.books.first.totalPages, 2);
    expect(store.books.first.progressPercentage, 1.0);

    // العودة للفصل السابق
    await tester.tap(find.byTooltip('السابق'));
    await tester.pump();
    expect(find.text('فصل 1 من 2'), findsOneWidget);
    expect(store.books.first.currentPage, 1);
  });

  testWidgets('ملف غير موجود: رسالة خطأ واضحة', (tester) async {
    final store = LibraryStore(
        initialBooks: [_book('x1', missingFile.path, BookFileType.pdf, 1)]);
    await tester.pumpWidget(
        _wrap(ReaderScreen(book: store.books.first, store: store)));
    await tester.pump();

    expect(find.text('ملف الكتاب غير موجود على الجهاز'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });

  // 4.2: الاستعادة — يفتح على آخر فصل محفوظ (currentPage = 2).
  testWidgets('EPUB: يستعيد آخر فصل محفوظ عند الفتح', (tester) async {
    final store = LibraryStore(
        initialBooks: [_book('e2', epubFile.path, BookFileType.epub, 2)]);

    await tester.runAsync(() async {
      await tester.pumpWidget(
          _wrap(ReaderScreen(book: store.books.first, store: store)));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pump();

    // العدّاد يعرض الفصل المستعاد (وليس الأول)
    expect(find.text('فصل 2 من 2'), findsOneWidget);
  });

  // 4.2: الحفظ اليدوي — زر bookmark يحفظ الموضع ويؤكد عبر SnackBar.
  testWidgets('EPUB: الحفظ اليدوي يحفظ الموضع ويعرض تأكيداً', (tester) async {
    final store = LibraryStore(
        initialBooks: [_book('e3', epubFile.path, BookFileType.epub, 1)]);

    await tester.runAsync(() async {
      await tester.pumpWidget(
          _wrap(ReaderScreen(book: store.books.first, store: store)));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pump();

    // الانتقال للفصل الثاني ثم الحفظ يدوياً
    await tester.tap(find.byTooltip('التالي'));
    await tester.pump();
    expect(find.text('فصل 2 من 2'), findsOneWidget);

    await tester.tap(find.byTooltip('حفظ الموضع يدوياً'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('تم حفظ الموضع: فصل 2'), findsOneWidget);
    expect(store.books.first.currentPage, 2);
    expect(store.books.first.totalPages, 2);
  });

  // الانتقال السريع: النقر على عدّاد الصفحات يفتح حوار إدخال الرقم —
  // كتابة رقم ثم «انتقال» يقفز فعلياً ويحفظ الموضع تلقائياً.
  testWidgets('EPUB: الانتقال السريع — نقر العدّاد + إدخال رقم + قفز فعلي',
      (tester) async {
    final store = LibraryStore(
        initialBooks: [_book('j1', epubFile.path, BookFileType.epub, 1)]);

    await tester.runAsync(() async {
      await tester.pumpWidget(
          _wrap(ReaderScreen(book: store.books.first, store: store)));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pump();

    // النقر على العدّاد (الآن زر) يفتح حوار الانتقال
    await tester.tap(find.byTooltip('الانتقال إلى فصل'));
    await tester.pumpAndSettle();
    expect(find.text('انتقال'), findsOneWidget);
    expect(find.text('إلغاء'), findsOneWidget);

    // كتابة رقم الفصل الثاني ثم التأكيد
    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text('انتقال'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // قفز فعلي للفصل الثاني + الحفظ التلقائي في المخزن
    expect(find.text('فصل 2 من 2'), findsOneWidget);
    expect(store.books.first.currentPage, 2);
    expect(store.books.first.totalPages, 2);
  });

  testWidgets('EPUB: الانتقال السريع — رقم خارج النطاق يُرفض برسالة',
      (tester) async {
    final store = LibraryStore(
        initialBooks: [_book('j2', epubFile.path, BookFileType.epub, 1)]);

    await tester.runAsync(() async {
      await tester.pumpWidget(
          _wrap(ReaderScreen(book: store.books.first, store: store)));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pump();

    await tester.tap(find.byTooltip('الانتقال إلى فصل'));
    await tester.pumpAndSettle();

    // رقم غير موجود في الكتاب
    await tester.enterText(find.byType(TextField), '999');
    await tester.tap(find.text('انتقال'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('رقم فصل يجب أن يكون بين 1 و 2'), findsOneWidget);
    // بلا قفز — ما زلنا في الفصل الأول
    expect(find.text('فصل 1 من 2'), findsOneWidget);
    expect(store.books.first.currentPage, 1);
  });

  testWidgets('EPUB: الانتقال السريع — إلغاء الحوار بلا قفز', (tester) async {
    final store = LibraryStore(
        initialBooks: [_book('j3', epubFile.path, BookFileType.epub, 1)]);

    await tester.runAsync(() async {
      await tester.pumpWidget(
          _wrap(ReaderScreen(book: store.books.first, store: store)));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pump();

    await tester.tap(find.byTooltip('الانتقال إلى فصل'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    // بلا قفز — ما زلنا في الفصل الأول
    expect(find.text('فصل 1 من 2'), findsOneWidget);
    expect(store.books.first.currentPage, 1);
  });

  // 4.3: التمرير التلقائي EPUB — محرك إطار-بإطار: تفعيل/حركة فعلية/
  // توقف عند النهاية/إيقاف. المحرك يستخدم Ticker + jumpTo (كلاهما
  // يعمل في بيئة الاختبار حتى بعد runAsync) — فنختبر الحركة الحقيقية.
  testWidgets('EPUB: التمرير التلقائي — تفعيل/حركة/توقف عند النهاية/إيقاف',
      (tester) async {
    // شاشة 600 افتراضية: المحتوى القصير يتجاوزها (max>0) — لو كبّرناها
    // لصار المحتوى أقصر من الشاشة والتمرير ينهي فوراً. نضيف padding
    // سفلياً فقط (يحاكي الجهاز الحقيقي) ليرتفع الشريط السفلي عن حافة
    // الشاشة — النقر على أزراره عند y=528 يصيبها (عند y=576 على الحد
    // 600 تفشل hit-test في بيئة الاختبار).
    // padding سفلي يحاكي الجهاز الحقيقي: يرفع الشريط السفلي عن حافة
    // الشاشة (أزراره عند y=528 تصاب — عند y=576 على الحد 600 تفشل
    // hit-test في بيئة الاختبار)
    final store = LibraryStore(
        initialBooks: [_book('e4', epubFile.path, BookFileType.epub, 1)]);

    await tester.runAsync(() async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(bottom: 48),
        ),
        child: _wrap(ReaderScreen(book: store.books.first, store: store)),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pump();

    final epubState = tester.state<EpubViewState>(find.byType(EpubView));
    // المحتوى القصير يجب أن يتجاوز الشاشة (وإلا لا معنى للتمرير)
    expect(epubState.maxScrollExtent, greaterThan(0));

    // قبل التفعيل: لا شريط سرعة
    expect(find.byType(Slider), findsNothing);

    // تفعيل التمرير التلقائي — نقر مباشر على الأيقونة (أدق من Tooltip
    // على حافة الشاشة)
    await tester.tap(find.byIcon(LucideIcons.play));
    await tester.pump();
    // إطار استقرار: Ticker يبدأ بإطار أول ثم يستقر البناء
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byIcon(LucideIcons.pause), findsOneWidget);

    // المحرك يحرّك الموضع فعلياً (خطوات صغيرة كل إطار)
    await tester.pump(const Duration(milliseconds: 600));
    expect(epubState.scrollOffset, greaterThan(0));

    // قفز إلى آخر فصل — المحرك يرى النهاية فيتوقف تلقائياً
    epubState.jumpToChapter(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('وصلت إلى نهاية الكتاب'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    // الحالة عادت "غير نشطة": أيقونة التشغيل ظهرت من جديد
    expect(find.byIcon(LucideIcons.play), findsOneWidget);

    // انتظار اختفاء SnackBar النهاية (2 ثانية + أنيميشن الخروج) —
    // كان يغطي البار ويحجب النقر على أزراره
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));

    // العودة للفصل الأول (بعيداً عن النهاية — عند النهاية ينهي المحرك
    // فوراً: سلوك صحيح، لا شيء متبقٍ للتمرير) ثم إعادة التفعيل
    epubState.jumpToChapter(1);
    await tester.pump();
    // إعادة التفعيل ثم إيقاف يدوي — Slider يختفي فوراً
    await tester.tap(find.byIcon(LucideIcons.play));
    await tester.pump();
    // إطار استقرار (نفس نمط التفعيل الأول)
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(Slider), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.pause));
    await tester.pump();
    expect(find.byType(Slider), findsNothing);
    expect(find.byIcon(LucideIcons.play), findsOneWidget);
  });

  // اختبار PDF: pdfrx يستدعي path_provider عند التهيئة — نزوّد mockاً،
  // وكل البناء داخل runAsync لأن تحميل pdfium I/O حقيقي.
  testWidgets('PDF: يعرض عدّاد الصفحات', (tester) async {
    // ignore: deprecated_member_use
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    // ignore: deprecated_member_use
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getTemporaryDirectory') return tempDir.path;
      if (call.method == 'getApplicationSupportDirectory') {
        return tempDir.path;
      }
      return null;
    });

    final store = LibraryStore(
        initialBooks: [_book('p1', pdfFile.path, BookFileType.pdf, 1)]);

    await tester.runAsync(() async {
      await tester.pumpWidget(
          _wrap(ReaderScreen(book: store.books.first, store: store)));
      // pdfium: فتح المستند + تهيئة — مهلة سخية
      await Future<void>.delayed(const Duration(seconds: 8));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // عدّاد الصفحات ظاهر بعد الجاهزية
    expect(find.textContaining('من 2'), findsOneWidget);
  });
}
