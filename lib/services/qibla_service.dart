import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Alignment state machine for the qibla finder.
enum QiblaState {
  /// No reliable sensor data yet.
  searching,

  /// More than [QiblaService.nearThreshold] away from the qibla.
  far,

  /// Within the near band — fine-tuning.
  near,

  /// Facing the qibla (entered at ±[QiblaService.lockEnter]°, kept until
  /// ±[QiblaService.lockExit]° — hysteresis prevents flicker at the edge).
  locked,
}

/// Compass accuracy reported by the platform sensor stack.
enum QiblaAccuracy { unreliable, low, medium, high }

/// High-accuracy qibla engine.
///
/// Heading source (Android): native fused ROTATION_VECTOR stream via
/// EventChannel `azan.qibla/sensors` — gyro-stabilised, tilt-compensated,
/// screen-rotation remapped and corrected to TRUE north with the World
/// Magnetic Model declination for the user's coordinates. Falls back to an
/// in-Dart accelerometer+magnetometer fusion if the native stream is missing.
///
/// Bearing & distance to the Kaaba are solved on the WGS-84 ellipsoid with
/// Vincenty's inverse formula (sub-0.01° vs ~0.2° error of the spherical
/// great-circle approximation), falling back to great-circle only if the
/// iteration fails to converge (antipodal edge case).
class QiblaService extends ChangeNotifier {
  // Kaaba coordinates (center of the structure).
  static const double kaabaLat = 21.4225241;
  static const double kaabaLng = 39.8261818;

  // Alignment thresholds (degrees).
  static const double lockEnter = 3.0;
  static const double lockExit = 6.0;
  static const double nearThreshold = 20.0;

  static const EventChannel _channel = EventChannel('azan.qibla/sensors');

  final double latitude;
  final double longitude;

  QiblaService({required this.latitude, required this.longitude}) {
    final geo = _vincentyInverse(latitude, longitude, kaabaLat, kaabaLng);
    qiblaBearing = geo.$1;
    distanceMeters = geo.$2;
  }

  /// TRUE-north bearing from the user to the Kaaba, degrees 0..360.
  late final double qiblaBearing;

  /// Geodesic distance to the Kaaba in meters.
  late final double distanceMeters;

  // ── Live sensor state ──
  double _heading = 0; // smoothed true heading
  double _rawHeading = 0;
  bool _hasFix = false;
  double pitch = 0, roll = 0;
  double declination = 0;
  bool fieldOk = true;
  bool nativeFusion = false;
  QiblaAccuracy accuracy = QiblaAccuracy.medium;
  QiblaState state = QiblaState.searching;

  double get heading => _heading;
  bool get hasFix => _hasFix;

  /// Signed shortest-path offset to the qibla, degrees in (-180, 180].
  /// Positive → user must turn RIGHT (clockwise); negative → turn LEFT.
  double get offset {
    double d = qiblaBearing - _heading;
    while (d > 180) {
      d -= 360;
    }
    while (d <= -180) {
      d += 360;
    }
    return d;
  }

  /// True when the phone is tilted too far from horizontal for a stable
  /// compass reading.
  bool get tooTilted => pitch.abs() > 35 || roll.abs() > 35;

  /// Calibration needed: the magnetometer reports unreliable/low accuracy.
  bool get needsCalibration =>
      accuracy == QiblaAccuracy.unreliable || accuracy == QiblaAccuracy.low;

  StreamSubscription? _nativeSub;
  StreamSubscription? _magSub;
  StreamSubscription? _accSub;
  Timer? _fallbackTimer;

  // Fallback fusion state.
  final List<double> _mag = [0, 0, 0];
  final List<double> _acc = [0, 0, 0];
  bool _gotMag = false, _gotAcc = false;

  // ── Lifecycle ──

  void start() {
    stop();
    try {
      _nativeSub = _channel.receiveBroadcastStream({
        'lat': latitude,
        'lng': longitude,
        'alt': 0.0,
      }).listen(_onNative, onError: (_) => _startFallback());
    } catch (_) {
      _startFallback();
    }
  }

  void stop() {
    _nativeSub?.cancel();
    _nativeSub = null;
    _stopFallback();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  // ── Native stream ──

  void _onNative(dynamic event) {
    final map = event as Map;
    _rawHeading = (map['heading'] as num).toDouble();
    pitch = (map['pitch'] as num?)?.toDouble() ?? 0;
    roll = (map['roll'] as num?)?.toDouble() ?? 0;
    declination = (map['declination'] as num?)?.toDouble() ?? 0;
    fieldOk = (map['fieldOk'] as bool?) ?? true;
    nativeFusion = (map['fused'] as bool?) ?? false;
    accuracy = switch ((map['accuracy'] as num?)?.toInt() ?? 2) {
      0 => QiblaAccuracy.unreliable,
      1 => QiblaAccuracy.low,
      2 => QiblaAccuracy.medium,
      _ => QiblaAccuracy.high,
    };
    _ingestHeading();
  }

  // ── Dart fallback fusion (non-Android / missing native stream) ──

  void _startFallback() {
    if (_fallbackTimer != null) return;
    const period = Duration(milliseconds: 40);
    _magSub = magnetometerEventStream(samplingPeriod: period).listen((e) {
      _mag[0] += 0.12 * (e.x - _mag[0]);
      _mag[1] += 0.12 * (e.y - _mag[1]);
      _mag[2] += 0.12 * (e.z - _mag[2]);
      _gotMag = true;
    });
    _accSub = accelerometerEventStream(samplingPeriod: period).listen((e) {
      _acc[0] += 0.12 * (e.x - _acc[0]);
      _acc[1] += 0.12 * (e.y - _acc[1]);
      _acc[2] += 0.12 * (e.z - _acc[2]);
      _gotAcc = true;
    });
    _fallbackTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_gotMag || !_gotAcc) return;
      final h = _tiltCompensatedAzimuth(_acc, _mag);
      if (h == null) return;
      _rawHeading = h; // no declination data in fallback mode
      accuracy = QiblaAccuracy.medium;
      _ingestHeading();
    });
  }

  void _stopFallback() {
    _magSub?.cancel();
    _accSub?.cancel();
    _fallbackTimer?.cancel();
    _magSub = null;
    _accSub = null;
    _fallbackTimer = null;
    _gotMag = false;
    _gotAcc = false;
  }

  static double? _tiltCompensatedAzimuth(List<double> a, List<double> m) {
    final aLen = math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
    if (aLen < 0.5) return null;
    final ax = a[0] / aLen, ay = a[1] / aLen, az = a[2] / aLen;
    // East = M × G, North = G × East (Android getRotationMatrix convention)
    double ex = m[1] * az - m[2] * ay;
    double ey = m[2] * ax - m[0] * az;
    double ez = m[0] * ay - m[1] * ax;
    final eLen = math.sqrt(ex * ex + ey * ey + ez * ez);
    if (eLen < 0.3) return null; // gravity ∥ field — unusable orientation
    ex /= eLen;
    ey /= eLen;
    ez /= eLen;
    final ny = az * ex - ax * ez;
    double h = math.atan2(ey, ny) * 180 / math.pi;
    if (h < 0) h += 360;
    return h;
  }

  // ── Smoothing + state machine ──

  void _ingestHeading() {
    if (!_hasFix) {
      _heading = _rawHeading;
      _hasFix = true;
    } else {
      // Circular exponential smoothing along the shortest arc. Adaptive
      // alpha: track fast while turning, settle hard when nearly still so
      // the needle is rock-stable for fine alignment.
      double delta = _rawHeading - _heading;
      while (delta > 180) {
        delta -= 360;
      }
      while (delta <= -180) {
        delta += 360;
      }
      final speed = delta.abs();
      final alpha = speed > 25 ? 0.45 : (speed > 8 ? 0.25 : 0.12);
      _heading = (_heading + alpha * delta + 360) % 360;
    }
    _updateState();
    notifyListeners();
  }

  void _updateState() {
    final d = offset.abs();
    switch (state) {
      case QiblaState.searching:
        state = d <= lockEnter
            ? QiblaState.locked
            : (d <= nearThreshold ? QiblaState.near : QiblaState.far);
      case QiblaState.locked:
        if (d > lockExit) {
          state = d <= nearThreshold ? QiblaState.near : QiblaState.far;
        }
      case QiblaState.near:
        if (d <= lockEnter) {
          state = QiblaState.locked;
        } else if (d > nearThreshold + 5) {
          state = QiblaState.far; // +5 hysteresis on the near/far edge too
        }
      case QiblaState.far:
        if (d <= lockEnter) {
          state = QiblaState.locked;
        } else if (d <= nearThreshold) {
          state = QiblaState.near;
        }
    }
  }

  // ── Geodesy: Vincenty inverse on the WGS-84 ellipsoid ──
  // Returns (initial bearing deg 0..360, distance meters).

  static (double, double) _vincentyInverse(
    double lat1, double lng1, double lat2, double lng2,
  ) {
    const a = 6378137.0; // WGS-84 semi-major axis
    const f = 1 / 298.257223563; // flattening
    const b = (1 - f) * a;

    final phi1 = lat1 * math.pi / 180, phi2 = lat2 * math.pi / 180;
    final l = (lng2 - lng1) * math.pi / 180;
    final u1 = math.atan((1 - f) * math.tan(phi1));
    final u2 = math.atan((1 - f) * math.tan(phi2));
    final sinU1 = math.sin(u1), cosU1 = math.cos(u1);
    final sinU2 = math.sin(u2), cosU2 = math.cos(u2);

    double lambda = l;
    double sinSigma = 0, cosSigma = 0, sigma = 0;
    double cosSqAlpha = 0, cos2SigmaM = 0;
    double sinLambda = 0, cosLambda = 0;
    bool converged = false;

    for (int i = 0; i < 200; i++) {
      sinLambda = math.sin(lambda);
      cosLambda = math.cos(lambda);
      final t1 = cosU2 * sinLambda;
      final t2 = cosU1 * sinU2 - sinU1 * cosU2 * cosLambda;
      sinSigma = math.sqrt(t1 * t1 + t2 * t2);
      if (sinSigma == 0) return (0, 0); // coincident points
      cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda;
      sigma = math.atan2(sinSigma, cosSigma);
      final sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma;
      cosSqAlpha = 1 - sinAlpha * sinAlpha;
      cos2SigmaM = cosSqAlpha != 0
          ? cosSigma - 2 * sinU1 * sinU2 / cosSqAlpha
          : 0; // equatorial line
      final c = f / 16 * cosSqAlpha * (4 + f * (4 - 3 * cosSqAlpha));
      final lambdaPrev = lambda;
      lambda = l +
          (1 - c) * f * sinAlpha *
              (sigma + c * sinSigma *
                  (cos2SigmaM + c * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)));
      if ((lambda - lambdaPrev).abs() < 1e-12) {
        converged = true;
        break;
      }
    }

    if (!converged) {
      // Antipodal edge case — fall back to spherical great-circle bearing.
      final y = math.sin(l) * math.cos(phi2);
      final x = math.cos(phi1) * math.sin(phi2) -
          math.sin(phi1) * math.cos(phi2) * math.cos(l);
      double brg = math.atan2(y, x) * 180 / math.pi;
      if (brg < 0) brg += 360;
      const r = 6371008.8;
      final dist = r *
          math.acos(
            (math.sin(phi1) * math.sin(phi2) +
                    math.cos(phi1) * math.cos(phi2) * math.cos(l))
                .clamp(-1.0, 1.0),
          );
      return (brg, dist);
    }

    final uSq = cosSqAlpha * (a * a - b * b) / (b * b);
    final bigA = 1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)));
    final bigB = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)));
    final deltaSigma = bigB * sinSigma *
        (cos2SigmaM + bigB / 4 *
            (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM) -
                bigB / 6 * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma) *
                    (-3 + 4 * cos2SigmaM * cos2SigmaM)));
    final distance = b * bigA * (sigma - deltaSigma);

    double bearing = math.atan2(
          cosU2 * sinLambda,
          cosU1 * sinU2 - sinU1 * cosU2 * cosLambda,
        ) * 180 / math.pi;
    if (bearing < 0) bearing += 360;
    return (bearing, distance);
  }
}
