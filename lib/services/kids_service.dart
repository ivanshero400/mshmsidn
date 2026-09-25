import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks a child's daily prayer completions, stars and day-streak.
///
/// All state is persisted locally. The "prayed today" set resets automatically
/// on a new calendar day; the streak counts consecutive days in which all five
/// obligatory prayers were marked.
class KidsService extends ChangeNotifier {
  static const _keyDate = 'kids_date';
  static const _keyPrayedToday = 'kids_prayed_today';
  static const _keyStars = 'kids_stars';
  static const _keyStreak = 'kids_streak';
  static const _keyLastComplete = 'kids_last_complete';

  /// The five obligatory prayers shown to children (no sunrise / duha / night).
  static const List<String> fardPrayers = [
    'FAJR', 'DHUHR', 'ASR', 'MAGHRIB', 'ISHA'
  ];

  final Set<String> _prayedToday = {};
  int _stars = 0;
  int _streak = 0;
  String _lastCompleteDate = '';
  bool _loaded = false;

  bool get loaded => _loaded;
  Set<String> get prayedToday => _prayedToday;
  int get stars => _stars;
  int get streak => _streak;
  int get prayedCount => _prayedToday.length;
  bool isPrayed(String key) => _prayedToday.contains(key);
  bool get allDone => fardPrayers.every(_prayedToday.contains);

  static String _fmt(DateTime n) =>
      '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  static String _today() => _fmt(DateTime.now());
  static String _yesterday() =>
      _fmt(DateTime.now().subtract(const Duration(days: 1)));

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _stars = p.getInt(_keyStars) ?? 0;
    _streak = p.getInt(_keyStreak) ?? 0;
    _lastCompleteDate = p.getString(_keyLastComplete) ?? '';
    final savedDate = p.getString(_keyDate) ?? '';
    final today = _today();

    if (savedDate == today) {
      final csv = p.getString(_keyPrayedToday) ?? '';
      _prayedToday
        ..clear()
        ..addAll(csv.split(',').where((e) => e.isNotEmpty));
    } else {
      // New day → reset today's completions.
      _prayedToday.clear();
      await p.setString(_keyDate, today);
      await p.setString(_keyPrayedToday, '');
    }

    // Break the streak if a whole day was skipped (last completion is neither
    // today nor yesterday).
    if (_lastCompleteDate.isNotEmpty &&
        _lastCompleteDate != today &&
        _lastCompleteDate != _yesterday()) {
      _streak = 0;
      await p.setInt(_keyStreak, 0);
    }

    _loaded = true;
    notifyListeners();
  }

  /// Toggle a prayer's completed state for today. Awards a star when marked and
  /// removes it when unmarked; grants a bonus and advances the streak the first
  /// time all five are completed in a day.
  Future<void> togglePrayed(String key) async {
    if (!fardPrayers.contains(key)) return;
    final p = await SharedPreferences.getInstance();
    final wasAllDone = allDone;

    if (_prayedToday.contains(key)) {
      _prayedToday.remove(key);
      _stars = (_stars - 1).clamp(0, 1 << 30);
    } else {
      _prayedToday.add(key);
      _stars += 1;
    }

    await p.setString(_keyDate, _today());
    await p.setString(_keyPrayedToday, _prayedToday.join(','));
    await p.setInt(_keyStars, _stars);

    if (!wasAllDone && allDone) {
      final today = _today();
      if (_lastCompleteDate != today) {
        _streak = (_lastCompleteDate == _yesterday()) ? _streak + 1 : 1;
        _lastCompleteDate = today;
        _stars += 5; // bonus for completing the whole day
        await p.setInt(_keyStreak, _streak);
        await p.setString(_keyLastComplete, today);
        await p.setInt(_keyStars, _stars);
      }
    }

    notifyListeners();
  }
}
