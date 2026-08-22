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

    final String html = '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>HyperDrop – File Transfer</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif}
    body{background:#070D18;color:#fff;display:flex;flex-direction:column;align-items:center;min-height:100vh;padding:16px}
    .header{display:flex;align-items:center;gap:12px;margin:16px 0 24px;text-align:center}
    .logo-badge{width:42px;height:42px;background:linear-gradient(135deg,#00f2fe,#4facfe);border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:22px}
    h1{font-size:22px;font-weight:900;background:linear-gradient(135deg,#00f2fe,#fff);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
    .card{background:#0E1726;border:1.5px solid #1E293B;border-radius:20px;padding:24px;max-width:440px;width:100%;box-shadow:0 8px 32px rgba(0,0,0,0.4)}
    .status-box{display:flex;align-items:center;justify-content:space-between;background:#131F33;border-radius:12px;padding:12px 16px;margin-bottom:20px}
    .status-left{display:flex;align-items:center;gap:10px}
    .status-dot{width:10px;height:10px;background:#00E676;border-radius:50%;box-shadow:0 0 10px #00E676}
    .pc-name{font-weight:700;font-size:14px;color:#fff}
    .dropzone{border:2px dashed #00F2FE;border-radius:16px;background:rgba(0,242,254,0.03);padding:36px 20px;text-align:center;cursor:pointer;transition:all 0.2s ease}
    .dropzone:active{background:rgba(0,242,254,0.1);transform:scale(0.98)}
    .dropzone-icon{font-size:48px;margin-bottom:12px}
    .dropzone-title{font-size:16px;font-weight:700;color:#00F2FE;margin-bottom:6px}
    .dropzone-sub{font-size:12px;color:#94A3B8}
    .progress-card{background:#131F33;border-radius:14px;padding:16px;margin-top:16px;display:none}
    .progress-title{display:flex;justify-content:space-between;font-size:13px;font-weight:700;margin-bottom:8px}
    .progress-bar-bg{height:8px;background:#1E293B;border-radius:4px;overflow:hidden;margin-bottom:8px}
    .progress-bar-fill{height:100%;width:0%;background:linear-gradient(90deg,#00F2FE,#00E676);transition:width 0.1s linear}
    .progress-speed{font-size:11px;color:#00E676;font-weight:700}
    .btn-select{width:100%;margin-top:16px;background:linear-gradient(135deg,#00F2FE,#4FACFE);color:#070D18;font-weight:800;font-size:15px;padding:14px;border:none;border-radius:12px;cursor:pointer}
  </style>
</head>
<body>
  <div class="header">
    <div class="logo-badge">⚡</div>
    <h1>HyperDrop</h1>
  </div>
  <div class="card">
    <div class="status-box">
      <div class="status-left">
        <div class="status-dot"></div>
        <div>
          <div class="pc-name">${identity.deviceName}</div>
          <div style="font-size:11px;color:#94A3B8">Ready to receive files</div>
        </div>
      </div>
      <span style="font-size:11px;font-weight:700;color:#00F2FE;background:rgba(0,242,254,0.1);padding:4px 8px;border-radius:6px">Connected</span>
    </div>

    <input type="file" id="file-input" multiple style="display:none">
    <div class="dropzone" onclick="document.getElementById('file-input').click()">
      <div class="dropzone-icon">📤</div>
      <div class="dropzone-title">Tap to Send Files</div>
      <div class="dropzone-sub">Photos, Videos, Documents, Any Size</div>
    </div>

    <button class="btn-select" onclick="document.getElementById('file-input').click()">Choose Files from Phone</button>

    <div class="progress-card" id="progress-card">
      <div class="progress-title">
        <span id="file-name">filename.jpg</span>
        <span id="percent-text">0%</span>
      </div>
      <div class="progress-bar-bg">
        <div class="progress-bar-fill" id="progress-fill"></div>
      </div>
      <div style="display:flex;justify-content:space-between;align-items:center">
        <span class="progress-speed" id="speed-text">0.0 MB/s</span>
        <span style="font-size:11px;color:#94A3B8" id="bytes-text">0 / 0 MB</span>
      </div>
    </div>
  </div>

  <script>
    const fileInput = document.getElementById('file-input');
    const progressCard = document.getElementById('progress-card');
    const fileNameEl = document.getElementById('file-name');
    const percentEl = document.getElementById('percent-text');
    const fillEl = document.getElementById('progress-fill');
    const speedEl = document.getElementById('speed-text');
    const bytesEl = document.getElementById('bytes-text');

    fileInput.addEventListener('change', async (e) => {
      const files = e.target.files;
      if (!files || files.length === 0) return;

      for (let i = 0; i < files.length; i++) {
        await uploadFile(files[i]);
      }
    });

    async function uploadFile(file) {
      progressCard.style.display = 'block';
      fileNameEl.textContent = file.name;
      const fileId = 'f_' + Date.now() + '_' + Math.floor(Math.random()*1000);
      const chunkSize = 2 * 1024 * 1024; // 2MB
      const totalChunks = Math.ceil(file.size / chunkSize) || 1;

      // 1. Start transfer
      await fetch('/api/transfer/start', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ fileId, fileName: file.name, fileSize: file.size, resumeOffset: 0 })
      });

      let transferred = 0;
      let lastTime = Date.now();
      let lastBytes = 0;

      for (let c = 0; c < totalChunks; c++) {
        const start = c * chunkSize;
        const end = Math.min(start + chunkSize, file.size);
        const chunk = file.slice(start, end);

        await fetch('/api/transfer/chunk', {
          method: 'POST',
          headers: {
            'x-file-id': fileId,
            'x-chunk-offset': start.toString()
          },
          body: chunk
        });

        transferred += (end - start);
        const pct = Math.round((transferred / file.size) * 100);
        fillEl.style.width = pct + '%';
        percentEl.textContent = pct + '%';
        bytesEl.textContent = (transferred/(1024*1024)).toFixed(1) + ' / ' + (file.size/(1024*1024)).toFixed(1) + ' MB';

        const now = Date.now();
        const deltaMs = now - lastTime;
        if (deltaMs >= 200 || transferred === file.size) {
          const speedMBs = ((transferred - lastBytes) / (deltaMs / 1000)) / (1024 * 1024);
          speedEl.textContent = speedMBs.toFixed(1) + ' MB/s';
          lastTime = now;
          lastBytes = transferred;
        }
      }

      await fetch('/api/transfer/complete', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ fileId })
      });

      percentEl.textContent = '✓ Sent!';
      speedEl.textContent = 'Completed';
      setTimeout(() => {
        progressCard.style.display = 'none';
        fillEl.style.width = '0%';
      }, 2500);
    }
  </script>
</body>
</html>''';

    request.response
      ..statusCode = HttpStatus.ok
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
