import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/ar.dart' as ar_data;
import '../l10n/en.dart' as en_data;
import '../l10n/fa.dart' as fa_data;
import '../l10n/ku.dart' as ku_data;
import '../l10n/de.dart' as de_data;

class L10nService extends ChangeNotifier {
  static const _key = 'app_language';
  static final Map<String, Map<String, String>> _langs = {
    'ar': ar_data.ar,
    'en': en_data.en,
    'fa': fa_data.fa,
    'ku': ku_data.ku,
    'de': de_data.de,
  };

  String _locale = 'ar';
  String get locale => _locale;
  bool get isArabic => _locale == 'ar';

  Map<String, String> get _strings => _langs[_locale] ?? _langs['ar']!;

  String t(String key, {String? line1, String? count, String? time, String? name, String? curr, String? total}) {
    var s = _strings[key] ?? key;
    if (line1 != null) s = s.replaceFirst('LINE1', line1);
    if (count != null) s = s.replaceFirst('COUNT', count);
    if (time != null) s = s.replaceFirst('TIME', time);
    if (name != null) s = s.replaceFirst('NAME', name);
    if (curr != null) s = s.replaceFirst('CURR', curr);
    if (total != null) s = s.replaceFirst('TOTAL', total);
    return s;
  }

  List<String> get supportedLocales => _langs.keys.toList();

  String localeName(String code) {
    switch (code) {
      case 'ar': return 'العربية';
      case 'en': return 'English';
      case 'fa': return 'فارسی';
      case 'ku': return 'کوردی';
      case 'de': return 'Deutsch';
      default: return code;
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && _langs.containsKey(saved)) {
      _locale = saved;
    }
    notifyListeners();
  }

  Future<void> setLocale(String code) async {
    if (!_langs.containsKey(code)) return;
    _locale = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, code);
    notifyListeners();
  }

  Future<void> toggle() => setLocale(_locale == 'ar' ? 'en' : 'ar');

  TextDirection get textDirection =>
      _locale == 'ar' ? TextDirection.rtl : TextDirection.ltr;
}
