package com.midad.reader

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "midad/media_store",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> {
                    val srcPath = call.argument<String>("srcPath")
                    val fileName = call.argument<String>("fileName")
                    val mimeType = call.argument<String>("mimeType")
                    if (srcPath == null || fileName == null) {
                        result.error("BAD_ARGS", "معلومات غير مكتملة", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val saved = saveToDownloads(srcPath, fileName, mimeType ?: "application/pdf")
                        if (saved == null) {
                            result.error("SAVE_FAILED", "فشل الحفظ في مجلد التنزيلات", null)
                        } else {
                            result.success(saved)
                        }
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message ?: "خطأ غير معروف", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /// ينقل ملفاً من التخزين الخاص إلى Download/مداد عبر MediaStore —
    /// يظهر في مدير الملفات. يعيد المسار الفعلي للملف، أو null عند الفشل.
    private fun saveToDownloads(srcPath: String, fileName: String, mimeType: String): String? {
        // MediaStore.RELATIVE_PATH متاح من أندرويد 10 (Q) فقط
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null

        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/مداد")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri: Uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: return null

        try {
            resolver.openOutputStream(uri)?.use { out ->
                FileInputStream(File(srcPath)).use { it.copyTo(out) }
            } ?: return null
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }

        // إنهاء الإضافة — الملف أصبح مرئياً
        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(uri, values, null, null)

        return realPath(uri, fileName)
    }

    /// يحوّل uri من MediaStore إلى مسار فعلي قابل للفتح من التطبيق.
    private fun realPath(uri: Uri, fallbackName: String): String? {
        val projection = arrayOf(
            MediaStore.Downloads.DISPLAY_NAME,
            MediaStore.Downloads.RELATIVE_PATH,
        )
        contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val name = cursor.getString(0) ?: fallbackName
                val relative = cursor.getString(1)
                    ?: Environment.DIRECTORY_DOWNLOADS + "/"
                val base = Environment.getExternalStorageDirectory()?.absolutePath ?: return null
                return "$base/$relative$name"
            }
        }
        return null
    }
}
