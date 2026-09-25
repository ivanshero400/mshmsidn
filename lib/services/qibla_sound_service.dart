import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// Audio + haptic guidance for the qibla finder.
///
/// All sounds are synthesized at runtime as 16-bit PCM WAV (pure math — no
/// asset files, no network):
///  • tick  — short soft blip; repeats Geiger-counter style, faster as the
///    user closes in on the qibla, so they can align eyes-free.
///  • lock  — warm major-arpeggio chime when alignment is reached.
///  • lost  — low descending tone when alignment is lost again.
class QiblaSoundService {
  final AudioPlayer _tickPlayer = AudioPlayer();
  final AudioPlayer _chimePlayer = AudioPlayer();

  bool enabled = true;
  bool _ready = false;
  Timer? _tickTimer;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);

  late final _MemoryWav _tick;
  late final _MemoryWav _lock;
  late final _MemoryWav _lost;

  Future<void> init() async {
    if (_ready) return;
    _tick = _MemoryWav(_synth([_Note(1180, 45, gain: 0.32)]));
    _lock = _MemoryWav(_synth([
      _Note(659.25, 110, gain: 0.45), // E5
      _Note(830.61, 110, gain: 0.45), // G#5
      _Note(987.77, 240, gain: 0.50), // B5
    ]));
    _lost = _MemoryWav(_synth([
      _Note(392.0, 90, gain: 0.35), // G4
      _Note(293.66, 180, gain: 0.32), // D4
    ]));
    _ready = true;
  }

  /// Drive the tick cadence from the current absolute offset (degrees).
  /// Call on every heading update; cheap and idempotent.
  void updateTicks(double absOffset, {required bool locked}) {
    if (!enabled || !_ready || locked) {
      return;
    }
    // Cadence: 1.4s when fully misaligned → 130ms when nearly there.
    final t = (absOffset / 180.0).clamp(0.0, 1.0);
    final intervalMs = (130 + (1400 - 130) * math.pow(t, 0.7)).round();
    if (DateTime.now().difference(_lastTick).inMilliseconds < intervalMs) return;
    _lastTick = DateTime.now();
    _play(_tickPlayer, _tick);
    if (absOffset < 30) HapticFeedback.selectionClick();
  }

  /// Aligned with the qibla — celebrate once.
  Future<void> playLocked() async {
    if (!_ready) return;
    HapticFeedback.heavyImpact();
    if (enabled) await _play(_chimePlayer, _lock);
  }

  /// Alignment lost after having been locked.
  Future<void> playLost() async {
    if (!_ready) return;
    HapticFeedback.lightImpact();
    if (enabled) await _play(_chimePlayer, _lost);
  }

  Future<void> _play(AudioPlayer p, _MemoryWav src) async {
    try {
      await p.setAudioSource(src, preload: true);
      p.play();
    } catch (_) {}
  }

  void dispose() {
    _tickTimer?.cancel();
    _tickPlayer.dispose();
    _chimePlayer.dispose();
  }

  // ── WAV synthesis ──

  static const int _sampleRate = 44100;

  /// Renders a note sequence to a complete WAV file in memory. Each note is a
  /// sine fundamental + quieter octave harmonic, shaped by a fast-attack /
  /// exponential-decay envelope so it sounds like a soft bell, not a beep.
  static Uint8List _synth(List<_Note> notes) {
    final totalMs = notes.fold<int>(0, (s, n) => s + n.durMs) + 60; // tail
    final totalSamples = (_sampleRate * totalMs / 1000).round();
    final pcm = Float64List(totalSamples);

    int cursor = 0;
    for (final n in notes) {
      final len = (_sampleRate * n.durMs / 1000).round();
      // Let each note ring 80ms past its slot for natural overlap.
      final ring = (_sampleRate * 0.08).round();
      for (int i = 0; i < len + ring && cursor + i < totalSamples; i++) {
        final t = i / _sampleRate;
        final attack = math.min(1.0, i / (_sampleRate * 0.005)); // 5ms attack
        final decay = math.exp(-t * 9.0);
        final env = attack * decay * n.gain;
        final s = math.sin(2 * math.pi * n.freq * t) * 0.8 +
            math.sin(2 * math.pi * n.freq * 2 * t) * 0.2;
        pcm[cursor + i] += s * env;
      }
      cursor += len;
    }

    // Float → 16-bit PCM with soft clipping.
    final data = Int16List(totalSamples);
    for (int i = 0; i < totalSamples; i++) {
      final v = math.tan(pcm[i].clamp(-1.2, 1.2) * 0.78); // gentle saturation
      data[i] = (v.clamp(-1.0, 1.0) * 32767).round();
    }

    return _wrapWav(data);
  }

  /// Wraps raw 16-bit mono PCM in a canonical RIFF/WAVE header.
  static Uint8List _wrapWav(Int16List pcm) {
    final dataLen = pcm.length * 2;
    final bytes = BytesBuilder();
    void str(String s) => bytes.add(s.codeUnits);
    void u32(int v) => bytes.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
    void u16(int v) => bytes.add([v & 0xFF, (v >> 8) & 0xFF]);

    str('RIFF');
    u32(36 + dataLen);
    str('WAVE');
    str('fmt ');
    u32(16); // PCM chunk size
    u16(1); // PCM format
    u16(1); // mono
    u32(_sampleRate);
    u32(_sampleRate * 2); // byte rate
    u16(2); // block align
    u16(16); // bits per sample
    str('data');
    u32(dataLen);
    bytes.add(pcm.buffer.asUint8List());
    return bytes.toBytes();
  }
}

class _Note {
  final double freq;
  final int durMs;
  final double gain;
  const _Note(this.freq, this.durMs, {this.gain = 0.4});
}

/// just_audio source backed by an in-memory WAV byte buffer.
class _MemoryWav extends StreamAudioSource {
  final Uint8List bytes;
  _MemoryWav(this.bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= bytes.length;
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(bytes.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}
