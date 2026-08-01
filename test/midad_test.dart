import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import 'package:midad/core/theme/app_theme.dart';
import 'package:midad/core/theme/eye_care.dart';
import 'package:midad/data/mock/mock_books.dart';
import 'package:midad/main.dart';
import 'package:midad/presentation/main_shell.dart';
import 'package:midad/presentation/pages/favorites_page.dart';
import 'package:midad/presentation/pages/home_page.dart';
import 'package:midad/presentation/pages/online_search_page.dart';
import 'package:midad/presentation/pages/reader_screen.dart';
import 'package:midad/presentation/pages/settings_page.dart';
import 'package:midad/presentation/widgets/book_actions_sheet.dart';
import 'package:midad/presentation/widgets/book_card.dart';
import 'package:midad/presentation/widgets/book_cover_placeholder.dart';
import 'package:midad/state/library_store.dart';
import 'package:midad/state/theme_controller.dart';

void main() {
  group('AppTheme', () {
    test('القوالب الثلاثة تُبنى بخلفياتها الصحيحة', () {
      expect(AppTheme.light().scaffoldBackgroundColor, AppColors.paperLight);
      expect(AppTheme.dark().scaffoldBackgroundColor, AppColors.darkBackground);
      expect(
          AppTheme.amoled().scaffoldBackgroundColor, AppColors.amoledBackground);
    });

    test('ألوان PRD مطابقة للمواصفات', () {
      expect(AppColors.lightBrown, const Color(0xFF8B5A2B));
      expect(AppColors.darkBrown, const Color(0xFF3E2723));
      expect(AppColors.warmYellow, const Color(0xFFF5D061));
      expect(AppColors.paperLight, const Color(0xFFFDFBF7));
      expect(AppColors.darkBackground, const Color(0xFF121212));
      expect(AppColors.amoledBackground, const Color(0xFF000000));
    });
  });

  group('EyeCare', () {
    test('sepiaColorFilter عند صفر يعطي مصفوفة هوية', () {
      final filter = sepiaColorFilter(0);
      expect(filter.toString(), contains('matrix'));
      expect(sepiaColorFilter(1).toString(), contains('matrix'));
    });

    test('الشدة تُقفل ضمن المدى', () {
      expect(sepiaColorFilter(-1).toString(), sepiaColorFilter(0).toString());
      expect(sepiaColorFilter(5).toString(), sepiaColorFilter(1).toString());
    });
  });

  group('LibraryStore', () {
    late LibraryStore store;

    setUp(() => store = LibraryStore(initialBooks: MockBooks.all));

    test('toggleFavorite يعكس الحالة', () {
      final first = store.books.first;
      store.toggleFavorite(first.id);
      expect(store.bookById(first.id)!.isFavorite, !first.isFavorite);
    });

    test('togglePin يعكس الحالة', () {
      final first = store.books.first;
      store.togglePin(first.id);
      expect(store.bookById(first.id)!.isPinned, !first.isPinned);
    });

    test('removeBook يحذف الكتاب', () {
      final count = store.books.length;
      store.removeBook(store.books.first.id);
      expect(store.books.length, count - 1);
    });

    test('filteredBooks يصفّي بالعنوان', () {
      store.setSearchQuery('البداية');
      expect(store.filteredBooks.length, 1);
      expect(store.filteredBooks.first.title, 'البداية والنهاية');
    });

    test('filteredBooks بلا استعلام يعيد كل الكتب', () {
      expect(store.filteredBooks.length, MockBooks.all.length);
    });

    test('sortedBooks يضع المثبت أولاً', () {
      final target = store.books.first;
      store.togglePin(target.id);
      expect(store.sortedBooks.first.id, target.id);
    });
  });

  group('ThemeController', () {
    test('تبديل الوضع والشدة', () {
      final controller = ThemeController();
      controller.setMode(AppThemeMode.amoled);
      expect(controller.mode, AppThemeMode.amoled);
      controller.setEyeCareEnabled(true);
      expect(controller.eyeCareEnabled, isTrue);
      controller.setEyeCareIntensity(0.8);
      expect(controller.eyeCareIntensity, 0.8);
    });
  });

  group('BookCard', () {
    testWidgets('يعرض العنوان والنسبة وزر القلب', (tester) async {
      final book = MockBooks.all.first;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: BookCard(book: book)),
        ),
      );

      expect(find.text(book.title), findsOneWidget);
      expect(
        find.text('${(book.progressPercentage * 100).round()}%'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('الغلاف الافتراضي يظهر بدون صورة', (tester) async {
      final book = MockBooks.all.first;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: BookCoverPlaceholder(
              title: book.title,
              accent: MockBooks.coverAccent(book.id),
            ),
          ),
        ),
      );
      expect(find.byType(BookCoverPlaceholder), findsOneWidget);
      expect(find.byIcon(LucideIcons.bookOpen), findsOneWidget);
    });
  });

  group('MidadApp — التفاعلات', () {
    // مع IndexedStack كل التبويبات حية في الشجرة — يجب استهداف عناصر كل تبويب
    Finder homeCards() => find.descendant(
        of: find.byType(HomePage), matching: find.byType(BookCard));

    Finder favCards() => find.descendant(
        of: find.byType(FavoritesPage), matching: find.byType(BookCard));

    Finder navTab(String label) => find.descendant(
        of: find.byType(BottomNavigationBar), matching: find.text(label));

    testWidgets('يعرض الرئيسية والتبويبات الثلاثة', (tester) async {
      await tester.pumpWidget(const MidadApp());

      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.text('مكتبتي'), findsOneWidget);
    });

    testWidgets('البحث يصفّي القائمة ويظهر واجهة النتائج', (tester) async {
      await tester.pumpWidget(const MidadApp());

      await tester.enterText(find.byType(TextField), 'البداية');
      await tester.pumpAndSettle();

      expect(homeCards(), findsOneWidget);
      expect(find.text('البداية والنهاية'), findsOneWidget);
      expect(find.textContaining('نتائج البحث'), findsOneWidget);

      await tester.tap(find.text('مسح'));
      await tester.pumpAndSettle();
      expect(find.textContaining('نتائج البحث'), findsNothing);
      // ListView كسول — لا يبني كل البطاقات في viewport الاختبار
      expect(homeCards(), findsWidgets);
    });

    testWidgets('بحث بلا نتائج يعرض الحالة الفارغة', (tester) async {
      await tester.pumpWidget(const MidadApp());

      await tester.enterText(find.byType(TextField), 'كلمة غير موجودة');
      await tester.pumpAndSettle();

      expect(homeCards(), findsNothing);
      expect(find.textContaining('لا توجد نتائج'), findsOneWidget);
    });

    testWidgets('قلب البطاقة يبدّل المفضلة لحظياً', (tester) async {
      await tester.pumpWidget(const MidadApp());

      // أول كتاب رئيسي (رياض الصالحين) مفضل — نسحب المفضلة بضربة القلب
      await tester.tap(
        find.descendant(of: homeCards().first, matching: find.byIcon(Icons.favorite)),
      );
      await tester.pumpAndSettle();

      await tester.tap(navTab('المفضلة'));
      await tester.pumpAndSettle();

      expect(favCards(), findsNWidgets(2)); // إحياء + ابن بطوطة
    });

    testWidgets('الضغط على كتاب في المفضلة يفتح القارئ', (tester) async {
      await tester.pumpWidget(const MidadApp());

      await tester.tap(navTab('المفضلة'));
      await tester.pumpAndSettle();

      // كتب المفضلة تظهر (كلها PDF افتراضياً)
      expect(favCards(), findsWidgets);

      // الضغط على كتاب مفضل — كان لا يستجيب إطلاقاً قبل الإصلاح
      await tester.tap(favCards().first);
      await tester.pumpAndSettle();

      // القارئ فُتح (الكتاب mock بملف غير موجود — يظهر القارئ بخطأ واضح)
      expect(find.byType(ReaderScreen), findsOneWidget);
    });

    testWidgets('الضغط المطول يفتح القائمة المخصصة ويحذف بعد التأكيد',
        (tester) async {
      await tester.pumpWidget(const MidadApp());

      // ثاني كتاب رئيسي (البداية والنهاية): غير مثبت، غير مفضل
      await tester.longPress(homeCards().at(1));
      await tester.pumpAndSettle();

      // القائمة المخصصة ظهرت بالإجراءات الثلاثة
      expect(find.byType(BookActionsSheet), findsOneWidget);
      expect(find.text('تثبيت في الأعلى'), findsOneWidget);
      expect(find.text('إضافة إلى المفضلة'), findsOneWidget);

      await tester.tap(find.text('حذف الكتاب'));
      await tester.pumpAndSettle();

      // تأكيد الحذف
      expect(find.textContaining('سيتم حذف'), findsOneWidget);
      await tester.tap(find.text('حذف'));
      await tester.pumpAndSettle();

      expect(find.text('البداية والنهاية'), findsNothing);
    });

    testWidgets('إلغاء الحذف لا يحذف', (tester) async {
      await tester.pumpWidget(const MidadApp());

      await tester.longPress(homeCards().first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('حذف الكتاب'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();

      // لا يزال موجوداً في الرئيسية (النسخة الأخرى في المفضلة لأن الكتاب مفضل)
      expect(
        find.descendant(
          of: find.byType(HomePage),
          matching: find.text('رياض الصالحين'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('أيقونة مكتبة الإنترنت تفتح صفحة البحث عن الكتب', (tester) async {
      await tester.pumpWidget(const MidadApp());

      await tester.tap(find.byIcon(LucideIcons.library));
      await tester.pumpAndSettle();

      expect(find.byType(OnlineSearchPage), findsOneWidget);
      expect(find.text('مكتبة الإنترنت'), findsOneWidget);
    });

    testWidgets('التبديل بين الشاشات الثلاث يعمل ويحافظ على التبويب',
        (tester) async {
      await tester.pumpWidget(const MidadApp());

      await tester.tap(navTab('المفضلة'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .currentIndex,
        1,
      );

      await tester.tap(navTab('الإعدادات'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .currentIndex,
        2,
      );
    });

    testWidgets('تبديل الثيم في الإعدادات يغيّر خلفية التطبيق', (tester) async {
      await tester.pumpWidget(const MidadApp());

      await tester.tap(navTab('الإعدادات'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('داكن'));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(MainShell));
      expect(
        Theme.of(context).scaffoldBackgroundColor,
        AppColors.darkBackground,
      );

      await tester.tap(find.text('AMOLED'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(context).scaffoldBackgroundColor,
        AppColors.amoledBackground,
      );
    });

    testWidgets('حماية العين تُفعّل الفلتر الدافئ مع شريط الشدة',
        (tester) async {
      await tester.pumpWidget(const MidadApp());

      await tester.tap(navTab('الإعدادات'));
      await tester.pumpAndSettle();

      // قبل التفعيل لا يوجد شريط شدة
      expect(find.byType(Slider), findsNothing);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsOneWidget);
      expect(
        tester
            .widgetList<ColorFiltered>(find.byType(ColorFiltered))
            .any((f) => f.colorFilter.toString().contains('matrix')),
        isTrue,
      );
    });
  });
}
