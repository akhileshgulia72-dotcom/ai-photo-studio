import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/photo_template.dart';

class GenerationException implements Exception {
  const GenerationException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class ImageGenerationService {
  Future<Uri> generateImage({
    required File sourceImage,
    required PhotoTemplate template,
  });
}

/// Sends the image to the authenticated application backend.
/// Provider credentials belong on the server, never in the Flutter app.
/// Configure with --dart-define=GENERATION_API_BASE_URL=https://your-api.example.com
class BackendImageGenerationService implements ImageGenerationService {
  BackendImageGenerationService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl =
          baseUrl ?? const String.fromEnvironment('GENERATION_API_BASE_URL');

  final http.Client _client;
  final String _baseUrl;

  @override
  Future<Uri> generateImage({
    required File sourceImage,
    required PhotoTemplate template,
  }) async {
    if (_baseUrl.trim().isEmpty) {
      throw const GenerationException(
        'Photo generation is not connected yet. Configure the secure generation backend and try again.',
      );
    }
    if (!await sourceImage.exists() || await sourceImage.length() == 0) {
      throw const GenerationException(
        'We could not read that photo. Choose another image and try again.',
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const GenerationException(
        'Your secure session is not ready. Check your connection and try again.',
      );
    }
    final token = await user.getIdToken();
    if (token == null) {
      throw const GenerationException(
        'Your secure session expired. Please try again.',
      );
    }

    final request =
        http.MultipartRequest('POST', Uri.parse('$_baseUrl/v1/generations'))
          ..headers['Authorization'] = 'Bearer $token'
          ..fields['templateId'] = template.id
          ..fields['prompt'] = template.prompt
          ..fields['negativePrompt'] = template.negativePrompt
          ..files.add(
            await http.MultipartFile.fromPath('image', sourceImage.path),
          );

    try {
      final streamed = await _client
          .send(request)
          .timeout(const Duration(minutes: 3));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 402) {
          throw const GenerationException(
            'You need more credits to create this photo.',
          );
        }
        throw const GenerationException(
          'Something went wrong while creating your photo. Your credit was not charged. Try again.',
        );
      }
      final body = jsonDecode(response.body);
      final url = body is Map ? body['outputImageUrl']?.toString() : null;
      final uri = Uri.tryParse(url ?? '');
      if (uri == null || !uri.hasScheme) {
        throw const GenerationException(
          'The server returned an invalid image. Please try again.',
        );
      }
      return uri;
    } on GenerationException {
      rethrow;
    } on SocketException {
      throw const GenerationException(
        'You appear to be offline. Check your connection and try again.',
      );
    } on http.ClientException {
      throw const GenerationException(
        'Could not reach the photo service. Check your connection and try again.',
      );
    } on FormatException {
      throw const GenerationException(
        'The photo service returned an unreadable response. Please try again.',
      );
    } on Exception {
      throw const GenerationException(
        'Photo creation timed out or failed. Your credit was not charged. Try again.',
      );
    }
  }
}
