import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;

import '../models/photo_template.dart';
import 'api_config.dart';

class GenerationException implements Exception {
  const GenerationException(this.message, {this.insufficientCredits = false});
  final String message;
  final bool insufficientCredits;
  @override
  String toString() => message;
}

class GeneratedImage {
  const GeneratedImage({
    required this.generationId,
    required this.storagePath,
    this.imageUrl,
  });

  final String generationId;
  final String storagePath;
  final Uri? imageUrl;
}

abstract interface class ImageGenerationService {
  Future<GeneratedImage> generateImage({
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
      _baseUrl = baseUrl ?? generationApiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  @override
  Future<GeneratedImage> generateImage({
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
          .timeout(const Duration(minutes: 6));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 402) {
          throw const GenerationException(
            'You need more credits to create this photo.',
            insufficientCredits: true,
          );
        }
        if (response.statusCode == 422) {
          try {
            final body = jsonDecode(response.body);
            final detail = body is Map ? body['detail']?.toString() : null;
            if (detail != null && detail.isNotEmpty) {
              throw GenerationException(detail);
            }
          } on FormatException {
            // Use the generic, non-sensitive message below for malformed errors.
          }
        }
        throw const GenerationException(
          'Something went wrong while creating your photo. Your credit was not charged. Try again.',
        );
      }
      final body = jsonDecode(response.body);
      final generationId = body is Map
          ? body['generationId']?.toString()
          : null;
      final storagePath = body is Map ? body['storagePath']?.toString() : null;
      if (generationId == null || generationId.isEmpty || storagePath == null) {
        throw const GenerationException(
          'The server did not return a valid saved image. Please try again.',
        );
      }
      final expectedPrefix = 'users/${user.uid}/generations/';
      if (!storagePath.startsWith(expectedPrefix) || storagePath.contains('..') || storagePath.contains('\\')) {
        throw const GenerationException(
          'The server did not return a valid saved image. Please try again.',
        );
      }
      Uri? uri;
      try {
        final downloadUrl = await FirebaseStorage.instance
            .ref(storagePath)
            .getDownloadURL();
        uri = Uri.tryParse(downloadUrl);
      } on FirebaseException {
        // The result screen can retry URL resolution from the durable path.
      }
      return GeneratedImage(
        generationId: generationId,
        storagePath: storagePath,
        imageUrl: uri,
      );
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
