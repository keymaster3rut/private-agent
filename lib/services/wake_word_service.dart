import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:open_wake_word/open_wake_word.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'voice_settings.dart';

/// Entry point of the foreground-service isolate. It only forwards the
/// notification's Mute/Unmute button press to the main isolate.
@pragma('vm:entry-point')
void wakeWordForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_WakeWordTaskHandler());
}

class _WakeWordTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'toggle_mute') {
      FlutterForegroundTask.sendDataToMain('toggle_mute');
    }
  }
}

/// Always-listening "Hey Jarvis" hot word (openWakeWord, fully on-device).
///
/// While enabled it keeps a foreground service (persistent notification with
/// a Mute/Unmute button) so detection also works with the screen off or while
/// another app is open. When the hot word is heard, [onWake] is called and the
/// app's existing voice input takes over.
class WakeWordService {
  WakeWordService._();
  static final WakeWordService instance = WakeWordService._();

  // Model files that must be present in assets/models/
  static const String _melAsset = 'assets/models/melspectrogram.onnx';
  static const String _embAsset = 'assets/models/embedding_model.onnx';
  static const String _wakeAsset = 'assets/models/hey_jarvis_v0.1.onnx';

  static const int _chunkSamples = 1280; // 80 ms @ 16 kHz

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSub;
  Timer? _pollTimer;
  Timer? _resumeTimer;
  final List<int> _buffer = <int>[];
  Future<void> _queue = Future<void>.value();

  bool _engineReady = false;
  bool _enabled = false;
  bool _capturing = false;
  bool _wasActive = false;
  bool _listenersAttached = false;
  DateTime _lastTrigger = DateTime.fromMillisecondsSinceEpoch(0);

  /// Detection threshold (0..1). Lower = more sensitive.
  double threshold = VoiceSettings.defaultThreshold;

  /// Called when the hot word is detected.
  VoidCallback? onWake;

  /// True while the hot word is enabled.
  final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  bool get isEnabled => _enabled;

  Future<void> _run(Future<void> Function() action) {
    final next = _queue.then((_) => action()).catchError((_) {});
    _queue = next;
    return next;
  }

  /// Starts the hot word. Returns an error message, or null on success.
  Future<String?> start() async {
    if (_enabled) return null;

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      return 'Microphone permission is required for the hot word.';
    }
    try {
      await Permission.notification.request();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    threshold =
        prefs.getDouble(VoiceSettings.keyHotwordThreshold) ??
        VoiceSettings.defaultThreshold;

    if (!_engineReady) {
      try {
        _engineReady = await OpenWakeWord.init(
          melModelAssetPath: _melAsset,
          embModelAssetPath: _embAsset,
          wwModelAssetPaths: [_wakeAsset],
        );
      } catch (_) {
        _engineReady = false;
      }
      if (!_engineReady) {
        return 'Hot word model files could not be loaded. Make sure '
            'melspectrogram.onnx, embedding_model.onnx and '
            'hey_jarvis_v0.1.onnx are in assets/models/.';
      }
    }

    _enabled = true;
    active.value = true;

    _initForegroundTask();
    await _showServiceNotification();

    if (!_listenersAttached) {
      _listenersAttached = true;
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);
      VoiceSettings.muted.addListener(_onMuteChanged);
      VoiceSettings.listening.addListener(_onBusyChanged);
      VoiceSettings.speaking.addListener(_onBusyChanged);
    }
    VoiceSettings.beforeListen = () => _run(_endCapture);

    await _run(_beginCapture);
    return null;
  }

  Future<void> stop() async {
    if (!_enabled) return;
    _enabled = false;
    active.value = false;
    VoiceSettings.beforeListen = null;
    _resumeTimer?.cancel();

    if (_listenersAttached) {
      _listenersAttached = false;
      FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
      VoiceSettings.muted.removeListener(_onMuteChanged);
      VoiceSettings.listening.removeListener(_onBusyChanged);
      VoiceSettings.speaking.removeListener(_onBusyChanged);
    }

    await _run(_endCapture);
    try {
      OpenWakeWord.destroy();
    } catch (_) {}
    _engineReady = false;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Foreground service / notification
  // ---------------------------------------------------------------------------

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'private_agent_hotword',
        channelName: 'Hot word',
        channelDescription: 'Shown while the Hey Jarvis hot word is active.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  List<NotificationButton> _buttons() => [
    NotificationButton(
      id: 'toggle_mute',
      text: VoiceSettings.muted.value ? 'Unmute' : 'Mute',
    ),
  ];

  String _notificationText() => VoiceSettings.muted.value
      ? 'Assistant voice is muted'
      : 'Say "Hey Jarvis" to start';

  Future<void> _showServiceNotification() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'PrivateAgent - hot word active',
        notificationText: _notificationText(),
        notificationButtons: _buttons(),
      );
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: 7401,
      notificationTitle: 'PrivateAgent - hot word active',
      notificationText: _notificationText(),
      notificationButtons: _buttons(),
      callback: wakeWordForegroundCallback,
    );
  }

  void _onTaskData(Object data) {
    if (data == 'toggle_mute') {
      VoiceSettings.setMuted(!VoiceSettings.muted.value);
    }
  }

  void _onMuteChanged() {
    if (!_enabled) return;
    FlutterForegroundTask.updateService(
      notificationTitle: 'PrivateAgent - hot word active',
      notificationText: _notificationText(),
      notificationButtons: _buttons(),
    );
  }

  // ---------------------------------------------------------------------------
  // Microphone capture (paused while the app listens or speaks)
  // ---------------------------------------------------------------------------

  void _onBusyChanged() {
    if (!_enabled) return;
    _resumeTimer?.cancel();
    final busy = VoiceSettings.listening.value || VoiceSettings.speaking.value;
    if (busy) {
      _run(_endCapture);
    } else {
      // Small delay so the tail of the assistant's own voice is not heard.
      _resumeTimer = Timer(const Duration(milliseconds: 700), () {
        if (_enabled &&
            !VoiceSettings.listening.value &&
            !VoiceSettings.speaking.value) {
          _run(_beginCapture);
        }
      });
    }
  }

  Future<void> _beginCapture() async {
    if (_capturing || !_enabled) return;
    if (VoiceSettings.listening.value || VoiceSettings.speaking.value) return;
    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _capturing = true;
      _buffer.clear();
      _wasActive = false;
      _audioSub = stream.listen(_onAudio, onError: (Object _) {});
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _poll(),
      );
    } catch (_) {
      _capturing = false;
    }
  }

  Future<void> _endCapture() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _audioSub?.cancel();
    _audioSub = null;
    if (_capturing) {
      try {
        await _recorder.stop();
      } catch (_) {}
    }
    _capturing = false;
    _buffer.clear();
    _wasActive = false;
  }

  void _onAudio(Uint8List bytes) {
    final samples = bytes.length ~/ 2;
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < samples; i++) {
      _buffer.add(view.getInt16(i * 2, Endian.little));
    }
    while (_buffer.length >= _chunkSamples) {
      final chunk = Int16List.fromList(_buffer.sublist(0, _chunkSamples));
      _buffer.removeRange(0, _chunkSamples);
      OpenWakeWord.processAudio(chunk);
    }
  }

  void _poll() {
    if (!_capturing || !_engineReady) return;
    final hit = OpenWakeWord.getProbability() >= threshold;
    if (hit &&
        !_wasActive &&
        DateTime.now().difference(_lastTrigger) >
            const Duration(seconds: 3)) {
      _lastTrigger = DateTime.now();
      HapticFeedback.mediumImpact();
      onWake?.call();
    }
    _wasActive = hit;
  }
}
