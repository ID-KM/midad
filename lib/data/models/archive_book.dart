/// نتيجة بحث من أرشيف الإنترنت (Archive.org) — Step 5.
class ArchiveBook {
  final String identifier;
  final String title;
  final String? creator;
  final String? year;
  final String? description;

  const ArchiveBook({
    required this.identifier,
    required this.title,
    this.creator,
    this.year,
    this.description,
  });

  /// يعرّف المؤلفين/السنين كسطر واحد «المؤلف · سنة».
  String get subtitle {
    final parts = <String>[
      if (creator != null && creator!.isNotEmpty) creator!,
      if (year != null && year!.isNotEmpty) year!,
    ];
    return parts.join(' · ');
  }

  /// رابط غلاف الكتاب من أرشيف الإنترنت — endpoint الأغلفة الرسمي
  /// يعيد صورة مصغرة (~180px) من المعرّف مباشرة بلا استدعاء إضافي.
  String get coverUrl =>
      'https://archive.org/services/img/$identifier';
}
