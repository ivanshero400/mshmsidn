import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/mosque_service.dart';
import '../services/location_service.dart';
import '../services/app_theme_colors.dart';

class MosquePickerPage extends StatefulWidget {
  final MosqueService srv; final LocationService loc; final bool isNight; final bool translateToArabic;
  const MosquePickerPage({super.key, required this.srv, required this.loc, this.isNight = true, this.translateToArabic = false});
  @override State<MosquePickerPage> createState() => _MosquePickerPageState();
}

class _MosquePickerPageState extends State<MosquePickerPage> {
  List<MosqueWithTimes> _list = [];
  bool _discovering = false;
  String _stepLabel = '', _stepDetail = '';
  String? _err;

  bool get n => widget.isNight;
  Color get bg => n ? AppThemeColors.nightBg : AppThemeColors.dayBg;
  Color get cbg => n ? AppThemeColors.nightCardBg : AppThemeColors.dayCardBg;
  Color get t1 => n ? AppThemeColors.nightTextPrimary : AppThemeColors.dayTextPrimary;
  Color get t2 => n ? AppThemeColors.nightTextSecondary : AppThemeColors.dayTextSecondary;
  Color get tDim => n ? AppThemeColors.nightTextDim : AppThemeColors.dayTextDim;
  Color get bdr => n ? AppThemeColors.nightBorder : AppThemeColors.dayBorder;
  Color get glw => n ? AppThemeColors.nightGlow : AppThemeColors.dayGlow;

  @override void initState() { super.initState(); _discover(); }

  Future<void> _discover() async {
    setState(() { _discovering = true; _err = null; _stepLabel = 'جارٍ التحضير...'; _stepDetail = ''; });
    try {
      final list = await widget.srv.discoverNearby(
        widget.loc.latitude, widget.loc.longitude,
        translateToArabic: widget.translateToArabic,
        onProgress: (step, detail) {
          if (mounted) setState(() { _stepLabel = step; _stepDetail = detail; });
        },
      );
      if (mounted) setState(() { _list = list; _discovering = false; });
    } catch (_) {
      if (mounted) setState(() { _discovering = false; _err = 'تعذر إكمال البحث. تأكد من اتصالك بالإنترنت.'; });
    }
  }

  Future<void> _pick(MosqueWithTimes e) async {
    final ok = await widget.srv.selectMosque(e);
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _reset() async {
    final c = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: cbg, title: Text('إعادة الضبط', style: GoogleFonts.inter(color: t1)),
      content: Text('العودة إلى هيئة الحساب الافتراضية.', style: GoogleFonts.inter(color: t2)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: Text('إلغاء', style: GoogleFonts.inter(color: t2))),
                TextButton(onPressed: () => Navigator.pop(ctx,true), child: Text('تأكيد', style: GoogleFonts.inter(color: glw)))]));
    if (c == true) { await widget.srv.resetToDefault(); if (mounted) Navigator.pop(context, true); }
  }

  String _sum(MosqueSchedule s) => 'فجر ${s.fajr} · ظهر ${s.dhuhr} · عصر ${s.asr} · مغرب ${s.maghrib} · عشاء ${s.isha}';

  @override Widget build(BuildContext ctx) {
    final has = widget.srv.hasMosque;
    return Scaffold(backgroundColor: bg,
      appBar: AppBar(backgroundColor: bg, elevation: 0,
        leading: GestureDetector(onTap: ()=>Navigator.pop(ctx), child: Icon(Icons.arrow_back_rounded, size: 20, color: t1)),
        title: Text('المساجد القريبة', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: t1)), centerTitle: true),
      body: _discovering
          ? Center(child: Padding(padding: const EdgeInsets.all(40),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 52, height: 52, child: CircularProgressIndicator(strokeWidth: 3)),
                const SizedBox(height: 28),
                Text(_stepLabel, textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: t1)),
                const SizedBox(height: 8),
                Text(_stepDetail, textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 12, color: tDim)),
                const SizedBox(height: 26),
                Text('قد تستغرق هذه العملية بعض الوقت في المرة الأولى فقط',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 11, color: tDim.withValues(alpha: 0.55))),
              ])))
          : _err != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_err!, style: GoogleFonts.inter(color: tDim)), const SizedBox(height: 14),
                  ElevatedButton(onPressed: _discover, child: const Text('إعادة المحاولة'))]))
              : RefreshIndicator(onRefresh: _discover,
                  child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), children: [
                    if (has) _tile(onTap: _reset, icon: Icons.restart_alt_rounded,
                        title: 'إعادة ضبط الافتراضي', sub: 'العودة إلى هيئة الحساب', trail: widget.srv.mosqueName ?? ''),
                    const SizedBox(height: 10),
                    if (_list.isNotEmpty)
                      Padding(padding: const EdgeInsets.only(right: 4, bottom: 10),
                          child: Text('${_list.length} مسجد قريب:',
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: t2))),
                    ..._list.map((e) => Padding(padding: const EdgeInsets.only(bottom: 6),
                        child: _tile(onTap: () => _pick(e), icon: Icons.mosque_rounded,
                            title: '${e.mosque.name}  ${e.source == 'Mawaqit' ? '🎯' : '📡'}',
                            sub: '${e.mosque.distanceLabel} · ${_sum(e.schedule)}'))),
                    if (_list.isEmpty)
                      Center(child: Padding(padding: const EdgeInsets.all(40),
                          child: Text('لا توجد مساجد بأوقات متاحة', style: GoogleFonts.inter(color: tDim)))),
                  ])),
    );
  }

  Widget _tile({required VoidCallback onTap, required IconData icon, required String title, required String sub, String? trail}) {
    return GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(color: cbg, borderRadius: BorderRadius.circular(14), border: Border.all(color: bdr)),
      child: Row(children: [
        Icon(icon, size: 20, color: glw), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: t1)),
          const SizedBox(height: 2),
          Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11, color: t2))])),
        if (trail != null) Text(trail, style: GoogleFonts.lexend(fontSize: 10, color: tDim)),
      ])));
  }
}
