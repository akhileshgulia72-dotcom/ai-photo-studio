import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Logs network/adapter outcomes without logging request extras or user data.
void logAdResponseInfo(String source, ResponseInfo? responseInfo) {
  if (responseInfo == null) {
    debugPrint('$source responseInfo=unavailable');
    return;
  }

  final responses =
      responseInfo.adapterResponses ?? const <AdapterResponseInfo>[];
  debugPrint(
    '$source responseId=${responseInfo.responseId ?? 'unavailable'} '
    'loadedAdapter=${responseInfo.loadedAdapterResponseInfo?.adapterClassName ?? 'none'} '
    'adapterCount=${responses.length}',
  );
  for (final response in responses) {
    final error = response.adError;
    debugPrint(
      '$source adapter=${response.adapterClassName} '
      'latency=${response.latencyMillis}ms'
      '${error == null ? '' : ' error=${error.code}/${error.domain}: ${error.message}'}',
    );
  }
}

void logAdFailure(String source, AdError error, {ResponseInfo? responseInfo}) {
  debugPrint(
    '$source failure code=${error.code} domain=${error.domain} '
    'message=${error.message}',
  );
  logAdResponseInfo(source, responseInfo);
}
