import 'dart:async';
import 'package:flutter/services.dart';

/// Schedules exact alarms for prayer times via native AlarmManager.
///
/// The actual scheduling lives natively in `AlarmScheduler.kt`, which reads the
/// prayer times Flutter already persisted to SharedPreferences and arms the
/// NEXT occurrence of every prayer. Because the native side re-arms itself
/// after each fire and after every reboot, the adhan keeps working in the
/// background permanently — even if this Flutter app is never opened again.
class AdhanAlarmService {
  static const _channel = MethodChannel('azan.adhan.alarm_scheduler');
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
  }

  /// (Re)arm all prayer alarms. Idempotent and cheap — call it whenever prayer
  /// times change (settings change, daily refresh, app open) to keep the native
  /// schedule in sync with the exact computed times.
  ///
  /// [prayers] is accepted for API compatibility; the native side reads the
  /// canonical times straight from SharedPreferences (`prayer_times_json`).
  static Future<void> schedulePrayerAlarms(
    List<Map<String, String>> prayers, {
    String soundKey = '',
  }) async {
    try {
      await _channel.invokeMethod('rescheduleAll');
    } catch (e) {
      // Fallback: silent fail — the notification system handles it
    }
  }

}
