enum TransferStatus {
  idle,
  connecting,
  transferring,
  paused,
  completed,
  failed,
  cancelled,
}

enum TransferDirection {
  outgoing,
  incoming,
}

class TransferModel {
  final String transferId;
  final String fileName;
  final String? filePath;
  final int fileSize;
  final int bytesTransferred;
  final double speedMBs;
  final double speedMbps;
  final int etaSeconds;
  final TransferStatus status;
  final TransferDirection direction;
  final String peerName;
  final String peerIp;
  final String? checksum;
  final String? errorMessage;
  final DateTime startTime;
  // Frozen when transfer ends — so the timer stops at actual duration
  final DateTime? endTime;

  TransferModel({
    required this.transferId,
    required this.fileName,
    this.filePath,
    required this.fileSize,
    this.bytesTransferred = 0,
    this.speedMBs = 0.0,
    this.speedMbps = 0.0,
    this.etaSeconds = 0,
    this.status = TransferStatus.idle,
    required this.direction,
    required this.peerName,
    required this.peerIp,
    this.checksum,
    this.errorMessage,
    this.endTime,
    DateTime? startTime,
  }) : startTime = startTime ?? DateTime.now();

  double get progress {
    if (fileSize <= 0) return 0.0;
    return (bytesTransferred / fileSize).clamp(0.0, 1.0);
  }

  int get percent => (progress * 100).toInt();

  /// Returns elapsed seconds; frozen once transfer ends
  int get elapsedSeconds {
    final ref = endTime ?? DateTime.now();
    return ref.difference(startTime).inSeconds.clamp(0, 99999);
  }

  bool get isFinished =>
      status == TransferStatus.completed ||
      status == TransferStatus.failed ||
      status == TransferStatus.cancelled;

  TransferModel copyWith({
    String? filePath,
    int? bytesTransferred,
    double? speedMBs,
    double? speedMbps,
    int? etaSeconds,
    TransferStatus? status,
    String? checksum,
    String? errorMessage,
    DateTime? endTime,
  }) {
    return TransferModel(
      transferId: transferId,
      fileName: fileName,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      speedMBs: speedMBs ?? this.speedMBs,
      speedMbps: speedMbps ?? this.speedMbps,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      status: status ?? this.status,
      direction: direction,
      peerName: peerName,
      peerIp: peerIp,
      checksum: checksum ?? this.checksum,
      errorMessage: errorMessage ?? this.errorMessage,
      startTime: startTime,
      endTime: endTime ?? this.endTime,
    );
  }
}

