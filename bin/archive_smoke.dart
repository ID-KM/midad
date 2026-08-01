// فحص حي لخدمة الأرشيف (Step 5) — تشغيل: dart run bin/archive_smoke.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:midad/data/services/archive_service.dart';

Future<void> main() async {
  final service = ArchiveService();

  print('== 1) بحث عربي PDF فقط ==');
  final results = await service.search('رياض الصالحين', rows: 3);
  for (final b in results) {
    print('  - ${b.title} [${b.identifier}] (${b.subtitle})');
  }
  if (results.isEmpty) {
    print('لا نتائج — توقف');
    return;
  }

  print('== 2) جلب ملف PDF الفعلي ==');
  final id = results.first.identifier;
  final pdfName = await service.fetchPdfFileName(id);
  print('  identifier=$id -> pdf=$pdfName');
  if (pdfName == null) return;

  print('== 3) تنزيل (أول 100KB فقط عبر تحقق سريع) ==');
  final target = '${Directory.systemTemp.path}/midad_smoke.pdf';
  double last = 0;
  await service.downloadPdf(
    identifier: id,
    pdfName: pdfName,
    targetPath: target,
    onProgress: (p) => last = p,
  );
  final size = await File(target).length();
  print('  ok: size=$size bytes, lastProgress=$last');
  File(target).deleteSync();
  print('== نجح ==');
}
