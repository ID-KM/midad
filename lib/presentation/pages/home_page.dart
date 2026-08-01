import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../data/models/book_model.dart';
import '../../state/library_store.dart';
import '../../state/notes_store.dart';
import '../widgets/book_actions_sheet.dart';
import '../widgets/book_card.dart';
import 'online_search_page.dart';
import 'reader_screen.dart';

/// شريط البحث العلوي — يصفّي المكتبة المحلية لحظياً.
/// البحث عبر الإنترنت (Archive.org) في Step 5.
class SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  const SearchField({super.key, required this.controller, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'ابحث عن كتاب في مكتبتك...',
          hintStyle: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            LucideIcons.search,
            size: 20,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    onPressed: () => controller.clear(),
                    icon: Icon(
                      LucideIcons.x,
                      size: 18,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

/// الصفحة الرئيسية — مكتبة قابلة للبحث، ترتيب: مثبت أولاً ثم آخر قراءة.
class HomePage extends StatelessWidget {
  final LibraryStore store;
  final NotesStore? notesStore;
  final TextEditingController searchController = TextEditingController();

  HomePage({super.key, required this.store, this.notesStore});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مكتبتي'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OnlineSearchPage(store: store),
                ),
              );
            },
            icon: const Icon(LucideIcons.library, size: 22),
            tooltip: 'مكتبة الإنترنت — ابحث وتنزّل PDF',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final books = store.filteredBooks;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SearchField(
                  controller: searchController,
                  onChanged: store.setSearchQuery,
                ),
              ),
              if (store.isSearching)
                _SearchResultsHeader(
                  query: store.searchQuery,
                  count: books.length,
                  onClear: () {
                    searchController.clear();
                    store.clearSearch();
                  },
                ),
              Expanded(
                child: books.isEmpty
                    ? _EmptySearch(query: store.searchQuery)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        itemCount: books.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final book = books[index];
                          return BookCard(
                            book: book,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ReaderScreen(
                                    book: book,
                                    store: store,
                                    notesStore: notesStore,
                                  ),
                                ),
                              );
                            },
                            onLongPress: () => _showActions(context, book),
                            onToggleFavorite: () =>
                                store.toggleFavorite(book.id),
                          );
                        },
                      ),
              ),
            ],
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
      onDelete: () => _confirmDelete(context, book),
    );
  }

  Future<void> _confirmDelete(BuildContext context, BookModel book) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('حذف الكتاب'),
        content: Text('سيتم حذف «${book.title}» من مكتبتك نهائياً.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE5484D),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      store.removeBook(book.id);
      notesStore?.deleteForBook(book.id); // ملاحظات الكتاب تُحذف معه
    }
  }
}

/// رأس نتائج البحث — العنوان + العدد + زر مسح.
class _SearchResultsHeader extends StatelessWidget {
  final String query;
  final int count;
  final VoidCallback onClear;

  const _SearchResultsHeader({
    required this.query,
    required this.count,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'نتائج البحث عن «${query.trim()}» — $count',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(LucideIcons.x, size: 16),
            label: const Text('مسح'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
    );
  }
}

/// حالة عدم وجود نتائج للبحث.
class _EmptySearch extends StatelessWidget {
  final String query;

  const _EmptySearch({required this.query});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.searchX,
            size: 64,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 16),
          Text(
            'لا توجد نتائج لـ «${query.trim()}»',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'جرّب كلمة أخرى أو امسح البحث',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
