import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/location_service.dart';
import '../services/adhan_sound_service.dart';
import '../services/aladhan_api_service.dart';
import '../services/prayer_times_service.dart';
import '../services/l10n_service.dart';
import 'permission_gate.dart';
import 'city_picker_sheet.dart';

/// Comprehensive first-launch onboarding flow
class OnboardingPage extends StatefulWidget {
  final PrayerTimesService timesService;
  final AdhanSoundService adhanService;
  final L10nService l10n;
  final VoidCallback onComplete;
  const OnboardingPage({
    super.key,
    required this.timesService,
    required this.adhanService,
    required this.l10n,
    required this.onComplete,
  });
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _step = 0;
  static const _totalSteps = 9;
  static const _kStepKey = 'onboarding_step';

  PrayerTimesService get ts => widget.timesService;
  LocationService get loc => widget.timesService.locationService;
  AdhanSoundService get adhan => widget.adhanService;
  L10nService get l10n => widget.l10n;

  // ── Step 0 (language) state ──
  late String _lang;

  // ── Step 3 (adhan) state ──
  bool _soundsLoading = true;
  List<AdhanSound> _sounds = [];
  String? _selectedSoundKey;
  String? _onboardPlayingKey;
  final TextEditingController _searchCtrl = TextEditingController();

  // ── Step 3 (location) state ──
  bool _detectingGps = false;
  bool _locationDetected = false;
  List<SearchResult> _searchResults = [];

  // ── Step 4 (prayer settings) state ──
  int _method = 12; // default: UOIF France
  Madhab _madhab = Madhab.shafii;
  double? _fajrAngle;
  double? _ishaAngle;
  String _ishaMode = 'angle';

  // ── Step 5 (display) state ──
  bool _showHijri = true;
  bool _use24h = false;

  // ── Theme ──
  static const Color gold = Color(0xFFD4A853);
  static const Color nightBg = Color(0xFF08080F);
  static const Color nightCardBg = Color(0xFF14141E);
  static const Color nightText = Color(0xFFF0EDE4);
  static const Color nightText2 = Color(0xFF9A9588);
  static const Color nightTextDim = Color(0xFF4A4540);
  static const Color nightBorder = Color(0xFF2A2528);

  @override
  void initState() {
    super.initState();
    _method = ts.method;
    _madhab = ts.madhab;
    _fajrAngle = ts.fajrAngle;
    _ishaAngle = ts.ishaAngle;
    _ishaMode = ts.ishaMode;
    _showHijri = ts.showHijri;
    _use24h = ts.use24h;
    _lang = l10n.locale;
    _loadSounds();
    _restoreStep();
  }

  /// Resume at the step the user last reached (survives app restarts as long as
  /// app data isn't wiped).
  Future<void> _restoreStep() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_kStepKey) ?? 0;
    if (saved > 0 && saved < _totalSteps && mounted) {
      setState(() => _step = saved);
    }
  }

  Future<void> _saveStep() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kStepKey, _step);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    adhan.stop();
    super.dispose();
  }

  Future<void> _loadSounds() async {
    await adhan.fetchSounds();
    if (mounted) {
      setState(() {
        _sounds = adhan.sounds;
        _soundsLoading = false;
        // Auto-select first sound as default if none selected
        if (adhan.selectedKey == null && _sounds.isNotEmpty) {
          _selectedSoundKey = _sounds.first.key;
        } else {
          _selectedSoundKey = adhan.selectedKey;
        }
      });
    }
  }

  void _next() {
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
      _saveStep();
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    // Save adhan sound
    if (_selectedSoundKey != null) {
      await adhan.selectSound(_selectedSoundKey!);
    }

    // Save prayer settings
    await ts.setMethod(_method);
    await ts.setMadhab(_madhab);
    if (_fajrAngle != null) {
      await ts.setFajrAngle(_fajrAngle);
    }
    if (_ishaAngle != null) {
      await ts.setIshaAngle(_ishaAngle, mode: _ishaMode);
    }

    // Save display settings
    await ts.setShowHijri(_showHijri);
    await ts.setUse24h(_use24h);

    // Mark location setup as done & clear the resume pointer
    await loc.markSetupDone();
    final stepPrefs = await SharedPreferences.getInstance();
    await stepPrefs.remove(_kStepKey);

    // Save current city as baseline for travel detection
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('loc_last_city', loc.cityName);

    // Trigger prayer times fetch with final settings
    await ts.loadTimes();

    widget.onComplete();
  }

  // ─────────────────── BUILD ───────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: nightBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // Progress dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_totalSteps, (i) => Container(
                  width: i == _step ? 24 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == _step ? gold : nightTextDim.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                )),
              ),
              const SizedBox(height: 32),
              // Content
              Expanded(child: _buildStep()),
              // Permission steps (8, 9) carry their own buttons via the gated
              // view, so hide the generic Next button there.
              if (_step != 8 && _step != 9) ...[
                const SizedBox(height: 16),
                _buildNextButton(),
                const SizedBox(height: 24),
              ] else
                const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0: return _scrollableStep(_buildLanguage());
      case 1: return _scrollableStep(_buildWelcome());
      case 2: return _scrollableStep(_buildFeatures());
      case 3: return _buildAdhanSounds();
      case 4: return _buildLocation();
      case 5: return _buildPrayerSettings();
      case 6: return _scrollableStep(_buildDisplaySettings());
      case 7: return _buildNotifications();
      case 8: return _buildOverlayPermission();
      default: return const SizedBox();
    }
  }

  /// Wraps a fixed-height step in a scroll view so it never overflows on small
  /// screens while still filling (and centering within) larger ones.
  Widget _scrollableStep(Widget child) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(child: child),
          ),
        ),
      );

  Widget _buildNextButton() {
    return GestureDetector(
      onTap: _next,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: gold.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: gold.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Text(
          _step == _totalSteps - 1 ? '✨ ابدأ' : 'التالي ←',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: gold),
        ),
      ),
    );
  }

  // ═══════════ STEP 0: LANGUAGE ═══════════
  Widget _buildLanguage() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(l10n.t('onboarding_lang_title'), style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: nightText)),
        const SizedBox(height: 6),
        Text(l10n.t('onboarding_lang_sub'), style: GoogleFonts.inter(fontSize: 13, color: nightText2)),
        const SizedBox(height: 36),
        for (final code in l10n.supportedLocales)
          GestureDetector(
            onTap: () { setState(() => _lang = code); l10n.setLocale(code); },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _lang == code ? gold.withValues(alpha: 0.12) : nightCardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _lang == code ? gold.withValues(alpha: 0.5) : nightBorder, width: _lang == code ? 2 : 1),
              ),
              child: Row(children: [
                Text(_flagFor(code), style: const TextStyle(fontSize: 30)),
                const SizedBox(width: 16),
                Expanded(child: Text(l10n.localeName(code), style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: nightText))),
                if (_lang == code) const Icon(Icons.check_circle_rounded, color: gold, size: 28),
              ]),
            ),
          ),
      ],
    );
  }

  String _flagFor(String code) {
    switch (code) {
      case 'ar': return '🇸🇦';
      case 'en': return '🇬🇧';
      case 'fa': return '🇮🇷';
      case 'ku': return '☀️';
      case 'de': return '🇩🇪';
      default: return '🌐';
    }
  }

  // ═══════════ STEP 1: WELCOME ═══════════
  Widget _buildWelcome() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 90, height: 90,
          decoration: BoxDecoration(color: gold.withValues(alpha: 0.10), shape: BoxShape.circle,
            border: Border.all(color: gold.withValues(alpha: 0.25), width: 1.5)),
          child: const Icon(Icons.mosque_rounded, size: 44, color: gold),
        ),
        const SizedBox(height: 32),
        Text(l10n.t('app_name'), style: GoogleFonts.inter(fontSize: 36, fontWeight: FontWeight.w200, color: nightText, letterSpacing: 6)),
        const SizedBox(height: 16),
        Text(l10n.t('app_tagline'), style: GoogleFonts.inter(fontSize: 13, color: gold.withValues(alpha: 0.7), letterSpacing: 3)),
        const SizedBox(height: 32),
        Text(l10n.t('onboarding_welcome'), textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 15, height: 1.7, color: nightText2)),
      ],
    );
  }

  // ═══════════ STEP 2: FEATURES ═══════════
  Widget _buildFeatures() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('ما يميز ${l10n.t('app_name')}', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: nightText)),
        const SizedBox(height: 36),
        _f(Icons.access_time_rounded, 'أوقات صلاة دقيقة', 'حساب الأوقات حسب موقعك و هيئتك المختارة'),
        _f(Icons.explore_rounded, 'بوصلة القبلة', 'تحديد اتجاه القبلة بدقة باستخدام حساسات الهاتف'),
        _f(Icons.volume_up_rounded, 'أصوات الأذان', 'اختيار صوت المؤذن المفضل لديك'),
        _f(Icons.notifications_active_rounded, 'إشعارات ذكية', 'تنبيهات عند دخول كل وقت صلاة'),
      ],
    );
  }

  Widget _f(IconData icon, String title, String sub) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: gold.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 22, color: gold)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: nightText)),
          const SizedBox(height: 3),
          Text(sub, style: GoogleFonts.inter(fontSize: 12, color: nightText2, height: 1.3)),
        ])),
      ],
    ),
  );

  // ═══════════ STEP 3: ADHAN SOUNDS ═══════════
  Widget _buildAdhanSounds() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('اختر صوت الأذان', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: nightText)),
        const SizedBox(height: 6),
        Text('سيتم تعيينه كصوت افتراضي للأذان', style: GoogleFonts.inter(fontSize: 13, color: nightText2)),
        const SizedBox(height: 20),
        // Pick a custom sound from the device
        GestureDetector(
          onTap: () async {
            final ok = await adhan.pickCustomFromDevice();
            if (!mounted) return;
            if (ok) {
              setState(() {
                _sounds = adhan.sounds;
                _selectedSoundKey = adhan.selectedKey;
              });
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: gold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: gold.withValues(alpha: 0.4), width: 1.2),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: gold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.library_music_rounded, size: 20, color: gold),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('اختر صوتًا من جهازك',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: nightText)),
                  Text('أي ملف صوتي من هاتفك',
                      style: GoogleFonts.inter(fontSize: 11, color: nightTextDim)),
                ]),
              ),
              const Icon(Icons.add_circle_outline_rounded, size: 22, color: gold),
            ]),
          ),
        ),
        if (_soundsLoading)
          const Expanded(child: Center(child: CircularProgressIndicator(color: gold)))
        else
          Expanded(
            child: ListView.builder(
              itemCount: _sounds.length,
              itemBuilder: (_, i) {
                final s = _sounds[i];
                final sel = s.key == _selectedSoundKey;
                return GestureDetector(
                  onTap: () => setState(() => _selectedSoundKey = s.key),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: sel ? gold.withValues(alpha: 0.12) : nightCardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: sel ? gold.withValues(alpha: 0.5) : nightBorder, width: sel ? 1.5 : 1),
                    ),
                    child: Row(children: [
                      GestureDetector(
                        onTap: () {
                          final isPlaying = _onboardPlayingKey == s.key;
                          if (isPlaying) {
                            adhan.stop();
                            setState(() => _onboardPlayingKey = null);
                          } else {
                            adhan.play(key: s.key);
                            setState(() => _onboardPlayingKey = s.key);
                          }
                        },
                        child: Container(padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _onboardPlayingKey == s.key
                                ? Colors.redAccent.withValues(alpha: 0.15)
                                : gold.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12)),
                          child: Icon(
                            _onboardPlayingKey == s.key ? Icons.stop_rounded : Icons.play_arrow_rounded,
                            size: 20,
                            color: _onboardPlayingKey == s.key ? Colors.redAccent : gold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.nameAr, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: sel ? nightText : nightText2)),
                        Text(s.nameEn, style: GoogleFonts.inter(fontSize: 11, color: nightTextDim)),
                      ])),
                      if (sel) const Icon(Icons.check_circle_rounded, size: 20, color: gold),
                    ]),
                  ),
                );
              },
            ),
          ),
        Text('يمكنك تغيير الصوت لاحقاً من إعدادات الصلاة', style: GoogleFonts.inter(fontSize: 11, color: nightTextDim)),
        const SizedBox(height: 12),
      ],
    );
  }

  // ═══════════ STEP 3: LOCATION ═══════════
  Widget _buildLocation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('تحديد موقعك', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: nightText)),
        const SizedBox(height: 6),
        Text('نحتاج موقعك لحساب أوقات الصلاة بدقة', style: GoogleFonts.inter(fontSize: 13, color: nightText2)),
        const SizedBox(height: 20),
        // GPS button (shows location info when detected)
        GestureDetector(
          onTap: _detectingGps ? null : _detectLocation,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _locationDetected ? gold.withValues(alpha: 0.15) : (_detectingGps ? gold.withValues(alpha: 0.08) : gold.withValues(alpha: 0.12)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _locationDetected ? gold : gold.withValues(alpha: 0.4), width: _locationDetected ? 2 : 1.5),
            ),
            child: Row(children: [
              _detectingGps
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: gold))
                  : Icon(_locationDetected ? Icons.check_circle_rounded : Icons.my_location_rounded, size: 22, color: gold),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_detectingGps ? 'جاري التحديد...' : _locationDetected ? '✓ تم تحديد الموقع' : 'تحديد موقعي تلقائياً (GPS)',
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: gold)),
                if (_locationDetected)
                  Text(loc.compactName, style: GoogleFonts.inter(fontSize: 12, color: nightText2)),
              ])),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        // Manual search
        Text('أو ابحث عن مدينتك:', style: GoogleFonts.inter(fontSize: 13, color: nightText2)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: nightCardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: nightBorder)),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onCitySearch,
            style: GoogleFonts.inter(fontSize: 14, color: nightText),
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              hintText: 'اكتب اسم المدينة...',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: nightTextDim),
              hintTextDirection: TextDirection.rtl,
              prefixIcon: const Icon(Icons.search_rounded, color: gold),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Hierarchical city picker button
        GestureDetector(
          onTap: () async {
            final ok = await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => CityPickerSheet(loc: loc, isNight: true),
            );
            if (ok == true && mounted) setState(() => _locationDetected = true);
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: gold.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.public_rounded, size: 20, color: gold),
              const SizedBox(width: 12),
              Expanded(child: Text('أو الاختيار من قائمة الدول والمدن',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: gold))),
              const Icon(Icons.chevron_left_rounded, size: 16, color: gold),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _searchResults.isNotEmpty
              ? ListView.builder(
                  itemCount: _searchResults.length,
                  itemBuilder: (_, i) {
                    final r = _searchResults[i];
                    return GestureDetector(
                      onTap: () => _selectCity(r),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(color: nightCardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: nightBorder)),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.name, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: nightText)),
                            if (r.displayName != r.name)
                              Text(r.displayName, maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(fontSize: 11, color: nightTextDim)),
                          ])),
                          const Icon(Icons.chevron_left_rounded, size: 16, color: nightTextDim),
                        ]),
                      ),
                    );
                  },
                )
              : _searchCtrl.text.isNotEmpty
                  ? Center(child: Text('لا توجد نتائج', style: GoogleFonts.inter(color: nightTextDim)))
                  : ListView(
                      children: CityData.popular.map((c) => GestureDetector(
                        onTap: () => _selectPopularCity(c),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          child: Row(children: [
                            Expanded(child: Text(c.name, style: GoogleFonts.inter(fontSize: 14, color: nightText2))),
                            const Icon(Icons.chevron_left_rounded, size: 16, color: nightTextDim),
                          ]),
                        ),
                      )).toList(),
                    ),
        ),
      ],
    );
  }

  Future<void> _detectLocation() async {
    setState(() => _detectingGps = true);
    final ok = await loc.detectGps();
    if (mounted) {
      setState(() {
        _detectingGps = false;
        if (ok) {
          _locationDetected = true;
        }
      });
      if (ok) {
        // Wait a moment so the user sees the confirmation, then auto-advance
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) _next();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('تعذر تحديد الموقع، اختر مدينتك يدوياً'),
          backgroundColor: gold.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  void _onCitySearch(String q) {
    // Debounced search would be ideal, but for simplicity do direct
    if (q.trim().length < 2) { setState(() => _searchResults = []); return; }
    Future.delayed(const Duration(milliseconds: 400), () async {
      if (!mounted || q != _searchCtrl.text) return;
      final results = await loc.searchCities(q.trim());
      if (mounted && q == _searchCtrl.text) {
        setState(() => _searchResults = results);
      }
    });
  }

  Future<void> _selectCity(SearchResult r) async {
    await loc.setManualLocation(lat: r.lat, lng: r.lng, city: r.name, state: r.state ?? '', country: r.country ?? '');
    if (mounted) {
      setState(() => _locationDetected = true);
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) _next();
    }
  }

  Future<void> _selectPopularCity(CityData c) async {
    await loc.setManualLocation(lat: c.lat, lng: c.lng, city: c.name);
    if (mounted) {
      setState(() => _locationDetected = true);
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) _next();
    }
  }

  // ═══════════ STEP 4: PRAYER SETTINGS ═══════════
  Widget _buildPrayerSettings() {
    // Auto-select method based on location
    if (_step == 4 && _method == 12 && loc.isInEurope) {
      // already default French
    }

    final methods = AlAdhanApiService.calculationMethods.entries.toList();
    final methodName = AlAdhanApiService.calculationMethods[_method] ?? 'غير معروف';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('إعدادات الحساب', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: nightText)),
          const SizedBox(height: 20),
          // Method dropdown
          _settingCard(
            icon: Icons.account_balance_rounded,
            title: 'هيئة الحساب',
            subtitle: methodName,
            onTap: () => _showMethodPicker(methods),
          ),
          // Madhab
          _settingCard(
            icon: Icons.school_rounded,
            title: 'المذهب الفقهي',
            subtitle: _madhab == Madhab.hanafi ? 'أهل الرأي' : 'أهل الحديث',
            onTap: _showMadhabPicker,
          ),
          // Fajr angle
          _settingCard(
            icon: Icons.wb_twilight_rounded,
            title: 'زاوية الفجر',
            subtitle: _fajrAngle != null ? '${_fajrAngle!.toStringAsFixed(1)}°' : 'تلقائي',
            onTap: () => _showAnglePicker(true),
          ),
          // Isha angle
          _settingCard(
            icon: Icons.nights_stay_rounded,
            title: 'زاوية العشاء',
            subtitle: _ishaAngle != null
                ? (_ishaMode == 'minutes' ? '${_ishaAngle!.toInt()} دقيقة' : '${_ishaAngle!.toStringAsFixed(1)}°')
                : 'تلقائي',
            onTap: () => _showAnglePicker(false),
          ),
        ],
      ),
    );
  }

  Widget _settingCard({required IconData icon, required String title, required String subtitle, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: nightCardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: nightBorder)),
        child: Row(children: [
          Icon(icon, size: 20, color: gold),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: nightText)),
            const SizedBox(height: 2),
            Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: nightText2)),
          ])),
          const Icon(Icons.chevron_left_rounded, size: 18, color: nightTextDim),
        ]),
      ),
    );
  }

  void _showMethodPicker(List<MapEntry<int, String>> methods) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: nightBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6, minChildSize: 0.4, maxChildSize: 0.85, expand: false,
        builder: (ctx, sc) => Column(children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: nightTextDim, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text('هيئة الحساب', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: nightText))),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              controller: sc, padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
              itemCount: methods.length,
              itemBuilder: (_, i) {
                final e = methods[i]; final sel = e.key == _method;
                return GestureDetector(
                  onTap: () { Navigator.pop(context); setState(() => _method = e.key); },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: sel ? gold.withValues(alpha: 0.12) : nightCardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sel ? gold.withValues(alpha: 0.5) : nightBorder, width: sel ? 1.5 : 1),
                    ),
                    child: Row(children: [
                      Expanded(child: Text(e.value, style: GoogleFonts.inter(fontSize: 14, color: sel ? nightText : nightText2))),
                      if (sel) const Icon(Icons.check_circle_rounded, size: 20, color: gold),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _showMadhabPicker() {
    showModalBottomSheet(
      context: context, useSafeArea: true, backgroundColor: nightBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Container(padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).viewPadding.bottom), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(color: nightTextDim, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Text('المذهب الفقهي', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: nightText)),
        const SizedBox(height: 16),
        _madOpt('أهل الحديث', 'العصر حين يصير ظل الشيء مثله', _madhab == Madhab.shafii,
            () { Navigator.pop(context); setState(() => _madhab = Madhab.shafii); }),
        const SizedBox(height: 8),
        _madOpt('أهل الرأي', 'العصر حين يصير ظل الشيء مثليه', _madhab == Madhab.hanafi,
            () { Navigator.pop(context); setState(() => _madhab = Madhab.hanafi); }),
        const SizedBox(height: 16),
      ])),
    );
  }

  Widget _madOpt(String title, String sub, bool sel, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(
      color: sel ? gold.withValues(alpha: 0.12) : nightCardBg, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: sel ? gold.withValues(alpha: 0.5) : nightBorder, width: sel ? 1.5 : 1)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: sel ? nightText : nightText2)),
          const SizedBox(height: 2), Text(sub, style: GoogleFonts.inter(fontSize: 12, color: nightTextDim)),
        ])),
        if (sel) const Icon(Icons.check_circle_rounded, size: 20, color: gold),
      ])),
  );

  void _showAnglePicker(bool isFajr) {
    final current = isFajr ? _fajrAngle : _ishaAngle;
    showModalBottomSheet(
      context: context, useSafeArea: true, backgroundColor: nightBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => Container(padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).viewPadding.bottom), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: nightTextDim, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text(isFajr ? 'زاوية الفجر' : 'زاوية العشاء', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: nightText)),
          const SizedBox(height: 16),
          // Auto option
          GestureDetector(
            onTap: () { Navigator.pop(ctx); setState(() => isFajr ? _fajrAngle = null : _ishaAngle = null); },
            child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(
              color: current == null ? gold.withValues(alpha: 0.12) : nightCardBg, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: current == null ? gold.withValues(alpha: 0.5) : nightBorder)),
              child: Row(children: [
                Expanded(child: Text('تلقائي', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: current == null ? nightText : nightText2))),
                if (current == null) const Icon(Icons.check_circle_rounded, size: 20, color: gold),
              ])),
          ),
          if (current != null) ...[
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              GestureDetector(
                onTap: () => setLocal(() => isFajr ? _fajrAngle = (_fajrAngle! - 0.5).clamp(12.0, 20.0) : _ishaAngle = (_ishaAngle! - 0.5).clamp(12.0, 20.0)),
                child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: nightCardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: nightBorder)),
                  child: const Icon(Icons.remove_rounded, size: 24, color: gold)),
              ),
              const SizedBox(width: 24),
              Text('${current.toStringAsFixed(1)}°', style: GoogleFonts.lexend(fontSize: 28, fontWeight: FontWeight.w600, color: gold)),
              const SizedBox(width: 24),
              GestureDetector(
                onTap: () => setLocal(() => isFajr ? _fajrAngle = (_fajrAngle! + 0.5).clamp(12.0, 20.0) : _ishaAngle = (_ishaAngle! + 0.5).clamp(12.0, 20.0)),
                child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: nightCardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: nightBorder)),
                  child: const Icon(Icons.add_rounded, size: 24, color: gold)),
              ),
            ]),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
        ])),
      ),
    );
  }

  // ═══════════ STEP 5: DISPLAY SETTINGS ═══════════
  Widget _buildDisplaySettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('إعدادات العرض', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: nightText)),
        const SizedBox(height: 20),
        // Hijri toggle
        GestureDetector(
          onTap: () => setState(() => _showHijri = !_showHijri),
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _showHijri ? gold.withValues(alpha: 0.10) : nightCardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _showHijri ? gold.withValues(alpha: 0.4) : nightBorder, width: _showHijri ? 1.5 : 1),
            ),
            child: Row(children: [
              const Icon(Icons.calendar_month_rounded, size: 22, color: gold),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('التقويم الهجري', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: nightText)),
                const SizedBox(height: 2),
                Text(_showHijri ? 'يظهر في الشاشة الرئيسية' : 'مخفي', style: GoogleFonts.inter(fontSize: 12, color: nightText2)),
              ])),
              _toggle(_showHijri),
            ]),
          ),
        ),
        // 24h toggle
        GestureDetector(
          onTap: () => setState(() => _use24h = !_use24h),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _use24h ? gold.withValues(alpha: 0.10) : nightCardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _use24h ? gold.withValues(alpha: 0.4) : nightBorder, width: _use24h ? 1.5 : 1),
            ),
            child: Row(children: [
              const Icon(Icons.schedule_rounded, size: 22, color: gold),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('نظام 24 ساعة', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: nightText)),
                const SizedBox(height: 2),
                Text(_use24h ? '16:30' : '4:30 م', style: GoogleFonts.inter(fontSize: 12, color: nightText2)),
              ])),
              _toggle(_use24h),
            ]),
          ),
        ),
      ],
    );
  }

  // ═══════════ STEP 6: NOTIFICATIONS ═══════════
  Widget _buildNotifications() {
    // Gated: can't advance until granted, or skipped after seeing manual steps.
    return PermissionRequestView(
      permission: AppPermission.notification,
      onGranted: _next,
      onSkip: _next,
    );
  }

  // ═══════════ STEP 7: OVERLAY PERMISSION ═══════════
  Widget _buildOverlayPermission() {
    return PermissionRequestView(
      permission: AppPermission.overlay,
      onGranted: _next,
      onSkip: _next,
    );
  }

  Widget _toggle(bool v) => Container(
    width: 44, height: 26,
    decoration: BoxDecoration(color: v ? gold : nightTextDim.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(13)),
    child: Stack(children: [
      AnimatedPositioned(duration: const Duration(milliseconds: 200), left: v ? 20 : 2, top: 2,
        child: Container(width: 22, height: 22, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white))),
    ]),
  );
}
