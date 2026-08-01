import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../data/mock/mock_books.dart';
import '../../data/models/book_model.dart';
import 'book_cover_placeholder.dart';

/// بطاقة الكتاب — غلاف + عنوان + شريط تقدم + زر المفضلة.
/// الضغط المطول يفتح قائمة الإجراءات (تثبيت / مفضلة / حذف).
class BookCard extends StatelessWidget {
  final BookModel book;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggleFavorite;

  const BookCard({
    super.key,
    required this.book,
    this.onTap,
    this.onLongPress,
    this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = book.coverPath == null
        ? BookCoverPlaceholder(
            title: book.title,
            accent: MockBooks.coverAccent(book.id),
            width: 64,
            height: 92,
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(book.coverPath!),
              width: 64,
              height: 92,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => BookCoverPlaceholder(
                title: book.title,
                accent: MockBooks.coverAccent(book.id),
                width: 64,
                height: 92,
              ),
            ),
          );

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cover,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (book.isPinned) ...[
                          Icon(LucideIcons.pin,
                              size: 14,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            book.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${book.fileType.name.toUpperCase()}  |  صفحة ${book.currentPage} من ${book.totalPages}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // شريط التقدم
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: book.progressPercentage,
                              minHeight: 6,
                              backgroundColor: AppColors.warmYellow
                                  .withValues(alpha: 0.25),
                              valueColor: const AlwaysStoppedAnimation(
                                  AppColors.warmYellow),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(book.progressPercentage * 100).round()}%',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.warmYellow,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // زر المفضلة — يبدّل الحالة عبر المخزن
              IconButton(
                onPressed: onToggleFavorite,
                icon: Icon(
                  book.isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: book.isFavorite
                      ? AppColors.warmYellow
                      : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  size: 22,
                ),
                tooltip: book.isFavorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
