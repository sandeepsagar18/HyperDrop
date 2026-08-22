import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/utils/checksum_utils.dart';
import '../domain/models/transfer_model.dart';

class LanSenderClient {
  static const int defaultChunkSize = 2 * 1024 * 1024; // 2MB chunk
  static final Set<String> _cancelledTransferIds = {};

  static void cancelTransfer(String fileId) {
    _cancelledTransferIds.add(fileId);
    // Notify server to drop chunk ingestion immediately
    try {
      http.post(Uri.parse('http://127.0.0.1:3000/api/transfer/cancel/$fileId'));
    } catch (_) {}
  }

  /// High-speed non-blocking stream sender with live chunk progress updates, speed metrics, and authorization support
  static Stream<TransferModel> sendFile({
    required File file,
    required String targetIp,
    required int targetPort,
    required String targetDeviceName,
    int? customChunkSize,
    bool enableChecksum = true,
  }) async* {
    final fileSize = await file.length();
    final fileName = file.path.split(Platform.pathSeparator).last;
    final fileId = 'f_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
    _cancelledTransferIds.remove(fileId);

    var currentTransfer = TransferModel(
      transferId: fileId,
      fileName: fileName,
      filePath: file.path,
      fileSize: fileSize,
      direction: TransferDirection.outgoing,
      peerName: targetDeviceName,
      peerIp: targetIp,
      status: TransferStatus.connecting,
    );
    yield currentTransfer;

    try {
      // 1. Send authorization / handshake request to phone receiver
      try {
        final authReq = await http.post(
          Uri.parse('http://127.0.0.1:3000/api/transfer/request'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'fileId': fileId,
            'fileName': fileName,
            'fileSize': fileSize,
            'senderName': 'Laptop',
            'targetPeerIp': targetIp,
          }),
        ).timeout(const Duration(seconds: 4));
        
        if (authReq.statusCode == 200) {
          final authData = jsonDecode(authReq.body);
          if (authData['accepted'] == false) {
            currentTransfer = currentTransfer.copyWith(
              status: TransferStatus.failed,
              errorMessage: 'Receiver declined the transfer request.',
            );
            yield currentTransfer;
            return;
          }
        }
      } catch (_) {
        // If auth endpoint not blocking, proceed with high-speed streaming
      }

      currentTransfer = currentTransfer.copyWith(
        status: TransferStatus.transferring,
        bytesTransferred: 0,
      );
      yield currentTransfer;

      // 2. High-Speed Chunk Streaming with Live Gauge & Speedometer metrics
      final chunkSize = customChunkSize ?? defaultChunkSize;
      final totalChunks = (fileSize / chunkSize).ceil().clamp(1, 999999);
      final raf = await file.open(mode: FileMode.read);
      
      int bytesTransferred = 0;
      final startTime = DateTime.now();
      var lastCheckTime = startTime;
      var lastCheckBytes = 0;

      for (int i = 0; i < totalChunks; i++) {
        if (_cancelledTransferIds.contains(fileId)) {
          await raf.close();
          currentTransfer = currentTransfer.copyWith(
            status: TransferStatus.cancelled,
            speedMBs: 0.0,
            speedMbps: 0.0,
            errorMessage: 'Transfer cancelled by user',
            endTime: DateTime.now(),
          );
          yield currentTransfer;
          return;
        }

        final offset = i * chunkSize;
        final end = min(offset + chunkSize, fileSize);
        final currentChunkLen = end - offset;

        await raf.setPosition(offset);
        final chunkBytes = await raf.read(currentChunkLen);

        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 3);

        final req = await client.postUrl(Uri.parse('http://127.0.0.1:3000/api/vault/upload-chunk'));
        req.headers.add('x-file-id', fileId);
        req.headers.add('x-file-name', Uri.encodeComponent(fileName));
        req.headers.add('x-file-size', fileSize.toString());
        req.headers.add('x-chunk-index', i.toString());
        req.headers.add('x-total-chunks', totalChunks.toString());
        req.headers.add('x-chunk-start', offset.toString());
        req.headers.add('x-sender-name', Uri.encodeComponent('Laptop'));
        req.add(chunkBytes);

        final res = await req.close();
        if (res.statusCode != 200) {
          // Fallback to direct upload if chunking error
          break;
        }

        bytesTransferred += currentChunkLen;

        final now = DateTime.now();
        final deltaMs = now.difference(lastCheckTime).inMilliseconds;
        if (deltaMs >= 100 || bytesTransferred == fileSize) {
          final deltaBytes = bytesTransferred - lastCheckBytes;
          final speedBytesPerSec = deltaMs > 0 ? (deltaBytes / (deltaMs / 1000.0)) : 0.0;
          final speedMBs = speedBytesPerSec / (1024 * 1024);
          final speedMbps = speedMBs * 8;
          final remBytes = fileSize - bytesTransferred;
          final etaSec = speedBytesPerSec > 0 ? (remBytes / speedBytesPerSec).ceil() : 0;

          currentTransfer = currentTransfer.copyWith(
            bytesTransferred: bytesTransferred,
            speedMBs: speedMBs,
            speedMbps: speedMbps,
            etaSeconds: etaSec,
          );
          yield currentTransfer;

          lastCheckTime = now;
          lastCheckBytes = bytesTransferred;
        }
      }

      await raf.close();

      // If chunks were not all processed or small file, perform direct finalization
      if (bytesTransferred < fileSize) {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('http://127.0.0.1:3000/api/vault/direct-upload'),
        );
        request.fields['senderName'] = 'Laptop (Desktop App)';
        request.files.add(await http.MultipartFile.fromPath('file', file.path));
        await request.send();
      }

      final totalSec = max(DateTime.now().difference(startTime).inMilliseconds / 1000.0, 0.1);

      currentTransfer = currentTransfer.copyWith(
        status: TransferStatus.completed,
        bytesTransferred: fileSize,
        speedMBs: 0.0,
        speedMbps: 0.0,
        endTime: DateTime.now(), // freeze timer here
      );
      yield currentTransfer;
    } catch (e) {
      debugPrint('[LAN SENDER] Error sending file: $e');
      currentTransfer = currentTransfer.copyWith(
        status: TransferStatus.failed,
        errorMessage: e.toString(),
        endTime: DateTime.now(), // freeze timer here
      );
      yield currentTransfer;
    }
  }
}
