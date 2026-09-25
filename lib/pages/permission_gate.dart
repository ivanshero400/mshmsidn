import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_theme_colors.dart';

/// Permissions the app cares about, in the order we ask for them.
enum AppPermission { notification, overlay, battery }

class _PermMeta {
  final IconData icon;
  final String title;
  final String desc;
  final List<String> steps;
  const _PermMeta(this.icon, this.title, this.desc, this.steps);
}

const Map<AppPermission, _PermMeta> _meta = {
  AppPermission.notification: _PermMeta(
    Icons.notifications_active_rounded,
    'تفعيل الإشعارات',
    'لنرسل لك تنبيهاً عند دخول وقت كل صلاة. بدون هذا الإذن لن تصلك تنبيهات الصلاة.',
    [
      'افتح إعدادات التطبيق',
      'اختر «الإشعارات»',
      'فعّل «السماح بإرسال الإشعارات»',
    ],
  ),
  AppPermission.overlay: _PermMeta(
    Icons.phone_callback_rounded,
    'العرض فوق التطبيقات',
    'لإظهار شاشة الأذان كاملةً عند دخول الوقت حتى لو كان الهاتف مقفلاً أو تستخدم تطبيقاً آخر.',
    [
      'سيُفتح إعداد «العرض فوق التطبيقات»',
      'ابحث عن تطبيق «الفجر» وفعّله',
      'ارجع إلى التطبيق',
    ],
  ),
  AppPermission.battery: _PermMeta(
    Icons.battery_charging_full_rounded,
    'إيقاف تقييد البطارية',
    'كي يعمل الأذان في وقته بدقّة، يجب ألا يوقف النظام التطبيق في الخلفية لتوفير البطارية.',
    [
      'افتح إعدادات التطبيق ← «البطارية»',
      'اختر «غير مقيّد» أو «بدون قيود»',
      'ارجع إلى التطبيق',
    ],
  ),
};

/// The ordered list of permissions we gate on.
const List<AppPermission> _required = [
  AppPermission.notification,
  AppPermission.overlay,
  AppPermission.battery,
];

Future<bool> isPermissionGranted(AppPermission p) async {
  if (!Platform.isAndroid) return true;
  switch (p) {
    case AppPermission.notification:
      return (await Permission.notification.status).isGranted;
    case AppPermission.overlay:
      return (await Permission.systemAlertWindow.status).isGranted;
    case AppPermission.battery:
      return (await Permission.ignoreBatteryOptimizations.status).isGranted;
  }
}

Future<PermissionStatus> _requestPermission(AppPermission p) {
  switch (p) {
    case AppPermission.notification:
      return Permission.notification.request();
    case AppPermission.overlay:
      return Permission.systemAlertWindow.request();
    case AppPermission.battery:
      return Permission.ignoreBatteryOptimizations.request();
  }
}

String _dismissKey(AppPermission p) => 'perm_dismissed_${p.name}';

Future<bool> _isDismissed(AppPermission p) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_dismissKey(p)) ?? false;
}

Future<void> _setDismissed(AppPermission p) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_dismissKey(p), true);
}

/// A full-screen gate that walks the user through every still-missing
/// permission, one screen at a time, then calls [onAllDone]. Resumes
/// automatically at the first ungranted permission, and re-checks live when
/// the user returns from system settings.
class PermissionGatePage extends StatefulWidget {
  final VoidCallback onAllDone;
  const PermissionGatePage({super.key, required this.onAllDone});

  /// True if at least one required permission is neither granted nor dismissed
  /// — i.e. the gate has something to show.
  static Future<bool> anyMissing() async {
    if (!Platform.isAndroid) return false;
    for (final p in _required) {
      if (!await isPermissionGranted(p) && !await _isDismissed(p)) return true;
    }
    return false;
  }

  @override
  State<PermissionGatePage> createState() => _PermissionGatePageState();
}

class _PermissionGatePageState extends State<PermissionGatePage> {
  final List<AppPermission> _queue = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _buildQueue();
  }

  Future<void> _buildQueue() async {
    _queue.clear();
    for (final p in _required) {
      if (!await isPermissionGranted(p) && !await _isDismissed(p)) {
        _queue.add(p);
      }
    }
    if (mounted) setState(() => _loading = false);
    if (_queue.isEmpty) widget.onAllDone();
  }

  void _advance() {
    if (!mounted) return;
    setState(() {
      if (_queue.isNotEmpty) _queue.removeAt(0);
    });
    if (_queue.isEmpty) widget.onAllDone();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _queue.isEmpty) {
      return Scaffold(
        backgroundColor: AppThemeColors.nightBg,
        body: const Center(child: CircularProgressIndicator(color: Color(0xFFD4A853))),
      );
    }
    return Scaffold(
      backgroundColor: AppThemeColors.nightBg,
      body: SafeArea(
        child: PermissionRequestView(
          // key forces a fresh state per permission as the queue advances
          key: ValueKey(_queue.first),
          permission: _queue.first,
          stepLabel: '${_required.length - _queue.length + 1} / ${_required.length}',
          onGranted: _advance,
          onSkip: () async {
            await _setDismissed(_queue.first);
            _advance();
          },
        ),
      ),
    );
  }
}

/// Reusable single-permission view. Used both inside onboarding (embedded) and
/// by [PermissionGatePage]. Auto-detects grants when the user returns from
/// settings and calls [onGranted].
class PermissionRequestView extends StatefulWidget {
  final AppPermission permission;
  final VoidCallback onGranted;
  final VoidCallback? onSkip;
  final String? stepLabel;

  const PermissionRequestView({
    super.key,
    required this.permission,
    required this.onGranted,
    this.onSkip,
    this.stepLabel,
  });

  @override
  State<PermissionRequestView> createState() => _PermissionRequestViewState();
}

class _PermissionRequestViewState extends State<PermissionRequestView>
    with WidgetsBindingObserver {
  static const gold = Color(0xFFD4A853);
  bool _showSteps = false;
  bool _checking = false;

  _PermMeta get meta => _meta[widget.permission]!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autoCheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the system settings screen — re-check live.
    if (state == AppLifecycleState.resumed) _autoCheck();
  }

  Future<void> _autoCheck() async {
    if (await isPermissionGranted(widget.permission)) {
      if (mounted) widget.onGranted();
    }
  }

  Future<void> _request() async {
    setState(() => _checking = true);
    await _requestPermission(widget.permission);
    // Give the system a beat, then re-check.
    await Future.delayed(const Duration(milliseconds: 300));
    final granted = await isPermissionGranted(widget.permission);
    if (!mounted) return;
    if (granted) {
      widget.onGranted();
    } else {
      setState(() {
        _checking = false;
        _showSteps = true; // reveal manual guidance + open-settings fallback
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    if (widget.stepLabel != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(widget.stepLabel!,
                            style: GoogleFonts.lexend(
                                fontSize: 13,
                                color: AppThemeColors.nightTextDim)),
                      ),
                    ],
                    const Spacer(flex: 2),
                    const SizedBox(height: 16),
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: gold.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: gold.withValues(alpha: 0.3), width: 1.5),
                      ),
                      child: Icon(meta.icon, size: 44, color: gold),
                    ),
                    const SizedBox(height: 26),
                    Text(meta.title,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            color: AppThemeColors.nightTextPrimary)),
                    const SizedBox(height: 14),
                    Text(meta.desc,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                            fontSize: 14,
                            height: 1.8,
                            color: AppThemeColors.nightTextSecondary)),
                    const SizedBox(height: 24),
                    if (_showSteps) _stepsBox(),
                    const Spacer(flex: 3),
                    const SizedBox(height: 24),
                    _primaryButton(),
                    const SizedBox(height: 12),
                    _secondaryButton(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _stepsBox() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: gold.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: gold.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.info_outline_rounded, size: 16, color: gold),
              const SizedBox(width: 8),
              Text('لم نتمكّن من طلب الإذن تلقائياً — فعّله يدوياً:',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppThemeColors.nightTextPrimary)),
            ]),
            const SizedBox(height: 12),
            for (int i = 0; i < meta.steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                        color: gold.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(7)),
                    alignment: Alignment.center,
                    child: Text('${i + 1}',
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: gold)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(meta.steps[i],
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              height: 1.5,
                              color: AppThemeColors.nightTextPrimary))),
                ]),
              ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: openAppSettings,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.open_in_new_rounded, size: 15, color: gold),
                const SizedBox(width: 6),
                Text('فتح إعدادات التطبيق',
                    style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w700, color: gold)),
              ]),
            ),
          ],
        ),
      );

  Widget _primaryButton() {
    final label = _checking
        ? '…'
        : _showSteps
            ? 'تحقّقت، تابع'
            : 'منح الإذن';
    return GestureDetector(
      onTap: _checking
          ? null
          : () async {
              if (_showSteps) {
                // User says they granted it manually — verify.
                if (await isPermissionGranted(widget.permission)) {
                  widget.onGranted();
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('لم يُمنح الإذن بعد',
                        style: GoogleFonts.inter(color: Colors.white)),
                    backgroundColor: Colors.red.withValues(alpha: 0.8),
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              } else {
                _request();
              }
            },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: gold.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: gold.withValues(alpha: 0.45), width: 1.5),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                fontSize: 16, fontWeight: FontWeight.w700, color: gold)),
      ),
    );
  }

  Widget _secondaryButton() {
    if (widget.onSkip == null) return const SizedBox(height: 4);
    return GestureDetector(
      onTap: widget.onSkip,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('تخطّي الآن',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppThemeColors.nightTextSecondary)),
      ),
    );
  }
}
