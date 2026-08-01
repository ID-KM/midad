/// نموذج الكتاب — حسب مواصفات PRD حرفياً.
enum BookFileType { pdf, epub }

class BookModel {
  final String id;
  final String title;
  final String filePath;
  final BookFileType fileType;
  final String? coverPath;
  final int currentPage;
  final int totalPages;
  final double progressPercentage;
  final bool isFavorite;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime lastReadAt;

  const BookModel({
    required this.id,
    required this.title,
    required this.filePath,
    required this.fileType,
    this.coverPath,
    required this.currentPage,
    required this.totalPages,
    required this.progressPercentage,
    required this.isFavorite,
    required this.isPinned,
    required this.createdAt,
    required this.lastReadAt,
  });

  /// نسخة معدّلة من الكتاب — الحالة في الذاكرة تُحدَّث بلا تغيير الأصل.
  BookModel copyWith({
    String? coverPath,
    int? currentPage,
    int? totalPages,
    double? progressPercentage,
    bool? isFavorite,
    bool? isPinned,
    DateTime? lastReadAt,
  }) {
    return BookModel(
      id: id,
      title: title,
      filePath: filePath,
      fileType: fileType,
      coverPath: coverPath ?? this.coverPath,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      progressPercentage: progressPercentage ?? this.progressPercentage,
      isFavorite: isFavorite ?? this.isFavorite,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
    );
  }
}
