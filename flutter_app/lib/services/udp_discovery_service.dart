import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/peer_device.dart';

class UdpDiscoveryService {
  static const int discoveryPort = 35432;
  RawDatagramSocket? _socket;
  Timer? _beaconTimer;
  Timer? _cleanupTimer;

  final String myDeviceId;
  final String myDeviceName;
  final String myDeviceType;
  final int myHttpPort;

  final StreamController<List<PeerDevice>> _peersController = StreamController<List<PeerDevice>>.broadcast();
  Stream<List<PeerDevice>> get peersStream => _peersController.stream;

  final Map<String, PeerDevice> _peers = {};
  List<PeerDevice> get peers => _peers.values.toList();

  UdpDiscoveryService({
    required this.myDeviceId,
    required this.myDeviceName,
    this.myDeviceType = 'phone',
    this.myHttpPort = 3000,
  });

  Future<void> start() async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort, reuseAddress: true);
      _socket?.broadcastEnabled = true;

      _socket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket?.receive();
          if (datagram != null) {
            _handlePacket(datagram.data, datagram.address.address);
          }
        }
      });

      // Send beacon every 2 seconds
      _beaconTimer = Timer.periodic(const Duration(seconds: 2), (_) => _sendBeacon());
      _sendBeacon();

      // Clean up inactive peers every 5 seconds
      _cleanupTimer = Timer.periodic(const Duration(seconds: 5), (_) => _cleanupPeers());

      debugPrint('[UDP] Peer discovery active on port $discoveryPort');
    } catch (e) {
      debugPrint('[UDP] Failed to bind discovery socket: $e');
    }
  }

  void _sendBeacon() {
    if (_socket == null) return;
    try {
      final message = jsonEncode({
        'type': 'hyperdrop_beacon',
        'version': 1,
        'deviceId': myDeviceId,
        'deviceName': myDeviceName,
        'deviceType': myDeviceType,
        'httpPort': myHttpPort,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final bytes = utf8.encode(message);
      _socket?.send(bytes, InternetAddress('255.255.255.255'), discoveryPort);
    } catch (e) {
      debugPrint('[UDP] Error sending beacon: $e');
    }
  }

  void _handlePacket(Uint8List data, String senderIp) {
    try {
      final str = utf8.decode(data);
      final json = jsonDecode(str) as Map<String, dynamic>;

      if (json['type'] == 'hyperdrop_beacon') {
        final id = json['deviceId'] as String?;
        if (id == null || id == myDeviceId) return; // Ignore self

        final peer = PeerDevice(
          id: id,
          name: json['deviceName'] ?? 'Nearby Device',
          type: json['deviceType'] ?? 'phone',
          ip: senderIp,
          port: json['httpPort'] ?? 3000,
          isRemote: false,
        );

        _peers[id] = peer;
        _peersController.add(_peers.values.toList());
      }
    } catch (_) {}
  }

  void _cleanupPeers() {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    _peers.forEach((key, peer) {
      if (now.difference(peer.lastSeen).inSeconds > 10) {
        expiredKeys.add(key);
      }
    });

    if (expiredKeys.isNotEmpty) {
      for (final key in expiredKeys) {
        _peers.remove(key);
      }
      _peersController.add(_peers.values.toList());
    }
  }

  void stop() {
    _beaconTimer?.cancel();
    _cleanupTimer?.cancel();
    _socket?.close();
    _socket = null;
  }
}
