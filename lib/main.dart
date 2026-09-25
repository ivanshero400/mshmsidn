import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'pages/settings_page.dart';
import 'pages/fajr_alarm_settings_page.dart';
import 'pages/fajr_alarm_active_page.dart';
import 'pages/qibla_page.dart';
import 'pages/learn_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/permission_gate.dart';
import 'pages/adhan_alarm_page.dart';
import 'pages/adhkar_display_page.dart';
import 'services/vibe_service.dart';
import 'services/app_theme_colors.dart';

import 'services/prayer_times_service.dart';
import 'services/kids_service.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'services/adhan_sound_service.dart';
import 'services/widget_update_service.dart';
import 'services/adhan_alarm_service.dart';
import 'services/l10n_service.dart';
import 'pages/splash_screen.dart';

// ============================================================
// Enums & Theme Data
// ============================================================
enum AppThemeMode { auto, light, dark }

class AppTheme {
  // Night: deep indigo (not flat black) with vivid gold — alive, not gloomy.
  static const Color nightBg = Color(0xFF0B1026);
  static const Color nightSurface = Color(0xFF131A36);
  static const Color nightCardBg = Color(0xFF161E3C);
  static const Color nightTextPrimary = Color(0xFFF4F1E8);
  static const Color nightTextSecondary = Color(0xFFA9B2D0);
  static const Color nightTextDim = Color(0xFF5A6285);
  static const Color nightBorder = Color(0xFF28315A);
  static const Color nightActiveBg = Color(0xFF3D3425);
  static const Color nightActiveText = Color(0xFFF5EDDF);
  static const Color nightGlow = Color(0xFFF0BC5E);
  static const Color nightActiveBorder = Color(
    0xFF5BA8F5,
  ); // sky blue for night

  // Day: warm ivory with saturated amber.
  static const Color dayBg = Color(0xFFFDF8EE);
  static const Color daySurface = Color(0xFFF9F0DC);
  static const Color dayCardBg = Color(0xFFFFFEFA);
  static const Color dayTextPrimary = Color(0xFF2E2618);
  static const Color dayTextSecondary = Color(0xFF7A6A4F);
  static const Color dayTextDim = Color(0xFFC9BCA4);
  static const Color dayBorder = Color(0xFFE5D5B4);
  static const Color dayActiveBg = Color(0xFFE3A93F);
  static const Color dayActiveText = Color(0xFFFFFDF7);
  static const Color dayGlow = Color(0xFFECB54E);
  static const Color dayActiveBorder = Color(0xFFD88A2E); // warm amber for day

  /// Per-prayer accent identity (icon + highlights).
  static const Map<String, Color> prayerAccent = {
    'FAJR': Color(0xFF7B9EF0), // dawn blue
    'SUNRISE': Color(0xFFF0B860), // sunrise amber
    'DHUHR': Color(0xFFE8C547), // noon yellow
    'ASR': Color(0xFFE8975A), // afternoon orange
    'MAGHRIB': Color(0xFFE0708C), // sunset rose
    'ISHA': Color(0xFF9B8CE8), // night violet
  };

  /// Per-prayer icon.
  static const Map<String, IconData> prayerIcon = {
    'FAJR': Icons.wb_twilight_rounded,
    'SUNRISE': Icons.wb_sunny_outlined,
    'DHUHR': Icons.light_mode_rounded,
    'ASR': Icons.brightness_6_rounded,
    'MAGHRIB': Icons.brightness_4_rounded,
    'ISHA': Icons.nights_stay_rounded,
  };

  /// Signature gradient that gives each home style its own colour identity.
  static const Map<HomeStyle, List<Color>> styleGradient = {
    HomeStyle.circle: [Color(0xFFECB54E), Color(0xFFE0708C)],
    HomeStyle.rectangle: [Color(0xFF7B9EF0), Color(0xFF9B8CE8)],
    HomeStyle.minimal: [Color(0xFF8A8F98), Color(0xFFB8BCC4)],
    HomeStyle.focus: [Color(0xFFE8975A), Color(0xFFE0708C)],
    HomeStyle.timeline: [Color(0xFF58B97D), Color(0xFF7B9EF0)],
  };
}

// ============================================================
// Root App
// ============================================================
/// Global navigator key so native notification taps can deep-link to pages.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  await initializeDateFormatting('en');
  runApp(const AuraAdhanApp());
}

class AuraAdhanApp extends StatefulWidget {
  const AuraAdhanApp({super.key});

  @override
  State<AuraAdhanApp> createState() => _AuraAdhanAppState();
}

class _AuraAdhanAppState extends State<AuraAdhanApp>
    with WidgetsBindingObserver {
  static const _routeChannel = MethodChannel('azan.device_activity');
  final PrayerTimesService _timesService = PrayerTimesService();
  final AdhanSoundService _adhanService = AdhanSoundService();
  final L10nService l10n = L10nService();
  bool _ready = false;
  bool _needsSetup = true;
  bool _needsPerms = false; // any required permission still missing
  bool _langChanged = false; // force rebuild on locale switch

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A notification tap may have relaunched/resumed us with a deep link.
    if (state == AppLifecycleState.resumed) _checkPendingRoute();
  }

  /// Navigate to the route attached to the notification that opened the app
  /// (adhkar / surah al-Mulk / travel rules…), if any.
  Future<void> _checkPendingRoute() async {
    try {
      final route = await _routeChannel.invokeMethod<String>(
        'takePendingRoute',
      );
      if (route != null && route.isNotEmpty) {
        appNavigatorKey.currentState?.pushNamed(route);
      }
    } catch (_) {}
  }

  Future<void> _init() async {
    await l10n.load();
    // Trigger full rebuild on every language change
    l10n.addListener(() {
      if (mounted) setState(() => _langChanged = !_langChanged);
    });
    await _timesService.initialize();
    await NotificationService.init();
    if (!mounted) return;

    // Load and check if location setup is done
    await _timesService.locationService.load();
    if (!mounted) return;

    final setupDone = _timesService.locationService.setupDone;
    // For returning users, decide up front whether the permission gate is
    // needed (only shows permissions that are actually missing & not dismissed).
    final needsPerms = setupDone
        ? await PermissionGatePage.anyMissing()
        : false;
    if (!mounted) return;
    setState(() {
      _needsSetup = !setupDone;
      _needsPerms = needsPerms;
      _ready = true;
    });

    // Start background prayer checker immediately
    BackgroundPrayerService.start();

    // Notification taps inside Flutter (e.g. travel info) deep-link via the
    // global navigator.
    NotificationService.onTapRoute = (route) =>
        appNavigatorKey.currentState?.pushNamed(route);

    // Detect city changes → remind about travel prayer rules; tapping the
    // notification opens the full جمع وقصر lesson.
    _timesService.locationService.onCityChanged = () {
      final city = _timesService.locationService.cityName;
      NotificationService.showImmediate(
        '🧳 أحكام صلاة السفر',
        'يبدو أنك انتقلت إلى مدينة جديدة: $city.\n'
            'يجوز للمسافر قصر الرباعية والجمع بين الصلاتين — اضغط لقراءة الأحكام كاملة.',
        payload: '/learn/travel',
      );
    };

    // Handle a cold-start deep link from a native notification.
    _checkPendingRoute();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timesService.locationService.dispose();
    _timesService.dispose();
    _adhanService.dispose();
    super.dispose();
  }

  /// Called after onboarding finishes — show the permission gate for anything
  /// still missing, otherwise go straight home.
  Future<void> _checkPermissions() async {
    final need = await PermissionGatePage.anyMissing();
    if (mounted) setState(() => _needsPerms = need);
  }

  /// Map our locale codes to Flutter's supported ones (ku/fa/de have no
  /// Material localizations, so we pass ar/en for system widgets).
  Locale _systemLocaleFor(String code) {
    if (code == 'ku' || code == 'fa' || code == 'de') return const Locale('en');
    return Locale(code);
  }

  @override
  Widget build(BuildContext context) {
    // Check if launched as alarm activity from platform
    final defaultRoute =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;

    // Use a Flutter-supported locale for Material widgets while our
    // own L10nService handles all app text in the chosen language.
    final systemLocale = _systemLocaleFor(l10n.locale);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'الفجر',
      navigatorKey: appNavigatorKey,
      locale: systemLocale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      initialRoute: defaultRoute != '/' ? defaultRoute : null,
      routes: {
        '/adhan-alarm': (context) => const AdhanAlarmPage(),
        '/fajr-alarm-active': (context) => const FajrAlarmActivePage(),
        '/adhkar-display': (context) => const AdhkarDisplayPage(),

        '/learn': (context) => const LearnPage(),
        '/learn/travel': (context) => const LearnTopicPage(topicId: 'travel'),
        '/learn/adhkar': (context) => const LearnTopicPage(topicId: 'adhkar'),
        '/learn/mulk': (context) => const MulkPage(),
      },
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppTheme.dayBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTheme.dayActiveBg,
          brightness: Brightness.light,
          surface: AppTheme.daySurface,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppTheme.nightBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTheme.nightGlow,
          brightness: Brightness.dark,
          surface: AppTheme.nightSurface,
        ),
      ),
      themeMode: ThemeMode.dark,
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (!_ready) {
      return const SplashScreen();
    }

    if (_needsSetup) {
      return OnboardingPage(
        timesService: _timesService,
        adhanService: _adhanService,
        l10n: l10n,
        onComplete: () {
          setState(() => _needsSetup = false);
          _timesService.loadTimes();
          _checkPermissions();
        },
      );
    }

    if (_needsPerms) {
      return PermissionGatePage(
        onAllDone: () {
          if (mounted) setState(() => _needsPerms = false);
        },
      );
    }

    return PrayerHomeScreen(timesService: _timesService, l10n: l10n);
  }
}

// ============================================================
// Main Screen
// ============================================================
class PrayerHomeScreen extends StatefulWidget {
  final PrayerTimesService timesService;
  final L10nService l10n;
  const PrayerHomeScreen({
    super.key,
    required this.timesService,
    required this.l10n,
  });
  @override
  State<PrayerHomeScreen> createState() => _PrayerHomeScreenState();
}

class _PrayerHomeScreenState extends State<PrayerHomeScreen>
    with TickerProviderStateMixin {
  late DateTime _now;
  late Timer _timer;
  AppThemeMode _themeMode = AppThemeMode.auto;
  AppThemeId _themeId = AppThemeId.base; // selected colour palette

  // Floating menu
  final GlobalKey _menuKey = GlobalKey();
  late AnimationController _menuCtrl;
  late Animation<double> _overlayFade;
  late Animation<double> _menuScale;
  bool _menuOpen = false;
  Offset _menuBtnPos = Offset.zero;
  Size _menuBtnSize = Size.zero;

  // Prayer times service
  PrayerTimesService get _timesService => widget.timesService;

  // Kids-mode tracking (stars / streak / prayed-today), persisted locally.
  final KidsService _kidsService = KidsService();

  // Expanded card state
  int? _expandedIndex;
  late AnimationController _cardCtrl;
  late Animation<double> _cardOverlayFade;
  late Animation<double> _cardScale;

  // Notification toggles (persisted; muted prayers are skipped natively)
  final Set<String> _mutedPrayers = {};
  static const _kMutedPrayers = 'muted_prayers_csv';

  Future<void> _loadMutedPrayers() async {
    final prefs = await SharedPreferences.getInstance();
    final csv = prefs.getString(_kMutedPrayers) ?? '';
    if (csv.isEmpty) return;
    if (mounted) {
      setState(() {
        _mutedPrayers
          ..clear()
          ..addAll(csv.split(',').where((e) => e.isNotEmpty));
      });
    }
  }

  Future<void> _saveMutedPrayers() async {
    final prefs = await SharedPreferences.getInstance();
    // Plain CSV (not setStringList) so the native scheduler can read it.
    await prefs.setString(_kMutedPrayers, _mutedPrayers.join(','));
    // Re-arm native alarms so muted prayers stop firing immediately.
    AdhanAlarmService.schedulePrayerAlarms(const []);
  }

  List<Map<String, String>> get _prayerTimes => _timesService.times;

  String _displayName(String key) {
    // Use l10n service for prayer names
    switch (key) {
      case 'FAJR':
        return widget.l10n.t('prayer_fajr');
      case 'SUNRISE':
        return widget.l10n.t('prayer_sunrise');
      case 'DHUHR':
        return widget.l10n.t('prayer_dhuhr');
      case 'ASR':
        return widget.l10n.t('prayer_asr');
      case 'MAGHRIB':
        return widget.l10n.t('prayer_maghrib');
      case 'ISHA':
        return widget.l10n.t('prayer_isha');
      default:
        return key;
    }
  }

  int _parseTimeMin(String t) {
    final p = t.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  AppPalette get _p => paletteFor(_themeId);

  bool get _isNight {
    if (_themeMode == AppThemeMode.light) return false;
    if (_themeMode == AppThemeMode.dark) return true;
    return _timesService.isNightNow();
  }

  Color get bg => _isNight ? _p.bg : (_p.dayBg ?? _p.bg);
  Color get cardBg => _isNight ? _p.cardBg : (_p.dayCardBg ?? _p.cardBg);
  Color get text1 =>
      _isNight ? _p.textPrimary : (_p.dayTextPrimary ?? _p.textPrimary);
  Color get text2 =>
      _isNight ? _p.textSecondary : (_p.dayTextSecondary ?? _p.textSecondary);
  Color get textDim => _isNight ? _p.textDim : (_p.dayTextDim ?? _p.textDim);
  Color get border => _isNight ? _p.border : (_p.dayBorder ?? _p.border);
  Color get glowColor => _isNight ? _p.glow : (_p.dayGlow ?? _p.glow);

  HomeStyle get _homeStyle => _timesService.homeStyle;
  List<Color> get _styleColors =>
      AppTheme.styleGradient[_homeStyle] ?? [glowColor, glowColor];

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    // Restore the saved theme preference (auto / light / dark)
    SharedPreferences.getInstance().then((p) {
      final saved = p.getInt('theme_mode');
      if (saved != null &&
          saved >= 0 &&
          saved < AppThemeMode.values.length &&
          mounted) {
        setState(() => _themeMode = AppThemeMode.values[saved]);
      }
      // Restore colour palette
      final savedId = p.getInt('theme_id');
      if (savedId != null &&
          savedId >= 0 &&
          savedId < AppThemeId.values.length &&
          mounted) {
        setState(() => _themeId = AppThemeId.values[savedId]);
      }
    });
    // Restore per-prayer mute preferences
    _loadMutedPrayers();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });

    _menuCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _overlayFade = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _menuCtrl, curve: Curves.easeOut));
    _menuScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _menuCtrl,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    _cardCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _cardOverlayFade = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOut));
    _cardScale = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: _cardCtrl,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    _timesService.addListener(_onTimesChanged);
    _kidsService.addListener(_onKidsChanged);
    _kidsService.load();
    // Service already initialized by AuraAdhanApp
    if (_timesService.times.length <= 1 ||
        _timesService.times[0]['time'] ==
            PrayerTimesService.defaultTimes[0]['time']) {
      _timesService.loadTimes();
    }
    // Schedule alarms once after first frame (listener may not fire if already loaded)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleNotificationsIfNeeded();
    });
  }

  void _onTimesChanged() {
    if (mounted) {
      setState(() {});
      // Schedule notifications whenever times are updated
      _scheduleNotificationsIfNeeded();
    }
  }

  void _onKidsChanged() {
    if (mounted) setState(() {});
  }

  String _lastScheduledDate = '';
  String _lastWidgetMinute = '';
  final ScrollController _cardsCtrl = ScrollController();
  String _lastAutoScrollKey = '';

  void _scheduleNotificationsIfNeeded() {
    final times = _prayerTimes;
    if (times.length < 3) return;

    // Only schedule if we have real prayer times (not defaults)
    final firstTime = times[0]['time']!;
    if (firstTime == PrayerTimesService.defaultTimes[0]['time'] &&
        times.length <= 6) {
      // Check if API data has been loaded yet
      return;
    }

    // Always keep the native alarm schedule in sync with the latest times.
    // Idempotent + cheap, and the native side self-perpetuates in the
    // background, so this must run on every times change (incl. settings).
    AdhanAlarmService.schedulePrayerAlarms(times);

    // Heavier per-day notification setup: only once per calendar day.
    final today = '${_now.year}-${_now.month}-${_now.day}';
    if (_lastScheduledDate != today) {
      _lastScheduledDate = today;
      NotificationService.scheduleAll(times);
      // Schedule post-prayer check 15 min after Fajr
    }
  }

  int _findNextPrayerIndex() {
    for (int i = 0; i < _prayerTimes.length; i++) {
      if (_prayerTimes[i]['name'] == 'SUNRISE') continue;
      final parts = _prayerTimes[i]['time']!.split(':');
      final pt = DateTime(
        _now.year,
        _now.month,
        _now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
      if (pt.isAfter(_now)) return i;
    }
    return 0;
  }

  /// Returns a label like "الصلاة الحالية: العشاء" if the current time window
  /// is Isha and the next prayer has already rolled over to Fajr.
  /// Returns "الصلاة الحالية: الفجر" etc. for the prayer window we're in.
  String? _currentPrayerLabel(int nextIdx) {
    const skip = {'MIDNIGHT', 'LAST_THIRD'};
    final total = _prayerTimes.length;

    // Find the last real prayer before the next one
    for (int offset = 1; offset < total; offset++) {
      final idx = (nextIdx - offset + total) % total;
      final key = _prayerTimes[idx]['name'] ?? '';
      if (skip.contains(key)) continue;

      // Special case: between Sunrise and Duha (15 min after sunrise)
      if (key == 'SUNRISE') {
        final sunriseStr = _timesService.getTime('SUNRISE');
        if (sunriseStr != null) {
          final srMin = _parseTimeMin(sunriseStr);
          final nowMin = _now.hour * 60 + _now.minute;
          final duhaStartMin = (srMin + 15) % (24 * 60);
          // Normalise all around midnight
          final normNow = nowMin < srMin ? nowMin + 24 * 60 : nowMin;
          final normDuha = duhaStartMin < srMin
              ? duhaStartMin + 24 * 60
              : duhaStartMin;
          if (normNow < normDuha) {
            return widget.l10n.t('current_sunrise');
          }
        }
        return widget.l10n.t('current_duha');
      }

      if (key == 'DUHA') continue;

      final arName = _displayName(key);
      if (arName.isEmpty) continue;
      final prefix = widget.l10n.t('current_prayer');
      return '$prefix: $arName';
    }
    return null;
  }

  void _openCard(int index, String prayerName) {
    setState(() => _expandedIndex = index);
    _cardCtrl.forward();
  }

  void _closeCard() {
    _cardCtrl.reverse().then((_) {
      if (mounted) setState(() => _expandedIndex = null);
    });
  }

  void _toggleMute(String prayerName) {
    setState(() {
      _mutedPrayers.contains(prayerName)
          ? _mutedPrayers.remove(prayerName)
          : _mutedPrayers.add(prayerName);
    });
    _saveMutedPrayers();
  }

  @override
  void dispose() {
    _timer.cancel();
    _menuCtrl.dispose();
    _cardCtrl.dispose();
    _cardsCtrl.dispose();
    _timesService.removeListener(_onTimesChanged);
    _kidsService.removeListener(_onKidsChanged);
    super.dispose();
  }

  void _openMenu() {
    final RenderBox? box =
        _menuKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      _menuBtnPos = box.localToGlobal(Offset.zero);
      _menuBtnSize = box.size;
    }
    setState(() => _menuOpen = true);
    _menuCtrl.forward();
  }

  void _closeMenu() {
    _menuCtrl.reverse().then((_) {
      if (mounted) setState(() => _menuOpen = false);
    });
  }

  void _setTheme(AppThemeMode mode) {
    setState(() => _themeMode = mode);
    SharedPreferences.getInstance().then(
      (p) => p.setInt('theme_mode', mode.index),
    );
  }

  void _setThemeId(AppThemeId id) {
    setState(() => _themeId = id);
    SharedPreferences.getInstance().then((p) => p.setInt('theme_id', id.index));
  }

  String _buildDateString(Locale loc) {
    try {
      return DateFormat('EEEE، d MMMM', loc.languageCode).format(_now);
    } catch (_) {
      return DateFormat('EEEE، d MMMM', 'en').format(_now);
    }
  }

  // ========================================================== BUILD
  @override
  Widget build(BuildContext context) {
    final dateLocale = Locale(widget.l10n.locale);
    final dateStr = _buildDateString(dateLocale);
    final hijri = HijriDate.fromGregorian(_now);
    final hijriStr = hijri.format();
    final nextIdx = _findNextPrayerIndex();
    final nextKey = _prayerTimes[nextIdx]['name']!;
    final nextTime = _prayerTimes[nextIdx]['time']!;
    final nextTimeFormatted = _formatTime(nextTime);
    final countdown = _calculateCountdown(nextTime);

    // In the long gap between Isha and Fajr, the "next" prayer is Fajr
    // but the user is still in Isha time — clarify so it doesn't confuse.
    final String? currentPrayerLabel = _currentPrayerLabel(nextIdx);

    // ── Update home screen widget (minutes only, every 60s to save battery) ──
    final widgetCountdown = countdown.substring(0, 5); // HH:MM only
    if (_lastWidgetMinute != '${_now.hour}:${_now.minute}') {
      _lastWidgetMinute = '${_now.hour}:${_now.minute}';
      WidgetUpdateService.update(
        nextPrayer: _displayName(nextKey),
        remaining: widgetCountdown,
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: _isNight ? Brightness.light : Brightness.dark,
        statusBarBrightness: _isNight ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: bg,
        systemNavigationBarIconBrightness: _isNight
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Theme(
        data: ThemeData(
          useMaterial3: true,
          brightness: _isNight ? Brightness.dark : Brightness.light,
          scaffoldBackgroundColor: bg,
          colorScheme: ColorScheme.fromSeed(
            seedColor: glowColor,
            brightness: _isNight ? Brightness.dark : Brightness.light,
            surface: _isNight ? _p.surface : (_p.daySurface ?? _p.surface),
          ),
        ),
        child: Scaffold(
          backgroundColor: bg,
          body: Stack(
            children: [
              _buildBackgroundDecor(),
              _buildMain(
                dateStr,
                _displayName(nextKey),
                countdown,
                nextKey,
                hijriStr,
                nextTimeFormatted,
                currentPrayerLabel,
              ),
              _buildFloatingMenu(),
              _buildCardPopup(),
            ],
          ),
        ),
      ),
    );
  }

  // ========================================================== BACKGROUND DECORATION
  Widget _buildBackgroundDecor() {
    final Color decorColor = glowColor.withValues(
      alpha: _isNight ? 0.04 : 0.06,
    );
    final Color decorBorder = glowColor.withValues(
      alpha: _isNight ? 0.08 : 0.10,
    );
    return Stack(
      children: [
        // Top-right large square
        Positioned(
          top: -80,
          right: -60,
          child: Transform.rotate(
            angle: 0.3,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: decorColor,
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: decorBorder, width: 1.5),
              ),
            ),
          ),
        ),
        // Bottom-left large square
        Positioned(
          bottom: -40,
          left: -90,
          child: Transform.rotate(
            angle: -0.25,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                color: decorColor,
                borderRadius: BorderRadius.circular(48),
                border: Border.all(color: decorBorder, width: 1.5),
              ),
            ),
          ),
        ),
        // Small center-top accent square
        Positioned(
          top: 180,
          right: 50,
          child: Transform.rotate(
            angle: 0.55,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: decorBorder, width: 1),
              ),
            ),
          ),
        ),
        // Background circle behind countdown
        Positioned(
          top: 240,
          left: 40,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: decorColor,
              border: Border.all(color: decorBorder, width: 1),
            ),
          ),
        ),
        // Bottom-right small rotated square
        Positioned(
          bottom: 100,
          right: 20,
          child: Transform.rotate(
            angle: 0.7,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: decorBorder, width: 1),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ========================================================== MAIN CONTENT
  // Dispatches to the user-selected home layout. Kids mode overrides the
  // chosen style with a fixed, child-friendly screen.
  Widget _buildMain(
    String date,
    String nextPrayer,
    String countdown,
    String nextKey,
    String hijriStr,
    String nextTimeFormatted, [
    String? currentPrayerLabel,
  ]) {
    // Label row: current prayer + qibla button side by side
    Widget? buildLabelWithQibla(String? currentPrayerLabel) {
      if (currentPrayerLabel == null) return null;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: glowColor.withValues(alpha: _isNight ? 0.12 : 0.16),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: glowColor.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time_rounded, size: 14, color: glowColor),
                  const SizedBox(width: 7),
                  Text(
                    currentPrayerLabel,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: glowColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _qiblaNav,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: glowColor.withValues(alpha: _isNight ? 0.10 : 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.explore_rounded,
                  size: 18,
                  color: Color(0xFFD4A853),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final labelWidget = buildLabelWithQibla(currentPrayerLabel);

    if (_timesService.kidsMode) return _buildKidsHome(date, hijriStr);
    switch (_timesService.homeStyle) {
      case HomeStyle.circle:
        return _composeWithHero(
          date,
          hijriStr,
          _buildPrayerCards(nextKey),
          hero: _heroCircle(nextPrayer, countdown, nextKey, nextTimeFormatted),
          gap: 14,
          labelWidget: labelWidget,
        );
      case HomeStyle.rectangle:
        return _composeWithHero(
          date,
          hijriStr,
          _buildPrayerCards(nextKey),
          hero: _buildCountdownHero(
            nextPrayer,
            countdown,
            nextKey,
            nextTimeFormatted,
          ),
          gap: 12,
          labelWidget: labelWidget,
        );
      case HomeStyle.minimal:
        return _composeWithHero(
          date,
          hijriStr,
          _buildPrayerCards(nextKey),
          hero: _heroMinimal(nextPrayer, countdown, nextKey),
          gap: 10,
          labelWidget: labelWidget,
        );
      case HomeStyle.focus:
        return _composeFocus(
          date,
          hijriStr,
          nextPrayer,
          countdown,
          nextKey,
          nextTimeFormatted,
          labelWidget,
        );
      case HomeStyle.timeline:
        return _composeTimeline(
          date,
          hijriStr,
          nextPrayer,
          countdown,
          nextKey,
          labelWidget,
        );
    }
  }

  /// Shared scaffold for the hero-based styles (circle / rectangle / minimal):
  /// header + permission banner + a hero block + the scrolling prayer list.
  Widget _composeWithHero(
    String date,
    String hijriStr,
    List<Widget> prayerCards, {
    required Widget hero,
    double gap = 12,
    Widget? labelWidget,
  }) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildHeader(date, hijriStr),
            if (labelWidget != null) ...[
              const SizedBox(height: 8),
              labelWidget,
            ],
            const SizedBox(height: 8),
            hero,
            SizedBox(height: gap),
            Expanded(
              child: ListView(
                controller: _cardsCtrl,
                padding: const EdgeInsets.only(bottom: 12),
                children: prayerCards,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the vertical prayer-card list (Duha / 5 fard + sunrise / midnight)
  /// and schedules the once-per-prayer auto-scroll to the next prayer.
  List<Widget> _buildPrayerCards(String nextKey) {
    const fixedOrder = ['FAJR', 'SUNRISE', 'DHUHR', 'ASR', 'MAGHRIB', 'ISHA'];
    final nowMin = _now.hour * 60 + _now.minute;
    final prayerCards = <Widget>[];

    // Add Duha card after Fajr (before sunrise) if enabled
    if (_timesService.showDuha) {
      final duha = _timesService.calcDuha();
      if (duha != null && _timesService.isDuhaActive()) {
        final bestTime = duha['best']!;
        prayerCards.add(
          _buildPrayerCard(
            nameKey: 'DUHA',
            timeStr:
                '${_formatTime(duha['time']!)} → ${_formatTime(duha['end']!)}',
            idx: -1,
            isNext: false,
            customDisplay: 'الضحى',
            customSubtitle: 'أفضل وقت: ${_formatTime(bestTime)}',
            customIcon: Icons.wb_sunny_rounded,
          ),
        );
      }
    }

    for (final nameKey in fixedOrder) {
      final idx = _prayerTimes.indexWhere((p) => p['name'] == nameKey);
      final rawTime = idx != -1 ? _prayerTimes[idx]['time']! : '--:--';
      final timeStr = _formatTime(rawTime);
      final isNext = nameKey == nextKey;
      prayerCards.add(
        _buildPrayerCard(
          nameKey: nameKey,
          timeStr: timeStr,
          idx: idx,
          isNext: isNext,
        ),
      );
    }

    // Add Midnight/Last-third card after Isha if enabled
    if (_timesService.showMidnight) {
      final ishaTime = _timesService.getTime('ISHA') ?? '23:59';
      final fajrTime = _timesService.getTime('FAJR') ?? '05:00';
      final ishaMin = _parseTimeMin(ishaTime);
      final fajrMin = _parseTimeMin(fajrTime);
      final isAfterIsha = nowMin >= ishaMin || nowMin < fajrMin;

      if (isAfterIsha) {
        if (_timesService.isAfterMidnight()) {
          final lastThird = _timesService.calcLastThird();
          prayerCards.add(
            _buildPrayerCard(
              nameKey: 'LAST_THIRD',
              timeStr: lastThird ?? '--:--',
              idx: -1,
              isNext: false,
              customDisplay: 'الثلث الأخير من الليل',
              customSubtitle: 'وقت الاستغفار وقيام الليل',
              customIcon: Icons.nightlight_round_rounded,
            ),
          );
        } else {
          final midnight = _timesService.calcMidnight();
          prayerCards.add(
            _buildPrayerCard(
              nameKey: 'MIDNIGHT',
              timeStr: midnight ?? '--:--',
              idx: -1,
              isNext: false,
              customDisplay: 'نصف الليل',
              customSubtitle: 'منتصف الليل الشرعي',
              customIcon: Icons.bedtime_rounded,
            ),
          );
        }
      }
    }

    // Auto-scroll the cards list so the NEXT prayer is visible (e.g. Isha at
    // night) — once per prayer change, and the user can still scroll freely.
    final duhaShown =
        prayerCards.length > 1 &&
        _timesService.showDuha &&
        _timesService.calcDuha() != null &&
        _timesService.isDuhaActive();
    if (_lastAutoScrollKey != nextKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_cardsCtrl.hasClients) return;
        _lastAutoScrollKey = nextKey;
        final idx = fixedOrder.indexOf(nextKey) + (duhaShown ? 1 : 0);
        final target = (idx * 66.0 - 60.0).clamp(
          0.0,
          _cardsCtrl.position.maxScrollExtent,
        );
        _cardsCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
        );
      });
    }

    return prayerCards;
  }

  // ---------------------------------------------------------- QIBLA HELPERS
  Future<void> _qiblaNav() async {
    final loc = _timesService.locationService;

    // If GPS isn't active, request it — city-level precision isn't enough for qibla
    if (!loc.useGps) {
      final ok = await _requestGpsForQibla();
      if (!ok) return; // user declined or unavailable
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QiblaPage(
          latitude: loc.latitude,
          longitude: loc.longitude,
          isNight: _isNight,
        ),
      ),
    );
  }

  /// Returns true if GPS was successfully activated.
  Future<bool> _requestGpsForQibla() async {
    // 1. Check if location services are enabled
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى تفعيل خدمة الموقع من إعدادات الجهاز'),
          backgroundColor: glowColor.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return false;
    }

    // 2. Check permission status
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('الإذن مطلوب لتحديد اتجاه القبلة بدقة'),
            backgroundColor: glowColor.withValues(alpha: 0.9),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        return false;
      }
    }
    if (perm == LocationPermission.deniedForever) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'تم رفض الإذن نهائياً. افتح إعدادات الجهاز لتفعيله',
          ),
          backgroundColor: glowColor.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return false;
    }

    // 3. Detect current position
    final ok = await _timesService.locationService.detectGps();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تعذر تحديد الموقع. تأكد من تفعيل GPS'),
          backgroundColor: glowColor.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
    return ok;
  }

  // ---------------------------------------------------------- CIRCLE HERO
  Widget _heroCircle(
    String name,
    String countdown,
    String nextKey,
    String nextTimeFormatted,
  ) {
    final accent = AppTheme.prayerAccent[nextKey] ?? glowColor;
    const double ringSize = 190; // ~10% smaller than original 212
    return Center(
      child: Column(
        children: [
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(ringSize, ringSize),
                  painter: _ProgressRingPainter(
                    progress: _intervalProgress(),
                    start: _styleColors.first,
                    end: _styleColors.last,
                    track: border.withValues(alpha: _isNight ? 0.5 : 0.8),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.l10n.t('home_next_prayer'),
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: text2,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      style: GoogleFonts.inter(
                        fontSize: 26,
                        fontWeight: FontWeight.w300,
                        color: text1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      countdown,
                      style: GoogleFonts.lexend(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        color: _styleColors.first,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        nextTimeFormatted,
                        style: GoogleFonts.lexend(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- MINIMAL HERO
  Widget _heroMinimal(String name, String countdown, String nextKey) {
    final accent = AppTheme.prayerAccent[nextKey] ?? glowColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: _isNight ? 0.16 : 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              AppTheme.prayerIcon[nextKey] ?? Icons.mosque_rounded,
              size: 20,
              color: accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.l10n.t('home_next_prayer'),
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: text2,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: text1,
                  ),
                ),
              ],
            ),
          ),
          Text(
            countdown,
            style: GoogleFonts.lexend(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _styleColors.first,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _qiblaNav,
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: glowColor.withValues(alpha: _isNight ? 0.10 : 0.14),
                shape: BoxShape.circle,
                border: Border.all(
                  color: glowColor.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: Icon(Icons.explore_rounded, size: 18, color: glowColor),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- FOCUS LAYOUT
  Widget _composeFocus(
    String date,
    String hijriStr,
    String name,
    String countdown,
    String nextKey,
    String nextTimeFormatted, [
    Widget? labelWidget,
  ]) {
    final accent = AppTheme.prayerAccent[nextKey] ?? glowColor;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildHeader(date, hijriStr),
            if (labelWidget != null) ...[
              const SizedBox(height: 8),
              labelWidget,
            ],
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.l10n.t('home_next_prayer'),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: text2,
                        letterSpacing: 6,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      name,
                      style: GoogleFonts.inter(
                        fontSize: 44,
                        fontWeight: FontWeight.w200,
                        color: text1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ShaderMask(
                      shaderCallback: (b) =>
                          LinearGradient(colors: _styleColors).createShader(b),
                      child: Text(
                        countdown,
                        style: GoogleFonts.lexend(
                          fontSize: 46,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        nextTimeFormatted,
                        style: GoogleFonts.lexend(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: 210,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _intervalProgress(),
                          minHeight: 6,
                          backgroundColor: border,
                          valueColor: AlwaysStoppedAnimation(
                            _styleColors.first,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _focusStrip(nextKey),
            const SizedBox(height: 14),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _focusStrip(String nextKey) {
    const order = ['FAJR', 'SUNRISE', 'DHUHR', 'ASR', 'MAGHRIB', 'ISHA'];
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: order.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final k = order[i];
          final accent = AppTheme.prayerAccent[k] ?? glowColor;
          final isNext = k == nextKey;
          final time = _formatTime(_timesService.getTime(k) ?? '--:--');
          final idx = _prayerTimes.indexWhere((p) => p['name'] == k);
          return GestureDetector(
            onTap: idx != -1 ? () => _openCard(idx, k) : null,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 64,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isNext
                    ? accent.withValues(alpha: _isNight ? 0.18 : 0.14)
                    : cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isNext ? accent.withValues(alpha: 0.6) : border,
                  width: isNext ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    AppTheme.prayerIcon[k] ?? Icons.mosque_rounded,
                    size: 18,
                    color: accent,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    time,
                    style: GoogleFonts.lexend(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isNext ? text1 : text2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------- TIMELINE LAYOUT
  Widget _composeTimeline(
    String date,
    String hijriStr,
    String name,
    String countdown,
    String nextKey, [
    Widget? labelWidget,
  ]) {
    const order = ['FAJR', 'SUNRISE', 'DHUHR', 'ASR', 'MAGHRIB', 'ISHA'];
    final nowMin = _now.hour * 60 + _now.minute;
    final rows = <Widget>[];
    for (var i = 0; i < order.length; i++) {
      final k = order[i];
      final raw = _timesService.getTime(k) ?? '--:--';
      final isNext = k == nextKey;
      final isPassed =
          raw != '--:--' && _parseTimeMin(raw) <= nowMin && !isNext;
      final idx = _prayerTimes.indexWhere((p) => p['name'] == k);
      rows.add(
        GestureDetector(
          onTap: idx != -1 ? () => _openCard(idx, k) : null,
          behavior: HitTestBehavior.opaque,
          child: _timelineRow(
            k,
            _formatTime(raw),
            isFirst: i == 0,
            isLast: i == order.length - 1,
            isNext: isNext,
            isPassed: isPassed,
          ),
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildHeader(date, hijriStr),
            if (labelWidget != null) ...[
              const SizedBox(height: 8),
              labelWidget,
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border, width: 1),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 18,
                    color: _styleColors.first,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    name,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: text1,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    countdown,
                    style: GoogleFonts.lexend(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _styleColors.first,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                controller: _cardsCtrl,
                padding: const EdgeInsets.only(bottom: 8),
                children: rows,
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _timelineRow(
    String nameKey,
    String timeStr, {
    required bool isFirst,
    required bool isLast,
    required bool isNext,
    required bool isPassed,
  }) {
    final accent = AppTheme.prayerAccent[nameKey] ?? glowColor;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2,
                    color: isFirst ? Colors.transparent : border,
                  ),
                ),
                Container(
                  width: isNext ? 16 : 12,
                  height: isNext ? 16 : 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (isPassed || isNext) ? accent : cardBg,
                    border: Border.all(color: accent, width: 2),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : border,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: isNext
                    ? Color.alphaBlend(
                        accent.withValues(alpha: _isNight ? 0.13 : 0.12),
                        cardBg,
                      )
                    : cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isNext ? accent.withValues(alpha: 0.65) : border,
                  width: isNext ? 1.5 : 1,
                ),
              ),
              child: Opacity(
                opacity: isPassed ? 0.55 : 1.0,
                child: Row(
                  children: [
                    Icon(
                      AppTheme.prayerIcon[nameKey] ?? Icons.mosque_rounded,
                      size: 18,
                      color: accent,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _displayName(nameKey),
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: isNext ? FontWeight.w700 : FontWeight.w500,
                        color: text1,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      timeStr,
                      style: GoogleFonts.lexend(
                        fontSize: isNext ? 16 : 14,
                        fontWeight: isNext ? FontWeight.w600 : FontWeight.w400,
                        color: isNext ? accent : text2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- KIDS HOME
  Widget _buildKidsHome(String date, String hijriStr) {
    final count = _kidsService.prayedCount;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'السلام عليكم 👋',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: text1,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SettingsPage(
                        timesService: _timesService,
                        l10n: widget.l10n,
                        isNight: _isNight,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border, width: 1),
                  ),
                  child: Icon(Icons.settings_rounded, size: 20, color: text2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Stars + streak banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _styleColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: _styleColors.first.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                _kidsStat('⭐', '${_kidsService.stars}', 'نجمة'),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                _kidsStat('🔥', '${_kidsService.streak}', 'يوم متتالٍ'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              'صلّيت $count من ٥ اليوم',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: text1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              _kidsEncouragement(count),
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: text2,
              ),
            ),
          ),
          const SizedBox(height: 18),
          ...KidsService.fardPrayers.map(_kidsPrayerCard),
        ],
      ),
    );
  }

  Widget _kidsStat(String emoji, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.lexend(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  String _kidsEncouragement(int count) {
    if (count == 0) return 'هيا نبدأ يومنا بالصلاة! 🌟';
    if (count >= 5) return 'أحسنت! أكملت صلوات اليوم 🎉';
    return 'بارك الله فيك، أكمِل الباقي 💪';
  }

  Widget _kidsPrayerCard(String key) {
    final done = _kidsService.isPrayed(key);
    final accent = AppTheme.prayerAccent[key] ?? glowColor;
    final time = _formatTime(_timesService.getTime(key) ?? '--:--');
    return GestureDetector(
      onTap: () => _kidsService.togglePrayed(key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: done
              ? accent.withValues(alpha: _isNight ? 0.2 : 0.16)
              : cardBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: done ? accent : border,
            width: done ? 2 : 1.4,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: _isNight ? 0.22 : 0.16),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                AppTheme.prayerIcon[key] ?? Icons.mosque_rounded,
                size: 30,
                color: accent,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName(key),
                    style: GoogleFonts.inter(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: text1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'الساعة $time',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: text2,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: done ? accent : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: accent, width: 2),
              ),
              child: Icon(
                done ? Icons.check_rounded : Icons.add_rounded,
                size: 24,
                color: done ? Colors.white : accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------- STYLE PICKER
  String _styleName(HomeStyle s) => widget.l10n.t('home_style_${s.name}');
  String _styleDesc(HomeStyle s) => widget.l10n.t('home_style_${s.name}_desc');
  IconData _styleIcon(HomeStyle s) {
    switch (s) {
      case HomeStyle.circle:
        return Icons.circle_outlined;
      case HomeStyle.rectangle:
        return Icons.crop_16_9_rounded;
      case HomeStyle.minimal:
        return Icons.short_text_rounded;
      case HomeStyle.focus:
        return Icons.center_focus_strong_rounded;
      case HomeStyle.timeline:
        return Icons.timeline_rounded;
    }
  }

  void _showHomeStyleSheet() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            16 + MediaQuery.of(context).viewPadding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: textDim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.l10n.t('home_style'),
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: text1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.l10n.t('home_style_hint'),
                style: GoogleFonts.inter(fontSize: 12, color: text2),
              ),
              const SizedBox(height: 16),
              ...HomeStyle.values.map((s) {
                final sel = _timesService.homeStyle == s;
                final grad =
                    AppTheme.styleGradient[s] ?? [glowColor, glowColor];
                return GestureDetector(
                  onTap: () {
                    _timesService.setHomeStyle(s);
                    setSheet(() {});
                    Navigator.pop(context);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: sel
                          ? glowColor.withValues(alpha: _isNight ? 0.12 : 0.16)
                          : cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: sel ? glowColor.withValues(alpha: 0.5) : border,
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: grad,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _styleIcon(s),
                            size: 22,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _styleName(s),
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: text1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _styleDesc(s),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: text2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (sel)
                          Icon(
                            Icons.check_circle_rounded,
                            size: 22,
                            color: glowColor,
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrayerCard({
    required String nameKey,
    required String timeStr,
    required int idx,
    required bool isNext,
    String? customDisplay,
    String? customSubtitle,
    IconData? customIcon,
  }) {
    final displayName = customDisplay ?? _displayName(nameKey);
    final isMuted = _mutedPrayers.contains(nameKey);
    final isExtra =
        customDisplay != null; // midnight/last-third/duha are not clickable
    final accent = AppTheme.prayerAccent[nameKey] ?? glowColor;

    // Has this prayer's time already passed today?
    bool isPassed = false;
    if (!isExtra && idx != -1 && !isNext) {
      final nowMin = _now.hour * 60 + _now.minute;
      isPassed = _parseTimeMin(_prayerTimes[idx]['time'] ?? '0:0') <= nowMin;
    }

    final Color cardColor = isNext
        ? Color.alphaBlend(
            accent.withValues(alpha: _isNight ? 0.13 : 0.12),
            cardBg,
          )
        : (isExtra ? glitterColor : cardBg);
    final Color borderColor = isNext
        ? accent.withValues(alpha: 0.65)
        : (isExtra ? glitterBorder : border);

    return GestureDetector(
      onTap: () {
        if (idx != -1 && !isExtra) _openCard(idx, nameKey);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: isNext ? 14 : 11,
        ),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: isNext ? 1.5 : 1),
          boxShadow: isNext
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: _isNight ? 0.18 : 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Opacity(
          opacity: isPassed ? 0.55 : 1.0,
          child: Row(
            children: [
              // Per-prayer icon badge
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: _isNight ? 0.16 : 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  customIcon ??
                      AppTheme.prayerIcon[nameKey] ??
                      Icons.mosque_rounded,
                  size: 18,
                  color: accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          displayName,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: isNext
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isExtra
                                ? glowColor.withValues(alpha: 0.9)
                                : text1,
                            letterSpacing: 1.5,
                          ),
                        ),
                        if (isMuted && !isExtra)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.notifications_off_rounded,
                              size: 13,
                              color: textDim,
                            ),
                          ),
                      ],
                    ),
                    if (customSubtitle != null)
                      Text(
                        customSubtitle,
                        style: GoogleFonts.inter(fontSize: 11, color: textDim),
                      ),
                  ],
                ),
              ),
              if (isPassed)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: accent.withValues(alpha: 0.8),
                  ),
                ),
              if (isNext)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'القادمة',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
              Text(
                timeStr,
                style: GoogleFonts.lexend(
                  fontSize: isNext ? 16 : 14,
                  fontWeight: isNext ? FontWeight.w600 : FontWeight.w400,
                  color: isNext
                      ? accent
                      : (isExtra ? glowColor.withValues(alpha: 0.75) : text2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color get glitterColor {
    return glowColor.withValues(alpha: _isNight ? 0.06 : 0.08);
  }

  Color get glitterBorder {
    return glowColor.withValues(alpha: _isNight ? 0.15 : 0.20);
  }

  Widget _buildHeader(String date, String hijriStr) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.location_on_rounded,
                    size: 13,
                    color: glowColor.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _timesService.locationService.compactName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: text2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _timesService.locationService.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: textDim,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                date,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: text1.withValues(alpha: 0.85),
                ),
              ),
              if (_timesService.showHijri)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    hijriStr,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: glowColor.withValues(alpha: 0.75),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          key: _menuKey,
          onTap: _openMenu,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border, width: 1),
            ),
            child: Icon(Icons.menu_rounded, size: 20, color: text1),
          ),
        ),
      ],
    );
  }

  /// Fraction of the interval between the previous and next prayer that has
  /// already elapsed — drives the hero progress ring.
  double _intervalProgress() {
    final nowMin = _now.hour * 60 + _now.minute + _now.second / 60.0;
    final mins =
        _prayerTimes
            .map((p) => _parseTimeMin(p['time'] ?? '0:0').toDouble())
            .toList()
          ..sort();
    if (mins.isEmpty) return 0;
    double prev = mins.lastWhere(
      (m) => m <= nowMin,
      orElse: () => mins.last - 1440,
    );
    double next = mins.firstWhere(
      (m) => m > nowMin,
      orElse: () => mins.first + 1440,
    );
    if (next <= prev) next += 1440;
    return ((nowMin - prev) / (next - prev)).clamp(0.0, 1.0);
  }

  Widget _buildCountdownHero(
    String name,
    String countdown,
    String nextKey,
    String nextTimeFormatted,
  ) {
    final accent = AppTheme.prayerAccent[nextKey] ?? glowColor;
    return Center(
      child: Column(
        children: [
          SizedBox(
            width: 236,
            height: 116,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(236, 116),
                  painter: _ProgressSquarePainter(
                    progress: _intervalProgress(),
                    start: _styleColors.first,
                    end: _styleColors.last,
                    track: border.withValues(alpha: _isNight ? 0.5 : 0.8),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.l10n.t('home_next_prayer'),
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: text2,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      name,
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w300,
                        color: text1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          countdown,
                          style: GoogleFonts.lexend(
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            color: glowColor,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            nextTimeFormatted,
                            style: GoogleFonts.lexend(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================== CARD POPUP
  Widget _buildCardPopup() {
    if (_expandedIndex == null && _cardCtrl.isDismissed) {
      return const SizedBox();
    }
    final all = _prayerTimes;
    if (_expandedIndex == null || _expandedIndex! >= all.length) {
      return const SizedBox();
    }
    final prayer = all[_expandedIndex!];
    final name = prayer['name']!, displayName = _displayName(name);
    final time = prayer['time']!;
    final isMuted = _mutedPrayers.contains(name);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _closeCard,
            child: FadeTransition(
              opacity: _cardOverlayFade,
              child: Container(color: Colors.black.withValues(alpha: 0.5)),
            ),
          ),
        ),
        Center(
          child: ScaleTransition(
            scale: _cardScale,
            child: Container(
              width: MediaQuery.of(context).size.width - 48,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: glowColor.withValues(alpha: 0.6),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: glowColor.withValues(alpha: _isNight ? 0.15 : 0.2),
                    blurRadius: 30,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          displayName,
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: text1,
                            letterSpacing: 2,
                          ),
                        ),
                        Text(
                          time,
                          style: GoogleFonts.lexend(
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            color: glowColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _popupAction(
                      isMuted
                          ? Icons.notifications_off_rounded
                          : Icons.notifications_rounded,
                      isMuted
                          ? widget.l10n.t('notif_off')
                          : widget.l10n.t('notif_on'),
                      () => _toggleMute(name),
                    ),
                    const SizedBox(height: 12),
                    _popupAction(
                      Icons.volume_up_rounded,
                      widget.l10n.t('sound_title'),
                      () async {
                        _closeCard();
                        await _showAdhanSoundsSheet(name);
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _popupAction(
    IconData icon,
    String label,
    VoidCallback? onTap, {
    bool locked = false,
    String lockedMsg = '',
  }) {
    return GestureDetector(
      onTap: locked ? null : onTap,
      child: Opacity(
        opacity: locked ? 0.4 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: _isNight
                ? Colors.white.withValues(alpha: 0.04)
                : const Color(0xFFE8DCC8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: locked ? textDim : glowColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: locked ? textDim : text1,
                      ),
                    ),
                    if (locked)
                      Text(
                        lockedMsg,
                        style: GoogleFonts.inter(fontSize: 11, color: textDim),
                      ),
                  ],
                ),
              ),
              if (locked) Icon(Icons.lock_rounded, size: 16, color: textDim),
            ],
          ),
        ),
      ),
    );
  }

  // ========================================================== ALL-PRAYER ADHAN SOUND

  /// Opens the sound picker sheet with a warning that the chosen sound
  /// will apply to ALL prayers, overwriting per-prayer preferences.
  Future<void> _showAllPrayerSoundSheet() async {
    await _adhanService.init();
    if (!mounted) return;

    final allPrayers = ['FAJR', 'DHUHR', 'ASR', 'MAGHRIB', 'ISHA'];

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) => ListenableBuilder(
            listenable: _adhanService,
            builder: (context, _) {
              final sounds = _adhanService.sounds;

              return DraggableScrollableSheet(
                initialChildSize: 0.62,
                minChildSize: 0.4,
                maxChildSize: 0.9,
                expand: false,
                builder: (ctx, scrollCtrl) => Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: textDim,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.music_note_rounded,
                            size: 20,
                            color: Color(0xFFD4A853),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            widget.l10n.t('sound_all_title'),
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: text1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ⚠ Warning
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2574C).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(
                              0xFFE2574C,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: Color(0xFFE2574C),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.l10n.t('sound_all_warn'),
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFFE2574C),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.l10n.t('sound_all_warn_desc'),
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      height: 1.6,
                                      color: text2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ── Global mute toggle ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GestureDetector(
                        onTap: () {
                          _timesService.setAdhanGlobalMute(
                            !_timesService.adhanGlobalMute,
                          );
                          setSheet(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: _timesService.adhanGlobalMute
                                ? const Color(0xFFE2574C).withValues(alpha: 0.1)
                                : cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _timesService.adhanGlobalMute
                                  ? const Color(
                                      0xFFE2574C,
                                    ).withValues(alpha: 0.4)
                                  : border,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _timesService.adhanGlobalMute
                                    ? Icons.volume_off_rounded
                                    : Icons.volume_up_rounded,
                                size: 20,
                                color: _timesService.adhanGlobalMute
                                    ? const Color(0xFFE2574C)
                                    : text2,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _timesService.adhanGlobalMute
                                      ? widget.l10n.t('sound_muted')
                                      : widget.l10n.t('quick_mute'),
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _timesService.adhanGlobalMute
                                        ? const Color(0xFFE2574C)
                                        : text1,
                                  ),
                                ),
                              ),
                              Container(
                                width: 40,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: _timesService.adhanGlobalMute
                                      ? const Color(0xFFE2574C)
                                      : textDim.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Stack(
                                  children: [
                                    AnimatedPositioned(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      left: _timesService.adhanGlobalMute
                                          ? 18
                                          : 2,
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
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _adhanService.loading
                          ? const Center(child: CircularProgressIndicator())
                          : _adhanService.error != null
                          ? Center(
                              child: Text(
                                _adhanService.error!,
                                style: GoogleFonts.inter(color: textDim),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollCtrl,
                              itemCount:
                                  sounds.length +
                                  1, // +1 for "pick custom" button
                              itemBuilder: (_, i) {
                                if (i == sounds.length) {
                                  // ── Custom file button ──
                                  final custom = _adhanService.customSound;
                                  final hasCustom = custom != null;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    child: GestureDetector(
                                      onTap: hasCustom
                                          ? () async {
                                              _adhanService.selectSound(
                                                custom.key,
                                              );
                                              _adhanService.stop();
                                              await _applySoundToAll(
                                                allPrayers,
                                              );
                                              if (mounted) {
                                                Navigator.pop(ctx);
                                                setState(() {});
                                              }
                                            }
                                          : () async {
                                              final ok = await _adhanService
                                                  .pickCustomFromDevice();
                                              if (ok) {
                                                await _applySoundToAll(
                                                  allPrayers,
                                                );
                                                if (mounted) {
                                                  Navigator.pop(ctx);
                                                  setState(() {});
                                                }
                                              }
                                            },
                                      child: _soundCard(
                                        name: hasCustom
                                            ? custom.nameAr
                                            : widget.l10n.t('sound_pick_file'),
                                        sub: hasCustom
                                            ? widget.l10n.t(
                                                'sound_custom_label',
                                              )
                                            : null,
                                        isSelected:
                                            hasCustom &&
                                            _adhanService.selectedKey ==
                                                custom.key,
                                        isDownloaded: true,
                                        showPlay: false,
                                        icon: hasCustom
                                            ? Icons.audiotrack_rounded
                                            : Icons.add_rounded,
                                      ),
                                    ),
                                  );
                                }
                                final s = sounds[i];
                                final isDownloaded =
                                    s.isLocal ||
                                    _adhanService.isDownloaded(s.key);
                                final isSelected =
                                    _adhanService.selectedKey == s.key;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  child: GestureDetector(
                                    onTap: isDownloaded
                                        ? () async {
                                            _adhanService.selectSound(s.key);
                                            _adhanService.stop();
                                            await _applySoundToAll(allPrayers);
                                            if (mounted) {
                                              Navigator.pop(ctx);
                                              setState(() {});
                                            }
                                          }
                                        : null,
                                    child: _soundCard(
                                      name: s.nameAr,
                                      sub: s.nameEn.isNotEmpty
                                          ? s.nameEn
                                          : null,
                                      isSelected: isSelected,
                                      isDownloaded: isDownloaded,
                                      showPlay: isDownloaded && !s.isLocal,
                                      sound: s,
                                      onPlay: isDownloaded
                                          ? () {
                                              if (_playingKey == s.key) {
                                                _adhanService.stop();
                                                setSheet(
                                                  () => _playingKey = null,
                                                );
                                              } else {
                                                _adhanService.stop();
                                                _adhanService.play(key: s.key);
                                                setSheet(
                                                  () => _playingKey = s.key,
                                                );
                                              }
                                            }
                                          : null,
                                      onDownload: isDownloaded
                                          ? null
                                          : () => _adhanService.downloadSound(
                                              s.key,
                                            ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    ).then((_) {
      _adhanService.stop();
    });
  }

  /// Mark that the globally-selected sound applies to all prayers.
  /// Future per-prayer overrides will be stored under adhan_sound_<PRAYER>.
  Future<void> _applySoundToAll(List<String> prayers) async {
    // selectSound already sets the global default, which is what every prayer
    // uses unless a per-prayer override exists. We store the key for future use.
    final key = _adhanService.selectedKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    for (final p in prayers) {
      await prefs.setString('adhan_sound_$p', key);
    }
  }

  /// Shared card widget for a sound item with clear selection styling.
  Widget _soundCard({
    required String name,
    String? sub,
    required bool isSelected,
    required bool isDownloaded,
    bool showPlay = true,
    IconData? icon,
    AdhanSound? sound,
    VoidCallback? onPlay,
    VoidCallback? onDownload,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isSelected
            ? glowColor.withValues(alpha: _isNight ? 0.12 : 0.16)
            : cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? glowColor.withValues(alpha: 0.5) : border,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: isSelected ? glowColor : text2),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? glowColor : text1,
                  ),
                ),
                if (sub != null)
                  Text(
                    sub,
                    style: GoogleFonts.inter(fontSize: 11, color: textDim),
                  ),
              ],
            ),
          ),
          if (!isDownloaded && onDownload != null)
            GestureDetector(
              onTap: onDownload,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: glowColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'تحميل',
                  style: GoogleFonts.inter(fontSize: 11, color: glowColor),
                ),
              ),
            )
          else if (showPlay && onPlay != null) ...[
            GestureDetector(
              onTap: onPlay,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: glowColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  (_playingKey == sound?.key)
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded,
                  size: 18,
                  color: glowColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          if (isSelected)
            const Icon(
              Icons.check_circle_rounded,
              size: 20,
              color: Color(0xFFD4A853),
            )
          else if (!isDownloaded)
            const SizedBox(width: 20),
        ],
      ),
    );
  }

  // ========================================================== ADHAN SOUNDS SHEET
  final AdhanSoundService _adhanService = AdhanSoundService();
  String? _playingKey; // track which sound is playing

  Future<void> _showAdhanSoundsSheet([String? prayerName]) async {
    await _adhanService.init();
    VibeMode vibe = prayerName != null
        ? await VibeService.get(prayerName)
        : VibeMode.off;
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) => ListenableBuilder(
            listenable: _adhanService,
            builder: (context, _) {
              final sounds = _adhanService.sounds;
              final selected = _adhanService.selectedKey;

              return DraggableScrollableSheet(
                initialChildSize: 0.62,
                minChildSize: 0.4,
                maxChildSize: 0.9,
                expand: false,
                builder: (ctx, scrollCtrl) => Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: textDim,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.volume_up_rounded,
                            size: 20,
                            color: Color(0xFFD4A853),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            widget.l10n.t('sound_title'),
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: text1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ── DnD / silent-mode notice ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: glowColor.withValues(
                            alpha: _isNight ? 0.07 : 0.10,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: glowColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: glowColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'نتجاوز وضع «عدم الإزعاج» والوضع الصامت لضمان وصول الأذان في وقته. '
                                'يمكنك اختيار صوت مخصص، أو الاكتفاء بالاهتزاز فقط.',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  height: 1.6,
                                  color: text2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // ── Per-prayer vibration mode (cycles off → with → only) ──
                    if (prayerName != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: GestureDetector(
                          onTap: () async {
                            vibe = VibeService.next(vibe);
                            await VibeService.set(prayerName, vibe);
                            // Re-arm so a muted/vibrate-only choice takes effect.
                            AdhanAlarmService.schedulePrayerAlarms(const []);
                            setSheetState(() {});
                            if (mounted) setState(() {});
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            decoration: BoxDecoration(
                              color: vibe == VibeMode.off
                                  ? cardBg
                                  : glowColor.withValues(
                                      alpha: _isNight ? 0.10 : 0.15,
                                    ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: vibe == VibeMode.off
                                    ? border
                                    : glowColor.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  vibe == VibeMode.off
                                      ? Icons.smartphone_rounded
                                      : Icons.vibration_rounded,
                                  size: 20,
                                  color: vibe == VibeMode.off
                                      ? text2
                                      : glowColor,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'الاهتزاز',
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: text1,
                                        ),
                                      ),
                                      Text(
                                        VibeService.label(vibe),
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: vibe == VibeMode.off
                                              ? text2
                                              : glowColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.sync_alt_rounded,
                                  size: 16,
                                  color: textDim,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (prayerName != null) const SizedBox(height: 10),
                    // ── Pick a custom sound from the device ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GestureDetector(
                        onTap: () async {
                          final ok = await _adhanService.pickCustomFromDevice();
                          if (!mounted) return;
                          if (ok) {
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'تم تعيين الصوت المخصص',
                                  style: GoogleFonts.inter(color: Colors.white),
                                ),
                                backgroundColor: const Color(0xFF58B97D),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: glowColor.withValues(
                              alpha: _isNight ? 0.08 : 0.12,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: glowColor.withValues(alpha: 0.4),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: glowColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.library_music_rounded,
                                  size: 20,
                                  color: glowColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'اختر صوتًا من جهازك',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: text1,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'أي ملف صوتي (mp3, m4a, wav…)',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: textDim,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.add_circle_outline_rounded,
                                size: 22,
                                color: glowColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_adhanService.loading)
                      const Expanded(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFD4A853),
                          ),
                        ),
                      )
                    else if (_adhanService.error != null)
                      Expanded(
                        child: Center(
                          child: Text(
                            'تعذر تحميل الأصوات',
                            style: GoogleFonts.inter(color: textDim),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          controller: scrollCtrl,
                          padding: EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            16 + MediaQuery.of(context).viewPadding.bottom,
                          ),
                          itemCount: sounds.length,
                          itemBuilder: (_, i) {
                            final s = sounds[i];
                            final isSel = s.key == selected;
                            final isPlaying = _playingKey == s.key;
                            final isDownloaded =
                                s.isLocal || _adhanService.isDownloaded(s.key);
                            return GestureDetector(
                              onTap: () {
                                _adhanService.selectSound(s.key);
                                _adhanService.stop();
                                setState(() => _playingKey = null);
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? glowColor.withValues(
                                          alpha: _isNight ? 0.10 : 0.15,
                                        )
                                      : cardBg,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSel
                                        ? glowColor.withValues(alpha: 0.5)
                                        : border,
                                    width: isSel ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    // Play/Stop toggle
                                    GestureDetector(
                                      onTap: () {
                                        if (isPlaying) {
                                          _adhanService.stop();
                                          setState(() => _playingKey = null);
                                        } else {
                                          _adhanService.play(key: s.key);
                                          setState(() => _playingKey = s.key);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: glowColor.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Icon(
                                          isPlaying
                                              ? Icons.stop_rounded
                                              : Icons.play_arrow_rounded,
                                          size: 20,
                                          color: isPlaying
                                              ? Colors.redAccent
                                              : glowColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // Download button
                                    if (s.isLocal)
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        child: Icon(
                                          Icons.smartphone_rounded,
                                          size: 18,
                                          color: glowColor,
                                        ),
                                      )
                                    else if (!isDownloaded)
                                      GestureDetector(
                                        onTap: () =>
                                            _adhanService.downloadSound(s.key),
                                        child: Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.download_rounded,
                                            size: 18,
                                            color: Colors.blueAccent,
                                          ),
                                        ),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        child: const Icon(
                                          Icons.check_rounded,
                                          size: 18,
                                          color: Color(0xFF58B97D),
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            s.nameAr,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: isSel ? text1 : text2,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            s.nameEn,
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: textDim,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSel)
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        size: 20,
                                        color: Color(0xFFD4A853),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    ).then((_) {
      // Stop audio when sheet is dismissed
      _adhanService.stop();
      if (mounted) setState(() => _playingKey = null);
    });
  }

  // ========================================================== FLOATING MENU
  Widget _buildFloatingMenu() {
    if (!_menuOpen && _menuCtrl.isDismissed) return const SizedBox();
    final double menuW = MediaQuery.of(context).size.width - 16;
    final double btnCenterY = _menuBtnPos.dy + _menuBtnSize.height / 2;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _closeMenu,
            child: FadeTransition(
              opacity: _overlayFade,
              child: Container(color: Colors.black.withValues(alpha: 0.55)),
            ),
          ),
        ),
        Positioned(
          top: btnCenterY - 12,
          right: 8,
          width: menuW,
          child: ScaleTransition(
            scale: _menuScale,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: border, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: _isNight ? 0.6 : 0.25,
                      ),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => _setTheme(
                                  AppThemeMode.values[(_themeMode.index + 1) %
                                      3],
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _isNight
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : const Color(0xFFE8DCC8),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _themeMode == AppThemeMode.auto
                                        ? Icons.brightness_auto_rounded
                                        : _themeMode == AppThemeMode.light
                                        ? Icons.light_mode_rounded
                                        : Icons.dark_mode_rounded,
                                    size: 18,
                                    color: glowColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                widget.l10n.t('home_appearance'),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: text2,
                                  letterSpacing: 4,
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: _closeMenu,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _isNight
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : const Color(0xFFE8DCC8),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: text1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Theme picker — opens palette + day/night mode sheet
                      GestureDetector(
                        onTap: () {
                          _closeMenu();
                          _showThemeSheet();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: border, width: 1),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.palette_rounded,
                                size: 18,
                                color: glowColor,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                widget.l10n.t('quick_theme'),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: text1,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                themeName(_themeId),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: text2,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.chevron_left_rounded,
                                size: 16,
                                color: textDim,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Adhan sound picker — applies to ALL prayers
                      GestureDetector(
                        onTap: () {
                          _closeMenu();
                          _showAllPrayerSoundSheet();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: border, width: 1),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.music_note_rounded,
                                size: 18,
                                color: Color(0xFFD4A853),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                widget.l10n.t('quick_sound'),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: text1,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.chevron_left_rounded,
                                size: 16,
                                color: textDim,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () {
                          _closeMenu();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FajrAlarmSettingsPage(
                                timesService: _timesService,
                                l10n: widget.l10n,
                                isNight: _isNight,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: border, width: 1),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.alarm_rounded,
                                size: 18,
                                color: Color(0xFFD4A853),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'منبه الفجر',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: text1,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.chevron_left_rounded,
                                size: 16,
                                color: textDim,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Home style selector — opens the layout picker sheet
                      GestureDetector(
                        onTap: () {
                          _closeMenu();
                          _showHomeStyleSheet();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: border, width: 1),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _styleIcon(_timesService.homeStyle),
                                size: 18,
                                color: glowColor,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                widget.l10n.t('home_style'),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: text1,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _styleName(_timesService.homeStyle),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: text2,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.chevron_left_rounded,
                                size: 16,
                                color: textDim,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      GestureDetector(
                        onTap: () {
                          _closeMenu();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SettingsPage(
                                timesService: _timesService,
                                l10n: widget.l10n,
                                isNight: _isNight,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _isNight
                                ? Colors.white.withValues(alpha: 0.04)
                                : const Color(0xFFE8DCC8),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: border, width: 1),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.settings_rounded,
                                size: 18,
                                color: text2,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.l10n.t('home_settings'),
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: text1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ========================================================== THEME SHEET

  void _showThemeSheet() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return Container(
            padding: EdgeInsets.fromLTRB(
              24,
              20,
              24,
              20 + MediaQuery.of(ctx).viewPadding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: textDim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Icon(Icons.palette_rounded, size: 20, color: glowColor),
                    const SizedBox(width: 10),
                    Text(
                      widget.l10n.t('theme_title'),
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: text1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  widget.l10n.t('mode'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textDim,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 10),
                _themeModeSegments(onChanged: () => setSheet(() {})),
                const SizedBox(height: 18),
                Text(
                  widget.l10n.t('theme_palette'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textDim,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    widget.l10n.t('theme_palette_desc'),
                    style: GoogleFonts.inter(fontSize: 11, color: textDim),
                  ),
                ),
                ...AppThemeId.values.map((id) {
                  final sel = _themeId == id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () {
                        _setThemeId(id);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: sel
                              ? glowColor.withValues(
                                  alpha: _isNight ? 0.12 : 0.18,
                                )
                              : cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: sel
                                ? glowColor.withValues(alpha: 0.5)
                                : border,
                            width: sel ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              themeIcon(id),
                              size: 20,
                              color: sel ? glowColor : text2,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    themeName(id),
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: sel ? text1 : text2,
                                    ),
                                  ),
                                  Text(
                                    themeDesc(id),
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: textDim,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (sel)
                              Icon(
                                Icons.check_circle_rounded,
                                size: 20,
                                color: glowColor,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _themeModeSegments({VoidCallback? onChanged}) {
    const modes = AppThemeMode.values;
    const icons = [
      Icons.brightness_auto_rounded,
      Icons.light_mode_rounded,
      Icons.dark_mode_rounded,
    ];
    final labels = [
      widget.l10n.t('home_auto'),
      widget.l10n.t('home_light'),
      widget.l10n.t('home_dark'),
    ];

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: border),
      ),
      child: Row(
        children: List.generate(modes.length, (i) {
          final sel = _themeMode == modes[i];
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: i == 0 ? 0 : 3,
                right: i == modes.length - 1 ? 0 : 3,
              ),
              child: GestureDetector(
                onTap: () {
                  _setTheme(modes[i]);
                  onChanged?.call();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 6,
                  ),
                  decoration: BoxDecoration(
                    color: sel
                        ? glowColor.withValues(alpha: _isNight ? 0.18 : 0.22)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icons[i],
                        size: 18,
                        color: sel ? glowColor : text2.withValues(alpha: 0.45),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        labels[i],
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: sel ? text1 : textDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ========================================================== PRAYER LOGIC
  String _formatTime(String time24) {
    if (time24 == '--:--') return time24;
    final parts = time24.split(':');
    final int h = int.parse(parts[0]);
    final String m = parts[1];
    if (_timesService.use24h) return '$h:$m';
    // 12-hour with م/ص
    final period = h >= 12 ? 'م' : 'ص';
    final int h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $period';
  }

  // (ring painter defined at file end)

  String _calculateCountdown(String target) {
    final parts = target.split(':');
    var t = DateTime(
      _now.year,
      _now.month,
      _now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
    if (t.isBefore(_now)) t = t.add(const Duration(days: 1));
    final d = t.difference(_now);
    return '${d.inHours.toString().padLeft(2, '0')}:'
        '${(d.inMinutes % 60).toString().padLeft(2, '0')}:'
        '${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }
}

/// Gradient progress ring around the hero countdown: sweeps from the previous
/// prayer (0%) to the next prayer (100%).
class _ProgressSquarePainter extends CustomPainter {
  final double progress;
  final Color start, end, track;
  final double radius;
  _ProgressSquarePainter({
    required this.progress,
    required this.start,
    required this.end,
    required this.track,
  }) : radius = 28;

  @override
  void paint(Canvas c, Size s) {
    const stroke = 6.5;
    const inset = stroke; // keep the stroke fully inside the bounds
    final rect = Rect.fromLTWH(
      inset,
      inset,
      s.width - inset * 2,
      s.height - inset * 2,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // Track — the full rounded-square outline
    c.drawRRect(
      rrect,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.5,
    );

    if (progress <= 0.001) return;

    final fullPath = Path()..addRRect(rrect);
    final metric = fullPath.computeMetrics().first;
    final total = metric.length;

    // Path.addRRect starts at the beginning of the top edge and runs clockwise.
    // Shift the origin to the TOP-CENTER so progress grows symmetrically, just
    // like the previous circular ring did from the top.
    final startDist = (s.width / 2) - (inset + radius);
    final len = total * progress;

    final prog = Path();
    if (startDist + len <= total) {
      prog.addPath(metric.extractPath(startDist, startDist + len), Offset.zero);
    } else {
      prog.addPath(metric.extractPath(startDist, total), Offset.zero);
      prog.addPath(
        metric.extractPath(0, (startDist + len) - total),
        Offset.zero,
      );
    }

    c.drawPath(
      prog,
      Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + 2 * math.pi,
          colors: [start, end],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Glowing head dot at the progress tip
    final tipDist = (startDist + len) % total;
    final tangent = metric.getTangentForOffset(tipDist);
    if (tangent != null) {
      final tip = tangent.position;
      c.drawCircle(
        tip,
        7,
        Paint()
          ..color = end.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      c.drawCircle(tip, 4.5, Paint()..color = end);
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressSquarePainter o) =>
      o.progress != progress || o.end != end;
}

/// Circular progress ring used by the "circle" home layout. Draws a faint
/// track circle, a gradient sweep for the elapsed fraction, and a glowing tip.
class _ProgressRingPainter extends CustomPainter {
  final double progress;
  final Color start, end, track;
  _ProgressRingPainter({
    required this.progress,
    required this.start,
    required this.end,
    required this.track,
  });

  @override
  void paint(Canvas c, Size s) {
    const stroke = 7.0;
    final center = Offset(s.width / 2, s.height / 2);
    final radius = (s.width / 2) - stroke;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Track circle
    c.drawCircle(
      center,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.5,
    );

    if (progress <= 0.001) return;

    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    c.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + 2 * math.pi,
          colors: [start, end],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    // Glowing head dot at the progress tip
    final angle = -math.pi / 2 + sweep;
    final tip = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
    c.drawCircle(
      tip,
      7,
      Paint()
        ..color = end.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    c.drawCircle(tip, 4.5, Paint()..color = end);
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter o) =>
      o.progress != progress || o.end != end;
}
