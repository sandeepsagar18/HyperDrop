class PeerDevice {
  final String id;
  final String name;
  final String type; // 'phone', 'laptop', 'tablet'
  final String ip;
  final int port;
  final bool isRemote;
  final String? sessionId;
  DateTime lastSeen;

  PeerDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.ip,
    this.port = 3000,
    this.isRemote = false,
    this.sessionId,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  String get url => isRemote ? '' : 'http://$ip:$port';

  String get networkType {
    if (isRemote) return 'Remote (WebRTC)';
    if (ip.startsWith('192.168.43.') || ip.startsWith('172.20.10.')) {
      return 'Zero-Network (Hotspot)';
    }
    return 'Same Wi-Fi Network';
  }

  factory PeerDevice.fromMap(Map<String, dynamic> map) {
    return PeerDevice(
      id: map['id'] ?? map['deviceId'] ?? '',
      name: map['name'] ?? map['deviceName'] ?? 'Unknown Device',
      type: map['type'] ?? map['deviceType'] ?? 'phone',
      ip: map['ip'] ?? map['address'] ?? '127.0.0.1',
      port: map['port'] ?? map['httpPort'] ?? 3000,
      isRemote: map['isRemote'] ?? false,
      sessionId: map['sessionId'],
      lastSeen: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'ip': ip,
      'port': port,
      'isRemote': isRemote,
      'sessionId': sessionId,
    };
  }
}
