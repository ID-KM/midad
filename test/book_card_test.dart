import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midad/data/models/book_model.dart';
import 'package:midad/presentation/widgets/book_card.dart';
import 'package:midad/presentation/widgets/book_cover_placeholder.dart';

BookModel _book(String id, {String? coverPath}) {
  final now = DateTime(2026, 1, 1);
  return BookModel(
    id: id,
    title: 'كتاب تجريبي',
    filePath: '/tmp/$id.pdf',
    fileType: BookFileType.pdf,
    coverPath: coverPath,
    currentPage: 5,
    totalPages: 100,
    progressPercentage: 0.05,
    isFavorite: false,
    isPinned: false,
    createdAt: now,
    lastReadAt: now,
  );
}

Widget _wrap(BookModel book) => MaterialApp(
      home: Scaffold(body: BookCard(book: book)),
    );

void main() {
  late Directory tempDir;
  late File coverPng;

  setUp(() async {
    // I/O خارج testWidgets (الزمن الوهمي) — درس مُوثَّق: داخل testWidgets يعلّق
    tempDir = await Directory.systemTemp.createTemp('midad_cover_card_');
    coverPng = File('${tempDir.path}/cover.png');
    // 1×1 PNG صالح
    await coverPng.writeAsBytes([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('بلا coverPath: يظهر placeholder ولا Image', (tester) async {
    await tester.pumpWidget(_wrap(_book('n1')));
    expect(find.byType(BookCoverPlaceholder), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('مع coverPath: يعرض Image.file من المسار الحقيقي', (tester) async {
    await tester.pumpWidget(_wrap(_book('c1', coverPath: coverPng.path)));
    await tester.pump();
    expect(find.byType(BookCoverPlaceholder), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<FileImage>());
  });

  testWidgets('coverPath يشير لملف مفقود: placeholder بدل انهيار', (tester) async {
    await tester.pumpWidget(
        _wrap(_book('m1', coverPath: '${tempDir.path}/missing.png')));
    // فشل FileImage يتم عبر I/O حقيقي — ننتظر خارج الزمن الوهمي
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    expect(find.byType(BookCoverPlaceholder), findsOneWidget);
  });
}
