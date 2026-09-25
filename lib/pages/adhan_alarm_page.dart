import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/adhan_sound_service.dart';
import '../services/vibe_service.dart';

/// شاشة الأذان — تظهر عند حلول وقت الصلاة.
///
/// تصميم إسلامي هادئ: خلفية ليلية عميقة، هالة متوهجة حول المسجد،
/// اسم الصلاة بخط عربي كبير، وزران دائريان للإيقاف والغفوة.
class AdhanAlarmPage extends StatefulWidget {
  const AdhanAlarmPage({super.key});

  @override
  State<AdhanAlarmPage> createState() => _AdhanAlarmPageState();
}

class _AdhanAlarmPageState extends State<AdhanAlarmPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _channel = MethodChannel('azan.adhan.alarm');
  static const int snoozeMinutes = 15;

  final AudioPlayer _player = AudioPlayer();
  String _prayerName = 'الصلاة';
  String _soundKey = '';
  VibeMode _vibe = VibeMode.off;
  bool _playing = false;
  bool _muted = false;
  bool _dismissing = false;

  // ── Theme ──
  static const Color gold = Color(0xFFD4A853);
  static const Color coral = Color(0xFFE0708C);
  static const Color bgDeep = Color(0xFF060914);
  static const Color bgMid = Color(0xFF0D1330);
  static const Color cardBg = Color(0xFF141C3A);

  // ── Animations ──
  late final AnimationController _glowCtrl;
  late final AnimationController _slideCtrl;
  late final AnimationController _pulseCtrl;
  late Animation<double> _slideAnim;
  bool _visible = false;

  // ═══ أسماء الصلوات بالعربية فقط ═══
  static const Map<String, String> _arabicNames = {
    'FAJR': 'الفجر',
    'SUNRISE': 'الشروق',
    'DHUHR': 'الظهر',
    'ASR': 'العصر',
    'MAGHRIB': 'المغرب',
    'ISHA': 'العشاء',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000))
      ..repeat();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _slideAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic);

    _loadAlarmData();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) { setState(() => _visible = true); _slideCtrl.forward(); }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopVibration();
    _player.dispose();
    _glowCtrl.dispose();
    _pulseCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAlarmData() async {
    try {
      final data = await _channel.invokeMethod('getAlarmData');
      if (data != null && mounted) {
        final raw = (data as Map)['prayerName'] as String? ?? 'الفجر';
        _vibe = await VibeService.get(raw);
        if (mounted) {
          setState(() {
            _prayerName = _toArabic(raw);
            _soundKey = (data)['soundKey'] as String? ?? '';
          });
        }
      }
    } catch (_) {}
    _startAdhan();
  }

  /// يضمن اسم الصلاة بالعربية دائماً للعرض
  String _toArabic(String name) {
    // إن كان عربياً بالفعل نُبقيه
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(name)) return name;
    // نبحث في الخريطة
    return _arabicNames[name] ?? 'الصلاة';
  }

  Future<void> _startAdhan() async {
    // Global mute — skip audio entirely but keep vibration
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('adhan_global_mute') == true) {
      setState(() => _playing = false);
      return;
    }
    if (_vibe != VibeMode.off) {
      try { await _channel.invokeMethod('startVibration'); } catch (_) {}
    }
    if (_vibe == VibeMode.only) {
      setState(() => _playing = false);
      return;
    }
    try {
      final soundService = AdhanSoundService();
      await soundService.init();
      final sound = soundService.sounds.isNotEmpty
          ? soundService.sounds.firstWhere(
              (s) => s.key == (_soundKey.isNotEmpty ? _soundKey : soundService.selectedKey),
              orElse: () => soundService.sounds.first)
          : null;

      if (sound != null && mounted) {
        if (sound.isLocal) {
          await _player.setFilePath(sound.url);
        } else {
          await _player.setUrl(sound.url);
        }
        await _player.setLoopMode(LoopMode.one);
        await _player.play();
        setState(() => _playing = true);
        _player.processingStateStream.listen((state) {
          if (state == ProcessingState.completed && mounted) {
            setState(() => _playing = false);
          }
        });
      }
    } catch (_) {
      HapticFeedback.heavyImpact();
    }
  }

  Future<void> _stopVibration() async {
    if (_vibe == VibeMode.off) return;
    try { await _channel.invokeMethod('stopVibration'); } catch (_) {}
  }

  // ── Actions ──

  Future<void> _stop() async {
    if (_dismissing) return;
    _dismissing = true;
    HapticFeedback.heavyImpact();
    await _stopVibration();
    try { await _player.stop(); } catch (_) {}
    try { await _channel.invokeMethod('stopAlarm'); } catch (_) {}
  }

  Future<void> _snooze() async {
    if (_dismissing) return;
    _dismissing = true;
    HapticFeedback.mediumImpact();
    await _stopVibration();
    try { await _player.stop(); } catch (_) {}
    try {
      await _channel.invokeMethod('scheduleSnooze', {'minutes': snoozeMinutes});
    } catch (_) {
      try { await _channel.invokeMethod('stopAlarm'); } catch (_) {}
    }
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
      _muted ? _player.pause() : _player.play();
    });
  }

  // ═══════════════════════════════════════════
  //  UI
  // ═══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 800),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [bgDeep, bgMid, bgDeep],
            ),
          ),
          child: SafeArea(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 800),
              opacity: _visible ? 1 : 0,
              child: Column(
                children: [
                  _topBar(),
                  const Spacer(flex: 2),
                  _mosqueGlow(),
                  const SizedBox(height: 20),
                  _prayerTitle(),
                  const Spacer(flex: 1),
                  _statusChip(),
                  const Spacer(flex: 2),
                  _actionButtons(),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── شريط علوي ──

  Widget _topBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    child: Row(
      children: [
        _iconBtn(Icons.volume_up_rounded, _toggleMute, active: !_muted),
        if (_muted)
          _iconBtn(Icons.volume_off_rounded, _toggleMute, active: false),
        const Spacer(),
        Text('﷽',
          style: GoogleFonts.amiri(fontSize: 22, color: gold.withValues(alpha: 0.5))),
      ],
    ),
  );

  // ── هالة المسجد ──

  Widget _mosqueGlow() {
    return AnimatedBuilder(
      animation: Listenable.merge([_glowCtrl, _pulseCtrl]),
      builder: (_, _) {
        final glowAngle = _glowCtrl.value * 2 * math.pi;
        final scale = 1 + _pulseCtrl.value * 0.05;
        return SizedBox(
          width: 240 * scale, height: 240 * scale,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 3; i >= 1; i--)
                Transform.rotate(
                  angle: glowAngle * (i.isOdd ? 1 : -1) * 0.25,
                  child: Container(
                    width: 120.0 + i * 48,
                    height: 120.0 + i * 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: gold.withValues(alpha: 0.05 + i * 0.04),
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    gold.withValues(alpha: 0.22), gold.withValues(alpha: 0.05), Colors.transparent,
                  ], stops: const [0.0, 0.5, 1.0]),
                  border: Border.all(color: gold.withValues(alpha: 0.35), width: 1.5),
                ),
                child: const Icon(Icons.mosque_rounded, size: 48, color: gold),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── اسم الصلاة ──

  Widget _prayerTitle() {
    return Column(
      children: [
        Text('حان وقت الصلاة',
          style: GoogleFonts.amiri(
            fontSize: 18, color: Colors.white.withValues(alpha: 0.5), letterSpacing: 2)),
        const SizedBox(height: 12),
        Text(_prayerName,
          style: GoogleFonts.amiri(fontSize: 50, fontWeight: FontWeight.w700,
            color: Colors.white, height: 1.1)),
        const SizedBox(height: 6),
        Container(height: 3, width: 40,
          decoration: BoxDecoration(
            color: gold.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(2))),
      ],
    );
  }

  // ── شريحة الحالة ──

  Widget _statusChip() {
    final icon = _vibe == VibeMode.only ? Icons.vibration_rounded : Icons.graphic_eq_rounded;
    final label = _vibe == VibeMode.only
        ? 'اهتزاز فقط'
        : _muted ? 'تم كتم الصوت' : _playing ? 'جارٍ رفع الأذان...' : 'انتظر...';
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 400),
      opacity: (_playing || _muted || _vibe == VibeMode.only) ? 0.85 : 0.3,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: gold.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: gold.withValues(alpha: 0.15)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: gold.withValues(alpha: 0.85)),
          const SizedBox(width: 8),
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: gold.withValues(alpha: 0.85))),
        ]),
      ),
    );
  }

  // ── زرا الإيقاف والغفوة ──

  Widget _actionButtons() {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(_slideAnim),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Row(children: [
          Expanded(child: _card(Icons.stop_rounded, 'إيقاف', null, coral, _stop)),
          const SizedBox(width: 24),
          Expanded(child: _card(Icons.snooze_rounded, 'غفوة', '١٥ دقيقة', gold, _snooze)),
        ]),
      ),
    );
  }

  Widget _card(IconData icon, String label, String? sub, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, child) => Transform.scale(scale: 1 + _pulseCtrl.value * 0.03, child: child),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.2),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 20)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [color.withValues(alpha: 0.4), color.withValues(alpha: 0.1)]),
                border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 14),
            Text(label, style: GoogleFonts.inter(
              fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(sub, style: GoogleFonts.inter(
                fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
            ],
          ]),
        ),
      ),
    );
  }

  // ── زر أيقونة ──

  Widget _iconBtn(IconData icon, VoidCallback onTap, {bool active = true}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42, height: 42,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? gold.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: active ? gold.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Icon(icon, size: 19, color: active ? gold : Colors.white38),
      ),
    );
  }
}
