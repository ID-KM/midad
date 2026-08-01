import 'package:flutter/material.dart';

import '../../data/services/epub_reader_service.dart';

/// عارض EPUB مخصص — Step 4.
///
/// يعرض الفصول كقائمة عمودية RTL بخط Amiri، ويتتبع الفصل الحالي
/// (رقم الصفحة في نموذج الكتاب = رقم الفصل) عبر قياس ارتفاعات
/// العناصر المبنية فعلياً، مع إمكانية القفز لفصل معين.
class EpubView extends StatefulWidget {
  final EpubDocument document;

  /// الفصل الافتتاحي (1-based) — لاستعادة آخر موضع قراءة.
  final int initialChapter;

  /// حجم خط النص — يغيّر إعادة القياس والتخطيط.
  final double fontSize;

  /// يُستدعى عند تغيّر الفصل الحالي (1-based).
  final ValueChanged<int> onChapterChanged;

  const EpubView({
    super.key,
    required this.document,
    required this.initialChapter,
    required this.fontSize,
    required this.onChapterChanged,
  });

  @override
  State<EpubView> createState() => EpubViewState();
}

class EpubViewState extends State<EpubView> {
  final ScrollController _scroll = ScrollController();
  final Map<int, double> _heights = {};
  late int _currentChapter;

  double get _avgHeight {
    if (_heights.isEmpty) return 800; // تقدير أولي قبل أي قياس
    return _heights.values.reduce((a, b) => a + b) / _heights.length;
  }

  /// الإزاحة التقديرية لبداية فصل — ارتفاعات معلومة + متوسط للباقي.
  double _offsetOf(int index) {
    var offset = 0.0;
    for (var i = 0; i < index; i++) {
      offset += _heights[i] ?? _avgHeight;
    }
    return offset;
  }

  @override
  void initState() {
    super.initState();
    _currentChapter =
        widget.initialChapter.clamp(1, widget.document.chapters.length);
    // قفز على مرحلتين: تقدير، ثم إعادة تقدير بعد بناء العناصر المجاورة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scroll.jumpTo(_offsetOf(_currentChapter - 1));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(_offsetOf(_currentChapter - 1));
      });
    });
  }

  @override
  void didUpdateWidget(EpubView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fontSize != widget.fontSize) {
      _heights.clear(); // تغيّر الخط يبطل كل القياسات
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// القفز لفصل (1-based) — يُستخدم من شاشة القراءة (أزرار التنقل).
  void jumpToChapter(int chapter) {
    final target = chapter.clamp(1, widget.document.chapters.length);
    _currentChapter = target;
    widget.onChapterChanged(target);
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_offsetOf(target - 1));
  }

  // ─── تمرير برمجي — للتمرير التلقائي (4.3) ────────────────────────────

  double get scrollOffset => _scroll.hasClients ? _scroll.offset : 0;

  double get maxScrollExtent =>
      _scroll.hasClients ? _scroll.position.maxScrollExtent : 0;

  /// تمرير فوري بمقدار dy بكسل (موجب = أسفل) — يُستدعى كل إطار من
  /// محرك التمرير المستمر في شاشة القراءة (بلا أنيميشن داخلي = بلا تقطيع).
  void scrollByJump(double dy) {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(
      (_scroll.offset + dy).clamp(0.0, _scroll.position.maxScrollExtent),
    );
  }

  void _onScroll(ScrollMetrics metrics) {
    final pixels = metrics.pixels;
    // الفصل الحالي = آخر فصل بدايته فوق حافة العرض + هامش تقدم
    var chapter = 0;
    for (var i = 0; i < widget.document.chapters.length; i++) {
      if (_offsetOf(i) <= pixels + 120) chapter = i + 1;
    }
    chapter = chapter.clamp(1, widget.document.chapters.length);
    if (chapter != _currentChapter) {
      _currentChapter = chapter;
      widget.onChapterChanged(chapter);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis == Axis.vertical) _onScroll(n.metrics);
        return false;
      },
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
        itemCount: widget.document.chapters.length,
        itemBuilder: (context, index) => _MeasuredChapter(
          index: index,
          onMeasured: (i, h) {
            if ((_heights[i] ?? 0) != h) _heights[i] = h;
          },
          child: _ChapterBody(
            chapter: widget.document.chapters[index],
            fontSize: widget.fontSize,
            textColor: theme.colorScheme.onSurface,
            accent: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// يبلّغ بارتفاع عنصر الفصل بعد اكتمال تخطيطه.
class _MeasuredChapter extends StatelessWidget {
  final int index;
  final void Function(int index, double height) onMeasured;
  final Widget child;

  const _MeasuredChapter({
    required this.index,
    required this.onMeasured,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = context.size;
      if (size != null) onMeasured(index, size.height);
    });
    return child;
  }
}

/// جسم الفصل: العنوان في الأعلى ثم الفقرات.
class _ChapterBody extends StatelessWidget {
  final EpubChapter chapter;
  final double fontSize;
  final Color textColor;
  final Color accent;

  const _ChapterBody({
    required this.chapter,
    required this.fontSize,
    required this.textColor,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final body = TextStyle(
      fontFamily: 'Amiri',
      fontSize: fontSize,
      height: 1.9,
      color: textColor,
    );
    final heading = body.copyWith(
      fontSize: fontSize * 1.15,
      fontWeight: FontWeight.w700,
    );

    final paragraphs = chapter.paragraphs
        .where((para) => !para.isTitle)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // عنوان الفصل — مفصول بمخطّط علوي وسفلي
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 2,
                color: accent.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 14),
              Text(
                chapter.title,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                style: body.copyWith(
                  fontSize: fontSize * 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: 48,
                height: 2,
                color: accent.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
        for (final para in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              para.text,
              textDirection: TextDirection.rtl,
              textAlign: para.isHeading ? TextAlign.center : TextAlign.right,
              style: para.isHeading ? heading : body,
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}
