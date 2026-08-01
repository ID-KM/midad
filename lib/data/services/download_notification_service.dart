import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// خدمة إشعارات تقدم التحميل — تُظهر إشعاراً في شريط الإشعارات
/// بشريط تقدم يتحدث لحظياً، ويبقى ظاهراً حتى لو غادر المستخدم
/// صفحة البحث وبحث عن كتاب آخر في نفس الوقت.
///
/// زر «إلغاء» في الإشعار يبث [cancelRequests] — الصفحة تستمع إليه
/// وتوقف التحميل المطابق للمعرّف.
class DownloadNotificationService {
  DownloadNotificationService._();

  static final DownloadNotificationService instance =
      DownloadNotificationService._();

  static const _channelId = 'downloads';
  static const _channelName = 'تحميل الكتب';

  /// بث طلبات الإلغاء القادمة من زر الإشعار — القيمة: معرّف الكتاب (identifier).
  final StreamController<String> _cancelController =
      StreamController<String>.broadcast();
  Stream<String> get cancelRequests => _cancelController.stream;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// تهيئة القناة — تُستدعى مرة واحدة عند بدء التطبيق.
  Future<void> init() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings: settings,
      // زر «إلغاء» في الإشعار — نمرر معرّف الكتاب في الـ payload
      onDidReceiveNotificationResponse: (response) {
        if (response.actionId == 'cancel' && response.payload != null) {
          _cancelController.add(response.payload!);
        }
      },
    );

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'تقدم تحميل الكتب من مكتبة الإنترنت',
      importance: Importance.low, // شريط تقدم بدون صوت/اهتزاز مزعج
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  /// طلب إذن الإشعارات (أندرويد 13+).
  Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// عرض إشعار تحميل جديد (أو تحديثه) بشريط تقدم.
  ///
  /// [id] معرّف ثابت لكل كتاب — التحديثات اللاحقة تستخدم نفس المعرّف
  /// فيُحدَّث نفس الإشعار بدل تكديس إشعارات متعددة.
  /// [progress] نسبة 0.0–1.0؛ [indeterminate] شريط بلا نسبة (قبل معرفة الحجم).
  /// [payload] معرّف الكتاب — يُرسَل مع زر «إلغاء» ليعرف التطبيق ماذا يوقف.
  Future<void> showDownloadProgress({
    required int id,
    required String title,
    required double progress,
    bool indeterminate = false,
    String? payload,
  }) async {
    await _plugin.show(
      id: id,
      title: 'تحميل «$title»',
      body: indeterminate ? 'جارٍ التحميل…' : '${(progress * 100).round()}%',
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'تقدم تحميل الكتب من مكتبة الإنترنت',
          importance: Importance.low,
          priority: Priority.low,
          showProgress: true,
          onlyAlertOnce: true,
          progress: ((progress * 100).round()).clamp(0, 100),
          indeterminate: indeterminate,
          // زر الإيقاف — المستخدم يستطيع إلغاء التحميل من الإشعار مباشرة
          actions: [
            AndroidNotificationAction('cancel', 'إلغاء',
                showsUserInterface: false, cancelNotification: true),
          ],
        ),
      ),
    );
  }

  /// إشعار نجاح التحميل — يُعرض بإيجاز ثم يُلغى تلقائياً.
  Future<void> showDownloaded({
    required int id,
    required String title,
  }) async {
    await _plugin.show(
      id: id,
      title: 'اكتمل تحميل «$title» ✅',
      body: 'أُضيف الكتاب إلى مكتبتك',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'تقدم تحميل الكتب من مكتبة الإنترنت',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          showProgress: false,
        ),
      ),
    );
    // يبقى الإشعار ثوانٍ ثم يُلغى ليترك الشريط نظيفاً
    await Future.delayed(const Duration(seconds: 4));
    await dismiss(id);
  }

  /// إشعار فشل التحميل.
  Future<void> showDownloadFailed({
    required int id,
    required String title,
    String? reason,
  }) async {
    await _plugin.show(
      id: id,
      title: 'فشل تحميل «$title»',
      body: reason ?? 'حدث خطأ أثناء التحميل',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'تقدم تحميل الكتب من مكتبة الإنترنت',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          showProgress: false,
        ),
      ),
    );
  }

  /// إلغاء إشعار — عند الفشل أو عند إعادة المحاولة.
  Future<void> dismiss(int id) => _plugin.cancel(id: id);
}
