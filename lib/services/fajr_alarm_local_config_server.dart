import 'fajr_alarm_config_service.dart';
import 'fajr_alarm_sound_service.dart';
import 'prayer_times_service.dart';

class FajrAlarmLocalConfigEndpoints {
  static const config = '/local/fajr-alarm/config';
  static const system = '/local/fajr-alarm/system';
  static const fajr = '/local/fajr-alarm/prayers/fajr';
  static const isha = '/local/fajr-alarm/prayers/isha';
  static const start = '/local/fajr-alarm/start';
  static const end = '/local/fajr-alarm/end';
  static const finishMethod = '/local/fajr-alarm/finish-method';
  static const sound = '/local/fajr-alarm/sound';
  static const effectiveFajr = '/local/fajr-alarm/effective/fajr';
  static const effectiveIsha = '/local/fajr-alarm/effective/isha';
}

class FajrAlarmLocalConfigResponse {
  final int statusCode;
  final Map<String, Object?> body;

  const FajrAlarmLocalConfigResponse(this.statusCode, this.body);

  bool get ok => statusCode >= 200 && statusCode < 300;
}

class FajrAlarmLocalConfigServer {
  final FajrAlarmConfigService configService;
  final FajrAlarmSoundService? soundService;
  final PrayerTimesService timesService;

  FajrAlarmLocalConfigServer({
    required this.configService,
    required this.timesService,
    this.soundService,
  });

  Future<FajrAlarmLocalConfigResponse> handle({
    required String method,
    required String path,
    Map<String, Object?> body = const {},
  }) async {
    final normalizedMethod = method.toUpperCase();
    await configService.ensureLoaded(timesService: timesService);
    await soundService?.ensureLoaded();

    if (normalizedMethod == 'GET') {
      return _handleGet(path);
    }
    if (normalizedMethod == 'PATCH' || normalizedMethod == 'PUT') {
      return _handleWrite(path, body);
    }
    return const FajrAlarmLocalConfigResponse(405, {
      'error': 'method_not_allowed',
    });
  }

  FajrAlarmLocalConfigResponse _handleGet(String path) {
    switch (path) {
      case FajrAlarmLocalConfigEndpoints.config:
        return FajrAlarmLocalConfigResponse(
          200,
          _snapshot(),
        );
      case FajrAlarmLocalConfigEndpoints.sound:
        final service = soundService;
        if (service == null) return _soundUnavailable();
        return FajrAlarmLocalConfigResponse(200, service.config.toJson());
      case FajrAlarmLocalConfigEndpoints.effectiveFajr:
        return _effectivePrayer('FAJR');
      case FajrAlarmLocalConfigEndpoints.effectiveIsha:
        return _effectivePrayer('ISHA');
      default:
        return const FajrAlarmLocalConfigResponse(404, {
          'error': 'endpoint_not_found',
        });
    }
  }

  Future<FajrAlarmLocalConfigResponse> _handleWrite(
    String path,
    Map<String, Object?> body,
  ) async {
    switch (path) {
      case FajrAlarmLocalConfigEndpoints.system:
        final enabled = body['enabled'];
        if (enabled is! bool) return _badRequest('enabled_bool_required');
        await configService.setSystemEnabled(
          enabled,
          timesService: timesService,
        );
        return _updated();
      case FajrAlarmLocalConfigEndpoints.fajr:
        final enabled = body['enabled'];
        if (enabled is! bool) return _badRequest('enabled_bool_required');
        return await configService.setFajrEnabled(enabled)
            ? _updated()
            : _frozen();
      case FajrAlarmLocalConfigEndpoints.isha:
        final enabled = body['enabled'];
        if (enabled is! bool) return _badRequest('enabled_bool_required');
        return await configService.setIshaEnabled(enabled)
            ? _updated()
            : _frozen();
      case FajrAlarmLocalConfigEndpoints.start:
        final beforeValue = body['beforeFajrMinutes'];
        final afterValue = body['afterFajrMinutes'];
        if (beforeValue != null && beforeValue is! int) {
          return _badRequest('before_fajr_minutes_int_required');
        }
        if (afterValue != null && afterValue is! int) {
          return _badRequest('after_fajr_minutes_int_required');
        }
        if (!configService.config.systemEnabled) return _frozen();
        final before = beforeValue as int?;
        final after = afterValue as int?;
        if ((before ?? 0) > 0 && (after ?? 0) > 0) {
          return _badRequest('choose_one_start_mode');
        }
        if (before != null) {
          await configService.setStartBeforeFajrMinutes(before);
        }
        if (after != null) {
          await configService.setStartAfterFajrMinutes(after, timesService);
        }
        return _updated();
      case FajrAlarmLocalConfigEndpoints.end:
      case FajrAlarmLocalConfigEndpoints.finishMethod:
        final mode = body['mode'];
        if (mode is! String) return _badRequest('mode_string_required');
        return await configService.setEndMode(
              FajrAlarmEndModeCodec.fromStorage(mode),
            )
            ? _updated()
            : _frozen();
      case FajrAlarmLocalConfigEndpoints.sound:
        final service = soundService;
        if (service == null) return _soundUnavailable();
        if (!configService.config.systemEnabled) return _frozen();
        final mode = body['mode'];
        if (mode is! String) return _badRequest('mode_string_required');
        switch (FajrAlarmSoundModeLabels.fromStorage(mode)) {
          case FajrAlarmSoundMode.generated:
            await service.setGenerated();
            return _updated();
          case FajrAlarmSoundMode.adhan:
            await service.setAdhan();
            return _updated();
          case FajrAlarmSoundMode.file:
            final path = body['path'];
            final name = body['name'];
            if (path is! String || path.isEmpty) {
              return _badRequest('path_string_required');
            }
            await service.setFile(
              path: path,
              name: name is String && name.isNotEmpty ? name : 'ملف صوتي',
            );
            return _updated();
          case FajrAlarmSoundMode.recording:
            final path = body['path'];
            final name = body['name'];
            if (path is! String || path.isEmpty) {
              return _badRequest('path_string_required');
            }
            await service.setRecording(
              path: path,
              name: name is String && name.isNotEmpty
                  ? name
                  : 'تسجيل صوت مخصص',
            );
            return _updated();
        }
      default:
        return const FajrAlarmLocalConfigResponse(404, {
          'error': 'endpoint_not_found',
        });
    }
  }

  FajrAlarmLocalConfigResponse _effectivePrayer(String prayerName) {
    return FajrAlarmLocalConfigResponse(200, {
      'prayer': prayerName,
      'alarmActive': configService.config.controlsPrayer(prayerName),
      'policy': configService.effectiveAdhanPolicyFor(prayerName),
    });
  }

  FajrAlarmLocalConfigResponse _updated() {
    return FajrAlarmLocalConfigResponse(
      200,
      _snapshot(),
    );
  }

  Map<String, Object?> _snapshot() {
    final snapshot = Map<String, Object?>.from(
      configService.snapshotForServer(timesService),
    );
    final service = soundService;
    if (service != null) snapshot['sound'] = service.config.toJson();
    return snapshot;
  }

  static FajrAlarmLocalConfigResponse _badRequest(String error) {
    return FajrAlarmLocalConfigResponse(400, {'error': error});
  }

  static FajrAlarmLocalConfigResponse _frozen() {
    return const FajrAlarmLocalConfigResponse(423, {
      'error': 'alarm_system_disabled',
    });
  }

  static FajrAlarmLocalConfigResponse _soundUnavailable() {
    return const FajrAlarmLocalConfigResponse(501, {
      'error': 'alarm_sound_service_unavailable',
    });
  }
}
