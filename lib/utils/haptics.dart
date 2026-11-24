import 'package:vibration/vibration.dart';

import '../providers/theme_provider.dart';

class Haptics {
  static bool get isEnabled =>
      ThemeProvider.instance?.vibrationsEnabled ??
      ThemeProvider.defaultVibrationsEnabled;

  static Future<bool> hasVibrator() async {
    try {
      return await Vibration.hasVibrator();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasCustomVibrationsSupport() async {
    try {
      return await Vibration.hasCustomVibrationsSupport();
    } catch (_) {
      return false;
    }
  }

  /// Vibration amplitudes, on the 1–255 scale the platform takes.
  static const int _snapAmplitude = 90;
  static const int _tickAmplitude = 120;
  static const int _firmAmplitude = 200;

  /// Pulse lengths in milliseconds. Anything under about ten reads as a click
  /// rather than a buzz.
  static const int _snapMs = 10;
  static const int _lightTickMs = 12;
  static const int _mediumTickMs = 18;
  static const int _defaultPulseMs = 20;

  /// The swell a long press builds through: five pulses of rising strength,
  /// spaced so they are felt as one gathering press rather than five taps.
  static const List<int> _pressRampAmplitudes = [40, 80, 120, 160, 200];
  static const Duration _pressRampGap = Duration(milliseconds: 40);

  static Future<void> _tryVibrate({
    int duration = _defaultPulseMs,
    int? amplitude,
  }) async {
    if (!isEnabled) return;

    try {
      final bool hasVibrator = await Haptics.hasVibrator();
      if (!hasVibrator) return;
      if (amplitude != null) {
        await Vibration.vibrate(duration: duration, amplitude: amplitude);
      } else {
        await Vibration.vibrate(duration: duration);
      }
    } catch (_) {}
  }

  static Future<void> subtlePress() async {
    for (var i = 0; i < _pressRampAmplitudes.length; i++) {
      if (i > 0) await Future.delayed(_pressRampGap);
      await _tryVibrate(amplitude: _pressRampAmplitudes[i]);
    }
  }

  static Future<void> lightTick() async {
    await _tryVibrate(duration: _lightTickMs, amplitude: _tickAmplitude);
  }

  static Future<void> mediumTick() async {
    await _tryVibrate(duration: _mediumTickMs, amplitude: _firmAmplitude);
  }

  static Future<void> snap({required bool useCustomAmplitude}) async {
    await _tryVibrate(
      duration: _snapMs,
      amplitude: useCustomAmplitude ? _snapAmplitude : null,
    );
  }
}
