import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../data/services/book_cover_service.dart';
import '../data/services/book_import_service.dart';
import '../state/library_store.dart';
import '../state/notes_store.dart';
import '../state/theme_controller.dart';
import 'pages/favorites_page.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';

/// الهيكل العام — التبويب السفلي الثلاثي + زر الرفع العائم.
/// كل التبويبات تبقى حية (IndexedStack + Fade) فلا تضيع حالة البحث.
class MainShell extends StatefulWidget {
  final LibraryStore libraryStore;
  final NotesStore notesStore;
  final ThemeController themeController;

  const MainShell({
    super.key,
    required this.libraryStore,
    required this.notesStore,
    required this.themeController,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  late final List<Widget> _pages = [
    HomePage(store: widget.libraryStore, notesStore: widget.notesStore),
    FavoritesPage(store: widget.libraryStore, notesStore: widget.notesStore),
    SettingsPage(themeController: widget.themeController),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          for (var i = 0; i < _pages.length; i++)
            IgnorePointer(
              ignoring: i != _index,
              child: AnimatedOpacity(
                opacity: i == _index ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: _pages[i],
              ),
            ),
        ],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton(
              onPressed: _importBooks,
              tooltip: 'رفع كتاب',
              child: const Icon(LucideIcons.plus, size: 26),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(LucideIcons.home),
            label: 'الرئيسية',
          ),
          BottomNavigationBarItem(
            icon: Icon(LucideIcons.heart),
            label: 'المفضلة',
          ),
          BottomNavigationBarItem(
            icon: Icon(LucideIcons.settings),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }

  /// اختيار ملفات PDF/EPUB ← نسخها إلى المساحة الداخلية ← إضافتها للمكتبة.
  Future<void> _importBooks() async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await BookImportService.pickBookFiles();
    if (picked == null || picked.isEmpty) return;

    final support = await getApplicationSupportDirectory();
    final libraryDir = '${support.path}/books';

    int added = 0;
    final skipped = <String>[];
    for (final file in picked) {
      final title = BookImportService.titleFromFile(file);
      // تكرار: نفس العنوان موجود في المكتبة → تخطٍّ
      if (widget.libraryStore.books.any((b) => b.title == title)) {
        skipped.add(title);
        continue;
      }
      try {
        final book = await BookImportService.importFile(
          file,
          libraryDir: libraryDir,
        );
        // الغلاف: استخراج (PDF/EPUB) أو افتراضي بني/أصفر عند التعذر
        final cover = await BookCoverService.ensureCover(
          filePath: book.filePath,
          fileType: book.fileType,
          bookId: book.id,
          coverDir: '$support.path/covers',
          title: book.title,
        );
        await widget.libraryStore.addBook(book.copyWith(coverPath: cover));
        added++;
      } catch (e) {
        debugPrint('⚠️ فشل استيراد «$title»: $e');
        skipped.add(title);
      }
    }

    final msg = added > 0
        ? 'تمت إضافة $added كتاب إلى مكتبتك'
        : 'لم تُضف أي كتب';
    final detail = skipped.isEmpty ? '' : ' — تخطّينا ${skipped.length}';
    messenger.showSnackBar(SnackBar(content: Text('$msg$detail')));
  }
}
