import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// State and preference keys shared by the added voice features:
/// TTS options, mute, and the "Hey Jarvis" hot word.
class VoiceSettings {
  VoiceSettings._();

  // SharedPreferences keys
  static const keyEngine = 'tts_engine';
  static const keyLanguage = 'tts_language';
  static const keyVoiceName = 'tts_voice_name';
  static const keyVoiceLocale = 'tts_voice_locale';
  static const keyRate = 'tts_rate';
  static const keyPitch = 'tts_pitch';
  static const keyMuted = 'tts_muted';
  static const keyHotwordEnabled = 'hotword_enabled';
  static const keyHotwordThreshold = 'hotword_threshold';

  // Defaults = the exact values the original app hard-coded in VoiceService.
  static const String defaultLanguage = 'en-US';
  static const double defaultRate = 0.5;
  static const double defaultPitch = 1.0;
  static const double defaultThreshold = 0.5;

  /// Assistant voice muted (TTS silent).
  static final ValueNotifier<bool> muted = ValueNotifier<bool>(false);

  /// TTS is currently speaking.
  static final ValueNotifier<bool> speaking = ValueNotifier<bool>(false);

  /// The app's own speech-to-text is currently listening.
  static final ValueNotifier<bool> listening = ValueNotifier<bool>(false);

  /// Bumped when TTS options are saved, so VoiceService re-applies them.
  static final ValueNotifier<int> ttsRevision = ValueNotifier<int>(0);

  /// Set by the hot word service: releases the microphone before the
  /// app's speech-to-text starts listening.
  static Future<void> Function()? beforeListen;

  static Future<void> loadMuted() async {
    final prefs = await SharedPreferences.getInstance();
    muted.value = prefs.getBool(keyMuted) ?? false;
  }

  static Future<void> setMuted(bool value) async {
    muted.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyMuted, value);
  }

  static void notifyTtsChanged() {
    ttsRevision.value = ttsRevision.value + 1;
  }
}
