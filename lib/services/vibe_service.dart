import 'package:shared_preferences/shared_preferences.dart';

/// Per-prayer vibration behaviour for the adhan.
///
///  • [off]       — adhan plays with sound only, no vibration (default).
///  • [withAdhan] — adhan plays AND the phone vibrates.
///  • [only]      — vibration only; the adhan SOUND is suppressed for this
///                  prayer (useful in meetings / mosques).
enum VibeMode { off, withAdhan, only }

class VibeService {
  static String _key(String prayer) => 'vibe_mode_$prayer';

  static VibeMode _decode(String? s) {
    switch (s) {
      case 'with':
        return VibeMode.withAdhan;
      case 'only':
        return VibeMode.only;
      default:
        return VibeMode.off;
    }
  }

  static String encode(VibeMode m) {
    switch (m) {
      case VibeMode.withAdhan:
        return 'with';
      case VibeMode.only:
        return 'only';
      case VibeMode.off:
        return 'off';
    }
  }

  static Future<VibeMode> get(String prayer) async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_key(prayer)));
  }

  /// Synchronous decode from an already-loaded prefs instance.
  static VibeMode getFrom(SharedPreferences prefs, String prayer) =>
      _decode(prefs.getString(_key(prayer)));

  static Future<void> set(String prayer, VibeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(prayer), encode(mode));
  }

  /// off → with → only → off
  static VibeMode next(VibeMode m) {
    switch (m) {
      case VibeMode.off:
        return VibeMode.withAdhan;
      case VibeMode.withAdhan:
        return VibeMode.only;
      case VibeMode.only:
        return VibeMode.off;
    }
  }

  static String label(VibeMode m) {
    switch (m) {
      case VibeMode.off:
        return 'بدون اهتزاز';
      case VibeMode.withAdhan:
        return 'اهتزاز مع الأذان';
      case VibeMode.only:
        return 'اهتزاز فقط (بدون صوت)';
    }
  }
}
