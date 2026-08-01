import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../data/mock/mock_books.dart';
import '../../data/models/book_model.dart';
import 'book_cover_placeholder.dart';

/// قائمة الضغط المطول المخصصة — BottomSheet مطابق لثيم التطبيق.
/// تعرض معلومات الكتاب + إجراءات: تثبيت، مفضلة، حذف.
class BookActionsSheet extends StatelessWidget {
  final BookModel book;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDelete;

  const BookActionsSheet({
    super.key,
    required this.book,
    required this.onTogglePin,
    required this.onToggleFavorite,
    required this.onDelete,
  });

  /// فتح القائمة من أي سياق.
  static Future<void> show(
    BuildContext context, {
    required BookModel book,
    required VoidCallback onTogglePin,
    required VoidCallback onToggleFavorite,
    required VoidCallback onDelete,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => BookActionsSheet(
        book: book,
        onTogglePin: onTogglePin,
        onToggleFavorite: onToggleFavorite,
        onDelete: onDelete,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = book.coverPath == null
        ? BookCoverPlaceholder(
            title: book.title,
            accent: MockBooks.coverAccent(book.id),
            width: 52,
            height: 74,
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(book.coverPath!),
              width: 52,
              height: 74,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => BookCoverPlaceholder(
                title: book.title,
                accent: MockBooks.coverAccent(book.id),
                width: 52,
                height: 74,
              ),
            ),
          );

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // مقبض السحب
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // رأس: الغلاف + المعلومات
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Row(
              children: [
                cover,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${book.fileType.name.toUpperCase()}  |  '
                        '${(book.progressPercentage * 100).round()}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
          ),
          // الإجراءات
          ListTile(
            onTap: () {
              Navigator.of(context).pop();
              onTogglePin();
            },
            leading: Icon(
              book.isPinned ? LucideIcons.pinOff : LucideIcons.pin,
              color: book.isPinned
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            title: Text(book.isPinned ? 'إلغاء التثبيت' : 'تثبيت في الأعلى'),
            trailing: Icon(
              LucideIcons.chevronLeft,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
          ListTile(
            onTap: () {
              Navigator.of(context).pop();
              onToggleFavorite();
            },
            leading: Icon(
              book.isFavorite ? LucideIcons.heart : LucideIcons.heart,
              color: book.isFavorite
                  ? AppColors.warmYellow
                  : theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            title: Text(book.isFavorite ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة'),
            trailing: Icon(
              LucideIcons.chevronLeft,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
          ListTile(
            onTap: () {
              Navigator.of(context).pop();
              onDelete();
            },
            leading: const Icon(
              LucideIcons.trash2,
              color: Color(0xFFE5484D),
            ),
            title: const Text(
              'حذف الكتاب',
              style: TextStyle(color: Color(0xFFE5484D)),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
