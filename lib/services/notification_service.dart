import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages prayer time notifications using flutter_local_notifications
class NotificationService {
  static const _keyEnabled = 'notif_enabled';
  static const _keyPermissionAsked = 'notif_perm_asked';
  static const _channelId = 'prayer_channel';
  static const _channelName = 'أوقات الصلاة';
  static const _channelDesc = 'إشعارات دخول وقت الصلاة';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;
  static bool _enabled = true;

  static bool get isEnabled => _enabled;
  static bool get isReady => _ready;

  /// Set by the app shell: called with the route payload when the user taps
  /// a notification (e.g. '/learn/travel').
  static void Function(String route)? onTapRoute;

  // ── Init ──

  static Future<void> init() async {
    if (_ready) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.startsWith('/')) {
          onTapRoute?.call(payload);
        }
      },
    );

    // Create Android channel (importance = high = heads-up)
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_keyEnabled) ?? true;
    _ready = true;
  }

  static Future<void> setEnabled(bool v) async {
    _enabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, v);
    if (!v) await _plugin.cancelAll();
  }

  static Future<bool> get wasPermissionAsked async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyPermissionAsked) ?? false;
  }

  static Future<void> markPermissionAsked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPermissionAsked, true);
  }

  /// Request notification permission (Android 13+).
  static Future<void> requestNotification() async {
    try {
      await _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
    await markPermissionAsked();
  }

  /// Show an immediate notification. [payload] is a route ('/learn/travel')
  /// opened when the user taps it.
  static Future<void> showImmediate(String title, String body,
      {String? payload}) async {
    if (!_ready) await init();
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
    );
    await _plugin.show(99, title, body,
        const NotificationDetails(android: androidDetails),
        payload: payload);
  }

  // ── Schedule all 5 daily prayers ──

  static const Map<String, String> _arNames = {
    'FAJR': 'الفجر',
    'SUNRISE': 'الشروق',
    'DHUHR': 'الظهر',
    'ASR': 'العصر',
    'MAGHRIB': 'المغرب',
    'ISHA': 'العشاء',
  };

  /// Call this whenever prayer times change (after API fetch or settings change)
  static Future<void> scheduleAll(List<Map<String, String>> prayers) async {
    if (!_ready) await init();
    if (!_enabled) return;

    await _plugin.cancelAll();

    final now = DateTime.now();
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
    );
    const details = NotificationDetails(android: androidDetails);

    for (int i = 0; i < prayers.length; i++) {
      final name = prayers[i]['name']!;
      if (name == 'SUNRISE') continue;

      final parts = prayers[i]['time']!.split(':');
      final target = DateTime(
        now.year, now.month, now.day,
        int.parse(parts[0]), int.parse(parts[1]),
      );

      final delay = target.difference(now);

      if (delay.inSeconds > 0 && delay.inHours < 24) {
        final arName = _arNames[name] ?? name;
        Timer(delay, () async {
          await _plugin.show(
            i,
            '🕌 حان وقت الصلاة',
            'دخل وقت صلاة $arName',
            details,
          );
        });
      }
    }
  }
}
