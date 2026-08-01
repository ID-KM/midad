import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../data/models/book_model.dart';
import '../../state/library_store.dart';
import '../../state/notes_store.dart';
import '../pages/reader_screen.dart';
import '../widgets/book_actions_sheet.dart';
import '../widgets/book_card.dart';

/// تبويب المفضلة — الكتب المفضلة من المخزن، يتفاعل مع التغييرات لحظياً.
class FavoritesPage extends StatelessWidget {
  final LibraryStore store;
  final NotesStore? notesStore;

  const FavoritesPage({super.key, required this.store, this.notesStore});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المفضلة')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final books = store.favoriteBooks;
          if (books.isEmpty) return const _EmptyFavorites();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: books.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => BookCard(
              book: books[index],
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReaderScreen(
                      book: books[index],
                      store: store,
                      notesStore: notesStore,
                    ),
                  ),
                );
              },
              onToggleFavorite: () => store.toggleFavorite(books[index].id),
              onLongPress: () => _showActions(context, books[index]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showActions(BuildContext context, BookModel book) {
    return BookActionsSheet.show(
      context,
      book: book,
      onTogglePin: () => store.togglePin(book.id),
      onToggleFavorite: () => store.toggleFavorite(book.id),
      onDelete: () {
        store.removeBook(book.id);
        notesStore?.deleteForBook(book.id);
      },
    );
  }
}

/// حالة فارغة للمفضلة — بدون إيموجي، بأيقونة متجهة.
class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.heart,
            size: 64,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 16),
          Text(
            'لا توجد كتب مفضلة بعد',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'اضغط على القلب في أي كتاب لإضافته هنا',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
