import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/voice_settings.dart';
import '../services/wake_word_service.dart';

/// Builds a card in the same style as the other Settings cards.
typedef SettingsCardBuilder =
    Widget Function({
      required IconData icon,
      required String title,
      String? subtitle,
      required List<Widget> children,
      required bool isDark,
    });

/// Two extra Settings cards: "Text-to-Speech" and "Hot word".
class VoiceSettingsSection extends StatefulWidget {
  final SettingsCardBuilder buildCard;
  final bool isDark;

  const VoiceSettingsSection({
    super.key,
    required this.buildCard,
    required this.isDark,
  });

  @override
  State<VoiceSettingsSection> createState() => _VoiceSettingsSectionState();
}

class _VoiceSettingsSectionState extends State<VoiceSettingsSection> {
  final FlutterTts _tts = FlutterTts();

  List<String> _engines = [];
  List<String> _languages = [];
  List<Map<String, String>> _voices = [];

  String _engine = ''; // '' = engine default
  String _language = VoiceSettings.defaultLanguage;
  String _voiceName = ''; // '' = automatic
  String _voiceLocale = '';
  double _rate = VoiceSettings.defaultRate;
  double _pitch = VoiceSettings.defaultPitch;
  double _threshold = VoiceSettings.defaultThreshold;
  bool _hotword = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  String _norm(String s) => s.replaceAll('_', '-').toLowerCase();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _engine = prefs.getString(VoiceSettings.keyEngine) ?? '';
    _language =
        prefs.getString(VoiceSettings.keyLanguage) ??
        VoiceSettings.defaultLanguage;
    _voiceName = prefs.getString(VoiceSettings.keyVoiceName) ?? '';
    _voiceLocale = prefs.getString(VoiceSettings.keyVoiceLocale) ?? '';
    _rate = prefs.getDouble(VoiceSettings.keyRate) ?? VoiceSettings.defaultRate;
    _pitch =
        prefs.getDouble(VoiceSettings.keyPitch) ?? VoiceSettings.defaultPitch;
    _threshold =
        prefs.getDouble(VoiceSettings.keyHotwordThreshold) ??
        VoiceSettings.defaultThreshold;
    _hotword =
        WakeWordService.instance.isEnabled ||
        (prefs.getBool(VoiceSettings.keyHotwordEnabled) ?? false);
    await VoiceSettings.loadMuted();
    await _loadLists();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadLists() async {
    if (_engine.isNotEmpty) {
      try {
        await _tts.setEngine(_engine);
      } catch (_) {}
    }
    try {
      final e = await _tts.getEngines;
      _engines = (e as List).map((x) => x.toString()).toList();
    } catch (_) {
      _engines = [];
    }
    try {
      final l = await _tts.getLanguages;
      _languages = (l as List).map((x) => x.toString()).toList()..sort();
    } catch (_) {
      _languages = [];
    }
    try {
      final v = await _tts.getVoices;
      _voices = (v as List).map((x) {
        final m = Map<dynamic, dynamic>.from(x as Map);
        return <String, String>{
          'name': m['name'].toString(),
          'locale': m['locale'].toString(),
        };
      }).toList();
    } catch (_) {
      _voices = [];
    }
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(VoiceSettings.keyEngine, _engine);
    await prefs.setString(VoiceSettings.keyLanguage, _language);
    await prefs.setString(VoiceSettings.keyVoiceName, _voiceName);
    await prefs.setString(VoiceSettings.keyVoiceLocale, _voiceLocale);
    await prefs.setDouble(VoiceSettings.keyRate, _rate);
    await prefs.setDouble(VoiceSettings.keyPitch, _pitch);
    VoiceSettings.notifyTtsChanged();
  }

  Future<void> _preview() async {
    try {
      await _tts.stop();
      if (_engine.isNotEmpty) await _tts.setEngine(_engine);
      await _tts.setLanguage(_language);
      if (_voiceName.isNotEmpty && _voiceLocale.isNotEmpty) {
        await _tts.setVoice({'name': _voiceName, 'locale': _voiceLocale});
      }
      await _tts.setSpeechRate(_rate);
      await _tts.setPitch(_pitch);
      await _tts.setVolume(1.0);
      final isIndonesian = _norm(_language).startsWith('id');
      await _tts.speak(
        isIndonesian
            ? 'Halo, ini adalah tes suara asisten.'
            : 'Hello, this is a test of the assistant voice.',
      );
    } catch (_) {}
  }

  InputDecoration _dec(String label) => InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
  );

  Widget _dropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return InputDecorator(
      decoration: _dec(label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildTtsCard() {
    final engineItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('System default')),
      ..._engines.map((e) => DropdownMenuItem(value: e, child: Text(e))),
    ];
    final engineValue = engineItems.any((i) => i.value == _engine)
        ? _engine
        : '';

    final langList = [..._languages];
    if (!langList.contains(_language)) langList.insert(0, _language);
    final langItems = langList
        .map((l) => DropdownMenuItem(value: l, child: Text(l)))
        .toList();

    final voicesForLang = _voices
        .where((v) => _norm(v['locale'] ?? '') == _norm(_language))
        .toList();
    final voiceItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('Automatic')),
      ...voicesForLang.map(
        (v) => DropdownMenuItem(value: v['name']!, child: Text(v['name']!)),
      ),
    ];
    final voiceValue = voiceItems.any((i) => i.value == _voiceName)
        ? _voiceName
        : '';

    return widget.buildCard(
      icon: Icons.record_voice_over_outlined,
      title: 'Text-to-Speech',
      subtitle: 'Assistant voice engine, language, speed and pitch',
      isDark: widget.isDark,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: VoiceSettings.muted,
          builder: (context, muted, _) => SwitchListTile(
            title: const Text('Mute assistant voice'),
            subtitle: const Text('Replies are shown as text only'),
            value: muted,
            onChanged: (v) => VoiceSettings.setMuted(v),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 8),
        _dropdown(
          label: 'TTS engine',
          value: engineValue,
          items: engineItems,
          onChanged: (v) async {
            setState(() {
              _engine = v ?? '';
              _voiceName = '';
              _voiceLocale = '';
            });
            await _loadLists();
            if (mounted) setState(() {});
            await _savePrefs();
          },
        ),
        const SizedBox(height: 12),
        _dropdown(
          label: 'Language',
          value: _language,
          items: langItems,
          onChanged: (v) async {
            if (v == null) return;
            setState(() {
              _language = v;
              _voiceName = '';
              _voiceLocale = '';
            });
            await _savePrefs();
          },
        ),
        const SizedBox(height: 12),
        _dropdown(
          label: 'Voice',
          value: voiceValue,
          items: voiceItems,
          onChanged: (v) async {
            setState(() {
              _voiceName = v ?? '';
              _voiceLocale = '';
              if (_voiceName.isNotEmpty) {
                final match = voicesForLang.firstWhere(
                  (x) => x['name'] == _voiceName,
                  orElse: () => <String, String>{},
                );
                _voiceLocale = match['locale'] ?? '';
              }
            });
            await _savePrefs();
          },
        ),
        const SizedBox(height: 12),
        Text('Speech rate: ${_rate.toStringAsFixed(2)}'),
        Slider(
          value: _rate,
          min: 0.1,
          max: 1.0,
          divisions: 18,
          onChanged: (v) => setState(() => _rate = v),
          onChangeEnd: (_) => _savePrefs(),
        ),
        Text('Pitch: ${_pitch.toStringAsFixed(2)}'),
        Slider(
          value: _pitch,
          min: 0.5,
          max: 2.0,
          divisions: 15,
          onChanged: (v) => setState(() => _pitch = v),
          onChangeEnd: (_) => _savePrefs(),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _preview,
            icon: const Icon(Icons.volume_up_rounded, size: 18),
            label: const Text('Test voice'),
          ),
        ),
      ],
    );
  }

  Widget _buildHotwordCard() {
    return widget.buildCard(
      icon: Icons.hearing_rounded,
      title: 'Hot word',
      subtitle: 'Say "Hey Jarvis" to start voice input hands-free',
      isDark: widget.isDark,
      children: [
        SwitchListTile(
          title: const Text('Enable "Hey Jarvis"'),
          subtitle: const Text(
            'Listens in the background with a persistent notification. '
            'Uses more battery.',
          ),
          value: _hotword,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) async {
            final prefs = await SharedPreferences.getInstance();
            if (v) {
              final error = await WakeWordService.instance.start();
              if (error != null) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error)));
                }
                await prefs.setBool(VoiceSettings.keyHotwordEnabled, false);
                if (mounted) setState(() => _hotword = false);
                return;
              }
            } else {
              await WakeWordService.instance.stop();
            }
            await prefs.setBool(VoiceSettings.keyHotwordEnabled, v);
            if (mounted) setState(() => _hotword = v);
          },
        ),
        const SizedBox(height: 8),
        Text('Detection threshold: ${_threshold.toStringAsFixed(2)}'),
        const Text(
          'Lower = more sensitive (more false triggers). '
          'Higher = stricter.',
          style: TextStyle(fontSize: 12),
        ),
        Slider(
          value: _threshold,
          min: 0.2,
          max: 0.9,
          divisions: 14,
          onChanged: (v) => setState(() => _threshold = v),
          onChangeEnd: (v) async {
            WakeWordService.instance.threshold = v;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setDouble(VoiceSettings.keyHotwordThreshold, v);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_buildTtsCard(), _buildHotwordCard()],
    );
  }
}
