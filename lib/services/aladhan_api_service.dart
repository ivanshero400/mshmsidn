import 'dart:convert';
import 'package:http/http.dart' as http;

/// AlAdhan API service – completely free, no API key required
/// Base URL: https://api.aladhan.com/v1
class AlAdhanApiService {
  static const _base = 'https://api.aladhan.com/v1';

  /// All supported calculation methods
  static const Map<int, String> calculationMethods = {
    0: 'شبكة - أقرب سلطة (تلقائي)',
    1: 'جامعة العلوم الإسلامية، كراتشي',
    2: 'رابطة العالم الإسلامي (MWL)',
    3: 'رابطة أمريكا الشمالية (ISNA)',
    4: 'جامعة أم القرى، مكة المكرمة',
    5: 'الهيئة المصرية العامة للمساحة',
    7: 'معهد الجيوفيزياء، جامعة طهران',
    8: 'منطقة الخليج',
    9: 'الكويت',
    10: 'قطر',
    11: 'مجلس علماء إندونيسيا، سنغافورة',
    12: 'اتحاد المنظمات الإسلامية في فرنسا',
    13: 'الشؤون الدينية التركية',
    14: 'الإدارة الدينية لمسلمي روسيا',
    15: 'لجنة مراقبة الهلال',
    16: 'دبي، الإمارات',
    17: 'جابتن كماجوان إسلام ماليزيا (JAKIM)',
    18: 'تونس',
    19: 'الجزائر',
    20: 'وزارة الشؤون الدينية الإندونيسية',
    21: 'المغرب',
    22: 'الجماعة الإسلامية في لشبونة (البرتغال)',
    23: 'وزارة الأوقاف الأردنية',
    99: 'مخصص (تحديد الزوايا يدوياً)',
  };

  /// Static map of which methods differ most in Fajr/Isha angles
  static const Map<int, Map<String, String>> methodAngles = {
    1: {'fajr': '18°', 'isha': '18°'},
    2: {'fajr': '18°', 'isha': '17°'},
    3: {'fajr': '15°', 'isha': '15°'},
    4: {'fajr': '18.5°', 'isha': '90 دقيقة'},
    5: {'fajr': '19.5°', 'isha': '17.5°'},
    7: {'fajr': '17.7°', 'isha': '14°'},
    8: {'fajr': '19.5°', 'isha': '90 دقيقة'},
    12: {'fajr': '12°', 'isha': '12°'},
    13: {'fajr': '18°', 'isha': '17°'},
    20: {'fajr': '20°', 'isha': '18°'},
    23: {'fajr': '18°', 'isha': '18°'},
  };

  /// Fetch prayer times for given coordinates & method
  /// [madhab] 0=Shafi'i (standard), 1=Hanafi (Asr later)
  /// [fajrAngle] custom Fajr angle (12.0-20.0), only used when method=99
  /// [ishaAngle] custom Isha angle, only used when method=99
  /// [ishaMode] 'angle'|'minutes' – if minutes, ishaAngle is minutes after Maghrib
  Future<Map<String, String>> fetchTimings({
    required double latitude,
    required double longitude,
    int method = 12,
    int madhab = 0,
    double? fajrAngle,
    double? ishaAngle,
    String ishaMode = 'angle',
    int month = 0,
    int year = 0,
  }) async {
    final now = DateTime.now();
    final d = now.day;
    final m = month > 0 ? month : now.month;
    final y = year > 0 ? year : now.year;

    final params = StringBuffer('latitude=$latitude&longitude=$longitude');

    if (method == 99 && fajrAngle != null) {
      // Custom method: methodSettings=fajrAngle,null,ishaAngleOrMins
      final ishaStr = ishaMode == 'minutes'
          ? (ishaAngle?.toStringAsFixed(1) ?? '90')
          : (ishaAngle?.toStringAsFixed(1) ?? '12');
      params.write('&method=99&methodSettings=${fajrAngle.toStringAsFixed(1)},null,$ishaStr');
      if (ishaMode == 'minutes') {
        params.write('&ishaMethod=0'); // 0 = minutes (AlAdhan API convention in methodSettings)
      }
    } else {
      params.write('&method=$method');
    }

    // Madhab (0=Shafi, 1=Hanafi) – affects Asr only
    params.write('&madhab=$madhab');

    final url = Uri.parse('$_base/timings/$d-$m-$y?$params');

    final res = await http.get(url);
    if (res.statusCode != 200) {
      throw Exception('فشل الاتصال بـ AlAdhan API: ${res.statusCode}');
    }

    final json = jsonDecode(res.body);
    final timings = json['data']['timings'] as Map<String, dynamic>;

    // Map AlAdhan keys to our internal keys
    return {
      'FAJR': timings['Fajr']?.toString() ?? '--:--',
      'SUNRISE': timings['Sunrise']?.toString() ?? '--:--',
      'DHUHR': timings['Dhuhr']?.toString() ?? '--:--',
      'ASR': timings['Asr']?.toString() ?? '--:--',
      'MAGHRIB': timings['Maghrib']?.toString() ?? '--:--',
      'ISHA': timings['Isha']?.toString() ?? '--:--',
    };
  }
}
