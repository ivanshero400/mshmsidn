import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_theme_colors.dart';
import '../services/fajr_alarm_sound_service.dart';

class FajrAlarmRecordingPage extends StatefulWidget {
  final FajrAlarmSoundService soundService;
  final bool isNight;

  const FajrAlarmRecordingPage({
    super.key,
    required this.soundService,
    required this.isNight,
  });

  @override
  State<FajrAlarmRecordingPage> createState() => _FajrAlarmRecordingPageState();
}

class _FajrAlarmRecordingPageState extends State<FajrAlarmRecordingPage> {
  Timer? _timer;
  bool _recording = false;
  bool _busy = false;
  bool _hasRecording = false;
  int _seconds = 0;
  String? _error;
  String? _recordingName;

  bool get n => widget.isNight;
  Color get bg => n ? AppThemeColors.nightBg : AppThemeColors.dayBg;
  Color get cbg => n ? AppThemeColors.nightCardBg : AppThemeColors.dayCardBg;
  Color get t1 =>
      n ? AppThemeColors.nightTextPrimary : AppThemeColors.dayTextPrimary;
  Color get t2 =>
      n ? AppThemeColors.nightTextSecondary : AppThemeColors.dayTextSecondary;
  Color get bdr => n ? AppThemeColors.nightBorder : AppThemeColors.dayBorder;
  Color get glw => n ? AppThemeColors.nightGlow : AppThemeColors.dayGlow;

  @override
  void dispose() {
    _timer?.cancel();
    if (_recording) {
      unawaited(widget.soundService.cancelRecording());
    }
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.soundService.startRecording();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'تعذر بدء التسجيل. تأكد من إذن الميكروفون.';
      });
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = false;
      _recording = true;
      _hasRecording = false;
      _recordingName = null;
      _seconds = 0;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  Future<void> _stop() async {
    if (_busy || !_recording) return;
    setState(() => _busy = true);
    _timer?.cancel();
    final saved = await widget.soundService.stopRecording();
    if (!mounted) return;
    if (saved == null) {
      setState(() {
        _busy = false;
        _recording = false;
        _error = 'لم يتم حفظ التسجيل. حاول مرة أخرى.';
      });
      return;
    }
    HapticFeedback.heavyImpact();
    setState(() {
      _busy = false;
      _recording = false;
      _hasRecording = true;
      _recordingName = saved.name;
    });
  }

  Future<void> _recordAgain() async {
    setState(() {
      _hasRecording = false;
      _recordingName = null;
      _seconds = 0;
      _error = null;
    });
    await _start();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          elevation: 0,
          foregroundColor: t1,
          title: Text(
            'تسجيل صوت مخصص',
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
            child: Column(
              children: [
                const Spacer(),
                _recordCircle(),
                const SizedBox(height: 28),
                Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: t1,
                  ),
                ),
                if (_recordingName != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _recordingName!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 13, color: t2),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFE2574C),
                    ),
                  ),
                ],
                const Spacer(),
                _actions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _statusText {
    if (_recording) return 'يتم التسجيل الآن  ${_formatSeconds(_seconds)}';
    if (_hasRecording) return 'تم حفظ التسجيل';
    return 'اضغط التسجيل واحفظ صوت المنبه';
  }

  Widget _recordCircle() {
    final active = _recording;
    return Container(
      width: 176,
      height: 176,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (active ? const Color(0xFFE2574C) : glw).withValues(
          alpha: active ? 0.18 : 0.14,
        ),
        border: Border.all(
          color: (active ? const Color(0xFFE2574C) : glw).withValues(
            alpha: 0.55,
          ),
          width: 2,
        ),
      ),
      child: Icon(
        active ? Icons.mic_rounded : Icons.mic_none_rounded,
        size: 74,
        color: active ? const Color(0xFFE2574C) : glw,
      ),
    );
  }

  Widget _actions() {
    if (_recording) {
      return _wideButton(
        label: _busy ? 'جار الحفظ' : 'إيقاف التسجيل',
        icon: Icons.stop_rounded,
        color: const Color(0xFFE2574C),
        onTap: _stop,
      );
    }
    if (_hasRecording) {
      return Row(
        children: [
          Expanded(
            child: _wideButton(
              label: 'إعادة تسجيل',
              icon: Icons.refresh_rounded,
              color: t2,
              onTap: _recordAgain,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _wideButton(
              label: 'موافق',
              icon: Icons.check_rounded,
              color: glw,
              onTap: () => Navigator.pop(context, true),
            ),
          ),
        ],
      );
    }
    return _wideButton(
      label: _busy ? 'جار البدء' : 'تسجيل',
      icon: Icons.fiber_manual_record_rounded,
      color: glw,
      onTap: _start,
    );
  }

  Widget _wideButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _busy ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.45),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: Icon(icon, size: 22),
        label: Text(
          label,
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  String _formatSeconds(int value) {
    final minutes = (value ~/ 60).toString().padLeft(2, '0');
    final seconds = (value % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
