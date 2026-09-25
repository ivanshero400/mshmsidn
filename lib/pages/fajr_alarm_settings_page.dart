import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'fajr_alarm_recording_page.dart';
import '../services/app_theme_colors.dart';
import '../services/fajr_alarm_config_service.dart';
import '../services/fajr_alarm_sound_service.dart';
import '../services/l10n_service.dart';
import '../services/prayer_times_service.dart';

class FajrAlarmSettingsPage extends StatefulWidget {
  final PrayerTimesService timesService;
  final L10nService l10n;
  final bool isNight;

  const FajrAlarmSettingsPage({
    super.key,
    required this.timesService,
    required this.l10n,
    required this.isNight,
  });

  @override
  State<FajrAlarmSettingsPage> createState() => _FajrAlarmSettingsPageState();
}

class _FajrAlarmSettingsPageState extends State<FajrAlarmSettingsPage> {
  final FajrAlarmConfigService _configService = FajrAlarmConfigService();
  final FajrAlarmSoundService _soundService = FajrAlarmSoundService();
  bool _loading = true;

  PrayerTimesService get ts => widget.timesService;
  bool get n => widget.isNight;

  Color get bg => n ? AppThemeColors.nightBg : AppThemeColors.dayBg;
  Color get cbg => n ? AppThemeColors.nightCardBg : AppThemeColors.dayCardBg;
  Color get t1 =>
      n ? AppThemeColors.nightTextPrimary : AppThemeColors.dayTextPrimary;
  Color get t2 =>
      n ? AppThemeColors.nightTextSecondary : AppThemeColors.dayTextSecondary;
  Color get tDim => n ? AppThemeColors.nightTextDim : AppThemeColors.dayTextDim;
  Color get bdr => n ? AppThemeColors.nightBorder : AppThemeColors.dayBorder;
  Color get glw => n ? AppThemeColors.nightGlow : AppThemeColors.dayGlow;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _configService.dispose();
    _soundService.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await Future.wait([
      _configService.ensureLoaded(timesService: ts),
      _soundService.ensureLoaded(),
    ]);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: ThemeData(
          scaffoldBackgroundColor: bg,
          colorScheme: ColorScheme.fromSeed(
            seedColor: glw,
            brightness: n ? Brightness.dark : Brightness.light,
          ),
        ),
        child: ListenableBuilder(
          listenable: Listenable.merge([_configService, _soundService]),
          builder: (context, _) {
            final config = _configService.config;
            return Scaffold(
              backgroundColor: bg,
              appBar: AppBar(
                backgroundColor: bg,
                elevation: 0,
                leading: _topIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.pop(context),
                ),
                title: Text(
                  'منبه الفجر',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: t1,
                  ),
                ),
                centerTitle: true,
                actions: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 10),
                    child: _powerButton(config.systemEnabled),
                  ),
                ],
              ),
              body: _loading
                  ? Center(child: CircularProgressIndicator(color: glw))
                  : _buildBody(config),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(FajrAlarmConfig config) {
    final enabled = config.systemEnabled;
    final maxAfterFajr = FajrAlarmConfigService.maxAfterFajrMinutes(ts);
    final afterFajr = config.startAfterFajrMinutes
        .clamp(0, maxAfterFajr)
        .toInt();
    final beforeActive = config.startBeforeFajrMinutes > 0;
    final afterActive = config.startAfterFajrMinutes > 0 && maxAfterFajr > 0;
    final fajr = ts.getTime('FAJR') ?? '--:--';
    final sunrise = ts.getTime('SUNRISE') ?? '--:--';

    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        IgnorePointer(
          ignoring: !enabled,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: enabled ? 1 : 0.38,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _section('المنبهات'),
                const SizedBox(height: 8),
                _alarmToggle(
                  icon: Icons.wb_twilight_rounded,
                  title: 'منبه الفجر',
                  value: config.fajrEnabled,
                  onTap: () =>
                      _configService.setFajrEnabled(!config.fajrEnabled),
                ),
                const SizedBox(height: 8),
                _alarmToggle(
                  icon: Icons.nights_stay_rounded,
                  title: 'منبه العشاء',
                  value: config.ishaEnabled,
                  onTap: () =>
                      _configService.setIshaEnabled(!config.ishaEnabled),
                ),
                const SizedBox(height: 22),
                _section('صوت المنبه'),
                const SizedBox(height: 8),
                _alarmSoundCard(),
                const SizedBox(height: 22),
                _section('وقت البدء'),
                const SizedBox(height: 8),
                _startModeToggleCard(
                  icon: Icons.keyboard_double_arrow_left_rounded,
                  title: 'قبل الفجر',
                  value: beforeActive,
                  onTap: () =>
                      _configService.setStartBeforeFajrEnabled(!beforeActive),
                ),
                if (beforeActive) ...[
                  const SizedBox(height: 8),
                  _minuteSliderCard(
                    title: 'تشغيل قبل الفجر ب',
                    minutes: config.startBeforeFajrMinutes,
                    maxMinutes: 60,
                    minMinutes: 5,
                    onChanged: _configService.setStartBeforeFajrMinutes,
                  ),
                ],
                const SizedBox(height: 8),
                _startModeToggleCard(
                  icon: Icons.keyboard_double_arrow_right_rounded,
                  title: 'بعد الفجر',
                  value: afterActive,
                  enabled: maxAfterFajr > 0,
                  onTap: () => _configService.setStartAfterFajrEnabled(
                    !afterActive,
                    ts,
                  ),
                ),
                if (afterActive) ...[
                  const SizedBox(height: 8),
                  _minuteSliderCard(
                    title: 'تشغيل بعد الفجر ب',
                    minutes: afterFajr,
                    maxMinutes: maxAfterFajr,
                    minMinutes: 5,
                    footer:
                        'الفجر $fajr · الشروق $sunrise · المتاح $maxAfterFajr د',
                    onChanged: (minutes) =>
                        _configService.setStartAfterFajrMinutes(minutes, ts),
                  ),
                ],
                if (!beforeActive && !afterActive) ...[
                  const SizedBox(height: 8),
                  _startAtFajrCard(fajr),
                ],
                const SizedBox(height: 22),
                _section('طريقة الإنهاء'),
                const SizedBox(height: 8),
                _endModePicker(config.endMode),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _topIconButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cbg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bdr, width: 1),
        ),
        child: Icon(icon, size: 20, color: t1),
      ),
    );
  }

  Widget _powerButton(bool enabled) {
    final color = enabled ? const Color(0xFFE2574C) : glw;
    return GestureDetector(
      onTap: () => _configService.setSystemEnabled(!enabled, timesService: ts),
      child: Container(
        height: 40,
        constraints: const BoxConstraints(minWidth: 118),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: n ? 0.14 : 0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.power_settings_new_rounded, size: 17, color: color),
            const SizedBox(width: 6),
            Text(
              enabled ? 'إيقاف المنبه' : 'تشغيل المنبه',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({
    required Widget child,
    VoidCallback? onTap,
    bool enabled = true,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: cbg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: bdr, width: 1),
        ),
        child: child,
      ),
    );
  }

  Widget _section(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: t2,
        letterSpacing: 4,
      ),
    );
  }

  Widget _alarmToggle({
    required IconData icon,
    required String title,
    required bool value,
    required VoidCallback onTap,
  }) {
    return _card(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: glw),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value ? 'تشغيل' : 'إيقاف تشغيل',
                  style: GoogleFonts.inter(fontSize: 11, color: t2),
                ),
              ],
            ),
          ),
          _toggle(value),
        ],
      ),
    );
  }

  Widget _alarmSoundCard() {
    final sound = _soundService.config;
    return _card(
      onTap: _showAlarmSoundSheet,
      child: Row(
        children: [
          Icon(Icons.volume_up_rounded, size: 20, color: glw),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'صوت المنبه',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sound.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 11, color: t2),
                ),
              ],
            ),
          ),
          Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: tDim),
        ],
      ),
    );
  }

  Future<void> _showAlarmSoundSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: cbg,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tDim.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _soundOption(
                    icon: Icons.graphic_eq_rounded,
                    title: 'توليدي',
                    subtitle: 'أصوات عشوائية بنبضات مختلفة',
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _soundService.setGenerated();
                    },
                  ),
                  _soundOption(
                    icon: Icons.music_note_rounded,
                    title: 'أذان',
                    subtitle: 'استخدام صوت الأذان الافتراضي في التطبيق',
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _soundService.setAdhan();
                    },
                  ),
                  _soundOption(
                    icon: Icons.folder_rounded,
                    title: 'اختيار من الملفات',
                    subtitle: 'تعيين ملف صوتي محفوظ على الهاتف',
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final picked = await _soundService.pickFileFromDevice();
                      if (!mounted) return;
                      if (picked == null) _showSnack('لم يتم اختيار ملف صوتي');
                    },
                  ),
                  _soundOption(
                    icon: Icons.mic_rounded,
                    title: 'تسجيل صوت مخصص',
                    subtitle: 'تسجيل صوت جديد للمنبه',
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _openRecordingPage();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _soundOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Icon(icon, color: glw),
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: t1,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(fontSize: 11, color: t2),
      ),
      onTap: onTap,
    );
  }

  Future<void> _openRecordingPage() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FajrAlarmRecordingPage(
          soundService: _soundService,
          isNight: n,
        ),
      ),
    );
    if (!mounted) return;
    if (changed == true) setState(() {});
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _startModeToggleCard({
    required IconData icon,
    required String title,
    required bool value,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return _card(
      onTap: onTap,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 20, color: enabled ? glw : tDim),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: enabled ? t1 : tDim,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value ? 'تشغيل' : 'إيقاف تشغيل',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: enabled ? t2 : tDim,
                  ),
                ),
              ],
            ),
          ),
          _toggle(enabled && value),
        ],
      ),
    );
  }

  Widget _startAtFajrCard(String fajr) {
    return _card(
      child: Row(
        children: [
          Icon(Icons.access_time_rounded, size: 20, color: glw),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'يبدأ عند أذان الفجر $fajr',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: t2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _minuteSliderCard({
    required String title,
    required int minutes,
    required int maxMinutes,
    required ValueChanged<int> onChanged,
    int minMinutes = 0,
    String? footer,
  }) {
    final sliderMax = maxMinutes <= 0 ? 1.0 : maxMinutes.toDouble();
    final effectiveMin = maxMinutes <= 0
        ? 0
        : minMinutes.clamp(0, maxMinutes).toInt();
    final divisions = maxMinutes > effectiveMin
        ? ((maxMinutes - effectiveMin) ~/ 5).clamp(1, 1000).toInt()
        : null;
    final value = maxMinutes <= 0
        ? 0.0
        : minutes.clamp(effectiveMin, maxMinutes).toDouble();
    return _card(
      enabled: maxMinutes > 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t1,
                  ),
                ),
              ),
              _valueBadge('$minutes د'),
            ],
          ),
          const SizedBox(height: 10),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: glw,
              inactiveTrackColor: bdr,
              thumbColor: glw,
              overlayColor: glw.withValues(alpha: 0.15),
              trackHeight: 3,
            ),
            child: Slider(
              value: value,
              min: effectiveMin.toDouble(),
              max: sliderMax,
              divisions: divisions,
              onChanged: maxMinutes > 0
                  ? (raw) => onChanged(((raw / 5).round() * 5).toInt())
                  : null,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$effectiveMin د',
                style: GoogleFonts.inter(fontSize: 11, color: tDim),
              ),
              Text(
                '$maxMinutes د',
                style: GoogleFonts.inter(fontSize: 11, color: tDim),
              ),
            ],
          ),
          if (footer != null) ...[
            const SizedBox(height: 8),
            Text(footer, style: GoogleFonts.inter(fontSize: 11, color: t2)),
          ],
        ],
      ),
    );
  }

  Widget _endModePicker(FajrAlarmEndMode selected) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final mode in FajrAlarmEndMode.values)
              SizedBox(
                width: width,
                child: _endModeButton(mode: mode, selected: mode == selected),
              ),
          ],
        );
      },
    );
  }

  Widget _endModeButton({
    required FajrAlarmEndMode mode,
    required bool selected,
  }) {
    return GestureDetector(
      onTap: () => _configService.setEndMode(mode),
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? glw.withValues(alpha: n ? 0.13 : 0.2) : cbg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? glw.withValues(alpha: 0.55) : bdr,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: selected ? glw : tDim,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    mode.arabicLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? t1 : t2,
                    ),
                  ),
                ),
              ],
            ),
            if (mode.arabicSubLabel.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                mode.arabicSubLabel,
                style: GoogleFonts.inter(fontSize: 11, color: tDim),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _valueBadge(String text) {
    return Container(
      constraints: const BoxConstraints(minWidth: 54),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: glw.withValues(alpha: n ? 0.12 : 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: glw.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: glw,
        ),
      ),
    );
  }

  Widget _toggle(bool value) {
    return Container(
      width: 40,
      height: 24,
      decoration: BoxDecoration(
        color: value ? glw : tDim.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            left: value ? 18 : 2,
            top: 2,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
