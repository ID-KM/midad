import 'package:flutter/services.dart';

/// ينقل الملفات إلى مجلد عام يظهر في مدير الملفات (Download/مداد)
/// عبر MediaStore — يعمل على أندرويد 10+ بدون أي أذونات إضافية.
class MediaStoreHelper {
  static const _channel = MethodChannel('midad/media_store');

  /// ينقل ملفاً من التخزين الخاص إلى Download/مداد ويعيد المسار العام.
  /// يرمي استثناء عند الفشل (جهاز قديم/خطأ نظام).
  static Future<String> saveToDownloads({
    required String srcPath,
    required String fileName,
    String mimeType = 'application/pdf',
  }) async {
    final path = await _channel.invokeMethod<String>('saveToDownloads', {
      'srcPath': srcPath,
      'fileName': fileName,
      'mimeType': mimeType,
    });
    if (path == null || path.isEmpty) {
      throw Exception('تعذر الحفظ في مجلد التنزيلات');
    }
    return path;
  }
}
