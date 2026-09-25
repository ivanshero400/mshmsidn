import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../services/app_theme_colors.dart';
import '../services/qibla_service.dart';
import '../services/qibla_sound_service.dart';

/// Qibla finder — "target lock" design.
///
/// A fixed needle at the top represents where the phone points; the compass
/// rose rotates underneath using the gyro-fused TRUE-north heading from
/// [QiblaService]. A colored "remaining turn" arc connects the needle to the
/// Kaaba marker and shrinks as the user rotates, changing red → amber → green.
/// Real-time guidance (turn right/left + degrees), Geiger-style ticks that
/// speed up near alignment, a chime + pulse on lock, real sensor-driven
/// calibration, tilt and magnetic-interference warnings.
class QiblaPage extends StatefulWidget {
  final double latitude;
  final double longitude;
  final bool isNight;
  const QiblaPage({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.isNight,
  });

  @override
  State<QiblaPage> createState() => _QiblaPageState();
}

class _QiblaPageState extends State<QiblaPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final QiblaService _qibla;
  final QiblaSoundService _sound = QiblaSoundService();

  late final AnimationController _pulseCtrl;
  QiblaState _prevState = QiblaState.searching;
  bool _calibrationSheetOpen = false;
  bool _calibrationAutoPrompted = false; // auto-open at most once per visit

  bool get n => widget.isNight;
  Color get bg => n ? AppThemeColors.nightBg : AppThemeColors.dayBg;
  Color get cbg => n ? AppThemeColors.nightCardBg : AppThemeColors.dayCardBg;
  Color get t1 => n ? AppThemeColors.nightTextPrimary : AppThemeColors.dayTextPrimary;
  Color get t2 => n ? AppThemeColors.nightTextSecondary : AppThemeColors.dayTextSecondary;
  Color get tDim => n ? AppThemeColors.nightTextDim : AppThemeColors.dayTextDim;
  Color get bdr => n ? AppThemeColors.nightBorder : AppThemeColors.dayBorder;

  static const Color gold = Color(0xFFD4A853);
  static const Color cFar = Color(0xFFE2574C);
  static const Color cNear = Color(0xFFE8A23D);
  static const Color cLocked = Color(0xFF58B97D);

  Color get stateColor => switch (_qibla.state) {
        QiblaState.locked => cLocked,
        QiblaState.near => cNear,
        QiblaState.far => cFar,
        QiblaState.searching => tDim,
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _qibla = QiblaService(latitude: widget.latitude, longitude: widget.longitude);
    _qibla.addListener(_onQiblaUpdate);
    _qibla.start();
    _sound.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _qibla.removeListener(_onQiblaUpdate);
    _qibla.dispose();
    _sound.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Don't burn sensors/battery while the page is hidden.
    if (state == AppLifecycleState.paused) {
      _qibla.stop();
    } else if (state == AppLifecycleState.resumed) {
      _qibla.start();
    }
  }

  void _onQiblaUpdate() {
    if (!mounted) return;

    // Sound state transitions
    final s = _qibla.state;
    if (s != _prevState) {
      if (s == QiblaState.locked) {
        _sound.playLocked();
      } else if (_prevState == QiblaState.locked) {
        _sound.playLost();
      }
      _prevState = s;
    }
    _sound.updateTicks(_qibla.offset.abs(), locked: s == QiblaState.locked);

    // Real-accuracy-driven calibration prompt (once per visit; the toolbar
    // button can always reopen it manually)
    if (_qibla.needsCalibration &&
        !_calibrationSheetOpen &&
        !_calibrationAutoPrompted &&
        _qibla.hasFix) {
      _calibrationAutoPrompted = true;
      _openCalibrationSheet();
    }

    setState(() {});
  }

  // ── Guidance text ──

  String get _guidanceText {
    if (!_qibla.hasFix) return 'جارٍ قراءة المستشعرات…';
    final d = _qibla.offset;
    final abs = d.abs();
    if (_qibla.state == QiblaState.locked) return 'أنت الآن باتجاه القبلة';
    final dir = d > 0 ? 'يمينًا' : 'يسارًا';
    if (abs < 12) return 'اقتربت جدًا — قليلًا $dir';
    return 'استدر $dir ${abs.round()}°';
  }

  IconData? get _guidanceIcon {
    if (_qibla.state == QiblaState.locked) return Icons.check_circle_rounded;
    if (!_qibla.hasFix) return null;
    return _qibla.offset > 0
        ? Icons.rotate_right_rounded
        : Icons.rotate_left_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final locked = _qibla.state == QiblaState.locked;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: _iconBtn(Icons.arrow_back_rounded, () => Navigator.pop(context)),
        title: Text('القبلة',
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: t1)),
        centerTitle: true,
        actions: [
          _iconBtn(
            _sound.enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            () => setState(() => _sound.enabled = !_sound.enabled),
            active: _sound.enabled,
          ),
          _iconBtn(Icons.compass_calibration_rounded, _openCalibrationSheet,
              active: _qibla.needsCalibration),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 4),
            _guidanceBanner(locked),
            const Spacer(),
            _dial(locked),
            const Spacer(),
            _warningChips(),
            const SizedBox(height: 12),
            _infoRow(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, {bool active = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cbg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? gold.withValues(alpha: 0.5) : bdr),
          ),
          child: Icon(icon, size: 19, color: active ? gold : t1),
        ),
      );

  // ── Guidance banner ──

  Widget _guidanceBanner(bool locked) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(horizontal: 28),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: stateColor.withValues(alpha: n ? 0.12 : 0.15),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: stateColor.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_guidanceIcon != null) ...[
            Icon(_guidanceIcon, size: 26, color: stateColor),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              _guidanceText,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: locked ? cLocked : t1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Compass dial ──

  Widget _dial(bool locked) {
    final size = math.min(MediaQuery.of(context).size.width - 56, 330.0);
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, _) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _DialPainter(
                heading: _qibla.heading,
                qiblaBearing: _qibla.qiblaBearing,
                stateColor: stateColor,
                locked: locked,
                pulse: _pulseCtrl.value,
                isNight: n,
              ),
            ),
            _centerReadout(locked),
          ],
        ),
      ),
    );
  }

  Widget _centerReadout(bool locked) {
    final abs = _qibla.offset.abs();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (locked) ...[
          Icon(Icons.check_rounded, size: 44, color: cLocked),
          Text('القِبلة',
              style: GoogleFonts.inter(
                  fontSize: 20, fontWeight: FontWeight.w800, color: cLocked)),
        ] else ...[
          Text(
            _qibla.hasFix ? '${abs.round()}°' : '--',
            style: GoogleFonts.lexend(
              fontSize: 46,
              fontWeight: FontWeight.w300,
              color: t1,
            ),
          ),
          Text(
            _qibla.hasFix ? (_qibla.offset > 0 ? 'إلى اليمين' : 'إلى اليسار') : '',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: stateColor),
          ),
        ],
      ],
    );
  }

  // ── Warnings ──

  Widget _warningChips() {
    final chips = <Widget>[];
    if (_qibla.tooTilted) {
      chips.add(_chip(Icons.screen_rotation_alt_rounded, 'ضع الهاتف بشكل مستوٍ', cNear));
    }
    if (!_qibla.fieldOk) {
      chips.add(_chip(Icons.warning_amber_rounded, 'تشويش مغناطيسي — ابتعد عن المعادن', cFar));
    }
    if (chips.isEmpty) return const SizedBox(height: 30);
    return Wrap(spacing: 8, runSpacing: 6, children: chips);
  }

  Widget _chip(IconData icon, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
        ]),
      );

  // ── Info cards ──

  Widget _infoRow() {
    final km = _qibla.distanceMeters / 1000;
    final distStr = NumberFormat('#,##0', 'ar').format(km.round());
    final accLabel = switch (_qibla.accuracy) {
      QiblaAccuracy.high => 'عالية',
      QiblaAccuracy.medium => 'متوسطة',
      QiblaAccuracy.low => 'منخفضة',
      QiblaAccuracy.unreliable => 'غير موثوقة',
    };
    final accColor = switch (_qibla.accuracy) {
      QiblaAccuracy.high => cLocked,
      QiblaAccuracy.medium => cNear,
      _ => cFar,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(children: [
        _infoCard('المسافة إلى مكة', '$distStr كم'),
        const SizedBox(width: 8),
        _infoCard('زاوية القبلة', '${_qibla.qiblaBearing.toStringAsFixed(1)}°'),
        const SizedBox(width: 8),
        _infoCard('دقة البوصلة', accLabel, valueColor: accColor,
            onTap: _openCalibrationSheet),
      ]),
    );
  }

  Widget _infoCard(String label, String value,
          {Color? valueColor, VoidCallback? onTap}) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: cbg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: bdr),
            ),
            child: Column(children: [
              Text(label,
                  style: GoogleFonts.inter(fontSize: 10, color: tDim),
                  textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(value,
                  style: GoogleFonts.lexend(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: valueColor ?? t1),
                  textAlign: TextAlign.center),
            ]),
          ),
        ),
      );

  // ── Calibration (driven by REAL sensor accuracy) ──

  void _openCalibrationSheet() {
    if (_calibrationSheetOpen || !mounted) return;
    _calibrationSheetOpen = true;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: bg,
      isDismissible: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _CalibrationSheet(qibla: _qibla, isNight: n),
    ).whenComplete(() => _calibrationSheetOpen = false);
  }
}

// ═══════════════════ CALIBRATION SHEET ═══════════════════

class _CalibrationSheet extends StatefulWidget {
  final QiblaService qibla;
  final bool isNight;
  const _CalibrationSheet({required this.qibla, required this.isNight});

  @override
  State<_CalibrationSheet> createState() => _CalibrationSheetState();
}

class _CalibrationSheetState extends State<_CalibrationSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat();
    widget.qibla.addListener(_check);
  }

  @override
  void dispose() {
    widget.qibla.removeListener(_check);
    _anim.dispose();
    super.dispose();
  }

  void _check() {
    if (!mounted) return;
    // Auto-dismiss the moment the OS reports the magnetometer is calibrated.
    // The listener fires ~30×/s, so guard with a flag: popping more than once
    // would pop the qibla page (and beyond) too → black screen.
    if (widget.qibla.accuracy == QiblaAccuracy.high) {
      if (_popped) return;
      _popped = true;
      widget.qibla.removeListener(_check);
      Navigator.of(context).pop();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.isNight;
    final t1 = n ? AppThemeColors.nightTextPrimary : AppThemeColors.dayTextPrimary;
    final t2 = n ? AppThemeColors.nightTextSecondary : AppThemeColors.dayTextSecondary;
    final acc = widget.qibla.accuracy;
    final accLabel = switch (acc) {
      QiblaAccuracy.high => 'عالية ✓',
      QiblaAccuracy.medium => 'متوسطة',
      QiblaAccuracy.low => 'منخفضة',
      QiblaAccuracy.unreliable => 'غير موثوقة',
    };

    return Padding(
      padding: EdgeInsets.fromLTRB(28, 16, 28, 32 + MediaQuery.of(context).viewPadding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: t2.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        Text('معايرة البوصلة',
            style: GoogleFonts.inter(
                fontSize: 18, fontWeight: FontWeight.w700, color: t1)),
        const SizedBox(height: 8),
        Text(
          'حرّك الهاتف ببطء على شكل الرقم 8 في الهواء.\nستُغلق هذه النافذة تلقائيًا عند اكتمال المعايرة.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 13, height: 1.7, color: t2),
        ),
        const SizedBox(height: 24),
        // Animated figure-8 path
        AnimatedBuilder(
          animation: _anim,
          builder: (_, _) => CustomPaint(
            size: const Size(180, 90),
            painter: _Figure8Painter(progress: _anim.value),
          ),
        ),
        const SizedBox(height: 24),
        Text('الدقة الحالية: $accLabel',
            style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: acc == QiblaAccuracy.high
                    ? const Color(0xFF58B97D)
                    : const Color(0xFFD4A853))),
      ]),
    );
  }
}

class _Figure8Painter extends CustomPainter {
  final double progress;
  _Figure8Painter({required this.progress});

  @override
  void paint(Canvas c, Size s) {
    final cx = s.width / 2, cy = s.height / 2;
    final a = s.width * 0.42, b = s.height * 0.42;

    Offset lemniscate(double t) {
      // Lissajous figure-8
      return Offset(cx + a * math.sin(t), cy + b * math.sin(2 * t) / 1.6);
    }

    final track = Paint()
      ..color = const Color(0xFFD4A853).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(lemniscate(0).dx, lemniscate(0).dy);
    for (double t = 0; t <= 2 * math.pi + 0.05; t += 0.05) {
      final p = lemniscate(t);
      path.lineTo(p.dx, p.dy);
    }
    c.drawPath(path, track);

    // Phone dot sweeping the path
    final t = progress * 2 * math.pi;
    c.drawCircle(lemniscate(t), 9,
        Paint()..color = const Color(0xFFD4A853));
    c.drawCircle(
        lemniscate(t),
        14,
        Paint()
          ..color = const Color(0xFFD4A853).withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _Figure8Painter o) => o.progress != progress;
}

// ═══════════════════ DIAL PAINTER ═══════════════════

class _DialPainter extends CustomPainter {
  final double heading;
  final double qiblaBearing;
  final Color stateColor;
  final bool locked;
  final double pulse; // 0..1 repeating
  final bool isNight;

  _DialPainter({
    required this.heading,
    required this.qiblaBearing,
    required this.stateColor,
    required this.locked,
    required this.pulse,
    required this.isNight,
  });

  static const gold = Color(0xFFD4A853);

  @override
  void paint(Canvas c, Size s) {
    final cx = s.width / 2, cy = s.height / 2;
    final center = Offset(cx, cy);
    final r = s.width / 2 - 10;

    final ringBg = isNight ? const Color(0xFF14141E) : const Color(0xFFF0E8D5);
    final tickDim = isNight ? const Color(0xFF3A3540) : const Color(0xFFC4B8A8);
    final cardC = gold;

    // ── Lock pulse rings (behind everything) ──
    if (locked) {
      for (final phase in [0.0, 0.5]) {
        final p = (pulse + phase) % 1.0;
        c.drawCircle(
          center,
          r * (0.55 + 0.45 * p),
          Paint()
            ..color = stateColor.withValues(alpha: (1 - p) * 0.25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      }
    }

    // ── Dial face ──
    c.drawCircle(center, r, Paint()..color = ringBg);
    c.drawCircle(
        center,
        r,
        Paint()
          ..color = locked ? stateColor.withValues(alpha: 0.7) : tickDim
          ..style = PaintingStyle.stroke
          ..strokeWidth = locked ? 2.2 : 1.4);

    // ── Rotating rose: ticks every 5°, majors every 30° ──
    for (int d = 0; d < 360; d += 5) {
      final isMajor = d % 30 == 0;
      final isCardinal = d % 90 == 0;
      final ang = (d - heading) * math.pi / 180 - math.pi / 2;
      final outer = r * 0.96;
      final inner = r * (isCardinal ? 0.86 : (isMajor ? 0.89 : 0.92));
      c.drawLine(
        center + Offset(math.cos(ang), math.sin(ang)) * inner,
        center + Offset(math.cos(ang), math.sin(ang)) * outer,
        Paint()
          ..color = isCardinal ? cardC : tickDim.withValues(alpha: isMajor ? 0.9 : 0.45)
          ..strokeWidth = isCardinal ? 2.2 : (isMajor ? 1.6 : 1.0)
          ..strokeCap = StrokeCap.round,
      );
    }

    // Cardinal letters (rotate with the rose)
    for (final e in const {0: 'ش', 90: 'ق', 180: 'ج', 270: 'غ'}.entries) {
      final ang = (e.key - heading) * math.pi / 180 - math.pi / 2;
      final pos = center + Offset(math.cos(ang), math.sin(ang)) * r * 0.76;
      _text(c, e.value, pos, e.key == 0 ? cardC : tickDim, 15, FontWeight.w800);
    }

    // ── Remaining-turn arc: from device-forward (top) to the qibla marker
    //    along the shortest direction; shrinks as alignment improves ──
    double off = qiblaBearing - heading;
    while (off > 180) {
      off -= 360;
    }
    while (off <= -180) {
      off += 360;
    }
    final arcR = r * 0.62;
    if (!locked && off.abs() > 1.5) {
      final sweep = off * math.pi / 180;
      c.drawArc(
        Rect.fromCircle(center: center, radius: arcR),
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..color = stateColor.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
      // Arrowhead at the arc end pointing in the turn direction
      final endAng = -math.pi / 2 + sweep;
      final tip = center + Offset(math.cos(endAng), math.sin(endAng)) * arcR;
      final tangent = endAng + (off > 0 ? math.pi / 2 : -math.pi / 2);
      _arrowHead(c, tip, tangent, stateColor);
    }

    // ── Kaaba marker on the ring at the qibla bearing ──
    final qAng = (qiblaBearing - heading) * math.pi / 180 - math.pi / 2;
    final qPos = center + Offset(math.cos(qAng), math.sin(qAng)) * r * 0.62;
    // Halo grows as you get closer
    final halo = locked ? 22.0 : (14.0 + 8.0 * (1 - (off.abs() / 180))).clamp(14.0, 22.0);
    c.drawCircle(
        qPos,
        halo,
        Paint()
          ..color = (locked ? stateColor : gold).withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    _kaaba(c, qPos, 13, locked ? stateColor : gold);

    // ── Fixed device-forward needle at top ──
    final needle = Path()
      ..moveTo(cx, cy - r + 2)
      ..lineTo(cx - 9, cy - r + 24)
      ..lineTo(cx, cy - r + 18)
      ..lineTo(cx + 9, cy - r + 24)
      ..close();
    c.drawPath(needle, Paint()..color = locked ? stateColor : gold);

    // ── Inner readout disc ──
    c.drawCircle(center, r * 0.40,
        Paint()..color = isNight ? const Color(0xFF0E0E16) : const Color(0xFFFBF7F0));
    c.drawCircle(
        center,
        r * 0.40,
        Paint()
          ..color = locked ? stateColor.withValues(alpha: 0.6) : tickDim.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
  }

  void _arrowHead(Canvas c, Offset tip, double dirAngle, Color color) {
    const len = 11.0;
    final p = Path()
      ..moveTo(tip.dx + math.cos(dirAngle) * len, tip.dy + math.sin(dirAngle) * len)
      ..lineTo(tip.dx + math.cos(dirAngle + 2.5) * len * 0.7,
          tip.dy + math.sin(dirAngle + 2.5) * len * 0.7)
      ..lineTo(tip.dx + math.cos(dirAngle - 2.5) * len * 0.7,
          tip.dy + math.sin(dirAngle - 2.5) * len * 0.7)
      ..close();
    c.drawPath(p, Paint()..color = color);
  }

  /// Tiny Kaaba glyph: dark cube, gold kiswa band, door.
  void _kaaba(Canvas c, Offset at, double size, Color accent) {
    final rect = Rect.fromCenter(center: at, width: size * 1.5, height: size * 1.5);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
    c.drawRRect(rrect, Paint()..color = const Color(0xFF1A1A1A));
    c.drawRRect(
        rrect,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4);
    // Kiswa band
    c.drawLine(
      Offset(rect.left + 1.5, rect.top + rect.height * 0.30),
      Offset(rect.right - 1.5, rect.top + rect.height * 0.30),
      Paint()
        ..color = accent
        ..strokeWidth = 2,
    );
  }

  void _text(Canvas c, String s, Offset at, Color color, double size, FontWeight w) {
    final tp = TextPainter(
      text: TextSpan(
          text: s, style: TextStyle(color: color, fontSize: size, fontWeight: w)),
      textDirection: TextDirection.rtl,
    )..layout();
    tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _DialPainter o) =>
      o.heading != heading ||
      o.locked != locked ||
      o.pulse != pulse ||
      o.stateColor != stateColor;
}
