import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../models/book_model.dart';

/// استيراد الكتب المحلية — Step 3.
///
/// المسار: اختيار ملف PDF/EPUB عبر file_picker ← نسخه إلى المساحة
/// الداخلية للتطبيق (`getApplicationSupportDirectory()/books/`) ←
/// بناء [BookModel] جاهز للإضافة إلى المكتبة.
abstract final class BookImportService {
  /// يفتح حوار اختيار الملفات (PDF/EPUB) — متعدد الاختيار.
  /// يرجع null عند إلغاء المستخدم.
  static Future<List<File>?> pickBookFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'epub'],
      allowMultiple: true,
    );
    if (result == null) return null;
    return result.files
        .map((f) => f.path)
        .whereType<String>()
        .map(File.new)
        .toList();
  }

  /// عنوان الكتاب من اسم الملف (بدون الامتداد) — يحافظ على العربية.
  static String titleFromFile(File file) {
    final name = file.path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// نوع الكتاب من الامتداد — كل ما ليس epub يُعامل كـ pdf.
  static BookFileType typeFromFile(File file) {
    final ext = file.path.split('.').last.toLowerCase();
    return ext == 'epub' ? BookFileType.epub : BookFileType.pdf;
  }

  /// اسم ملف آمن للمساحة الداخلية — يُزيل محارف المسارات فقط
  /// ولا يمس العربية (لا تستخدم `\w` فهو ASCII في Dart).
  static String safeFileName(String title) {
    final cleaned =
        title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').replaceAll('\x00', '');
    return cleaned.trim().isEmpty ? 'book' : cleaned.trim();
  }

  /// ينسخ الملف إلى [libraryDir] ويبني نموذج الكتاب.
  /// يرمي [FileSystemException] عند فشل النسخ.
  static Future<BookModel> importFile(
    File source, {
    required String libraryDir,
  }) async {
    final title = titleFromFile(source);
    final type = typeFromFile(source);
    final ext = type == BookFileType.epub ? 'epub' : 'pdf';

    final dest = File('$libraryDir/${safeFileName(title)}.$ext');
    await dest.parent.create(recursive: true);
    await source.copy(dest.path);

    final now = DateTime.now();
    return BookModel(
      id: now.microsecondsSinceEpoch.toString(),
      title: title,
      filePath: dest.path,
      fileType: type,
      currentPage: 0,
      totalPages: 0,
      progressPercentage: 0,
      isFavorite: false,
      isPinned: false,
      createdAt: now,
      lastReadAt: now,
    );
  }
}
