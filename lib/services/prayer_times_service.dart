import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'aladhan_api_service.dart';
import 'location_service.dart';
import 'mosque_service.dart';

enum Madhab { shafii, hanafi }

/// Visual layout of the home screen (user-selectable from quick settings).
enum HomeStyle { circle, rectangle, minimal, focus, timeline }

/// Manages prayer times with local storage + AlAdhan API
class PrayerTimesService extends ChangeNotifier {
  static const _keyTimes = 'prayer_times_json';
  static const _keyLastFetch = 'last_fetch_date';
  static const _keyMethod = 'calc_method';
  static const _keyMadhab = 'madhab';
  static const _keyFajrAngle = 'fajr_angle';
  static const _keyIshaAngle = 'isha_angle';
  static const _keyIshaMode = 'isha_mode'; // 'angle' or 'minutes'
  static const _keyUse24h = 'use_24h';
  static const _keyShowHijri = 'show_hijri';
  static const _keyShowMidnight = 'show_midnight';
  static const _keyShowDuha = 'show_duha';
  static const _keyHomeStyle = 'home_style';
  static const _keyKidsMode = 'kids_mode';
  static const _keyAdhanGlobalMute = 'adhan_global_mute';
  static const _keyAdhanScreenEnabled = 'adhan_screen_enabled';

  /// Default fallback times
  static const List<Map<String, String>> defaultTimes = [
    {'name': 'FAJR', 'time': '05:12'},
    {'name': 'SUNRISE', 'time': '06:34'},
    {'name': 'DHUHR', 'time': '12:15'},
    {'name': 'ASR', 'time': '15:42'},
    {'name': 'MAGHRIB', 'time': '18:05'},
    {'name': 'ISHA', 'time': '19:28'},
  ];

  final AlAdhanApiService _api = AlAdhanApiService();
  final LocationService locationService = LocationService();
  final MosqueService mosqueService = MosqueService();

  List<Map<String, String>> _times = List.from(defaultTimes);
  List<Map<String, String>> get times => _times;

  int _method = 12; // default: Union des Organisations Islamiques de France
  int get method => _method;

  Madhab _madhab = Madhab.shafii;
  Madhab get madhab => _madhab;

  /// Custom Fajr angle (12.0–20.0), null = use method default
  double? _fajrAngle;
  double? get fajrAngle => _fajrAngle;

  /// Custom Isha angle/value
  double? _ishaAngle;
  double? get ishaAngle => _ishaAngle;

  /// 'angle' or 'minutes'
  String _ishaMode = 'angle';
  String get ishaMode => _ishaMode;

  bool _use24h = false;
  bool get use24h => _use24h;

  bool _showHijri = true;
  bool get showHijri => _showHijri;

  bool _showMidnight = true;
  bool get showMidnight => _showMidnight;

  bool _showDuha = true;
  bool get showDuha => _showDuha;

  /// Selected home-screen layout (circle / rectangle / minimal / focus / timeline).
  HomeStyle _homeStyle = HomeStyle.circle;
  HomeStyle get homeStyle => _homeStyle;

  /// When true the home screen switches to a fixed, child-friendly layout.
  bool _kidsMode = false;
  bool get kidsMode => _kidsMode;

  /// Global mute for all adhan sounds. When true, no sound plays for any
  /// prayer, but the alarm screen still shows and vibration still works.
  /// Per-prayer VibeMode settings are NOT touched.
  bool _adhanGlobalMute = false;
  bool get adhanGlobalMute => _adhanGlobalMute;

  /// When false, the full-screen adhan alarm Activity is skipped entirely.
  /// Only a notification appears at prayer time.
  bool _adhanScreenEnabled = true;
  bool get adhanScreenEnabled => _adhanScreenEnabled;

  /// Determine whether it's currently night (between Maghrib & Fajr)
  /// based on actual prayer times. Falls back to 6 PM–5 AM if no times yet.
  bool isNightNow() {
    String? fajr, maghrib;
    for (final p in _times) {
      if (p['name'] == 'FAJR') fajr = p['time'];
      if (p['name'] == 'MAGHRIB') maghrib = p['time'];
    }
    if (fajr == null || maghrib == null) {
      final h = DateTime.now().hour;
      return h >= 18 || h < 5;
    }
    final now = DateTime.now();
    final fParts = fajr.split(':');
    final mParts = maghrib.split(':');
    final maghribDt = DateTime(now.year, now.month, now.day,
        int.parse(mParts[0]), int.parse(mParts[1]));
    final fajrDt = DateTime(now.year, now.month, now.day,
        int.parse(fParts[0]), int.parse(fParts[1]));
    // Night = after Maghrib OR before Fajr (same day)
    return now.isAfter(maghribDt) || now.isBefore(fajrDt);
  }

  /// Get time string for a named prayer
  String? getTime(String name) {
    for (final p in _times) {
      if (p['name'] == name) return p['time'];
    }
    return null;
  }

  /// Parse HH:MM to minutes since midnight
  int _parseMin(String t) {
    final parts = t.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// Islamic midnight = midpoint between Maghrib and Fajr
  String? calcMidnight() {
    final maghrib = getTime('MAGHRIB');
    final fajr = getTime('FAJR');
    if (maghrib == null || fajr == null) return null;

    int maghribMin = _parseMin(maghrib);
    int fajrMin = _parseMin(fajr);
    // Fajr is next day from Maghrib's perspective
    if (fajrMin < maghribMin) fajrMin += 24 * 60;

    int midMin = maghribMin + (fajrMin - maghribMin) ~/ 2;
    midMin = midMin % (24 * 60);
    return '${(midMin ~/ 60).toString().padLeft(2, '0')}:${(midMin % 60).toString().padLeft(2, '0')}';
  }

  /// Last third of night starts at 2/3 of the way from Maghrib to Fajr
  String? calcLastThird() {
    final maghrib = getTime('MAGHRIB');
    final fajr = getTime('FAJR');
    if (maghrib == null || fajr == null) return null;

    int maghribMin = _parseMin(maghrib);
    int fajrMin = _parseMin(fajr);
    if (fajrMin < maghribMin) fajrMin += 24 * 60;

    int lastThirdMin = maghribMin + ((fajrMin - maghribMin) * 2 ~/ 3);
    lastThirdMin = lastThirdMin % (24 * 60);
    return '${(lastThirdMin ~/ 60).toString().padLeft(2, '0')}:${(lastThirdMin % 60).toString().padLeft(2, '0')}';
  }

  /// Is it currently after midnight (and before Fajr)?
  bool isAfterMidnight() {
    final mid = calcMidnight();
    if (mid == null) return false;
    final now = DateTime.now();
    final midMin = _parseMin(mid);
    final nowMin = now.hour * 60 + now.minute;
    final maghribMin = _parseMin(getTime('MAGHRIB') ?? '00:00');

    // After midnight means now > midnight AND now > Maghrib (same night)
    if (maghribMin < midMin) {
      return nowMin >= midMin;
    } else {
      // Maghrib > midnight (crosses 00:00)
      return nowMin >= midMin && nowMin < maghribMin;
    }
  }

  /// Duha time: 15 min after sunrise, ends 15 min before Dhuhr
  /// Best time: when the sun is high (~1/4 of the day after sunrise)
  Map<String, String>? calcDuha() {
    final sunrise = getTime('SUNRISE');
    final dhuhr = getTime('DHUHR');
    if (sunrise == null || dhuhr == null) return null;

    int sunriseMin = _parseMin(sunrise);
    int dhuhrMin = _parseMin(dhuhr);
    if (dhuhrMin < sunriseMin) dhuhrMin += 24 * 60;

    // Duha starts 15 min after sunrise
    int duhaStart = (sunriseMin + 15) % (24 * 60);
    // Duha ends 15 min before Dhuhr
    int duhaEnd = (dhuhrMin - 15) % (24 * 60);

    // Best time (most rewarding): 1/4 of daylight after sunrise
    int bestTime = sunriseMin + (dhuhrMin - sunriseMin) ~/ 4;
    bestTime = bestTime % (24 * 60);

    return {
      'name': 'DUHA',
      'time': '${(duhaStart ~/ 60).toString().padLeft(2, '0')}:${(duhaStart % 60).toString().padLeft(2, '0')}',
      'end': '${(duhaEnd ~/ 60).toString().padLeft(2, '0')}:${(duhaEnd % 60).toString().padLeft(2, '0')}',
      'best': '${(bestTime ~/ 60).toString().padLeft(2, '0')}:${(bestTime % 60).toString().padLeft(2, '0')}',
    };
  }

  /// Check if current time is within Duha window
  bool isDuhaActive() {
    final duha = calcDuha();
    if (duha == null) return false;
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final startMin = _parseMin(duha['time']!);
    final endMin = _parseMin(duha['end']!);
    return nowMin >= startMin && nowMin <= endMin;
  }

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  Future<void> initialize() async {
    final p = await SharedPreferences.getInstance();
    _method = p.getInt(_keyMethod) ?? 12;
    _madhab = (p.getInt(_keyMadhab) ?? 0) == 1 ? Madhab.hanafi : Madhab.shafii;
    _fajrAngle = p.getDouble(_keyFajrAngle); // null if not set
    _ishaAngle = p.getDouble(_keyIshaAngle);
    _ishaMode = p.getString(_keyIshaMode) ?? 'angle';
    _use24h = p.getBool(_keyUse24h) ?? false;
    _showHijri = p.getBool(_keyShowHijri) ?? true;
    _showMidnight = p.getBool(_keyShowMidnight) ?? true;
    _showDuha = p.getBool(_keyShowDuha) ?? true;
    final hs = p.getInt(_keyHomeStyle) ?? 0;
    _homeStyle = HomeStyle.values[hs.clamp(0, HomeStyle.values.length - 1)];
    _kidsMode = p.getBool(_keyKidsMode) ?? false;
    _adhanGlobalMute = p.getBool(_keyAdhanGlobalMute) ?? false;
    _adhanScreenEnabled = p.getBool(_keyAdhanScreenEnabled) ?? true;
    await locationService.load();
    await mosqueService.load();

    // If a mosque is selected, use its times directly.
    if (mosqueService.hasMosque && mosqueService.schedule != null) {
      _times = mosqueService.schedule!.toPrayerTimes();
    }

    locationService.addListener(() async {
      await _fetchFromApi();
    });
    // When the user picks/resets a mosque, reload times immediately
    mosqueService.addListener(() async {
      if (mosqueService.hasMosque && mosqueService.schedule != null) {
        _times = mosqueService.schedule!.toPrayerTimes();
        await _saveToPrefs();
        notifyListeners();
      } else {
        await _fetchFromApi();
      }
    });
  }

  Future<void> loadTimes() async {
    final prefs = await SharedPreferences.getInstance();
    final lastFetchStr = prefs.getString(_keyLastFetch);

    final bool needsRefresh = lastFetchStr == null ||
        DateTime.now()
                .difference(DateTime.parse(lastFetchStr))
                .inDays >=
            3;

    if (needsRefresh) {
      await _fetchFromApi();
    } else {
      final json = prefs.getString(_keyTimes);
      if (json != null) {
        final list = jsonDecode(json) as List;
        _times =
            list.map((e) => Map<String, String>.from(e as Map)).toList();
      } else {
        _times = List.from(defaultTimes);
        await _saveToPrefs();
      }
    }
    notifyListeners();
  }

  Future<void> setMethod(int newMethod) async {
    _method = newMethod;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_keyMethod, _method);
    await _fetchFromApi();
    notifyListeners();
  }

  Future<void> setMadhab(Madhab m) async {
    _madhab = m;
    await SharedPreferences.getInstance()
        .then((p) => p.setInt(_keyMadhab, m == Madhab.hanafi ? 1 : 0));
    await _fetchFromApi();
    notifyListeners();
  }

  Future<void> setFajrAngle(double? angle) async {
    _fajrAngle = angle;
    final p = await SharedPreferences.getInstance();
    if (angle == null) {
      await p.remove(_keyFajrAngle);
    } else {
      await p.setDouble(_keyFajrAngle, angle);
    }
    await _fetchFromApi();
    notifyListeners();
  }

  Future<void> setIshaAngle(double? angle, {String mode = 'angle'}) async {
    _ishaAngle = angle;
    _ishaMode = mode;
    final p = await SharedPreferences.getInstance();
    if (angle == null) {
      await p.remove(_keyIshaAngle);
    } else {
      await p.setDouble(_keyIshaAngle, angle);
    }
    await p.setString(_keyIshaMode, mode);
    await _fetchFromApi();
    notifyListeners();
  }

  /// Check if custom angles are active (method should be 99 in API)
  bool get useCustomAngles => _fajrAngle != null || _ishaAngle != null;

  Future<void> setUse24h(bool v) async {
    _use24h = v;
    await SharedPreferences.getInstance().then((p) => p.setBool(_keyUse24h, v));
    notifyListeners();
  }

  Future<void> setShowHijri(bool v) async {
    _showHijri = v;
    await SharedPreferences.getInstance().then((p) => p.setBool(_keyShowHijri, v));
    notifyListeners();
  }

  Future<void> setShowMidnight(bool v) async {
    _showMidnight = v;
    await SharedPreferences.getInstance().then((p) => p.setBool(_keyShowMidnight, v));
    notifyListeners();
  }

  Future<void> setShowDuha(bool v) async {
    _showDuha = v;
    await SharedPreferences.getInstance().then((p) => p.setBool(_keyShowDuha, v));
    notifyListeners();
  }

  Future<void> setHomeStyle(HomeStyle s) async {
    _homeStyle = s;
    await SharedPreferences.getInstance().then((p) => p.setInt(_keyHomeStyle, s.index));
    notifyListeners();
  }

  Future<void> setKidsMode(bool v) async {
    _kidsMode = v;
    await SharedPreferences.getInstance().then((p) => p.setBool(_keyKidsMode, v));
    notifyListeners();
  }

  Future<void> setAdhanGlobalMute(bool v) async {
    _adhanGlobalMute = v;
    await SharedPreferences.getInstance().then((p) => p.setBool(_keyAdhanGlobalMute, v));
    notifyListeners();
  }

  Future<void> setAdhanScreenEnabled(bool v) async {
    _adhanScreenEnabled = v;
    await SharedPreferences.getInstance().then((p) => p.setBool(_keyAdhanScreenEnabled, v));
    notifyListeners();
  }

  Future<void> refresh() async {
    await _fetchFromApi();
  }

  // ── Private ──

  Future<void> _fetchFromApi() async {
    // Mosque mode: use the mosque's stored timetable — no API call.
    if (mosqueService.hasMosque && mosqueService.schedule != null) {
      _times = mosqueService.schedule!.toPrayerTimes();
      await _saveToPrefs();
      _loading = false;
      _error = null;
      notifyListeners();
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final effectiveMethod = useCustomAngles ? 99 : _method;
      final timings = await _api.fetchTimings(
        latitude: locationService.latitude,
        longitude: locationService.longitude,
        method: effectiveMethod,
        madhab: _madhab == Madhab.hanafi ? 1 : 0,
        fajrAngle: _fajrAngle,
        ishaAngle: _ishaAngle,
        ishaMode: _ishaMode,
      );

      _times = [
        {'name': 'FAJR', 'time': timings['FAJR'] ?? '--:--'},
        {'name': 'SUNRISE', 'time': timings['SUNRISE'] ?? '--:--'},
        {'name': 'DHUHR', 'time': timings['DHUHR'] ?? '--:--'},
        {'name': 'ASR', 'time': timings['ASR'] ?? '--:--'},
        {'name': 'MAGHRIB', 'time': timings['MAGHRIB'] ?? '--:--'},
        {'name': 'ISHA', 'time': timings['ISHA'] ?? '--:--'},
      ];

      await _saveToPrefs();
    } catch (e) {
      _error = e.toString();
      // Fallback to stored or default
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_keyTimes);
      if (json != null) {
        final list = jsonDecode(json) as List;
        _times =
            list.map((e) => Map<String, String>.from(e as Map)).toList();
      } else {
        _times = List.from(defaultTimes);
      }
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTimes, jsonEncode(_times));
    await prefs.setString(
        _keyLastFetch, DateTime.now().toIso8601String());
  }
}

// ── Hijri date converter ──
class HijriDate {
  final int year;
  final int month;
  final int day;

  const HijriDate(this.year, this.month, this.day);

  static const _monthNames = [
    'محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر',
    'جمادى الأولى', 'جمادى الآخرة', 'رجب', 'شعبان',
    'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة',
  ];

  String get monthName => _monthNames[month - 1];

  String format() => '$day $monthName $year هـ';

  /// Convert Gregorian to Hijri (approximate, ±1 day)
  static HijriDate fromGregorian(DateTime g) {
    int jd = _gregorianToJd(g.year, g.month, g.day);
    int l = jd - 1948440 + 10632;
    int n = ((l - 1) ~/ 10631);
    l = l - 10631 * n + 354;
    int j = ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) + (l ~/ 5670) * ((43 * l) ~/ 15238);
    l = l - ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) - (j ~/ 16) * ((15238 * j) ~/ 43) + 29;
    int m = (24 * l) ~/ 709;
    int d = l - ((709 * m) ~/ 24);
    int y = 30 * n + j - 30;
    return HijriDate(y, m, d);
  }

  static int _gregorianToJd(int y, int m, int d) {
    if (m < 3) { y--; m += 12; }
    int a = y ~/ 100;
    int b = 2 - a + (a ~/ 4);
    return (365.25 * (y + 4716)).floor() +
           (30.6001 * (m + 1)).floor() + d + b - 1524;
  }
}
