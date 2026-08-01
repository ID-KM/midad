import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../state/notes_store.dart';

/// القائمة الجانبية للملاحظات (4.4) — تعرض ملاحظات الكتاب الحالي
/// مرتبة برقم الصفحة، مع إضافة ملاحظة على الصفحة الحالية، وحذف،
/// والقفز الفوري لصفحة الملاحظة عند النقر عليها.
class NotesDrawer extends StatelessWidget {
  final NotesStore store;
  final int currentPage;
  final ValueChanged<int> onJumpToPage;

  const NotesDrawer({
    super.key,
    required this.store,
    required this.currentPage,
    required this.onJumpToPage,
  });

  Future<void> _addNote(BuildContext context) async {
    final controller = TextEditingController();
    final theme = Theme.of(context);
    final content = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(LucideIcons.stickyNote,
                size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('ملاحظة على صفحة $currentPage'),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(
            hintText: 'اكتب ملاحظتك...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (content == null || content.trim().isEmpty) return;
    await store.addNote(pageNumber: currentPage, content: content);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return Drawer(
      width: 320,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final notes = store.notes;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      Icon(LucideIcons.stickyNote,
                          size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'الملاحظات',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton.filledTonal(
                        onPressed: () => _addNote(context),
                        icon: const Icon(LucideIcons.plus, size: 18),
                        tooltip: 'إضافة ملاحظة على الصفحة الحالية',
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (notes.isEmpty)
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.stickyNote,
                              size: 48,
                              color:
                                  theme.colorScheme.onSurface.withValues(alpha: 0.15),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'لا توجد ملاحظات بعد',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: muted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'اضغط + لإضافة ملاحظة على هذه الصفحة',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      itemCount: notes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.08),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => onJumpToPage(note.pageNumber),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'صفحة ${note.pageNumber}',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      note.content,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      textDirection: TextDirection.rtl,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(height: 1.4),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => store.deleteNote(note.id),
                                    icon: Icon(
                                      LucideIcons.trash2,
                                      size: 16,
                                      color: theme.colorScheme.error
                                          .withValues(alpha: 0.7),
                                    ),
                                    tooltip: 'حذف الملاحظة',
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
