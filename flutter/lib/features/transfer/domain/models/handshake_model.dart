enum HandshakeStatus {
  idle,
  pendingAuthorization,
  accepted,
  rejected,
  timedOut,
}

class HandshakeRequest {
  final String requestId;
  final String senderDeviceId;
  final String senderDeviceName;
  final String senderDeviceType;
  final String senderIp;
  final int senderPort;
  final String sessionToken;
  final int totalFiles;
  final int totalSizeBytes;
  final DateTime timestamp;

  HandshakeRequest({
    required this.requestId,
    required this.senderDeviceId,
    required this.senderDeviceName,
    required this.senderDeviceType,
    required this.senderIp,
    required this.senderPort,
    required this.sessionToken,
    this.totalFiles = 1,
    required this.totalSizeBytes,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'requestId': requestId,
      'senderDeviceId': senderDeviceId,
      'senderDeviceName': senderDeviceName,
      'senderDeviceType': senderDeviceType,
      'senderIp': senderIp,
      'senderPort': senderPort,
      'sessionToken': sessionToken,
      'totalFiles': totalFiles,
      'totalSizeBytes': totalSizeBytes,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory HandshakeRequest.fromJson(Map<String, dynamic> json, String remoteIp) {
    return HandshakeRequest(
      requestId: json['requestId'] as String? ?? 'req_${DateTime.now().millisecondsSinceEpoch}',
      senderDeviceId: json['senderDeviceId'] as String? ?? 'unknown_device',
      senderDeviceName: json['senderDeviceName'] as String? ?? 'Nearby Device',
      senderDeviceType: json['senderDeviceType'] as String? ?? 'phone',
      senderIp: remoteIp,
      senderPort: (json['senderPort'] as num?)?.toInt() ?? 8080,
      sessionToken: json['sessionToken'] as String? ?? '',
      totalFiles: (json['totalFiles'] as num?)?.toInt() ?? 1,
      totalSizeBytes: (json['totalSizeBytes'] as num?)?.toInt() ?? 0,
      timestamp: DateTime.now(),
    );
  }
}

class HandshakeResponse {
  final bool accepted;
  final String receiverDeviceId;
  final String receiverDeviceName;
  final String? rejectionReason;
  final String? authToken;

  HandshakeResponse({
    required this.accepted,
    required this.receiverDeviceId,
    required this.receiverDeviceName,
    this.rejectionReason,
    this.authToken,
  });

  Map<String, dynamic> toJson() {
    return {
      'accepted': accepted,
      'receiverDeviceId': receiverDeviceId,
      'receiverDeviceName': receiverDeviceName,
      'rejectionReason': rejectionReason,
      'authToken': authToken,
    };
  }

  factory HandshakeResponse.fromJson(Map<String, dynamic> json) {
    return HandshakeResponse(
      accepted: json['accepted'] as bool? ?? false,
      receiverDeviceId: json['receiverDeviceId'] as String? ?? '',
      receiverDeviceName: json['receiverDeviceName'] as String? ?? '',
      rejectionReason: json['rejectionReason'] as String?,
      authToken: json['authToken'] as String?,
    );
  }
}
