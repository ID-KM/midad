import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_theme.dart';

/// التحكم بالمظهر — وضع الثيم وحماية العين.
/// التفضيلات محفوظة عبر shared_preferences وتُستعاد عند كل تشغيل.
class ThemeController extends ChangeNotifier {
  static const _kMode = 'theme_mode';
  static const _kEyeCare = 'eye_care_enabled';
  static const _kEyeCareIntensity = 'eye_care_intensity';

  AppThemeMode _mode = AppThemeMode.light;
  AppThemeMode get mode => _mode;

  bool _eyeCareEnabled = false;
  bool get eyeCareEnabled => _eyeCareEnabled;

  double _eyeCareIntensity = 0.6;
  double get eyeCareIntensity => _eyeCareIntensity;

  /// استعادة التفضيلات المحفوظة. تُستدعى مرة واحدة عند بدء التشغيل.
  /// تفشل بصمت (اختبارات/بيئة بلا تخزين) وتبقي القيم الافتراضية.
  Future<void> loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = AppThemeMode.values.asNameMap()[prefs.getString(_kMode)] ??
          AppThemeMode.light;
      _eyeCareEnabled = prefs.getBool(_kEyeCare) ?? false;
      _eyeCareIntensity = (prefs.getDouble(_kEyeCareIntensity) ?? 0.6)
          .clamp(0.0, 1.0);
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ تعذّر استعادة التفضيلات: $e');
    }
  }

  void setMode(AppThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _saveString(_kMode, mode.name);
    notifyListeners();
  }

  void setEyeCareEnabled(bool enabled) {
    if (_eyeCareEnabled == enabled) return;
    _eyeCareEnabled = enabled;
    _saveBool(_kEyeCare, enabled);
    notifyListeners();
  }

  void setEyeCareIntensity(double intensity) {
    final clamped = intensity.clamp(0.0, 1.0);
    if (_eyeCareIntensity == clamped) return;
    _eyeCareIntensity = clamped;
    _saveDouble(_kEyeCareIntensity, clamped);
    notifyListeners();
  }

  Future<void> _saveString(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (e) {
      debugPrint('⚠️ فشل حفظ $key: $e');
    }
  }

  Future<void> _saveBool(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      debugPrint('⚠️ فشل حفظ $key: $e');
    }
  }

  Future<void> _saveDouble(String key, double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(key, value);
    } catch (e) {
      debugPrint('⚠️ فشل حفظ $key: $e');
    }
  }
}
