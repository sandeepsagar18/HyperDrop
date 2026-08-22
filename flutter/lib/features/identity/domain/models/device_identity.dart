import 'dart:io';
import 'package:hyperdrop_flutter/features/discovery/domain/models/device_model.dart';

class DeviceIdentity {
  final String deviceId;
  final String deviceName;
  final DeviceType deviceType;
  final String osVersion;
  final int httpPort;
  final int discoveryPort;
  final String token;

  DeviceIdentity({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.osVersion,
    this.httpPort = 8080,
    this.discoveryPort = 35432,
    required this.token,
  });

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'deviceType': deviceType.name,
      'osVersion': osVersion,
      'httpPort': httpPort,
      'discoveryPort': discoveryPort,
      'token': token,
      'protocolVersion': 1,
    };
  }

  factory DeviceIdentity.createDefault({
    required String deviceId,
    required String deviceName,
    required String token,
  }) {
    DeviceType type = DeviceType.phone;
    String os = Platform.operatingSystem;

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      type = DeviceType.laptop;
    }

    return DeviceIdentity(
      deviceId: deviceId,
      deviceName: deviceName,
      deviceType: type,
      osVersion: '$os ${Platform.operatingSystemVersion}',
      token: token,
    );
  }

  DeviceIdentity copyWith({
    String? deviceName,
    int? httpPort,
    String? token,
  }) {
    return DeviceIdentity(
      deviceId: deviceId,
      deviceName: deviceName ?? this.deviceName,
      deviceType: deviceType,
      osVersion: osVersion,
      httpPort: httpPort ?? this.httpPort,
      discoveryPort: discoveryPort,
      token: token ?? this.token,
    );
  }
}
