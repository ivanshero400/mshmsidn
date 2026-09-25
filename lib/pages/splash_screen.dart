import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Elegant splash/loading screen shown on app startup
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  static const Color gold = Color(0xFFD4A853);
  static const Color nightBg = Color(0xFF08080F);
  static const Color dayBg = Color(0xFFFBF7F0);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    final n = isDark;
    final bg = n ? nightBg : dayBg;
    final textColor = n ? const Color(0xFFF0EDE4) : const Color(0xFF3D3022);
    final textDim = n ? const Color(0xFF4A4540) : const Color(0xFFC4B8A8);

    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value.clamp(0.0, 1.0);
            final fade = (t * 2.5).clamp(0.0, 1.0);
            final slide = (t * 1.8 - 0.2).clamp(0.0, 1.0);
            final scale = 0.94 + 0.06 * (t * 1.4).clamp(0.0, 1.0);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                Opacity(
                  opacity: fade,
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: gold.withValues(alpha: n ? 0.12 : 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: gold.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(Icons.mosque_rounded, size: 40, color: gold),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                // Title
                Opacity(
                  opacity: fade,
                  child: Transform.translate(
                    offset: Offset(0, 16 * (1 - slide)),
                    child: Text(
                      'الفجر',
                      style: GoogleFonts.inter(
                        fontSize: 36,
                        fontWeight: FontWeight.w200,
                        color: textColor,
                        letterSpacing: 6,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Subtitle
                Opacity(
                  opacity: fade,
                  child: Text(
                    'أوقات الصلاة | القبلة | الأذان',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: gold.withValues(alpha: 0.7),
                      letterSpacing: 3,
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                // Loading bar
                Opacity(
                  opacity: fade,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 64),
                    child: SizedBox(
                      height: 3,
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final w = c.maxWidth;
                          final fillW = w * t;
                          return Stack(
                            children: [
                              // Track
                              Container(
                                decoration: BoxDecoration(
                                  color: textDim.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              // Animated fill with glow
                              Positioned(
                                left: 0, top: 0, bottom: 0,
                                width: fillW,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(2),
                                    gradient: const LinearGradient(
                                      colors: [Color(0x00D4A853), Color(0xFFD4A853), Color(0xCCD4A853)],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: gold.withValues(alpha: 0.5),
                                        blurRadius: 6,
                                        spreadRadius: 0,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
