import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:midad/data/models/book_model.dart';
import 'package:midad/data/services/book_cover_service.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// PNG صغير حقيقي (2×2) لتوظيفه كغلاف داخل EPUB.
Uint8List _tinyPng() {
  final image = img.Image(width: 2, height: 2);
  img.fill(image, color: img.ColorRgb8(0x8B, 0x5A, 0x2B));
  return Uint8List.fromList(img.encodePng(image));
}

/// EPUB بغلاف معرّف عبر properties="cover-image".
Uint8List _epubWithCoverProperty() {
  final png = _tinyPng();
  const containerXml =
      '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
      'version="1.0"><rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';
  const opfXml =
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>كتاب بغلاف</dc:title></metadata>'
      '<manifest>'
      '<item id="cover-img" href="cover.png" media-type="image/png" properties="cover-image"/>'
      '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest>'
      '<spine><itemref idref="c1"/></spine></package>';
  const c1 =
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>أول</title></head>'
      '<body><p>نص</p></body></html>';

  final archive = Archive()
    ..addFile(ArchiveFile('mimetype', 20, utf8.encode('application/epub+zip')))
    ..addFile(ArchiveFile('META-INF/container.xml', containerXml.length,
        utf8.encode(containerXml)))
    ..addFile(
        ArchiveFile('OEBPS/content.opf', opfXml.length, utf8.encode(opfXml)))
    ..addFile(ArchiveFile('OEBPS/cover.png', png.length, png))
    ..addFile(ArchiveFile('OEBPS/c1.xhtml', c1.length, utf8.encode(c1)));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// EPUB بغلاف معرّف عبر <meta name="cover" content="..."/> (طريقة EPUB2).
Uint8List _epubWithMetaCover() {
  const containerXml =
      '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
      'version="1.0"><rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';
  const opfXml =
      '<package xmlns="http://www.idpf.org/2007/opf" version="2.0">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>كتاب بغلاف قديم</dc:title>'
      '<meta name="cover" content="cov"/>'
      '</metadata>'
      '<manifest>'
      '<item id="cov" href="images/cov.jpg" media-type="image/jpeg"/>'
      '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest>'
      '<spine><itemref idref="c1"/></spine></package>';
  const c1 =
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>أول</title></head>'
      '<body><p>نص</p></body></html>';
  // JPEG توقيع فقط (لا يُفكك — نتحقق من الحفظ)
  final jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x00];

  final archive = Archive()
    ..addFile(ArchiveFile('mimetype', 20, utf8.encode('application/epub+zip')))
    ..addFile(ArchiveFile('META-INF/container.xml', containerXml.length,
        utf8.encode(containerXml)))
    ..addFile(
        ArchiveFile('OEBPS/content.opf', opfXml.length, utf8.encode(opfXml)))
    ..addFile(ArchiveFile('OEBPS/images/cov.jpg', jpeg.length, jpeg))
    ..addFile(ArchiveFile('OEBPS/c1.xhtml', c1.length, utf8.encode(c1)));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// EPUB بلا أي غلاف (فصل واحد فقط).
Uint8List _epubWithoutCover() {
  const containerXml =
      '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
      'version="1.0"><rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';
  const opfXml =
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>كتاب بلا غلاف</dc:title></metadata>'
      '<manifest>'
      '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest>'
      '<spine><itemref idref="c1"/></spine></package>';
  const c1 =
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>أول</title></head>'
      '<body><p>نص</p></body></html>';

  final archive = Archive()
    ..addFile(ArchiveFile('mimetype', 20, utf8.encode('application/epub+zip')))
    ..addFile(ArchiveFile('META-INF/container.xml', containerXml.length,
        utf8.encode(containerXml)))
    ..addFile(
        ArchiveFile('OEBPS/content.opf', opfXml.length, utf8.encode(opfXml)))
    ..addFile(ArchiveFile('OEBPS/c1.xhtml', c1.length, utf8.encode(c1)));
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

bool _isPng(File f) {
  final bytes = f.readAsBytesSync();
  return bytes.length > 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47;
}

void main() {
  late Directory tempDir;
  late Directory coverDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('midad_cover_test_');
    coverDir = Directory('${tempDir.path}/covers');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('BookCoverService.ensureCover', () {
    // ملاحظة منهجية: I/O حقيقي (قراءة/كتابة ملفات، Process خارجي) يعمل
    // داخل test() العادي لكنه يعلّق داخل testWidgets (الزمن الوهمي).
    test('EPUB بغلاف properties: يستخرج الصورة ويحفظها', () async {
      final epub = File('${tempDir.path}/with_cover.epub');
      await epub.writeAsBytes(_epubWithCoverProperty());

      final path = await BookCoverService.ensureCover(
        filePath: epub.path,
        fileType: BookFileType.epub,
        bookId: 'b1',
        coverDir: coverDir.path,
        title: 'كتاب بغلاف',
      );
      expect(path, isNotNull);
      expect(path, contains('b1.png'));
      expect(_isPng(File(path)), isTrue);
    });

    test('EPUB بغلاف meta (EPUB2): الطريقة الثانية تنجح', () async {
      final epub = File('${tempDir.path}/meta_cover.epub');
      await epub.writeAsBytes(_epubWithMetaCover());

      final path = await BookCoverService.ensureCover(
        filePath: epub.path,
        fileType: BookFileType.epub,
        bookId: 'b2',
        coverDir: coverDir.path,
        title: 'كتاب بغلاف قديم',
      );
      expect(path, isNotNull);
      expect(path, contains('b2.jpg'));
      final bytes = File(path).readAsBytesSync();
      expect(bytes[0], 0xFF);
      expect(bytes[1], 0xD8); // توقيع JPEG
    });

    test('EPUB بلا غلاف: يولد الغلاف الافتراضي البني/الأصفر', () async {
      final epub = File('${tempDir.path}/no_cover.epub');
      await epub.writeAsBytes(_epubWithoutCover());

      final path = await BookCoverService.ensureCover(
        filePath: epub.path,
        fileType: BookFileType.epub,
        bookId: 'b3',
        coverDir: coverDir.path,
        title: 'كتاب بلا غلاف',
      );
      expect(path, isNotNull);
      expect(_isPng(File(path)), isTrue);
    });

    test('PDF: يستخرج الصفحة الأولى كـ PNG عبر pdftoppm', () async {
      final pdf = File('${tempDir.path}/book.pdf');
      await pdf.writeAsBytes(await _pdfFixture());

      final path = await BookCoverService.ensureCover(
        filePath: pdf.path,
        fileType: BookFileType.pdf,
        bookId: 'b4',
        coverDir: coverDir.path,
        title: 'كتاب PDF',
      );
      expect(path, isNotNull);
      expect(_isPng(File(path)), isTrue);
      // عبر poppler: الصورة تُنتج بأبعاد عرض 600
      final decoded = img.decodePng(File(path).readAsBytesSync());
      expect(decoded, isNotNull);
      expect(decoded!.width, 600);
    });

    test('ملف EPUB تالف: غلاف افتراضي دون انهيار', () async {
      // ملف EPUB بلا container.xml — يفشل الاستخراج من أول خطوة
      final bad = File('${tempDir.path}/bad.epub');
      await bad.writeAsBytes([0x50, 0x4B, 0x03, 0x04]); // zip ناقص

      final path = await BookCoverService.ensureCover(
        filePath: bad.path,
        fileType: BookFileType.epub,
        bookId: 'b5',
        coverDir: coverDir.path,
        title: 'تالف',
      );
      expect(path, isNotNull);
      expect(_isPng(File(path)), isTrue);
    });
  });

  group('BookCoverService.generateDefaultCover', () {
    // الرسم عبر ui.PictureRecorder يحتاج محرك Flutter → testWidgets.
    testWidgets('يرسم غلافاً بني/أصفر PNG صالحاً', (tester) async {
      await tester.runAsync(() async {
        final path = await BookCoverService.generateDefaultCover(
          title: 'موسوعة العصر',
          destPath: '${coverDir.path}/default.png',
        );
        final f = File(path);
        expect(f.existsSync(), isTrue);
        expect(_isPng(f), isTrue);
        // فك الترميز والتحقق من أبعاد الغلاف 600×900
        final decoded = img.decodePng(f.readAsBytesSync());
        expect(decoded, isNotNull);
        expect(decoded!.width, 600);
        expect(decoded.height, 900);
      });
    });
  });
}
