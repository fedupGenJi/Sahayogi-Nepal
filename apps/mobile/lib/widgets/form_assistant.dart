import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/api.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../core/voice_transcription_config.dart';

class FormAssistantButton extends StatelessWidget {
  const FormAssistantButton({
    super.key,
    required this.formType,
    required this.prompt,
    required this.onApply,
  });

  final String formType;
  final String prompt;
  final ValueChanged<Map<String, dynamic>> onApply;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => _FormAssistantDialog(
              formType: formType,
              prompt: prompt,
              onApply: onApply,
            ),
          ),
          icon: const Icon(Icons.mic_rounded, color: appTeal),
          label: Text(appText('Voice AI help')),
        ),
      );
}

class _FormAssistantDialog extends StatefulWidget {
  const _FormAssistantDialog({
    required this.formType,
    required this.prompt,
    required this.onApply,
  });

  final String formType;
  final String prompt;
  final ValueChanged<Map<String, dynamic>> onApply;

  @override
  State<_FormAssistantDialog> createState() => _FormAssistantDialogState();
}

class _FormAssistantDialogState extends State<_FormAssistantDialog> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final List<Map<String, String>> _conversation = [];
  bool _loading = false;
  bool _listening = false;
  bool _retryFormAssist = false;
  String? _error;
  String? _transcript;

  static const _introByType = <String, String>{
    'resource_request':
        'नमस्कार। कृपया कुन सामग्री चाहिएको हो, कति चाहिएको हो, कति जना प्रभावित हुनुहुन्छ, आफ्नो नाम र सम्पर्क नम्बर बताउनुहोस्।',
    'health':
        'नमस्कार। कृपया कस्तो सहायता चाहिएको हो, कति जना स्वयंसेवक चाहिन्छ, कति जना प्रभावित हुनुहुन्छ, आफ्नो नाम र सम्पर्क नम्बर बताउनुहोस्।',
    'donation_offer':
        'नमस्कार। कृपया तपाईंले दिन सक्ने सामग्री र परिमाण, आफ्नो नाम र सम्पर्क नम्बर बताउनुहोस्।',
  };

  @override
  void initState() {
    super.initState();
    unawaited(_speak(_introByType[widget.formType] ?? _introByType['health']!));
  }

  @override
  void dispose() {
    unawaited(_recorder.dispose());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_listening) {
      await _stopAndFillForm();
      return;
    }
    setState(() {
      _error = null;
      _retryFormAssist = false;
    });
    try {
      if (!VoiceTranscriptionConfig.isConfigured) {
        throw StateError(
          'Add ELEVENLABS_API_KEY and ELEVENLABS_VOICE_ID to apps/mobile/.env, then restart the app.',
        );
      }
      if (!await _recorder.hasPermission()) {
        throw StateError('Microphone permission is required to record your answer.');
      }
      await _player.stop();
      final directory = await getTemporaryDirectory();
      final audioPath = '${directory.path}${Platform.pathSeparator}voice_answer.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: audioPath,
      );
      if (mounted) setState(() => _listening = true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _listening = false;
          _error = _errorMessage(error, 'Could not start recording. Check microphone permission.');
        });
      }
    }
  }

  Future<void> _stopAndFillForm() async {
    setState(() {
      _listening = false;
      _loading = true;
      _error = null;
    });
    String? audioPath;
    String? recognizedText;
    try {
      audioPath = await _recorder.stop();
      if (audioPath == null) throw StateError('The voice recording is empty.');
      recognizedText = await VoiceTranscriptionConfig.transcribe(File(audioPath));
      if (!mounted) return;
      setState(() {
        _transcript = recognizedText;
        _conversation.add({'role': 'user', 'content': recognizedText!});
      });
      await _sendTranscriptToFormAssistant();
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _retryFormAssist = false;
          _error = _errorMessage(error, 'Could not process the recording. Check your connection.');
        });
      }
    } finally {
      if (audioPath != null) {
        try {
          await File(audioPath).delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _sendTranscriptToFormAssistant() async {
    final transcript = _transcript;
    if (transcript == null || transcript.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _retryFormAssist = false;
    });
    final result = await Api.assistForm(
      formType: widget.formType,
      message: transcript,
    );
    if (!mounted) return;
    if (!result.ok || result.data == null || result.data!['suggestions'] is! Map) {
      setState(() {
        _loading = false;
        _retryFormAssist = true;
        _error = result.errorMessage ?? 'Could not prepare form suggestions. Try again.';
      });
      return;
    }

    final suggestions = Map<String, dynamic>.from(result.data!['suggestions'] as Map);
    setState(() {
      _loading = false;
      _conversation.add({
        'role': 'assistant',
        'content': 'फारमका विवरणहरू भरिएका छन्। कृपया जाँच गरेर आवश्यक परे सच्याउनुहोस्।',
      });
    });
    widget.onApply(suggestions);
    await _speak('फारमका विवरणहरू भरिएका छन्। कृपया जाँच गरेर आवश्यक परे सच्याउनुहोस्।');
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _speak(String text) async {
    File? audioFile;
    try {
      final bytes = await VoiceTranscriptionConfig.speakNepali(text);
      final directory = await getTemporaryDirectory();
      audioFile = File('${directory.path}${Platform.pathSeparator}form_assistant.mp3');
      await audioFile.writeAsBytes(bytes, flush: true);
      await _player.setFilePath(audioFile.path);
      await _player.play();
    } catch (error) {
      if (mounted && VoiceTranscriptionConfig.isConfigured) {
        setState(() => _error = _errorMessage(error, 'Nepali voice playback failed.'));
      }
    } finally {
      if (audioFile != null) {
        try {
          await audioFile.delete();
        } catch (_) {}
      }
    }
  }

  String _errorMessage(Object error, String fallback) {
    if (error is StateError || error is HttpException || error is FormatException) {
      return error.toString().replaceFirst('Bad state: ', '');
    }
    return fallback;
  }

  Widget _conversationBubble(Map<String, String> turn) {
    final isAssistant = turn['role'] == 'assistant';
    return Align(
      alignment: isAssistant ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isAssistant ? const Color(0xFFEAF1F4) : appTeal.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(turn['content'] ?? ''),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(appText('Voice AI help')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appText(widget.prompt)),
                const SizedBox(height: 12),
                ..._conversation.map(_conversationBubble),
                const SizedBox(height: 8),
                Center(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _toggleRecording,
                    icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
                    label: Text(appText(_listening ? 'Stop and send' : 'Record answer')),
                    style: FilledButton.styleFrom(
                      backgroundColor: _listening ? Colors.redAccent : appTeal,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ],
                if (_loading) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _loading || _listening ? null : () => Navigator.of(context).pop(),
            child: Text(appText('Cancel')),
          ),
          if (_error != null)
            FilledButton(
              onPressed: _loading
                  ? null
                  : _retryFormAssist
                      ? _sendTranscriptToFormAssistant
                      : _toggleRecording,
              child: Text(appText('Try again')),
            ),
        ],
      );
}
