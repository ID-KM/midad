import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../data/models/book_model.dart';
import '../../data/services/epub_reader_service.dart';
import '../../state/library_store.dart';
import '../../state/notes_store.dart';
import '../widgets/epub_view.dart';
import '../widgets/notes_drawer.dart';

/// شاشة القراءة النظيفة الخالية من التشتيت — Step 4.
///
/// تستضيف عارض PDF (pdfrx) أو عارض EPUB المخصص حسب نوع الكتاب،
/// مع شريط سفلي نحيف للتنقل وعدّاد الصفحات، وحفظ تلقائي لموضع
/// القراءة عبر [LibraryStore.updateProgress] (أساس الحفظ في 4.2).
class ReaderScreen extends StatefulWidget {
  final BookModel book;
  final LibraryStore store;
  final NotesStore? notesStore;

  const ReaderScreen({
    super.key,
    required this.book,
    required this.store,
    this.notesStore,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const double _minFontSize = 14;
  static const double _maxFontSize = 32;

  final GlobalKey<EpubViewState> _epubKey = GlobalKey<EpubViewState>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  PdfViewerController? _pdfController;
  bool _isEpub = false;

  EpubDocument? _epubDoc;
  String? _loadError;
  bool _loading = true;

  late int _currentPage; // 1-based — رقم الفصل في EPUB
  int _totalPages = 0;
  double _fontSize = 20;

  // التمرير التلقائي (4.3)
  // محرك إطار-بإطار (60fps): Ticker يستدعي _onAutoScrollFrame كل إطار
  // فيحدّث الموضع خطوة صغيرة — تمرير مستمر بلا نبضات منفصلة.
  // يُنشأ في initState (لا late-final): إنشاء أثناء dispose يُرمي
  // "deactivated widget's ancestor lookup" لأنه يبحث عن TickerMode.
  late final AnimationController _scrollAnim;
  bool _autoScrollActive = false;
  double _autoScrollSpeed = 1.0;

  // الملاحظات (4.4) — مخزن خاص بذاكرة عند غياب الخارجي (اختبارات)
  late final NotesStore _notes = widget.notesStore ?? NotesStore();

  String get _pageLabel => _isEpub ? 'فصل' : 'صفحة';

  @override
  void initState() {
    super.initState();
    _scrollAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_onAutoScrollFrame);
    WidgetsBinding.instance.addObserver(this);
    _isEpub = widget.book.fileType == BookFileType.epub;
    _currentPage = widget.book.currentPage > 0 ? widget.book.currentPage : 1;
    _notes.loadForBook(widget.book.id); // بلا انتظار — القائمة تتحدث لاحقاً

    if (_isEpub) {
      _loadEpub();
    } else {
      _checkPdfFile();
    }
  }

  void _checkPdfFile() {
    final exists = File(widget.book.filePath).existsSync();
    setState(() {
      _loading = false;
      _loadError = exists ? null : 'ملف الكتاب غير موجود على الجهاز';
    });
  }

  Future<void> _loadEpub() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final doc = await EpubReaderService.read(widget.book.filePath);
      if (!mounted) return;
      setState(() {
        _epubDoc = doc;
        _totalPages = doc.chapters.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'تعذّر فتح الكتاب: $e';
        _loading = false;
      });
    }
  }

  /// كتابة الموضع في المتغيرات والمخزن — بلا إعادة رسم (تُستخدم من dispose).
  void _persistProgress(int page, int totalPages) {
    _currentPage = page;
    _totalPages = totalPages;
    widget.store.updateProgress(
      widget.book.id,
      currentPage: page,
      totalPages: totalPages,
    );
  }

  /// حفظ موضع القراءة مع إعادة الرسم — يُستدعى عند كل تغيّر صفحة (تلقائي)
  /// ومن زر الحفظ اليدوي.
  void _saveProgress(int page, int totalPages) {
    _persistProgress(page, totalPages);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollAnim.dispose();
    // حفظ تلقائي أخير عند مغادرة الشاشة — حتى بلا حدث تغيّر صفحة
    _persistProgress(_currentPage, _totalPages);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // حفظ تلقائي عند إيقاف التطبيق (إغلاق من مدير المهام مثلاً)
    if (state == AppLifecycleState.paused) {
      _persistProgress(_currentPage, _totalPages);
    }
  }

  void _onPdfPageChanged(int? page) {
    if (page == null) return;
    _saveProgress(page, _pdfController?.pageCount ?? _totalPages);
  }

  void _onEpubChapterChanged(int chapter) {
    _saveProgress(chapter, _epubDoc?.chapters.length ?? _totalPages);
  }

  void _goPrevious() => _goToPage(_currentPage - 1);
  void _goNext() => _goToPage(_currentPage + 1);

  bool get _canGoPrevious => _currentPage > 1;
  bool get _canGoNext => _totalPages <= 0 || _currentPage < _totalPages;

  // ─── الانتقال السريع للصفحات ────────────────────────────────────────

  /// قفز موحد مع ضبط الحدود (PDF: goToPage · EPUB: jumpToChapter).
  void _goToPage(int page) {
    if (page < 1) return;
    final total = _totalPages;
    if (total > 0 && page > total) page = total;
    if (_isEpub) {
      _epubKey.currentState?.jumpToChapter(page);
    } else {
      _pdfController?.goToPage(pageNumber: page);
    }
  }

  /// حوار إدخال رقم الصفحة — يُفتح بالنقر على عدّاد الصفحات في الشريط
  /// السفلي. يرفض الأرقام خارج النطاق برسالة ولا يقفز.
  Future<void> _openPageJumpDialog() async {
    final total = _totalPages;
    if (total <= 0) return; // لا نعرف عدد الصفحات بعد — لا نقفز

    final page = await showDialog<int>(
      context: context,
      builder: (_) => _PageJumpDialog(totalPages: total, label: _pageLabel),
    );
    if (page == null) return; // إلغاء أو نص غير رقمي
    if (page < 1 || page > total) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('رقم $_pageLabel يجب أن يكون بين 1 و $total'),
          duration: const Duration(seconds: 2),
        ));
      return;
    }
    _goToPage(page);
  }

  // ─── الملاحظات (4.4) ────────────────────────────────────────────────

  /// القفز الفوري لصفحة ملاحظة (PDF: goToPage · EPUB: jumpToChapter).
  void _jumpToNotePage(int page) {
    Navigator.of(context).pop(); // إغلاق القائمة الجانبية
    _goToPage(page);
  }

  // ─── التمرير التلقائي (4.3) ──────────────────────────────────────────

  void _toggleAutoScroll() {
    if (_autoScrollActive) {
      _stopAutoScroll();
    } else {
      _startAutoScroll();
    }
  }

  void _startAutoScroll() {
    _autoScrollActive = true;
    _scrollAnim.repeat();
    setState(() {});
  }

  void _stopAutoScroll() {
    _autoScrollActive = false;
    _scrollAnim.stop();
    _scrollAnim.value = 0;
    setState(() {});
  }

  /// خطوة النزول بالبكسل لكل إطار (عند 60fps) — 6px/s أساسية عند 1.0×:
  /// 0.5× = 12px/s (قراءة متأنية) · 1.0× = 24px/s (قراءة مريحة) ·
  /// 2.0× = 48px/s (تصفّح سريع).
  double get _autoScrollStepPerFrame => (6 * _autoScrollSpeed) / 60;

  /// نبضة المحرك — تُستدعى كل إطار (Ticker): خطوة صغيرة فورية بلا
  /// أنيميشن داخلي → حركة مستمرة متصلة (لا نبضات، لا تقطيع).
  void _onAutoScrollFrame() {
    if (!_autoScrollActive) return;
    final step = _autoScrollStepPerFrame;
    if (_isEpub) {
      final epub = _epubKey.currentState;
      if (epub == null) return;
      // نهاية المحتوى → توقف تلقائي
      if (epub.maxScrollExtent - epub.scrollOffset < 2) {
        _finishAutoScroll();
        return;
      }
      epub.scrollByJump(step);
    } else {
      // PDF: نزول مستمر عبر تحديث مصفوفة العرض مباشرة (مثل التمرير اليدوي)
      final c = _pdfController;
      if (c == null || !c.isReady) return;
      final maxY = c.documentSize.height - c.viewSize.height;
      if (maxY <= 0) return;
      if (c.visibleRect.top >= maxY - 2) {
        // الوصول لنهاية المستند → التثبيت ثم التوقف
        c.goToPosition(documentOffset: Offset(0, maxY));
        _finishAutoScroll();
        return;
      }
      final m = c.value.clone();
      // المصفوفة معكوسة: النزول = ترجمة y سالبة (مثل _goToPosition)
      m.translateByDouble(0.0, -step, 0.0, 1.0);
      c.value = m; // setter يضبط الحدود تلقائياً (forceClamp)
    }
  }

  void _finishAutoScroll() {
    // حفظ آخر موضع معروف قبل التوقف (PDF: رقم الصفحة الفعلي)
    if (!_isEpub) {
      final p = _pdfController?.pageNumber;
      if (p != null) _saveProgress(p, _pdfController?.pageCount ?? _totalPages);
    }
    _stopAutoScroll();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('وصلت إلى نهاية الكتاب'),
        duration: Duration(seconds: 2),
        // عائم ومرتفع: لا يغطي أزرار الشريط السفلي (يمكن إعادة
        // التفعيل فوراً بدل انتظار اختفائه)
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, 84),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: NotesDrawer(
        store: _notes,
        currentPage: _currentPage,
        onJumpToPage: _jumpToNotePage,
      ),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Text(
          widget.book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_isEpub && _epubDoc != null) ...[
            IconButton(
              onPressed: _fontSize > _minFontSize
                  ? () => setState(() => _fontSize -= 2)
                  : null,
              icon: const Icon(LucideIcons.type, size: 20),
              tooltip: 'تصغير الخط',
            ),
            IconButton(
              onPressed: _fontSize < _maxFontSize
                  ? () => setState(() => _fontSize += 2)
                  : null,
              icon: const Icon(LucideIcons.type, size: 26),
              tooltip: 'تكبير الخط',
            ),
          ],
          IconButton(
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            icon: const Icon(LucideIcons.stickyNote, size: 20),
            tooltip: 'الملاحظات',
          ),
          IconButton(
            onPressed: () {
              _saveProgress(_currentPage, _totalPages);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text('تم حفظ الموضع: $_pageLabel $_currentPage'),
                    duration: const Duration(seconds: 2),
                  ),
                );
            },
            icon: const Icon(LucideIcons.bookmark, size: 20),
            tooltip: 'حفظ الموضع يدوياً',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(LucideIcons.x, size: 22),
            tooltip: 'الخروج من القارئ',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody(theme)),
          _buildBottomBar(theme, muted),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return _ErrorView(
        message: _loadError!,
        onRetry: _isEpub ? _loadEpub : _checkPdfFile,
      );
    }

    if (_isEpub) {
      final doc = _epubDoc!;
      return EpubView(
        key: _epubKey,
        document: doc,
        initialChapter: _currentPage,
        fontSize: _fontSize,
        onChapterChanged: _onEpubChapterChanged,
      );
    }

    final startPage = widget.book.currentPage > 0 ? widget.book.currentPage : 1;
    return PdfViewer.file(
      widget.book.filePath,
      controller: _pdfController ??= PdfViewerController(),
      initialPageNumber: startPage,
      params: PdfViewerParams(
        backgroundColor: theme.scaffoldBackgroundColor,
        margin: 10,
        // سلاسة التمرير: عرض تدريجي سريع بدل الانتظار لدقة كاملة
        // 1) onePassRenderingScaleThreshold أصغر → كل صفحة تظهر فوراً
        //    بدقة منخفضة ثم تتحسن خلال أجزاء الثانية (لا توقف عند كل صفحة)
        // 2) useAlternativeFitScaleAsMinScale=false → لا تصغير مفرط يعرض
        //    صفحات كثيرة دفعة واحدة (رسم أبطأ)
        // 3) limitRenderingCache → كاش محدود: ذاكرة أقل على الأجهزة الضعيفة
        sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(
          onePassRenderingScaleThreshold: 1.5,
          useAlternativeFitScaleAsMinScale: false,
        ),
        onePassRenderingSizeThreshold: 1000,
        limitRenderingCache: true,
        onPageChanged: _onPdfPageChanged,
        onViewerReady: (document, controller) {
          if (!mounted) return;
          setState(() {
            _totalPages = document.pages.length;
          });
        },
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme, Color muted) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: muted.withValues(alpha: 0.25)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // تمرير تلقائي — تشغيل/إيقاف
                IconButton(
                  onPressed: _toggleAutoScroll,
                  icon: Icon(
                    _autoScrollActive
                        ? LucideIcons.pause
                        : LucideIcons.play,
                    size: 20,
                  ),
                  color: _autoScrollActive
                      ? theme.colorScheme.primary
                      : null,
                  tooltip: _autoScrollActive
                      ? 'إيقاف التمرير التلقائي'
                      : 'تمرير تلقائي',
                ),
                IconButton(
                  onPressed: _canGoPrevious ? _goPrevious : null,
                  icon: const Icon(LucideIcons.chevronRight, size: 22),
                  tooltip: 'السابق',
                ),
                Expanded(
                  child: Tooltip(
                    message: 'الانتقال إلى $_pageLabel',
                    child: InkWell(
                      onTap: _totalPages > 0 ? _openPageJumpDialog : null,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$_pageLabel $_currentPage من $_totalPages',
                                  textDirection: TextDirection.rtl,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: muted,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  LucideIcons.arrowUpRight,
                                  size: 14,
                                  color: muted,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _canGoNext ? _goNext : null,
                  icon: const Icon(LucideIcons.chevronLeft, size: 22),
                  tooltip: 'التالي',
                ),
              ],
            ),
            // شريط السرعة — يظهر أثناء التمرير التلقائي فقط
            if (_autoScrollActive)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Icon(LucideIcons.gauge,
                        size: 16, color: muted),
                    Expanded(
                      child: Slider(
                        value: _autoScrollSpeed,
                        min: 0.5,
                        max: 2.0,
                        divisions: 15,
                        label:
                            '${_autoScrollSpeed.toStringAsFixed(1)}×',
                        onChanged: (v) {
                          // السرعة تُقرأ كل إطار من المحرك — التغيير يسري
                          // فوراً بلا إعادة جدولة
                          setState(() => _autoScrollSpeed = v);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${_autoScrollSpeed.toStringAsFixed(1)}×',
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// حوار الانتقال السريع لرقم صفحة/فصل — StatefulWidget يدير
/// TextEditingController بدورة حياة صحيحة (dispose بعد خروج الحوار
/// بأنيميشن — لا يسمح بالتفريغ الفوري بعد await showDialog).
class _PageJumpDialog extends StatefulWidget {
  final int totalPages;
  final String label;

  const _PageJumpDialog({required this.totalPages, required this.label});

  @override
  State<_PageJumpDialog> createState() => _PageJumpDialogState();
}

class _PageJumpDialogState extends State<_PageJumpDialog> {
  late final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(int.tryParse(_controller.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('الانتقال إلى ${widget.label}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.go,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          hintText: 'من 1 إلى ${widget.totalPages}',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('انتقال'),
        ),
      ],
    );
  }
}

/// حالة الخطأ: رسالة + إعادة محاولة + خروج.
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.fileWarning,
              size: 56,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw, size: 18),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
