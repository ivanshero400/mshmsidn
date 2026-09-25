import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adhan_alarm_service.dart';
import 'prayer_times_service.dart';

enum FajrAlarmEndMode {
  untilWake,
  prayerConfirmation,
  phoneMovement,
  heavySleeper,
}

extension FajrAlarmEndModeCodec on FajrAlarmEndMode {
  String get storageKey {
    switch (this) {
      case FajrAlarmEndMode.untilWake:
        return 'until_wake';
      case FajrAlarmEndMode.prayerConfirmation:
        return 'prayer_confirmation';
      case FajrAlarmEndMode.phoneMovement:
        return 'phone_movement';
      case FajrAlarmEndMode.heavySleeper:
        return 'heavy_sleeper';
    }
  }

  String get arabicLabel {
    switch (this) {
      case FajrAlarmEndMode.untilWake:
        return 'حتى أستيقظ';
      case FajrAlarmEndMode.prayerConfirmation:
        return 'بعد تأكيد الصلاة';
      case FajrAlarmEndMode.phoneMovement:
        return 'عند تحرك الهاتف';
      case FajrAlarmEndMode.heavySleeper:
        return 'نومي ثقيل للغاية';
    }
  }

  String get arabicSubLabel {
    switch (this) {
      case FajrAlarmEndMode.heavySleeper:
        return 'معادلة + تحرك';
      default:
        return '';
    }
  }

  static FajrAlarmEndMode fromStorage(String? value) {
    for (final mode in FajrAlarmEndMode.values) {
      if (mode.storageKey == value) return mode;
    }
    return FajrAlarmEndMode.untilWake;
  }
}

class FajrAlarmConfig {
  final bool systemEnabled;
  final bool fajrEnabled;
  final bool ishaEnabled;
  final int startBeforeFajrMinutes;
  final int startAfterFajrMinutes;
  final FajrAlarmEndMode endMode;

  const FajrAlarmConfig({
    required this.systemEnabled,
    required this.fajrEnabled,
    required this.ishaEnabled,
    required this.startBeforeFajrMinutes,
    required this.startAfterFajrMinutes,
    required this.endMode,
  });

  const FajrAlarmConfig.defaults()
    : systemEnabled = false,
      fajrEnabled = false,
      ishaEnabled = false,
      startBeforeFajrMinutes = 0,
      startAfterFajrMinutes = 0,
      endMode = FajrAlarmEndMode.untilWake;

  bool controlsPrayer(String prayerName) {
    if (!systemEnabled) return false;
    switch (prayerName.toUpperCase()) {
      case 'FAJR':
        return fajrEnabled;
      case 'ISHA':
        return ishaEnabled;
      default:
        return false;
    }
  }

  String get startModeStorageKey {
    if (startBeforeFajrMinutes > 0) return 'before_fajr';
    if (startAfterFajrMinutes > 0) return 'after_fajr';
    return 'at_fajr';
  }

  String get startModeLabel {
    if (startBeforeFajrMinutes > 0) return 'قبل الفجر';
    if (startAfterFajrMinutes > 0) return 'بعد الفجر';
    return 'عند الفجر';
  }

  FajrAlarmConfig copyWith({
    bool? systemEnabled,
    bool? fajrEnabled,
    bool? ishaEnabled,
    int? startBeforeFajrMinutes,
    int? startAfterFajrMinutes,
    FajrAlarmEndMode? endMode,
  }) {
    return FajrAlarmConfig(
      systemEnabled: systemEnabled ?? this.systemEnabled,
      fajrEnabled: fajrEnabled ?? this.fajrEnabled,
      ishaEnabled: ishaEnabled ?? this.ishaEnabled,
      startBeforeFajrMinutes:
          startBeforeFajrMinutes ?? this.startBeforeFajrMinutes,
      startAfterFajrMinutes:
          startAfterFajrMinutes ?? this.startAfterFajrMinutes,
      endMode: endMode ?? this.endMode,
    );
  }

  Map<String, Object> toJson({
    int? maxStartAfterFajrMinutes,
    String? fajrTime,
    String? sunriseTime,
  }) {
    final start = <String, Object>{
      'mode': startModeStorageKey,
      'label': startModeLabel,
      'beforeFajrMinutes': startBeforeFajrMinutes,
      'afterFajrMinutes': startAfterFajrMinutes,
    };
    if (maxStartAfterFajrMinutes != null) {
      start['maxAfterFajrMinutes'] = maxStartAfterFajrMinutes;
    }
    if (fajrTime != null) {
      start['fajrTime'] = fajrTime;
    }
    if (sunriseTime != null) {
      start['sunriseTime'] = sunriseTime;
    }

    return {
      'systemEnabled': systemEnabled,
      'alarms': {'FAJR': fajrEnabled, 'ISHA': ishaEnabled},
      'start': start,
      'finishMethod': {'mode': endMode.storageKey, 'label': endMode.arabicLabel},
      'effectiveAdhanPolicy': {
        'FAJR': controlsPrayer('FAJR') ? 'alarm_override' : 'user_default',
        'ISHA': controlsPrayer('ISHA') ? 'alarm_override' : 'user_default',
      },
    };
  }
}

class FajrAlarmConfigService extends ChangeNotifier {
  static const keyConfigJson = 'fajr_alarm_config_json';
  static const keySystemEnabled = 'fajr_alarm_system_enabled';
  static const keyFajrEnabled = 'fajr_alarm_fajr_enabled';
  static const keyIshaEnabled = 'fajr_alarm_isha_enabled';
  static const keyStartBeforeFajr = 'fajr_alarm_start_before_fajr_min';
  static const keyStartAfterFajr = 'fajr_alarm_start_after_fajr_min';
  static const keyEndMode = 'fajr_alarm_end_mode';
  static const keyFajrAdhanOverride = 'fajr_alarm_fajr_adhan_override';
  static const keyIshaAdhanOverride = 'fajr_alarm_isha_adhan_override';

  FajrAlarmConfig _config = const FajrAlarmConfig.defaults();
  bool _loaded = false;

  FajrAlarmConfig get config => _config;
  bool get loaded => _loaded;

  Future<void> ensureLoaded({PrayerTimesService? timesService}) async {
    if (_loaded) {
      if (timesService != null) await sanitizeAgainstPrayerTimes(timesService);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _config = FajrAlarmConfig(
      systemEnabled: prefs.getBool(keySystemEnabled) ?? false,
      fajrEnabled: prefs.getBool(keyFajrEnabled) ?? false,
      ishaEnabled: prefs.getBool(keyIshaEnabled) ?? false,
      startBeforeFajrMinutes: _stepMinutes(
        prefs.getInt(keyStartBeforeFajr) ?? 0,
        max: 60,
      ),
      startAfterFajrMinutes: _stepMinutes(
        prefs.getInt(keyStartAfterFajr) ?? 0,
        max: timesService == null ? 120 : maxAfterFajrMinutes(timesService),
      ),
      endMode: FajrAlarmEndModeCodec.fromStorage(prefs.getString(keyEndMode)),
    );
    _loaded = true;
    if (timesService != null) {
      await sanitizeAgainstPrayerTimes(timesService, notify: false);
    }
    await _persist(notify: false);
    notifyListeners();
  }

  Future<void> setSystemEnabled(
    bool enabled, {
    PrayerTimesService? timesService,
  }) async {
    _config = _config.copyWith(systemEnabled: enabled);
    if (timesService != null) {
      await sanitizeAgainstPrayerTimes(timesService, notify: false);
    }
    await _persist();
  }

  Future<bool> setFajrEnabled(bool enabled) async {
    if (!_config.systemEnabled) return false;
    _config = _config.copyWith(fajrEnabled: enabled);
    await _persist();
    return true;
  }

  Future<bool> setIshaEnabled(bool enabled) async {
    if (!_config.systemEnabled) return false;
    _config = _config.copyWith(ishaEnabled: enabled);
    await _persist();
    return true;
  }

  Future<bool> setStartBeforeFajrMinutes(int minutes) async {
    if (!_config.systemEnabled) return false;
    final stepped = _stepMinutes(minutes, max: 60);
    _config = _config.copyWith(
      startBeforeFajrMinutes: stepped,
      startAfterFajrMinutes: stepped > 0 ? 0 : _config.startAfterFajrMinutes,
    );
    await _persist();
    return true;
  }

  Future<bool> setStartBeforeFajrEnabled(bool enabled) async {
    if (!_config.systemEnabled) return false;
    _config = _config.copyWith(
      startBeforeFajrMinutes: enabled
          ? (_config.startBeforeFajrMinutes > 0
              ? _config.startBeforeFajrMinutes
              : 15)
          : 0,
      startAfterFajrMinutes: enabled ? 0 : _config.startAfterFajrMinutes,
    );
    await _persist();
    return true;
  }

  Future<bool> setStartAfterFajrMinutes(
    int minutes,
    PrayerTimesService timesService,
  ) async {
    if (!_config.systemEnabled) return false;
    final maxMinutes = maxAfterFajrMinutes(timesService);
    final stepped = _stepMinutes(minutes, max: maxMinutes);
    _config = _config.copyWith(
      startBeforeFajrMinutes: stepped > 0 ? 0 : _config.startBeforeFajrMinutes,
      startAfterFajrMinutes: stepped,
    );
    await _persist();
    return true;
  }

  Future<bool> setStartAfterFajrEnabled(
    bool enabled,
    PrayerTimesService timesService,
  ) async {
    if (!_config.systemEnabled) return false;
    final maxMinutes = maxAfterFajrMinutes(timesService);
    if (enabled && maxMinutes <= 0) return false;
    final minutes = enabled
        ? (_config.startAfterFajrMinutes > 0
            ? _config.startAfterFajrMinutes.clamp(0, maxMinutes).toInt()
            : (maxMinutes >= 15 ? 15 : maxMinutes))
        : 0;
    _config = _config.copyWith(
      startBeforeFajrMinutes: enabled ? 0 : _config.startBeforeFajrMinutes,
      startAfterFajrMinutes: _stepMinutes(minutes, max: maxMinutes),
    );
    await _persist();
    return true;
  }

  Future<bool> setEndMode(FajrAlarmEndMode mode) async {
    if (!_config.systemEnabled) return false;
    _config = _config.copyWith(endMode: mode);
    await _persist();
    return true;
  }

  Future<void> sanitizeAgainstPrayerTimes(
    PrayerTimesService timesService, {
    bool notify = true,
  }) async {
    final maxMinutes = maxAfterFajrMinutes(timesService);
    final clampedBefore = _stepMinutes(
      _config.startBeforeFajrMinutes,
      max: 60,
    );
    final clampedAfter = _stepMinutes(
      _config.startAfterFajrMinutes,
      max: maxMinutes,
    );
    final exclusiveAfter = clampedBefore > 0 ? 0 : clampedAfter;
    if (clampedBefore == _config.startBeforeFajrMinutes &&
        exclusiveAfter == _config.startAfterFajrMinutes) {
      return;
    }
    _config = _config.copyWith(
      startBeforeFajrMinutes: clampedBefore,
      startAfterFajrMinutes: exclusiveAfter,
    );
    await _persist(notify: notify);
  }

  String effectiveAdhanPolicyFor(String prayerName) {
    return _config.controlsPrayer(prayerName)
        ? 'alarm_override'
        : 'user_default';
  }

  Map<String, Object> snapshotForServer(PrayerTimesService timesService) {
    return _config.toJson(
      maxStartAfterFajrMinutes: maxAfterFajrMinutes(timesService),
      fajrTime: timesService.getTime('FAJR'),
      sunriseTime: timesService.getTime('SUNRISE'),
    );
  }

  static int maxAfterFajrMinutes(PrayerTimesService timesService) {
    final fajr = _parseMinutes(timesService.getTime('FAJR'));
    final sunrise = _parseMinutes(timesService.getTime('SUNRISE'));
    if (fajr == null || sunrise == null) return 0;

    var sunriseNormalized = sunrise;
    if (sunriseNormalized <= fajr) sunriseNormalized += 24 * 60;
    final raw = sunriseNormalized - fajr - 15;
    if (raw <= 0) return 0;
    return (raw ~/ 5) * 5;
  }

  static int _stepMinutes(int value, {required int max}) {
    if (max <= 0) return 0;
    final clamped = value.clamp(0, max).toInt();
    return ((clamped / 5).round() * 5).clamp(0, max).toInt();
  }

  static int? _parseMinutes(String? value) {
    if (value == null || value == '--:--') return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  Future<void> _persist({bool notify = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keySystemEnabled, _config.systemEnabled);
    await prefs.setBool(keyFajrEnabled, _config.fajrEnabled);
    await prefs.setBool(keyIshaEnabled, _config.ishaEnabled);
    await prefs.setInt(keyStartBeforeFajr, _config.startBeforeFajrMinutes);
    await prefs.setInt(keyStartAfterFajr, _config.startAfterFajrMinutes);
    await prefs.setString(keyEndMode, _config.endMode.storageKey);
    await prefs.setBool(keyFajrAdhanOverride, _config.controlsPrayer('FAJR'));
    await prefs.setBool(keyIshaAdhanOverride, _config.controlsPrayer('ISHA'));
    await prefs.setString(keyConfigJson, jsonEncode(_config.toJson()));
    unawaited(AdhanAlarmService.schedulePrayerAlarms(const []));
    if (notify) notifyListeners();
  }
}
