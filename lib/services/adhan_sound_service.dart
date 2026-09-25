import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'custom_sound_service.dart';

/// Represents one Adhan sound track from the remote API (or a local custom file)
class AdhanSound {
  final String key;
  final String nameAr;
  final String nameEn;
  final String url;
  final String? fajrUrl;

  /// True when [url] points to a local file on the device (custom sound)
  /// rather than a remote http(s) URL.
  final bool isLocal;

  const AdhanSound({
    required this.key,
    required this.nameAr,
    required this.nameEn,
    required this.url,
    this.fajrUrl,
    this.isLocal = false,
  });

  factory AdhanSound.fromJson(Map<String, dynamic> json) {
    return AdhanSound(
      key: json['key'] as String? ?? '',
      nameAr: json['nameAr'] as String? ?? '',
      nameEn: json['nameEn'] as String? ?? '',
      url: json['url'] as String? ?? '',
      fajrUrl: json['fajrUrl'] as String?,
    );
  }
}

/// Manages fetching, caching & playing adhan sounds from din.hk API.
/// Sounds are downloaded and stored locally so they work offline.
class AdhanSoundService extends ChangeNotifier {
  static const _apiUrl = 'https://din.hk/qadaa/athan/map.json';
  static const _keySelected = 'adhan_selected_key';

  List<AdhanSound> _sounds = [];
  String? _selectedKey;
  bool _loading = false;
  String? _error;
  final Set<String> _downloadedKeys = {};

  /// User-picked custom sound (local file), or null if none chosen.
  AdhanSound? _customSound;
  AdhanSound? get customSound => _customSound;

  final AudioPlayer _player = AudioPlayer();

  /// The custom sound (if any) always appears first, followed by remote sounds.
  List<AdhanSound> get sounds =>
      [?_customSound, ..._sounds];
  String? get selectedKey => _selectedKey;
  bool get loading => _loading;
  String? get error => _error;

  AdhanSound? get selectedSound {
    if (_selectedKey == null) return null;
    try {
      return _sounds.firstWhere((s) => s.key == _selectedKey);
    } catch (_) {
      return null;
    }
  }

  bool isDownloaded(String key) => _downloadedKeys.contains(key);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedKey = prefs.getString(_keySelected);
    _loadDownloadedList();
    await loadCustom();
    await fetchSounds();
    // Pre-download the selected sound (custom is already local)
    if (_selectedKey != null && _selectedKey != CustomSoundService.soundKey) {
      await downloadSound(_selectedKey!);
    }
  }

  /// Load the saved custom (device-picked) sound, if any, into the list.
  Future<void> loadCustom() async {
    final saved = await CustomSoundService.load();
    if (saved != null && File(saved.path).existsSync()) {
      _customSound = AdhanSound(
        key: CustomSoundService.soundKey,
        nameAr: saved.name,
        nameEn: 'Custom sound',
        url: saved.path,
        isLocal: true,
      );
    } else {
      _customSound = null;
    }
    notifyListeners();
  }

  /// Open the device picker, save the chosen file, select it, and return true
  /// on success.
  Future<bool> pickCustomFromDevice() async {
    final picked = await CustomSoundService.pickFromDevice();
    if (picked == null) return false;
    await loadCustom();
    await selectSound(CustomSoundService.soundKey);
    return _customSound != null;
  }

  void _loadDownloadedList() {
    final dirPath = _cacheDirPath;
    if (dirPath == null) return;
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;
    for (final f in dir.listSync()) {
      if (f is File) {
        final name = f.uri.pathSegments.last;
        if (name.endsWith('.mp3')) {
          _downloadedKeys.add(name.replaceAll('.mp3', ''));
        }
      }
    }
  }

  String? get _cacheDirPath {
    try {
      // Use a stable app-specific directory
      return '${Directory.systemTemp.parent.path}/app_flutter/adhan_cache';
    } catch (_) {
      return null;
    }
  }

  Future<String> _localPath(String key) async {
    await Directory(_cacheDirPath!).create(recursive: true);
    return '${_cacheDirPath!}/$key.mp3';
  }

  Future<String> _localFajrPath(String key) async {
    await Directory(_cacheDirPath!).create(recursive: true);
    return '${_cacheDirPath!}/${key}_fajr.mp3';
  }

  Future<void> fetchSounds() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await http.get(Uri.parse(_apiUrl));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final list = jsonDecode(res.body) as List;
      _sounds = list.map((e) => AdhanSound.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      _error = e.toString();
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> selectSound(String key) async {
    _selectedKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySelected, key);
    notifyListeners();
    // The custom sound is already a local file — nothing to download.
    if (key == CustomSoundService.soundKey) return;
    // Auto-download if not yet cached
    if (!_downloadedKeys.contains(key)) {
      await downloadSound(key);
    }
  }

  /// Download the sound file locally so it works offline.
  Future<void> downloadSound(String key) async {
    try {
      final sound = _sounds.firstWhere((s) => s.key == key);
      final dir = _cacheDirPath;
      if (dir == null) return;

      // Download main sound
      final localPath = await _localPath(key);
      final localFile = File(localPath);
      if (!localFile.existsSync()) {
        final res = await http.get(Uri.parse(sound.url));
        if (res.statusCode == 200) {
          await localFile.writeAsBytes(res.bodyBytes);
        }
      }

      // Download fajr variant if any
      if (sound.fajrUrl != null) {
        final fajrPath = await _localFajrPath(key);
        final fajrFile = File(fajrPath);
        if (!fajrFile.existsSync()) {
          final res = await http.get(Uri.parse(sound.fajrUrl!));
          if (res.statusCode == 200) {
            await fajrFile.writeAsBytes(res.bodyBytes);
          }
        }
      }

      _downloadedKeys.add(key);
      notifyListeners();
    } catch (_) {}
  }

  /// Get the local URI for a cached sound (or null if not downloaded)
  String? localUri(String key, {bool isFajr = false}) {
    if (!_downloadedKeys.contains(key)) return null;
    final suffix = isFajr ? '_fajr.mp3' : '.mp3';
    final p = '$_cacheDirPath/$key$suffix';
    if (File(p).existsSync()) return p;
    return null;
  }

  /// Play the currently selected adhan sound (or a specific one by key).
  /// Prefers local cached file, falls back to remote URL.
  Future<void> play({String? key, bool isFajr = false}) async {
    try {
      final k = key ?? _selectedKey;
      if (k == null) return;

      // Custom local sound picked from the device
      if (k == CustomSoundService.soundKey && _customSound != null) {
        await _player.setFilePath(_customSound!.url);
        await _player.play();
        return;
      }

      // Try local cached file first
      final local = localUri(k, isFajr: isFajr);
      if (local != null) {
        await _player.setFilePath(local);
        await _player.play();
        return;
      }

      // Fallback: stream from remote
      final sound = _sounds.firstWhere((s) => s.key == k);
      final url = (isFajr && sound.fajrUrl != null) ? sound.fajrUrl! : sound.url;

      await _player.setUrl(url);
      await _player.play();
    } catch (_) {}
  }

  Future<void> stop() async {
    try { await _player.stop(); } catch (_) {}
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
