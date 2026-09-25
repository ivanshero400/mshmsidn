import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/adhan_alarm_service.dart';
import '../services/app_theme_colors.dart';

/// قسم «تعلّم»: فقه الوضوء والصلاة والجمع والقصر والتيمم وفاقد الطهورين،
/// وأذكار من الكتاب والسنة، وسورة الملك — منقول من نصوص الوحيين وكتب أهل العلم.
class LearnPage extends StatelessWidget {
  final bool isNight;
  const LearnPage({super.key, this.isNight = true});

  static const gold = Color(0xFFD4A853);

  Color get bg => isNight ? AppThemeColors.nightBg : AppThemeColors.dayBg;
  Color get cbg => isNight ? AppThemeColors.nightCardBg : AppThemeColors.dayCardBg;
  Color get t1 => isNight ? AppThemeColors.nightTextPrimary : AppThemeColors.dayTextPrimary;
  Color get t2 => isNight ? AppThemeColors.nightTextSecondary : AppThemeColors.dayTextSecondary;
  Color get bdr => isNight ? AppThemeColors.nightBorder : AppThemeColors.dayBorder;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('wudu', Icons.water_drop_rounded, 'فقه الوضوء', 'صفة وضوء النبي ﷺ وفروضه ونواقضه'),
      ('salah', Icons.mosque_rounded, 'فقه الصلاة', 'صفة الصلاة كاملة كما في السنة'),
      ('travel', Icons.luggage_rounded, 'الجمع والقصر', 'أحكام صلاة المسافر ومسائل الخلاف'),
      ('tayammum', Icons.back_hand_rounded, 'التيمم', 'حالاته وكيفيته ونواقضه'),
      ('faqid', Icons.do_not_touch_rounded, 'فاقد الطهورين', 'من لا يجد ماءً ولا تراباً'),
      ('adhkar', Icons.favorite_rounded, 'أذكار من الكتاب والسنة', 'أذكار الصلاة والصباح والمساء + الإشعارات'),
      ('mulk', Icons.nightlight_round, 'سورة الملك', 'فضلها وقراءتها قبل النوم'),
    ];

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: _backBtn(context),
        title: Text('تعلّم',
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: t1)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          for (final it in items)
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => it.$1 == 'mulk'
                      ? MulkPage(isNight: isNight)
                      : LearnTopicPage(topicId: it.$1, isNight: isNight),
                ),
              ),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cbg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: bdr),
                ),
                child: Row(children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: gold.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(it.$2, size: 21, color: gold),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(it.$3,
                          style: GoogleFonts.inter(
                              fontSize: 15, fontWeight: FontWeight.w700, color: t1)),
                      const SizedBox(height: 2),
                      Text(it.$4, style: GoogleFonts.inter(fontSize: 11.5, color: t2)),
                    ]),
                  ),
                  Icon(Icons.chevron_left_rounded, size: 20, color: t2),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _backBtn(BuildContext context) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: cbg, borderRadius: BorderRadius.circular(12), border: Border.all(color: bdr)),
          child: Icon(Icons.arrow_back_rounded, size: 20, color: t1),
        ),
      );
}

// ═══════════════════════════ TOPIC VIEWER ═══════════════════════════

class LearnTopicPage extends StatefulWidget {
  final String topicId;
  final bool isNight;
  const LearnTopicPage({super.key, required this.topicId, this.isNight = true});

  @override
  State<LearnTopicPage> createState() => _LearnTopicPageState();
}

class _LearnTopicPageState extends State<LearnTopicPage> {
  static const gold = Color(0xFFD4A853);
  bool get n => widget.isNight;
  Color get bg => n ? AppThemeColors.nightBg : AppThemeColors.dayBg;
  Color get cbg => n ? AppThemeColors.nightCardBg : AppThemeColors.dayCardBg;
  Color get t1 => n ? AppThemeColors.nightTextPrimary : AppThemeColors.dayTextPrimary;
  Color get t2 => n ? AppThemeColors.nightTextSecondary : AppThemeColors.dayTextSecondary;
  Color get bdr => n ? AppThemeColors.nightBorder : AppThemeColors.dayBorder;

  bool _adhkarNotif = false;

  @override
  void initState() {
    super.initState();
    if (widget.topicId == 'adhkar') {
      SharedPreferences.getInstance().then((p) {
        if (mounted) setState(() => _adhkarNotif = p.getBool('adhkar_notif') ?? false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final topic = _learnContent[widget.topicId]!;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: cbg, borderRadius: BorderRadius.circular(12), border: Border.all(color: bdr)),
            child: Icon(Icons.arrow_back_rounded, size: 20, color: t1),
          ),
        ),
        title: Text(topic.title,
            style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: t1)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
        children: [
          if (widget.topicId == 'adhkar') ...[
            _adhkarToggleCard(),
            const SizedBox(height: 16),
          ],
          for (final s in topic.sections) ...[
            Row(children: [
              Container(width: 4, height: 18,
                  decoration: BoxDecoration(color: gold, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 10),
              Expanded(
                child: Text(s.$1,
                    style: GoogleFonts.inter(
                        fontSize: 16, fontWeight: FontWeight.w800, color: gold)),
              ),
            ]),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cbg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: bdr),
              ),
              child: Text(s.$2,
                  style: GoogleFonts.notoNaskhArabic(
                      fontSize: 15.5, height: 2.0, color: t1)),
            ),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }

  Widget _adhkarToggleCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: gold.withValues(alpha: n ? 0.08 : 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: gold.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(Icons.notifications_active_rounded, size: 22, color: gold),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('إشعارات الأذكار',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: t1)),
              const SizedBox(height: 3),
              Text(
                'أذكار بعد كل صلاة، وأذكار الصباح بعد الفجر والمساء بعد العصر، وتذكير بسورة الملك قبل النوم',
                style: GoogleFonts.inter(fontSize: 11, height: 1.5, color: t2),
              ),
            ]),
          ),
          GestureDetector(
            onTap: () async {
              final p = await SharedPreferences.getInstance();
              await p.setBool('adhkar_notif', !_adhkarNotif);
              // Re-arm native alarms so the adhkar schedule applies now.
              AdhanAlarmService.schedulePrayerAlarms(const []);
              if (mounted) setState(() => _adhkarNotif = !_adhkarNotif);
            },
            child: Container(
              width: 42, height: 25,
              decoration: BoxDecoration(
                color: _adhkarNotif ? gold : t2.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(13),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: _adhkarNotif ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  width: 21, height: 21,
                  margin: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                ),
              ),
            ),
          ),
        ]),
      );
}

// ═══════════════════════════ SURAH AL-MULK ═══════════════════════════

class MulkPage extends StatelessWidget {
  final bool isNight;
  const MulkPage({super.key, this.isNight = true});

  static const gold = Color(0xFFD4A853);

  @override
  Widget build(BuildContext context) {
    final bg = isNight ? AppThemeColors.nightBg : AppThemeColors.dayBg;
    final cbg = isNight ? AppThemeColors.nightCardBg : AppThemeColors.dayCardBg;
    final t1 = isNight ? AppThemeColors.nightTextPrimary : AppThemeColors.dayTextPrimary;
    final t2 = isNight ? AppThemeColors.nightTextSecondary : AppThemeColors.dayTextSecondary;
    final bdr = isNight ? AppThemeColors.nightBorder : AppThemeColors.dayBorder;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: cbg, borderRadius: BorderRadius.circular(12), border: Border.all(color: bdr)),
            child: Icon(Icons.arrow_back_rounded, size: 20, color: t1),
          ),
        ),
        title: Text('سورة الملك',
            style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: t1)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: gold.withValues(alpha: isNight ? 0.08 : 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: gold.withValues(alpha: 0.35)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('🌙 فضل سورة الملك',
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: gold)),
              const SizedBox(height: 8),
              Text(
                'عن أبي هريرة رضي الله عنه عن النبي ﷺ قال: «سورةٌ من القرآن ثلاثون آية، شفعت لرجلٍ حتى غُفر له، وهي: تبارك الذي بيده الملك» — رواه أبو داود والترمذي وقال: حديث حسن.\n\n'
                'وعن ابن عباس رضي الله عنهما قال النبي ﷺ: «هي المانعة، هي المنجية، تنجيه من عذاب القبر» — رواه الترمذي.\n\n'
                'وكان النبي ﷺ لا ينام حتى يقرأ ﴿الم تنزيل﴾ السجدة و﴿تبارك الذي بيده الملك﴾ — رواه الترمذي وصححه الألباني.',
                style: GoogleFonts.notoNaskhArabic(fontSize: 14.5, height: 2.0, color: t1),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text('بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
                style: GoogleFonts.notoNaskhArabic(
                    fontSize: 20, fontWeight: FontWeight.w700, color: gold)),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cbg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: bdr),
            ),
            child: Text(
              _mulkText,
              textAlign: TextAlign.justify,
              style: GoogleFonts.notoNaskhArabic(fontSize: 19, height: 2.3, color: t1),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text('صدق الله العظيم',
                style: GoogleFonts.inter(fontSize: 12, color: t2)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════ CONTENT ═══════════════════════════

class _Topic {
  final String title;
  final List<(String, String)> sections;
  const _Topic(this.title, this.sections);
}

const String _mulkText =
    'تَبَارَكَ الَّذِي بِيَدِهِ الْمُلْكُ وَهُوَ عَلَىٰ كُلِّ شَيْءٍ قَدِيرٌ ﴿١﴾ الَّذِي خَلَقَ الْمَوْتَ وَالْحَيَاةَ لِيَبْلُوَكُمْ أَيُّكُمْ أَحْسَنُ عَمَلًا ۚ وَهُوَ الْعَزِيزُ الْغَفُورُ ﴿٢﴾ الَّذِي خَلَقَ سَبْعَ سَمَاوَاتٍ طِبَاقًا ۖ مَّا تَرَىٰ فِي خَلْقِ الرَّحْمَٰنِ مِن تَفَاوُتٍ ۖ فَارْجِعِ الْبَصَرَ هَلْ تَرَىٰ مِن فُطُورٍ ﴿٣﴾ ثُمَّ ارْجِعِ الْبَصَرَ كَرَّتَيْنِ يَنقَلِبْ إِلَيْكَ الْبَصَرُ خَاسِئًا وَهُوَ حَسِيرٌ ﴿٤﴾ وَلَقَدْ زَيَّنَّا السَّمَاءَ الدُّنْيَا بِمَصَابِيحَ وَجَعَلْنَاهَا رُجُومًا لِّلشَّيَاطِينِ ۖ وَأَعْتَدْنَا لَهُمْ عَذَابَ السَّعِيرِ ﴿٥﴾ وَلِلَّذِينَ كَفَرُوا بِرَبِّهِمْ عَذَابُ جَهَنَّمَ ۖ وَبِئْسَ الْمَصِيرُ ﴿٦﴾ إِذَا أُلْقُوا فِيهَا سَمِعُوا لَهَا شَهِيقًا وَهِيَ تَفُورُ ﴿٧﴾ تَكَادُ تَمَيَّزُ مِنَ الْغَيْظِ ۖ كُلَّمَا أُلْقِيَ فِيهَا فَوْجٌ سَأَلَهُمْ خَزَنَتُهَا أَلَمْ يَأْتِكُمْ نَذِيرٌ ﴿٨﴾ قَالُوا بَلَىٰ قَدْ جَاءَنَا نَذِيرٌ فَكَذَّبْنَا وَقُلْنَا مَا نَزَّلَ اللَّهُ مِن شَيْءٍ إِنْ أَنتُمْ إِلَّا فِي ضَلَالٍ كَبِيرٍ ﴿٩﴾ وَقَالُوا لَوْ كُنَّا نَسْمَعُ أَوْ نَعْقِلُ مَا كُنَّا فِي أَصْحَابِ السَّعِيرِ ﴿١٠﴾ فَاعْتَرَفُوا بِذَنبِهِمْ فَسُحْقًا لِّأَصْحَابِ السَّعِيرِ ﴿١١﴾ إِنَّ الَّذِينَ يَخْشَوْنَ رَبَّهُم بِالْغَيْبِ لَهُم مَّغْفِرَةٌ وَأَجْرٌ كَبِيرٌ ﴿١٢﴾ وَأَسِرُّوا قَوْلَكُمْ أَوِ اجْهَرُوا بِهِ ۖ إِنَّهُ عَلِيمٌ بِذَاتِ الصُّدُورِ ﴿١٣﴾ أَلَا يَعْلَمُ مَنْ خَلَقَ وَهُوَ اللَّطِيفُ الْخَبِيرُ ﴿١٤﴾ هُوَ الَّذِي جَعَلَ لَكُمُ الْأَرْضَ ذَلُولًا فَامْشُوا فِي مَنَاكِبِهَا وَكُلُوا مِن رِّزْقِهِ ۖ وَإِلَيْهِ النُّشُورُ ﴿١٥﴾ أَأَمِنتُم مَّن فِي السَّمَاءِ أَن يَخْسِفَ بِكُمُ الْأَرْضَ فَإِذَا هِيَ تَمُورُ ﴿١٦﴾ أَمْ أَمِنتُم مَّن فِي السَّمَاءِ أَن يُرْسِلَ عَلَيْكُمْ حَاصِبًا ۖ فَسَتَعْلَمُونَ كَيْفَ نَذِيرِ ﴿١٧﴾ وَلَقَدْ كَذَّبَ الَّذِينَ مِن قَبْلِهِمْ فَكَيْفَ كَانَ نَكِيرِ ﴿١٨﴾ أَوَلَمْ يَرَوْا إِلَى الطَّيْرِ فَوْقَهُمْ صَافَّاتٍ وَيَقْبِضْنَ ۚ مَا يُمْسِكُهُنَّ إِلَّا الرَّحْمَٰنُ ۚ إِنَّهُ بِكُلِّ شَيْءٍ بَصِيرٌ ﴿١٩﴾ أَمَّنْ هَٰذَا الَّذِي هُوَ جُندٌ لَّكُمْ يَنصُرُكُم مِّن دُونِ الرَّحْمَٰنِ ۚ إِنِ الْكَافِرُونَ إِلَّا فِي غُرُورٍ ﴿٢٠﴾ أَمَّنْ هَٰذَا الَّذِي يَرْزُقُكُمْ إِنْ أَمْسَكَ رِزْقَهُ ۚ بَل لَّجُّوا فِي عُتُوٍّ وَنُفُورٍ ﴿٢١﴾ أَفَمَن يَمْشِي مُكِبًّا عَلَىٰ وَجْهِهِ أَهْدَىٰ أَمَّن يَمْشِي سَوِيًّا عَلَىٰ صِرَاطٍ مُّسْتَقِيمٍ ﴿٢٢﴾ قُلْ هُوَ الَّذِي أَنشَأَكُمْ وَجَعَلَ لَكُمُ السَّمْعَ وَالْأَبْصَارَ وَالْأَفْئِدَةَ ۖ قَلِيلًا مَّا تَشْكُرُونَ ﴿٢٣﴾ قُلْ هُوَ الَّذِي ذَرَأَكُمْ فِي الْأَرْضِ وَإِلَيْهِ تُحْشَرُونَ ﴿٢٤﴾ وَيَقُولُونَ مَتَىٰ هَٰذَا الْوَعْدُ إِن كُنتُمْ صَادِقِينَ ﴿٢٥﴾ قُلْ إِنَّمَا الْعِلْمُ عِندَ اللَّهِ وَإِنَّمَا أَنَا نَذِيرٌ مُّبِينٌ ﴿٢٦﴾ فَلَمَّا رَأَوْهُ زُلْفَةً سِيئَتْ وُجُوهُ الَّذِينَ كَفَرُوا وَقِيلَ هَٰذَا الَّذِي كُنتُم بِهِ تَدَّعُونَ ﴿٢٧﴾ قُلْ أَرَأَيْتُمْ إِنْ أَهْلَكَنِيَ اللَّهُ وَمَن مَّعِيَ أَوْ رَحِمَنَا فَمَن يُجِيرُ الْكَافِرِينَ مِنْ عَذَابٍ أَلِيمٍ ﴿٢٨﴾ قُلْ هُوَ الرَّحْمَٰنُ آمَنَّا بِهِ وَعَلَيْهِ تَوَكَّلْنَا ۖ فَسَتَعْلَمُونَ مَنْ هُوَ فِي ضَلَالٍ مُّبِينٍ ﴿٢٩﴾ قُلْ أَرَأَيْتُمْ إِنْ أَصْبَحَ مَاؤُكُمْ غَوْرًا فَمَن يَأْتِيكُم بِمَاءٍ مَّعِينٍ ﴿٣٠﴾';

final Map<String, _Topic> _learnContent = {
  'wudu': _Topic('فقه الوضوء', [
    (
      'صفة وضوء النبي ﷺ',
      'عن حُمران مولى عثمان: أن عثمان بن عفان رضي الله عنه دعا بوَضوء، فغسل كفيه ثلاث مرات، ثم مضمض واستنشق واستنثر، ثم غسل وجهه ثلاث مرات، ثم غسل يده اليمنى إلى المرفق ثلاث مرات، ثم اليسرى مثل ذلك، ثم مسح برأسه، ثم غسل رجله اليمنى إلى الكعبين ثلاث مرات، ثم اليسرى مثل ذلك، ثم قال: رأيت رسول الله ﷺ توضأ نحو وضوئي هذا — متفق عليه.\n\n'
      'فالخطوات بالترتيب:\n'
      '١. النية بالقلب (إنما الأعمال بالنيات — متفق عليه) ولا يُشرع التلفظ بها.\n'
      '٢. التسمية: «بسم الله».\n'
      '٣. غسل الكفين ثلاثاً.\n'
      '٤. المضمضة والاستنشاق ثلاثاً (ويبالغ فيهما إلا أن يكون صائماً).\n'
      '٥. غسل الوجه ثلاثاً: من منابت الشعر إلى الذقن، ومن الأذن إلى الأذن.\n'
      '٦. غسل اليدين مع المرفقين ثلاثاً، يبدأ باليمنى.\n'
      '٧. مسح الرأس مرة واحدة: يُقبل بيديه ويُدبر، ويمسح الأذنين بباطن السبابتين وظاهر الإبهامين.\n'
      '٨. غسل الرجلين مع الكعبين ثلاثاً، يبدأ باليمنى، ويخلل الأصابع.'
    ),
    (
      'فروض الوضوء (التي لا يصح بدونها)',
      'دلّت عليها آية المائدة: ﴿يَا أَيُّهَا الَّذِينَ آمَنُوا إِذَا قُمْتُمْ إِلَى الصَّلَاةِ فَاغْسِلُوا وُجُوهَكُمْ وَأَيْدِيَكُمْ إِلَى الْمَرَافِقِ وَامْسَحُوا بِرُءُوسِكُمْ وَأَرْجُلَكُمْ إِلَى الْكَعْبَيْنِ﴾ [المائدة: ٦]\n\n'
      '١. غسل الوجه ومنه المضمضة والاستنشاق.\n'
      '٢. غسل اليدين إلى المرفقين.\n'
      '٣. مسح الرأس كله ومنه الأذنان.\n'
      '٤. غسل الرجلين إلى الكعبين.\n'
      '٥. الترتيب بين الأعضاء.\n'
      '٦. الموالاة: ألا يؤخر غسل عضو حتى يجف الذي قبله.\n\n'
      'وما زاد على ذلك — كالتثليث والتيامن — سننٌ يُؤجر فاعلها ولا يبطل الوضوء بتركها.'
    ),
    (
      'الذكر بعد الوضوء',
      'قال رسول الله ﷺ: «ما منكم من أحد يتوضأ فيُسبغ الوضوء ثم يقول: أشهد أن لا إله إلا الله وحده لا شريك له، وأشهد أن محمداً عبده ورسوله، إلا فُتحت له أبواب الجنة الثمانية يدخل من أيها شاء» — رواه مسلم.\n\n'
      'وزاد الترمذي: «اللهم اجعلني من التوابين واجعلني من المتطهرين».'
    ),
    (
      'نواقض الوضوء',
      '١. الخارج من السبيلين (بول، غائط، ريح) — لقوله ﷺ: «لا يقبل الله صلاة أحدكم إذا أحدث حتى يتوضأ» متفق عليه.\n'
      '٢. النوم المستغرق الذي يزول معه الإدراك.\n'
      '٣. زوال العقل بإغماء أو سُكر.\n'
      '٤. مسّ الفرج باليد مباشرة بلا حائل — لحديث: «من مسّ ذكره فليتوضأ» رواه أصحاب السنن وصححه أحمد.\n'
      '٥. أكل لحم الإبل — لحديث مسلم: سُئل ﷺ: أنتوضأ من لحوم الإبل؟ قال: «نعم».\n\n'
      'ومما لا ينقض على الصحيح: لمس المرأة بغير شهوة، وخروج الدم من غير السبيلين، والقيء — لعدم ثبوت الدليل الموجب.'
    ),
  ]),
  'salah': _Topic('فقه الصلاة', [
    (
      'القاعدة الجامعة',
      'قال رسول الله ﷺ: «صلّوا كما رأيتموني أصلي» — رواه البخاري.\n\n'
      'فمرجع صفة الصلاة هو فعل النبي ﷺ المنقول في الصحيحين وغيرهما، وأشهر حديث جامع لها حديث «المسيء صلاته» — متفق عليه — الذي علّم فيه النبي ﷺ الأركان التي لا تصح الصلاة إلا بها.'
    ),
    (
      'صفة الصلاة خطوة بخطوة',
      '١. استقبال القبلة بالبدن كله، والنية بالقلب.\n\n'
      '٢. تكبيرة الإحرام: «الله أكبر» رافعاً يديه حذو منكبيه أو أذنيه.\n\n'
      '٣. وضع اليد اليمنى على اليسرى على الصدر، والنظر إلى موضع السجود.\n\n'
      '٤. دعاء الاستفتاح (انظر قسم الأذكار).\n\n'
      '٥. التعوذ والبسملة ثم قراءة الفاتحة — وهي ركن: «لا صلاة لمن لم يقرأ بفاتحة الكتاب» متفق عليه — ثم سورة أو ما تيسر في الأوليين.\n\n'
      '٦. الركوع: يكبّر رافعاً يديه، ويسوّي ظهره ويضع كفيه على ركبتيه، ويقول: «سبحان ربي العظيم» ثلاثاً، ومن السنة الزيادة: «سبحانك اللهم ربنا وبحمدك اللهم اغفر لي» متفق عليه.\n\n'
      '٧. الرفع من الركوع: «سمع الله لمن حمده» ثم «ربنا ولك الحمد، حمداً كثيراً طيباً مباركاً فيه» مطمئناً قائماً.\n\n'
      '٨. السجود مكبّراً على الأعضاء السبعة: «أُمرت أن أسجد على سبعة أعظم: الجبهة — وأشار إلى أنفه — واليدين والركبتين وأطراف القدمين» متفق عليه. يقول: «سبحان ربي الأعلى» ثلاثاً ويكثر من الدعاء: «أقرب ما يكون العبد من ربه وهو ساجد فأكثروا الدعاء» رواه مسلم.\n\n'
      '٩. الجلوس بين السجدتين مفترشاً: «ربِّ اغفر لي، ربِّ اغفر لي».\n\n'
      '١٠. السجدة الثانية مثل الأولى، ثم يقوم للركعة التالية.\n\n'
      '١١. التشهد الأوسط بعد الركعتين: «التحيات لله والصلوات والطيبات، السلام عليك أيها النبي ورحمة الله وبركاته، السلام علينا وعلى عباد الله الصالحين، أشهد أن لا إله إلا الله وأشهد أن محمداً عبده ورسوله» — متفق عليه.\n\n'
      '١٢. التشهد الأخير ويزيد الصلاة الإبراهيمية: «اللهم صلِّ على محمد وعلى آل محمد كما صليت على إبراهيم وعلى آل إبراهيم إنك حميد مجيد...» متفق عليه، ثم الاستعاذة من أربع (انظر الأذكار).\n\n'
      '١٣. التسليم: «السلام عليكم ورحمة الله» يميناً ثم شمالاً.'
    ),
    (
      'أركان لا تصح الصلاة بدونها',
      'القيام في الفريضة للقادر، تكبيرة الإحرام، قراءة الفاتحة، الركوع، الرفع منه، السجود على الأعضاء السبعة، الجلسة بين السجدتين، الطمأنينة في كل ركن — لقوله ﷺ للمسيء صلاته: «ثم اركع حتى تطمئن راكعاً» — والتشهد الأخير وجلسته، والتسليم، والترتيب بين الأركان.\n\n'
      'فمن أخلّ بالطمأنينة — وهي أكثر ما يفرّط الناس فيه — لم تصح صلاته، لقوله ﷺ للرجل: «ارجع فصلِّ فإنك لم تصلِّ».'
    ),
  ]),
  'travel': _Topic('الجمع والقصر', [
    (
      'القصر: الأصل ودليله',
      'القصر: أداء الصلاة الرباعية (الظهر والعصر والعشاء) ركعتين في السفر. أما الفجر والمغرب فلا تُقصران.\n\n'
      'الدليل: ﴿وَإِذَا ضَرَبْتُمْ فِي الْأَرْضِ فَلَيْسَ عَلَيْكُمْ جُنَاحٌ أَن تَقْصُرُوا مِنَ الصَّلَاةِ﴾ [النساء: ١٠١].\n\n'
      'وسأل يعلى بن أمية عمرَ بن الخطاب: قد أمِن الناس! فقال عمر: عجبتُ مما عجبتَ منه، فسألت رسول الله ﷺ فقال: «صدقةٌ تصدّق الله بها عليكم فاقبلوا صدقته» — رواه مسلم.\n\n'
      'وكان ﷺ لا يزيد في السفر على ركعتين، حتى قال ابن عمر: «صحبت النبي ﷺ فكان لا يزيد في السفر على ركعتين، وأبا بكر وعمر وعثمان كذلك» — متفق عليه.'
    ),
    (
      'مسافة السفر — مسألة خلافية',
      'القول الأول (الجمهور: المالكية والشافعية والحنابلة): تُقدَّر بأربعة بُرُد ≈ ٨٠ كم تقريباً، لآثار وردت عن ابن عباس وابن عمر رضي الله عنهم.\n\n'
      'القول الثاني (الحنفية): مسيرة ثلاثة أيام بلياليها.\n\n'
      'القول الثالث (اختيار شيخ الإسلام ابن تيمية): لا حدّ للمسافة بالكيلومترات، بل كل ما سمّاه الناس سفراً وعُدّ في العرف سفراً قُصرت فيه الصلاة؛ لأن الشرع علّق الحكم بمطلق السفر ولم يحدّه.\n\n'
      'والعمل بقول الجمهور (~٨٠ كم) أحوط وأضبط للمسافر المعاصر، ومن أخذ بالعرف فله سلف.'
    ),
    (
      'متى يبدأ القصر ومدة الإقامة',
      'يبدأ المسافر بالقصر إذا فارق بنيان بلده — لأن الله قال: ﴿وَإِذَا ضَرَبْتُمْ فِي الْأَرْضِ﴾ ولا يكون ضارباً في الأرض وهو في بلده.\n\n'
      'مدة الإقامة التي ينقطع بها حكم السفر — خلاف مشهور:\n'
      '• الجمهور (الشافعية والمالكية والحنابلة): إذا نوى الإقامة أكثر من أربعة أيام أتمّ؛ لأن النبي ﷺ أقام بمكة في حجة الوداع أربعاً يقصر.\n'
      '• الحنفية: خمسة عشر يوماً.\n'
      '• اختيار ابن تيمية: يبقى مسافراً يقصر ما لم ينوِ الاستيطان أو إقامة مطلقة، ولو طالت المدة؛ لأن النبي ﷺ أقام بتبوك عشرين يوماً يقصر — رواه أحمد وأبو داود.\n\n'
      'فمن جلس في بلدٍ مدة محددة لعملٍ أو دراسة وأخذ بقول الجمهور أتمّ بعد أربعة أيام، ومن قلّد القول الآخر فلا حرج، والخلاف فيها سائغ.'
    ),
    (
      'الجمع: أسبابه وكيفيته',
      'الجمع: ضمّ الظهر إلى العصر، أو المغرب إلى العشاء، في وقت إحداهما — تقديماً أو تأخيراً. ولا جمع للفجر مع غيرها.\n\n'
      'أسبابه:\n'
      '١. السفر: جمع النبي ﷺ بين الظهر والعصر والمغرب والعشاء في غزوة تبوك — رواه مسلم. والأفضل للنازل المستقر تركه، فإن جدّ به السير جمع.\n'
      '٢. المطر والوحل الذي يشق معه الرجوع للمسجد (للجماعة في المسجد).\n'
      '٣. المرض الذي يلحق صاحبه بتركه مشقة.\n'
      '٤. الحاجة العارضة غير المتخذة عادة: لحديث ابن عباس: «جمع رسول الله ﷺ بين الظهر والعصر والمغرب والعشاء بالمدينة من غير خوفٍ ولا مطر»، قيل لابن عباس: ما أراد بذلك؟ قال: «أراد ألا يُحرج أمته» — رواه مسلم.\n\n'
      'تنبيه: القصر خاص بالسفر، أما الجمع فأوسع أسباباً؛ فقد يجمع المقيم لعذر ولا يقصر.'
    ),
  ]),
  'tayammum': _Topic('التيمم', [
    (
      'دليله',
      '﴿فَلَمْ تَجِدُوا مَاءً فَتَيَمَّمُوا صَعِيدًا طَيِّبًا فَامْسَحُوا بِوُجُوهِكُمْ وَأَيْدِيكُم مِّنْهُ﴾ [المائدة: ٦].\n\n'
      'وقال ﷺ: «جُعلت لي الأرض مسجداً وطَهوراً» — متفق عليه.'
    ),
    (
      'الحالات التي يُشرع فيها',
      '١. عدم وجود الماء أصلاً، في سفر أو حضر، بعد طلبه.\n'
      '٢. العجز عن استعماله: كمريضٍ يضره الماء أو يؤخر برأه — لحديث صاحب الشجّة: «إنما كان يكفيه أن يتيمم» رواه أبو داود.\n'
      '٣. شدة البرد مع تعذر تسخين الماء وخوف الضرر — كما في قصة عمرو بن العاص حين تيمم من الجنابة في ليلة باردة فأقرّه النبي ﷺ — رواه أبو داود.\n'
      '٤. الحاجة إلى الماء القليل للشرب أو الطبخ بحيث لو توضأ به عطش.\n\n'
      'ويقوم التيمم مقام الوضوء والغسل جميعاً، ويفعل به ما يفعل بالطهارة المائية.'
    ),
    (
      'كيفيته',
      'لحديث عمار بن ياسر — متفق عليه — أن النبي ﷺ قال له: «إنما كان يكفيك أن تقول بيديك هكذا»، ثم ضرب بيديه الأرض ضربة واحدة، ثم مسح الشمال على اليمين وظاهر كفيه ووجهه.\n\n'
      'فالكيفية: ١) النية. ٢) التسمية. ٣) ضرب الأرض الطاهرة (تراب أو رمل أو حجر — كل صعيد طيب) ضربة واحدة بالكفين. ٤) مسح الوجه. ٥) مسح الكفين بعضهما ببعض.\n\n'
      'ولا تُشترط ضربتان ولا المسح إلى المرفقين على الصحيح؛ اقتصاراً على حديث عمار.'
    ),
    (
      'نواقضه',
      '١. كل ما ينقض الوضوء ينقض التيمم.\n'
      '٢. وجود الماء لمن تيمم لفقده — لقوله ﷺ: «الصعيد الطيب طَهور المسلم وإن لم يجد الماء عشر سنين، فإذا وجد الماء فليتقِ الله وليُمسّه بشرته» رواه أبو داود والترمذي.\n'
      '٣. زوال العذر المبيح (كشفاء المريض).\n\n'
      'وما صلاه بالتيمم قبل وجود الماء صحيح ولا إعادة عليه.'
    ),
  ]),
  'faqid': _Topic('فاقد الطهورين', [
    (
      'من هو؟',
      'هو من لا يجد ماءً ولا تراباً، أو عجز عن استعمالهما معاً: كالمريض المربوط الذي لا يستطيع الحركة ولا يجد من يناوله، والمحبوس في مكان لا ماء فيه ولا صعيد، ومن على متن طائرة لا يمكنه شيء من ذلك.'
    ),
    (
      'حكمه',
      'الصحيح من أقوال أهل العلم — وهو مذهب الشافعي وأحمد في رواية واختاره جمع من المحققين — أنه يصلي على حاله بلا وضوء ولا تيمم، ولا إعادة عليه.\n\n'
      'الدليل: حديث عائشة رضي الله عنها لما انقطع عقدها وأقام الناس على غير ماء، فصلوا بغير وضوء، فلم يأمرهم النبي ﷺ بالإعادة، ونزلت بعدها آية التيمم — متفق عليه. فدل على أن الصلاة لا تسقط بفقد الطهارة.\n\n'
      'وقاعدة الباب: ﴿لَا يُكَلِّفُ اللَّهُ نَفْسًا إِلَّا وُسْعَهَا﴾ [البقرة: ٢٨٦]، وقوله ﷺ: «إذا أمرتكم بأمرٍ فأتوا منه ما استطعتم» — متفق عليه.\n\n'
      'فالصلاة في وقتها آكد من شرطها العاجز عنه، ولا يجوز تأخيرها حتى يخرج وقتها بحجة انتظار الماء.'
    ),
  ]),
  'adhkar': _Topic('أذكار من الكتاب والسنة', [
    (
      'أدعية الاستفتاح (بعد تكبيرة الإحرام)',
      '١. «اللهم باعد بيني وبين خطاياي كما باعدت بين المشرق والمغرب، اللهم نقّني من خطاياي كما يُنقّى الثوب الأبيض من الدنس، اللهم اغسلني من خطاياي بالثلج والماء والبَرَد» — متفق عليه.\n\n'
      '٢. «سبحانك اللهم وبحمدك، وتبارك اسمك، وتعالى جدّك، ولا إله غيرك» — رواه أبو داود والترمذي.\n\n'
      'يُقال أحدها سراً قبل الفاتحة، والتنويع بينها سنة.'
    ),
    (
      'في الركوع',
      '«سبحان ربي العظيم» ثلاثاً — رواه مسلم.\n\n'
      '«سبحانك اللهم ربنا وبحمدك، اللهم اغفر لي» — متفق عليه.\n\n'
      '«سبّوح قدّوس، رب الملائكة والروح» — رواه مسلم.'
    ),
    (
      'في السجود',
      '«سبحان ربي الأعلى» ثلاثاً — رواه مسلم.\n\n'
      '«اللهم اغفر لي ذنبي كله: دقّه وجلّه، وأوله وآخره، وعلانيته وسرّه» — رواه مسلم.\n\n'
      'وأكثر من الدعاء بما شئت، فقال ﷺ: «أقرب ما يكون العبد من ربه وهو ساجد، فأكثروا الدعاء» — رواه مسلم.'
    ),
    (
      'قبل السلام (في آخر التشهد)',
      '«اللهم إني أعوذ بك من عذاب جهنم، ومن عذاب القبر، ومن فتنة المحيا والممات، ومن شر فتنة المسيح الدجال» — متفق عليه، وقد أمر ﷺ بها بعد التشهد الأخير.\n\n'
      'ودعاء أبي بكر رضي الله عنه — علّمه إياه النبي ﷺ: «اللهم إني ظلمت نفسي ظلماً كثيراً، ولا يغفر الذنوب إلا أنت، فاغفر لي مغفرةً من عندك وارحمني، إنك أنت الغفور الرحيم» — متفق عليه.'
    ),
    (
      'بعد السلام من الصلاة',
      '١. «أستغفر الله» ثلاثاً، «اللهم أنت السلام ومنك السلام، تباركت يا ذا الجلال والإكرام» — رواه مسلم.\n\n'
      '٢. «لا إله إلا الله وحده لا شريك له، له الملك وله الحمد وهو على كل شيء قدير، اللهم لا مانع لما أعطيت ولا معطي لما منعت، ولا ينفع ذا الجَدّ منك الجَدّ» — متفق عليه.\n\n'
      '٣. التسبيح: سبحان الله ٣٣، الحمد لله ٣٣، الله أكبر ٣٣، وتمام المائة: «لا إله إلا الله وحده لا شريك له، له الملك وله الحمد وهو على كل شيء قدير» — «غُفرت خطاياه وإن كانت مثل زبد البحر» رواه مسلم.\n\n'
      '٤. آية الكرسي: «من قرأها دبر كل صلاة مكتوبة لم يمنعه من دخول الجنة إلا أن يموت» — رواه النسائي وصححه الألباني.\n\n'
      '٥. المعوذات (الإخلاص والفلق والناس) دبر كل صلاة — رواه أبو داود والترمذي — وتُثلَّث بعد الفجر والمغرب.\n\n'
      '٦. «اللهم أعني على ذكرك وشكرك وحسن عبادتك» — أوصى بها النبي ﷺ معاذاً دبر كل صلاة — رواه أبو داود والنسائي.'
    ),
    (
      'من أذكار الصباح والمساء',
      '١. سيد الاستغفار: «اللهم أنت ربي لا إله إلا أنت، خلقتني وأنا عبدك، وأنا على عهدك ووعدك ما استطعت، أعوذ بك من شر ما صنعت، أبوء لك بنعمتك عليّ وأبوء بذنبي، فاغفر لي فإنه لا يغفر الذنوب إلا أنت» — من قالها موقناً بها فمات من يومه/ليلته دخل الجنة — رواه البخاري.\n\n'
      '٢. آية الكرسي: من قالها حين يصبح أُجير من الجن حتى يمسي، ومن قالها حين يمسي أُجير حتى يصبح — رواه الحاكم وصححه الألباني.\n\n'
      '٣. الإخلاص والمعوذتان ثلاثاً: «تكفيك من كل شيء» — رواه أبو داود والترمذي.\n\n'
      '٤. «أصبحنا وأصبح الملك لله، والحمد لله، لا إله إلا الله وحده لا شريك له...» وفي المساء: «أمسينا وأمسى الملك لله...» — رواه مسلم.\n\n'
      '٥. «اللهم بك أصبحنا وبك أمسينا، وبك نحيا وبك نموت وإليك النشور» — رواه الترمذي.\n\n'
      '٦. «بسم الله الذي لا يضر مع اسمه شيء في الأرض ولا في السماء وهو السميع العليم» ثلاثاً: لم يضره شيء — رواه أبو داود والترمذي.\n\n'
      '٧. «رضيت بالله رباً وبالإسلام ديناً وبمحمدٍ ﷺ نبياً» ثلاثاً — رواه أبو داود.\n\n'
      '٨. «حسبي الله لا إله إلا هو عليه توكلت وهو رب العرش العظيم» سبعاً — رواه أبو داود.\n\n'
      '٩. «سبحان الله وبحمده» مائة مرة — «لم يأتِ أحدٌ يوم القيامة بأفضل مما جاء به إلا أحد قال مثل ما قال أو زاد عليه» — رواه مسلم.'
    ),
  ]),
};
