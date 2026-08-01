import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/archive_book.dart';

/// خدمة أرشيف الإنترنت (Archive.org) — البحث والتنزيل (Step 5).
///
/// القواعد المطبقة إلزامياً:
/// - **PDF فقط**: فلترة في الاستعلام (`format:PDF`) + اختيار ملف PDF الفعلي
///   من بيانات الـ metadata (لا نثق بفهرس البحث وحده).
/// - **NSFW**: استبعاد موضوعات حساسة في الاستعلام (`-subject:...`) +
///   فحص برمجي للكلمات المفتاحية على الحقول المرتجعة (شبكة أمان ثانية).
/// - **التحقق من الملف**: فحص magic bytes (`%PDF`) بعد التنزيل — الأرشيف
///   قد يعيد صفحة HTML برمز 200 (صفحات Cloudflare/خطأ) فيُحذف الملف الفاسد.
///
/// ⚠️ User-Agent: أرشيف الإنترنت يحجب الوكلاء غير المعروفين — نرسل
/// User-Agent متصفح حقيقي مع كل طلب (بحثاً وتنزيلاً).
class ArchiveService {
  ArchiveService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _userAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

  /// موضوعات محجوبة على مستوى الاستعلام (فلاتر archive.org).
  static const List<String> _blockedSubjects = [
    'erotica',
    'pornography',
    'porn',
    'xxx',
    'nsfw',
    'erotic',
  ];

  /// كلمات مفتاحية لحظر محتوى الكبار برمجياً (فحص على الحقول المرتجعة).
  static const List<String> _nsfwKeywords = [
    // لاتينية
    'erotica', 'erotic', 'porn', 'xxx', 'nsfw', 'nude', 'naked',
    'escort', 'sex', 'fuck',
    // عربية
    'بورن', 'إباحي', 'اباحي', 'إباحية', 'اباحية', 'بغاء',
    'عاري', 'عارية', 'جنس', 'مثير',
  ];

  static final RegExp _latinKeyword = RegExp(
    r'\b(erotica|erotic|porn|xxx|nsfw|nude|naked|escort|sex|fuck)\b',
    caseSensitive: false,
  );

  static final RegExp _htmlTag = RegExp(r'<[^>]+>');

  /// بحث في أرشيف الإنترنت — PDF فقط، محتوى الكبار محجوب.
  Future<List<ArchiveBook>> search(String query, {int rows = 20}) async {
    final filters = <String>[
      '($query)',
      'mediatype:texts',
      'format:PDF',
      ..._blockedSubjects.map((s) => '-subject:$s'),
    ];
    final url = Uri.parse(
      'https://archive.org/advancedsearch.php'
      '?q=${Uri.encodeQueryComponent(filters.join(' AND '))}'
      '&fl[]=identifier&fl[]=title&fl[]=creator&fl[]=year'
      '&fl[]=description&rows=$rows&page=1&output=json',
    );

    final response = await _get(url);
    if (response.statusCode != 200) {
      throw ArchiveException('تعذر الاتصال بالأرشيف (${response.statusCode})');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final docs = (body['response']?['docs'] as List<dynamic>?) ?? const [];
    final results = <ArchiveBook>[];
    for (final doc in docs) {
      final book = ArchiveBook(
        identifier: doc['identifier'] as String? ?? '',
        title: (doc['title'] as String? ?? '').trim(),
        creator: _firstString(doc['creator']),
        year: _firstString(doc['year']),
        description: _firstString(doc['description']),
      );
      if (book.identifier.isEmpty || book.title.isEmpty) continue;
      if (_isNsfw(book)) continue; // الفلتر البرمجي — شبكة الأمان الثانية
      results.add(book);
    }
    return results;
  }

  /// اسم ملف الـ PDF الفعلي للكتاب — الأكبر حجماً (عادة هو الكتاب نفسه،
  /// وليس نسخ OCR/نصوص مشتقة). null إذا لم يوجد PDF فعلي.
  Future<String?> fetchPdfFileName(String identifier) async {
    final url = Uri.parse('https://archive.org/metadata/$identifier');
    final response = await _get(url);
    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final files = (body['files'] as List<dynamic>?) ?? const [];
    String? best;
    int bestSize = -1;
    for (final f in files) {
      if (f is! Map<String, dynamic>) continue;
      final name = f['name'] as String? ?? '';
      if (!name.toLowerCase().endsWith('.pdf')) continue;
      // استبعد نسخ النص/النسخ المصغرة المشتقة — نبقي ملف الكتاب الرئيسي
      final lower = name.toLowerCase();
      if (lower.contains('_text.pdf') || lower.contains('_djvu')) continue;
      final size = _sizeOf(f);
      if (size > bestSize) {
        best = name;
        bestSize = size;
      }
    }
    return best;
  }

  /// تنزيل ملف PDF متدفقاً مع تتبع التقدم، ثم التحقق من magic bytes.
  /// يرمي [ArchiveException] عند أي فشل — والملف الفاسد يُحذف.
  /// إذا أرجع [isCancelled] true أثناء التنزيل يُلغى التحميل، يُحذف
  /// الملف الجزئي، ويُرمى [ArchiveCancelledException].
  Future<void> downloadPdf({
    required String identifier,
    required String pdfName,
    required String targetPath,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final uri = Uri.parse(
      'https://archive.org/download/'
      '${Uri.encodeComponent(identifier)}/${Uri.encodeComponent(pdfName)}',
    );
    final target = File(targetPath);
    await target.parent.create(recursive: true);

    final request = http.Request('GET', uri);
    request.headers['User-Agent'] = _userAgent;
    request.headers['Accept'] = 'application/pdf,*/*';

    final streamed =
        await _client.send(request).timeout(const Duration(seconds: 120));
    if (streamed.statusCode != 200) {
      throw ArchiveException(
          'فشل تحميل الملف من الأرشيف (${streamed.statusCode})');
    }

    final total = streamed.contentLength ?? 0;
    final sink = target.openWrite();
    var received = 0;
    try {
      await for (final chunk in streamed.stream) {
        // إيقاف طلب من المستخدم — نحذف الملف الجزئي وننهي
        if (isCancelled?.call() ?? false) {
          await sink.close();
          if (target.existsSync()) target.deleteSync();
          throw const ArchiveCancelledException();
        }
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) {
          onProgress((received / total).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      if (target.existsSync()) target.deleteSync();
      rethrow;
    }

    if (!await _isValidPdf(target)) {
      target.deleteSync();
      throw ArchiveException('الملف المُستلم ليس PDF صالحاً');
    }
    if (onProgress != null) onProgress(1.0);
  }

  /// تنزيل غلاف الكتاب من الأرشيف وحفظه محلياً (JPEG/PNG/GIF/WebP).
  /// يرمي [ArchiveException] عند الفشل — والملف الفاسد يُحذف.
  Future<void> downloadCover({
    required String identifier,
    required String targetPath,
  }) async {
    final uri = Uri.parse(
      'https://archive.org/services/img/'
      '${Uri.encodeComponent(identifier)}',
    );
    final target = File(targetPath);
    await target.parent.create(recursive: true);

    final request = http.Request('GET', uri);
    request.headers['User-Agent'] = _userAgent;
    request.headers['Accept'] = 'image/*';

    final streamed =
        await _client.send(request).timeout(const Duration(seconds: 60));
    if (streamed.statusCode != 200) {
      throw ArchiveException('فشل تحميل الغلاف (${streamed.statusCode})');
    }

    final sink = target.openWrite();
    try {
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      if (target.existsSync()) target.deleteSync();
      rethrow;
    }

    if (!await _isValidImage(target)) {
      target.deleteSync();
      throw const ArchiveException('الغلاف المُستلم ليس صورة صالحة');
    }
  }

  Future<http.Response> _get(Uri url) {
    return _client
        .get(url, headers: {
          'User-Agent': _userAgent,
          'Accept': 'application/json',
        })
        .timeout(const Duration(seconds: 30));
  }

  /// فحص magic bytes: %PDF (0x25 0x50 0x44 0x46).
  static Future<bool> _isValidPdf(File file) async {
    try {
      final raf = await file.open(mode: FileMode.read);
      final magic = await raf.read(4);
      await raf.close();
      return magic.length >= 4 &&
          magic[0] == 0x25 &&
          magic[1] == 0x50 &&
          magic[2] == 0x44 &&
          magic[3] == 0x46;
    } catch (_) {
      return false;
    }
  }

  /// فحص magic bytes للصور: JPEG / PNG / GIF / WebP / BMP.
  static Future<bool> _isValidImage(File file) async {
    try {
      final raf = await file.open(mode: FileMode.read);
      final magic = await raf.read(12);
      await raf.close();
      if (magic.length < 3) return false;
      final jpeg = magic[0] == 0xFF && magic[1] == 0xD8 && magic[2] == 0xFF;
      final png = magic[0] == 0x89 &&
          magic[1] == 0x50 &&
          magic[2] == 0x4E &&
          magic[3] == 0x47;
      final gif = magic[0] == 0x47 &&
          magic[1] == 0x49 &&
          magic[2] == 0x46 &&
          magic[3] == 0x38;
      final webp = magic.length >= 12 &&
          magic[0] == 0x52 &&
          magic[1] == 0x49 &&
          magic[2] == 0x46 &&
          magic[3] == 0x46 &&
          magic[8] == 0x57 &&
          magic[9] == 0x45 &&
          magic[10] == 0x42 &&
          magic[11] == 0x50;
      final bmp = magic[0] == 0x42 && magic[1] == 0x4D;
      return jpeg || png || gif || webp || bmp;
    } catch (_) {
      return false;
    }
  }

  /// الفلتر البرمجي لمحتوى الكبار — يفحص العنوان والوصف والمؤلف والمعرّف.
  static bool _isNsfw(ArchiveBook book) {
    final haystack = _stripHtml([
      book.title,
      book.description ?? '',
      book.creator ?? '',
      book.identifier,
    ].join(' \n ')).toLowerCase();
    if (_latinKeyword.hasMatch(haystack)) return true;
    for (final kw in _nsfwKeywords) {
      if (haystack.contains(kw)) return true;
    }
    return false;
  }

  /// حجم الملف من metadata — الأرشيف يعيده رقماً أحياناً ونصاً أحياناً.
  static int _sizeOf(Map<String, dynamic> file) {
    final v = file['size'];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static String _stripHtml(String text) => text.replaceAll(_htmlTag, ' ');

  static String? _firstString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is List && value.isNotEmpty) return value.first.toString();
    return null;
  }
}

/// خطأ موجه للمستخدم من خدمة الأرشيف.
class ArchiveException implements Exception {
  final String message;
  const ArchiveException(this.message);

  @override
  String toString() => message;
}

/// أُلقيت عندما يوقف المستخدم التحميل — ليست خطأً، بل إلغاء متعمد.
class ArchiveCancelledException implements Exception {
  const ArchiveCancelledException();

  @override
  String toString() => 'تم إلغاء التحميل';
}
