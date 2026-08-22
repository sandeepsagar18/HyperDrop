import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../identity/domain/models/device_identity.dart';
import '../domain/models/handshake_model.dart';

class HandshakeService {
  final DeviceIdentity identity;
  final StreamController<HandshakeRequest> _incomingRequestsController = StreamController<HandshakeRequest>.broadcast();
  Stream<HandshakeRequest> get incomingRequestsStream => _incomingRequestsController.stream;

  final Map<String, Completer<bool>> _pendingUserApprovals = {};

  HandshakeService({required this.identity});

  Future<HandshakeResponse> initiateHandshake({
    required String targetIp,
    required int targetPort,
    required int totalFiles,
    required int totalSizeBytes,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 1500);

    try {
      final request = await client.post(targetIp, targetPort, '/api/handshake');
      request.headers.contentType = ContentType.json;

      final handshakePayload = HandshakeRequest(
        requestId: 'req_${DateTime.now().millisecondsSinceEpoch}',
        senderDeviceId: identity.deviceId,
        senderDeviceName: identity.deviceName,
        senderDeviceType: identity.deviceType.name,
        senderIp: '0.0.0.0',
        senderPort: identity.httpPort,
        sessionToken: identity.token,
        totalFiles: totalFiles,
        totalSizeBytes: totalSizeBytes,
      );

      request.write(jsonEncode(handshakePayload.toJson()));
      final response = await request.close();

      if (response.statusCode == HttpStatus.ok) {
        final responseBody = await utf8.decodeStream(response);
        final json = jsonDecode(responseBody) as Map<String, dynamic>;
        return HandshakeResponse.fromJson(json);
      } else {
        return HandshakeResponse(
          accepted: false,
          receiverDeviceId: '',
          receiverDeviceName: '',
          rejectionReason: 'HTTP status error ${response.statusCode}',
        );
      }
    } catch (e) {
      return HandshakeResponse(
        accepted: false,
        receiverDeviceId: '',
        receiverDeviceName: '',
        rejectionReason: 'Connection timed out or receiver unreachable ($e)',
      );
    } finally {
      client.close();
    }
  }

  Future<void> handleIncomingHandshakeHttpRequest(HttpRequest request) async {
    try {
      final body = await utf8.decodeStream(request);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final remoteIp = request.connectionInfo?.remoteAddress.address ?? '127.0.0.1';

      final handshakeReq = HandshakeRequest.fromJson(json, remoteIp);

      final completer = Completer<bool>();
      _pendingUserApprovals[handshakeReq.requestId] = completer;

      _incomingRequestsController.add(handshakeReq);

      bool userAccepted = false;
      try {
        userAccepted = await completer.future.timeout(const Duration(seconds: 30));
      } catch (_) {
        userAccepted = false;
      } finally {
        _pendingUserApprovals.remove(handshakeReq.requestId);
      }

      final responseObj = HandshakeResponse(
        accepted: userAccepted,
        receiverDeviceId: identity.deviceId,
        receiverDeviceName: identity.deviceName,
        rejectionReason: userAccepted ? null : 'Transfer request declined by receiver',
        authToken: userAccepted ? identity.token : null,
      );

      request.response
        ..statusCode = userAccepted ? HttpStatus.ok : HttpStatus.forbidden
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(responseObj.toJson()));
      await request.response.close();

    } catch (e) {
      debugPrint('[HANDSHAKE] Error handling handshake: $e');
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write(jsonEncode({'error': e.toString()}));
      await request.response.close();
    }
  }

  void acceptTransfer(String requestId) {
    if (_pendingUserApprovals.containsKey(requestId)) {
      _pendingUserApprovals[requestId]?.complete(true);
    }
  }

  void rejectTransfer(String requestId) {
    if (_pendingUserApprovals.containsKey(requestId)) {
      _pendingUserApprovals[requestId]?.complete(false);
    }
  }

  void dispose() {
    _incomingRequestsController.close();
  }
}
