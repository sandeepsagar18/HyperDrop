enum DeviceType { phone, laptop, tablet, desktop }
enum ConnectionMode { lan, hotspot, remoteWebRTC, disconnected }

class DeviceModel {
  final String deviceId;
  final String deviceName;
  final DeviceType deviceType;
  final String ipAddress;
  final int port;
  final ConnectionMode connectionMode;
  final bool isSelf;
  final DateTime lastSeen;

  DeviceModel({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.ipAddress,
    required this.port,
    this.connectionMode = ConnectionMode.lan,
    this.isSelf = false,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  String get connectionLabel {
    switch (connectionMode) {
      case ConnectionMode.lan:
        return 'Direct LAN (Same Wi-Fi)';
      case ConnectionMode.hotspot:
        return 'Zero-Network Hotspot';
      case ConnectionMode.remoteWebRTC:
        return 'Remote P2P (WebRTC)';
      case ConnectionMode.disconnected:
        return 'Disconnected';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'deviceType': deviceType.name,
      'ipAddress': ipAddress,
      'port': port,
      'protocol': 'HYPERDROP_LAN_V1',
    };
  }

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      deviceId: json['deviceId'] as String? ?? 'unknown_id',
      deviceName: json['deviceName'] as String? ?? 'Nearby Device',
      deviceType: DeviceType.values.firstWhere(
        (e) => e.name == json['deviceType'],
        orElse: () => DeviceType.phone,
      ),
      ipAddress: json['ipAddress'] as String? ?? '127.0.0.1',
      port: (json['port'] as num?)?.toInt() ?? 8080,
      connectionMode: ConnectionMode.lan,
    );
  }
}
