import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

import '../models/book_model.dart';

/// محرك أغلفة الكتب — Step 3 (مُصلَّح).
///
/// الترتيب: استخراج الغلاف من الملف نفسه (PDF: الصفحة الأولى عبر pdfrx —
/// نفس مكتبة العارض فلا صراع pdfium؛ EPUB: صورة الغلاف من المحتوى بثلاث
/// طرق fallback) ← إن تعذّر، توليد غلاف افتراضي بني/أصفر.
/// النتيجة دائماً مسار ملف صورة محفوظ في `coverDir`.
abstract final class BookCoverService {
  /// يضمن وجود غلاف لكتاب — يرجع مسار صورة موجودة دائماً.
  static Future<String> ensureCover({
    required String filePath,
    required BookFileType fileType,
    required String bookId,
    required String coverDir,
    required String title,
  }) async {
    String? cover;
    try {
      cover = fileType == BookFileType.epub
          ? await _extractEpubCover(filePath, bookId, coverDir)
          : await _extractPdfCover(filePath, bookId, coverDir);
    } catch (e) {
      debugPrint('⚠️ فشل استخراج غلاف: $e');
    }
    cover ??= await generateDefaultCover(
      title: title,
      destPath: '$coverDir/$bookId.png',
    );
    return cover;
  }

  // ——— PDF: الصفحة الأولى ———

  /// يستخرج الصفحة الأولى كـ PNG. الطريق الأول: poppler (pdftoppm) —
  /// أداة النظام، سريعة ومستقرة ولا تعتمد على محرك Flutter. عند تعذّرها
  /// (منصة بلا poppler) ننتقل لـ pdfrx كـ fallback برمجي.
  static Future<String?> _extractPdfCover(
    String filePath,
    String bookId,
    String coverDir,
  ) async {
    try {
      return await _extractPdfCoverViaPoppler(filePath, bookId, coverDir);
    } catch (e) {
      debugPrint('⚠️ تعذّر الاستخراج عبر pdftoppm: $e');
    }
    return _extractPdfCoverViaPdfrx(filePath, bookId, coverDir);
  }

  /// poppler: `pdftoppm -f 1 -l 1 -png -scale-to-x 600` → ملف واحد بعرض 600px.
  static Future<String> _extractPdfCoverViaPoppler(
    String filePath,
    String bookId,
    String coverDir,
  ) async {
    await Directory(coverDir).create(recursive: true);
    final base = '$coverDir/$bookId';
    final result = await Process.run('pdftoppm', [
      '-f', '1', '-l', '1',
      '-png',
      '-scale-to-x', '600',
      '-singlefile',
      filePath,
      base,
    ]);
    if (result.exitCode != 0) {
      throw Exception('pdftoppm خرج برمز ${result.exitCode}: ${result.stderr}');
    }
    // مع -singlefile ينتج pdftoppm ملفاً باسم {prefix}.png (بلا -1)
    final produced = File('$base.png');
    if (!produced.existsSync()) {
      throw Exception('pdftoppm لم ينتج صورة');
    }
    // توحيد الاسم: bookId.png
    final finalPath = '$coverDir/$bookId.png';
    await produced.rename(finalPath);
    return finalPath;
  }

  /// pdfrx: رسم الصفحة الأولى برمجياً — يعمل حيث لا تتوفر poppler.
  static Future<String?> _extractPdfCoverViaPdfrx(
    String filePath,
    String bookId,
    String coverDir,
  ) async {
    final doc = await PdfDocument.openFile(filePath);
    try {
      if (doc.pages.isEmpty) return null;
      final page = await doc.pages.first.ensureLoaded();
      // غلاف بعرض ~600px مع الحفاظ على نسبة أبعاد الصفحة.
      const targetWidth = 600.0;
      final scale = targetWidth / page.width;
      final w = (page.width * scale).round().clamp(1, 4096);
      final h = (page.height * scale).round().clamp(1, 4096);
      final image = await page.render(
        width: w,
        height: h,
        backgroundColor: 0xffffffff,
      );
      try {
        if (image == null) return null;
        // pdfrx ينتج BGRA8888 — تحويل إلى PNG عبر حزمة image.
        final decoded = img.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: image.pixels.buffer,
          order: img.ChannelOrder.bgra,
        );
        final png = img.encodePng(decoded);
        return await _writePng(png, '$coverDir/$bookId.png');
      } finally {
        image?.dispose();
      }
    } finally {
      await doc.dispose();
    }
  }

  // ——— EPUB: صورة الغلاف من OPF ———

  static Future<String?> _extractEpubCover(
    String filePath,
    String bookId,
    String coverDir,
  ) async {
    final bytes = await File(filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // container.xml → مسار OPF
    final container = archive.findFile('META-INF/container.xml');
    if (container == null) return null;
    final containerXml =
        XmlDocument.parse(utf8.decode(container.content as List<int>));
    String? opfPath;
    for (final rootfile in containerXml.findAllElements('rootfile')) {
      opfPath = rootfile.getAttribute('full-path');
      if (opfPath != null) break;
    }
    if (opfPath == null) return null;

    // OPF → manifest
    final opf = archive.findFile(opfPath);
    if (opf == null) return null;
    final opfXml = XmlDocument.parse(utf8.decode(opf.content as List<int>));
    final items = opfXml.findAllElements('item').toList();

    // الطريقة 1: properties="cover-image" أو id يحوي cover
    String? coverHref;
    for (final item in items) {
      final properties = item.getAttribute('properties') ?? '';
      final id = item.getAttribute('id') ?? '';
      if (properties.contains('cover-image') ||
          id.toLowerCase().contains('cover')) {
        coverHref = item.getAttribute('href');
        break;
      }
    }

    // الطريقة 2: <meta name="cover" content="معرّف-العنصر"/>
    if (coverHref == null) {
      for (final meta in opfXml.findAllElements('meta')) {
        if ((meta.getAttribute('name') ?? '').toLowerCase() == 'cover') {
          final refId = meta.getAttribute('content');
          if (refId != null) {
            for (final item in items) {
              if (item.getAttribute('id') == refId) {
                coverHref = item.getAttribute('href');
                break;
              }
            }
          }
          if (coverHref != null) break;
        }
      }
    }

    // الطريقة 3: أول عنصر صورة في manifest (fallback أخير)
    if (coverHref == null) {
      for (final item in items) {
        final mediaType = item.getAttribute('media-type') ?? '';
        if (mediaType.startsWith('image/')) {
          coverHref = item.getAttribute('href');
          break;
        }
      }
    }

    if (coverHref == null) return null;

    // المسار نسبي لدليل OPF
    final coverPath = p.normalize(p.join(p.dirname(opfPath), coverHref));
    final coverFile = archive.findFile(coverPath);
    if (coverFile == null || !coverFile.isFile) return null;

    final ext = p.extension(coverHref).toLowerCase();
    final destName = '$bookId${ext.isEmpty ? '.img' : ext}';
    final destFile = File('$coverDir/$destName');
    await destFile.parent.create(recursive: true);
    await destFile.writeAsBytes(coverFile.content as List<int>);
    return destFile.path;
  }

  // ——— الغلاف الافتراضي: بني/أصفر ———

  /// يرسم غلافاً بني/أصفر (متدرج بني + إطار أصفر + أيقونة كتاب + العنوان)
  /// ويحفظه PNG — يعمل حتى عند تعذّر استخراج أي صورة.
  static Future<String> generateDefaultCover({
    required String title,
    required String destPath,
  }) async {
    const width = 600.0;
    const height = 900.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // خلفية متدرجة: بني فاتح ← بني داكن
    final bg = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(width, height),
        const [Color(0xFF8B5A2B), Color(0xFF3E2723)],
      );
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), bg);

    // إطار أصفر دافئ
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..color = const Color(0xFFF5D061);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(28, 28, width - 56, height - 56),
        const Radius.circular(14),
      ),
      frame,
    );

    // أيقونة كتاب مفتوح (شكل مستطيل بقسمين + عمود فقري)
    final bookBody = Paint()
      ..color = const Color(0xFFF5D061).withValues(alpha: 0.9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(235, 290, 130, 180),
        const Radius.circular(10),
      ),
      bookBody,
    );
    final spine = Paint()
      ..color = const Color(0xFF3E2723).withValues(alpha: 0.55)
      ..strokeWidth = 4;
    canvas.drawLine(const Offset(300, 300), const Offset(300, 460), spine);

    // سطور النص داخل الكتاب
    final lines = Paint()
      ..color = const Color(0xFF3E2723).withValues(alpha: 0.3)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final y = 340.0 + i * 30;
      canvas.drawLine(Offset(258, y), Offset(292, y), lines);
      canvas.drawLine(Offset(308, y), Offset(342, y), lines);
    }

    // عنوان الكتاب (عربي RTL)
    final textPainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(
          color: Color(0xFFFDFBF7),
          fontSize: 44,
          fontWeight: FontWeight.bold,
          height: 1.35,
        ),
      ),
      textDirection: ui.TextDirection.rtl,
      textAlign: ui.TextAlign.center,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: width - 140);
    textPainter.paint(
      canvas,
      Offset((width - textPainter.width) / 2, 540),
    );

    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    uiImage.dispose();
    picture.dispose();

    return _writePng(byteData!.buffer.asUint8List(), destPath);
  }

  static Future<String> _writePng(List<int> png, String destPath) async {
    final file = File(destPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png);
    return file.path;
  }
}
