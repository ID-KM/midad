import 'package:flutter/foundation.dart';

import '../data/datasources/book_database.dart';
import '../data/models/note_model.dart';

/// مخزن ملاحظات الكتاب الحالي (4.4) — الحالة في الذاكرة مربوطة بقاعدة
/// البيانات المحلية: تحميل عند فتح القارئ، وحفظ كل تغيير لحظياً.
///
/// بلا قاعدة (اختبارات) يعمل بالذاكرة فقط — نفس نمط [LibraryStore].
class NotesStore extends ChangeNotifier {
  NotesStore({this._database, List<NoteModel>? initialNotes})
      : _notes = List.of(initialNotes ?? const []);

  final BookDatabase? _database;

  List<NoteModel> _notes;
  String? _bookId;

  /// ملاحظات الكتاب الحالي — مرتبة حسب رقم الصفحة ثم الأحدث.
  List<NoteModel> get notes => List.unmodifiable(_notes);

  /// معرّف الكتاب الحالي — null قبل فتح أي كتاب.
  String? get bookId => _bookId;

  /// يحمّل ملاحظات كتاب — يُستدعى عند فتح القارئ.
  Future<void> loadForBook(String bookId) async {
    _bookId = bookId;
    final db = _database;
    if (db != null) {
      _notes = await db.getNotesForBook(bookId);
    }
    notifyListeners();
  }

  /// إضافة ملاحظة للكتاب الحالي على الصفحة المحددة.
  Future<void> addNote({
    required int pageNumber,
    required String content,
  }) async {
    final bookId = _bookId;
    if (bookId == null || content.trim().isEmpty) return;
    final note = NoteModel(
      id: 'note_${DateTime.now().microsecondsSinceEpoch}',
      bookId: bookId,
      pageNumber: pageNumber,
      content: content.trim(),
      createdAt: DateTime.now(),
    );
    _notes.add(note);
    _sort();
    notifyListeners();
    await _database?.insertNote(note);
  }

  /// حذف ملاحظة بمعرّفها.
  Future<void> deleteNote(String id) async {
    final before = _notes.length;
    _notes.removeWhere((n) => n.id == id);
    if (_notes.length != before) {
      notifyListeners();
      await _database?.deleteNote(id);
    }
  }

  /// حذف كل ملاحظات كتاب — يُستدعى عند حذف الكتاب من المكتبة.
  Future<void> deleteForBook(String bookId) async {
    if (_bookId == bookId) {
      _notes = [];
      notifyListeners();
    }
    await _database?.deleteNotesForBook(bookId);
  }

  void _sort() {
    _notes.sort((a, b) {
      final byPage = a.pageNumber.compareTo(b.pageNumber);
      if (byPage != 0) return byPage;
      return a.createdAt.compareTo(b.createdAt);
    });
  }
}
