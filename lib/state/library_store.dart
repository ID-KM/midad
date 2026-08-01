import 'package:flutter/foundation.dart';

import '../data/datasources/book_database.dart';
import '../data/models/book_model.dart';

/// مخزن المكتبة — الحالة في الذاكرة (Step 2) مربوطة بقاعدة البيانات
/// المحلية (Step 3): تحميل عند الإقلاع، وحفظ كل تغيير لحظياً.
class LibraryStore extends ChangeNotifier {
  LibraryStore({List<BookModel>? initialBooks, this._database})
      : _books = List.of(initialBooks ?? const []);

  final List<BookModel> _books;
  final BookDatabase? _database;

  List<BookModel> get books => List.unmodifiable(_books);

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  bool get isSearching => _searchQuery.trim().isNotEmpty;

  /// يحمّل المكتبة من القاعدة — يُستدعى مرة واحدة عند إقلاع التطبيق.
  Future<void> loadFromDatabase() async {
    if (_database == null) return;
    _books
      ..clear()
      ..addAll(await _database.getAllBooks());
    notifyListeners();
  }

  /// الكتب المرتبة: المثبتة أولاً، ثم حسب آخر قراءة.
  List<BookModel> get sortedBooks {
    final list = [..._books]..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.lastReadAt.compareTo(a.lastReadAt);
      });
    return list;
  }

  /// نتائج البحث الحالية — كل الكتب عند غياب الاستعلام.
  List<BookModel> get filteredBooks {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return sortedBooks;
    return sortedBooks
        .where((b) => b.title.toLowerCase().contains(query))
        .toList();
  }

  /// الكتب المفضلة لتبويب المفضلة.
  List<BookModel> get favoriteBooks =>
      _books.where((b) => b.isFavorite).toList();

  /// البحث عن كتاب بمعرّفه — null عند عدم الوجود.
  BookModel? bookById(String id) {
    for (final book in _books) {
      if (book.id == id) return book;
    }
    return null;
  }

  /// إضافة كتاب (أو استبداله إن وُجد بنفس المعرّف) + حفظ في القاعدة.
  Future<void> addBook(BookModel book) async {
    final index = _books.indexWhere((b) => b.id == book.id);
    if (index >= 0) {
      _books[index] = book;
    } else {
      _books.add(book);
    }
    notifyListeners();
    await _database?.insertBook(book);
  }

  /// إضافة كتاب مُنزَّل من الأرشيف (Step 5) — يرفض التكرار حسب العنوان.
  /// يعيد false إذا كان الكتاب موجوداً بالفعل في المكتبة.
  Future<bool> addDownloadedBook({
    required String title,
    required String filePath,
    required BookFileType fileType,
    String? coverPath,
  }) async {
    if (_books.any((b) => b.title == title)) return false;
    final now = DateTime.now();
    await addBook(BookModel(
      id: 'dl_${now.millisecondsSinceEpoch}',
      title: title,
      filePath: filePath,
      fileType: fileType,
      coverPath: coverPath,
      currentPage: 1,
      totalPages: 0,
      progressPercentage: 0,
      isFavorite: false,
      isPinned: false,
      createdAt: now,
      lastReadAt: now,
    ));
    return true;
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    notifyListeners();
  }

  void clearSearch() {
    if (_searchQuery.isEmpty) return;
    _searchQuery = '';
    notifyListeners();
  }

  Future<void> toggleFavorite(String id) => _updateAndPersist(
      id, (b) => b.copyWith(isFavorite: !b.isFavorite));

  Future<void> togglePin(String id) => _updateAndPersist(
      id, (b) => b.copyWith(isPinned: !b.isPinned));

  /// تحديث موضع القراءة (Step 4) — يُستدعى عند كل تغيّر صفحة/فصل.
  /// يتجاهل التكرار (نفس الصفحة) فلا يكتب في القاعدة بلا حاجة.
  Future<void> updateProgress(
    String id, {
    required int currentPage,
    required int totalPages,
  }) async {
    final index = _books.indexWhere((b) => b.id == id);
    if (index == -1) return;
    final book = _books[index];
    if (book.currentPage == currentPage && book.totalPages == totalPages) {
      return;
    }
    await _updateAndPersist(
      id,
      (b) => b.copyWith(
        currentPage: currentPage,
        totalPages: totalPages,
        progressPercentage: totalPages <= 0
            ? 0
            : (currentPage / totalPages).clamp(0.0, 1.0),
        lastReadAt: DateTime.now(),
      ),
    );
  }

  Future<void> removeBook(String id) async {
    final before = _books.length;
    _books.removeWhere((b) => b.id == id);
    if (_books.length != before) {
      notifyListeners();
      await _database?.deleteBook(id);
    }
  }

  Future<void> _updateAndPersist(
      String id, BookModel Function(BookModel) transform) async {
    final index = _books.indexWhere((b) => b.id == id);
    if (index == -1) return;
    _books[index] = transform(_books[index]);
    notifyListeners();
    await _database?.updateBook(_books[index]);
  }
}
