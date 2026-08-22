import 'dart:io';
import 'package:crypto/crypto.dart';

class ChecksumUtils {
  /// Computes SHA-256 hash using stream processing (0-RAM memory buffering)
  static Future<String> computeSha256(File file) async {
    final stream = file.openRead();
    final digest = await sha256.bind(stream).first;
    return digest.toString();
  }

  /// Verifies file integrity against expected hash
  static Future<bool> verifyIntegrity(File file, String expectedChecksum) async {
    try {
      final actualChecksum = await computeSha256(file);
      return actualChecksum.toLowerCase() == expectedChecksum.toLowerCase();
    } catch (_) {
      return false;
    }
  }
}
