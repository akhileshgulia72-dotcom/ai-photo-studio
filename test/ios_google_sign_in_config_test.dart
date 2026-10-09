import 'dart:convert';
import 'dart:io';

import 'package:ai_photo_studio/firebase_options.dart';
import 'package:ai_photo_studio/services/google_sign_in_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS OAuth IDs belong to the configured Firebase project', () {
    expect(
      DefaultFirebaseOptions.ios.iosClientId,
      '516306315147-kevctuachaha9tp2sto6nnv6ivpodpi7.apps.googleusercontent.com',
    );
    expect(
      GoogleSignInConfig.serverClientId,
      '516306315147-afi4ibn72nha03d9j8u3dkkjg5ca49ca.apps.googleusercontent.com',
    );
    expect(
      DefaultFirebaseOptions.ios.projectId,
      DefaultFirebaseOptions.android.projectId,
    );
    expect(
      DefaultFirebaseOptions.ios.iosBundleId,
      'com.agdevelops.ainotescanner',
    );

    final androidConfig = jsonDecode(
      File('android/app/google-services.json').readAsStringSync(),
    );
    final webClientIds = (androidConfig['client'] as List)
        .expand((client) => client['oauth_client'] as List)
        .where((oauthClient) => oauthClient['client_type'] == 3)
        .map((oauthClient) => oauthClient['client_id']);
    expect(webClientIds, contains(GoogleSignInConfig.serverClientId));
  });

  test('Firebase CLI iOS app ID agrees with runtime options', () {
    final config = jsonDecode(File('firebase.json').readAsStringSync());
    final appId =
        config['flutter']['platforms']['dart']['lib/firebase_options.dart']['configurations']['ios'];
    expect(appId, DefaultFirebaseOptions.ios.appId);
  });

  test('Runner registers the reversed iOS OAuth URL scheme', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      plist,
      contains(
        'com.googleusercontent.apps.516306315147-kevctuachaha9tp2sto6nnv6ivpodpi7',
      ),
    );
  });
}
