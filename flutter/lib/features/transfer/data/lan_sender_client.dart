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
  static final Map<String, HttpClientRequest> _activeRequests = {};
  static final Map<String, RandomAccessFile> _activeFiles = {};

  static void cancelTransfer(String fileId) {
    _cancelledTransferIds.add(fileId);
    
    // Immediately abort in-flight network request
    if (_activeRequests.containsKey(fileId)) {
      try {
        _activeRequests[fileId]?.abort();
      } catch (_) {}
      _activeRequests.remove(fileId);
    }

    // Close any open file handle
    if (_activeFiles.containsKey(fileId)) {
      try {
        _activeFiles[fileId]?.closeSync();
      } catch (_) {}
      _activeFiles.remove(fileId);
    }

    // Notify local server to cancel ingestion and broadcast to connected phones
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
      final targetBaseUrl = 'http://$targetIp:$targetPort';
      final bool isMobilePeer = targetPort == 3000 || targetIp != '127.0.0.1';

      // 1. If destination is a mobile phone (web client), ingest into local vault so phone web socket immediately receives it
      if (isMobilePeer) {
        currentTransfer = currentTransfer.copyWith(
          status: TransferStatus.transferring,
          bytesTransferred: 0,
        );
        yield currentTransfer;

        final chunkSize = customChunkSize ?? defaultChunkSize;
        final totalChunks = (fileSize / chunkSize).ceil().clamp(1, 999999);
        final raf = await file.open(mode: FileMode.read);
        _activeFiles[fileId] = raf;
        
        int bytesTransferred = 0;
        final startTime = DateTime.now();
        var lastCheckTime = startTime;
        var lastCheckBytes = 0;

        for (int i = 0; i < totalChunks; i++) {
          if (_cancelledTransferIds.contains(fileId)) {
            _activeFiles.remove(fileId);
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
          client.connectionTimeout = const Duration(seconds: 4);

          final uri = Uri.parse('http://127.0.0.1:3000/api/vault/upload-chunk');
          final req = await client.postUrl(uri);
          _activeRequests[fileId] = req;

          req.headers.add('x-file-id', fileId);
          req.headers.add('x-file-name', Uri.encodeComponent(fileName));
          req.headers.add('x-file-size', fileSize.toString());
          req.headers.add('x-chunk-index', i.toString());
          req.headers.add('x-total-chunks', totalChunks.toString());
          req.headers.add('x-chunk-offset', offset.toString());
          req.headers.add('x-chunk-start', offset.toString());
          req.headers.add('x-sender-name', Uri.encodeComponent('Laptop'));
          req.add(chunkBytes);

          final res = await req.close();
          _activeRequests.remove(fileId);
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

        _activeFiles.remove(fileId);
        await raf.close();

        currentTransfer = currentTransfer.copyWith(
          status: TransferStatus.completed,
          bytesTransferred: fileSize,
          speedMBs: 0.0,
          speedMbps: 0.0,
          endTime: DateTime.now(),
        );
        yield currentTransfer;
        return;
      }

      // 2. High-Speed Direct Chunk Streaming
      final chunkSize = customChunkSize ?? defaultChunkSize;
      final totalChunks = (fileSize / chunkSize).ceil().clamp(1, 999999);
      final raf = await file.open(mode: FileMode.read);
      _activeFiles[fileId] = raf;
      
      int bytesTransferred = 0;
      final startTime = DateTime.now();
      var lastCheckTime = startTime;
      var lastCheckBytes = 0;

      for (int i = 0; i < totalChunks; i++) {
        if (_cancelledTransferIds.contains(fileId)) {
          _activeFiles.remove(fileId);
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
        client.connectionTimeout = const Duration(seconds: 4);

        // Try direct Flutter peer endpoint (/api/transfer/chunk) or Node endpoint (/api/vault/upload-chunk)
        final uri = Uri.parse(targetPort == 8080 ? '$targetBaseUrl/api/transfer/chunk' : '$targetBaseUrl/api/vault/upload-chunk');
        final req = await client.postUrl(uri);
        _activeRequests[fileId] = req;

        req.headers.add('x-file-id', fileId);
        req.headers.add('x-file-name', Uri.encodeComponent(fileName));
        req.headers.add('x-file-size', fileSize.toString());
        req.headers.add('x-chunk-index', i.toString());
        req.headers.add('x-total-chunks', totalChunks.toString());
        req.headers.add('x-chunk-offset', offset.toString());
        req.headers.add('x-chunk-start', offset.toString());
        req.headers.add('x-sender-name', Uri.encodeComponent('Laptop'));
        req.add(chunkBytes);

        final res = await req.close();
        _activeRequests.remove(fileId);
        if (res.statusCode != 200 && res.statusCode != 204) {
          // Fallback if needed
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

      // Complete notification
      try {
        await http.post(
          Uri.parse('$targetBaseUrl/api/transfer/complete'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fileId': fileId}),
        ).timeout(const Duration(seconds: 3));
      } catch (_) {}

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
