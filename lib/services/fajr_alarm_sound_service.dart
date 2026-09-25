import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adhan_sound_service.dart';
import 'custom_sound_service.dart';

enum FajrAlarmSoundMode { recording, file, generated, adhan }

extension FajrAlarmSoundModeLabels on FajrAlarmSoundMode {
  String get storageKey {
    switch (this) {
      case FajrAlarmSoundMode.recording:
        return 'recording';
      case FajrAlarmSoundMode.file:
        return 'file';
      case FajrAlarmSoundMode.generated:
        return 'generated';
      case FajrAlarmSoundMode.adhan:
        return 'adhan';
    }
  }

  String get arabicLabel {
    switch (this) {
      case FajrAlarmSoundMode.recording:
        return 'تسجيل صوت مخصص';
      case FajrAlarmSoundMode.file:
        return 'اختيار من الملفات';
      case FajrAlarmSoundMode.generated:
        return 'توليدي';
      case FajrAlarmSoundMode.adhan:
        return 'أذان';
    }
  }

  static FajrAlarmSoundMode fromStorage(String? value) {
    for (final mode in FajrAlarmSoundMode.values) {
      if (mode.storageKey == value) return mode;
    }
    return FajrAlarmSoundMode.generated;
  }
}

class FajrAlarmSoundConfig {
  final FajrAlarmSoundMode mode;
  final String? filePath;
  final String? fileName;
  final String? recordingPath;
  final String? recordingName;

  const FajrAlarmSoundConfig({
    this.mode = FajrAlarmSoundMode.generated,
    this.filePath,
    this.fileName,
    this.recordingPath,
    this.recordingName,
  });

  String get displayName {
    switch (mode) {
      case FajrAlarmSoundMode.recording:
        return recordingName ?? 'تسجيل صوت مخصص';
      case FajrAlarmSoundMode.file:
        return fileName ?? 'ملف صوتي';
      case FajrAlarmSoundMode.generated:
        return 'أصوات توليدية عشوائية';
      case FajrAlarmSoundMode.adhan:
        return 'الأذان الافتراضي';
    }
  }

  Map<String, Object?> toJson() {
    return {
      'mode': mode.storageKey,
      'label': mode.arabicLabel,
      'displayName': displayName,
      'filePath': filePath,
      'fileName': fileName,
      'recordingPath': recordingPath,
      'recordingName': recordingName,
    };
  }
}

class FajrAlarmSoundService extends ChangeNotifier {
  static const _pickerChannel = MethodChannel('azan.custom_sound');
  static const _alarmChannel = MethodChannel('azan.adhan.alarm');

  static const _keyMode = 'fajr_alarm_sound_mode';
  static const _keyFilePath = 'fajr_alarm_sound_file_path';
  static const _keyFileName = 'fajr_alarm_sound_file_name';
  static const _keyRecordingPath = 'fajr_alarm_sound_recording_path';
  static const _keyRecordingName = 'fajr_alarm_sound_recording_name';

  final AudioPlayer _player = AudioPlayer();

  FajrAlarmSoundConfig _config = const FajrAlarmSoundConfig();
  bool _loaded = false;
  bool _playing = false;

  FajrAlarmSoundConfig get config => _config;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _config = FajrAlarmSoundConfig(
      mode: FajrAlarmSoundModeLabels.fromStorage(prefs.getString(_keyMode)),
      filePath: _readStoredString(prefs, _keyFilePath),
      fileName: _readStoredString(prefs, _keyFileName),
      recordingPath: _readStoredString(prefs, _keyRecordingPath),
      recordingName: _readStoredString(prefs, _keyRecordingName),
    );
    _loaded = true;
    notifyListeners();
  }

  Future<void> setGenerated() async {
    await ensureLoaded();
    _config = FajrAlarmSoundConfig(
      mode: FajrAlarmSoundMode.generated,
      filePath: _config.filePath,
      fileName: _config.fileName,
      recordingPath: _config.recordingPath,
      recordingName: _config.recordingName,
    );
    await _persist();
  }

  Future<void> setAdhan() async {
    await ensureLoaded();
    _config = FajrAlarmSoundConfig(
      mode: FajrAlarmSoundMode.adhan,
      filePath: _config.filePath,
      fileName: _config.fileName,
      recordingPath: _config.recordingPath,
      recordingName: _config.recordingName,
    );
    await _persist();
  }

  Future<void> setFile({required String path, required String name}) async {
    await ensureLoaded();
    _config = FajrAlarmSoundConfig(
      mode: FajrAlarmSoundMode.file,
      filePath: path,
      fileName: name,
      recordingPath: _config.recordingPath,
      recordingName: _config.recordingName,
    );
    await _persist();
  }

  Future<void> setRecording({required String path, required String name}) async {
    await ensureLoaded();
    _config = FajrAlarmSoundConfig(
      mode: FajrAlarmSoundMode.recording,
      filePath: _config.filePath,
      fileName: _config.fileName,
      recordingPath: path,
      recordingName: name,
    );
    await _persist();
  }

  Future<({String path, String name})?> pickFileFromDevice() async {
    final allowed = await CustomSoundService.ensurePermission();
    if (!allowed) return null;
    try {
      final result = await _pickerChannel.invokeMethod<Map>('pickAlarmAudio');
      final picked = _parseNativeAudio(result, fallbackName: 'صوت المنبه');
      if (picked == null) return null;
      await setFile(path: picked.path, name: picked.name);
      return picked;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> ensureMicrophonePermission() async {
    if (!Platform.isAndroid) return true;
    var status = await Permission.microphone.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }
    status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> startRecording() async {
    final allowed = await ensureMicrophonePermission();
    if (!allowed) return false;
    try {
      await _pickerChannel.invokeMethod<Map>('startAlarmRecording');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<({String path, String name})?> stopRecording() async {
    try {
      final result = await _pickerChannel.invokeMethod<Map>(
        'stopAlarmRecording',
      );
      final recorded = _parseNativeAudio(
        result,
        fallbackName: 'تسجيل صوت مخصص',
      );
      if (recorded == null) return null;
      await setRecording(path: recorded.path, name: recorded.name);
      return recorded;
    } catch (_) {
      return null;
    }
  }

  Future<void> cancelRecording() async {
    try {
      await _pickerChannel.invokeMethod<void>('cancelAlarmRecording');
    } catch (_) {}
  }

  Future<void> startPlayback() async {
    await ensureLoaded();
    await _startNativeVolumeGuard();
    try {
      await _player.stop();
      await _player.setVolume(1);
      await _player.setLoopMode(LoopMode.one);

      final configured = await _setConfiguredSource();
      if (!configured) {
        await _player.setAudioSource(
          _AlarmGeneratedWavSource(_generateAlarmWav()),
          preload: true,
        );
      }
      await _player.play();
      _playing = true;
    } catch (_) {
      _playing = false;
      await stopPlayback();
    }
  }

  Future<void> setTemporarilyMuted(bool muted) async {
    try {
      if (muted) {
        await _player.pause();
      } else if (_playing) {
        await _player.play();
      }
    } catch (_) {}
  }

  Future<void> stopPlayback({bool restoreVolume = true}) async {
    _playing = false;
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _alarmChannel.invokeMethod<void>('stopAlarmAudioGuard', {
        'restore': restoreVolume,
      });
    } catch (_) {}
  }

  Future<bool> _setConfiguredSource() async {
    switch (_config.mode) {
      case FajrAlarmSoundMode.recording:
        final path = _config.recordingPath;
        if (path != null && File(path).existsSync()) {
          await _player.setFilePath(path);
          return true;
        }
        return false;
      case FajrAlarmSoundMode.file:
        final path = _config.filePath;
        if (path != null && File(path).existsSync()) {
          await _player.setFilePath(path);
          return true;
        }
        return false;
      case FajrAlarmSoundMode.generated:
        await _player.setAudioSource(
          _AlarmGeneratedWavSource(_generateAlarmWav()),
          preload: true,
        );
        return true;
      case FajrAlarmSoundMode.adhan:
        return _setAdhanSource();
    }
  }

  Future<bool> _setAdhanSource() async {
    final service = AdhanSoundService();
    try {
      await service.init();
      if (service.sounds.isEmpty) return false;
      final key = service.selectedKey ?? service.sounds.first.key;
      final sound = service.sounds.firstWhere(
        (candidate) => candidate.key == key,
        orElse: () => service.sounds.first,
      );
      if (sound.isLocal) {
        await _player.setFilePath(sound.url);
        return true;
      }

      final local =
          service.localUri(sound.key, isFajr: true) ?? service.localUri(sound.key);
      if (local != null) {
        await _player.setFilePath(local);
        return true;
      }

      final url = sound.fajrUrl ?? sound.url;
      if (url.isEmpty) return false;
      await _player.setUrl(url);
      return true;
    } catch (_) {
      return false;
    } finally {
      service.dispose();
    }
  }

  ({String path, String name})? _parseNativeAudio(
    Map<dynamic, dynamic>? result, {
    required String fallbackName,
  }) {
    if (result == null) return null;
    final path = result['path'] as String?;
    if (path == null || path.isEmpty) return null;
    final rawName = (result['name'] as String?)?.trim();
    final name = rawName == null || rawName.isEmpty ? fallbackName : rawName;
    return (path: path, name: name);
  }

  Future<void> _startNativeVolumeGuard() async {
    try {
      await _alarmChannel.invokeMethod<void>('startAlarmAudioGuard');
    } catch (_) {}
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, _config.mode.storageKey);
    await prefs.setString(_keyFilePath, _config.filePath ?? '');
    await prefs.setString(_keyFileName, _config.fileName ?? '');
    await prefs.setString(_keyRecordingPath, _config.recordingPath ?? '');
    await prefs.setString(_keyRecordingName, _config.recordingName ?? '');
    notifyListeners();
  }

  String? _readStoredString(SharedPreferences prefs, String key) {
    final value = prefs.getString(key)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  @override
  void dispose() {
    unawaited(
      _alarmChannel
          .invokeMethod<void>('stopAlarmAudioGuard', {'restore': true})
          .catchError((_) {}),
    );
    _player.dispose();
    super.dispose();
  }
}

class _AlarmGeneratedWavSource extends StreamAudioSource {
  final Uint8List bytes;

  _AlarmGeneratedWavSource(this.bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= bytes.length;
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(bytes.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}

Uint8List _generateAlarmWav() {
  const sampleRate = 22050;
  const durationMs = 22000;
  final random = math.Random(DateTime.now().microsecondsSinceEpoch);
  final totalSamples = (sampleRate * durationMs / 1000).round();
  final pcm = Float64List(totalSamples);
  var cursor = 0;

  while (cursor < totalSamples) {
    final pulseMs = 80 + random.nextInt(260);
    final gapMs = 50 + random.nextInt(430);
    final len = (sampleRate * pulseMs / 1000).round();
    final freq = 360 + random.nextInt(1500);
    final glide = (random.nextDouble() * 520) - 260;
    final gain = 0.28 + random.nextDouble() * 0.34;
    final decaySpeed = 7.0 + random.nextDouble() * 14.0;
    final harmonic = 1.25 + random.nextDouble() * 1.35;

    for (var i = 0; i < len && cursor + i < totalSamples; i++) {
      final t = i / sampleRate;
      final attack = math.min(1.0, i / (sampleRate * 0.006));
      final decay = math.exp(-t * decaySpeed);
      final env = attack * decay * gain;
      final swept = freq + glide * t;
      final noise = (random.nextDouble() * 2.0) - 1.0;
      final wave = math.sin(2 * math.pi * swept * t) * 0.68 +
          math.sin(2 * math.pi * swept * harmonic * t) * 0.24 +
          noise * 0.08;
      pcm[cursor + i] += wave * env;
    }

    cursor += len + (sampleRate * gapMs / 1000).round();
  }

  final data = Int16List(totalSamples);
  for (var i = 0; i < totalSamples; i++) {
    final driven = pcm[i] * 1.45;
    final saturated = driven / (1 + driven.abs());
    data[i] = (saturated.clamp(-1.0, 1.0) * 32767).round();
  }
  return _wrapWav(data, sampleRate: sampleRate);
}

Uint8List _wrapWav(Int16List pcm, {required int sampleRate}) {
  final dataLen = pcm.length * 2;
  final bytes = BytesBuilder();

  void str(String value) => bytes.add(value.codeUnits);
  void u32(int value) => bytes.add([
        value & 0xFF,
        (value >> 8) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 24) & 0xFF,
      ]);
  void u16(int value) => bytes.add([value & 0xFF, (value >> 8) & 0xFF]);

  str('RIFF');
  u32(36 + dataLen);
  str('WAVE');
  str('fmt ');
  u32(16);
  u16(1);
  u16(1);
  u32(sampleRate);
  u32(sampleRate * 2);
  u16(2);
  u16(16);
  str('data');
  u32(dataLen);
  bytes.add(pcm.buffer.asUint8List());
  return bytes.toBytes();
}
