import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../state/theme_controller.dart';

/// تبويب الإعدادات — المظهر (فاتح/داكن/AMOLED) + حماية العين.
/// سرعة التمرير الافتراضية تُفعَّل مع القارئ في Step 4.
class SettingsPage extends StatelessWidget {
  final ThemeController themeController;

  const SettingsPage({super.key, required this.themeController});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListenableBuilder(
        listenable: themeController,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionLabel(label: 'المظهر'),
              const SizedBox(height: 8),
              _SettingCard(
                children: [
                  for (final mode in AppThemeMode.values)
                    _ModeTile(
                      mode: mode,
                      selected: themeController.mode == mode,
                      onTap: () => themeController.setMode(mode),
                    ),
                  Divider(
                    height: 1,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                  ),
                  SwitchListTile(
                    value: themeController.eyeCareEnabled,
                    onChanged: themeController.setEyeCareEnabled,
                    secondary: const Icon(LucideIcons.eye),
                    title: const Text('حماية العين'),
                    subtitle: const Text('فلتر دافئ يريح العين'),
                  ),
                  if (themeController.eyeCareEnabled)
                    _EyeCareIntensitySlider(controller: themeController),
                ],
              ),
              const SizedBox(height: 20),
              _SectionLabel(label: 'القراءة'),
              const SizedBox(height: 8),
              _SettingCard(
                children: [
                  const ListTile(
                    enabled: false,
                    leading: Icon(LucideIcons.gauge),
                    title: Text('سرعة التمرير الافتراضية'),
                    subtitle: Text('عند تفعيل التمرير التلقائي في القارئ'),
                    trailing: Icon(LucideIcons.chevronLeft),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'التفضيلات تُحفظ تلقائياً في Step 3',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: Column(children: children),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final AppThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _ModeTile({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  IconData get _icon => switch (mode) {
        AppThemeMode.light => LucideIcons.sun,
        AppThemeMode.dark => LucideIcons.moon,
        AppThemeMode.amoled => LucideIcons.smartphone,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      leading: Icon(
        _icon,
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface.withValues(alpha: 0.7),
      ),
      title: Text(mode.label),
      trailing: selected
          ? Icon(LucideIcons.check, color: theme.colorScheme.primary)
          : Icon(
              LucideIcons.chevronLeft,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
    );
  }
}

class _EyeCareIntensitySlider extends StatelessWidget {
  final ThemeController controller;

  const _EyeCareIntensitySlider({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Icon(
            LucideIcons.sunset,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          Expanded(
            child: Slider(
              value: controller.eyeCareIntensity,
              onChanged: controller.setEyeCareIntensity,
              activeColor: AppColors.warmYellow,
              inactiveColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '${(controller.eyeCareIntensity * 100).round()}%',
              textAlign: TextAlign.end,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
