import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midad/data/services/epub_reader_service.dart';

/// يبني ملف EPUB صالحاً في الذاكرة — فصلان XHTML عربيان.
Uint8List buildEpubFixture() {
  const containerXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';

  const opfXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>كتاب التجربة</dc:title>
  </metadata>
  <manifest>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="img1" href="images/pic.png" media-type="image/png"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>''';

  const ch1 = '''
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>الفصل الأول</title>
<script>alert('يجب حذف هذا');</script>
<style>p { color: red; }</style>
</head>
<body>
  <h1>بداية الحكاية</h1>
  <div>
    <p>كان يا مكان في قديم الزمان &nbsp;&amp;&amp; <b>قصة</b> عربية.</p>
    <p>السطر الثاني يحتوي رقم: &#1632;&#1633; &#x6F1;&#x6F2;.</p>
  </div>
  <p>\u200Fنص بحرف اتجاه مقلوب\u200E يجب تنظيفه.</p>
</body>
</html>''';

  const ch2 = '''
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>الفصل الثاني</title></head>
<body>
  <h2>خاتمة</h2>
  <p>وانتهت الحكاية بسلام.</p>
</body>
</html>''';

  final archive = Archive()
    ..addFile(ArchiveFile('mimetype', 20, utf8.encode('application/epub+zip')))
    ..addFile(ArchiveFile('META-INF/container.xml', containerXml.length,
        utf8.encode(containerXml)))
    ..addFile(
        ArchiveFile('OEBPS/content.opf', opfXml.length, utf8.encode(opfXml)))
    ..addFile(ArchiveFile('OEBPS/ch1.xhtml', ch1.length, utf8.encode(ch1)))
    ..addFile(ArchiveFile('OEBPS/ch2.xhtml', ch2.length, utf8.encode(ch2)));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  group('EpubReaderService.parseParagraphs', () {
    test('يحذف script/style ويفك الكيانات ويرمّز الفقرات', () {
      final paras = EpubReaderService.parseParagraphs(
          '<html><head><title>عنوان</title><script>bad()</script>'
          '<style>p{}</style></head><body>'
          '<h1>ترويسة</h1><p>نص &amp; عربي &#1632;.</p>'
          '<p>\u200Fمقلوب\u200E نظيف</p></body></html>');

      expect(paras, hasLength(4));
      expect(paras[0].text, 'عنوان');
      expect(paras[0].isTitle, isTrue);
      expect(paras[1].text, 'ترويسة');
      expect(paras[1].isHeading, isTrue);
      expect(paras[1].isTitle, isTrue);
      expect(paras[2].text, 'نص & عربي ٠.');
      expect(paras[2].isHeading, isFalse);
      // علامات الاتجاه تُزال
      expect(paras[3].text, 'مقلوب نظيف');
    });

    test('لا يلتقط div الحاوية كفقرة واحدة عندما يحوي كتلاً', () {
      final paras = EpubReaderService.parseParagraphs(
          '<div><p>فقرة أولى</p><p>فقرة ثانية</p></div>');
      expect(paras, hasLength(2));
      expect(paras[0].text, 'فقرة أولى');
      expect(paras[1].text, 'فقرة ثانية');
    });

    test('br داخل الفقرة يتحول لمسافة', () {
      final paras = EpubReaderService.parseParagraphs(
          '<p>سطر أول<br/>سطر ثاني</p>');
      expect(paras.single.text, 'سطر أول سطر ثاني');
    });
  });

  group('EpubReaderService.read', () {
    test('يقرأ EPUB ويستخرج العنوان والفصول بترتيب spine', () async {
      final bytes = buildEpubFixture();
      final file = await _writeTemp(bytes);

      final doc = await EpubReaderService.read(file.path);

      expect(doc.title, 'كتاب التجربة');
      expect(doc.chapters, hasLength(2));
      expect(doc.chapters[0].title, 'الفصل الأول');
      expect(doc.chapters[1].title, 'الفصل الثاني');
      // محتوى الفصل الأول: h1 + فقرتان + فقرة نظيفة
      expect(doc.chapters[0].paragraphs.map((p) => p.text),
          contains('بداية الحكاية'));
      expect(doc.chapters[0].paragraphs.map((p) => p.text),
          contains('كان يا مكان في قديم الزمان && قصة عربية.'));
    });

    test('يرمي خطأً عند ملف تالف بلا spine', () async {
      final dir = await _tempDir();
      final bad = '${dir.path}/bad.epub';
      await File(bad).writeAsBytes([0x50, 0x4B, 0x03, 0x04]); // zip ناقص
      expect(
        () => EpubReaderService.read(bad),
        throwsA(anything),
      );
    });
  });
}

// ——— أدوات مساعدة ———

Future<File> _writeTemp(Uint8List bytes) async {
  final dir = await _tempDir();
  final file = File('${dir.path}/fixture.epub');
  await file.writeAsBytes(bytes);
  return file;
}

Future<Directory> _tempDir() async {
  final dir = await Directory.systemTemp.createTemp('midad_epub_test_');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}
