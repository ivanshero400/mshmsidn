import 'package:flutter/services.dart';

/// Updates the home screen widget with current prayer times data
/// Uses method channel to communicate directly with native widget
class WidgetUpdateService {
  static const _channel = MethodChannel('fajr.din.hk/widget');

  /// Call this whenever prayer times change
  static Future<void> update({
    required String nextPrayer,
    required String remaining,
  }) async {
    try {
      await _channel.invokeMethod('updateWidget', {
        'next': nextPrayer,
        'remaining': remaining,
      });
    } catch (_) {}
  }
}
