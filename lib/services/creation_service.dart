import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class SavedCreation {
  const SavedCreation({
    required this.id,
    required this.templateId,
    required this.storagePath,
    required this.createdAt,
    required this.imageUrl,
    required this.creditsUsed,
    required this.watermark,
  });

  final String id;
  final String templateId;
  final String storagePath;
  final DateTime? createdAt;
  final Uri? imageUrl;
  final int creditsUsed;
  final bool watermark;
}

/// Creation history is read through the authenticated backend. This keeps the
/// client independent from the backend's Firestore collection layout and makes
/// the server the authority for which creations belong to the current user.
class CreationService {
  CreationService({FirebaseAuth? auth, http.Client? client})
      : _auth = auth ?? FirebaseAuth.instance,
        _client = client ?? http.Client();

  final FirebaseAuth _auth;
  final http.Client _client;

  Future<String> _token() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Firebase user is not authenticated.');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Firebase ID token is unavailable.');
    }
    return token;
  }

  Future<List<SavedCreation>> fetchMine() async {
    final token = await _token();
    final response = await _client
        .get(
          Uri.parse('$generationApiBaseUrl/v1/my-creations'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw StateError('Could not load creations: HTTP ${response.statusCode}');
    }

    final body = jsonDecode(response.body);
    final items = body is Map ? body['items'] : null;
    if (items is! List) return const <SavedCreation>[];

    final result = <SavedCreation>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final id = raw['id']?.toString() ?? '';
      final templateId = raw['templateId']?.toString() ?? '';
      final storagePath = raw['storagePath']?.toString() ?? '';
      final imageUrlString = raw['imageUrl']?.toString();

      if (id.isEmpty || templateId.isEmpty) continue;
      if (!storagePath.startsWith('users/') ||
          storagePath.contains('..') ||
          storagePath.contains('\\')) {
        continue;
      }

      final createdAt = DateTime.tryParse(raw['createdAt']?.toString() ?? '');
      final credits = (raw['creditsUsed'] as num?)?.toInt() ?? 10;

      result.add(
        SavedCreation(
          id: id,
          templateId: templateId,
          storagePath: storagePath,
          createdAt: createdAt,
          imageUrl: imageUrlString == null
              ? null
              : Uri.tryParse(imageUrlString),
          creditsUsed: credits,
          watermark: raw['watermark'] == true,
        ),
      );
    }
    return result;
  }
}
