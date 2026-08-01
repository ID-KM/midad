import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/models/archive_book.dart';
import '../../data/models/book_model.dart';
import '../../data/services/archive_service.dart';
import '../../data/services/download_notification_service.dart';
import '../../data/services/media_store_helper.dart';
import '../../state/library_store.dart';

/// صفحة مكتبة الإنترنت (Step 5) — بحث في Archive.org (PDF فقط،
/// محتوى الكبار محجوب) وتنزيل الكتاب وإضافته تلقائياً للمكتبة المحلية.
class OnlineSearchPage extends StatefulWidget {
  final LibraryStore store;
  final ArchiveService? service;

  const OnlineSearchPage({super.key, required this.store, this.service});

  @override
  State<OnlineSearchPage> createState() => _OnlineSearchPageState();
}

class _OnlineSearchPageState extends State<OnlineSearchPage> {
  /// البحث التلقائي: ينتظر 600ms بعد آخر حرف، ويشترط 3 أحرف على الأقل.
  static const _debounceDuration = Duration(milliseconds: 600);
  static const _minQueryLength = 3;

  late final ArchiveService _service;
  final _controller = TextEditingController();

  Timer? _debounce;
  int _searchSeq = 0; // يبطل نتائج بحث قديم عند سباق الطلبات

  List<ArchiveBook>? _results;
  bool _searching = false;
  String? _searchError;

  final Set<String> _downloading = {};
  final Map<String, double> _progress = {};
  final Map<String, String> _errors = {};

  /// الكتب التي طلب المستخدم إيقاف تحميلها — تُفحص في كل دفعة.
  final Set<String> _cancelRequested = {};
  StreamSubscription<String>? _cancelSub;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ArchiveService();
    // الاستماع لزر «إلغاء» في شريط الإشعارات — يوقف التحميل حتى لو
    // كان المستخدم في صفحة أخرى من التطبيق.
    _cancelSub = DownloadNotificationService.instance.cancelRequests
        .listen(_cancelByIdentifier);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cancelSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// إيقاف تحميل كتاب — يُفحص علمه في الدفعة التالية فيتوقف التحميل
  /// ويُحذف الملف الجزئي. [fromNotification] يوقف الإشعار أيضاً.
  void _cancelByIdentifier(String identifier) {
    if (!_downloading.contains(identifier)) return;
    setState(() => _cancelRequested.add(identifier));
    DownloadNotificationService.instance.dismiss(identifier.hashCode & 0x7fffffff);
  }

  /// كل حرف يكتبه المستخدم: يعيد ضبط المؤقت — يبحث بعد التوقف 600ms.
  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < _minQueryLength) {
      if (_results != null || _searchError != null || _searching) {
        _searchSeq++; // يبطل أي بحث قيد التنفيذ
        setState(() {
          _results = null;
          _searchError = null;
          _searching = false;
        });
      }
      return;
    }
    setState(() {}); // لتحديث زر المسح (ظهور/اختفاء)
    _debounce = Timer(_debounceDuration, _search);
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.length < _minQueryLength) return;
    final seq = ++_searchSeq;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await _service.search(query);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _searchError = e.toString();
        _searching = false;
      });
    }
  }

  void _clear() {
    _debounce?.cancel();
    _searchSeq++;
    _controller.clear();
    setState(() {
      _results = null;
      _searchError = null;
      _searching = false;
    });
  }

  Future<void> _download(ArchiveBook book) async {
    if (_downloading.contains(book.identifier)) return;
    if (widget.store.books.any((b) => b.title == book.title)) {
      _snack('«${book.title}» موجود بالفعل في مكتبتك');
      return;
    }
    setState(() {
      _downloading.add(book.identifier);
      _progress[book.identifier] = 0;
      _errors.remove(book.identifier);
    });
    final notifications = DownloadNotificationService.instance;
    final noteId = book.identifier.hashCode & 0x7fffffff;
    try {
      // إشعار البداية — شريط غير محدد حتى نعرف حجم الملف
      await notifications.showDownloadProgress(
        id: noteId,
        title: book.title,
        progress: 0,
        indeterminate: true,
        payload: book.identifier,
      );
      final pdfName = await _service.fetchPdfFileName(book.identifier);
      if (pdfName == null) {
        throw const ArchiveException('لا يوجد ملف PDF فعلي لهذا الكتاب');
      }
      final dir = await getApplicationSupportDirectory();
      final safeName = _safeFileName(book.title);
      final path = '${dir.path}/books/$safeName.pdf';
      await _service.downloadPdf(
        identifier: book.identifier,
        pdfName: pdfName,
        targetPath: path,
        // الإيقاف: يفحص في كل دفعة — عند طلب الإلغاء يُحذف الملف الجزئي
        isCancelled: () => _cancelRequested.contains(book.identifier),
        onProgress: (p) {
          if (mounted) setState(() => _progress[book.identifier] = p);
          // تحديث الإشعار — يبقى ظاهراً حتى لو بحث المستخدم عن كتاب آخر
          notifications.showDownloadProgress(
            id: noteId,
            title: book.title,
            progress: p,
            payload: book.identifier,
          );
        },
      );
      // انقل الكتاب إلى مجلد عام يظهر في مدير الملفات (Download/مداد).
      // عند الفشل (جهاز قديم) يبقى في التخزين الخاص — الكتاب يعمل لكنه مخفي.
      String filePath = path;
      try {
        final publicPath = await MediaStoreHelper.saveToDownloads(
          srcPath: path,
          fileName: '$safeName.pdf',
        );
        final privateFile = File(path);
        if (privateFile.existsSync()) privateFile.deleteSync();
        filePath = publicPath;
      } catch (_) {
        // الأجهزة قبل أندرويد 10 لا تدعم MediaStore — نُبقي المسار الخاص
      }
      // الغلاف يُنزَّل مع الكتاب ويُحفظ محلياً — فشله لا يُسقط الكتاب
      String? coverPath;
      try {
        final coverTarget = '${dir.path}/books/$safeName.jpg';
        await _service.downloadCover(
          identifier: book.identifier,
          targetPath: coverTarget,
        );
        coverPath = coverTarget;
      } catch (_) {
        coverPath = null; // الكتاب يُضاف بلا غلاف — المكتبة تعرض بديلاً
      }
      final added = await widget.store.addDownloadedBook(
        title: book.title,
        filePath: filePath,
        fileType: BookFileType.pdf,
        coverPath: coverPath,
      );
      if (!mounted) return;
      _snack(added
          ? 'تم التنزيل وإضافة «${book.title}» إلى مكتبتك'
          : 'الكتاب موجود بالفعل في مكتبتك');
      // إشعار الاكتمال — يُعرض ثم يُلغى تلقائياً
      await notifications.showDownloaded(id: noteId, title: book.title);
    } on ArchiveCancelledException {
      // إلغاء متعمد من المستخدم — لا نعرضه كخطأ، فقط نؤكد الإيقاف
      if (!mounted) return;
      _snack('تم إيقاف تحميل «${book.title}»');
    } catch (e) {
      if (!mounted) return;
      setState(() => _errors[book.identifier] = e.toString());
      // إشعار الفشل — يبقى ليعرف المستخدم سبب التوقف
      await notifications.showDownloadFailed(
        id: noteId,
        title: book.title,
        reason: e.toString(),
      );
    } finally {
      _cancelRequested.remove(book.identifier);
      if (mounted) {
        setState(() => _downloading.remove(book.identifier));
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 84),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('مكتبة الإنترنت')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              onSubmitted: (_) {
                FocusScope.of(context).unfocus();
                _search();
              },
              decoration: InputDecoration(
                hintText: 'ابحث في أرشيف الإنترنت...',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  fontSize: 14,
                ),
                prefixIcon: Icon(
                  LucideIcons.search,
                  size: 20,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _clear,
                        icon: Icon(
                          LucideIcons.x,
                          size: 18,
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        tooltip: 'مسح',
                      ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final results = _results;
    if (results == null) {
      if (_searching) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_searchError != null) {
        return _StatusMessage(
          icon: LucideIcons.wifiOff,
          title: _searchError!,
          action:
              TextButton(onPressed: _search, child: const Text('إعادة المحاولة')),
        );
      }
      return const _StatusMessage(
        icon: LucideIcons.globe,
        title: 'ابحث عن كتاب — النتائج PDF فقط',
        subtitle: 'اكتب 3 أحرف على الأقل وتظهر النتائج تلقائياً — محتوى الكبار محجوب، والتنزيل يضيف الكتاب لمكتبتك',
      );
    }
    if (results.isEmpty && !_searching) {
      return const _StatusMessage(
        icon: LucideIcons.searchX,
        title: 'لا توجد نتائج مطابقة',
        subtitle: 'جرّب كلمة أخرى أو تحقق من الإملاء',
      );
    }
    final list = ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _ResultCard(
        book: results[index],
        downloading: _downloading.contains(results[index].identifier),
        progress: _progress[results[index].identifier] ?? 0,
        error: _errors[results[index].identifier],
        onDownload: () => _download(results[index]),
        onCancel: () => _cancelByIdentifier(results[index].identifier),
      ),
    );
    if (!_searching) return list;
    // بحث جديد جارٍ والنتائج السابقة ظاهرة — شريط رفيع فقط
    return Column(
      children: [
        const LinearProgressIndicator(minHeight: 2),
        Expanded(child: list),
      ],
    );
  }
}

/// بطاقة نتيجة بحث — عنوان + مؤلف/سنة + زر تنزيل مع تقدم وإيقاف.
class _ResultCard extends StatelessWidget {
  final ArchiveBook book;
  final bool downloading;
  final double progress;
  final String? error;
  final VoidCallback onDownload;
  final VoidCallback onCancel;

  const _ResultCard({
    required this.book,
    required this.downloading,
    required this.progress,
    required this.error,
    required this.onDownload,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الغلاف من الأرشيف — مع بديل عند تعذر التحميل
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  book.coverUrl,
                  width: 52,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 52,
                    height: 72,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      LucideIcons.bookOpen,
                      size: 22,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    if (book.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        book.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                    if (book.description != null &&
                        book.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        book.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (downloading)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                    // زر إيقاف التحميل — يحذف الملف الجزئي ويلغي الإشعار
                    IconButton(
                      onPressed: onCancel,
                      icon: Icon(
                        LucideIcons.square,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                      tooltip: 'إيقاف التحميل',
                    ),
                  ],
                )
              else
                IconButton(
                  onPressed: onDownload,
                  icon: Icon(
                    LucideIcons.download,
                    size: 22,
                    color: theme.colorScheme.primary,
                  ),
                  tooltip: 'تنزيل PDF وإضافته للمكتبة',
                ),
            ],
          ),
          if (downloading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor:
                    theme.colorScheme.onSurface.withValues(alpha: 0.08),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'جاري التنزيل... ${(progress * 100).round()}%',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  LucideIcons.alertCircle,
                  size: 15,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// رسالة حالة مركزية (بداية/فارغ/خطأ).
class _StatusMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const _StatusMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.15)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 10), action!],
          ],
        ),
      ),
    );
  }
}

/// اسم ملف آمن — نزيل فقط المحارف الخطرة على المسارات، ونُبقي العربية.
String _safeFileName(String title) {
  final cleaned =
      title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').trim();
  return cleaned.isEmpty ? 'book' : cleaned;
}
