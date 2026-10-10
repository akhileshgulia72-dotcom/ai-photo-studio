import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';

import 'account_profile_service.dart';
import 'api_config.dart';

enum PurchaseEventKind {
  pending,
  cancelled,
  failed,
  verified,
  verificationPending,
  syncComplete,
}

class PurchaseUiEvent {
  const PurchaseUiEvent(
    this.kind, {
    this.message,
    this.creditsAdded = 0,
    this.balance,
    this.duplicate = false,
  });

  final PurchaseEventKind kind;
  final String? message;
  final int creditsAdded;
  final int? balance;
  final bool duplicate;
}

/// Owns the one purchaseStream subscription for the lifetime of the app.
/// Unfinished transactions stay on Apple's queue if server verification fails,
/// so a later stream delivery can retry without granting credits locally.
class IapPurchaseService {
  IapPurchaseService._();

  static final IapPurchaseService instance = IapPurchaseService._();

  static const appleCreatorProductId = 'com.agdevelops.vyro.credits250';
  static const appleProProductId = 'com.agdevelops.vyro.credits800';
  static const playCreatorProductId = 'vyro_creator_150';
  static const playProProductId = 'vyro_pro_500';

  final InAppPurchase _iap = InAppPurchase.instance;
  final StreamController<PurchaseUiEvent> _events =
      StreamController<PurchaseUiEvent>.broadcast();
  final Set<String> _processing = <String>{};
  final Map<String, PurchaseDetails> _deferred = <String, PurchaseDetails>{};
  bool _initialized = false;

  Stream<PurchaseUiEvent> get events => _events.stream;

  bool get isApple => defaultTargetPlatform == TargetPlatform.iOS;

  String get creatorProductId => creatorProductIdFor(apple: isApple);

  String get proProductId => proProductIdFor(apple: isApple);

  int get creatorCredits => creatorCreditsFor(apple: isApple);

  int get proCredits => proCreditsFor(apple: isApple);

  String get storeName => isApple ? 'App Store' : 'Google Play';

  static String creatorProductIdFor({required bool apple}) =>
      apple ? appleCreatorProductId : playCreatorProductId;

  static String proProductIdFor({required bool apple}) =>
      apple ? appleProProductId : playProProductId;

  static int creatorCreditsFor({required bool apple}) => apple ? 250 : 150;

  static int proCreditsFor({required bool apple}) => apple ? 800 : 500;

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    debugPrint('IAP: subscribing to purchase updates');
    _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object error, StackTrace stack) {
        debugPrint('IAP: purchase stream errorType=${error.runtimeType}');
        _events.add(
          const PurchaseUiEvent(
            PurchaseEventKind.failed,
            message: 'Purchase updates could not be read. Please retry.',
          ),
        );
      },
    );
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) unawaited(_retryDeferred());
    });
  }

  Future<ProductDetailsResponse> loadProducts() async {
    final available = await _iap.isAvailable();
    if (!available) {
      throw StateError('$storeName is unavailable on this device.');
    }
    return _iap.queryProductDetails({creatorProductId, proProductId});
  }

  Future<bool> buy(ProductDetails product) async {
    if (!_initialized) initialize();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Sign in before purchasing credit packs.');
    }

    if (isApple) {
      final accountToken = appleAccountToken(user.uid);
      return _iap.buyConsumable(
        purchaseParam: PurchaseParam(
          productDetails: product,
          applicationUserName: accountToken,
        ),
        autoConsume: false,
      );
    }

    // Keep the existing Google Play product ids and purchase API behavior.
    return _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  Future<void> recoverTransactions() async {
    if (!_initialized) initialize();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to sync your purchases.');
    await _iap.restorePurchases(
      applicationUserName: isApple ? appleAccountToken(user.uid) : null,
    );
    await _retryDeferred();
    _events.add(const PurchaseUiEvent(PurchaseEventKind.syncComplete));
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (!_knownProduct(purchase.productID)) continue;
      final key = _transactionKey(purchase);
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _events.add(const PurchaseUiEvent(PurchaseEventKind.pending));
          break;
        case PurchaseStatus.canceled:
          await _completeIfRequired(purchase);
          _events.add(const PurchaseUiEvent(PurchaseEventKind.cancelled));
          break;
        case PurchaseStatus.error:
          await _completeIfRequired(purchase);
          _events.add(
            const PurchaseUiEvent(
              PurchaseEventKind.failed,
              message: 'The store could not complete this purchase.',
            ),
          );
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _deferred[key] = purchase;
          await _processPurchase(key, purchase);
          break;
      }
    }
  }

  bool _knownProduct(String productId) =>
      productId == appleCreatorProductId ||
      productId == appleProProductId ||
      productId == playCreatorProductId ||
      productId == playProProductId;

  String _transactionKey(PurchaseDetails purchase) =>
      purchase.purchaseID ??
      '${purchase.productID}:${purchase.transactionDate ?? 'pending'}';

  Future<void> _processPurchase(String key, PurchaseDetails purchase) async {
    if (_processing.contains(key)) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _events.add(
        const PurchaseUiEvent(
          PurchaseEventKind.verificationPending,
          message: 'Sign in to sync this completed purchase.',
        ),
      );
      return;
    }

    _processing.add(key);
    try {
      final token = await user.getIdToken();
      if (token == null || token.isEmpty) {
        throw StateError('Your secure session expired. Sign in and retry.');
      }
      final response = await _verifyOnServer(purchase, token);
      if (response.statusCode != 200) {
        Object? errorBody;
        try {
          errorBody = jsonDecode(response.body);
        } catch (_) {}
        throw StateError(_verificationError(response, errorBody));
      }

      Map<String, dynamic> body = <String, dynamic>{};
      if (isApple) {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic> ||
            decoded['success'] != true ||
            decoded['productId'] != purchase.productID) {
          throw StateError(_verificationError(response, decoded));
        }
        body = decoded;
      } else {
        // The existing Play flow considered HTTP 200 from its verification
        // endpoint authoritative. Keep that response contract unchanged.
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) body = decoded;
        } catch (_) {}
      }

      // Server confirmed the atomic credit grant (or confirmed it was already
      // granted). Only now acknowledge Apple's transaction.
      await _completeIfRequired(purchase);
      _deferred.remove(key);

      final added = (body['creditsAdded'] as num?)?.toInt() ?? 0;
      final balance = (body['credits'] as num?)?.toInt();
      AccountProfile? refreshedProfile;
      try {
        refreshedProfile = await AccountProfileService.instance.refresh(
          forceTokenRefresh: true,
        );
      } catch (error) {
        debugPrint('IAP: profile refresh failed after server grant');
      }
      final reportedCredits = isApple
          ? added
          : purchase.productID == playCreatorProductId
          ? creatorCredits
          : proCredits;
      _events.add(
        PurchaseUiEvent(
          PurchaseEventKind.verified,
          creditsAdded: isApple ? added : reportedCredits,
          balance: balance ?? refreshedProfile?.credits,
          duplicate: body['duplicate'] == true,
        ),
      );
    } catch (error) {
      debugPrint(
        'IAP: transaction verification failedType=${error.runtimeType}',
      );
      _events.add(
        PurchaseUiEvent(
          PurchaseEventKind.verificationPending,
          message: error is StateError
              ? error.message.toString()
              : 'Purchase verification is pending. Check your connection and retry.',
        ),
      );
      // Keep the transaction unfinished and queued for retry after auth change,
      // app restart, or the user's transaction sync action.
    } finally {
      _processing.remove(key);
    }
  }

  Future<http.Response> _verifyOnServer(
    PurchaseDetails purchase,
    String firebaseToken,
  ) {
    if (isApple) {
      final signedTransaction =
          purchase.verificationData.serverVerificationData;
      if (signedTransaction.isEmpty) {
        throw StateError('Apple did not provide a signed transaction.');
      }
      return http
          .post(
            Uri.parse('$generationApiBaseUrl/v1/iap/apple/verify'),
            headers: {
              'Authorization': 'Bearer $firebaseToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'signedTransactionJws': signedTransaction}),
          )
          .timeout(const Duration(seconds: 45));
    }

    final purchaseToken = purchase.verificationData.serverVerificationData;
    if (purchaseToken.isEmpty) {
      throw StateError('Google Play purchase token is missing.');
    }
    return http
        .post(
          Uri.parse('$generationApiBaseUrl/v1/iap/google/verify'),
          headers: {
            'Authorization': 'Bearer $firebaseToken',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'productId': purchase.productID,
            'purchaseToken': purchaseToken,
          },
        )
        .timeout(const Duration(seconds: 30));
  }

  String _verificationError(http.Response response, Object? body) {
    if (response.statusCode == 503) {
      return 'Secure purchase verification is not configured yet. Your purchase is saved; try again later.';
    }
    if (response.statusCode == 403) {
      return 'This purchase belongs to a different account or is not enabled for this account.';
    }
    if (body is Map && body['detail'] is String) {
      return body['detail'] as String;
    }
    return 'The store could not verify this purchase. Please retry.';
  }

  Future<void> _retryDeferred() async {
    if (_deferred.isEmpty) return;
    for (final entry in _deferred.entries.toList()) {
      await _processPurchase(entry.key, entry.value);
    }
  }

  Future<void> _completeIfRequired(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return;
    try {
      await _iap.completePurchase(purchase);
    } catch (error) {
      debugPrint('IAP: transaction completion failedType=${error.runtimeType}');
    }
  }

  static String appleAccountToken(String uid) {
    final bytes = sha256.convert(utf8.encode('vyro-app-account:$uid')).bytes;
    final value = bytes.sublist(0, 16);
    value[6] = (value[6] & 0x0f) | 0x50;
    value[8] = (value[8] & 0x3f) | 0x80;
    final hex = value
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
