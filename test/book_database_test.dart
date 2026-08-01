import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:midad/data/datasources/book_database.dart';
import 'package:midad/data/mock/mock_books.dart';
import 'package:midad/data/models/book_model.dart';

void main() {
  group('BookDatabase', () {
    late BookDatabase db;

    BookModel book(
      String id, {
      bool favorite = false,
      bool pinned = false,
      DateTime? lastRead,
    }) =>
        BookModel(
          id: id,
          title: 'كتاب $id',
          filePath: '/books/$id.pdf',
          fileType: BookFileType.pdf,
          currentPage: 0,
          totalPages: 100,
          progressPercentage: 0,
          isFavorite: favorite,
          isPinned: pinned,
          createdAt: DateTime(2026, 1, 1),
          lastReadAt: lastRead ?? DateTime(2026, 1, 1),
        );

    setUp(() async {
      db = await BookDatabase.open(overridePath: ':memory:');
    });

    tearDown(() => db.close());

    test('إدراج واسترجاع يحافظ على كل الحقول', () async {
      final b = book('b1', favorite: true, pinned: true);
      await db.insertBook(b);

      final got = await db.getBook('b1');
      expect(got, isNotNull);
      expect(got!.title, b.title);
      expect(got.filePath, b.filePath);
      expect(got.fileType, BookFileType.pdf);
      expect(got.coverPath, isNull);
      expect(got.isFavorite, isTrue);
      expect(got.isPinned, isTrue);
      expect(got.currentPage, 0);
      expect(got.totalPages, 100);
      expect(got.createdAt, b.createdAt);
      expect(got.lastReadAt, b.lastReadAt);
    });

    test('إدراج بنفس المعرّف يستبدل السجل (upsert)', () async {
      await db.insertBook(book('x'));
      await db.insertBook(book('x', favorite: true, pinned: true));
      final got = await db.getBook('x');
      expect(got!.isFavorite, isTrue);
      expect(got.isPinned, isTrue);
      expect(await db.countBooks(), 1);
    });

    test('getAllBooks يرتب: المثبت أولاً ثم آخر قراءة', () async {
      await db.insertBook(book('a', lastRead: DateTime(2026, 7, 1)));
      await db.insertBook(book('b', pinned: true, lastRead: DateTime(2026, 7, 2)));
      await db.insertBook(book('c', lastRead: DateTime(2026, 7, 3)));

      final ids = (await db.getAllBooks()).map((b) => b.id).toList();
      expect(ids, ['b', 'c', 'a']);
    });

    test('updateBook يحدّث الحقول ويبقي المعرّف', () async {
      await db.insertBook(book('y'));
      await db.updateBook(book('y', favorite: true, pinned: true));

      final got = await db.getBook('y');
      expect(got!.isFavorite, isTrue);
      expect(got.isPinned, isTrue);
    });

    test('deleteBook يزيل السجل', () async {
      await db.insertBook(book('z'));
      await db.deleteBook('z');
      expect(await db.getBook('z'), isNull);
      expect(await db.countBooks(), 0);
    });

    test('getFavoriteBooks يعيد المفضلة فقط', () async {
      await db.insertBook(book('f1', favorite: true));
      await db.insertBook(book('f2'));
      await db.insertBook(book('f3', favorite: true));

      final favs = await db.getFavoriteBooks();
      expect(favs.map((b) => b.id).toList(), ['f1', 'f3']);
    });

    test('زرع الكتب التجريبية ثم العد', () async {
      for (final b in MockBooks.all) {
        await db.insertBook(b);
      }
      expect(await db.countBooks(), MockBooks.all.length);
    });

    test('البيانات تبقى بعد إغلاق القاعدة وإعادة فتحها (ملف حقيقي)', () async {
      final dir = await Directory.systemTemp.createTemp('midad_db_test');
      final dbPath = '${dir.path}/midad.db';

      // أول فتح: إدراج + إغلاق
      var db1 = await BookDatabase.open(overridePath: dbPath);
      await db1.insertBook(book('p1', favorite: true, pinned: true));
      await db1.close();

      // إعادة فتح (محاكاة إقلاع التطبيق): البيانات باقية
      var db2 = await BookDatabase.open(overridePath: dbPath);
      final got = await db2.getBook('p1');
      expect(got, isNotNull);
      expect(got!.title, 'كتاب p1');
      expect(got.isFavorite, isTrue);
      expect(got.isPinned, isTrue);
      await db2.close();

      await dir.delete(recursive: true);
    });
  });
}
