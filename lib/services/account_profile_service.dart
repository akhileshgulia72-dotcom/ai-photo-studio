import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class AccountProfile {
  const AccountProfile({
    required this.credits,
    required this.plan,
    this.totalGenerations = 0,
  });
  final int credits;
  final String plan;
  final int totalGenerations;
  bool get isAdFree =>
      plan.toLowerCase() == 'creator' ||
      plan.toLowerCase() == 'pro' ||
      plan.toLowerCase() == 'premium';
  bool get hasNoWatermark => plan.toLowerCase() != 'free';
  factory AccountProfile.fromJson(Map<String, dynamic> json) => AccountProfile(
    credits: (json['credits'] as num?)?.toInt() ?? 0,
    plan: json['plan']?.toString() ?? 'free',
    totalGenerations: (json['totalGenerations'] as num?)?.toInt() ?? 0,
  );
}

/// Single authenticated profile fetch path. The backend is always authoritative.
class AccountProfileService {
  AccountProfileService._();
  static final AccountProfileService instance = AccountProfileService._();
  AccountProfile? _cached;
  String? _cachedUid;
  AccountProfile? get cached =>
      _cachedUid == FirebaseAuth.instance.currentUser?.uid ? _cached : null;

  Future<AccountProfile> refresh({bool forceTokenRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Firebase user is not authenticated.');
    final token = await user.getIdToken(forceTokenRefresh);
    if (token == null || token.isEmpty) {
      throw StateError('Firebase ID token is unavailable.');
    }
    final response = await http
        .get(
          Uri.parse('$generationApiBaseUrl/v1/profile'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Profile request failed: HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Invalid profile response.');
    }
    _cachedUid = user.uid;
    return _cached = AccountProfile.fromJson(body);
  }
}
