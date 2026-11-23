import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// ElevenLabs speech services used by the mobile form assistant.
class VoiceTranscriptionConfig {
  static const _speechToTextUrl =
      'https://api.elevenlabs.io/v1/speech-to-text';
  static const _textToSpeechUrl =
      'https://api.elevenlabs.io/v1/text-to-speech';

  static String get apiKey => dotenv.env['ELEVENLABS_API_KEY']?.trim() ?? '';
  static String get voiceId => dotenv.env['ELEVENLABS_VOICE_ID']?.trim() ?? '';

  static bool get isConfigured =>
      apiKey.isNotEmpty &&
      !apiKey.contains('YOUR_') &&
      voiceId.isNotEmpty &&
      !voiceId.contains('YOUR_');

  static Future<String> transcribe(File audioFile) async {
    if (apiKey.isEmpty || apiKey.contains('YOUR_')) {
      throw StateError('Add ELEVENLABS_API_KEY to apps/mobile/.env.');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse(_speechToTextUrl),
    )
      ..headers['xi-api-key'] = apiKey
      ..fields['model_id'] = 'scribe_v3'
      ..fields['language_code'] = 'nep'
      ..fields['numbers_format'] = 'digits'
      ..fields['tag_audio_events'] = 'false'
      ..fields['diarize'] = 'false'
      ..fields['transcript_edit'] =
          'Translate this Nepali speech into concise English for filling a '
          'disaster relief request form. Preserve names using Latin script. '
          'Write phone numbers and quantities with Western digits. Keep the '
          'meaning and do not add details.'
      ..files.add(await http.MultipartFile.fromPath('file', audioFile.path));

    final streamed = await request.send().timeout(const Duration(seconds: 90));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'ElevenLabs transcription failed (${response.statusCode}): '
        '${_responseError(response.body)}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('ElevenLabs returned an unexpected transcript.');
    }
    final transcript = (decoded['edited_transcript'] ?? decoded['text'])
        ?.toString()
        .trim();
    if (transcript == null || transcript.isEmpty) {
      throw const FormatException('No speech was recognized.');
    }
    return transcript;
  }

  static Future<List<int>> speakNepali(String text) async {
    if (apiKey.isEmpty || apiKey.contains('YOUR_')) {
      throw StateError('Add ELEVENLABS_API_KEY to apps/mobile/.env.');
    }
    if (voiceId.isEmpty || voiceId.contains('YOUR_')) {
      throw StateError('Add ELEVENLABS_VOICE_ID to apps/mobile/.env.');
    }

    final endpoint = Uri.parse(_textToSpeechUrl);
    final uri = endpoint.replace(
      pathSegments: [...endpoint.pathSegments, voiceId],
      queryParameters: {'output_format': 'mp3_44100_128'},
    );
    final response = await http
        .post(
          uri,
          headers: {
            'xi-api-key': apiKey,
            'Content-Type': 'application/json',
            'Accept': 'audio/mpeg',
          },
          body: jsonEncode({
            'text': text,
            'model_id': 'eleven_v3',
            'language_code': 'ne',
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'ElevenLabs speech generation failed (${response.statusCode}): '
        '${_responseError(response.body)}',
      );
    }
    if (response.bodyBytes.isEmpty) {
      throw const FormatException('ElevenLabs returned empty speech audio.');
    }
    return response.bodyBytes;
  }

  static String _responseError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final detail = decoded['detail'];
        if (detail is Map) {
          final message = detail['message'] ?? detail['status'];
          if (message != null) return message.toString();
        }
        if (detail is String) return detail;
        if (decoded['message'] != null) return decoded['message'].toString();
      }
    } catch (_) {
      // Keep a short plain-text API error if the response is not JSON.
    }
    final trimmed = body.trim();
    if (trimmed.isEmpty) return 'The API returned no error details.';
    return trimmed.length > 400 ? '${trimmed.substring(0, 400)}…' : trimmed;
  }

}
