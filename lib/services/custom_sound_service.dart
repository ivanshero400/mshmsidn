import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lets the user pick ANY audio file from their device to use as the adhan.
///
/// The chosen file is copied by the native side (via the Storage Access
/// Framework) into the app's private storage, so it keeps working offline and
/// forever — even after the original file is moved or the picker permission
/// expires. Supports every audio format the device can decode (mp3, m4a, aac,
/// ogg, wav, flac, opus…).
class CustomSoundService {
  static const _channel = MethodChannel('azan.custom_sound');
  static const keyPath = 'custom_adhan_path';
  static const keyName = 'custom_adhan_name';

  /// Special sound key used across the app for the user's custom file.
  static const soundKey = '__custom__';

  /// Requests audio-access permission (READ_MEDIA_AUDIO on Android 13+, or
  /// READ_EXTERNAL_STORAGE below). Returns true if access is usable. The
  /// system document picker itself works without this, but we ask explicitly
  /// so the user is aware the app is reading a media file.
  static Future<bool> ensurePermission() async {
    if (!Platform.isAndroid) return true;
    // Permission.audio maps to READ_MEDIA_AUDIO on API 33+, and to storage
    // read on older versions.
    var status = await Permission.audio.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }
    status = await Permission.audio.request();
    if (status.isGranted || status.isLimited) return true;
    // On some OS versions storage read is the relevant one.
    if (status.isDenied) {
      final storage = await Permission.storage.request();
      return storage.isGranted;
    }
    return false;
  }

  /// Opens the system audio picker. Returns the saved local path + display
  /// name, or null if the user cancelled, denied permission, or it failed.
  static Future<({String path, String name})?> pickFromDevice() async {
    // Ask for audio access first (requested at pick time, as the user wants).
    final allowed = await ensurePermission();
    if (!allowed) return null;
    try {
      final result = await _channel.invokeMethod<Map>('pickAudio');
      if (result == null) return null;
      final path = result['path'] as String?;
      final name = (result['name'] as String?)?.trim();
      if (path == null || path.isEmpty) return null;

      final displayName = (name == null || name.isEmpty) ? 'الصوت المخصص' : name;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyPath, path);
      await prefs.setString(keyName, displayName);
      return (path: path, name: displayName);
    } catch (_) {
      return null;
    }
  }

  /// The currently saved custom sound, or null if none was ever picked.
  static Future<({String path, String name})?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(keyPath);
    if (path == null || path.isEmpty) return null;
    return (path: path, name: prefs.getString(keyName) ?? 'الصوت المخصص');
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyPath);
    await prefs.remove(keyName);
  }
}
