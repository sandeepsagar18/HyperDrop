import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../identity/domain/models/device_identity.dart';
import '../domain/models/device_model.dart';

class UdpDiscoveryEngine {
  static const int defaultDiscoveryPort = 35432;

  RawDatagramSocket? _socket;
  Timer? _beaconTimer;
  Timer? _cleanupTimer;
  Timer? _pollTimer;

  final DeviceIdentity identity;
  final StreamController<List<DeviceModel>> _peersController = StreamController<List<DeviceModel>>.broadcast();
  Stream<List<DeviceModel>> get peersStream => _peersController.stream;

  final Map<String, DeviceModel> _discoveredPeers = {};
  List<DeviceModel> get discoveredPeers => _discoveredPeers.values.toList();

  bool _isListening = false;
  bool get isListening => _isListening;

  UdpDiscoveryEngine({required this.identity});

  Future<void> startDiscovery() async {
    if (_isListening) return;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        defaultDiscoveryPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );

      _socket?.broadcastEnabled = true;
      _isListening = true;

      _socket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket?.receive();
          if (datagram != null) {
            _handleIncomingBeacon(datagram.data, datagram.address.address);
          }
        }
      });

      // Broadcast presence every 2 seconds to discover other laptops
      _beaconTimer = Timer.periodic(const Duration(seconds: 2), (_) => broadcastPresence());
      broadcastPresence();

      // Clean up stale peers every 4 seconds (inactive for >15s)
      _cleanupTimer = Timer.periodic(const Duration(seconds: 4), (_) => _cleanupStalePeers());

      // Poll Node server local peers API (port 3000) every 2 seconds if running
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollLocalNodeServerPeers());
      _pollLocalNodeServerPeers();

      debugPrint('[DISCOVERY] Active UDP & Node Discovery listening on port $defaultDiscoveryPort');
    } catch (e) {
      debugPrint('[DISCOVERY] Discovery init error: $e');
    }
  }

  Future<void> _pollLocalNodeServerPeers() async {
    try {
      final res = await http.get(Uri.parse('http://127.0.0.1:3000/api/peers')).timeout(const Duration(seconds: 1));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final peersList = data['peers'] as List<dynamic>? ?? [];
        bool changed = false;

        for (final p in peersList) {
          final ip = p['ip'] as String?;
          final id = p['id'] as String? ?? p['deviceId'] as String? ?? 'peer_${ip?.replaceAll('.', '_')}';
          if (ip == null || ip == '127.0.0.1' || id == identity.deviceId) continue;

          final name = p['name'] as String? ?? p['deviceName'] as String? ?? 'Mobile / Peer';
          final port = (p['httpPort'] as num?)?.toInt() ?? 3000;
          final typeStr = p['deviceType'] as String? ?? 'phone';

          final devType = DeviceType.values.firstWhere(
            (e) => e.name == typeStr,
            orElse: () => DeviceType.phone,
          );

          _discoveredPeers[id] = DeviceModel(
            deviceId: id,
            deviceName: name,
            deviceType: devType,
            ipAddress: ip,
            port: port,
            lastSeen: DateTime.now(),
          );
          changed = true;
        }

        if (changed) {
          _peersController.add(_discoveredPeers.values.toList());
        }
      }
    } catch (_) {}
  }

  void broadcastPresence() {
    if (_socket == null || !_isListening) return;

    try {
      final beaconData = jsonEncode({
        'type': 'HYPERDROP_BEACON',
        'protocolVersion': 1,
        'deviceId': identity.deviceId,
        'deviceName': identity.deviceName,
        'deviceType': identity.deviceType.name,
        'httpPort': identity.httpPort,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final bytes = utf8.encode(beaconData);
      _socket?.send(bytes, InternetAddress('255.255.255.255'), defaultDiscoveryPort);
    } catch (e) {
      debugPrint('[DISCOVERY] Error sending UDP beacon: $e');
    }
  }

  void _handleIncomingBeacon(Uint8List data, String senderIp) {
    try {
      final str = utf8.decode(data);
      final json = jsonDecode(str) as Map<String, dynamic>;

      if (json['type'] == 'HYPERDROP_BEACON' || json['type'] == 'hyperdrop_beacon') {
        final peerId = json['deviceId'] as String?;
        if (peerId == null || peerId == identity.deviceId) return; // Skip self

        final peerName = json['deviceName'] as String? ?? 'Nearby Device';
        final peerTypeStr = json['deviceType'] as String? ?? 'phone';
        final peerPort = (json['httpPort'] as num?)?.toInt() ?? 8080;

        final deviceType = DeviceType.values.firstWhere(
          (e) => e.name == peerTypeStr,
          orElse: () => DeviceType.phone,
        );

        ConnectionMode mode = ConnectionMode.lan;
        if (senderIp.startsWith('192.168.43.') || senderIp.startsWith('172.20.10.')) {
          mode = ConnectionMode.hotspot;
        }

        final peer = DeviceModel(
          deviceId: peerId,
          deviceName: peerName,
          deviceType: deviceType,
          ipAddress: senderIp,
          port: peerPort,
          connectionMode: mode,
          lastSeen: DateTime.now(),
        );

        _discoveredPeers[peerId] = peer;
        _peersController.add(_discoveredPeers.values.toList());
      }
    } catch (_) {}
  }

  void _cleanupStalePeers() {
    final now = DateTime.now();
    final expiredIds = <String>[];

    _discoveredPeers.forEach((id, peer) {
      if (now.difference(peer.lastSeen).inSeconds > 15) {
        expiredIds.add(id);
      }
    });

    if (expiredIds.isNotEmpty) {
      for (final id in expiredIds) {
        _discoveredPeers.remove(id);
      }
      _peersController.add(_discoveredPeers.values.toList());
    }
  }

  Future<void> forceScan() async {
    broadcastPresence();
    await _pollLocalNodeServerPeers();
    // Fast second pulse
    await Future.delayed(const Duration(milliseconds: 300));
    broadcastPresence();
    await _pollLocalNodeServerPeers();
  }

  void stop() {
    _beaconTimer?.cancel();
    _cleanupTimer?.cancel();
    _pollTimer?.cancel();
    _socket?.close();
    _socket = null;
    _isListening = false;
    _discoveredPeers.clear();
    _peersController.add([]);
  }

  void dispose() {
    stop();
    _peersController.close();
  }
}
