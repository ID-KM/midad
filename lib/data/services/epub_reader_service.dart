import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// فقرة جاهزة للعرض — تُستخرج من XHTML الفصل مع تصنيف تنسيقها.
class EpubParagraph {
  final String text;
  final bool isHeading;
  final bool isTitle;

  const EpubParagraph({
    required this.text,
    required this.isHeading,
    required this.isTitle,
  });
}

/// فصل واحد من الكتاب — عنوان + فقراته.
class EpubChapter {
  final String title;
  final List<EpubParagraph> paragraphs;

  const EpubChapter({required this.title, required this.paragraphs});
}

/// كتاب EPUB محلَّل — عنوان + فصول مرتبة حسب spine.
class EpubDocument {
  final String title;
  final List<EpubChapter> chapters;

  const EpubDocument({required this.title, required this.chapters});
}

/// محرك تحليل EPUB — Step 4.
///
/// المسار: `META-INF/container.xml` ← مسار OPF ← `manifest` (id→href)
/// ← `spine` (ترتيب الفصول) ← تحميل كل XHTML وتحويله لفقرات.
/// نفس نمط التحليل المستخدم في [BookCoverService] — بلا مكتبات خارجية.
abstract final class EpubReaderService {
  /// يقرأ ملف EPUB ويعيد الفصول بترتيب القراءة.
  /// يرمي استثناءً عند ملف تالف أو بلا spine صالح.
  static Future<EpubDocument> read(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // container.xml → مسار OPF
    final container = archive.findFile('META-INF/container.xml');
    if (container == null) {
      throw const FormatException('EPUB تالف: لا يوجد META-INF/container.xml');
    }
    final containerXml =
        XmlDocument.parse(utf8.decode(container.content as List<int>));
    String? opfPath;
    for (final rootfile in containerXml.findAllElements('rootfile')) {
      opfPath = rootfile.getAttribute('full-path');
      if (opfPath != null) break;
    }
    if (opfPath == null) {
      throw const FormatException('EPUB تالف: container.xml بلا rootfile');
    }

    // OPF → manifest + spine
    final opf = archive.findFile(opfPath);
    if (opf == null) {
      throw FormatException('EPUB تالف: ملف OPF غير موجود ($opfPath)');
    }
    final opfXml = XmlDocument.parse(utf8.decode(opf.content as List<int>));

    final manifest = <String, ({String href, String mediaType})>{};
    for (final item in opfXml.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = (
        href: href,
        mediaType: item.getAttribute('media-type') ?? '',
      );
    }

    final spineIds = <String>[];
    for (final itemref in opfXml.findAllElements('itemref')) {
      final idref = itemref.getAttribute('idref');
      if (idref != null) spineIds.add(idref);
    }
    if (spineIds.isEmpty) {
      throw const FormatException('EPUB تالف: spine فارغ');
    }

    // عنوان الكتاب من OPF
    var bookTitle = 'بدون عنوان';
    for (final title in opfXml.findAllElements('dc:title')) {
      final text = title.innerText.trim();
      if (text.isNotEmpty) {
        bookTitle = text;
        break;
      }
    }

    // الفصول: كل spine idref → ملف XHTML
    final chapters = <EpubChapter>[];
    for (var i = 0; i < spineIds.length; i++) {
      final entry = manifest[spineIds[i]];
      if (entry == null) continue;

      final lower = entry.mediaType.toLowerCase();
      final isHtml = lower.contains('html') || lower.contains('xml') ||
          p.extension(entry.href).toLowerCase() == '.xhtml';
      if (!isHtml) continue; // صور/خطوط/ملفات وسائط — ليست فصولاً

      final hrefPath = p.normalize(p.join(p.dirname(opfPath), entry.href));
      final file = archive.findFile(hrefPath);
      if (file == null || !file.isFile) continue;

      final html = utf8.decode(file.content as List<int>);
      final paragraphs = parseParagraphs(html);

      // عنوان الفصل: أول <title> أو h1 في المحتوى، وإلا «فصل N»
      var chapterTitle = 'فصل ${i + 1}';
      for (final para in paragraphs) {
        if (para.isTitle) {
          chapterTitle = para.text;
          break;
        }
      }
      chapters.add(EpubChapter(title: chapterTitle, paragraphs: paragraphs));
    }
    if (chapters.isEmpty) {
      throw const FormatException('EPUB تالف: لا توجد فصول XHTML قابلة للقراءة');
    }

    return EpubDocument(title: bookTitle, chapters: chapters);
  }

  /// يحوّل XHTML فصل إلى فقرات مع تصنيف (عنوان/ترويسة/نص).
  static List<EpubParagraph> parseParagraphs(String html) {
    // إزالة السكربتات والأنماط أولاً
    var cleaned = html
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '');
    return _parseBlocks(cleaned);
  }

  static final RegExp _blockRe = RegExp(
    r'<(h[1-6]|p|div|li|blockquote|title|dt|dd)[^>]*>(.*?)</\1>',
    dotAll: true,
    caseSensitive: false,
  );

  static List<EpubParagraph> _parseBlocks(String html) {
    final result = <EpubParagraph>[];
    var lastEnd = 0;
    for (final m in _blockRe.allMatches(html)) {
      if (m.start < lastEnd) continue; // تداخل — تخطَّ (الأعمق يُلتقط بالتكرير)
      final tag = m.group(1)!.toLowerCase();
      final inner = m.group(2)!;

      // div حاوية تحتوي كتلاً أخرى → حلّل داخلها بدل التقاطها كفقرة واحدة
      if (tag == 'div' && _blockRe.hasMatch(inner)) {
        result.addAll(_parseBlocks(inner));
        lastEnd = m.end;
        continue;
      }

      final text = _stripInnerTags(inner);
      if (text.isEmpty) {
        lastEnd = m.end;
        continue;
      }
      result.add(EpubParagraph(
        text: text,
        isHeading: tag == 'h1' || tag == 'h2' || tag == 'h3',
        isTitle: tag == 'title' || tag == 'h1',
      ));
      lastEnd = m.end;
    }
    return result;
  }

  static String _stripInnerTags(String s) {
    var t = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ');
    t = t.replaceAll(RegExp(r'<[^>]*>'), '');
    t = _decodeEntities(t);
    // علامات اتجاه (RTL/LTR embedding) تكسر عرض Flutter — تُزال
    t = t.replaceAll(RegExp(r'[\u200E\u200F\u202A-\u202E\u2066-\u2069]'), '');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// فك الكيانات HTML الشائعة + الرقمية (عشري/سداسي عشر).
  static String _decodeEntities(String s) {
    var t = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#160;', ' ');
    t = t.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    );
    t = t.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (m) => String.fromCharCode(int.parse(m.group(1)!)),
    );
    return t;
  }
}
