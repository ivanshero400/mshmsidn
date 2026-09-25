import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/adhkar_data.dart';

/// Full-screen adhkar display (morning / evening / Surah al-Mulk).
///
/// Flow:
///  1. A 5-second "about to show" gate with a Cancel button — so the screen
///     never reveals dhikr text unexpectedly (e.g. while the phone is in a
///     bathroom). Cancelling closes it.
///  2. The adhkar content: scrollable, with a Hide button and swipe-down to
///     dismiss.
///  3. A "remind in 15 min" action (allowed at most twice per dhikr per day);
///     the reminder re-shows this very screen — including the 5-second gate.
class AdhkarDisplayPage extends StatefulWidget {
  const AdhkarDisplayPage({super.key});

  @override
  State<AdhkarDisplayPage> createState() => _AdhkarDisplayPageState();
}

class _AdhkarDisplayPageState extends State<AdhkarDisplayPage> {
  static const _channel = MethodChannel('azan.adhan.alarm');
  static const int snoozeMinutes = 15;
  static const int maxReminders = 2;

  static const Color gold = Color(0xFFE6BE63);
  static const Color bg0 = Color(0xFF0B1026);
  static const Color bg1 = Color(0xFF131A36);

  AdhkarType _type = AdhkarType.morning;
  bool _revealed = false; // false = countdown gate, true = content shown
  int _countdown = 5;
  Timer? _timer;
  int _remindersUsed = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    String? typeStr;
    try {
      final data = await _channel.invokeMethod('getAlarmData');
      if (data is Map && data['adhkarType'] is String) {
        typeStr = data['adhkarType'] as String;
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    // Opened from the home-screen adhkar widget: the native side writes the
    // current set (morning/evening) here for us to pick up.
    typeStr ??= prefs.getString('adhkar_widget_type');
    final type = adhkarTypeFromString(typeStr ?? 'morning');

    final today = DateTime.now().toString().substring(0, 10);
    final used = prefs.getInt('adhkar_remind_${type.name}_$today') ?? 0;

    if (mounted) {
      setState(() {
        _type = type;
        _remindersUsed = used;
      });
    }
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() {
      _countdown = 5;
      _revealed = false;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_countdown <= 1) {
        t.cancel();
        setState(() => _revealed = true);
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _close() async {
    _timer?.cancel();
    try {
      await _channel.invokeMethod('stopAlarm');
    } catch (_) {}
  }

  Future<void> _remindLater() async {
    _timer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toString().substring(0, 10);
    final key = 'adhkar_remind_${_type.name}_$today';
    await prefs.setInt(key, _remindersUsed + 1);
    try {
      await _channel.invokeMethod(
          'scheduleAdhkarReminder', {'type': _type.name, 'minutes': snoozeMinutes});
    } catch (_) {
      try {
        await _channel.invokeMethod('stopAlarm');
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [bg0, bg1, bg0],
            ),
          ),
          child: SafeArea(
            child: _revealed ? _contentView() : _gateView(),
          ),
        ),
      ),
    );
  }

  // ── Phase 1: 5-second gate ──
  Widget _gateView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        SizedBox(
          width: 130,
          height: 130,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: CircularProgressIndicator(
                  value: _countdown / 5,
                  strokeWidth: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: const AlwaysStoppedAnimation(gold),
                ),
              ),
              Text('$_countdown',
                  style: GoogleFonts.lexend(
                      fontSize: 48, fontWeight: FontWeight.w300, color: Colors.white)),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Text('سيتم عرض ${adhkarTitle(_type)}',
            style: GoogleFonts.inter(
                fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 10),
        Text('بعد $_countdown ثوانٍ…',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.white.withValues(alpha: 0.6))),
        const SizedBox(height: 8),
        Text('إن كنت في مكان غير مناسب، اضغط إلغاء',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: gold.withValues(alpha: 0.7))),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: GestureDetector(
            onTap: _close,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Text('إلغاء',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white70)),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Phase 2: content ──
  Widget _contentView() {
    final canRemind = _remindersUsed < maxReminders;
    return GestureDetector(
      // Swipe down to dismiss
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 250) _close();
      },
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: gold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    _type == AdhkarType.mulk
                        ? Icons.nightlight_round
                        : _type == AdhkarType.morning
                            ? Icons.wb_twilight_rounded
                            : Icons.nights_stay_rounded,
                    color: gold,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(adhkarTitle(_type),
                          style: GoogleFonts.inter(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      Text(adhkarSubtitle(_type),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontSize: 11, color: gold.withValues(alpha: 0.8))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Grab handle hint
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(
            child: _type == AdhkarType.mulk ? _mulkBody() : _listBody(),
          ),
          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _close,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        color: gold.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: gold.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_rounded, size: 18, color: gold),
                          const SizedBox(width: 6),
                          Text('إخفاء',
                              style: GoogleFonts.inter(
                                  fontSize: 15, fontWeight: FontWeight.w700, color: gold)),
                        ],
                      ),
                    ),
                  ),
                ),
                if (canRemind) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: _remindLater,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                        ),
                        child: Column(
                          children: [
                            Text('تذكير بعد ١٥ دقيقة',
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white70)),
                            Text('المتبقّي ${maxReminders - _remindersUsed}',
                                style: GoogleFonts.inter(
                                    fontSize: 10, color: Colors.white38)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listBody() {
    final list = _type == AdhkarType.morning ? morningAdhkar : eveningAdhkar;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final d = list[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                d.text,
                textAlign: TextAlign.right,
                style: GoogleFonts.notoNaskhArabic(
                    fontSize: 17, height: 2.0, color: Colors.white),
              ),
              if (d.count.isNotEmpty || d.source.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (d.count.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: gold.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(d.count,
                            style: GoogleFonts.lexend(
                                fontSize: 13, fontWeight: FontWeight.w700, color: gold)),
                      ),
                    if (d.source.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(d.source,
                            style: GoogleFonts.inter(
                                fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _mulkBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: gold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: gold.withValues(alpha: 0.3)),
          ),
          child: Text(kMulkFadl,
              style: GoogleFonts.notoNaskhArabic(
                  fontSize: 14.5, height: 1.9, color: Colors.white)),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Text(
            kMulkText,
            textAlign: TextAlign.justify,
            style: GoogleFonts.notoNaskhArabic(
                fontSize: 19, height: 2.3, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
