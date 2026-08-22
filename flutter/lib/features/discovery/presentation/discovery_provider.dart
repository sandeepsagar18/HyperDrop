import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../identity/presentation/identity_provider.dart';
import '../data/udp_discovery_engine.dart';
import '../domain/models/device_model.dart';

final udpDiscoveryEngineProvider = Provider<UdpDiscoveryEngine>((ref) {
  final identity = ref.watch(currentIdentityProvider);
  final engine = UdpDiscoveryEngine(identity: identity);
  
  // Auto-start discovery engine
  engine.startDiscovery();
  
  ref.onDispose(() {
    engine.dispose();
  });
  
  return engine;
});

final discoveredPeersStreamProvider = StreamProvider<List<DeviceModel>>((ref) {
  final engine = ref.watch(udpDiscoveryEngineProvider);
  return engine.peersStream;
});

/// Resolves the device's real LAN IPv4 address for use in the QR code URL.
/// Prioritizes real Wi-Fi adapter IP over Windows virtual hotspot adapters (192.168.137.x).
final localIpProvider = FutureProvider<String>((ref) async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );

    String? wifiIp;
    String? fallbackIp;

    for (final iface in interfaces) {
      final name = iface.name.toLowerCase();
      // Skip loopback and virtual adapter names
      if (name.contains('loopback') || name == 'lo' || name.contains('vethernet') || name.contains('virtual')) {
        continue;
      }

      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;

        // Skip Windows Mobile Hotspot virtual subnet (192.168.137.x) unless no other choice
        if (ip.startsWith('192.168.137.')) {
          fallbackIp ??= ip;
          continue;
        }

        // Check if this is the active Wi-Fi / Ethernet interface
        if (name.contains('wi-fi') || name.contains('wlan') || name.contains('ethernet')) {
          return ip;
        }

        if (ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.')) {
          wifiIp ??= ip;
        }
      }
    }

    if (wifiIp != null) return wifiIp;
    if (fallbackIp != null) return fallbackIp;
  } catch (_) {}
  return '192.168.29.137';
});

