import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../models/book_model.dart';

/// بيانات وهمية لعرض Step 1 — ستُستبدل بقاعدة البيانات المحلية في Step 3.
abstract final class MockBooks {
  static final List<BookModel> all = [
    BookModel(
      id: 'b1',
      title: 'رياض الصالحين',
      filePath: '/books/riyad_alsalihin.pdf',
      fileType: BookFileType.pdf,
      currentPage: 214,
      totalPages: 640,
      progressPercentage: 0.334,
      isFavorite: true,
      isPinned: true,
      createdAt: DateTime(2026, 7, 2),
      lastReadAt: DateTime(2026, 7, 30, 21, 40),
    ),
    BookModel(
      id: 'b2',
      title: 'البداية والنهاية',
      filePath: '/books/albidaya_wannihaya.epub',
      fileType: BookFileType.epub,
      currentPage: 120,
      totalPages: 480,
      progressPercentage: 0.25,
      isFavorite: false,
      isPinned: false,
      createdAt: DateTime(2026, 6, 18),
      lastReadAt: DateTime(2026, 7, 29, 23, 10),
    ),
    BookModel(
      id: 'b3',
      title: 'إحياء علوم الدين',
      filePath: '/books/ihya_ulum_aldin.pdf',
      fileType: BookFileType.pdf,
      currentPage: 512,
      totalPages: 704,
      progressPercentage: 0.727,
      isFavorite: true,
      isPinned: false,
      createdAt: DateTime(2026, 5, 30),
      lastReadAt: DateTime(2026, 7, 28, 19, 5),
    ),
    BookModel(
      id: 'b4',
      title: 'صحيح البخاري',
      filePath: '/books/sahih_albukhari.epub',
      fileType: BookFileType.epub,
      currentPage: 88,
      totalPages: 1248,
      progressPercentage: 0.071,
      isFavorite: false,
      isPinned: false,
      createdAt: DateTime(2026, 7, 10),
      lastReadAt: DateTime(2026, 7, 27, 8, 15),
    ),
    BookModel(
      id: 'b5',
      title: 'رحلة ابن بطوطة',
      filePath: '/books/rihlat_ibn_battuta.pdf',
      fileType: BookFileType.pdf,
      currentPage: 156,
      totalPages: 480,
      progressPercentage: 0.325,
      isFavorite: true,
      isPinned: false,
      createdAt: DateTime(2026, 4, 22),
      lastReadAt: DateTime(2026, 7, 25, 14, 30),
    ),
    BookModel(
      id: 'b6',
      title: 'الأغاني',
      filePath: '/books/alaaghani.epub',
      fileType: BookFileType.epub,
      currentPage: 96,
      totalPages: 960,
      progressPercentage: 0.10,
      isFavorite: false,
      isPinned: false,
      createdAt: DateTime(2026, 7, 15),
      lastReadAt: DateTime(2026, 7, 20, 11, 0),
    ),
    BookModel(
      id: 'b7',
      title: 'مختصر تفسير ابن كثير',
      filePath: '/books/tafsir_ibn_kathir.pdf',
      fileType: BookFileType.pdf,
      currentPage: 60,
      totalPages: 1216,
      progressPercentage: 0.049,
      isFavorite: false,
      isPinned: false,
      createdAt: DateTime(2026, 7, 21),
      lastReadAt: DateTime(2026, 7, 18, 17, 45),
    ),
  ];

  /// لون تمييزي ثابت لكل كتاب (مشتق من المعرّف) للغلاف الافتراضي.
  static Color coverAccent(String id) {
    final hash = id.codeUnits.fold<int>(0, (acc, c) => acc + c);
    const palette = [
      AppColors.lightBrown,
      Color(0xFF9C6B3C),
      Color(0xFF7A4E2D),
      Color(0xFFB0782F),
    ];
    return palette[hash % palette.length];
  }
}
