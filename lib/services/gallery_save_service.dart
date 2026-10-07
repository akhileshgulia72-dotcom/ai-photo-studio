import 'package:flutter/services.dart';

/// Saves an image into the public Pictures/VYRO gallery folder on Android.
class GallerySaveService {
  GallerySaveService._();

  static const _channel = MethodChannel('vyro/gallery');

  static Future<void> save({
    required Uint8List bytes,
    required String fileName,
    String mimeType = 'image/jpeg',
  }) async {
    await _channel.invokeMethod<void>('saveImage', {
      'bytes': bytes,
      'fileName': fileName,
      'mimeType': mimeType,
    });
  }
}
