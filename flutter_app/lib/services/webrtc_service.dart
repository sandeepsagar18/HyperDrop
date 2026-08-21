import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/peer_device.dart';

class WebRtcService {
  WebSocketChannel? _wsChannel;
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, RTCDataChannel> _dataChannels = {};

  final String signalingServerUrl;
  final String deviceId;
  final String deviceName;
  final String deviceType;

  final StreamController<PeerDevice> _remotePeerController = StreamController<PeerDevice>.broadcast();
  Stream<PeerDevice> get remotePeerStream => _remotePeerController.stream;

  final StreamController<Map<String, dynamic>> _incomingDataController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get incomingDataStream => _incomingDataController.stream;

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:global.stun.twilio.com:3478'},
    ]
  };

  WebRtcService({
    required this.signalingServerUrl,
    required this.deviceId,
    required this.deviceName,
    this.deviceType = 'phone',
  });

  void connectSignaling() {
    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(signalingServerUrl));
      _wsChannel?.stream.listen((message) {
        _handleSignalingMessage(message);
      }, onError: (err) {
        debugPrint('[WebRTC] Signaling error: $err');
      });
      debugPrint('[WebRTC] Connected to signaling: $signalingServerUrl');
    } catch (e) {
      debugPrint('[WebRTC] Could not connect to signaling: $e');
    }
  }

  void _handleSignalingMessage(dynamic rawMsg) {
    try {
      final msg = jsonDecode(rawMsg as String) as Map<String, dynamic>;
      final type = msg['type'] as String?;
      final data = msg['data'] as Map<String, dynamic>?;

      switch (type) {
        case 'remote_session_created':
          debugPrint('[WebRTC] Room Created: ${data?['shortCode']}');
          break;
        case 'peer_paired':
          final remotePeer = PeerDevice(
            id: data?['guestId'] ?? data?['hostId'] ?? '',
            name: data?['guestName'] ?? data?['hostName'] ?? 'Remote Device',
            type: data?['guestType'] ?? data?['hostType'] ?? 'phone',
            ip: 'WebRTC Remote',
            isRemote: true,
            sessionId: data?['sessionId'],
          );
          _remotePeerController.add(remotePeer);
          _createPeerConnection(remotePeer.id, isInitiator: true);
          break;
        case 'webrtc_offer':
          _handleRemoteOffer(data?['from'], data?['sdp']);
          break;
        case 'webrtc_answer':
          _handleRemoteAnswer(data?['from'], data?['sdp']);
          break;
        case 'webrtc_ice_candidate':
          _handleRemoteCandidate(data?['from'], data?['candidate']);
          break;
      }
    } catch (e) {
      debugPrint('[WebRTC] Error handling signal: $e');
    }
  }

  Future<void> _createPeerConnection(String targetPeerId, {required bool isInitiator}) async {
    final pc = await createPeerConnection(_iceServers);
    _peerConnections[targetPeerId] = pc;

    pc.onIceCandidate = (candidate) {
      _wsChannel?.sink.add(jsonEncode({
        'type': 'webrtc_ice_candidate',
        'data': {
          'targetPeerId': targetPeerId,
          'from': deviceId,
          'candidate': candidate.toMap(),
        }
      }));
    };

    if (isInitiator) {
      final dcInit = RTCDataChannelInit()..ordered = true;
      final dc = await pc.createDataChannel('hyperdrop_transfer', dcInit);
      _setupDataChannel(targetPeerId, dc);

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      _wsChannel?.sink.add(jsonEncode({
        'type': 'webrtc_offer',
        'data': {
          'targetPeerId': targetPeerId,
          'from': deviceId,
          'sdp': offer.toMap(),
        }
      }));
    } else {
      pc.onDataChannel = (dc) {
        _setupDataChannel(targetPeerId, dc);
      };
    }
  }

  void _setupDataChannel(String peerId, RTCDataChannel dc) {
    _dataChannels[peerId] = dc;
    dc.onMessage = (data) {
      if (data.isBinary) {
        _incomingDataController.add({
          'peerId': peerId,
          'bytes': data.binary,
        });
      }
    };
  }

  Future<void> _handleRemoteOffer(String? from, Map<String, dynamic>? sdpMap) async {
    if (from == null || sdpMap == null) return;
    await _createPeerConnection(from, isInitiator: false);
    final pc = _peerConnections[from];
    if (pc == null) return;

    final desc = RTCSessionDescription(sdpMap['sdp'], sdpMap['type']);
    await pc.setRemoteDescription(desc);

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    _wsChannel?.sink.add(jsonEncode({
      'type': 'webrtc_answer',
      'data': {
        'targetPeerId': from,
        'from': deviceId,
        'sdp': answer.toMap(),
      }
    }));
  }

  Future<void> _handleRemoteAnswer(String? from, Map<String, dynamic>? sdpMap) async {
    if (from == null || sdpMap == null) return;
    final pc = _peerConnections[from];
    if (pc == null) return;
    final desc = RTCSessionDescription(sdpMap['sdp'], sdpMap['type']);
    await pc.setRemoteDescription(desc);
  }

  Future<void> _handleRemoteCandidate(String? from, Map<String, dynamic>? candMap) async {
    if (from == null || candMap == null) return;
    final pc = _peerConnections[from];
    if (pc == null) return;
    final candidate = RTCIceCandidate(
      candMap['candidate'],
      candMap['sdpMid'],
      candMap['sdpMLineIndex'],
    );
    await pc.addCandidate(candidate);
  }

  void sendBinaryChunk(String peerId, Uint8List chunk) {
    final dc = _dataChannels[peerId];
    if (dc != null && dc.state == RTCDataChannelState.RTCDataChannelOpen) {
      dc.send(RTCDataChannelMessage.fromBinary(chunk));
    }
  }

  void joinRemoteSession(String shortCode) {
    _wsChannel?.sink.add(jsonEncode({
      'type': 'join_remote_session',
      'data': {
        'sessionIdOrCode': shortCode.toUpperCase(),
        'deviceId': deviceId,
        'deviceName': deviceName,
        'deviceType': deviceType,
      }
    }));
  }

  void dispose() {
    _wsChannel?.sink.close();
    _dataChannels.values.forEach((dc) => dc.close());
    _peerConnections.values.forEach((pc) => pc.close());
  }
}
