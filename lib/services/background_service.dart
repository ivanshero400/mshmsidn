import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Background service that handles prayer time notifications.
/// Uses a Timer loop to check prayer times every minute and fire notifications.
class BackgroundPrayerService {
  static bool _running = false;
  static Timer? _timer;

  static const _channelId = 'prayer_channel';
  static const _channelName = 'أوقات الصلاة';
  static const _channelDesc = 'إشعارات دخول وقت الصلاة';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Start the background notification checker
  static Future<void> start() async {
    if (_running) return;
    _running = true;

    // Initialize the notification plugin
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _plugin.initialize(settings);

    const channel = AndroidNotificationChannel(
      _channelId, _channelName,
      description: _channelDesc,
      importance: Importance.high,
      playSound: true, enableVibration: true,
    );
    await _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);

    // Start checking every 60 seconds
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _checkAndNotify());
  }

  static void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Check if any prayer time has just passed and fire a notification
  static Future<void> _checkAndNotify() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timesJson = prefs.getString('prayer_times_json');
      if (timesJson == null) return;

      // Parse saved times
      final List<dynamic> list = _parseJson(timesJson);
      if (list.isEmpty) return;

      final now = DateTime.now();
      final currentMinute = now.hour * 60 + now.minute;

      for (int i = 0; i < list.length; i++) {
        final name = list[i]['name'] as String? ?? '';
        if (name == 'SUNRISE') continue;

        final timeStr = list[i]['time'] as String? ?? '--:--';
        final parts = timeStr.split(':');
        final prayerMinute = int.parse(parts[0]) * 60 + int.parse(parts[1]);

        // Fire notification exactly at prayer time
        if (prayerMinute == currentMinute) {
          const androidDetails = AndroidNotificationDetails(
            _channelId, _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true, enableVibration: true, autoCancel: true,
          );
          await _plugin.show(
            i, '🕌 حان وقت الصلاة', 'دخل وقت صلاة $name',
            const NotificationDetails(android: androidDetails),
          );
        }
      }
    } catch (_) {
      // Silently ignore errors in background
    }
  }

  static List<dynamic> _parseJson(String json) {
    // Simple manual parsing to avoid dart:convert import issues
    final result = <Map<String, String>>[];
    try {
      // Quick check: use regex to extract name/time pairs
      final regex = RegExp(r'"name":"([^"]+)".*?"time":"([^"]+)"');
      for (final match in regex.allMatches(json)) {
        result.add({'name': match.group(1)!, 'time': match.group(2)!});
      }
    } catch (_) {}
    return result;
  }
}
