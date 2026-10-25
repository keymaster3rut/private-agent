import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'voice_settings.dart';

class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;
  bool _isListening = false;
  bool _listenersAttached = false;

  bool get isListening => _isListening;

  Future<void> init() async {
    if (_isInitialized) return;

    _isInitialized = await _speech.initialize(
      onError: (error) {
        _isListening = false;
        VoiceSettings.listening.value = false;
      },
      onStatus: (status) {
        // Added: lets the hot word resume when listening ends silently.
        if (status == 'done' || status == 'notListening') {
          VoiceSettings.listening.value = false;
        }
      },
    );

    // Configure TTS (defaults identical to the original app)
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    // --- Added: saved TTS options, mute, speaking state ---
    await VoiceSettings.loadMuted();
    _tts.setStartHandler(() => VoiceSettings.speaking.value = true);
    _tts.setCompletionHandler(() => VoiceSettings.speaking.value = false);
    _tts.setCancelHandler(() => VoiceSettings.speaking.value = false);
    _tts.setErrorHandler((message) => VoiceSettings.speaking.value = false);
    await _applySavedTtsSettings();
    if (!_listenersAttached) {
      _listenersAttached = true;
      VoiceSettings.muted.addListener(_onMuteChanged);
      VoiceSettings.ttsRevision.addListener(_onTtsChanged);
    }
  }

  /// Applies the TTS options saved from Settings. With nothing saved this
  /// leaves the original defaults (en-US, rate 0.5, pitch 1.0) untouched.
  Future<void> _applySavedTtsSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final engine = prefs.getString(VoiceSettings.keyEngine);
    if (engine != null && engine.isNotEmpty) {
      try {
        await _tts.setEngine(engine);
      } catch (_) {}
    }

    final language =
        prefs.getString(VoiceSettings.keyLanguage) ??
        VoiceSettings.defaultLanguage;
    try {
      await _tts.setLanguage(language);
    } catch (_) {}

    final voiceName = prefs.getString(VoiceSettings.keyVoiceName);
    final voiceLocale = prefs.getString(VoiceSettings.keyVoiceLocale);
    if (voiceName != null && voiceLocale != null) {
      try {
        await _tts.setVoice({'name': voiceName, 'locale': voiceLocale});
      } catch (_) {}
    }

    await _tts.setSpeechRate(
      prefs.getDouble(VoiceSettings.keyRate) ?? VoiceSettings.defaultRate,
    );
    await _tts.setPitch(
      prefs.getDouble(VoiceSettings.keyPitch) ?? VoiceSettings.defaultPitch,
    );
    await _tts.setVolume(1.0);
  }

  void _onTtsChanged() {
    _applySavedTtsSettings();
  }

  void _onMuteChanged() {
    if (VoiceSettings.muted.value) {
      _tts.stop();
      VoiceSettings.speaking.value = false;
    }
  }

  /// Start listening for speech. Returns transcribed text via callback.
  Future<void> startListening({
    required Function(String) onResult,
    required Function() onDone,
  }) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return;

    _isListening = true;
    VoiceSettings.listening.value = true;

    // Added: make sure the hot word has released the microphone.
    final release = VoiceSettings.beforeListen;
    if (release != null) {
      try {
        await release();
      } catch (_) {}
    }

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        if (result.finalResult) {
          _isListening = false;
          VoiceSettings.listening.value = false;
          onResult(result.recognizedWords);
          onDone();
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.confirmation,
        partialResults: false,
      ),
    );
  }

  /// Stop listening
  Future<void> stopListening() async {
    _isListening = false;
    VoiceSettings.listening.value = false;
    await _speech.stop();
  }

  /// Speak text aloud (silent while muted)
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    if (VoiceSettings.muted.value) return;
    await _tts.speak(text);
  }

  /// Stop speaking
  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  void dispose() {
    if (_listenersAttached) {
      VoiceSettings.muted.removeListener(_onMuteChanged);
      VoiceSettings.ttsRevision.removeListener(_onTtsChanged);
      _listenersAttached = false;
    }
    _speech.stop();
    _tts.stop();
  }
}
