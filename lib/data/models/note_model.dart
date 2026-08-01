/// نموذج الملاحظة — حسب مواصفات PRD حرفياً (4.4).
class NoteModel {
  final String id;
  final String bookId;
  final int pageNumber;
  final String content;
  final DateTime createdAt;

  const NoteModel({
    required this.id,
    required this.bookId,
    required this.pageNumber,
    required this.content,
    required this.createdAt,
  });

  NoteModel copyWith({String? content, int? pageNumber}) {
    return NoteModel(
      id: id,
      bookId: bookId,
      pageNumber: pageNumber ?? this.pageNumber,
      content: content ?? this.content,
      createdAt: createdAt,
    );
  }
}
