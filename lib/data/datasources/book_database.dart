import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../models/book_model.dart';
import '../models/note_model.dart';

/// قاعدة البيانات المحلية (SQLite) — Step 3 + ملاحظات 4.4.
///
/// على أندرويد/آي أو إس تعمل sqflite الأصلية، وعلى لينكس/ويندوز/ماك
/// تُهيّأ عبر [ffi.sqfliteFfiInit] (المكتبة تأتي مع libsqlite3).
/// الملف: `getApplicationSupportDirectory()/midad.db` — داخل مساحة التطبيق.
class BookDatabase {
  BookDatabase._(this._db);

  static const String _dbFileName = 'midad.db';
  static const String _table = 'books';
  static const String _notesTable = 'notes';

  final Database _db;

  static bool _ffiInitialized = false;

  /// يفتح القاعدة ويُنشئ الجداول عند أول تشغيل.
  ///
  /// [overridePath] للاختبارات فقط — ملف مؤقت أو `':memory:'`.
  static Future<BookDatabase> open({String? overridePath}) async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      if (!_ffiInitialized) {
        ffi.sqfliteFfiInit();
        _ffiInitialized = true;
      }
      databaseFactory = ffi.databaseFactoryFfi;
    }

    final dbPath = overridePath ??
        p.join((await getApplicationSupportDirectory()).path, _dbFileName);
    final db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_table (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            file_path TEXT NOT NULL,
            file_type TEXT NOT NULL,
            cover_path TEXT,
            current_page INTEGER NOT NULL DEFAULT 0,
            total_pages INTEGER NOT NULL DEFAULT 0,
            progress_percentage REAL NOT NULL DEFAULT 0,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            last_read_at INTEGER NOT NULL
          )
        ''');
        await db.execute(_createNotesSql);
      },
      onUpgrade: (db, oldVersion, _) async {
        // v1 → v2: إضافة جدول الملاحظات (القاعدة موجودة عند المستخدم)
        if (oldVersion < 2) {
          await db.execute(_createNotesSql);
        }
      },
    );
    return BookDatabase._(db);
  }

  static const _createNotesSql = '''
    CREATE TABLE $_notesTable (
      id TEXT PRIMARY KEY,
      book_id TEXT NOT NULL,
      page_number INTEGER NOT NULL,
      content TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )
  ''';

  /// إدراج كتاب — يستبدل السجل إن وُجد بنفس المعرّف.
  Future<void> insertBook(BookModel book) => _db.insert(
        _table,
        _toMap(book),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  /// تحديث كتاب موجود (لا يُنشئ سجلاً جديداً).
  Future<void> updateBook(BookModel book) => _db.update(
        _table,
        _toMap(book),
        where: 'id = ?',
        whereArgs: [book.id],
      );

  /// حذف كتاب بمعرّفه.
  Future<void> deleteBook(String id) =>
      _db.delete(_table, where: 'id = ?', whereArgs: [id]);

  /// كل الكتب بنفس ترتيب المكتبة: المثبت أولاً ثم آخر قراءة.
  Future<List<BookModel>> getAllBooks() async {
    final rows = await _db.query(
      _table,
      orderBy: 'is_pinned DESC, last_read_at DESC',
    );
    return rows.map(_fromMap).toList();
  }

  /// كتاب بمعرّفه — null عند عدم الوجود.
  Future<BookModel?> getBook(String id) async {
    final rows =
        await _db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return _fromMap(rows.first);
  }

  /// عدد الكتب المخزنة — يُستخدم للزرع عند أول تشغيل.
  Future<int> countBooks() async {
    final result =
        await _db.rawQuery('SELECT COUNT(*) AS c FROM $_table');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// الكتب المفضلة فقط — للتبويب القادم إن احتاج استعلاماً مباشراً.
  Future<List<BookModel>> getFavoriteBooks() async {
    final rows = await _db.query(
      _table,
      where: 'is_favorite = 1',
      orderBy: 'is_pinned DESC, last_read_at DESC',
    );
    return rows.map(_fromMap).toList();
  }

  Future<void> close() => _db.close();

  // ——— الملاحظات (4.4) ———

  /// إدراج ملاحظة — يستبدل السجل إن وُجد بنفس المعرّف.
  Future<void> insertNote(NoteModel note) => _db.insert(
        _notesTable,
        _noteToMap(note),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  /// ملاحظات كتاب مرتبة حسب رقم الصفحة ثم الأحدث.
  Future<List<NoteModel>> getNotesForBook(String bookId) async {
    final rows = await _db.query(
      _notesTable,
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'page_number ASC, created_at ASC',
    );
    return rows.map(_noteFromMap).toList();
  }

  /// حذف ملاحظة بمعرّفها.
  Future<void> deleteNote(String id) =>
      _db.delete(_notesTable, where: 'id = ?', whereArgs: [id]);

  /// حذف كل ملاحظات كتاب — يُستدعى عند حذف الكتاب من المكتبة.
  Future<void> deleteNotesForBook(String bookId) =>
      _db.delete(_notesTable, where: 'book_id = ?', whereArgs: [bookId]);

  // ——— التحويل ———

  static Map<String, Object?> _toMap(BookModel b) => {
        'id': b.id,
        'title': b.title,
        'file_path': b.filePath,
        'file_type': b.fileType.name,
        'cover_path': b.coverPath,
        'current_page': b.currentPage,
        'total_pages': b.totalPages,
        'progress_percentage': b.progressPercentage,
        'is_favorite': b.isFavorite ? 1 : 0,
        'is_pinned': b.isPinned ? 1 : 0,
        'created_at': b.createdAt.millisecondsSinceEpoch,
        'last_read_at': b.lastReadAt.millisecondsSinceEpoch,
      };

  static Map<String, Object?> _noteToMap(NoteModel n) => {
        'id': n.id,
        'book_id': n.bookId,
        'page_number': n.pageNumber,
        'content': n.content,
        'created_at': n.createdAt.millisecondsSinceEpoch,
      };

  static NoteModel _noteFromMap(Map<String, Object?> m) => NoteModel(
        id: m['id'] as String,
        bookId: m['book_id'] as String,
        pageNumber: m['page_number'] as int,
        content: m['content'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );

  static BookModel _fromMap(Map<String, Object?> m) => BookModel(
        id: m['id'] as String,
        title: m['title'] as String,
        filePath: m['file_path'] as String,
        fileType: m['file_type'] == 'epub'
            ? BookFileType.epub
            : BookFileType.pdf,
        coverPath: m['cover_path'] as String?,
        currentPage: m['current_page'] as int,
        totalPages: m['total_pages'] as int,
        progressPercentage: (m['progress_percentage'] as num).toDouble(),
        isFavorite: (m['is_favorite'] as int) == 1,
        isPinned: (m['is_pinned'] as int) == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        lastReadAt:
            DateTime.fromMillisecondsSinceEpoch(m['last_read_at'] as int),
      );
}
