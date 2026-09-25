import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translator/translator.dart';

// ═══════════════════ Models ═══════════════════

class MosqueData {
  final String id, name;
  final double latitude, longitude;
  final int distanceMeters;
  final String city, country;

  const MosqueData({required this.id, required this.name, required this.latitude, required this.longitude,
    this.distanceMeters = 0, this.city = '', this.country = ''});

  factory MosqueData.fromJson(Map<String, dynamic> json) {
    final ar = json['nameArabic']?.toString();
    final en = json['name']?.toString() ?? '';
    return MosqueData(id: json['id']?.toString() ?? '', name: (ar != null && ar.isNotEmpty) ? ar : en,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0, longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      distanceMeters: (json['distanceMeters'] as num?)?.toInt() ?? 0,
      city: json['city']?.toString() ?? '', country: json['country']?.toString() ?? '');
  }

  String get distanceLabel => distanceMeters < 1000 ? '$distanceMeters م' : '${(distanceMeters / 1000).toStringAsFixed(1)} كم';
}

class MosqueSchedule {
  final String fajr, dhuhr, asr, maghrib, isha;
  final String? sunrise, jumua;
  const MosqueSchedule({required this.fajr, required this.dhuhr, required this.asr, required this.maghrib, required this.isha, this.sunrise, this.jumua});

  factory MosqueSchedule.fromAlAdhan(Map<String, dynamic> timings) {
    String t(String k) => (timings[k]?.toString().substring(0, 5)) ?? '--:--';
    return MosqueSchedule(fajr: t('Fajr'), sunrise: t('Sunrise'), dhuhr: t('Dhuhr'), asr: t('Asr'), maghrib: t('Maghrib'), isha: t('Isha'));
  }

  factory MosqueSchedule.fromMawaqit(Map<String, dynamic> c) => MosqueSchedule(
    fajr: (c['iqama']?.toString() ?? c['fajr']?.toString() ?? '--:--').substring(0, 5).padLeft(5, '0'),
    sunrise: (c['shuruq']?.toString() ?? '--:--').substring(0, 5).padLeft(5, '0'),
    dhuhr: (c['dhuhr']?.toString() ?? '--:--').substring(0, 5).padLeft(5, '0'),
    asr: (c['asr']?.toString() ?? '--:--').substring(0, 5).padLeft(5, '0'),
    maghrib: (c['maghrib']?.toString() ?? '--:--').substring(0, 5).padLeft(5, '0'),
    isha: (c['isha']?.toString() ?? '--:--').substring(0, 5).padLeft(5, '0'),
    jumua: c['jumua']?.toString(),
  );

  factory MosqueSchedule.fromJson(Map<String, dynamic> json) {
    final t = (json['timings'] as Map<String, dynamic>?) ?? json;
    return MosqueSchedule(fajr: t['fajr']?.toString() ?? '--:--', dhuhr: t['dhuhr']?.toString() ?? '--:--',
      asr: t['asr']?.toString() ?? '--:--', maghrib: t['maghrib']?.toString() ?? '--:--',
      isha: t['isha']?.toString() ?? '--:--', sunrise: t['sunrise']?.toString());
  }

  List<Map<String, String>> toPrayerTimes() => [
    {'name': 'FAJR', 'time': fajr}, if (sunrise != null && sunrise != '--:--') {'name': 'SUNRISE', 'time': sunrise!},
    {'name': 'DHUHR', 'time': dhuhr}, {'name': 'ASR', 'time': asr},
    {'name': 'MAGHRIB', 'time': maghrib}, {'name': 'ISHA', 'time': isha}];
}

class MosqueWithTimes {
  final MosqueData mosque;
  final MosqueSchedule schedule;
  final String source;
  const MosqueWithTimes({required this.mosque, required this.schedule, required this.source});
}

/// Progress callback during discovery: (stepLabel, detailsText)
typedef DiscoverProgress = void Function(String step, String detail);

// ═══════════════════ Service ═══════════════════

class MosqueService extends ChangeNotifier {
  static const _tbBase = 'https://takbeertime.com/api';
  static const _alAdhan = 'https://api.aladhan.com/v1';
  static const _kId = 'mosque_id', _kName = 'mosque_name', _kTimes = 'mosque_times_json';
  static const _kCache = 'mosque_nearby_cache', _kCacheAt = 'mosque_cache_at';
  static const _kFetchedAt = 'mosque_last_fetch';
  static const _cacheTtl = Duration(days: 7);

  String? _mosqueId, _mosqueName;
  MosqueSchedule? _schedule;
  final bool _loading = false;
  String? _error;

  String? get mosqueId => _mosqueId; String? get mosqueName => _mosqueName;
  MosqueSchedule? get schedule => _schedule;
  bool get loading => _loading; String? get error => _error;
  bool get hasMosque => _mosqueId != null && _mosqueId!.isNotEmpty;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _mosqueId = p.getString(_kId); _mosqueName = p.getString(_kName);
    final json = p.getString(_kTimes);
    if (json != null) { try { _schedule = MosqueSchedule.fromJson(jsonDecode(json)); } catch (_) {} }
    notifyListeners();
    // Auto-refresh every 7 days if mosque selected
    _autoRefreshIfNeeded();
  }

  // ── Auto-refresh ──
  Future<void> _autoRefreshIfNeeded() async {
    if (!hasMosque) return;
    final p = await SharedPreferences.getInstance();
    final lastStr = p.getString(_kFetchedAt);
    if (lastStr == null) return;
    final last = DateTime.tryParse(lastStr);
    if (last == null || DateTime.now().difference(last) < const Duration(days: 7)) return;
    // Silent background refresh
    try {
      final s = await _fetchFromMawaqitByCoords(
        p.getDouble('mosque_lat') ?? 0,
        p.getDouble('mosque_lng') ?? 0,
      );
      if (s != null) {
        _schedule = s;
        await _saveSchedule(p, s);
      }
      await p.setString(_kFetchedAt, DateTime.now().toIso8601String());
      notifyListeners();
    } catch (_) {}
  }

  // ── Step 1: nearby mosques (cached 7 days) ──
  Future<List<MosqueData>> fetchNearby(double lat, double lng, {int radius = 10000}) async {
    final p = await SharedPreferences.getInstance();
    // Check cache
    final cacheJson = p.getString(_kCache);
    final cacheAt = p.getString(_kCacheAt);
    if (cacheJson != null && cacheAt != null) {
      final at = DateTime.tryParse(cacheAt);
      if (at != null && DateTime.now().difference(at) < _cacheTtl) {
        final key = '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
        final cachedKey = p.getString('mosque_cache_coords') ?? '';
        if (cachedKey == key) {
          return (jsonDecode(cacheJson) as List).map((e) => MosqueData.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    }
    // Fetch fresh
    try {
      final uri = Uri.parse('$_tbBase/mosques/nearby?lat=$lat&lng=$lng&radius=$radius&limit=20');
      final res = await http.get(uri, headers: {'Accept': 'application/json'});
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body)['data'] as List? ?? [];
      final list = data.map((e) => MosqueData.fromJson(e as Map<String, dynamic>)).toList();
      // Cache
      final key = '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
      await p.setString('mosque_cache_coords', key);
      await p.setString(_kCache, jsonEncode(data));
      await p.setString(_kCacheAt, DateTime.now().toIso8601String());
      return list;
    } catch (_) { return []; }
  }

  // ── Step 2: Mawaqit scraper for ONE mosque by coordinates ──
  /// Tries to find the mosque on Mawaqit by matching coordinates within ~500m.
  /// If found, extracts the real prayer times from the page's confData.
  Future<MosqueSchedule?> _fetchFromMawaqitByCoords(double lat, double lng) async {
    try {
      // Mawaqit has a nearby endpoint: /ar/map/data?lat=...&lng=...
      final mapUri = Uri.parse('https://mawaqit.net/ar/map/data?lat=$lat&lng=$lng');
      final mapRes = await http.get(mapUri, headers: {'Accept': 'application/json'});
      if (mapRes.statusCode != 200) return null;
      final mosques = jsonDecode(mapRes.body) as List?;
      if (mosques == null || mosques.isEmpty) return null;

      // Find closest match within 500m
      Map<String, dynamic>? best;
      double bestDist = double.infinity;
      for (final m in mosques) {
        final mLat = (m['lat'] as num?)?.toDouble() ?? 0;
        final mLng = (m['lng'] as num?)?.toDouble() ?? 0;
        final dist = _distKm(lat, lng, mLat, mLng) * 1000;
        if (dist < bestDist && dist < 500) { bestDist = dist; best = m as Map<String, dynamic>?; }
      }
      if (best == null) return null;

      final slug = best['slug']?.toString() ?? best['id']?.toString();
      if (slug == null || slug.isEmpty) return null;

      // Fetch the mosque page
      final pageUri = Uri.parse('https://mawaqit.net/ar/m/$slug');
      final pageRes = await http.get(pageUri);
      if (pageRes.statusCode != 200) return null;

      // Extract confData from the page
      final body = pageRes.body;
      final confMatch = RegExp(r'var confData = (\{.*?\});', dotAll: true).firstMatch(body);
      if (confMatch == null) return null;

      final confJson = jsonDecode(confMatch.group(1)!) as Map<String, dynamic>;
      return MosqueSchedule.fromMawaqit(confJson);
    } catch (_) { return null; }
  }

  // ── Step 3: get times (Mawaqit first, AlAdhan fallback) ──
  Future<MosqueWithTimes?> timesForMosque(MosqueData m) async {
    // Try Mawaqit real times first
    final mw = await _fetchFromMawaqitByCoords(m.latitude, m.longitude);
    if (mw != null && mw.fajr != '--:--') {
      // Update name if Mawaqit has Arabic
      return MosqueWithTimes(mosque: m, schedule: mw, source: 'Mawaqit');
    }
    // Fallback to AlAdhan
    final adhan = await _fromAlAdhan(m);
    if (adhan != null) return MosqueWithTimes(mosque: m, schedule: adhan, source: 'AlAdhan');
    return null;
  }

  Future<MosqueSchedule?> _fromAlAdhan(MosqueData m) async {
    final method = _methodForCountry(m.country);
    try {
      final now = DateTime.now();
      final uri = Uri.parse('$_alAdhan/timings/${now.day}-${now.month}-${now.year}?latitude=${m.latitude}&longitude=${m.longitude}&method=$method');
      final res = await http.get(uri);
      if (res.statusCode != 200) return null;
      final timings = jsonDecode(res.body)['data']?['timings'] as Map<String, dynamic>?;
      return timings != null ? MosqueSchedule.fromAlAdhan(timings) : null;
    } catch (_) { return null; }
  }

  // ── Full discovery pipeline with progress ──
  Future<List<MosqueWithTimes>> discoverNearby(double lat, double lng, {DiscoverProgress? onProgress, bool translateToArabic = false}) async {
    onProgress?.call('تحديد موقعك...', 'جارٍ التحقق من إحداثيات GPS');
    await Future.delayed(const Duration(milliseconds: 600));

    onProgress?.call('تم تحديد الموقع ✓', 'خط العرض: ${lat.toStringAsFixed(4)}، خط الطول: ${lng.toStringAsFixed(4)}');

    onProgress?.call('البحث عن المساجد القريبة...', 'جارٍ استعلام قاعدة بيانات المساجد');
    final mosques = await fetchNearby(lat, lng);
    if (mosques.isEmpty) {
      onProgress?.call('لم نعثر على مساجد', 'تأكد من اتصالك بالإنترنت وحاول مجددًا');
      return [];
    }
    onProgress?.call('تم العثور على ${mosques.length} مسجد', 'المساجد ضمن نطاق ١٠ كم من موقعك');

    // ── Translate names to Arabic if requested ──
    if (translateToArabic) {
      onProgress?.call('ترجمة أسماء المساجد...', 'جارٍ ترجمة الأسماء إلى العربية');
      for (int i = 0; i < mosques.length; i++) {
        final m = mosques[i];
        if (!_hasArabic(m.name)) {
          final translated = await _translateName(m.name);
          if (translated != null) {
            mosques[i] = MosqueData(id: m.id, name: translated, latitude: m.latitude, longitude: m.longitude,
                distanceMeters: m.distanceMeters, city: m.city, country: m.country);
          }
        }
        await Future.delayed(const Duration(milliseconds: 80));
      }
    }

    onProgress?.call('استدعاء أوقات الصلاة...', 'جارٍ التحقق من مواقيت المساجد');
    final out = <MosqueWithTimes>[];
    for (int i = 0; i < mosques.length; i++) {
      final m = mosques[i];
      onProgress?.call('فحص ${m.name}...', '${i + 1} من ${mosques.length} — جارٍ استدعاء الأوقات');
      final entry = await timesForMosque(m);
      if (entry != null) out.add(entry);
      await Future.delayed(const Duration(milliseconds: 150));
    }
    out.sort((a, b) => a.mosque.distanceMeters.compareTo(b.mosque.distanceMeters));

    if (out.isNotEmpty) {
      onProgress?.call('اكتمل! ${out.length} مسجد متاح', 'الأوقات معروضة وأقرب مسجد في الأعلى');
    } else {
      onProgress?.call('لا توجد أوقات متاحة', 'لم نتمكن من الحصول على أوقات لأي مسجد قريب');
    }

    return out;
  }

  // ── Translation helpers ──
  final GoogleTranslator _translator = GoogleTranslator();
  static const _kTransCache = 'mosque_trans_cache';

  bool _hasArabic(String text) => RegExp(r'[\u0600-\u06FF]').hasMatch(text);

  Future<String?> _translateName(String text) async {
    try {
      final p = await SharedPreferences.getInstance();
      final cacheJson = p.getString(_kTransCache);
      final Map<String, dynamic> cache = cacheJson != null ? jsonDecode(cacheJson) as Map<String, dynamic> : <String, dynamic>{};
      if (cache.containsKey(text)) return cache[text] as String?;

      final result = await _translator.translate(text, to: 'ar');
      final translated = result.text;
      if (translated.isNotEmpty && translated != text) {
        cache[text] = translated;
        await p.setString(_kTransCache, jsonEncode(cache));
        return translated;
      }
      return null;
    } catch (_) { return null; }
  }

  // ── Save selection ──
  Future<bool> selectMosque(MosqueWithTimes entry) async {
    _mosqueId = entry.mosque.id; _mosqueName = entry.mosque.name; _schedule = entry.schedule;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kId, entry.mosque.id); await p.setString(_kName, entry.mosque.name);
    await p.setDouble('mosque_lat', entry.mosque.latitude); await p.setDouble('mosque_lng', entry.mosque.longitude);
    await _saveSchedule(p, entry.schedule);
    await p.setString(_kFetchedAt, DateTime.now().toIso8601String());
    notifyListeners(); return true;
  }

  Future<void> _saveSchedule(SharedPreferences p, MosqueSchedule s) async {
    final tj = <String, String>{'fajr': s.fajr, 'dhuhr': s.dhuhr, 'asr': s.asr, 'maghrib': s.maghrib, 'isha': s.isha};
    if (s.sunrise != null && s.sunrise != '--:--') tj['sunrise'] = s.sunrise!;
    await p.setString(_kTimes, jsonEncode(tj));
  }

  Future<void> resetToDefault() async {
    _mosqueId = null; _mosqueName = null; _schedule = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kId); await p.remove(_kName); await p.remove(_kTimes);
    await p.remove('mosque_lat'); await p.remove('mosque_lng');
    await p.remove(_kFetchedAt);
    notifyListeners();
  }

  // ── Helpers ──
  static double _distKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = _sinHalf(dLat) * _sinHalf(dLat) +
        _cosRad(_rad(lat1)) * _cosRad(_rad(lat2)) * _sinHalf(dLng) * _sinHalf(dLng);
    return r * 2 * _atan2Approx(a);
  }
  static double _rad(double deg) => deg * 0.017453292519943295;
  static double _sinHalf(double x) => x * (1 - x * x / 6); // Taylor: sin(x) ≈ x - x³/6
  static double _cosRad(double r) => 1 - r * r / 2; // Taylor: cos(x) ≈ 1 - x²/2
  static double _atan2Approx(double a) {
    final s = a < 0 ? -1 : 1;
    final v = a.abs();
    return s * (v / (1 + 0.28 * v * v)); // approx atan(sqrt(a)) for small a
  }

  static int _methodForCountry(String country) {
    final c = country.toLowerCase();
    if (c.contains('saudi') || c.contains('السعودية')) return 4;
    if (c.contains('egypt') || c.contains('مصر')) return 5;
    if (c.contains('morocco') || c.contains('المغرب')) return 21;
    if (c.contains('turkey') || c.contains('تركيا')) return 13;
    if (c.contains('pakistan') || c.contains('باكستان')) return 1;
    if (c.contains('iran') || c.contains('إيران')) return 7;
    if (c.contains('united states') || c.contains('canada')) return 2;
    if (c == 'uk' || c.contains('france') || c.contains('germany') || c.contains('belgium') || c.contains('netherlands') || c.contains('italy') || c.contains('spain')) return 12;
    return 2;
  }
}
