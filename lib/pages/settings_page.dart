import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_theme_colors.dart';
import '../services/prayer_times_service.dart';
import '../services/aladhan_api_service.dart';
import '../services/location_service.dart';

import '../services/l10n_service.dart';
import 'city_picker_sheet.dart';

import 'learn_page.dart';
import 'mosque_picker_page.dart';

class SettingsPage extends StatefulWidget {
  final PrayerTimesService timesService;
  final L10nService l10n;
  final bool isNight;
  const SettingsPage({super.key, required this.timesService, required this.l10n, required this.isNight});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  PrayerTimesService get ts => widget.timesService;
  L10nService get l10n => widget.l10n;
  bool get n => widget.isNight;

  Color get bg => n ? AppThemeColors.nightBg : AppThemeColors.dayBg;
  Color get cbg => n ? AppThemeColors.nightCardBg : AppThemeColors.dayCardBg;
  Color get t1 => n ? AppThemeColors.nightTextPrimary : AppThemeColors.dayTextPrimary;
  Color get t2 => n ? AppThemeColors.nightTextSecondary : AppThemeColors.dayTextSecondary;
  Color get tDim => n ? AppThemeColors.nightTextDim : AppThemeColors.dayTextDim;
  Color get bdr => n ? AppThemeColors.nightBorder : AppThemeColors.dayBorder;
  Color get glw => n ? AppThemeColors.nightGlow : AppThemeColors.dayGlow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Widget _card({required Widget child, VoidCallback? onTap}) => GestureDetector(
    onTap: onTap,
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(color: cbg, borderRadius: BorderRadius.circular(14), border: Border.all(color: bdr, width: 1)),
        child: child),
  );

  Widget _sect(String t) => Text(t, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: t2, letterSpacing: 4));

  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData(scaffoldBackgroundColor: bg, colorScheme: ColorScheme.fromSeed(seedColor: glw, brightness: n ? Brightness.dark : Brightness.light)),
    child: Scaffold(
      backgroundColor: bg,
      appBar: AppBar(backgroundColor: bg, elevation: 0, leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(margin: const EdgeInsets.all(8), padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: cbg, borderRadius: BorderRadius.circular(12), border: Border.all(color: bdr, width: 1)),
            child: Icon(Icons.arrow_back_rounded, size: 20, color: t1)),
      ), title: Text(l10n.t('settings_title'), style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: t1)), centerTitle: true),
      body: FadeTransition(opacity: _fade, child: ListenableBuilder(
        listenable: Listenable.merge([ts, ts.mosqueService]),
        builder: (context, _) => ListView(padding: EdgeInsets.fromLTRB(20, 8, 20, 8 + MediaQuery.of(context).padding.bottom), children: [
          _mosqueCard(), const SizedBox(height: 20),
          _sect(l10n.t('settings_location')), const SizedBox(height: 8), _locCard(), const SizedBox(height: 20),
          _sect(l10n.t('settings_method')), const SizedBox(height: 8), _methCard(), const SizedBox(height: 20),
          _sect(l10n.t('settings_madhab')), const SizedBox(height: 8), _madCard(), const SizedBox(height: 20),
          _sect(l10n.t('settings_fajr_angle')), const SizedBox(height: 8), _fajrCard(), const SizedBox(height: 20),
          _sect(l10n.t('settings_isha_angle')), const SizedBox(height: 8), _ishaCard(), const SizedBox(height: 20),
          _sect(l10n.t('settings_display')), const SizedBox(height: 8), _hijriCard(), const SizedBox(height: 8),
          _midnightCard(), const SizedBox(height: 8),
          _duhaCard(), const SizedBox(height: 20),
          _sect(l10n.t('settings_kids')), const SizedBox(height: 8), _kidsCard(), const SizedBox(height: 20),
          _adhanScreenCard(), const SizedBox(height: 20),
          _sect(l10n.t('general')), const SizedBox(height: 8), _languageCard(), const SizedBox(height: 8),
          _use24hCard(), const SizedBox(height: 8),
          _lockScreenCard(), const SizedBox(height: 20),
          _learnCard(), const SizedBox(height: 30),
          _buildCopyright(),
          const SizedBox(height: 30),
        ]),
      )),
    ),
  );

  // ---- Mosque sync ----
  Widget _mosqueCard() {
    final ms = ts.mosqueService;
    final hasMosque = ms.hasMosque;
    return _card(
      onTap: () async {
        // Show info dialog first
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: cbg,
            title: Text(l10n.t('mosque_dialog_title'), style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: t1)),
            content: Text(
              l10n.t('mosque_dialog_desc'),
              style: GoogleFonts.inter(fontSize: 13, height: 1.6, color: t2),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.t('cancel'), style: GoogleFonts.inter(color: t2))),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.t('continue'), style: GoogleFonts.inter(color: glw))),
            ],
          ),
        );
        if (proceed != true) return;

        // Check location
        final loc = ts.locationService;
        if (!loc.useGps) {
          final ok = await loc.detectGps();
          if (!ok && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('يرجى تفعيل GPS أو اختيار مدينة أولاً'),
              backgroundColor: glw.withValues(alpha: 0.9),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ));
            return;
          }
        }
        if (!mounted) return;
        final picked = await Navigator.push<bool>(context,
          MaterialPageRoute(builder: (_) => MosquePickerPage(
            srv: ms,
            loc: loc,
            isNight: n,
            translateToArabic: l10n.isArabic,
          )),
        );
        if (picked == true) {
          // Check if user has custom Fajr/Isha angles — offer to reset
          if (ts.fajrAngle != null || ts.ishaAngle != null) {
            await _handleMosqueAngleConflict();
          }
          setState(() {});
        }
      },
      child: Row(children: [
        Icon(Icons.mosque_rounded, size: 20, color: glw),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('الاقتران بمسجد قريب', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: t1)),
          const SizedBox(height: 2),
          Text(hasMosque ? 'مقترن: ${ms.mosqueName}' : 'اختر مسجداً للحصول على أوقاته',
              style: GoogleFonts.inter(fontSize: 11, color: hasMosque ? glw : t2)),
        ])),
        if (hasMosque)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(Icons.check_circle_rounded, size: 18, color: glw),
          ),
        Icon(Icons.chevron_left_rounded, size: 18, color: tDim),
      ]),
    );
  }

  /// When a mosque is selected and the user has custom angles, ask how to reconcile.
  Future<void> _handleMosqueAngleConflict() async {
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cbg,
        title: Text('تعارض في الزوايا', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: t1)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('لديك زوايا مخصصة للفجر والعشاء. هل ترغب في ضبطها وفقًا لأوقات المسجد؟',
              style: GoogleFonts.inter(fontSize: 13, height: 1.6, color: t2)),
          const SizedBox(height: 14),
          _angleOption(ctx, 'المسجد', 'ضبط الزوايا تلقائيًا لمطابقة أوقات المسجد تمامًا', 'mosque'),
          const SizedBox(height: 8),
          _angleOption(ctx, 'getMethod', 'الإبقاء على هيئة الحساب المختارة وضبط الزوايا وفقًا لها', 'method'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'method'), child: Text('هيئة الحساب', style: GoogleFonts.inter(color: glw))),
          TextButton(onPressed: () => Navigator.pop(ctx, 'mosque'), child: Text('أوقات المسجد', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: glw))),
        ],
      ),
    );
    if (choice == 'mosque') {
      // Reset to auto — mosque times are used directly
      await ts.setFajrAngle(null);
      await ts.setIshaAngle(null);
      if (mounted) setState(() {});
    }
    // If 'method': keep custom angles, times will be computed via AlAdhan
  }

  Widget _angleOption(BuildContext ctx, String id, String title, String sub) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cbg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bdr),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: t1)),
          Text(sub, style: GoogleFonts.inter(fontSize: 11, color: t2)),
        ])),
      ]),
    );
  }

  // ---- Location ----
  Widget _locCard() {
    final l = ts.locationService;
    final sub = [l.state, l.country].where((e) => e.isNotEmpty).join(', ');
    return _card(onTap: () => _locSheet(), child: Row(children: [
      Icon(l.useGps ? Icons.my_location_rounded : Icons.location_city_rounded, size: 20, color: glw),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(l10n.t('settings_location'), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: t1)),
          const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: l.useGps ? glw.withValues(alpha: 0.15) : tDim.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
              child: Text(l.useGps ? l10n.t('gps') : l10n.t('manual'), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: l.useGps ? glw : tDim))),
        ]),
        const SizedBox(height: 2),
        Text(l.compactName, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11, color: t2)),
        if (sub.isNotEmpty)
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 10, color: tDim)),
      ])),
      Icon(Icons.chevron_left_rounded, size: 18, color: tDim),
    ]));
  }

  // System navigation-bar inset (gesture pill / 3-button bar). `useSafeArea`
  // on a bottom sheet only guards the top/sides, so we add this to the bottom
  // padding of every sheet to keep content above the phone's buttons.
  double get _navInset => MediaQuery.of(context).viewPadding.bottom;

  void _locSheet() {
    showModalBottomSheet(context: context, useSafeArea: true, backgroundColor: bg, isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => LocationSheet(loc: ts.locationService, isNight: n));
  }

  // ---- Hijri ----p
  Widget _hijriCard() {
    final v = ts.showHijri;
    return _card(onTap: () => ts.setShowHijri(!v), child: Row(children: [
      Icon(Icons.calendar_month_rounded, size: 20, color: glw), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.t('settings_hijri'), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: t1)),
        const SizedBox(height: 2),
        Text(v ? l10n.t('settings_hijri_on') : l10n.t('settings_hijri_off'), style: GoogleFonts.inter(fontSize: 11, color: t2)),
      ])),
      _toggle(v),
    ]));
  }

  // ---- Midnight ----
  Widget _midnightCard() {
    final v = ts.showMidnight;
    return _card(onTap: () => ts.setShowMidnight(!v), child: Row(children: [
      Icon(Icons.bedtime_rounded, size: 20, color: glw), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.t('settings_midnight'), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: t1)),
        const SizedBox(height: 2),
        Text(v ? l10n.t('settings_midnight_on') : l10n.t('settings_midnight_off'), style: GoogleFonts.inter(fontSize: 11, color: t2)),
      ])),
      _toggle(v),
    ]));
  }

  // ---- Duha ----
  Widget _duhaCard() {
    final v = ts.showDuha;
    return _card(onTap: () => ts.setShowDuha(!v), child: Row(children: [
      Icon(Icons.wb_sunny_rounded, size: 20, color: glw), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.t('settings_duha'), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: t1)),
        const SizedBox(height: 2),
        Text(v ? l10n.t('settings_duha_on') : l10n.t('settings_duha_off'), style: GoogleFonts.inter(fontSize: 11, color: t2)),
      ])),
      _toggle(v),
    ]));
  }

  // ---- Kids mode ----
  Widget _kidsCard() {
    final v = ts.kidsMode;
    return _card(onTap: () => ts.setKidsMode(!v), child: Row(children: [
      Icon(Icons.child_care_rounded, size: 20, color: glw), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.t('settings_kids'), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: t1)),
        const SizedBox(height: 2),
        Text(v ? l10n.t('settings_kids_on') : l10n.t('settings_kids_q'), style: GoogleFonts.inter(fontSize: 11, color: t2)),
      ])),
      _toggle(v),
    ]));
  }

  // ---- Adhan screen (full-screen vs notification-only) ----
  Widget _adhanScreenCard() {
    final v = ts.adhanScreenEnabled;
    return _card(onTap: () => ts.setAdhanScreenEnabled(!v), child: Row(children: [
      Icon(v ? Icons.smartphone_rounded : Icons.notifications_rounded, size: 20, color: glw), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.t('settings_adhan_screen'), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: t1)),
        const SizedBox(height: 2),
        Text(v ? l10n.t('settings_adhan_screen_on') : l10n.t('settings_adhan_screen_off'), style: GoogleFonts.inter(fontSize: 11, color: t2)),
      ])),
      _toggle(v),
    ]));
  }

  Widget _toggle(bool v) => Container(
    width: 40, height: 24,
    decoration: BoxDecoration(color: v ? glw : tDim.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(12)),
    child: Stack(children: [
      AnimatedPositioned(duration: const Duration(milliseconds: 200), left: v ? 18 : 2, top: 2,
        child: Container(width: 20, height: 20, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
      ),
    ]),
  );

  // ---- Method ----
  Widget _methCard() {
    final nm = AlAdhanApiService.calculationMethods[ts.method] ?? '???';
    final a = AlAdhanApiService.methodAngles[ts.method];
    return _card(onTap: () => _methSheet(), child: Row(children: [
      const Icon(Icons.account_balance_rounded, size: 20, color: Color(0xFFD4A853)), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.t('settings_method'), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: t1)),
        const SizedBox(height: 2),
        Text(nm, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11, color: t2)),
        if (a != null) Text('Fajr: ${a['fajr']}  ·  Isha: ${a['isha']}', style: GoogleFonts.inter(fontSize: 10, color: tDim)),
      ])),
      _info('Methods differ in Fajr/Isha angle calculation'),
      const SizedBox(width: 8), const Icon(Icons.chevron_left_rounded, size: 18, color: Color(0xFF9A9588)),
    ]));
  }

  Widget _info(String msg) => Tooltip(message: msg, preferBelow: false,
    child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: glw.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFD4A853))));

  void _methSheet() {
    final en = AlAdhanApiService.calculationMethods.entries.toList();
    showModalBottomSheet(context: context, useSafeArea: true, backgroundColor: bg, isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => DraggableScrollableSheet(initialChildSize: 0.6, minChildSize: 0.4, maxChildSize: 0.85, expand: false,
            builder: (ctx, sc) => Column(children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: tDim, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFD4A853)), const SizedBox(width: 8),
                Expanded(child: Text('Methods differ in Fajr/Isha angle calculation', style: GoogleFonts.inter(fontSize: 12, color: tDim))),
              ])),
              const SizedBox(height: 12),
              Expanded(child: ListView.builder(controller: sc, itemCount: en.length, padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + _navInset),
                  itemBuilder: (_, i) {
                    final e = en[i]; final sel = e.key == ts.method; final a = AlAdhanApiService.methodAngles[e.key];
                    return GestureDetector(onTap: () { ts.setMethod(e.key); Navigator.pop(context); },
                        child: Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: sel ? glw.withValues(alpha: n ? 0.10 : 0.15) : cbg, borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: sel ? glw.withValues(alpha: 0.5) : bdr, width: sel ? 1.5 : 1)),
                            child: Row(children: [
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(e.value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: sel ? t1 : t2)),
                                if (a != null) Text('Fajr: ${a['fajr']}  ·  Isha: ${a['isha']}', style: GoogleFonts.inter(fontSize: 11, color: tDim)),
                              ])),
                              if (sel) Icon(Icons.check_circle_rounded, size: 20, color: glw),
                            ])));
                  })),
            ])));
  }

  // ---- Madhab ----
  Widget _madCard() {
    final m = ts.madhab;
    return _card(onTap: () => _madSheet(), child: Row(children: [
      const Icon(Icons.school_rounded, size: 20, color: Color(0xFFD4A853)), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.t('settings_madhab'), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: t1)),
        const SizedBox(height: 2),
        Text(m == Madhab.shafii ? l10n.t('settings_madhab_shafii') : l10n.t('settings_madhab_hanafi'), style: GoogleFonts.inter(fontSize: 11, color: t2)),
      ])),
      const Icon(Icons.chevron_left_rounded, size: 18, color: Color(0xFF9A9588)),
    ]));
  }

  void _madSheet() {
    showModalBottomSheet(context: context, useSafeArea: true, backgroundColor: bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => Container(padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + _navInset), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: tDim, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text(l10n.t('settings_madhab'), style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: t1)),
          const SizedBox(height: 16),
          _opt(l10n.t('settings_madhab_shafii'), l10n.t('settings_madhab_shafii_desc'),
              ts.madhab == Madhab.shafii, () { ts.setMadhab(Madhab.shafii); Navigator.pop(context); }),
          const SizedBox(height: 8),
          _opt(l10n.t('settings_madhab_hanafi'), l10n.t('settings_madhab_hanafi_desc'),
              ts.madhab == Madhab.hanafi, () { ts.setMadhab(Madhab.hanafi); Navigator.pop(context); }),
          const SizedBox(height: 8),
        ])));
  }

  // ---- Fajr ----
  Widget _fajrCard() {
    final a = ts.fajrAngle;
    final methodDef = AlAdhanApiService.methodAngles[ts.method]?['fajr'];
    return _card(onTap: () => _angleSheet(true), child: Row(children: [
      const Icon(Icons.wb_twilight_rounded, size: 20, color: Color(0xFFD4A853)), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.t('settings_fajr_angle'), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: t1)),
        const SizedBox(height: 2),
        Text(
          a != null
              ? 'زاوية مخصصة'
              : (methodDef != null ? 'تلقائي · حسب طريقة الحساب ($methodDef)' : 'تلقائي · حسب طريقة الحساب'),
          style: GoogleFonts.inter(fontSize: 11, color: t2),
        ),
      ])),
      _valueChip(a != null ? '${a.toStringAsFixed(1)}°' : 'تلقائي', custom: a != null),
      const SizedBox(width: 8),
      Icon(Icons.chevron_left_rounded, size: 18, color: tDim),
    ]));
  }

  // ---- Isha ----
  Widget _ishaCard() {
    final a = ts.ishaAngle; final m = ts.ishaMode;
    final methodDef = AlAdhanApiService.methodAngles[ts.method]?['isha'];
    return _card(onTap: () => _angleSheet(false), child: Row(children: [
      const Icon(Icons.nights_stay_rounded, size: 20, color: Color(0xFFD4A853)), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.t('settings_isha_angle'), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: t1)),
        const SizedBox(height: 2),
        Text(
          a != null
              ? (m == 'minutes' ? 'مدة ثابتة بعد المغرب' : 'زاوية مخصصة')
              : (methodDef != null ? 'تلقائي · حسب طريقة الحساب ($methodDef)' : 'تلقائي · حسب طريقة الحساب'),
          style: GoogleFonts.inter(fontSize: 11, color: t2),
        ),
      ])),
      _valueChip(
        a != null ? (m == 'minutes' ? '${a.toInt()} د' : '${a.toStringAsFixed(1)}°') : 'تلقائي',
        custom: a != null,
      ),
      const SizedBox(width: 8),
      Icon(Icons.chevron_left_rounded, size: 18, color: tDim),
    ]));
  }

  Widget _valueChip(String label, {required bool custom}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: custom ? glw.withValues(alpha: 0.15) : tDim.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: custom ? glw.withValues(alpha: 0.4) : bdr),
    ),
    child: Text(label, style: GoogleFonts.lexend(fontSize: 13, fontWeight: FontWeight.w600, color: custom ? glw : t2)),
  );

  void _angleSheet(bool isFajr) {
    // Local draft state — applied with a single API call on save, instead of
    // refetching prayer times on every tap.
    double? val = isFajr ? ts.fajrAngle : ts.ishaAngle;
    String mode = isFajr ? 'angle' : ts.ishaMode;
    final methodDef = AlAdhanApiService.methodAngles[ts.method]?[isFajr ? 'fajr' : 'isha'];

    showModalBottomSheet(context: context, useSafeArea: true, backgroundColor: bg, isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => StatefulBuilder(
          builder: (ctx, setSheetState) {
            final a = val;
            final isMin = mode == 'minutes';
            final minV = isMin ? 15.0 : 12.0;
            final maxV = isMin ? 120.0 : 20.0;
            final divisions = isMin ? 21 : 16; // 5-min / 0.5° steps
            final label = a == null
                ? 'تلقائي'
                : (isMin ? '${a.toInt()} دقيقة' : '${a.toStringAsFixed(1)}°');
            final presets = isFajr
                ? const [15.0, 16.0, 18.0, 19.5]
                : (isMin ? const [60.0, 90.0, 120.0] : const [14.0, 17.0, 18.0]);

            Widget presetChip(double v) {
              final sel = a != null && (a - v).abs() < 0.01;
              return GestureDetector(
                onTap: () => setSheetState(() => val = v),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? glw.withValues(alpha: n ? 0.15 : 0.2) : cbg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? glw.withValues(alpha: 0.6) : bdr, width: sel ? 1.5 : 1),
                  ),
                  child: Text(
                    isMin ? '${v.toInt()} د' : '${v % 1 == 0 ? v.toInt() : v}°',
                    style: GoogleFonts.lexend(fontSize: 13, fontWeight: FontWeight.w600, color: sel ? glw : t2),
                  ),
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + _navInset), child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: tDim, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(isFajr ? Icons.wb_twilight_rounded : Icons.nights_stay_rounded, size: 22, color: glw),
                  const SizedBox(width: 10),
                  Text(isFajr ? l10n.t('settings_fajr_angle') : l10n.t('settings_isha_angle'),
                      style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: t1)),
                ]),
                const SizedBox(height: 8),
                Text(
                  isFajr
                      ? 'زاوية انخفاض الشمس تحت الأفق التي يبدأ عندها وقت الفجر. الزاوية الأكبر تعني فجراً أبكر.'
                      : 'حدد وقت العشاء بزاوية الشمس تحت الأفق، أو بمدة ثابتة بعد المغرب (المعمول به في الحرمين خلال رمضان: 120 دقيقة).',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 12, height: 1.6, color: tDim),
                ),
                const SizedBox(height: 16),
                _opt('تلقائي', methodDef != null ? 'استخدام قيمة طريقة الحساب ($methodDef)' : 'استخدام قيمة طريقة الحساب',
                    a == null, () => setSheetState(() => val = null)),
                const SizedBox(height: 8),
                _opt(isFajr ? 'زاوية مخصصة' : 'زاوية مخصصة (12° – 20°)', '',
                    a != null && !isMin, () => setSheetState(() { mode = 'angle'; val = (a != null && !isMin) ? a : 17.0; })),
                if (!isFajr) ...[
                  const SizedBox(height: 8),
                  _opt('مدة ثابتة بعد المغرب', '15 – 120 دقيقة',
                      a != null && isMin, () => setSheetState(() { mode = 'minutes'; val = (a != null && isMin) ? a : 90.0; })),
                ],
                if (a != null) ...[
                  const SizedBox(height: 20),
                  Text(label, style: GoogleFonts.lexend(fontSize: 34, fontWeight: FontWeight.w600, color: glw)),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: glw,
                      inactiveTrackColor: bdr,
                      thumbColor: glw,
                      overlayColor: glw.withValues(alpha: 0.15),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: a.clamp(minV, maxV),
                      min: minV, max: maxV, divisions: divisions,
                      onChanged: (v) => setSheetState(() => val = v),
                    ),
                  ),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (final p in presets) ...[presetChip(p), const SizedBox(width: 8)],
                  ]),
                ],
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    if (isFajr) {
                      ts.setFajrAngle(val);
                    } else {
                      ts.setIshaAngle(val, mode: mode);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: glw.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: glw.withValues(alpha: 0.4), width: 1.5),
                    ),
                    child: Text('حفظ', textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: glw)),
                  ),
                ),
              ])),
            );
          },
        ));
  }

  Widget _opt(String title, String sub, bool sel, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(
        color: sel ? glw.withValues(alpha: n ? 0.10 : 0.15) : cbg, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: sel ? glw.withValues(alpha: 0.5) : bdr, width: sel ? 1.5 : 1)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: sel ? t1 : t2)),
            if (sub.isNotEmpty) Text(sub, style: GoogleFonts.inter(fontSize: 11, color: tDim)),
          ])),
          if (sel) Icon(Icons.check_circle_rounded, size: 20, color: glw),
        ])));

  // ---- Language (moved here from the quick menu) ----
  Widget _languageCard() => _card(
        onTap: _languageSheet,
        child: Row(children: [
          const Icon(Icons.language_rounded, size: 20, color: Color(0xFFD4A853)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.t('lang_title'), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: t1)),
            const SizedBox(height: 2),
            Text(l10n.localeName(l10n.locale), style: GoogleFonts.inter(fontSize: 11, color: glw)),
          ])),
          Icon(Icons.chevron_left_rounded, size: 18, color: tDim),
        ]),
      );

  void _languageSheet() {
    showModalBottomSheet(
      context: context, useSafeArea: true, backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Container(padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + _navInset), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(color: tDim, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 18),
        Text(l10n.t('lang_title'), style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: t1)),
        const SizedBox(height: 16),
        ...l10n.supportedLocales.map((code) => Padding(padding: const EdgeInsets.only(bottom: 8), child: GestureDetector(
          onTap: () { l10n.setLocale(code); Navigator.pop(context); setState(() {}); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: l10n.locale == code ? glw.withValues(alpha: n ? 0.12 : 0.18) : cbg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: l10n.locale == code ? glw.withValues(alpha: 0.5) : bdr, width: l10n.locale == code ? 1.5 : 1)),
            child: Row(children: [
              Expanded(child: Text(l10n.localeName(code), style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: l10n.locale == code ? t1 : t2))),
              if (l10n.locale == code) Icon(Icons.check_circle_rounded, size: 20, color: glw),
            ])),
        ))),
      ])),
    );
  }

  // ---- Lock-screen / AOD setup guide ----
  Widget _lockScreenCard() => _card(
        onTap: _lockScreenSheet,
        child: Row(children: [
          const Icon(Icons.lock_clock_rounded, size: 20, color: Color(0xFFD4A853)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('شاشة القفل والعرض الدائم', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: t1)),
            const SizedBox(height: 2),
            Text('كيف تعرض الصلاة الحالية والقادمة على شاشة القفل', style: GoogleFonts.inter(fontSize: 11, color: t2)),
          ])),
          Icon(Icons.chevron_left_rounded, size: 18, color: tDim),
        ]),
      );

  void _lockScreenSheet() {
    Widget step(String n0, String txt) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                    color: glw.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(7)),
                alignment: Alignment.center,
                child: Text(n0, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: glw))),
            const SizedBox(width: 12),
            Expanded(child: Text(txt, style: GoogleFonts.inter(fontSize: 13.5, height: 1.6, color: t1))),
          ]),
        );

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(28, 16, 28, 32 + _navInset),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: tDim, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Icon(Icons.lock_clock_rounded, size: 40, color: glw),
          const SizedBox(height: 10),
          Text('عرض المواقيت على شاشة القفل',
              style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: t1)),
          const SizedBox(height: 8),
          Text(
            'التطبيق يعرض إشعاراً دائماً فيه الساعة والصلاة الحالية والقادمة مع عدّ تنازلي حي. ليظهر على شاشة القفل دائماً:',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12.5, height: 1.7, color: t2),
          ),
          const SizedBox(height: 18),
          step('1', 'إعدادات الهاتف ← الإشعارات ← إشعارات شاشة القفل ← اختر «إظهار المحتوى كاملاً».'),
          step('2', 'في هواتف سامسونج: الإعدادات ← شاشة القفل وAOD ← فعّل «العرض الدائم AOD» واختر إظهار الإشعارات.'),
          step('3', 'تأكد أن إشعار «شاشة مواقيت الصلاة» مفعّل: اضغط مطولاً على أيقونة التطبيق ← معلومات التطبيق ← الإشعارات.'),
          step('4', 'عطّل تحسين البطارية للتطبيق (غير مقيد) حتى لا يُغلق الإشعار.'),
          const SizedBox(height: 8),
          Text('💡 الإشعار يحدّث نفسه بدون استهلاك بطارية، ويبقى ظاهراً عند قفل الهاتف.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 11.5, color: glw)),
        ]),
      ),
    );
  }

  // ---- 24 ساعة ----
  Widget _use24hCard() {
    final v = ts.use24h;
    return _card(onTap: () => ts.setUse24h(!v), child: Row(children: [
      Icon(Icons.schedule_rounded, size: 20, color: glw), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.t('home_24h'), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: t1)),
        const SizedBox(height: 2),
        Text(v ? 'نظام 24 ساعة' : 'نظام 12 ساعة', style: GoogleFonts.inter(fontSize: 11, color: t2)),
      ])),
      _toggle(v),
    ]));
  }

  // ---- تعلّم ----
  Widget _learnCard() {
    return _card(onTap: () {
      Navigator.push(context, MaterialPageRoute(builder: (_) => LearnPage(isNight: n)));
    }, child: Row(children: [
      const Icon(Icons.menu_book_rounded, size: 20, color: Color(0xFFD4A853)), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.t('learn'), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: t1)),
        const SizedBox(height: 2),
        Text(l10n.t('learn_sub'), style: GoogleFonts.inter(fontSize: 11, color: t2)),
      ])),
      Icon(Icons.chevron_left_rounded, size: 18, color: tDim),
    ]));
  }

  // ---- Copyright ----
  Widget _buildCopyright() {
    return Center(
      child: GestureDetector(
        onTap: () => launchUrl(Uri.parse('https://din.hk')),
        child: Text.rich(
          TextSpan(
            style: GoogleFonts.inter(fontSize: 11, color: tDim),
            children: const [
              TextSpan(text: '\u{a9} '),
              TextSpan(text: 'din.hk', style: TextStyle(color: Color(0xFFD4A853), decoration: TextDecoration.underline)),
              TextSpan(text: '  \u{b7}  All rights reserved'),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════
// Location Sheet (top-level widget, not inside another class)
// ═════════════════════════════════════════════════════════
class LocationSheet extends StatefulWidget {
  final LocationService loc;
  final bool isNight;
  const LocationSheet({super.key, required this.loc, required this.isNight});
  @override
  State<LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<LocationSheet> {
  bool detecting = false;
  bool get n => widget.isNight;
  Color get bg => n ? AppThemeColors.nightBg : AppThemeColors.dayBg;
  Color get cbg => n ? AppThemeColors.nightCardBg : AppThemeColors.dayCardBg;
  Color get t1 => n ? AppThemeColors.nightTextPrimary : AppThemeColors.dayTextPrimary;
  Color get t2 => n ? AppThemeColors.nightTextSecondary : AppThemeColors.dayTextSecondary;
  Color get tDim => n ? AppThemeColors.nightTextDim : AppThemeColors.dayTextDim;
  Color get bdr => n ? AppThemeColors.nightBorder : AppThemeColors.dayBorder;
  Color get glw => n ? AppThemeColors.nightGlow : AppThemeColors.dayGlow;

  @override
  void initState() { super.initState(); widget.loc.addListener(refresh); }
  @override
  void dispose() { widget.loc.removeListener(refresh); super.dispose(); }
  void refresh() { if (mounted) setState(() {}); }

  Future<void> gps() async {
    setState(() => detecting = true);
    final ok = await widget.loc.detectGps();
    setState(() => detecting = false);
    if (mounted) {
      if (ok) { Navigator.pop(context); } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Could not detect location. Check GPS permissions.'),
            backgroundColor: glw.withValues(alpha: 0.9), behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      }
    }
  }

  Future<void> selectCity(CityData c) async {
    await widget.loc.setManualLocation(lat: c.lat, lng: c.lng, city: c.name);
    if (mounted) Navigator.pop(context);
  }

  Widget locDetailRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 3), child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: GoogleFonts.inter(fontSize: 11, color: tDim))),
      Expanded(child: Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: t1))),
    ]));
  }

  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.only(top: 16),
    decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4, decoration: BoxDecoration(color: tDim, borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 20),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text('Location', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: t1))),
      const SizedBox(height: 8),
      if (widget.loc.useGps) ...[
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Container(
          width: double.infinity, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: glw.withValues(alpha: n ? 0.06 : 0.08), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: glw.withValues(alpha: 0.2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            locDetailRow('Village/District', widget.loc.village),
            locDetailRow('City', widget.loc.cityName),
            locDetailRow('Region', widget.loc.state),
            locDetailRow('Country', widget.loc.country),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.pin_drop_rounded, size: 14, color: tDim), const SizedBox(width: 4),
              Text('${widget.loc.latitude.toStringAsFixed(4)}, ${widget.loc.longitude.toStringAsFixed(4)}',
                  style: GoogleFonts.lexend(fontSize: 11, color: tDim)),
            ]),
          ]),
        )),
        const SizedBox(height: 12),
      ],
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: GestureDetector(onTap: detecting ? null : gps,
        child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(
            color: widget.loc.useGps ? glw.withValues(alpha: 0.12) : cbg, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: widget.loc.useGps ? glw.withValues(alpha: 0.5) : bdr, width: widget.loc.useGps ? 1.5 : 1)),
            child: Row(children: [
              Icon(Icons.my_location_rounded, size: 22, color: widget.loc.useGps ? glw : t2), const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Auto (GPS)', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: t1)),
                const SizedBox(height: 2),
                Text(widget.loc.useGps ? widget.loc.displayName : 'Tap to detect your location via GPS', style: GoogleFonts.inter(fontSize: 12, color: t2)),
              ])),
              if (detecting) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              if (widget.loc.useGps && !detecting) Icon(Icons.check_circle_rounded, size: 20, color: glw),
            ])))),
      const SizedBox(height: 16),
      // ── Browse all cities (hierarchical picker) ──
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: GestureDetector(
        onTap: () async {
          final ok = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => CityPickerSheet(loc: widget.loc, isNight: n),
          );
          if (ok == true && mounted) Navigator.pop(context);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cbg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: bdr),
          ),
          child: Row(children: [
            Icon(Icons.public_rounded, size: 22, color: glw),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('تصفح كل الدول والمدن', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: t1)),
              const SizedBox(height: 2),
              Text('اختيار هرمي: دولة ← منطقة ← مدينة', style: GoogleFonts.inter(fontSize: 12, color: t2)),
            ])),
            Icon(Icons.chevron_left_rounded, size: 18, color: tDim),
          ]),
        ),
      )),
      const SizedBox(height: 16),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Align(alignment: Alignment.centerRight,
          child: Text('Select City', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: t2, letterSpacing: 3)))),
      const SizedBox(height: 8),
      Flexible(child: ListView.builder(shrinkWrap: true, padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewPadding.bottom),
          itemCount: CityData.popular.length,
          itemBuilder: (_, i) {
            final c = CityData.popular[i];
            final sel = !widget.loc.useGps && widget.loc.cityName == c.name;
            return GestureDetector(onTap: () => selectCity(c),
                child: Container(margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: sel ? glw.withValues(alpha: 0.12) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      Text(c.name, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: sel ? t1 : t2)),
                      const Spacer(),
                      if (sel) Icon(Icons.check_rounded, size: 18, color: glw),
                    ])));
          })),
      const SizedBox(height: 24),
    ]));
}
