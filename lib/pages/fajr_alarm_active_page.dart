import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../services/fajr_alarm_config_service.dart';
import '../services/fajr_alarm_sound_service.dart';

class FajrAlarmActivePage extends StatefulWidget {
  const FajrAlarmActivePage({super.key});

  @override
  State<FajrAlarmActivePage> createState() => _FajrAlarmActivePageState();
}

class _FajrAlarmActivePageState extends State<FajrAlarmActivePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _channel = MethodChannel('azan.adhan.alarm');
  static const Color _gold = Color(0xFFD4A853);
  static const Color _bgTop = Color(0xFF050814);
  static const Color _bgMid = Color(0xFF111936);
  static const Color _danger = Color(0xFFE2574C);
  static const Color _ok = Color(0xFF58B97D);
  static const int _requiredMovementMs = 10000;
  static const int _problemSeconds = 45;

  final FajrAlarmConfigService _configService = FajrAlarmConfigService();
  final FajrAlarmSoundService _soundService = FajrAlarmSoundService();
  final math.Random _random = math.Random();

  late final AnimationController _pulse;
  FajrAlarmEndMode _mode = FajrAlarmEndMode.untilWake;
  StreamSubscription<AccelerometerEvent>? _movementSub;
  Timer? _wrongTimer;
  Timer? _problemTimer;
  Timer? _muteTimer;

  bool _loading = true;
  bool _stopping = false;
  bool _mathSolved = false;
  String _alarmTitle = 'منبه الفجر';
  int _movementMs = 0;
  int _wrongCountdown = 0;
  int _problemCountdown = _problemSeconds;
  int _muteCountdown = 0;
  int _muteCooldown = 0;
  int _left = 64;
  int _right = 49;
  String _answerText = '';
  String _operator = '+';
  String? _lastOperator;
  String? _mathError;
  DateTime? _lastMotionAt;
  double? _lastX;
  double? _lastY;
  double? _lastZ;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
      lowerBound: 0.82,
      upperBound: 1,
    )..repeat(reverse: true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadMode();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _movementSub?.cancel();
    _wrongTimer?.cancel();
    _problemTimer?.cancel();
    _muteTimer?.cancel();
    _soundService.dispose();
    _configService.dispose();
    _pulse.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _stopping) return;
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (_needsMovement) _startMovementDetection();
    }
  }

  Future<void> _loadMode() async {
    await _loadAlarmData();
    await Future.wait([
      _configService.ensureLoaded(),
      _soundService.ensureLoaded(),
    ]);
    if (!mounted) return;
    setState(() {
      _mode = _configService.config.endMode;
      _loading = false;
    });
    unawaited(_soundService.startPlayback());

    if (_mode == FajrAlarmEndMode.phoneMovement) {
      _startMovementDetection();
    } else if (_mode == FajrAlarmEndMode.heavySleeper) {
      _newProblem();
    }
  }

  Future<void> _loadAlarmData() async {
    try {
      final data = await _channel.invokeMethod<Map>('getAlarmData');
      final name = data?['prayerName'] as String?;
      if (!mounted) return;
      setState(() {
        _alarmTitle = name == 'ISHA_WAKE_ALARM' ? 'منبه العشاء' : 'منبه الفجر';
      });
    } catch (_) {}
  }

  bool get _needsMovement {
    return _mode == FajrAlarmEndMode.phoneMovement ||
        (_mode == FajrAlarmEndMode.heavySleeper && _mathSolved);
  }

  Future<void> _stop() async {
    if (_stopping) return;
    _hideKeyboard();
    setState(() => _stopping = true);
    HapticFeedback.heavyImpact();
    await _stopSoundForExit();
    try {
      await _channel.invokeMethod('stopAlarm');
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _snooze() async {
    if (_stopping) return;
    _hideKeyboard();
    setState(() => _stopping = true);
    HapticFeedback.mediumImpact();
    await _stopSoundForExit();
    try {
      await _channel.invokeMethod('scheduleSnooze', {'minutes': 15});
    } catch (_) {
      try {
        await _channel.invokeMethod('stopAlarm');
      } catch (_) {}
    }
  }

  Future<void> _stopSoundForExit() async {
    _muteTimer?.cancel();
    _muteTimer = null;
    await _soundService.stopPlayback();
  }

  Future<void> _muteTemporarily() async {
    if (_stopping || _muteCooldown > 0) return;
    HapticFeedback.selectionClick();
    await _soundService.setTemporarilyMuted(true);
    if (!mounted) return;
    setState(() {
      _muteCountdown = 30;
      _muteCooldown = 40;
    });
    _muteTimer?.cancel();
    _muteTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _stopping) {
        timer.cancel();
        return;
      }
      final shouldResume = _muteCountdown == 1;
      final nextMute = (_muteCountdown - 1).clamp(0, 30).toInt();
      final nextCooldown = (_muteCooldown - 1).clamp(0, 40).toInt();
      if (shouldResume) unawaited(_soundService.setTemporarilyMuted(false));
      setState(() {
        _muteCountdown = nextMute;
        _muteCooldown = nextCooldown;
      });
      if (nextCooldown == 0) timer.cancel();
    });
  }

  void _startMovementDetection() {
    if (_movementSub != null || _stopping) return;
    _lastMotionAt = null;
    _lastX = null;
    _lastY = null;
    _lastZ = null;
    _movementSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 80),
    ).listen(_onMovementEvent, onError: (_) {});
  }

  void _onMovementEvent(AccelerometerEvent event) {
    if (!mounted || _stopping || !_needsMovement) return;
    final now = DateTime.now();
    final previous = _lastMotionAt;
    final dt = previous == null
        ? 80
        : now.difference(previous).inMilliseconds.clamp(40, 180).toInt();
    _lastMotionAt = now;

    final dx = _lastX == null ? 0.0 : (event.x - _lastX!).abs();
    final dy = _lastY == null ? 0.0 : (event.y - _lastY!).abs();
    final dz = _lastZ == null ? 0.0 : (event.z - _lastZ!).abs();
    _lastX = event.x;
    _lastY = event.y;
    _lastZ = event.z;

    final delta = math.sqrt(dx * dx + dy * dy + dz * dz);
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    final moved = delta > 1.25 || (magnitude - 9.81).abs() > 1.6;

    final nextMs = moved
        ? (_movementMs + dt).clamp(0, _requiredMovementMs).toInt()
        : (_movementMs - dt * 2).clamp(0, _requiredMovementMs).toInt();

    if (nextMs != _movementMs) {
      setState(() => _movementMs = nextMs);
    }
    if (_movementMs >= _requiredMovementMs) {
      _movementSub?.cancel();
      _movementSub = null;
      _stop();
    }
  }

  void _newProblem() {
    _problemTimer?.cancel();
    final add = _pickAddition();
    var a = _goodOperand();
    var b = _goodOperand();
    if (!add && b > a) {
      final tmp = a;
      a = b;
      b = tmp;
    }
    if (!add && a == b) {
      a = 64;
      b = 22;
    }
    final op = add ? '+' : '-';
    _lastOperator = op;
    setState(() {
      _left = a;
      _right = b;
      _operator = op;
      _answerText = '';
      _mathError = null;
      _wrongCountdown = 0;
      _problemCountdown = _problemSeconds;
    });
    _startProblemTimer();
  }

  bool _pickAddition() {
    final add = _random.nextBool();
    final op = add ? '+' : '-';
    if (_lastOperator == op) return !add;
    return add;
  }

  void _startProblemTimer() {
    _problemTimer?.cancel();
    _problemTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _stopping || _mathSolved) {
        timer.cancel();
        return;
      }
      if (_wrongCountdown > 0) return;
      if (_problemCountdown <= 1) {
        timer.cancel();
        HapticFeedback.mediumImpact();
        _newProblem();
      } else {
        setState(() => _problemCountdown--);
      }
    });
  }

  int _goodOperand() {
    while (true) {
      final value = 22 + _random.nextInt(78);
      final text = value.toString();
      if (text.contains('0')) continue;
      if (value % 5 == 0) continue;
      return value;
    }
  }

  int get _expectedAnswer {
    return _operator == '+' ? _left + _right : _left - _right;
  }

  void _submitAnswer() {
    if (_wrongCountdown > 0 || _stopping) return;
    final answer = int.tryParse(_answerText.trim());
    if (answer == _expectedAnswer) {
      _hideKeyboard();
      _problemTimer?.cancel();
      HapticFeedback.heavyImpact();
      setState(() {
        _mathSolved = true;
        _movementMs = 0;
        _mathError = null;
      });
      _startMovementDetection();
      return;
    }
    _hideKeyboard();
    _problemTimer?.cancel();
    HapticFeedback.vibrate();
    setState(() {
      _mathError = 'إجابة خاطئة';
      _wrongCountdown = 15;
    });
    _wrongTimer?.cancel();
    _wrongTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_wrongCountdown <= 1) {
        timer.cancel();
        _newProblem();
      } else {
        setState(() => _wrongCountdown--);
      }
    });
  }

  void _hideKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _appendDigit(String digit) {
    if (_wrongCountdown > 0 || _stopping || _mathSolved) return;
    if (_answerText.length >= 4) return;
    setState(() {
      _mathError = null;
      _answerText = _answerText == '0' ? digit : '$_answerText$digit';
    });
  }

  void _backspaceAnswer() {
    if (_wrongCountdown > 0 || _stopping || _mathSolved) return;
    if (_answerText.isEmpty) return;
    setState(() {
      _mathError = null;
      _answerText = _answerText.substring(0, _answerText.length - 1);
    });
  }

  void _clearAnswer() {
    if (_wrongCountdown > 0 || _stopping || _mathSolved) return;
    setState(() {
      _mathError = null;
      _answerText = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) {
        HapticFeedback.mediumImpact();
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: _bgTop,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _hideKeyboard,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_bgTop, _bgMid, _bgTop],
                ),
              ),
              child: SafeArea(
                child: Stack(
                  children: [
                    _loading
                        ? Center(child: CircularProgressIndicator(color: _gold))
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final keyboardInset = MediaQuery.viewInsetsOf(
                                context,
                              ).bottom;
                              return SingleChildScrollView(
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: EdgeInsets.fromLTRB(
                                  24,
                                  28,
                                  24,
                                  28 + keyboardInset,
                                ),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: math.max(
                                      0,
                                      constraints.maxHeight - 56,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const SizedBox(height: 4),
                                      Column(
                                        children: [
                                          _alarmIcon(),
                                          const SizedBox(height: 30),
                                          _headline(),
                                          const SizedBox(height: 18),
                                          _modeBody(),
                                        ],
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 22),
                                        child: _actions(),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                    if (!_loading)
                      Positioned(
                        top: 8,
                        left: 14,
                        child: _temporaryMuteButton(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _alarmIcon() {
    return ScaleTransition(
      scale: _pulse,
      child: Container(
        width: 132,
        height: 132,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _gold.withValues(alpha: 0.14),
          border: Border.all(color: _gold.withValues(alpha: 0.45), width: 2),
          boxShadow: [
            BoxShadow(
              color: _gold.withValues(alpha: 0.28),
              blurRadius: 42,
              spreadRadius: 8,
            ),
          ],
        ),
        child: Icon(_modeIcon, size: 62, color: _gold),
      ),
    );
  }

  Widget _temporaryMuteButton() {
    final enabled = !_stopping && _muteCooldown == 0;
    final activeMute = _muteCountdown > 0;
    final label = activeMute
        ? _muteCountdown.toString()
        : (_muteCooldown > 0 ? _muteCooldown.toString() : null);
    final color = enabled ? _gold : Colors.white54;
    return Tooltip(
      message: 'كتم مؤقت',
      child: Material(
        color: Colors.white.withValues(alpha: enabled ? 0.12 : 0.06),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? _muteTemporarily : null,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  activeMute
                      ? Icons.volume_off_rounded
                      : Icons.volume_mute_rounded,
                  size: 23,
                  color: color,
                ),
                if (label != null)
                  Positioned(
                    bottom: 5,
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData get _modeIcon {
    switch (_mode) {
      case FajrAlarmEndMode.prayerConfirmation:
        return Icons.mosque_rounded;
      case FajrAlarmEndMode.phoneMovement:
        return Icons.directions_walk_rounded;
      case FajrAlarmEndMode.heavySleeper:
        return _mathSolved ? Icons.directions_walk_rounded : Icons.calculate;
      case FajrAlarmEndMode.untilWake:
        return Icons.alarm_rounded;
    }
  }

  Widget _headline() {
    return Column(
      children: [
        Text(
          _alarmTitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _subtitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 15,
            height: 1.6,
            color: const Color(0xFFA9B2D0),
          ),
        ),
      ],
    );
  }

  String get _subtitle {
    switch (_mode) {
      case FajrAlarmEndMode.prayerConfirmation:
        return 'أكد الصلاة أو خذ غفوة قصيرة';
      case FajrAlarmEndMode.phoneMovement:
        return 'تحرك لمدة 10 ثوان لإيقاف المنبه';
      case FajrAlarmEndMode.heavySleeper:
        return _mathSolved
            ? 'الآن تحرك لمدة 10 ثوان لإيقاف المنبه'
            : 'حل المسألة أولًا، ثم تحرك';
      case FajrAlarmEndMode.untilWake:
        return 'اضغط إيقاف عند الاستيقاظ';
    }
  }

  Widget _modeBody() {
    switch (_mode) {
      case FajrAlarmEndMode.phoneMovement:
        return _movementPanel();
      case FajrAlarmEndMode.heavySleeper:
        return _mathSolved ? _movementPanel() : _mathPanel();
      case FajrAlarmEndMode.prayerConfirmation:
      case FajrAlarmEndMode.untilWake:
        return const SizedBox(height: 120);
    }
  }

  Widget _movementPanel() {
    final progress = _movementMs / _requiredMovementMs;
    final seconds = (_movementMs / 1000).floor().clamp(0, 10);
    return Column(
      children: [
        Text(
          'تحرك الآن',
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: 190,
          height: 190,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 180,
                height: 180,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 12,
                  color: _ok,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Text(
                '$seconds / 10',
                style: GoogleFonts.inter(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mathPanel() {
    return Column(
      children: [
        Text(
          '$_left $_operator $_right',
          textDirection: TextDirection.ltr,
          style: GoogleFonts.inter(
            fontSize: 48,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 18),
        _answerDisplay(),
        const SizedBox(height: 8),
        _mathErrorLine(),
        const SizedBox(height: 8),
        _problemTimerRow(),
        const SizedBox(height: 12),
        _numberPad(),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: _wrongCountdown > 0 || _stopping ? null : _submitAnswer,
            style: FilledButton.styleFrom(
              backgroundColor: _gold,
              disabledBackgroundColor: _gold.withValues(alpha: 0.45),
              foregroundColor: const Color(0xFF15110A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.check_rounded, size: 22),
            label: Text(
              _wrongCountdown > 0 ? 'انتظر $_wrongCountdown ثانية' : 'تحقق',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _answerDisplay() {
    final disabled = _wrongCountdown > 0 || _stopping;
    final text = _wrongCountdown > 0
        ? 'انتظر $_wrongCountdown'
        : (_answerText.isEmpty ? 'الإجابة' : _answerText);
    return Container(
      width: double.infinity,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: disabled ? 0.05 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _mathError == null
              ? Colors.white.withValues(alpha: 0.18)
              : _danger.withValues(alpha: 0.7),
          width: _mathError == null ? 1 : 1.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            text,
            textDirection: TextDirection.ltr,
            style: GoogleFonts.inter(
              fontSize: _answerText.isEmpty && _wrongCountdown == 0 ? 18 : 28,
              fontWeight: FontWeight.w800,
              color: _answerText.isEmpty && _wrongCountdown == 0
                  ? Colors.white38
                  : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mathErrorLine() {
    return SizedBox(
      height: 18,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: _mathError == null
            ? const SizedBox.shrink()
            : Text(
                _mathError!,
                key: ValueKey(_mathError),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _danger,
                ),
              ),
      ),
    );
  }

  Widget _problemTimerRow() {
    final color = _problemCountdown <= 10 ? _danger : _gold;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_rounded, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            _wrongCountdown > 0
                ? 'مسألة جديدة بعد $_wrongCountdown ث'
                : 'تتغير المسألة بعد $_problemCountdown ث',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberPad() {
    final items = <_PadItem>[
      for (final digit in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
        _PadItem.text(digit),
      const _PadItem.action('مسح', Icons.close_rounded),
      const _PadItem.text('0'),
      const _PadItem.action('حذف', Icons.backspace_rounded),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonWidth = (constraints.maxWidth - 16) / 3;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              SizedBox(width: buttonWidth, height: 52, child: _padButton(item)),
          ],
        );
      },
    );
  }

  Widget _padButton(_PadItem item) {
    final disabled = _wrongCountdown > 0 || _stopping || _mathSolved;
    final isDigit = item.digit != null;
    return Material(
      color: isDigit
          ? Colors.white.withValues(alpha: disabled ? 0.04 : 0.1)
          : _gold.withValues(alpha: disabled ? 0.07 : 0.16),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: disabled
            ? null
            : () {
                if (item.digit != null) {
                  _appendDigit(item.digit!);
                } else if (item.label == 'مسح') {
                  _clearAnswer();
                } else {
                  _backspaceAnswer();
                }
              },
        borderRadius: BorderRadius.circular(14),
        child: Center(
          child: item.digit != null
              ? Text(
                  item.digit!,
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.icon, size: 18, color: _gold),
                    const SizedBox(width: 5),
                    Text(
                      item.label!,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: _gold,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _actions() {
    switch (_mode) {
      case FajrAlarmEndMode.untilWake:
        return _singleStopButton();
      case FajrAlarmEndMode.prayerConfirmation:
        return Row(
          children: [
            Expanded(
              child: _actionButton(
                label: 'غفوة',
                icon: Icons.snooze_rounded,
                color: _gold,
                onPressed: _snooze,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton(
                label: 'صليت',
                icon: Icons.check_circle_rounded,
                color: _ok,
                onPressed: _stop,
              ),
            ),
          ],
        );
      case FajrAlarmEndMode.phoneMovement:
        return const SizedBox(height: 58);
      case FajrAlarmEndMode.heavySleeper:
        return const SizedBox(height: 58);
    }
  }

  Widget _singleStopButton() {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: _actionButton(
        label: _stopping ? 'جار الإيقاف' : 'إيقاف',
        icon: Icons.stop_rounded,
        color: _danger,
        onPressed: _stop,
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return FilledButton.icon(
      onPressed: _stopping ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        disabledBackgroundColor: color.withValues(alpha: 0.5),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: _stopping
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, size: 22),
      label: Text(
        label,
        style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PadItem {
  final String? digit;
  final String? label;
  final IconData? icon;

  const _PadItem.text(this.digit) : label = null, icon = null;

  const _PadItem.action(this.label, this.icon) : digit = null;
}
