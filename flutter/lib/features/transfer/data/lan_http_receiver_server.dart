import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../core/utils/checksum_utils.dart';
import '../../identity/domain/models/device_identity.dart';
import '../domain/models/transfer_model.dart';
import 'handshake_service.dart';

class LanHttpReceiverServer {
  final DeviceIdentity identity;
  final HandshakeService handshakeService;
  HttpServer? _server;
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  final StreamController<TransferModel> _incomingTransferProgressController = StreamController<TransferModel>.broadcast();
  Stream<TransferModel> get incomingTransferStream => _incomingTransferProgressController.stream;

  final Map<String, RandomAccessFile> _openFiles = {};
  final Map<String, File> _fileHandles = {};
  final Map<String, int> _fileSizes = {};

  LanHttpReceiverServer({
    required this.identity,
    required this.handshakeService,
  });

  Future<void> startServer() async {
    if (_isRunning) return;

    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        identity.httpPort,
        shared: true,
      );

      _isRunning = true;
      debugPrint('[LAN SERVER] Direct HTTP Receiver listening on port ${identity.httpPort}');

      _server?.listen((HttpRequest request) async {
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        request.response.headers.add('Access-Control-Allow-Headers', '*');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        final path = request.uri.path;

        if (path == '/api/handshake' && request.method == 'POST') {
          await handshakeService.handleIncomingHandshakeHttpRequest(request);
        } else if (path == '/api/transfer/status' && request.method == 'GET') {
          await _handleResumeStatusCheck(request);
        } else if (path == '/api/transfer/start' && request.method == 'POST') {
          await _handleTransferStart(request);
        } else if (path == '/api/transfer/chunk' && request.method == 'POST') {
          await _handleChunkUpload(request);
        } else if (path == '/api/transfer/complete' && request.method == 'POST') {
          await _handleTransferComplete(request);
        } else if (path == '/connect' || path == '/' || path.isEmpty) {
          await _handleBrowserConnect(request);
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('HyperDrop 404');
          await request.response.close();
        }
      });

    } catch (e) {
      debugPrint('[LAN SERVER] Failed to bind HTTP server: $e');
    }
  }

  Future<Directory> _getDownloadsDirectory() async {
    if (Platform.isAndroid) {
      return Directory('/storage/emulated/0/Download/HyperDrop');
    }
    final docDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    return Directory(p.join(docDir.path, 'HyperDrop'));
  }

  Future<void> _handleResumeStatusCheck(HttpRequest request) async {
    final fileId = request.uri.queryParameters['fileId'];
    final fileName = request.uri.queryParameters['fileName'];

    if (fileId == null || fileName == null) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing parameters');
      await request.response.close();
      return;
    }

    final downloadFolder = await _getDownloadsDirectory();
    final targetFile = File(p.join(downloadFolder.path, p.basename(fileName)));

    int existingBytes = 0;
    if (await targetFile.exists()) {
      existingBytes = await targetFile.length();
    }

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'fileId': fileId,
        'existingBytes': existingBytes,
        'canResume': existingBytes > 0,
      }));
    await request.response.close();
  }

  Future<void> _handleTransferStart(HttpRequest request) async {
    try {
      final body = await utf8.decodeStream(request);
      final json = jsonDecode(body) as Map<String, dynamic>;

      final fileId = json['fileId'] as String;
      final fileName = p.basename(json['fileName'] as String);
      final fileSize = (json['fileSize'] as num).toInt();
      final resumeOffset = (json['resumeOffset'] as num?)?.toInt() ?? 0;

      final downloadFolder = await _getDownloadsDirectory();
      if (!await downloadFolder.exists()) {
        await downloadFolder.create(recursive: true);
      }

      final targetFile = File(p.join(downloadFolder.path, fileName));
      final raf = await targetFile.open(mode: resumeOffset > 0 ? FileMode.append : FileMode.write);
      if (resumeOffset == 0) {
        await raf.truncate(fileSize);
      }

      _openFiles[fileId] = raf;
      _fileHandles[fileId] = targetFile;
      _fileSizes[fileId] = fileSize;

      debugPrint('[LAN RECEIVER] Pre-allocated $fileName ($fileSize bytes, resumeOffset: $resumeOffset)');

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'status': 'ready', 'fileId': fileId, 'resumeOffset': resumeOffset}));
      await request.response.close();

    } catch (e) {
      debugPrint('[LAN RECEIVER] Error starting transfer: $e');
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write(jsonEncode({'error': e.toString()}));
      await request.response.close();
    }
  }

  Future<void> _handleChunkUpload(HttpRequest request) async {
    try {
      final fileId = request.headers.value('x-file-id');
      final offsetStr = request.headers.value('x-chunk-offset');

      if (fileId == null || offsetStr == null || !_openFiles.containsKey(fileId)) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('Invalid transfer headers');
        await request.response.close();
        return;
      }

      final offset = int.parse(offsetStr);
      final raf = _openFiles[fileId]!;

      final builder = BytesBuilder(copy: false);
      await for (final data in request) {
        builder.add(data);
      }
      final chunkBytes = builder.takeBytes();

      await raf.setPosition(offset);
      await raf.writeFrom(chunkBytes);

      request.response
        ..statusCode = HttpStatus.ok
        ..write('OK');
      await request.response.close();

    } catch (e) {
      debugPrint('[LAN RECEIVER] Chunk write error: $e');
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('Error');
      await request.response.close();
    }
  }

  Future<void> _handleTransferComplete(HttpRequest request) async {
    try {
      final body = await utf8.decodeStream(request);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final fileId = json['fileId'] as String;
      final expectedChecksum = json['checksum'] as String?;

      bool checksumValid = true;
      if (_openFiles.containsKey(fileId)) {
        final raf = _openFiles.remove(fileId)!;
        await raf.close();

        if (expectedChecksum != null && _fileHandles.containsKey(fileId)) {
          final file = _fileHandles[fileId]!;
          checksumValid = await ChecksumUtils.verifyIntegrity(file, expectedChecksum);
          debugPrint('[LAN RECEIVER] Checksum verification result for $fileId: $checksumValid');
        }
      }

      request.response
        ..statusCode = checksumValid ? HttpStatus.ok : HttpStatus.expectationFailed
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'status': checksumValid ? 'completed' : 'checksum_mismatch',
          'fileId': fileId,
          'verified': checksumValid,
        }));
      await request.response.close();

    } catch (e) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('Error');
      await request.response.close();
    }
  }

  /// Handles GET /connect?token=<token>&name=<deviceName>
  /// Serves a minimal HTML page that phone browsers display after scanning the QR.
  /// Token is validated to ensure only a device with the right pairing token can see the page.
  Future<void> _handleBrowserConnect(HttpRequest request) async {
    final queryToken = request.uri.queryParameters['token'];
    final querySenderName = request.uri.queryParameters['name'] ?? 'Unknown Device';
    final remoteIp = request.connectionInfo?.remoteAddress.address ?? '?';

    final bool tokenValid = queryToken != null && queryToken == identity.token;

    final String html;
    if (tokenValid) {
      debugPrint('[LAN SERVER] QR pairing page opened by $querySenderName ($remoteIp)');
      html = '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>HyperDrop – Paired!</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{background:#070D18;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;min-height:100vh;padding:24px}
    .card{background:#0E1726;border:1.5px solid #00F2FE;border-radius:20px;padding:32px 28px;max-width:380px;width:100%;text-align:center}
    .icon{font-size:52px;margin-bottom:16px}
    h1{font-size:22px;font-weight:900;color:#00F2FE;margin-bottom:8px}
    .sub{color:#94A3B8;font-size:14px;line-height:1.5;margin-bottom:20px}
    .info-row{display:flex;justify-content:space-between;align-items:center;background:#131F33;border-radius:10px;padding:10px 14px;margin-bottom:10px;font-size:13px}
    .info-row span:first-child{color:#64748B}
    .info-row span:last-child{color:#fff;font-weight:700}
    .badge{background:#00E67622;color:#00E676;border-radius:8px;padding:4px 10px;font-size:12px;font-weight:700;display:inline-block;margin-top:8px}
    .step{background:#131F33;border-radius:12px;padding:14px;margin-top:20px;text-align:left}
    .step p{color:#94A3B8;font-size:13px;margin-bottom:6px}
    .step ol{padding-left:18px;color:#CBD5E1;font-size:13px;line-height:1.8}
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">⚡</div>
    <h1>HyperDrop Paired!</h1>
    <p class="sub">Your phone is now connected to this PC over your local network.</p>
    <div class="info-row"><span>Connected PC</span><span>${identity.deviceName}</span></div>
    <div class="info-row"><span>Your Device</span><span>$querySenderName</span></div>
    <div class="info-row"><span>PC IP</span><span>$remoteIp ← you</span></div>
    <div class="info-row"><span>Transfer Port</span><span>${identity.httpPort}</span></div>
    <span class="badge">✓ Secure LAN Session Active</span>
    <div class="step">
      <p><strong style="color:#00F2FE">Next steps:</strong></p>
      <ol>
        <li>Open HyperDrop on your phone</li>
        <li>This PC will appear in "Nearby Devices"</li>
        <li>Tap it and send files at full LAN speed</li>
      </ol>
    </div>
  </div>
</body>
</html>''';
    } else {
      debugPrint('[LAN SERVER] QR connect attempt with invalid token from $remoteIp');
      html = '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>HyperDrop – Invalid Token</title>
  <style>
    body{background:#070D18;font-family:-apple-system,sans-serif;color:#fff;display:flex;align-items:center;justify-content:center;min-height:100vh}
    .card{background:#0E1726;border:1.5px solid #FF5252;border-radius:20px;padding:32px;max-width:360px;width:100%;text-align:center}
    h1{color:#FF5252;font-size:20px;margin-bottom:12px}
    p{color:#94A3B8;font-size:14px}
  </style>
</head>
<body>
  <div class="card">
    <h1>⚠ Invalid or Expired QR</h1>
    <p>This QR code is no longer valid. Please generate a new QR from the HyperDrop app on the PC.</p>
  </div>
</body>
</html>''';
    }

    request.response
      ..statusCode = tokenValid ? HttpStatus.ok : HttpStatus.forbidden
      ..headers.contentType = ContentType.html
      ..write(html);
    await request.response.close();
  }

  void stop() {
    _server?.close(force: true);
    _server = null;
    _isRunning = false;
  }
}
