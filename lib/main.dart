import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/eye_care.dart';
import 'data/datasources/book_database.dart';
import 'data/mock/mock_books.dart';
import 'data/services/download_notification_service.dart';
import 'presentation/main_shell.dart';
import 'state/library_store.dart';
import 'state/notes_store.dart';
import 'state/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // فتح قاعدة البيانات المحلية (SQLite) — Step 3 + ملاحظات 4.4.
  LibraryStore? libraryStore;
  NotesStore? notesStore;
  BookDatabase? database;
  try {
    // إشعارات تقدم التحميل — تُهيّأ قبل أي استخدام.
    await DownloadNotificationService.instance.init();
    await DownloadNotificationService.instance.requestPermission();
    database = await BookDatabase.open();
    libraryStore = LibraryStore(database: database);
    notesStore = NotesStore(database: database);
    await libraryStore.loadFromDatabase();
  } catch (e) {
    debugPrint('⚠️ تعذّر فتح قاعدة البيانات: $e');
  }

  runApp(MidadApp(libraryStore: libraryStore, notesStore: notesStore));
}

/// تطبيق "مداد" — قارئ الكتب المحلي والمنقب المباشر.
class MidadApp extends StatefulWidget {
  /// مخزن مرتبط بالقاعدة — عند غيابه (اختبارات) يُبنى مخزن ذاكرة افتراضي.
  final LibraryStore? libraryStore;

  /// مخزن الملاحظات المرتبط بنفس القاعدة — عند غيابه يُبنى داخلي.
  final NotesStore? notesStore;

  const MidadApp({super.key, this.libraryStore, this.notesStore});

  @override
  State<MidadApp> createState() => _MidadAppState();
}

class _MidadAppState extends State<MidadApp> {
  final ThemeController _themeController = ThemeController();
  late final LibraryStore _libraryStore = widget.libraryStore ??
      LibraryStore(initialBooks: MockBooks.all);
  late final NotesStore _notesStore = widget.notesStore ?? NotesStore();

  @override
  void initState() {
    super.initState();
    // استعادة المظهر المختار (فاتح/داكن/AMOLED) وحماية العين المحفوظة.
    _themeController.loadPreferences();
  }

  @override
  void dispose() {
    _themeController.dispose();
    _libraryStore.dispose();
    _notesStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeController,
      builder: (context, _) {
        final mode = _themeController.mode;
        final isDark = mode != AppThemeMode.light;

        // طبقة حماية العين — فلتر دافئ فوق كامل التطبيق
        return ColorFiltered(
          colorFilter: _themeController.eyeCareEnabled
              ? sepiaColorFilter(_themeController.eyeCareIntensity)
              : const ColorFilter.mode(Color(0x00000000), BlendMode.dst),
          child: MaterialApp(
            title: 'مداد',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.of(mode),
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: MainShell(
              libraryStore: _libraryStore,
              notesStore: _notesStore,
              themeController: _themeController,
            ),
          ),
        );
      },
    );
  }
}
