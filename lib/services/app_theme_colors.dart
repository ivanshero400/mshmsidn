import 'package:flutter/material.dart';

/// All app theme colour palettes — one set of 9 semantic colours per theme.
///
/// Each theme is a simple named instance. Pages use the same getter pattern
/// everywhere:  `bg`, `cardBg`, `t1`, `t2`, `tDim`, `bdr`, `glw`
/// which read from the *active* palette.
enum AppThemeId { base, blueNight, lilac, rose, jade }

/// One palette (9 colours) for a single theme mode.
class AppPalette {
  final Color bg, surface, cardBg;
  final Color textPrimary, textSecondary, textDim;
  final Color border, glow;
  final Color? dayBg, daySurface, dayCardBg,
      dayTextPrimary, dayTextSecondary, dayTextDim, dayBorder, dayGlow;

  const AppPalette({
    required this.bg, required this.surface, required this.cardBg,
    required this.textPrimary, required this.textSecondary, required this.textDim,
    required this.border, required this.glow,
    this.dayBg, this.daySurface, this.dayCardBg,
    this.dayTextPrimary, this.dayTextSecondary, this.dayTextDim,
    this.dayBorder, this.dayGlow,
  });

  bool get hasDayMode => dayBg != null;
}

// ── Backwards-compat: old code uses static members ──
// ignore: non_constant_identifier_names
final _baseCompat = _basePalette;
extension AppPaletteCompat on AppPalette {
  Color get nBg => bg;
  Color get nSurface => surface;
  Color get nCardBg => cardBg;
  Color get nTextPrimary => textPrimary;
  Color get nTextSecondary => textSecondary;
  Color get nTextDim => textDim;
  Color get nBorder => border;
  Color get nGlow => glow;
  Color get dBg => dayBg ?? bg;
  Color get dSurface => daySurface ?? surface;
  Color get dCardBg => dayCardBg ?? cardBg;
  Color get dTextPrimary => dayTextPrimary ?? textPrimary;
  Color get dTextSecondary => dayTextSecondary ?? textSecondary;
  Color get dTextDim => dayTextDim ?? textDim;
  Color get dBorder => dayBorder ?? border;
  Color get dGlow => dayGlow ?? glow;
}

// ═══════════════ 1. الأساسي — ليلي-نهاري تلقائي ═══════════════
const _basePalette = AppPalette(
  bg: Color(0xFF08080F), surface: Color(0xFF12121A),
  cardBg: Color(0xFF14141E),
  textPrimary: Color(0xFFF0EDE4), textSecondary: Color(0xFF9A9588),
  textDim: Color(0xFF4A4540), border: Color(0xFF2A2528),
  glow: Color(0xFFD4A853),
  dayBg: Color(0xFFFBF7F0), daySurface: Color(0xFFF5EDDF),
  dayCardBg: Color(0xFFF0E8D5),
  dayTextPrimary: Color(0xFF3D3022), dayTextSecondary: Color(0xFF8B7355),
  dayTextDim: Color(0xFFC4B8A8), dayBorder: Color(0xFFD4C4A8),
  dayGlow: Color(0xFFE8C56D),
);

// ═══════════════ 2. الأزرق الليلي ═══════════════
const _bluePalette = AppPalette(
  bg: Color(0xFF080C1A), surface: Color(0xFF10182A),
  cardBg: Color(0xFF161E36),
  textPrimary: Color(0xFFEBEFF5), textSecondary: Color(0xFF8A97B0),
  textDim: Color(0xFF4A5468), border: Color(0xFF2A3250),
  glow: Color(0xFF6B9FFF),
  dayBg: Color(0xFFF2F4F8), daySurface: Color(0xFFE4E8F0),
  dayCardBg: Color(0xFFD8DDE8),
  dayTextPrimary: Color(0xFF1A2A40), dayTextSecondary: Color(0xFF556080),
  dayTextDim: Color(0xFFA0A8C0), dayBorder: Color(0xFFC0C8D8),
  dayGlow: Color(0xFF5078D0),
);

// ═══════════════ 3. الليلاك ═══════════════
const _lilacPalette = AppPalette(
  bg: Color(0xFF0E0A14), surface: Color(0xFF1A1424),
  cardBg: Color(0xFF201A30),
  textPrimary: Color(0xFFF0ECF5), textSecondary: Color(0xFFA098B8),
  textDim: Color(0xFF504868), border: Color(0xFF302850),
  glow: Color(0xFFB89FFF),
  dayBg: Color(0xFFF8F4FC), daySurface: Color(0xFFEDE4F5),
  dayCardBg: Color(0xFFE0D8F0),
  dayTextPrimary: Color(0xFF2A1840), dayTextSecondary: Color(0xFF6858A0),
  dayTextDim: Color(0xFFB0A0D0), dayBorder: Color(0xFFD0C0E0),
  dayGlow: Color(0xFF8058C0),
);

// ═══════════════ 4. الوردي ═══════════════
const _rosePalette = AppPalette(
  bg: Color(0xFF1A0E12), surface: Color(0xFF261820),
  cardBg: Color(0xFF301E28),
  textPrimary: Color(0xFFF8ECF0), textSecondary: Color(0xFFB898A8),
  textDim: Color(0xFF684858), border: Color(0xFF503040),
  glow: Color(0xFFF090B0),
  dayBg: Color(0xFFFCF4F6), daySurface: Color(0xFFF5E4E8),
  dayCardBg: Color(0xFFEDD4DC),
  dayTextPrimary: Color(0xFF381820), dayTextSecondary: Color(0xFF885868),
  dayTextDim: Color(0xFFC8A0B0), dayBorder: Color(0xFFE0C0CC),
  dayGlow: Color(0xFFD06888),
);

// ═══════════════ 5. الجاد — ألوان طبيعية ═══════════════
const _jadePalette = AppPalette(
  bg: Color(0xFF0F0E0A), surface: Color(0xFF1A1812),
  cardBg: Color(0xFF222018),
  textPrimary: Color(0xFFF0EDE4), textSecondary: Color(0xFFA09878),
  textDim: Color(0xFF585030), border: Color(0xFF383020),
  glow: Color(0xFFC8B868),
  dayBg: Color(0xFFF8F4EC), daySurface: Color(0xFFECE4D4),
  dayCardBg: Color(0xFFE0D8C0),
  dayTextPrimary: Color(0xFF3A3020), dayTextSecondary: Color(0xFF786850),
  dayTextDim: Color(0xFFB8A890), dayBorder: Color(0xFFD0C8B0),
  dayGlow: Color(0xFFB09858),
);

// ═══════════════ Helpers ═══════════════
const _map = <AppThemeId, AppPalette>{
  AppThemeId.base: _basePalette,
  AppThemeId.blueNight: _bluePalette,
  AppThemeId.lilac: _lilacPalette,
  AppThemeId.rose: _rosePalette,
  AppThemeId.jade: _jadePalette,
};

AppPalette paletteFor(AppThemeId id) => _map[id] ?? _basePalette;

String themeName(AppThemeId id) {
  switch (id) {
    case AppThemeId.base: return 'الأساسي';
    case AppThemeId.blueNight: return 'الأزرق الليلي';
    case AppThemeId.lilac: return 'الليلاك';
    case AppThemeId.rose: return 'الوردي';
    case AppThemeId.jade: return 'الجاد';
  }
}

String themeDesc(AppThemeId id) {
  switch (id) {
    case AppThemeId.base: return 'ليلي · نهاري تلقائي';
    case AppThemeId.blueNight: return 'أزرق داكن أنيق';
    case AppThemeId.lilac: return 'بنفسجي هادئ';
    case AppThemeId.rose: return 'وردي ناعم';
    case AppThemeId.jade: return 'ألوان طبيعية دافئة';
  }
}

IconData themeIcon(AppThemeId id) {
  switch (id) {
    case AppThemeId.base: return Icons.brightness_auto_rounded;
    case AppThemeId.blueNight: return Icons.nights_stay_rounded;
    case AppThemeId.lilac: return Icons.auto_awesome_rounded;
    case AppThemeId.rose: return Icons.favorite_rounded;
    case AppThemeId.jade: return Icons.eco_rounded;
  }
}

// ── Backwards-compat: old code uses AppThemeColors.nightBg, etc. ──
class AppThemeColors {
  AppThemeColors._();
  static final _p = _basePalette;
  static Color get nightBg => _p.bg;
  static Color get nightSurface => _p.surface;
  static Color get nightCardBg => _p.cardBg;
  static Color get nightTextPrimary => _p.textPrimary;
  static Color get nightTextSecondary => _p.textSecondary;
  static Color get nightTextDim => _p.textDim;
  static Color get nightBorder => _p.border;
  static Color get nightGlow => _p.glow;
  static Color get dayBg => _p.dayBg!;
  static Color get daySurface => _p.daySurface!;
  static Color get dayCardBg => _p.dayCardBg!;
  static Color get dayTextPrimary => _p.dayTextPrimary!;
  static Color get dayTextSecondary => _p.dayTextSecondary!;
  static Color get dayTextDim => _p.dayTextDim!;
  static Color get dayBorder => _p.dayBorder!;
  static Color get dayGlow => _p.dayGlow!;
}
